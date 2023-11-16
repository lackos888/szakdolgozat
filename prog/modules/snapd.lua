local os = require("os");
local linux = require("linux");
local aptPackageManager = require("apt_packages");

local module = {};

function module.isSnapdInstalled()
    return aptPackageManager.is_package_installed("snapd");
end

function module.installSnapd()
    if module.isSnapdInstalled() then
        return module.ALREADY_INSTALLED_ERROR;
    end

    local ret1 = aptPackageManager.install_package("snapd");

    if ret1 ~= 0 then
        return false;
    end

    local ret2 = module.install_package("core");

    if ret2 ~= 0 then
        return false;
    end

    return true;
end

function module.is_package_installed(packageName)
    local retCode = linux.exec_command_with_proc_ret_code("snap list | awk '{print $1}' | grep -w \""..tostring(packageName).."\"");

    return retCode == 0
end

function module.install_package(packageName, classic)
    local retCode = linux.exec_command_with_proc_ret_code("snap install --stable "..tostring(classic and "--classic" or "").." "..tostring(packageName));

    return retCode == 0
end

return module
