local os = require("os");
local packageManager = require("apt_packages");
local linux = require("linux");

local module = {};
module.errors = {
    WEBSERVER_INSTALLED_ALREADY = -1
};

function module.isInstalled()
    return packageManager.isPackageInstalled("apache2");
end

function module.install()
    if module.isInstalled() then
        return module.errors.WEBSERVER_INSTALLED_ALREADY;
    end

    return packageManager.installPackage("apache2");
end

function module.isRunning()
    if linux.getServiceStatus("apache2") == "dead" then
        return false;
    end

    return linux.isServiceRunning("apache2") == true or linux.isProcessRunning("apache2") == true;
end

function module.stopServer()
    return linux.stopService("apache2");
end

function module.startServer()
    return linux.startService("apache2");
end

module.serverImpl = require("apacheHandler/apache_server_impl")(module);

function module.initDirs()
    module.serverImpl.initDirs();
end

return module
