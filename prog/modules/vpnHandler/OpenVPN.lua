local os = require("os");
local packageManager = require("apt_packages");
local linux = require("linux");

local module = {};
module.errors = {
    OPENVPN_INSTALLED_ALREADY = -1
};

function module.is_openvpn_installed()
    return packageManager.is_package_installed("openvpn");
end

function module.install_openvpn()
    if module.is_openvpn_installed() then
        return module.errors.OPENVPN_INSTALLED_ALREADY;
    end

    return packageManager.install_package("openvpn");
end

function module.is_running()
    if linux.get_service_status("openvpn") == "dead" then
        return false;
    end

    return linux.is_service_running("openvpn") == true or linux.is_process_running("openvpn") == true;
end

function module.stop_server()
    return linux.stop_service("openvpn");
end

function module.start_server()
    return linux.start_service("openvpn");
end

module.server_impl = require("vpnHandler/OpenVPN_server_impl")(module);

function module.init_dirs()
    module.server_impl.init_dirs();
end

return module
