local os = require("os");

local module = {};

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

    if retCodeForMkdir ~= 0 and retCodeForMkdir ~= 1 then --new dir successfully created/already exists
        return false;
    end

    return true;
end

function module.deleteFile(path)
    local retCodeForDelete = module.exec_command_with_proc_ret_code("rm "..path);

    if retCodeForDelete ~= 0 then --file don't exist anymore or perm problems
        return false;
    end

    return true;
end

function module.deleteDirectory(path)
    local retCodeForDelete = module.exec_command_with_proc_ret_code("rm -r "..path);

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

function module.check_if_user_exists(userName)
    local retCodeForId = module.exec_command_with_proc_ret_code("id "..userName);

    return retCodeForId == 0;
end

function module.create_user_with_name(userName, comment, shell, homeDir)
    local additionalStr = homeDir and (" -d "..homeDir.." ") or ("");

    local retCodeForUserCreation = module.exec_command_with_proc_ret_code("useradd -c \""..comment.."\" -m -s "..shell.." "..additionalStr.." "..userName);

    if retCodeForUserCreation ~= 0 and retCodeForUserCreation ~= 9 then
        return false, retCodeForUserCreation
    end

    return true;
end

function module.update_user(userName, comment, shell)
    local retCodeForUserUpdate = module.exec_command_with_proc_ret_code("usermod -c \""..comment.."\" -s "..shell.." "..userName);

    if retCodeForUserUpdate ~= 0 then
        return false
    end

    return true;
end

function module.get_user_home_dir(userName)
    local retLines, retCodeForUser = module.exec_command_with_proc_ret_code("cat /etc/passwd | grep \""..userName..":\" | awk -F ':' '{print $6}'", true);

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
    
    print("[exec_command_with_proc_ret_code] cmd: "..tostring(cmd).." overallReturn: "..tostring(overallReturn).."|||retCode: "..tostring(retCode));

    if linesReturned then
        return overallReturn, retCode;
    end

    return retCode;
end

function module.copy(from, to)
    local retCode = module.exec_command_with_proc_ret_code("cp "..tostring(from).." "..tostring(to));

    return retCode == 0;
end

function module.copyAndChown(user, from, to)
    local retCode = module.exec_command_with_proc_ret_code("cp "..tostring(from).." "..tostring(to));

    if retCode == 0 then
        return module.chown(to, user);
    end

    return false;
end

function module.chown(path, userName, isDir)
    local additionalString = (isDir and (" -hR ") or (""));

    local retCode = module.exec_command_with_proc_ret_code("chown "..additionalString.." "..userName..":"..userName.." "..path);

    return retCode == 0;
end

function module.chmod(path, perm, isDir)
    local additionalString = (isDir and (" -R ") or (""));

    local retCode = module.exec_command_with_proc_ret_code("chmod "..additionalString.." "..tostring(perm).." "..path);

    return retCode == 0;
end

return module;