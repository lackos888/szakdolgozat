local os = require("os");
local packageManager = require("apt_packages");
local linux = require("linux");

local module = {};
module.errors = {
    WEBSERVER_INSTALLED_ALREADY = -1
};

function module.is_installed()
    return packageManager.is_package_installed("nginx");
end

function module.install()
    if module.is_installed() then
        return module.errors.WEBSERVER_INSTALLED_ALREADY;
    end

    return packageManager.install_package("nginx");
end

function module.is_running()
    if linux.get_service_status("nginx") == "dead" then
        return false;
    end

    return linux.is_service_running("nginx") == true or linux.is_process_running("nginx") == true;
end

function module.stop_server()
    return linux.stop_service("nginx");
end

function module.start_server()
    return linux.start_service("nginx");
end

module.server_impl = require("nginxHandler/nginx_server_impl")(module);

function module.init_dirs()
    module.server_impl.init_dirs();
end

return module
