local os = require("os");
local packageManager = require("apt_packages");
local linux = require("linux");

local module = {};
module.errors = {
    WEBSERVER_INSTALLED_ALREADY = -1
};

function module.isInstalled()
    return packageManager.isPackageInstalled("nginx");
end

function module.install()
    if module.isInstalled() then
        return module.errors.WEBSERVER_INSTALLED_ALREADY;
    end

    return packageManager.installPackage("nginx");
end

function module.isRunning()
    if linux.getServiceStatus("nginx") == "dead" then
        return false;
    end

    return linux.isServiceRunning("nginx") == true or linux.isProcessRunning("nginx") == true;
end

function module.stopServer()
    return linux.stopService("nginx");
end

function module.startServer()
    return linux.startService("nginx");
end

module.serverImpl = require("nginxHandler/nginx_server_impl")(module);

function module.initDirs()
    module.serverImpl.initDirs();
end

return module
