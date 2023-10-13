local module = {};
local CR = '\r';
local LF = '\n';
local inspect = require("inspect");

function ltrim(s)
    return s:match'^%s*(.*)'
end  

--based on https://httpd.apache.org/docs/2.4/configuring.html

local function parse_apache_config(linesInStr)
    --escape empty lines: [^\r\n]+
    --not escaping empty lines: ([^\n]*)\n?

    local parsedLines = {};
    local paramToLine = {};
    --local linesIterator = linesInStr:gmatch("([^\n]*)\n?");
    local sharpComment = false;
    local lastSpace = true;
    local tempString = "";
    local status = -1;

    local offset = 0;

    local currentBlocks = {};
    local currentBlock = false;
    local currentBlockDeepness = 0;
    local lastDataParsed = false;
    local currentComment = "";
    local lastParamLine = false;
    local insideBlockStartOrEnd = false;
    local quoteStatus = false;

    local currentArgs = {};

    local insertBlockStart = function()
        table.insert(currentBlocks, currentBlock);
        currentBlock = currentBlocks[#currentBlocks];

        currentBlockDeepness = currentBlockDeepness + 1;

        table.insert(parsedLines, {["blockStart"] = currentBlock, ["args"] = currentArgs["args"], ["blockDeepness"] = currentBlockDeepness - 1});
                
        if not paramToLine["block:"..tostring(currentBlock)] then
            paramToLine["block:"..tostring(currentBlock)] = {};
        end

        table.insert(paramToLine["block:"..tostring(currentBlock)], #parsedLines);
    end

    local insertBlockEnd = function()
        currentBlock = currentBlocks[currentBlockDeepness] or false;
        table.remove(currentBlocks, currentBlockDeepness);

        currentBlockDeepness = currentBlockDeepness - 1;

        table.insert(parsedLines, {["blockEnd"] = currentBlock, ["blockDeepness"] = currentBlockDeepness});
                
        if not paramToLine["blockend:"..tostring(currentBlock)] then
            paramToLine["blockend:"..tostring(currentBlock)] = {};
        end

        table.insert(paramToLine["blockend:"..tostring(currentBlock)], #parsedLines);
    end

    local registerCurrentArg = function()
        if not tempString or #tempString == 0 then
            return;
        end

        local swapped = tempString:gsub(LF, ""):gsub(CR, "");

        if swapped:sub(-1) == "\\" then
            swapped = swapped:sub(1, #swapped - 1);
        end

        table.insert(currentArgs["args"], {["quoteStatus"] = currentArgs["quote"], ["data"] = swapped});
        tempString = "";
        quoteStatus = false;
        currentArgs["quote"] = nil;
    end;

    local lineCounter = 1;
    local lineChars = "";

    for ch in linesInStr:gmatch"." do
        offset = offset + 1;

        if ch == CR then
            goto continue;
        end

        if ch == LF then
            lineCounter = lineCounter + 1;

            lastSpace = true;

            quoteStatus = false;

            if sharpComment then
                sharpComment = false;

                print("Comment at: "..tostring(lineCounter).." comment: "..tostring(currentComment));

                currentComment = "";

                tempString = "";
                lineChars = "";
                currentArgs = {};

                goto continue;
            end

            if lineChars == " " or lineChars == "" or lineChars == CR or lineChars == CR..LF then
                tempString = "";
                lineChars = "";
                currentArgs = {};

                print("Found blank line at "..tostring(lineCounter));

                goto continue;
            end

            if currentArgs and currentArgs["type"] == "directive" then
                registerCurrentArg();

                print("==> Directive found at "..tostring(lineCounter).." args: "..tostring(inspect(currentArgs)));
            end

            tempString = "";
            lineChars = "";

            if not currentArgs or not currentArgs["multipleLine"] then
                currentArgs = {};
            end

            goto continue;
        else
            lineChars = lineChars..ch;
        end

        if currentArgs then
            currentArgs["multipleLine"] = nil;
        end

        if sharpComment then
            currentComment = currentComment..ch;

            goto continue;
        end

        if ch == "#" then
            sharpComment = true;

            goto continue;
        end

        if ch == "\t" or ch == "" or ch == " " then
            if lastSpace then
                goto continue;
            else
                lastSpace = true;
            end
        else
            lastSpace = false;
        end

        if insideBlockStartOrEnd then
            if ch == "/" then
                insideBlockStartOrEnd = 3;
                currentArgs["type"] = "blockEnd";
            elseif ch ~= " " then
                if ch ~= ">" then
                    tempString = tempString..ch;
                else
                    if insideBlockStartOrEnd == 2 or insideBlockStartOrEnd == 3 then
                        registerCurrentArg();
                        tempString = "";
                    end

                    if insideBlockStartOrEnd == 3 then
                        print("[apache] block end "..tostring(inspect(currentArgs)).." at "..tostring(offset).." lineCounter: "..tostring(lineCounter));

                        insertBlockEnd();
                    else
                        insertBlockStart();

                        print("[apache] block start "..tostring(currentBlock).." at "..tostring(offset).." lineCounter: "..tostring(lineCounter).." args: "..tostring(inspect(currentArgs)));
                    end

                    insideBlockStartOrEnd = false;

                    currentArgs = {};
                end
            else
                if insideBlockStartOrEnd == true then
                    currentArgs["type"] = "blockStart";
                    currentArgs["args"] = {tempString};
                    currentBlock = tempString;
                    insideBlockStartOrEnd = 2;
                elseif insideBlockStartOrEnd == 2 then
                    registerCurrentArg();
                end

                tempString = "";
            end
        elseif ch == "<" then
            if insideBlockStartOrEnd then
                print("[apache conf error] Starting new block inside block def? offset: "..tostring(offset).." lineCounter: "..tostring(lineCounter));
                return false;
            end

            currentArgs = {["args"] = {}};
            insideBlockStartOrEnd = true;
            tempString = "";
        else
            if not currentArgs["type"] then
                currentArgs["type"] = "directive";
                currentArgs["args"] = {};
            end

            if ch == '"' then
                if quoteStatus == "d" then
                    currentArgs["quote"] = quoteStatus;

                    registerCurrentArg();
                elseif quoteStatus == "s" then
                    print("[apache conf error] directive argument "..tostring(#currentArgs["args"] + 1).." should be quoted with \" but instead it is quoted with ' at line "..tostring(lineCounter));
                    return false;
                else
                    quoteStatus = "d";
                end
            elseif ch == '\'' then
                if quoteStatus == "s" then
                    currentArgs["quote"] = quoteStatus;

                    registerCurrentArg();
                elseif quoteStatus == "d" then
                    print("[apache conf error] directive argument "..tostring(#currentArgs["args"] + 1).." should be quoted with ' but instead it is quoted with \" at line "..tostring(lineCounter));
                    return false;
                else
                    quoteStatus = "s";
                end
            elseif ch ~= " " then
                tempString = tempString..ch;

                if ch == "\\" then
                    currentArgs["multipleLine"] = true;
                else
                    currentArgs["multipleLine"] = nil;
                end
            elseif ch == " " and not quoteStatus and not currentArgs["quote"] then
                registerCurrentArg();
            elseif ch == " " and quoteStatus then
                tempString = tempString..ch;
            end
        end

        ::continue::
    end    

    if lastDataParsed and #lastDataParsed > 0 and not last_space then
        print("[apache config error] unexpected end of parameter at file end, expecting \";\"");

        return false;
    end

    print("<================>");
    print(inspect(parsedLines));

    return parsedLines, paramToLine;
end

local function formatDataAccordingQuoting(tbl)
    local argsStr = "";
    local idx = 0;

    if #tbl == 0 then
        tbl = {tbl};
    end

    for t2, v2 in pairs(tbl) do
        idx = idx + 1;

        local str = "";

        if v2["quoteStatus"] == "d" then
            str = '"'..v2["data"]..'"';
        elseif v2["quoteStatus"] == "s" then
            str = '\''..v2["data"]..'\'';
        else
            str = v2["data"];
        end

        if idx > 1 then
            argsStr = argsStr.." "..str;
        else
            argsStr = str;
        end
    end

    return argsStr;
end

local function doPaddingWithBlockDeepness(blockDeepness)
    if not blockDeepness then
        return "";
    end

    local str = "";

    for i = 1, blockDeepness do
        str = str.."\t";
    end

    return str;
end

local function write_apache_config(parsedLines)
    if not parsedLines then
        return "";
    end

    local lines = "";

    for t, v in pairs(parsedLines) do
        if v["spacer"] then
            lines = lines..CR..LF;
        elseif v["blockStart"] then
            lines = lines..doPaddingWithBlockDeepness(v["blockDeepness"])..v["blockStart"].." {"..CR..LF;
        elseif v["blockEnd"] then
            lines = lines..doPaddingWithBlockDeepness(v["blockDeepness"]).."}"..CR..LF;
        elseif v["paramName"] then
            local additionalStr2 = v["comment"] and " #"..tostring(v["comment"]) or "";

            lines = lines..doPaddingWithBlockDeepness(v["blockDeepness"])..formatDataAccordingQuoting(v["paramName"]).." "..formatDataAccordingQuoting(v["args"])..";"..additionalStr2..CR..LF;
        elseif v["comment"] then
            lines = lines..doPaddingWithBlockDeepness(v["blockDeepness"])..("#"..v["comment"])..CR..LF;
        end
    end

    return lines;
end

apacheConfigHandler = {};

function apacheConfigHandler:new(linesInStr, paramToLine)
    local o = {
        ["parsedLines"] = linesInStr,
        ["paramToLine"] = paramToLine
    };

    if linesInStr and not paramToLine then
        local parsedLinesNew, paramToLineNew = parse_apache_config(linesInStr);

        if not parsedLinesNew then
            return false;
        end

        o["parsedLines"] = parsedLinesNew;
        o["paramToLine"] = paramToLineNew;
    end

    setmetatable(o, self);
    self.__index = self;

    return o;
end

function apacheConfigHandler:getParsedLines()
    return self["parsedLines"];
end

function apacheConfigHandler:getParamsToIdx()
    return self["paramToLine"];
end

function apacheConfigHandler:insertNewData(dataTbl, pos)
    local idx = -1;

    if #dataTbl == 0 then --object, not array -> convert object to array
        dataTbl = {dataTbl};
    end

    if pos then
        idx = pos;

        for t, v in pairs(dataTbl) do
            table.insert(self["parsedLines"], pos, v);
        end
    else
        idx = #self["parsedLines"];

        for t, v in pairs(dataTbl) do
            table.insert(self["parsedLines"], v);
        end
    end

    for paramName, paramArrayOfIndexes in pairs(self["paramToLine"]) do
        for arrayIdx, arrayValue in pairs(paramArrayOfIndexes) do
            if arrayValue > idx then
                paramArrayOfIndexes[arrayIdx] = paramArrayOfIndexes[arrayIdx] + #dataTbl;
            end
        end
    end

    for t, v in pairs(dataTbl) do
        local realParamName = false;

        if v["paramName"] then
            realParamName = tostring(v["paramName"].data);
        elseif dataTbl["blockStart"] then
            realParamName = "block:"..tostring(dataTbl["blockStart"]);
        elseif dataTbl["blockEnd"] then
            realParamName = "blockend:"..tostring(dataTbl["blockEnd"]);
        end

        if realParamName ~= false then
            local paramToLine = self["paramToLine"];

            if not paramToLine[realParamName] then
                paramToLine[realParamName] = {};
            end
            
            table.insert(paramToLine[realParamName], idx + t);

            table.sort(paramToLine[realParamName]);
        end
    end

    return true;
end

function apacheConfigHandler:deleteData(pos)
end

function apacheConfigHandler:toString()
    return write_apache_config(self["parsedLines"]);
end

return module;
