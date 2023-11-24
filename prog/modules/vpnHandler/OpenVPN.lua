local os = require("os");
local packageManager = require("apt_packages");
local linux = require("linux");

local module = {};
module.errors = {
    OPENVPN_INSTALLED_ALREADY = -1
};

function module.isOpenVPNInstalled()
    return packageManager.isPackageInstalled("openvpn");
end

function module.installOpenvpn()
    if module.isOpenVPNInstalled() then
        return module.errors.OPENVPN_INSTALLED_ALREADY;
    end

    return packageManager.installPackage("openvpn");
end

function module.isRunning()
    if linux.getServiceStatus("openvpn") == "dead" then
        return false;
    end

    return linux.isServiceRunning("openvpn") == true or linux.isProcessRunning("openvpn") == true;
end

function module.stopServer()
    return linux.stopService("openvpn");
end

function module.startServer()
    return linux.startService("openvpn");
end

module.serverImpl = require("vpnHandler/OpenVPN_server_impl")(module);

function module.initDirs()
    module.serverImpl.initDirs();
end

return module
