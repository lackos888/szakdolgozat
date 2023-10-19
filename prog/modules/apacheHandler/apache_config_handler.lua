local module = {};
local CR = '\r';
local LF = '\n';
local inspect = require("inspect");
local general = require("general");

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
    local lastChar = false;

    local currentParsedDetails = {};

    local insertBlockStart = function()
        table.insert(currentBlocks, currentBlock);
        currentBlock = currentBlocks[#currentBlocks];

        currentBlockDeepness = currentBlockDeepness + 1;

        table.insert(parsedLines, {["blockStart"] = currentBlock, ["args"] = currentParsedDetails["args"], ["blockDeepness"] = currentBlockDeepness - 1});
                
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

    local registerCurrentArg = function(lastLine)
        local swapped = tempString:gsub(LF, ""):gsub(CR, "");

        if swapped:sub(-1) == "\\" then
            swapped = swapped:sub(1, #swapped - 1);
        end

        if not swapped or #swapped == 0 then
            local args = currentParsedDetails["args"];

            if args[#args]["quoteStatus"] then
                return;
            end
        end

        if lastLine and swapped and #swapped == 0 and currentParsedDetails["multipleLine"] then
            local args = currentParsedDetails["args"];
            args[#args].multipleLine = true;
        else
            table.insert(currentParsedDetails["args"], {["quoteStatus"] = currentParsedDetails["quote"], ["data"] = swapped, ["multipleLine"] = currentParsedDetails["multipleLine"]});
        end

        tempString = "";
        quoteStatus = false;
        currentParsedDetails["quote"] = nil;
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

                --currentComment = currentComment:gsub(LF, ""):gsub(CR, ""):gsub('\t', "");

                table.insert(parsedLines, {["comment"] = currentComment});

                --print("Comment at: "..tostring(lineCounter).." comment: "..tostring(currentComment));

                currentComment = "";

                tempString = "";
                lineChars = "";
                currentParsedDetails = {};

                goto continue;
            end

            if lineChars == " " or lineChars == "" or lineChars == CR or lineChars == CR..LF then
                tempString = "";
                lineChars = "";
                currentParsedDetails = {};

                table.insert(parsedLines, {["spacer"] = true});

                --print("Found blank line at "..tostring(lineCounter));

                goto continue;
            end

            if currentParsedDetails and currentParsedDetails["type"] == "directive" then
                registerCurrentArg(true);

                --print("==> Directive found at "..tostring(lineCounter).." args: "..tostring(inspect(currentParsedDetails)));
            end

            tempString = "";
            lineChars = "";

            if currentParsedDetails and currentParsedDetails["args"] and not currentParsedDetails["multipleLine"] then
                local args = {table.unpack(currentParsedDetails["args"])};

                local paramName = args[1];

                local realParamName = paramName.data;

                table.remove(args, 1);

                table.insert(parsedLines, {["paramName"] = paramName, ["args"] = args, ["blockDeepness"] = currentBlockDeepness});

                if not paramToLine[realParamName] then
                    paramToLine[realParamName] = {};
                end

                table.insert(paramToLine[realParamName], #parsedLines);
            end

            if not currentParsedDetails or not currentParsedDetails["multipleLine"] then
                currentParsedDetails = {};
            end

            goto continue;
        else
            lineChars = lineChars..ch;
        end

        if currentParsedDetails then
            currentParsedDetails["multipleLine"] = nil;
        end

        if sharpComment then
            currentComment = currentComment..ch;

            goto continue;
        end

        if ch == "#" then
            sharpComment = true;
            currentComment = lineChars;

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
            if ch == "/" and insideBlockStartOrEnd == true then --block ending directive like </
                insideBlockStartOrEnd = 3;
                currentParsedDetails["type"] = "blockEnd";
            elseif ch ~= " " then
                if ch ~= ">" then --block definition ending character
                    if ch == '"' and lastChar ~= "\\" then
                        if quoteStatus == "d" then
                            currentParsedDetails["quote"] = quoteStatus;
        
                            registerCurrentArg();
                        elseif quoteStatus == "s" then
                            print("[apache conf error] block argument "..tostring(#currentParsedDetails["args"] + 1).." should be quoted with \" but instead it is quoted with ' at line "..tostring(lineCounter));
                            return false;
                        else
                            quoteStatus = "d";
                        end
                    elseif ch == '\'' and lastChar ~= "\\" then
                        if quoteStatus == "s" then
                            currentParsedDetails["quote"] = quoteStatus;
        
                            registerCurrentArg();
                        elseif quoteStatus == "d" then
                            print("[apache conf error] block argument "..tostring(#currentParsedDetails["args"] + 1).." should be quoted with ' but instead it is quoted with \" at line "..tostring(lineCounter));
                            return false;
                        else
                            quoteStatus = "s";
                        end
                    else
                        tempString = tempString..ch;
                    end
                else
                    if insideBlockStartOrEnd == 2 or insideBlockStartOrEnd == 3 then
                        if tempString and #tempString > 0 then
                            registerCurrentArg();
                        end

                        tempString = "";
                    end

                    if insideBlockStartOrEnd == 3 then
                        --print("[apache] block end "..tostring(inspect(currentParsedDetails)).." at "..tostring(offset).." lineCounter: "..tostring(lineCounter));

                        insertBlockEnd();
                    else
                        insertBlockStart();

                        --print("[apache] block start "..tostring(currentBlock).." at "..tostring(offset).." lineCounter: "..tostring(lineCounter).." args: "..tostring(inspect(currentParsedDetails)));
                    end

                    insideBlockStartOrEnd = false;

                    currentParsedDetails = {};
                end
            else
                if insideBlockStartOrEnd == true then
                    currentParsedDetails["type"] = "blockStart";
                    currentParsedDetails["args"] = {};
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

            currentParsedDetails = {["args"] = {}};
            insideBlockStartOrEnd = true;
            tempString = "";
        else
            if not currentParsedDetails["type"] then
                currentParsedDetails["type"] = "directive";
                currentParsedDetails["args"] = {};
            end

            if ch == '"' and lastChar ~= "\\" then
                if quoteStatus == "d" then
                    currentParsedDetails["quote"] = quoteStatus;

                    registerCurrentArg();
                elseif quoteStatus == "s" then
                    print("[apache conf error] directive argument "..tostring(#currentParsedDetails["args"] + 1).." should be quoted with \" but instead it is quoted with ' at line "..tostring(lineCounter));
                    return false;
                else
                    quoteStatus = "d";
                end
            elseif ch == '\'' and lastChar ~= "\\" then
                if quoteStatus == "s" then
                    currentParsedDetails["quote"] = quoteStatus;

                    registerCurrentArg();
                elseif quoteStatus == "d" then
                    print("[apache conf error] directive argument "..tostring(#currentParsedDetails["args"] + 1).." should be quoted with ' but instead it is quoted with \" at line "..tostring(lineCounter));
                    return false;
                else
                    quoteStatus = "s";
                end
            elseif ch ~= " " then
                tempString = tempString..ch;

                if ch == "\\" then
                    currentParsedDetails["multipleLine"] = true;
                else
                    currentParsedDetails["multipleLine"] = nil;
                end
            elseif ch == " " and not quoteStatus and not currentParsedDetails["quote"] then
                registerCurrentArg();
            elseif ch == " " and quoteStatus then
                tempString = tempString..ch;
            end
        end

        ::continue::
        lastChar = ch;
    end

    --print("<================>");
    --print(inspect(parsedLines));

    return parsedLines, paramToLine;
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

local function formatDataAccordingQuoting(tbl, blockDeepness)
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
            if not v2["multipleLine"] and not tbl[t2 - 1]["multipleLine"] then
                argsStr = argsStr.." "..str;
            else
                argsStr = argsStr..str;
            end
        else
            argsStr = str;
        end

        if v2["multipleLine"] then
            argsStr = argsStr.." \\"..tostring(general.lineEnding)..tostring(doPaddingWithBlockDeepness(blockDeepness));
        end
    end

    return argsStr;
end

local function write_apache_config(parsedLines)
    if not parsedLines then
        return "";
    end

    local lines = "";

    for t, v in pairs(parsedLines) do
        if v["spacer"] then
            lines = lines..tostring(general.lineEnding);
        elseif v["blockStart"] then
            local additionalStr = (v["args"] and #v["args"] > 0) and (" "..tostring(formatDataAccordingQuoting(v["args"], v["blockDeepness"]))) or "";

            lines = lines..doPaddingWithBlockDeepness(v["blockDeepness"]).."<"..tostring(v["blockStart"])..""..additionalStr..">"..tostring(general.lineEnding);
        elseif v["blockEnd"] then
            lines = lines..doPaddingWithBlockDeepness(v["blockDeepness"]).."</"..tostring(v["blockEnd"])..">"..tostring(general.lineEnding);
        elseif v["paramName"] then
            lines = lines..doPaddingWithBlockDeepness(v["blockDeepness"])..formatDataAccordingQuoting(v["paramName"], v["blockDeepness"]).." "..formatDataAccordingQuoting(v["args"], v["blockDeepness"])..tostring(general.lineEnding);
        elseif v["comment"] then
            lines = lines..tostring(v["comment"])..tostring(general.lineEnding);
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

apacheEnvvarsHandler = {};

local function parse_envvar_args_from_line(line)
    if line:find("#", 1, true) then
        return false;
    end

    local exportStr = "export ";

    local exportFound = line:find(exportStr, 1, true);
    if exportFound then
        local exportNameEnd = line:find("=", exportFound + #exportStr, 1, true);
        if exportNameEnd then
            local exportName = line:sub(exportFound + #exportStr, exportNameEnd - 1);
            return {exportName = exportName, val = line:sub(exportNameEnd + 1)};
        end
    end

    return false;
end

function apacheEnvvarsHandler:new(linesInStr)
    local o = {
        ["lines"] = linesInStr,
        ["args"] = {},
        ["lineOverride"] = {}
    };

    if linesInStr and type(linesInStr) == "string" then
        o["lines"] = {};
        
        for line in string.gmatch(linesInStr, "([^\n]*)\n?") do
            table.insert(o["lines"], line);
        end
    end

    for t, v in pairs(o["lines"]) do
        local argsFound = parse_envvar_args_from_line(v);

        if argsFound then
            o["args"][argsFound.exportName] = argsFound.val;
        end
    end

    setmetatable(o, self);
    self.__index = self;

    return o;
end

function apacheEnvvarsHandler:getArgs()
    return self["args"];
end

local function escape_magic(s) --from https://stackoverflow.com/questions/29503721/lua-plain-searching-with-string-gsub
    return (s:gsub('[%^%$%(%)%%%.%[%]%*%+%-%?]','%%%1'))
end

function apacheEnvvarsHandler:toString()
    local ret = "";
    
    for t, v in pairs(self["lines"]) do
        local argsFound = parse_envvar_args_from_line(v);

        if argsFound then
            v = v:gsub(escape_magic("="..tostring(argsFound.val)), "="..tostring(self["args"][argsFound.exportName]));
        end

        ret = ret..v..tostring(general.lineEnding);
    end

    return ret;
end

return module;
