package.path = package.path..";modules/?.lua";

--import handlers
local OpenVPNHandler = require("vpnHandler/OpenVPN");
local nginxHandler = require("nginxHandler/nginx");
local nginxConfigHandler = require("nginxHandler/nginx_config_handler");

--initialize handlers
--OpenVPNHandler.init_dirs();
nginxHandler.init_dirs();

--[[
local nginxConfigParsedLines, paramsLines = nginxConfigHandler.parse_nginx_config(require("general").readAllFileContents("/home/lackos/default"));

local testNginxConf = io.open("testnginx.conf", "wb");

if not testNginxConf then
    return -1
end

testNginxConf:write(nginxConfigHandler.write_nginx_config(nginxConfigParsedLines));
testNginxConf:flush();
testNginxConf:close();
]]

--main stuff
--[[
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
]]