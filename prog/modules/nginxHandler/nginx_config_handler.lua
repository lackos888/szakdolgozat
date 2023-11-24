local module = {};
local CR = '\r';
local LF = '\n';
local NGX_ERROR = 0;
local NGX_CONF_BLOCK_DONE = 1;
local NGX_CONF_FILE_DONE = 2;
local NGX_CONF_BLOCK_START = 3;
local NGX_CONF_BLOCK_DONE = 4;
local NGX_OK = 5;
local NGX_CONF_MAX_ARGS = 8;
local inspect = require("inspect");
local general = require("general");

--based on https://github.com/nginx/nginx/blob/master/src/core/ngx_conf_file.c | ngx_conf_read_token & ngx_conf_parse

local function concatArgsProperlyForBlockName(args)
    local concattedStr = "";

    for t, v in pairs(args) do
        local tempStr = v["data"];

        if v["quoteStatus"] == "d" then
            tempStr = '"'..tostring(v["data"])..'"';
        elseif v["quoteStatus"] == "s" then
            tempStr = "'"..tostring(v["data"]).."'";
        end

        if t == 1 then
            concattedStr = tempStr;
        elseif v["data"] ~= ")" then
            concattedStr = concattedStr.." "..tempStr;
        else
            concattedStr = concattedStr..tempStr;
        end
    end

    return concattedStr;
end

local function parseNginxConfig(linesInStr)
    --escape empty lines: [^\r\n]+
    --not escaping empty lines: ([^\n]*)\n?

    local parsedLines = {};
    local paramToLine = {};
    --local linesIterator = linesInStr:gmatch("([^\n]*)\n?");
    local sharp_comment = false;
    local quoted = false;
    local d_quoted = false;
    local s_quoted = false;
    local need_space = false;
    local last_space = true;
    local found = false;
    local variable = false;
    local status = -1;
    local start = 1;

    local offset = 0;

    local currentParams = false;
    local currentBlocks = {};
    local currentBlock = false;
    local currentBlockDeepness = 0;
    local lastDataParsed = false;
    local currentComment = "";
    local commentData = false;
    local lastParamLine = false;

    local resetAllVariablesExceptPositions = function()
        sharp_comment = false;
        quoted = false;
        d_quoted = false;
        s_quoted = false;
        need_space = false;
        last_space = true;
        found = false;
        variable = false;
        status = -1;
        start = offset;
        commentData = false;
        currentComment = "";
        currentParams = false;
    end

    local insertBlockStart = function()
        table.insert(currentBlocks, currentBlock);
        currentBlock = currentBlocks[#currentBlocks];

        currentBlockDeepness = currentBlockDeepness + 1;

        table.insert(parsedLines, {["blockStart"] = currentBlock, ["blockDeepness"] = currentBlockDeepness - 1});
                
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

    local lineCounter = 1;
    local lineChars = "";

    for ch in linesInStr:gmatch"." do
        local quoteStatus = false;

        offset = offset + 1;

        local needsResettingStuff = false;

        --print(tostring(ch).." last_space: "..tostring(last_space).." need_space: "..tostring(need_space));

        if ch == LF then
            lineCounter = lineCounter + 1;

            if lineChars == " " or lineChars == "" or lineChars == CR or lineChars == CR..LF or lineChars == LF then
                table.insert(parsedLines, {["spacer"] = true, ["block"] = currentBlock, ["blockDeepness"] = currentBlockDeepness});
            end

            lineChars = "";

            if sharp_comment then
                sharp_comment = false;

                currentComment = currentComment:gsub(CR, ""):gsub(LF, "");

                if not currentParams then
                    if lastParamLine == lineCounter - 1 then
                        parsedLines[#parsedLines]["comment"] = currentComment;

                        lastParamLine = false;
                    else
                        table.insert(parsedLines, {["comment"] = currentComment, ["block"] = currentBlock, ["blockDeepness"] = currentBlockDeepness});
                    end
                else
                    table.insert(currentParams, {["comment"] = currentComment, ["block"] = currentBlock, ["blockDeepness"] = currentBlockDeepness});
                end

                currentComment = "";

                commentData = false;
            end
        else
            lineChars = lineChars..ch;
        end

        if sharp_comment then
            currentComment = currentComment..ch;

            goto continue
        end

        if quoted then
            quoted = false;

            goto continue
        end

        if need_space then
            if (ch == ' ' or ch == '\t' or ch == CR or ch == LF) then
                last_space = true;
                need_space = false;
                goto continue
            end

            if ch == ';' then
                status = NGX_OK;

                needsResettingStuff = true;

                -- print("=> NGX_OK #1");

                goto continue
            end
            
            if ch == '{' then
                status = NGX_CONF_BLOCK_START;

                needsResettingStuff = true;

                -- print("=> NGX_CONF_BLOCK_START #1");

                goto continue
            end

            if ch == ')' then
                last_space = true;
                need_space = false;
            else
                print("[nginx config parse error] unexpected "..tostring(ch).." instead of ) character at offset: "..tostring(offset).." lineCounter: "..tostring(lineCounter));

                return false;
            end
        end

        if last_space then
            start = offset;

            if (ch == ' ' or ch == '\t' or ch == CR or ch == LF) then
                goto continue
            end

            if ch == '{' or ch == ';' then --nginx block start/nginx ok
                if not lastDataParsed or #lastDataParsed == 0 then
                    print("[nginx config error] unexpected character "..tostring(ch).." when expecting a block start at offset: "..tostring(offset).." lineCounter: "..tostring(lineCounter));

                    return false;
                end

                if ch == '{' then
                    status = NGX_CONF_BLOCK_START;

                    needsResettingStuff = true;

                    -- print("==> NGX_CONF_BLOCK_START #2");
                else
                    --local data = string.sub(linesInStr, start, offset - 1):gsub('"', ""):gsub('\'', ""):gsub('\\', "");

                    status = NGX_OK;
    
                    needsResettingStuff = true;
    
                    -- print("==> NGX_OK #2");
                    --print("==> NGX_OK #2 | data: "..tostring(data).." | start: "..tostring(start).." | endSubstr: "..tostring(offset - 1));
                end
                
                goto continue
            elseif ch == '}' then
                if lastDataParsed and #lastDataParsed ~= 0 then
                    print("[nginx config error] unexpected arguments ("..tostring(inspect(lastDataParsed))..") when expecting block ending at offset: "..tostring(offset).." lineCounter: "..tostring(lineCounter));

                    return false;
                end

                status = NGX_CONF_BLOCK_DONE;

                needsResettingStuff = true;

                --print("==> NGX_CONF_BLOCK_DONE #3");

                goto continue
            elseif ch == '#' then
                sharp_comment = true;
                commentData = {};
            elseif ch == '\\' then
                quoted = true;
                last_space = false;
            elseif ch == '"' then
                start = start + 1;
                d_quoted = true;
                last_space = false;
            elseif ch == '\'' then
                start = start + 1;
                s_quoted = true;
                last_space = false;
            elseif ch == '$' then
                variable = true;
                last_space = false;
            else
                last_space = false;
            end

            goto continue
        end

        if ch == '{' and variable then
            goto continue
        end

        variable = false;

        if ch == '\\' then
            quoted = true;

            goto continue;
        end
        
        if ch == '$' then
            variable = true;

            goto continue;
        end
        
        if d_quoted then
            if ch == '"' then
                d_quoted = false;
                need_space = true;
                found = true;

                quoteStatus = "d";
            end
        elseif s_quoted then
            if ch == '\'' then
                s_quoted = false;
                need_space = true;
                found = true;

                quoteStatus = "s";
            end
        elseif (ch == ' ' or ch == '\t' or ch == CR or ch == LF or ch == ';' or ch == '{') then
            last_space = true;
            found = true;

            --print("last_space | found");
        end

        if found then
            local data = tostring(string.sub(linesInStr, start, offset - 1)):gsub('\\"', ""):gsub('\\\'', ""):gsub('\\\\', "");

            if not lastDataParsed then
                lastDataParsed = {};
            end

            table.insert(lastDataParsed, {data = data, quoteStatus = quoteStatus});

            if #lastDataParsed > NGX_CONF_MAX_ARGS then
                print("[nginx config error] arguments exceeded at offset: "..tostring(offset).." lineCounter: "..tostring(lineCounter).." args: "..tostring(inspect(lastDataParsed)));

                return false;
            end
            
            --print("===> data: "..tostring(data).." start: "..tostring(start).." offset: "..tostring(offset).." quoteStatus: "..tostring(quoteStatus).." last_space: "..tostring(last_space));

            if not currentParams then
                currentParams = {};
            end

            table.insert(currentParams, {["data"] = data, ["quoteStatus"] = quoteStatus});

            if ch == ';' then --nginx ok
                status = NGX_OK;

                needsResettingStuff = true;

                goto continue
            end

            if ch == '{' then --nginx block start
                status = NGX_CONF_BLOCK_START;

                needsResettingStuff = true;

                goto continue
            end

            found = false;

            --print("===> resetting found, continuing");
        end

        ::continue::
        if needsResettingStuff then
            if status == NGX_OK then
                local paramName = currentParams[1];
                local realParamName = paramName.data;

                table.remove(currentParams, 1);

                -- print("====> NGX_OK #3 | stripped currentParams: "..inspect(currentParams).." paramName: "..inspect(paramName).." lineCounter: "..tostring(lineCounter));
                
                table.insert(parsedLines, {["block"] = currentBlock, ["blockDeepness"] = currentBlockDeepness, ["paramName"] = paramName, ["args"] = currentParams});

                if not paramToLine[realParamName] then
                    paramToLine[realParamName] = {};
                end
                
                table.insert(paramToLine[realParamName], #parsedLines);

                lastParamLine = lineCounter;

                currentParams = false;

                lastDataParsed = false;
            elseif status == NGX_CONF_BLOCK_START then
                currentBlock = concatArgsProperlyForBlockName(lastDataParsed);

                insertBlockStart();

                lastDataParsed = false;
            elseif status == NGX_CONF_BLOCK_DONE then
                insertBlockEnd();

                currentBlock = false;
            end

            resetAllVariablesExceptPositions();
        end
    end    

    if lastDataParsed and #lastDataParsed > 0 and not last_space then
        print("[nginx config error] unexpected end of parameter at file end, expecting \";\"");

        return false;
    end

    --print("<================>");
    --print(inspect(parsedLines));

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

local function writeNginxConfig(parsedLines)
    if not parsedLines then
        return "";
    end

    local lines = "";

    for t, v in pairs(parsedLines) do
        if v["spacer"] then
            lines = lines..tostring(general.lineEnding);
        elseif v["blockStart"] then
            lines = lines..doPaddingWithBlockDeepness(v["blockDeepness"])..v["blockStart"].." {"..tostring(general.lineEnding);
        elseif v["blockEnd"] then
            lines = lines..doPaddingWithBlockDeepness(v["blockDeepness"]).."}"..tostring(general.lineEnding);
        elseif v["paramName"] then
            local additionalStr2 = v["comment"] and " #"..tostring(v["comment"]) or "";

            lines = lines..doPaddingWithBlockDeepness(v["blockDeepness"])..formatDataAccordingQuoting(v["paramName"]).." "..formatDataAccordingQuoting(v["args"])..";"..additionalStr2..tostring(general.lineEnding);
        elseif v["comment"] then
            lines = lines..doPaddingWithBlockDeepness(v["blockDeepness"])..("#"..v["comment"])..tostring(general.lineEnding);
        end
    end

    return lines;
end

nginxConfigHandler = {};

function nginxConfigHandler:new(linesInStr, paramToLine)
    local o = {
        ["parsedLines"] = linesInStr,
        ["paramToLine"] = paramToLine
    };

    if linesInStr and not paramToLine then
        local parsedLinesNew, paramToLineNew = parseNginxConfig(linesInStr);

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

function nginxConfigHandler:getParsedLines()
    return self["parsedLines"];
end

function nginxConfigHandler:getParamsToIdx()
    return self["paramToLine"];
end

function nginxConfigHandler:insertNewData(dataTbl, pos)
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

function nginxConfigHandler:deleteData(pos)
end

function nginxConfigHandler:toString()
    return writeNginxConfig(self["parsedLines"]);
end

return module;
