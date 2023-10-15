local os = require("os");
local packageManager = require("apt_packages");

local module = {};

function module.is_nginx_installed()
    return packageManager.is_package_is_installed("nginx");
end

function module.install_nginx()
    if module.is_nginx_installed() then
        return -1
    end

    return packageManager.install_package("nginx");
end

module.server_impl = require("nginxHandler/nginx_server_impl");

function module.init_dirs()
    module.server_impl.init_dirs();
end

return module
