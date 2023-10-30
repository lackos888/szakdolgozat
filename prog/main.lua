package.path = package.path..";modules/?.lua";

--import handlers
local OpenVPNHandler = require("vpnHandler/OpenVPN");
local nginxHandler = require("nginxHandler/nginx");
local apacheHandler = require("apacheHandler/apache");
local nginxConfigHandlerObject = require("nginxHandler/nginx_config_handler");
local certbotHandler = require("certbotHandler/certbot");
local iptables = require("iptablesHandler/iptables");
local general = require("general");
local inspect = require("inspect");

--initialize handlers
--OpenVPNHandler.init_dirs();
-- nginxHandler.init_dirs(); --TODO: reverse proxy
-- apacheHandler.init_dirs(); --TODO: reverse proxy
-- certbotHandler.init();

-- print("Apache website creation: "..tostring(apacheHandler.server_impl.create_new_website("lszlo.ltd")));
-- print("Certbot test: "..tostring(certbotHandler.try_ssl_certification_creation("dns", "lszlo.ltd", "apache")));

print("ssh port: "..tostring(inspect(iptables.get_current_ssh_ports())));
print("module init: "..tostring(iptables.init_module()));

--[[
local configFileContents = general.readAllFileContents("/home/nginx-www/websiteconfigs/lszlo.ltd.conf");

local configInstance = nginxConfigHandler:new(configFileContents);
print(tostring(require("inspect")(configInstance:getParsedLines())));
print("<===========>Test config:<===========>");
print(tostring(configInstance:toString()));
]]

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