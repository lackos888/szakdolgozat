local os = require("os");
local linux = require("linux");

local module = {};

function module.is_package_installed(packageName)
    local resultForWhereis = linux.exec_command("whereis "..packageName):gsub("%s+", "");

    if resultForWhereis ~= packageName..":" then
        return true;
    end

    local retCode = linux.exec_command_with_proc_ret_code("dpkg -s "..packageName, nil, nil, true);

    return retCode == 0;
end

function module.install_package(packageName)
    local aptRetStr, retCode = linux.exec_command_with_proc_ret_code("apt-get install "..packageName.." --no-install-recommends --yes", true, nil, true);

    return retCode == 0, aptRetStr;
end

return module
