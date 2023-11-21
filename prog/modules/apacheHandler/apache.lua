local os = require("os");
local packageManager = require("apt_packages");
local linux = require("linux");

local module = {};
module.errors = {
    WEBSERVER_INSTALLED_ALREADY = -1
};

function module.is_installed()
    return packageManager.is_package_installed("apache2");
end

function module.install()
    if module.is_installed() then
        return module.errors.WEBSERVER_INSTALLED_ALREADY;
    end

    return packageManager.install_package("apache2");
end

function module.is_running()
    if linux.get_service_status("apache2") == "dead" then
        return false;
    end

    return linux.is_service_running("apache2") == true or linux.is_process_running("apache2") == true;
end

function module.stop_server()
    return linux.stop_service("apache2");
end

function module.start_server()
    return linux.start_service("apache2");
end

module.server_impl = require("apacheHandler/apache_server_impl")(module);

function module.init_dirs()
    module.server_impl.init_dirs();
end

return module
