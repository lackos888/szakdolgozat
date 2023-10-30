local os = require("os");
local packageManager = require("apt_packages");
local general = require("general");
local linux = require("linux");
local inspect = require("inspect");

local module = {};

function module.is_iptables_installed()
    return packageManager.is_package_is_installed("iptables");
end

function module.install_iptables()
    if module.is_iptables_installed() then
        return -1
    end

    return packageManager.install_package("iptables");
end

function module.get_current_ssh_ports()
    local retLines, retCode = linux.exec_command_with_proc_ret_code("sshd -T", true);

    if retCode ~= 0 then
        return false;
    end

    local linesIterator = retLines:gmatch("[^\r\n]+");
    local ports = {};

    for line in linesIterator do
        local str = "port ";

        local portStart = line:find(str, 1, true);
        
        if portStart then
            local portNumber = tonumber(line:sub(portStart + #str));

            table.insert(ports, portNumber);
        end
    end

    return ports;
end

local iptablesAliases = {
    ["t"] = "table",
    ["A"] = "append",
    ["C"] = "check",
    ["D"] = "delete",
    ["I"] = "insert",
    ["R"] = "replace",
    ["L"] = "list",
    ["S"] = "list-rules",
    ["F"] = "flush",
    ["Z"] = "zero",
    ["N"] = "new-chain",
    ["X"] = "delete-chain",
    ["P"] = "policy",
    ["E"] = "rename-chain",
    ["4"] = "ipv4",
    ["6"] = "ipv6",
    ["p"] = "protocol",
    ["s"] = "source",
    ["d"] = "destination",
    ["m"] = "match",
    ["j"] = "jump",
    ["g"] = "goto",
    ["i"] = "in-interface",
    ["o"] = "out-interface",
    ["f"] = "fragment",
    ["c"] = "set-counters"
};

function module.parse_current_rules()
    local retLines, retCode = linux.exec_command_with_proc_ret_code("iptables-save", true);

    if retCode ~= 0 then
        return false;
    end

    local parsedStuff = {};
    local linesIterator = retLines:gmatch("[^\r\n]+");

    for line in linesIterator do
        local firstChar = line:sub(1, 1);

        if firstChar == "" or firstChar == "*" or firstChar == ":" or firstChar == "#" or firstChar ~= "-" then
            goto continue;
        end

        local currentLineParsedStuff = {};

        local splittedStr = general.strSplit(line, " ");

        local lastArgType = "";
        local lastArgData = "";
        local lastArgDoubleArg = nil;

        for _, arg in pairs(splittedStr) do
            if arg:sub(1, 1) == "-" then
                lastArgType = arg:sub(2);
                lastArgDoubleArg = nil;

                if lastArgType:sub(1, 1) == "-" then
                    lastArgDoubleArg = true;

                    lastArgType = lastArgType:sub(2);
                end
            else
                lastArgData = arg;

                currentLineParsedStuff[lastArgType] = {data = arg, doubleTypeArg = lastArgDoubleArg};
            end
        end

        local interface = "all";
        local chain = false;
        local currentTable = "filter";

        for index, val in pairs(currentLineParsedStuff) do
            for uppercaseIndex, lowerCaseVerboseIndex in pairs(iptablesAliases) do
                if lowerCaseVerboseIndex == index then
                    currentLineParsedStuff[uppercaseIndex] = currentLineParsedStuff[lowerCaseVerboseIndex];
                    currentLineParsedStuff[uppercaseIndex].doubleTypeArg = nil;
                    currentLineParsedStuff[lowerCaseVerboseIndex] = nil;

                    break;
                end
            end
        end

        if currentLineParsedStuff["i"] then
            interface = currentLineParsedStuff["i"].data;

            currentLineParsedStuff["i"] = nil;
        end

        if currentLineParsedStuff["A"] then
            chain = currentLineParsedStuff["A"].data;

            currentLineParsedStuff["A"] = nil;
        end

        if currentLineParsedStuff["m"] then
            local mData = currentLineParsedStuff["m"].data;

            if mData == "tcp" or mData == "udp" then
                currentLineParsedStuff["p"] = {data = mData};
            end

            currentLineParsedStuff["m"] = nil;
        end

        if currentLineParsedStuff["t"] then
            currentTable = currentLineParsedStuff["t"].data;

            currentLineParsedStuff["t"] = nil;
        end

        if chain and interface and currentTable then
            if not parsedStuff[currentTable] then
                parsedStuff[currentTable] = {};
            end

            if not parsedStuff[currentTable][chain] then
                parsedStuff[currentTable][chain] = {};
            end

            if not parsedStuff[currentTable][chain][interface] then
                parsedStuff[currentTable][chain][interface] = {};
            end

            table.insert(parsedStuff[currentTable][chain][interface], currentLineParsedStuff);
        end

        ::continue::
    end

    return parsedStuff;
end

function module.get_open_ports(interface)
    interface = interface or "all";
    local ports = {};
    local parsedStuff = module.currentIPTablesRules;

    if not parsedStuff["filter"] then
        parsedStuff["filter"] = {};
    end

    if not parsedStuff["filter"]["INPUT"] then
        ports = "all";
    elseif parsedStuff["filter"]["INPUT"] and parsedStuff["filter"]["INPUT"][interface] then
        local tbl = parsedStuff["filter"]["INPUT"][interface];

        for t, v in pairs(tbl) do
            if v.j and v.j.data == "ACCEPT" then
                local sourceIP = (v.s and v.s.data) or nil;

                if v.dport then
                    table.insert(ports, {protocol = (v.p and v.p.data) or (v.m and v.m.data) or "all", dport = v.dport.data, sourceIP = sourceIP});
                else
                    table.insert(ports, {protocol = (v.p and v.p.data) or (v.m and v.m.data) or "all", dport = "all", sourceIP = sourceIP});
                end
            end
        end
    end

    return ports;
end

function module.close_port(interface, protocol, dport, fromIP)
    interface = interface or "all";
    local parsedStuff = module.currentIPTablesRules;

    if not parsedStuff["filter"] then
        parsedStuff["filter"] = {};
    end

    if not parsedStuff["filter"]["INPUT"] then
        parsedStuff["filter"]["INPUT"] = {};
    end

    if not parsedStuff["filter"]["INPUT"][interface] then
        parsedStuff["filter"]["INPUT"][interface] = {};
    end

    if parsedStuff["filter"]["INPUT"] and parsedStuff["filter"]["INPUT"][interface] then
        local tbl = parsedStuff["filter"]["INPUT"][interface];
        local success = false;

        local insertNewStuffAtPlace = function(t)
            table.insert(tbl, t, {
                p = protocol and {
                    data = protocol
                } or nil, dport = dport and {
                    data = tostring(dport),
                    doubleTypeArg = true
                } or nil, sourceIP = fromIP and {
                    data = fromIP
                } or nil,
                j = {data = "DROP"}
            });
            success = true;
        end

        for t, v in pairs(tbl) do
            if v.j and v.j.data == "DROP" and ((v.p and v.p.data == protocol) or (v.m and v.m.data == protocol)) then
                insertNewStuffAtPlace(t);

                break;
            end
        end

        if not success then
            for t, v in pairs(tbl) do
                if v.j and v.j.data == "DROP" then
                    insertNewStuffAtPlace(t);
    
                    break;
                end
            end
        end

        if not success then
            insertNewStuffAtPlace(#tbl + 1);
        end

        return success;
    end
end

function module.open_port(interface, protocol, dport, fromIP)
    interface = interface or "all";
    local parsedStuff = module.currentIPTablesRules;

    if not parsedStuff["filter"] then
        parsedStuff["filter"] = {};
    end

    if not parsedStuff["filter"]["INPUT"] then
        parsedStuff["filter"]["INPUT"] = {};
    end

    if not parsedStuff["filter"]["INPUT"][interface] then
        parsedStuff["filter"]["INPUT"][interface] = {};
    end

    if parsedStuff["filter"]["INPUT"] and parsedStuff["filter"]["INPUT"][interface] then
        local tbl = parsedStuff["filter"]["INPUT"][interface];
        local success = false;
        local newTbl = {
            p = protocol and {
                data = protocol
            } or nil, dport = dport and {
                data = tostring(dport),
                doubleTypeArg = true
            } or nil, source = fromIP and {
                data = fromIP,
                doubleTypeArg = true
            } or nil,
            j = {data = "ACCEPT"}
        };

        local insertNewStuffAtPlace = function(t)
            table.insert(tbl, t, newTbl);
            success = true;
        end

        for t, v in pairs(tbl) do
            print("v: "..tostring(inspect(v)).." newTbl: "..tostring(inspect(newTbl)));

            if general.deep_compare(v, newTbl) then
                return true;
            end
        end

        for t, v in pairs(tbl) do
            if v.j and v.j.data == "DROP" and ((v.p and v.p.data == protocol) or (v.m and v.m.data == protocol)) then
                insertNewStuffAtPlace(t);

                break;
            end
        end

        if not success then
            for t, v in pairs(tbl) do
                if v.j and v.j.data == "DROP" then
                    insertNewStuffAtPlace(t);
    
                    break;
                end
            end
        end

        if not success then
            insertNewStuffAtPlace(#tbl + 1);
        end

        return success;
    end

    return true;
end

function module.allow_outgoing_new_connection(interface, protocol, dip, dport)
    interface = interface or "all";
    local parsedStuff = module.currentIPTablesRules;

    if not parsedStuff["filter"] then
        parsedStuff["filter"] = {};
    end

    if not parsedStuff["filter"]["OUTPUT"] then
        parsedStuff["filter"]["OUTPUT"] = {};
    end

    if not parsedStuff["filter"]["OUTPUT"][interface] then
        parsedStuff["filter"]["OUTPUT"][interface] = {};
    end

    if parsedStuff["filter"]["OUTPUT"] and parsedStuff["filter"]["OUTPUT"][interface] then
        local tbl = parsedStuff["filter"]["OUTPUT"][interface];
        local success = false;

        local insertNewStuffAtPlace = function(t)
            table.insert(tbl, t, {
                p = protocol and {
                    data = protocol
                } or nil, dport = dport and {
                    data = tostring(dport),
                    doubleTypeArg = true
                } or nil, destination = dip and {
                    data = dip,
                    doubleTypeArg = true
                } or nil,
                j = {data = "ACCEPT"}
            });
            success = true;
        end

        for t, v in pairs(tbl) do
            if v.j and v.j.data == "DROP" and ((v.p and v.p.data == protocol) or (v.m and v.m.data == protocol)) then
                insertNewStuffAtPlace(t);

                break;
            end
        end

        if not success then
            for t, v in pairs(tbl) do
                if v.j and v.j.data == "DROP" then
                    insertNewStuffAtPlace(t);
    
                    break;
                end
            end
        end

        if not success then
            insertNewStuffAtPlace(#tbl + 1);
        end

        return success;
    end

    return true;
end

function module.check_if_inbound_packets_are_being_filtered_already(interface, protocol)
    local rules = module.currentIPTablesRules;

    interface = interface or "all";
    protocol = protocol or "all";

    if not rules["filter"] then
        return false;
    end

    if not rules["filter"]["INPUT"] then
        return false;
    end

    if not rules["filter"]["INPUT"][interface] then
        return false;
    end

    local tbl = rules["filter"]["INPUT"][interface];
    local protocolsBlocked = {};
    local protocolsToBlock = {protocol};

    if protocol == "all" then
        protocolsToBlock = {"tcp", "udp"};
    end

    for t, v in pairs(tbl) do
        local failedCheck = false;

        for dataName, _ in pairs(v) do
            if dataName ~= "j" and dataName ~= "p" then
                failedCheck = true;
                break;
            end
        end

        if not failedCheck and v.j and v.j.data == "DROP" then
            if not v.p then
                protocolsBlocked = "all";
            elseif protocolsBlocked and type(protocolsBlocked) == "table" then
                table.insert(protocolsBlocked, v.p.data);
            end
        end
    end

    if protocol == "all" and protocolsBlocked == "all" then
        return true;
    end

    return general.deep_compare(protocolsToBlock, protocolsBlocked);
end

function module.tog_only_allow_accepted_packets_inbound(toggle, interface, protocol)
    local rules = module.currentIPTablesRules;

    interface = interface or "all";
    protocol = protocol or "all";

    if not rules["filter"] then
        rules["filter"] = {};
    end

    if toggle then
        if not rules["filter"]["INPUT"] then
            rules["filter"]["INPUT"] = {};
        end

        if not rules["filter"]["INPUT"][interface] then
            rules["filter"]["INPUT"][interface] = {};
        end

        local tbl = rules["filter"]["INPUT"][interface];
        local protocolsBlocked = {};

        for t, v in pairs(tbl) do
            local failedCheck = false;

            for dataName, _ in pairs(v) do
                if dataName ~= "j" and dataName ~= "p" then
                    failedCheck = true;
                    break;
                end
            end

            if not failedCheck and v.j and v.j.data == "DROP" then
                if not v.p then
                    protocolsBlocked = "all";
                elseif protocolsBlocked and type(protocolsBlocked) == "table" then
                    table.insert(protocolsBlocked, v.p.data);
                end
            end
        end

        local protocolsToBlock = {protocol};

        if protocol == "all" then
            protocolsToBlock = {"tcp", "udp"};
        end

        if protocolsBlocked == "all" then
            return true;
        end

        for _, v in pairs(protocolsToBlock) do
            if not protocolsBlocked[v] then
                table.insert(tbl, {
                    p = {data = v},
                    j = {data = "DROP"}
                });
            end
        end

        return true;
    end

    if not rules["filter"]["INPUT"] or not rules["filter"]["INPUT"][interface] then
        return true;
    end

    local tbl = rules["filter"]["INPUT"][interface];
    local protocolsBlocked = {};

    for t, v in pairs(tbl) do
        if v.j and v.j.data == "DROP" then
            if not v.p then
                table.insert(protocolsBlocked, {type = "all", t = t});
            elseif protocolsBlocked and type(protocolsBlocked) == "table" then
                table.insert(protocolsBlocked, {type = v.p.data, t = t});
            end
        end
    end

    for t, v in pairs(protocolsBlocked) do
        if v.type == protocol or protocol == "all" then
            local idx = v.t;
            table.remove(tbl, idx);

            for t2, v2 in pairs(protocolsBlocked) do
                if v2.t >= idx then
                    v2.t = v2.t - 1;
                end
            end
        end
    end

    return true;
end

function module.check_if_outbound_packets_are_being_filtered_already(interface, protocol)
    local rules = module.currentIPTablesRules;

    interface = interface or "all";
    protocol = protocol or "all";

    if not rules["filter"] then
        return false;
    end

    if not rules["filter"]["OUTPUT"] then
        return false;
    end

    if not rules["filter"]["OUTPUT"][interface] then
        return false;
    end

    local tbl = rules["filter"]["OUTPUT"][interface];
    local protocolsBlocked = {};
    local protocolsToBlock = {protocol};

    if protocol == "all" then
        protocolsToBlock = {"tcp", "udp"};
    end

    for t, v in pairs(tbl) do
        local failedCheck = false;

        for dataName, dataTbl in pairs(v) do
            if dataName ~= "j" and dataName ~= "p" and (dataName ~= "m" or dataTbl.data ~= "state") and (dataName ~= "state" or dataTbl.data ~= "NEW") then
                failedCheck = true;
                break;
            end
        end

        if not failedCheck and v.j and v.j.data == "DROP" then
            if not v.p then
                protocolsBlocked = "all";
            elseif protocolsBlocked and type(protocolsBlocked) == "table" then
                table.insert(protocolsBlocked, v.p.data);
            end
        end
    end

    if protocol == "all" and protocolsBlocked == "all" then
        return true;
    end

    return general.deep_compare(protocolsToBlock, protocolsBlocked);
end

function module.tog_only_allow_accepted_packets_outbound(toggle, interface, protocol)
    local rules = module.currentIPTablesRules;

    interface = interface or "all";
    protocol = protocol or "all";

    if not rules["filter"] then
        rules["filter"] = {};
    end

    if toggle then
        if not rules["filter"]["OUTPUT"] then
            rules["filter"]["OUTPUT"] = {};
        end

        if not rules["filter"]["OUTPUT"][interface] then
            rules["filter"]["OUTPUT"][interface] = {};
        end

        local tbl = rules["filter"]["OUTPUT"][interface];
        local protocolsBlocked = {};

        for t, v in pairs(tbl) do
            local failedCheck = false;

            for dataName, dataTbl in pairs(v) do
                if dataName ~= "j" and dataName ~= "p" and (dataName ~= "m" or dataTbl.data ~= "state") and (dataName ~= "state" or dataTbl.data ~= "NEW") then
                    failedCheck = true;
                    break;
                end
            end

            if not failedCheck and v.j and v.j.data == "DROP" then
                if not v.p then
                    protocolsBlocked = "all";
                elseif protocolsBlocked and type(protocolsBlocked) == "table" then
                    table.insert(protocolsBlocked, v.p.data);
                end
            end
        end

        local protocolsToBlock = {protocol};

        if protocol == "all" then
            protocolsToBlock = {"tcp", "udp"};
        end

        if protocolsBlocked == "all" then
            return true;
        end

        for _, v in pairs(protocolsToBlock) do
            if not protocolsBlocked[v] then
                table.insert(tbl, {
                    p = {data = v},
                    m = {data = "state"},
                    state = {data = "NEW", doubleTypeArg = true},
                    j = {data = "DROP"}
                });
            end
        end

        return true;
    end

    if not rules["filter"]["OUTPUT"] or not rules["filter"]["OUTPUT"][interface] then
        return true;
    end

    local tbl = rules["filter"]["OUTPUT"][interface];
    local protocolsBlocked = {};

    for t, v in pairs(tbl) do
        if v.j and v.j.data == "DROP" then
            if not v.p then
                table.insert(protocolsBlocked, {type = "all", t = t});
            elseif protocolsBlocked and type(protocolsBlocked) == "table" then
                table.insert(protocolsBlocked, {type = v.p.data, t = t});
            end
        end
    end

    for t, v in pairs(protocolsBlocked) do
        if v.type == protocol or protocol == "all" then
            local idx = v.t;
            table.remove(tbl, idx);

            for t2, v2 in pairs(protocolsBlocked) do
                if v2.t >= idx then
                    v2.t = v2.t - 1;
                end
            end
        end
    end

    return true;
end

function module.init_nat_for_openvpn(mainInterface, tunnelInterface, openvpnSubnet)
    local rules = module.currentIPTablesRules;

    openvpnSubnet = tostring(openvpnSubnet).."/16";

    if not rules["filter"] then
        rules["filter"] = {};
    end

    if not rules["filter"]["INPUT"] then
        rules["filter"]["INPUT"] = {};
    end

    if not rules["filter"]["FORWARD"] then
        rules["filter"]["FORWARD"] = {};
    end

    if not rules["filter"]["FORWARD"][mainInterface] then
        rules["filter"]["FORWARD"][mainInterface] = {};
    end

    if not rules["filter"]["FORWARD"]["all"] then
        rules["filter"]["FORWARD"]["all"] = {};
    end

    if not rules["nat"] then
        rules["nat"] = {};
    end

    if not rules["nat"]["POSTROUTING"] then
        rules["nat"]["POSTROUTING"] = {};
    end

    if not rules["nat"]["POSTROUTING"]["all"] then
        rules["nat"]["POSTROUTING"]["all"] = {};
    end

    
    local forwardTblInterface = rules["filter"]["FORWARD"][mainInterface];
    local forwardTblAll = rules["filter"]["FORWARD"]["all"];
    local forwardDropFound = false;

    for t, v in pairs(forwardTblAll) do
        if v.j and v.j.data == "DROP" then
            forwardDropFound = t;
            break;
        end
    end

    local rule1Found = false;

    for t, v in pairs(forwardTblInterface) do
        if v.o and v.o.data == tunnelInterface and v.m and v.m.data == "state" and v.state and v.state.data == "NEW,ESTABLISHED,RELATED" and v.j and v.j.data == "ACCEPT" then
            rule1Found = true;
            break;
        end
    end

    if not rule1Found then
        local tbl = {
            o = {data = tunnelInterface},
            m = {data = "state"},
            state = {data = "NEW,ESTABLISHED,RELATED", doubleTypeArg = true},
            j = {data = "ACCEPT"}
        };

        table.insert(forwardTblInterface, tbl);
    end

    
    local rule2Found = false;

    for t, v in pairs(forwardTblAll) do
        if v.s and v.s.data == openvpnSubnet and v.o and v.o.data == mainInterface and v.j and v.j.data == "ACCEPT" then
            rule2Found = true;
            break;
        end
    end

    if not rule2Found then
        local tbl = {
            s = {data = openvpnSubnet},
            o = {data = mainInterface},
            j = {data = "ACCEPT"}
        };

        if not forwardDropFound then
            table.insert(forwardTblAll, tbl);
        else
            table.insert(forwardTblAll, forwardDropFound, tbl);
        end
    end

    local rule3Found = false;
    local natTableAll = rules["nat"]["POSTROUTING"]["all"];

    for t, v in pairs(natTableAll) do
        if v.s and v.s.data == openvpnSubnet and v.o and v.o.data == mainInterface and v.j and v.j.data == "MASQUERADE" then
            rule3Found = true;
            break;
        end
    end

    if not rule3Found then
        table.insert(natTableAll, {
            s = {data = openvpnSubnet},
            o = {data = mainInterface},
            j = {data = "MASQUERADE"}
        });
    end

    if not forwardDropFound then
        table.insert(forwardTblAll, {
            j = {data = "DROP"}
        });
    end

    return true;
end

function module.iptables_to_string()
    local rules = module.currentIPTablesRules;
    local str = "";

    for tableName, chainDatas in pairs(rules) do
        for chain, interfaces in pairs(chainDatas) do
            local interfaceOrder = {};
            for interface, _ in pairs(interfaces) do
                if interface ~= "all" then
                    table.insert(interfaceOrder, interface);
                end
            end
            table.insert(interfaceOrder, "all");

            for _, interface in pairs(interfaceOrder) do
                local interfaceDatas = interfaces[interface];

                table.sort(interfaceDatas, function(a, b)
                    if a.j and b.j then
                        return a.j.data < b.j.data
                    end

                    return false;
                end); --this ensures that ACCEPT is first, then DROP then MASQUERADE, so there won't be bad rule orders

                for idx, v in pairs(interfaceDatas) do
                    local dataFormatted = "";
                    local idx2 = 1;
                    local jData = "";

                    if tableName ~= "filter" then
                        dataFormatted = "-t "..tostring(tableName).." ";
                    end

                    local spaceStuff = false;

                    for dataName, dataTbl in pairs(v) do
                        if dataName == "j" then
                            jData = dataTbl;

                            goto continueIptables;
                        end

                        spaceStuff = true;

                        if idx2 ~= 1 then
                            dataFormatted = dataFormatted.." ";
                        end

                        dataFormatted = dataFormatted.."-"..tostring(dataTbl.doubleTypeArg and "-" or "")..tostring(dataName).." "..tostring(dataTbl.data);

                        idx2 = idx2 + 1;

                        ::continueIptables::
                    end

                    dataFormatted = dataFormatted..""..tostring(spaceStuff and " " or "").."-j "..tostring(jData.data);

                    str = str.."-A "..chain..""..tostring(interface ~= "all" and (" -i "..tostring(interface)) or "").." "..tostring(dataFormatted)..general.lineEnding;
                end
            end
        end
    end

    return str;
end

function module.init_module()
    local parseRulesRet = module.parse_current_rules();

    if not parseRulesRet then
        print("[iptables] failed to parse current rules from iptables-save");

        return false;
    end

    module.currentIPTablesRules = parseRulesRet;

    print("open ports: "..tostring(inspect(module.get_open_ports())));

    for t, v in pairs(module.get_current_ssh_ports()) do
        module.open_port(nil, "tcp", v);
    end

    print("port opening ret: "..tostring(module.open_port(nil, "tcp", 443, nil)));
    print("port closing ret: "..tostring(module.close_port(nil, nil, 6666, nil)));
    print("tog: "..tostring(module.tog_only_allow_accepted_packets_inbound(true, nil, "tcp")));
    print("tog #2: "..tostring(module.tog_only_allow_accepted_packets_inbound(true, nil, "udp")));
    print("allow everything #1: "..tostring(module.tog_only_allow_accepted_packets_inbound(false, nil, "tcp")));
    print("allow everything #2: "..tostring(module.tog_only_allow_accepted_packets_inbound(false, nil, "udp")));
    print("OpenVPN nat init: "..tostring(module.init_nat_for_openvpn("eth0", "tun0", "10.8.0.0")));
    print("allow outgoing only whitelisted: "..tostring(module.tog_only_allow_accepted_packets_outbound(true, nil, "tcp")));
    print("allow outgoing only whitelisted #2: "..tostring(module.tog_only_allow_accepted_packets_outbound(true, nil, "udp")));
    print("allow 192.168.0.1: "..tostring(module.allow_outgoing_new_connection(nil, "tcp", "192.168.0.1", 80)));
    print("allow 192.168.0.1 #2: "..tostring(module.allow_outgoing_new_connection(nil, "udp", "192.168.0.1", 80)));
    print("allow everything #3: "..tostring(module.tog_only_allow_accepted_packets_inbound(true, nil, "tcp")));
    print("allow everything #4: "..tostring(module.tog_only_allow_accepted_packets_inbound(true, nil, "udp")));
    print("is inbound filtered: "..tostring(module.check_if_inbound_packets_are_being_filtered_already()));
    print("is outbound filtered: "..tostring(module.check_if_outbound_packets_are_being_filtered_already()));
    print("open ports: "..tostring(inspect(module.get_open_ports())));

    print("iptables: "..tostring(module.iptables_to_string()));

    return true;
end

return module
