local module = {};
local CR = "\r";
local LF = "\n";
local NGX_ERROR = 0;
local NGX_CONF_BLOCK_DONE = 1;
local NGX_CONF_FILE_DONE = 2;
local NGX_CONF_BLOCK_START = 3;
local NGX_CONF_BLOCK_DONE = 4;
local NGX_OK = 5;

function ltrim(s)
    return s:match'^%s*(.*)'
end  

--based on https://github.com/nginx/nginx/blob/master/src/core/ngx_conf_file.c | ngx_conf_read_token & ngx_conf_parse

function module.parse_nginx_config(linesInStr)
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
        offset = offset + 1;

        local needsResettingStuff = false;

        --print(tostring(ch).." last_space: "..tostring(last_space).." need_space: "..tostring(need_space));

        if ch == LF then
            lineCounter = lineCounter + 1;

            if lineChars == " " or lineChars == "" or lineChars == CR or lineChars == CR..LF then
                table.insert(parsedLines, {["spacer"] = true, ["block"] = currentBlock, ["blockDeepness"] = currentBlockDeepness});
            end

            lineChars = "";

            if sharp_comment then
                sharp_comment = false;

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

                print("=> NGX_OK #1");

                goto continue
            end
            
            if ch == '{' then
                status = NGX_CONF_BLOCK_START;

                needsResettingStuff = true;

                currentBlock = lastDataParsed;

                insertBlockStart();

                print("=> NGX_CONF_BLOCK_START #1");

                goto continue
            end

            if ch == ')' then
                last_space = true;
                need_space = false;
            else
                print("[nginx config parse error] unexpected "..tostring(ch).." at offset: "..tostring(offset));

                return false;
            end
        end

        if last_space then
            start = offset - 1;

            if (ch == ' ' or ch == '\t' or ch == CR or ch == LF) then
                goto continue
            end

            if ch == '{' then --nginx block start
                status = NGX_CONF_BLOCK_START;

                needsResettingStuff = true;

                currentBlock = lastDataParsed;

                insertBlockStart();

                print("==> NGX_CONF_BLOCK_START #2");
                
                goto continue
            elseif ch == ';' then --nginx ok
                local data = string.sub(linesInStr, start, offset - 1):gsub('"', ""):gsub('\'', ""):gsub('\\', "");

                status = NGX_OK;

                needsResettingStuff = true;

                print("==> NGX_OK #2 | data: "..tostring(data).." | start: "..tostring(start).." | endSubstr: "..tostring(offset - 1));

                goto continue
            elseif ch == '}' then
                status = NGX_CONF_BLOCK_DONE;

                needsResettingStuff = true;

                insertBlockEnd();

                currentBlock = false;

                print("==> NGX_CONF_BLOCK_DONE #3");

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
            end
        elseif s_quoted then
            if ch == '\'' then
                s_quoted = false;
                need_space = true;
                found = true;
            end
        elseif (ch == ' ' or ch == '\t' or ch == CR or ch == LF or ch == ';' or ch == '{') then
            last_space = true;
            found = true;

            --print("last_space | found");
        end

        if found then
            local data = ltrim(tostring(string.sub(linesInStr, start, offset - 1)):gsub(CR, ""):gsub(LF, ""):gsub("\t", ""));

            lastDataParsed = data;

            print("===> data: "..tostring(data).." start: "..tostring(start).." offset: "..tostring(offset));

            if not currentParams then
                currentParams = {};
            end

            table.insert(currentParams, data);

            if ch == ';' then --nginx ok
                status = NGX_OK;

                needsResettingStuff = true;

                local paramName = currentParams[1];

                table.remove(currentParams, 1);

                print("====> NGX_OK #4 | stripped currentParams: "..require("inspect")(currentParams).." paramName: "..tostring(paramName).." lineCounter: "..tostring(lineCounter));
                
                table.insert(parsedLines, {["block"] = currentBlock, ["blockDeepness"] = currentBlockDeepness, ["paramName"] = paramName, ["args"] = currentParams});

                if not paramToLine[paramName] then
                    paramToLine[paramName] = {};
                end
                
                table.insert(paramToLine[paramName], #parsedLines);

                lastParamLine = lineCounter;

                currentParams = false;

                goto continue
            end

            if ch == '{' then --nginx block start
                status = NGX_CONF_BLOCK_START;

                needsResettingStuff = true;

                print("====> NGX_CONF_BLOCK_START #4");

                currentBlock = data;

                goto continue
            end

            found = false;

            --print("===> resetting found, continuing");
        end

        ::continue::
        if needsResettingStuff then
            resetAllVariablesExceptPositions();
        end
    end    

    print("<================>");
    print(require("inspect")(parsedLines));

    return parsedLines, paramToLine;
end

function doPaddingWithBlockDeepness(blockDeepness)
    if not blockDeepness then
        return "";
    end

    local str = "";

    for i = 1, blockDeepness do
        str = str.."\t";
    end

    return str;
end

function module.write_nginx_config(parsedLines)
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

            lines = lines..doPaddingWithBlockDeepness(v["blockDeepness"])..v["paramName"].." "..tostring(table.concat(v["args"], " "))..";"..additionalStr2..CR..LF;
        elseif v["comment"] then
            lines = lines..doPaddingWithBlockDeepness(v["blockDeepness"])..("#"..v["comment"])..CR..LF;
        end
    end

    return lines;
end

return module;
