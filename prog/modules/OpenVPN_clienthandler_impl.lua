local linux = require("linux");
local utils = require("utils");
local config_handler = require("OpenVPN_config_handler");

local module = {};
local serverImpl = false;
local clientObjects = {};
local validClients = {};

local clientSampleConfig = [[client
dev tun
proto udp
sndbuf 0
rcvbuf 0
remote IP-ADDRESS-OF-SERVER 1194
resolv-retry infinite
nobind
persist-key
persist-tun
remote-cert-tls server
auth Whirlpool
ncp-disable #don't negotiate ciphers, we know what we want
tls-cipher TLS-ECDHE-ECDSA-WITH-AES-256-GCM-SHA384 
tls-version-min 1.2 
cipher AES-256-GCM
tls-client
setenv opt block-outside-dns
verb 3]];

local function readAllFileContents(filePath)
    local fileHandle = io.open(filePath, "r");

    if not fileHandle then
        return false;
    end

    local ret = fileHandle:read("a*");
    fileHandle:close();

    return ret;
end

Client = {};

function Client:new(clientName, loadedFromPKI)
    local o = {
        name = clientName
    };

    setmetatable(o, self);
    self.__index = self;

    clientObjects[clientName] = o;

    if loadedFromPKI then
        validClients[clientName] = true;
    end

    return o;
end

function Client:genKeyAndCRT(password)
    local envVariables = {
        ["EASYRSA_PKI"] = serverImpl.getEasyRSAPKiDir()
    };

    envVariables["EASYRSA_BATCH"] = 1;
    envVariables["EASYRSA_ALGO"] = "ed";
    envVariables["EASYRSA_CURVE"] = "ed25519";
    envVariables["EASYRSA_DIGEST"] = "sha512";
    envVariables["EASYRSA_PASSIN"] = "pass:"..serverImpl.getCAPass();
    envVariables["EASYRSA_PASSOUT"] = "pass:"..password;

    local retCode = linux.exec_command_with_proc_ret_code("./"..linux.concatPaths(serverImpl.getEasyRSADir(), "/easyrsa").." build-client-full "..self["name"], nil, nil, envVariables);

    if retCode ~= 0 then
        return -1;
    end

    validClients[self["name"]] = true;

    return true;
end

function Client:generateClientConfig()
    if not self:isValidClient() then
        return false;
    end

    local configFileContent, paramsToLines = config_handler.parse_openvpn_config(clientSampleConfig);

    if paramsToLines["remote"] then
        local paramTbl = configFileContent[paramsToLines["remote"]];

        paramTbl["params"][2].val = "carina.szurti.com"; --test IP
        paramTbl["params"][3].val = 1337; --test Port
    end

    local clientConfig = config_handler.write_openvpn_config(configFileContent);

    local serverCAPath = linux.concatPaths(serverImpl.getEasyRSAPKiDir(), "/issued/"..serverImpl["openvpn_server_name_in_ca"]..".crt");

    local clientCAPath = linux.concatPaths(serverImpl.getEasyRSAPKiDir(), "/issued/"..self["name"]..".crt");

    local clientKeyPath = linux.concatPaths(serverImpl.getEasyRSAPKiDir(), "/private/"..self["name"]..".key");

    local tlsCryptKeyPath = linux.concatPaths(serverImpl.get_openvpn_home_dir(), "/ta.key");

    local serverCACrt = readAllFileContents(serverCAPath);

    if not serverCACrt then
        return -1;
    end

    local clientCACrt = readAllFileContents(clientCAPath);

    if not clientCACrt then
        return -2;
    end

    local clientKey = readAllFileContents(clientKeyPath);

    if not clientKey then
        return -3;
    end

    local tlsCryptKey = readAllFileContents(tlsCryptKeyPath);

    if not tlsCryptKey then
        return -4;
    end

    clientConfig = clientConfig.."<ca>\n"..serverCACrt.."</ca>\n";
    clientConfig = clientConfig.."<cert>\n"..clientCACrt.."</cert>\n";
    clientConfig = clientConfig.."<key>\n"..clientKey.."</key>\n";
    clientConfig = clientConfig.."<tls-crypt>\n"..tlsCryptKey.."</tls-crypt>\n";

    return clientConfig;
end

function Client:revoke()
    if not self:isValidClient() then
        return false;
    end

    local envVariables = {
        ["EASYRSA_PKI"] = serverImpl.getEasyRSAPKiDir()
    };

    envVariables["EASYRSA_BATCH"] = 1;
    envVariables["EASYRSA_ALGO"] = "ed";
    envVariables["EASYRSA_CURVE"] = "ed25519";
    envVariables["EASYRSA_DIGEST"] = "sha512";
    envVariables["EASYRSA_PASSIN"] = "pass:"..serverImpl.getCAPass();

    local retCode = linux.exec_command_with_proc_ret_code("./"..linux.concatPaths(serverImpl.getEasyRSADir(), "/easyrsa").." revoke "..self["name"], nil, nil, envVariables);

    if retCode ~= 0 and retCode ~= 1 then
        return -1;
    end

    if not module.update_revoke_crl_for_openvpn_daemon() then
        return -2;
    end

    validClients[self["name"]] = nil;
    clientObjects[self["name"]] = nil;

    return true;
end

function Client:isValidClient()
    return validClients[self["name"]] == true;
end

function module.update_revoke_crl_for_openvpn_daemon()
    local envVariables = {
        ["EASYRSA_PKI"] = serverImpl.getEasyRSAPKiDir()
    };

    envVariables["EASYRSA_BATCH"] = 1;
    envVariables["EASYRSA_ALGO"] = "ed";
    envVariables["EASYRSA_CURVE"] = "ed25519";
    envVariables["EASYRSA_DIGEST"] = "sha512";
    envVariables["EASYRSA_PASSIN"] = "pass:"..serverImpl.getCAPass();

    local retCode = linux.exec_command_with_proc_ret_code("./"..linux.concatPaths(serverImpl.getEasyRSADir(), "/easyrsa").." gen-crl", nil, nil, envVariables);

    if retCode ~= 0 then
        return -1;
    end

    local crlPathInPKI = linux.concatPaths(serverImpl.getEasyRSAPKiDir(), "/crl.pem");
    local crlPathInOpenVPNDir = linux.concatPaths(serverImpl.get_openvpn_home_dir(), "/crl.pem");

    if not linux.copy(crlPathInPKI, crlPathInOpenVPNDir) then
        return -2;
    end

    return true;
end

function module.get_valid_clients()
    return validClients;
end

local function get_valid_clients_from_PKI_database()
    local retStr, retCode = linux.exec_command_with_proc_ret_code("cat "..linux.concatPaths(serverImpl.getEasyRSAPKiDir(), "/index.txt").." | awk '{if($1 == \"V\"){ print $5; } }' | awk -F '/CN=' '{print $2; }'", true);

    local validClients = {};

    for clientName in string.gmatch(retStr, "[^\r\n]+") do
        if clientName ~= serverImpl["openvpn_server_name_in_ca"] then
            table.insert(validClients, clientName);
        end
    end

    return validClients;
end

return function(openVPNServerImpl)
    serverImpl = openVPNServerImpl;

    for _, v in pairs(get_valid_clients_from_PKI_database()) do
        Client:new(v, true);
    end

    --[[
    for t, v in pairs(clientObjects) do
        print("config for "..tostring(t)..": "..tostring(v:generateClientConfig()));
    end

    local newClient = Client:new("teszt1234");
    newClient:genKeyAndCRT("teszt1234");
    ]]

    module.update_revoke_crl_for_openvpn_daemon();

    return module;
end;