package.path = package.path..";modules/?.lua";

local OpenVPNHandler = require("vpnHandler/OpenVPN");

OpenVPNHandler.init_dirs();

local vpnInstalled = OpenVPNHandler.is_openvpn_installed();

print("is openvpn installed: "..tostring(vpnInstalled));

if not vpnInstalled then
    print("Trying to install OpenVPN server binaries...");

    OpenVPNHandler.install_openvpn();

    print("Installed OpenVPN basic server binaries...");
else
    print("OpenVPN is installed!");
end

print("easy_rsa install ret: "..tostring(OpenVPNHandler.server_impl.install_easy_rsa()));
print("initialize_server ret: "..tostring(OpenVPNHandler.server_impl.initialize_server()));