local os = require("os");

local module = {};

--from https://stackoverflow.com/questions/1340230/check-if-directory-exists-in-lua
function module.exists(file)
    local ok, err, code = os.rename(file, file)
    if not ok then
        if code == 13 or code == 17 then
            return true
        end
    end
    return ok, err
end
 
function module.isdir(path)
    return module.exists(path.."/")
end

function module.listDirFiles(path)
    local retLines, retCode = module.exec_command_with_proc_ret_code("dir "..tostring(path), true, nil, true);

    local files = {};

    if retCode == 0 then
        for filePath in string.gmatch(retLines, "[^\r\n]+") do
            table.insert(files, filePath);
        end
        --print("retLines: "..tostring(retLines));
    end

    return files;
end

function module.mkdir(path)
    local retCodeForMkdir = module.exec_command_with_proc_ret_code("mkdir "..path);
    return retCodeForMkdir == 0 or retCodeForMkdir == 1; --new dir successfully created/already exists
end

function module.deleteFile(path)
    local retCodeForDelete = module.exec_command_with_proc_ret_code("rm "..path, nil, nil, true);

    if retCodeForDelete ~= 0 then --file don't exist anymore or perm problems
        return false;
    end

    return true;
end

function module.deleteDirectory(path)
    local retCodeForDelete = module.exec_command_with_proc_ret_code("rm -r "..path, nil, nil, true);

    if retCodeForDelete ~= 0 then --dir don't exist anymore or perm problems
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

function module.get_service_status(serviceName)
    local output, retCode = module.exec_command_with_proc_ret_code("systemctl show -p SubState --value "..tostring(serviceName), true);
    return output;
end

function module.is_service_running(serviceName)
    return module.get_service_status(serviceName) == "running";
end

function module.is_process_running(name)
    return module.exec_command_with_proc_ret_code("pidof "..tostring(name), nil, nil, true) == 0;
end

function module.stop_service(serviceName)
    return module.exec_command_with_proc_ret_code("systemctl stop --quiet "..tostring(serviceName), nil, nil, true) == 0;
end

function module.start_service(serviceName)
    return module.exec_command_with_proc_ret_code("systemctl start --quiet "..tostring(serviceName), nil, nil, true) == 0;
end

function module.restart_service(serviceName)
    return module.exec_command_with_proc_ret_code("systemctl restart --quiet "..tostring(serviceName), nil, nil, true) == 0;
end

function module.systemctl_daemon_reload()
    return module.exec_command_with_proc_ret_code("systemctl daemon-reload", nil, nil, true) == 0;
end

function module.check_if_user_exists(userName)
    return module.exec_command_with_proc_ret_code("id "..userName, nil, nil, true) == 0;
end

function module.create_user_with_name(userName, comment, shell, homeDir)
    local additionalStr = homeDir and (" -d "..homeDir.." ") or ("");

    local retCodeForUserCreation = module.exec_command_with_proc_ret_code("useradd -c \""..comment.."\" -m -s "..shell.." "..additionalStr..""..userName, nil, nil, true);

    if retCodeForUserCreation ~= 0 and retCodeForUserCreation ~= 9 then
        return false, retCodeForUserCreation
    end

    return true;
end

function module.update_user(userName, comment, shell)
    local retCodeForUserUpdate = module.exec_command_with_proc_ret_code("usermod -c \""..comment.."\" -s "..shell.." "..userName, nil, nil, true);

    if retCodeForUserUpdate ~= 0 then
        return false
    end

    return true;
end

function module.get_user_home_dir(userName)
    local retLines, retCodeForUser = module.exec_command_with_proc_ret_code("cat /etc/passwd | grep \""..userName..":\" | awk -F ':' '{print $6}'", true, nil, true);

    if #retLines > 0 then
        return retLines;
    end

    return false;
end

function module.exec_command_with_proc_ret_code(cmd, linesReturned, envVariables, redirectStdErrToStdIn)
    local exportCmd = "";

    if envVariables then
        for k, v in pairs(envVariables) do
            exportCmd = exportCmd.." export "..tostring(k).."="..tostring(v).."; ";
        end
    end

    local handle = io.popen(exportCmd..cmd..tostring(redirectStdErrToStdIn and " 2>&1" or "").."; echo $?");
    handle:flush();

    local overallReturn = "";
    local lastLine = "";
    local newLineChar = "\n";
    local lineNum = 0;

    for line in handle:lines() do
        overallReturn = overallReturn .. line .. newLineChar;
        
        lastLine = line;

        lineNum = lineNum + 1;
    end

    handle:close();

    local retCode = tonumber(lastLine);

    if lineNum == 1 then
        overallReturn = "";
    else
        overallReturn = string.sub(overallReturn, 1, #overallReturn - #lastLine - #newLineChar * 2); --skip return code line
    end
    
    -- print("[exec_command_with_proc_ret_code] cmd: "..tostring(cmd).." overallReturn: "..tostring(overallReturn).."|||retCode: "..tostring(retCode));

    if linesReturned then
        return overallReturn, retCode;
    end

    return retCode;
end

function module.copy(from, to)
    local retCode = module.exec_command_with_proc_ret_code("cp "..tostring(from).." "..tostring(to), nil, nil, true);

    return retCode == 0;
end

function module.copyAndChown(user, from, to)
    local retCode = module.exec_command_with_proc_ret_code("cp "..tostring(from).." "..tostring(to), nil, nil, true);

    if retCode == 0 then
        return module.chown(to, user);
    end

    return false;
end

function module.chown(path, userName, isDir)
    local additionalString = (isDir and (" -hR") or (""));

    local retCode = module.exec_command_with_proc_ret_code("chown"..additionalString.." "..userName..":"..userName.." "..path, nil, nil, true);

    return retCode == 0;
end

function module.chmod(path, perm, isDir)
    local additionalString = (isDir and (" -R") or (""));

    local retCode = module.exec_command_with_proc_ret_code("chmod"..additionalString.." "..tostring(perm).." "..path, nil, nil, true);

    return retCode == 0;
end

return module;