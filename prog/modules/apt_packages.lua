local os = require("os");
local linux = require("linux");

local module = {};

function module.isPackageInstalled(packageName)
    local retLines, retCode = linux.execCommandWithProcRetCode("dpkg-query -W -f='${db:Status-Status}\n' "..tostring(packageName), true, nil, true);

    return retCode == 0 and retLines:find("installed", 1, true) == 1;
end

function module.installPackage(packageName)
    local aptRetStr, retCode = linux.execCommandWithProcRetCode("apt-get install "..packageName.." --no-install-recommends --yes", true, nil, true);

    return retCode == 0, aptRetStr;
end

return module
