local os = require("os");
local packageManager = require("apt_packages");

local module = {};

function module.is_openvpn_installed()
    return packageManager.is_package_installed("openvpn");
end

function module.install_openvpn()
    if module.is_openvpn_installed() then
        return -1
    end

    return packageManager.install_package("openvpn");
end

module.server_impl = require("vpnHandler/OpenVPN_server_impl");

function module.init_dirs()
    module.server_impl.init_dirs();
end

return module
