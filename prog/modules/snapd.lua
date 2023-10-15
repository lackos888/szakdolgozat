local os = require("os");
local linux = require("linux");

local module = {};

function module.is_package_installed(packageName)
    local retCode = linux.exec_command_with_proc_ret_code("snap list | awk '{print $1}' | grep -w \""..tostring(packageName).."\"");

    return retCode == 0
end

function module.install_package(packageName, classic)
    local retCode = linux.exec_command_with_proc_ret_code("snap install --stable "..tostring(classic and "--classic" or "").." "..tostring(packageName));

    return retCode == 0
end

return module
