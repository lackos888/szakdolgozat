local os = require("os");
local linux = require("linux");

local module = {};

function module.is_package_installed(packageName)
    local retLines, retCode = linux.exec_command_with_proc_ret_code("dpkg-query -W -f='${db:Status-Status}\n' "..tostring(packageName), true, nil, true);

    return retCode == 0 and retLines:find("installed", 1, true) == 1;
end

function module.install_package(packageName)
    local aptRetStr, retCode = linux.exec_command_with_proc_ret_code("apt-get install "..packageName.." --no-install-recommends --yes", true, nil, true);

    return retCode == 0, aptRetStr;
end

return module
