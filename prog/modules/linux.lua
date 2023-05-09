local os = require("os");

local module = {};

function module.exists(file)
    local ok, err, code = os.rename(file, file)
    if not ok then
        if code == 13 then
            return true
        end
    end
    return ok, err
end
 
function module.isdir(path)
    return module.exists(path.."/")
end

function module.mkdir(path)
    local retCodeForMkdir = module.exec_command_with_proc_ret_code("mkdir "..path);

    if retCodeForMkdir ~= 0 and retCodeForMkdir ~= 1 then --new dir successfully created/already exists
        return false;
    end

    return true;
end

function module.exec_command(cmd)
    local handle = io.popen(cmd);
    local result = handle:read("*a");
    handle:close();

    return result;
end

function module.exec_command_with_proc_ret_code(cmd, linesReturned, maxLengthForReturnCode, envVariables)
    maxLengthForReturnCode = maxLengthForReturnCode or 1;

    local exportCmd = "";

    if envVariables then
        for k, v in pairs(envVariables) do
            exportCmd = exportCmd.." export "..tostring(k).."="..tostring(v).."; ";
        end
    end

    local handle = io.popen(exportCmd..cmd.."; echo $?");
    handle:flush();

    local overallReturn = "";
    local lastLine = "";

    for line in handle:lines() do
        overallReturn = overallReturn .. line .. "\n";
        
        lastLine = line;
    end

    handle:close();

    local retCode = tonumber(lastLine);

    overallReturn = string.sub(overallReturn, 1, #overallReturn - #lastLine); --skip return code line
    
    print("[exec_command_with_proc_ret_code] cmd: "..tostring(cmd).." overallReturn: "..tostring(overallReturn).."|||retCode: "..tostring(retCode));

    if linesReturned then
        return overallReturn, retCode;
    end

    return retCode;
end

function module.concatPaths(...)
    local outputPath = "";
    local args = {...};
    
    for t, v in pairs(args) do
        v = string.gsub(v, "%\\", "/");

        if t == #args and v:sub(1, 1) == "/" then
            outputPath = outputPath..(v:sub(2));
        else
            if v.sub(#v - 1, 1) == "/" then
                outputPath = outputPath..v;
            else
                outputPath = outputPath..v.."/";
            end
        end
    end

    return outputPath;
end

return module;