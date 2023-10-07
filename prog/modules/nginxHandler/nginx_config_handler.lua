local module = {};

--based on https://github.com/nginx/nginx/blob/master/src/core/ngx_conf_file.c | ngx_conf_read_token
  
function module.parse_nginx_config(linesInStr)
    --escape empty lines: [^\r\n]+
    --not escaping empty lines: ([^\n]*)\n?

    local parsedLines = {};
    local paramToLine = {};
    local linesIterator = linesInStr:gmatch("([^\n]*)\n?");

    return parsedLines, paramToLine;
end

function module.write_nginx_config(parsedLines)
    local lines = "";

    return lines;
end

return module;
