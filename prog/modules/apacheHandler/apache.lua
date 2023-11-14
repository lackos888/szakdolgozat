local os = require("os");
local packageManager = require("apt_packages");

local module = {};

function module.is_apache_installed()
    return packageManager.is_package_installed("apache2");
end

function module.install_apache()
    if module.is_apache_installed() then
        return -1
    end

    return packageManager.install_package("apache2");
end

module.server_impl = require("apacheHandler/apache_server_impl");

function module.init_dirs()
    module.server_impl.init_dirs();
end

return module
