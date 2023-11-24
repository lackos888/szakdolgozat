local os = require("os");
local linux = require("linux");
local aptPackageManager = require("apt_packages");

local module = {};

function module.isSnapdInstalled()
    return aptPackageManager.isPackageInstalled("snapd");
end

function module.installSnapd()
    if module.isSnapdInstalled() then
        return module.ALREADY_INSTALLED_ERROR;
    end

    local ret1 = aptPackageManager.installPackage("snapd");

    if ret1 ~= 0 then
        return false;
    end

    local ret2 = module.installPackage("core");

    if ret2 ~= 0 then
        return false;
    end

    return true;
end

function module.isPackageInstalled(packageName)
    local retCode = linux.execCommandWithProcRetCode("snap list | awk '{print $1}' | grep -w \""..tostring(packageName).."\"", nil, nil, true);

    return retCode == 0
end

function module.installPackage(packageName, classic)
    local retCode = linux.execCommandWithProcRetCode("snap install --stable "..tostring(classic and "--classic" or "").." "..tostring(packageName), nil, nil, true);

    return retCode == 0
end

return module
