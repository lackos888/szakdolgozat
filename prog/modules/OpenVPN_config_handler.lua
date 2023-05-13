local module = {};

--based on src/openvpn/options.c
  
function module.parse_openvpn_config(linesInStr)
    --escape empty lines: [^\r\n]+
    --not escaping empty lines: ([^\n]*)\n?

    local parsedLines = {};
    local paramToLine = {};
    local linesIterator = linesInStr:gmatch("([^\n]*)\n?");

    for lineVal in linesIterator do
        local state = "initial";
        local beforeFinishState = state;
        local backslash = false;
        local out = "";

        local params = {};
        local commentStart = -1;

        for i = 1, #lineVal do
            local char = lineVal:sub(i, i);

            if not backslash and char == "\\" and state ~= "reading_squoted_param" then
                backslash = true;
            else
                if state == "initial" then
                    if char ~= " " then
                        if char == ";" or char == "#" then
                            commentStart = i;

                            break;
                        end

                        if not backslash and char == '\"' then
                            state = "reading_quoted_param";
                        elseif not backslash and char == "\'" then
                            state = "reading_squoted_param";
                        else
                            out = out..char;
                            state = "reading_unquoted_param";
                        end
                    end
                elseif state == "reading_unquoted_param" then
                    if not backslash and char == " " then
                        beforeFinishState = state;

                        state = "done";
                    else
                        out = out..char;
                    end
                elseif state == "reading_quoted_param" then
                    if not backslash and char == '\"' then
                        beforeFinishState = state;

                        state = "done";
                    else
                        out = out..char;
                    end
                elseif state == "reading_squoted_param" then
                    if not backslash and char == "\'" then
                        beforeFinishState = state;

                        state = "done";
                    else
                        out = out..char;
                    end
                end

                if state == "done" then
                    table.insert(params, {["val"] = out, ["state"] = beforeFinishState});

                    out = "";

                    state = "initial";
                end
            end
        end

        if #out > 0 and out ~= " " then
            table.insert(params, {["val"] = out, ["state"] = beforeFinishState});
        end

        local comment = nil;

        if commentStart ~= -1 then
            comment = lineVal:sub(commentStart);
        end

        if #params > 0 then
            local ix = #parsedLines + 1;

            parsedLines[ix] = {
                ["params"] = params,
                ["comment"] = comment,
            };

            paramToLine[params[1].val] = ix;
        else
            table.insert(parsedLines, {
                ["comment"] = comment
            });
        end
    end

    return parsedLines, paramToLine;
end

function module.write_openvpn_config(parsedLines)
    local lines = "";

    for t, v in pairs(parsedLines) do
        if not v["params"] then
            if v["comment"] then
                lines = lines..v["comment"].."\r\n";
            else
                lines = lines.."\r\n";
            end
        else
            for _, paramsV in pairs(v["params"]) do
                local appendStr = "";

                if paramsV["state"] == "reading_quoted_param" then
                    appendStr = '\"';
                elseif paramsV["state"] == "reading_squoted_param" then
                    appendStr = "\'";
                end

                lines = lines..appendStr..paramsV["val"]..appendStr.." ";
            end

            if v["comment"] then
                lines = lines..v["comment"].."\r\n";
            else
                lines = lines.."\r\n";
            end
        end
    end

    return lines;
end

return module;
