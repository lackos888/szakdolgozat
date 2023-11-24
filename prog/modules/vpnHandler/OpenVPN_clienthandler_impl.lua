local linux = require("linux");
local general = require("general");
local utils = require("utils");
local config_handler = require("vpnHandler/OpenVPN_config_handler");

local module = {
    errors = {}
};
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
tls-cipher TLS-ECDHE-ECDSA-WITH-AES-256-GCM-SHA384 
tls-version-min 1.2 
cipher AES-256-GCM
tls-client
setenv opt block-outside-dns
verb 3]];

local errorCounter = 0;
local function registerNewError(errorName)
    errorCounter = errorCounter + 1;

    module.errors[errorName] = errorCounter * -1;

    return true;
end

function module.resolveErrorToStr(error)
    for t, v in pairs(module.errors) do
        if tostring(v) == tostring(error) then
            return t;
        end 
    end

    return "";
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

registerNewError("BUILD_CLIENT_FULL_FAIL");
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

    local retCode = linux.execCommandWithProcRetCode("./"..general.concatPaths(serverImpl.getEasyRSADir(), "/easyrsa").." build-client-full "..self["name"], nil, envVariables);

    if retCode ~= 0 then
        return module.errors.BUILD_CLIENT_FULL_FAIL, retCode;
    end

    validClients[self["name"]] = true;

    return true;
end

registerNewError("CANNOT_READ_SERVER_CA_CRT");
registerNewError("CANNOT_READ_CLIENT_CA_CRT");
registerNewError("CANNOT_READ_CLIENT_KEY");
registerNewError("CANNOT_READ_TLS_CRYPT_KEY");

function Client:generateClientConfig()
    if not self:isValidClient() then
        return false;
    end

    local configFileContent, paramsToLines = config_handler.parseOpenVPNConfig(clientSampleConfig);

    if paramsToLines["remote"] then
        local paramTbl = configFileContent[paramsToLines["remote"]];

        paramTbl["params"][2].val = "IP_CIM_CSERE_HELYE"; --test IP
        paramTbl["params"][3].val = 1194; --test Port
    end

    local clientConfig = config_handler.writeOpenVPNConfig(configFileContent);

    local serverCAPath = general.concatPaths(serverImpl.getEasyRSAPKiDir(), "/issued/"..serverImpl["openvpn_server_name_in_ca"]..".crt");

    local clientCAPath = general.concatPaths(serverImpl.getEasyRSAPKiDir(), "/issued/"..self["name"]..".crt");

    local clientKeyPath = general.concatPaths(serverImpl.getEasyRSAPKiDir(), "/private/"..self["name"]..".key");

    local tlsCryptKeyPath = general.concatPaths(serverImpl.getOpenVPNHomeDir(), "/ta.key");

    local serverCACrt = general.readAllFileContents(serverCAPath);

    if not serverCACrt then
        return module.errors.CANNOT_READ_SERVER_CA_CRT;
    end

    local clientCACrt = general.readAllFileContents(clientCAPath);

    if not clientCACrt then
        return module.errors.CANNOT_READ_CLIENT_CA_CRT;
    end

    local clientKey = general.readAllFileContents(clientKeyPath);

    if not clientKey then
        return module.errors.CANNOT_READ_CLIENT_KEY;
    end

    local tlsCryptKey = general.readAllFileContents(tlsCryptKeyPath);

    if not tlsCryptKey then
        return module.errors.CANNOT_READ_TLS_CRYPT_KEY;
    end

    clientConfig = clientConfig.."<ca>\n"..serverCACrt.."</ca>\n";
    clientConfig = clientConfig.."<cert>\n"..clientCACrt.."</cert>\n";
    clientConfig = clientConfig.."<key>\n"..clientKey.."</key>\n";
    clientConfig = clientConfig.."<tls-crypt>\n"..tlsCryptKey.."</tls-crypt>\n";

    return true, clientConfig;
end

registerNewError("REVOKE_FAIL");
registerNewError("REVOKE_CRL_UPDATE_FAIL");
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

    local retCode = linux.execCommandWithProcRetCode("./"..general.concatPaths(serverImpl.getEasyRSADir(), "/easyrsa").." revoke "..self["name"], nil, envVariables);

    if retCode ~= 0 and retCode ~= 1 then
        return module.errors.REVOKE_FAIL;
    end

    if not module.updateRevokeCRLForOpenVPNDaemon() then
        return module.errors.REVOKE_CRL_UPDATE_FAIL;
    end

    validClients[self["name"]] = nil;
    clientObjects[self["name"]] = nil;

    return true;
end

function Client:isValidClient()
    return validClients[self["name"]] == true;
end

registerNewError("GEN_CRL_FAILED");
registerNewError("CRL_COPY_FAILED");

function module.updateRevokeCRLForOpenVPNDaemon()
    local envVariables = {
        ["EASYRSA_PKI"] = serverImpl.getEasyRSAPKiDir()
    };

    envVariables["EASYRSA_BATCH"] = 1;
    envVariables["EASYRSA_ALGO"] = "ed";
    envVariables["EASYRSA_CURVE"] = "ed25519";
    envVariables["EASYRSA_DIGEST"] = "sha512";
    envVariables["EASYRSA_PASSIN"] = "pass:"..serverImpl.getCAPass();

    local retCode = linux.execCommandWithProcRetCode("./"..general.concatPaths(serverImpl.getEasyRSADir(), "/easyrsa").." gen-crl", nil, envVariables);

    if retCode ~= 0 then
        return module.errors.GEN_CRL_FAILED;
    end

    local crlPathInPKI = general.concatPaths(serverImpl.getEasyRSAPKiDir(), "/crl.pem");
    local crlPathInOpenVPNDir = general.concatPaths(serverImpl.getOpenVPNHomeDir(), "/crl.pem");

    if not linux.copy(crlPathInPKI, crlPathInOpenVPNDir) then
        return module.errors.CRL_COPY_FAILED;
    end

    return true;
end

function module.getValidClients()
    if validClients then
        local ret = {};

        for t, v in pairs(validClients) do
            table.insert(ret, t);
        end

        return ret;
    end

    return false;
end

local function getValidClientsFromPKIDatabase()
    local retStr, retCode = linux.execCommandWithProcRetCode("cat "..general.concatPaths(serverImpl.getEasyRSAPKiDir(), "/index.txt").." | awk '{if($1 == \"V\"){ print $5; } }' | awk -F '/CN=' '{print $2; }'", true);

    local validClientsFromPKI = {};

    for clientName in string.gmatch(retStr, "[^\r\n]+") do
        if clientName ~= serverImpl["openvpn_server_name_in_ca"] then
            table.insert(validClientsFromPKI, clientName);
        end
    end

    return validClientsFromPKI;
end

return function(openVPNServerImpl)
    serverImpl = openVPNServerImpl;

    for _, v in pairs(getValidClientsFromPKIDatabase()) do
        Client:new(v, true);
    end

    --[[
    for t, v in pairs(clientObjects) do
        print("config for "..tostring(t)..": "..tostring(v:generateClientConfig()));
    end

    local newClient = Client:new("teszt1234");
    newClient:genKeyAndCRT("teszt1234");
    ]]

    module.updateRevokeCRLForOpenVPNDaemon();

    return module;
end;