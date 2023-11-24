local os = require("os");
local packageManager = require("apt_packages");
local linux = require("linux");
local general = require("general");
local inspect = require("inspect");
local config_handler = require("vpnHandler/OpenVPN_config_handler");
local bootstrapModule = false;

local module = {
    ["baseDir"] = "openvpn",
    ["easy_rsa_install_cache_dir"] = "easy_rsa_install_cache",
    ["easy_rsa_installation_dir"] = "easy_rsa",
    ["openvpn_user"] = "openvpn_serv",
    ["openvpn_user_comment"] = "OpenVPN server daemon's user",
    ["openvpn_user_shell"] = "/bin/false",
    ["openvpn_server_name_in_ca"] = "openvpn-server",
    ["client_handler"] = false,
    ["errors"] = {}
};

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

local caPass = "ca-pass";
local serverKeyPass = "server-key-pass";

function module.getEasyRSADir()
    return module.formatPathInsideBasedir(module["easy_rsa_installation_dir"]);
end

function module.getCAPass()
    return caPass;
end

function module.getOpenVPNBaseConfigDir()
    local retStr, retCode = linux.execCommandWithProcRetCode("cat /etc/init.d/openvpn | grep -m 1 \"CONFIG_DIR\" | awk -F '=' '{print $2}'", true);

    return retStr;
end

function module.isEasyRSAInstalled()
    if linux.isDir(module.getEasyRSADir()) and linux.exists(module.getEasyRSADir().."/installed.txt") then
        return true
    end

    return false
end

function module.formatPathInsideEasyRSAInstallCache(path)
    return module["easy_rsa_install_cache_dir"].."/"..path;
end

function module.formatPathInsideBasedir(path)
    return general.concatPaths(module["baseDir"], "/", path);
end

function module.initDirs()
    if not linux.isDir(module.baseDir) then
        if not linux.mkDir(module.baseDir) then
            return false;
        end
    end

    if not linux.isDir(module.easy_rsa_install_cache_dir) then
        if not linux.mkDir(module.easy_rsa_install_cache_dir) then
            return false;
        end
    end

    return true;
end

registerNewError("EASYRSA_DOWNLOAD_WGET_FAILED");
registerNewError("EASYRSA_MKDIR_FAILED");
registerNewError("EASYRSA_RM_FAILED");
registerNewError("EASYRSA_TAR_FAILED");
registerNewError("EASYRSA_MV_FAILED");
registerNewError("PACKAGE_INSTALL_FAIL");

function module.installEasyRSA()
    if module.isEasyRSAInstalled() then
        return true;
    end

    if not packageManager.installPackage("wget") or not packageManager.installPackage("tar") or not packageManager.installPackage("openssl") then
        return module.errors.PACKAGE_INSTALL_FAIL, 0;
    end

    local tgzOutput = module.formatPathInsideEasyRSAInstallCache("easyrsa.tgz");

    if linux.exists(tgzOutput) then
        if not linux.deleteFile(tgzOutput) then
            print("[OpenVPN init - installEasyRSA] couldn't delete file at "..tostring(tgzOutput));

            return module.errors.EASYRSA_RM_FAILED, 0;
        end
    end

    local retCodeForWget = linux.execCommandWithProcRetCode("wget https://github.com/OpenVPN/easy-rsa/releases/download/v3.1.2/EasyRSA-3.1.2.tgz -O "..tgzOutput);

    if retCodeForWget ~= 0 then
        print("[OpenVPN init - installEasyRSA] couldn't wget file");

        return module.errors.EASYRSA_DOWNLOAD_WGET_FAILED, retCodeForWget;
    end

    local outputDir = module.getEasyRSADir();

    local retCodeForMkdir = linux.mkDir(outputDir);

    if not retCodeForMkdir then
        print("[OpenVPN init - installEasyRSA] couldn't create directory at "..tostring(outputDir));

        return module.errors.EASYRSA_MKDIR_FAILED, retCodeForMkdir;
    end

    local retCodeForTar = linux.execCommandWithProcRetCode("tar -x --overwrite --directory "..outputDir.." -f "..tgzOutput);

    if retCodeForTar ~= 0 then
        print("[OpenVPN init - installEasyRSA] couldn't extract to directory at "..tostring(outputDir).." archive: "..tostring(tgzOutput));

        return module.errors.EASYRSA_TAR_FAILED, retCodeForTar;
    end

    local retCodeForMove = linux.execCommandWithProcRetCode("mv "..outputDir.."/*/* "..outputDir);

    if retCodeForMove ~= 0 then
        print("[OpenVPN init - installEasyRSA] couldn't move outputDir files");

        return module.errors.EASYRSA_MV_FAILED, retCodeForMove;
    end

    linux.execCommand("rmdir "..outputDir.."/EasyRSA-* && echo yes > "..outputDir.."/installed.txt");

    return true;
end

function module.getEasyRSAPKiDir()
    return module.getEasyRSADir().."/pki";
end

registerNewError("INIT_PKI_FAILED");
registerNewError("BUILD_CA_FAILED");
registerNewError("BUILD_SERVER_FULL_FAILED");
registerNewError("OPENSSL_VERIFY_FAILED");

function module.initEasyRSA()
    local easyRSADir = module.getEasyRSADir();
    local easyRSAPKIDir = module.getEasyRSAPKiDir();

    if not linux.isDir(easyRSAPKIDir) then
        local envVariables = {
            ["EASYRSA_PKI"] = easyRSAPKIDir
        };

        local retCode = linux.execCommandWithProcRetCode(easyRSADir.."/easyrsa init-pki", nil, envVariables, true);

        if retCode ~= 0 then
            return module.errors.INIT_PKI_CMD_FAILED;
        end

        envVariables["EASYRSA_PASSIN"] = "pass:"..caPass;
        envVariables["EASYRSA_PASSOUT"] = envVariables["EASYRSA_PASSIN"];
        envVariables["EASYRSA_BATCH"] = 1;
        envVariables["EASYRSA_REQ_CN"] = "Szakdolgozat Certificate Authority";
        envVariables["EASYRSA_REQ_COUNTRY"] = "HU";
        envVariables["EASYRSA_REQ_PROVINCE"] = "Borsod-Abauj-Zemplen";
        envVariables["EASYRSA_REQ_CITY"] = "Miskolc";
        envVariables["EASYRSA_REQ_ORG"] = "University of Miskolc";
        envVariables["EASYRSA_REQ_EMAIL"] = "cij404@student.uni-miskolc.hu";
        envVariables["EASYRSA_REQ_OU"] = "PTI";
        envVariables["EASYRSA_ALGO"] = "ed";
        envVariables["EASYRSA_CURVE"] = "ed25519";
        envVariables["EASYRSA_DIGEST"] = "sha512";

        local retCode = linux.execCommandWithProcRetCode(easyRSADir.."/easyrsa build-ca", nil, envVariables, true);

        if retCode ~= 0 then
            return module.errors.BUILD_CA_CMD_FAILED, retCode;
        end

        envVariables["EASYRSA_PASSOUT"] = "pass:"..serverKeyPass;

        envVariables["EASYRSA_REQ_CN"] = nil;

        local retCode = linux.execCommandWithProcRetCode(easyRSADir.."/easyrsa build-server-full "..tostring(module["openvpn_server_name_in_ca"]), nil, envVariables, true);

        if retCode ~= 0 then
            return module.errors.BUILD_SERVER_FULL_FAILED, retCode;
        end

        local retCode = linux.execCommandWithProcRetCode("openssl verify -CAfile "..envVariables["EASYRSA_PKI"].."/ca.crt "..envVariables["EASYRSA_PKI"].."/issued/"..tostring(module["openvpn_server_name_in_ca"])..".crt", nil, envVariables, true);

        if retCode ~= 0 then
            return module.errors.OPENSSL_VERIFY_FAILED, retCode;
        end
    else
        local envVariables = {
            ["EASYRSA_PKI"] = easyRSADir.."/pki"
        };

        local retCode = linux.execCommandWithProcRetCode("openssl verify -CAfile "..envVariables["EASYRSA_PKI"].."/ca.crt "..envVariables["EASYRSA_PKI"].."/issued/"..tostring(module["openvpn_server_name_in_ca"])..".crt", nil, envVariables, true);

        if retCode ~= 0 then
            return module.errors.OPENSSL_VERIFY_FAILED, retCode;
        end
    end

    return true
end

local sampleConfigFileContent = [[
    #################################################
    # Sample OpenVPN 2.0 config file for            #
    # multi-client server.                          #
    #                                               #
    # This file is for the server side              #
    # of a many-clients <-> one-server              #
    # OpenVPN configuration.                        #
    #                                               #
    # OpenVPN also supports                         #
    # single-machine <-> single-machine             #
    # configurations (See the Examples page         #
    # on the web site for more info).               #
    #                                               #
    # This config should work on Windows            #
    # or Linux/BSD systems.  Remember on            #
    # Windows to quote pathnames and use            #
    # double backslashes, e.g.:                     #
    # "C:\\Program Files\\OpenVPN\\config\\foo.key" #
    #                                               #
    # Comments are preceded with '#' or ';'         #
    #################################################
    
    # Which local IP address should OpenVPN
    # listen on? (optional)
    ;local a.b.c.d
    
    # Which TCP/UDP port should OpenVPN listen on?
    # If you want to run multiple OpenVPN instances
    # on the same machine, use a different port
    # number for each one.  You will need to
    # open up this port on your firewall.
    port 1194
    
    # TCP or UDP server?
    ;proto tcp
    proto udp
    
    #script-security 3
    #auth-user-pass-verify /etc/openvpn-panel/auth.sh via-file
    #verify-client-cert none
    #username-as-common-name
    
    # "dev tun" will create a routed IP tunnel,
    # "dev tap" will create an ethernet tunnel.
    # Use "dev tap0" if you are ethernet bridging
    # and have precreated a tap0 virtual interface
    # and bridged it with your ethernet interface.
    # If you want to control access policies
    # over the VPN, you must create firewall
    # rules for the the TUN/TAP interface.
    # On non-Windows systems, you can give
    # an explicit unit number, such as tun0.
    # On Windows, use "dev-node" for this.
    # On most systems, the VPN will not function
    # unless you partially or fully disable
    # the firewall for the TUN/TAP interface.
    ;dev tap
    dev tun
    
    # Windows needs the TAP-Win32 adapter name
    # from the Network Connections panel if you
    # have more than one.  On XP SP2 or higher,
    # you may need to selectively disable the
    # Windows firewall for the TAP adapter.
    # Non-Windows systems usually don't need this.
    ;dev-node MyTap
    
    crl-verify /root/EasyRSA-v3.0.6/pki/crl.pem
    
    # SSL/TLS root certificate (ca), certificate
    # (cert), and private key (key).  Each client
    # and the server must have their own cert and
    # key file.  The server and all clients will
    # use the same ca file.
    #
    # See the "easy-rsa" directory for a series
    # of scripts for generating RSA certificates
    # and private keys.  Remember to use
    # a unique Common Name for the server
    # and each of the client certificates.
    #
    # Any X509 key management system can be used.
    # OpenVPN can also use a PKCS #12 formatted key file
    # (see "pkcs12" directive in man page).
    ca /etc/openvpn/ca.crt
    cert /etc/openvpn/server.crt
    key /etc/openvpn/server.key  # This file should be kept secret
    askpass /etc/openvpn/asd.txt
    
    # Diffie hellman parameters.
    # Generate your own with:
    #   openssl dhparam -out dh2048.pem 2048
    # using tls-crypt & tls-ciphers & elliptic curve so DH is not needed
    dh none

    # Network topology
    # Should be subnet (addressing via IP)
    # unless Windows clients v2.0.9 and lower have to
    # be supported (then net30, i.e. a /30 per client)
    # Defaults to net30 (not recommended)
    topology subnet
    
    # Configure server mode and supply a VPN subnet
    # for OpenVPN to draw client addresses from.
    # The server will take 10.8.0.1 for itself,
    # the rest will be made available to clients.
    # Each client will be able to reach the server
    # on 10.8.0.1. Comment this line out if you are
    # ethernet bridging. See the man page for more info.
    server 10.8.0.0 255.255.255.0
    
    # Maintain a record of client <-> virtual IP address
    # associations in this file.  If OpenVPN goes down or
    # is restarted, reconnecting clients can be assigned
    # the same virtual IP address from the pool that was
    # previously assigned.
    ifconfig-pool-persist /var/log/openvpn/ipp.txt
    
    # Configure server mode for ethernet bridging.
    # You must first use your OS's bridging capability
    # to bridge the TAP interface with the ethernet
    # NIC interface.  Then you must manually set the
    # IP/netmask on the bridge interface, here we
    # assume 10.8.0.4/255.255.255.0.  Finally we
    # must set aside an IP range in this subnet
    # (start=10.8.0.50 end=10.8.0.100) to allocate
    # to connecting clients.  Leave this line commented
    # out unless you are ethernet bridging.
    ;server-bridge 10.8.0.4 255.255.255.0 10.8.0.50 10.8.0.100
    
    # Configure server mode for ethernet bridging
    # using a DHCP-proxy, where clients talk
    # to the OpenVPN server-side DHCP server
    # to receive their IP address allocation
    # and DNS server addresses.  You must first use
    # your OS's bridging capability to bridge the TAP
    # interface with the ethernet NIC interface.
    # Note: this mode only works on clients (such as
    # Windows), where the client-side TAP adapter is
    # bound to a DHCP client.
    ;server-bridge
    
    # Push routes to the client to allow it
    # to reach other private subnets behind
    # the server.  Remember that these
    # private subnets will also need
    # to know to route the OpenVPN client
    # address pool (10.8.0.0/255.255.255.0)
    # back to the OpenVPN server.
    ;push "route 192.168.10.0 255.255.255.0"
    ;push "route 192.168.20.0 255.255.255.0"
    
    # To assign specific IP addresses to specific
    # clients or if a connecting client has a private
    # subnet behind it that should also have VPN access,
    # use the subdirectory "ccd" for client-specific
    # configuration files (see man page for more info).
    
    # EXAMPLE: Suppose the client
    # having the certificate common name "Thelonious"
    # also has a small subnet behind his connecting
    # machine, such as 192.168.40.128/255.255.255.248.
    # First, uncomment out these lines:
    ;client-config-dir ccd
    ;route 192.168.40.128 255.255.255.248
    # Then create a file ccd/Thelonious with this line:
    #   iroute 192.168.40.128 255.255.255.248
    # This will allow Thelonious' private subnet to
    # access the VPN.  This example will only work
    # if you are routing, not bridging, i.e. you are
    # using "dev tun" and "server" directives.
    
    # EXAMPLE: Suppose you want to give
    # Thelonious a fixed VPN IP address of 10.9.0.1.
    # First uncomment out these lines:
    ;client-config-dir ccd
    ;route 10.9.0.0 255.255.255.252
    # Then add this line to ccd/Thelonious:
    #   ifconfig-push 10.9.0.1 10.9.0.2
    
    # Suppose that you want to enable different
    # firewall access policies for different groups
    # of clients.  There are two methods:
    # (1) Run multiple OpenVPN daemons, one for each
    #     group, and firewall the TUN/TAP interface
    #     for each group/daemon appropriately.
    # (2) (Advanced) Create a script to dynamically
    #     modify the firewall in response to access
    #     from different clients.  See man
    #     page for more info on learn-address script.
    ;learn-address ./script
    
    # If enabled, this directive will configure
    # all clients to redirect their default
    # network gateway through the VPN, causing
    # all IP traffic such as web browsing and
    # and DNS lookups to go through the VPN
    # (The OpenVPN server machine may need to NAT
    # or bridge the TUN/TAP interface to the internet
    # in order for this to work properly).
    #push "redirect-gateway def1 bypass-dhcp"
    
    # Certain Windows-specific network settings
    # can be pushed to clients, such as DNS
    # or WINS server addresses.  CAVEAT:
    # http://openvpn.net/faq.html#dhcpcaveats
    # The addresses below refer to the public
    # DNS servers provided by opendns.com.
    push "dhcp-option DNS 208.67.222.222"
    push "dhcp-option DNS 208.67.220.220"
    
    # Uncomment this directive to allow different
    # clients to be able to "see" each other.
    # By default, clients will only see the server.
    # To force clients to only see the server, you
    # will also need to appropriately firewall the
    # server's TUN/TAP interface.
    client-to-client
    
    # Uncomment this directive if multiple clients
    # might connect with the same certificate/key
    # files or common names.  This is recommended
    # only for testing purposes.  For production use,
    # each client should have its own certificate/key
    # pair.
    #
    # IF YOU HAVE NOT GENERATED INDIVIDUAL
    # CERTIFICATE/KEY PAIRS FOR EACH CLIENT,
    # EACH HAVING ITS OWN UNIQUE "COMMON NAME",
    # UNCOMMENT THIS LINE OUT.
    ;duplicate-cn
    
    # The keepalive directive causes ping-like
    # messages to be sent back and forth over
    # the link so that each side knows when
    # the other side has gone down.
    # Ping every 10 seconds, assume that remote
    # peer is down if no ping received during
    # a 120 second time period.
    keepalive 10 120
    
    # For extra security beyond that provided
    # by SSL/TLS, create an "HMAC firewall"
    # to help block DoS attacks and UDP port flooding.
    #
    # Generate with:
    #   openvpn --genkey tls-auth ta.key
    #
    # The server and each client must have
    # a copy of this key.
    # The second parameter should be '0'
    # on the server and '1' on the clients.
    tls-crypt /etc/openvpn/ta.key # This file is secret
    
    auth Whirlpool
    auth-nocache
    tls-server
    remote-cert-tls client
    
    # Select a cryptographic cipher.
    # This config item must be copied to
    # the client config file as well.
    # Note that v2.4 client/server will automatically
    # negotiate AES-256-GCM in TLS mode.
    # See also the ncp-cipher option in the manpage
    tls-cipher TLS-ECDHE-ECDSA-WITH-AES-256-GCM-SHA384
    tls-version-min 1.2
    cipher AES-256-GCM
    chroot /home/samplepath
    
    # Enable compression on the VPN link and push the
    # option to the client (v2.4+ only, for earlier
    # versions see below)
    ;compress lz4-v2
    ;push "compress lz4-v2"
    
    # For compression compatible with older clients use comp-lzo
    # If you enable it here, you must also
    # enable it in the client config file.
    ;comp-lzo
    
    # The maximum number of concurrently connected
    # clients we want to allow.
    ;max-clients 100
    
    # It's a good idea to reduce the OpenVPN
    # daemon's privileges after initialization.
    #
    # You can uncomment this out on
    # non-Windows systems.
    user nobody
    group nogroup
    
    # The persist options will try to avoid
    # accessing certain resources on restart
    # that may no longer be accessible because
    # of the privilege downgrade.
    persist-key
    persist-tun
    
    # Output a short status file showing
    # current connections, truncated
    # and rewritten every minute.
    status /var/log/openvpn/openvpn-status.log
    
    # By default, log messages will go to the syslog (or
    # on Windows, if running as a service, they will go to
    # the "\Program Files\OpenVPN\log" directory).
    # Use log or log-append to override this default.
    # "log" will truncate the log file on OpenVPN startup,
    # while "log-append" will append to it.  Use one
    # or the other (but not both).
    ;log         /var/log/openvpn/openvpn.log
    log-append  /var/log/openvpn/openvpn.log
    
    # Set the appropriate level of log
    # file verbosity.
    #
    # 0 is silent, except for fatal errors
    # 4 is reasonable for general usage
    # 5 and 6 can help to debug connection problems
    # 9 is extremely verbose
    verb 3
    
    # Silence repeating messages.  At most 20
    # sequential messages of the same message
    # category will be output to the log.
    ;mute 20
    
    # Notify the client that when the server restarts so it
    # can automatically reconnect.
    explicit-exit-notify 1    
]];

function module.enableAllAutostartInDefault()
    return linux.execCommandWithProcRetCode("sed -i 's/#AUTOSTART=\"all\"/AUTOSTART=\"all\"/g' /etc/default/openvpn");
end

registerNewError("CRLPEM_HANDLE_OPEN_FAIL");
registerNewError("CRLPEM_CHOWN_FAIL");
registerNewError("CRLPEM_CHMOD_FAIL");
registerNewError("ASKPASS_HANDLE_FAIL");
registerNewError("ASKPASS_CHOWN_FAIL");
registerNewError("ASKPASS_CHMOD_FAIL");
registerNewError("CACRT_COPYCHOWN_FAIL");
registerNewError("OPENVPN_CRT_COPYCHOWN_FAIL");
registerNewError("OPENVPN_KEY_COPYCHOWN_FAIL");
registerNewError("CONFIG_FILE_HANDLE_FAIL");
registerNewError("OPENVPN_GENKEY_FAIL");
registerNewError("TMPDIR_CR_FAIL");
registerNewError("TMPDIR_CHOWN_FAIL");
registerNewError("TLSAUTH_CHOWN_FAIL");
registerNewError("TMPDIR_CHMOD_FAIL");

local function getConfigFilePath(openVPNConfigDir)
    return general.concatPaths(openVPNConfigDir, "/server_"..tostring(module["openvpn_user"])..".conf");
end

function module.getOpenVPNSubnet()
    if not module.client_handler then
        return false;
    end

    local configFilePath = getConfigFilePath(module.getOpenVPNBaseConfigDir());

    local fileContent = general.readAllFileContents(configFilePath);

    if not fileContent then
        return false;
    end

    local configFileContent, paramsToLines = config_handler.parseOpenVPNConfig(fileContent);

    if not configFileContent then
        return false;
    end

    if paramsToLines["server"] then
        local serverData = configFileContent[paramsToLines["server"]];
        local params = serverData.params;

        if params[1] and params[2] and params[3] then
            return params[2].val;
        end
    end

    return false;
end

function module.checkServerConfig(homeDir, openVPNConfigDir)
    local pwd = linux.execCommand("pwd"):gsub("%s+", "");

    local configFilePath = getConfigFilePath(openVPNConfigDir);

    local tlsAuthKeyPath = general.concatPaths(homeDir, "/ta.key");

    local crlPemPath = general.concatPaths(homeDir, "/crl.pem");

    if not linux.exists(crlPemPath) then
        local crlPemHandle = io.open(crlPemPath, "wb");

        if not crlPemHandle then
            print("[OpenVPN init - checkServerConfig] couldn't open PEM handle at "..tostring(crlPemPath));

            return module.errors.CRLPEM_HANDLE_OPEN_FAIL;
        end

        crlPemHandle:write("");
        crlPemHandle:flush();
        crlPemHandle:close();

        if not linux.chown(crlPemPath, module["openvpn_user"]) then
            print("[OpenVPN init - checkServerConfig] couldn't chown PEM file at "..tostring(crlPemPath));

            return module.errors.CRLPEM_CHOWN_FAIL;
        end
    end

    if not linux.chmod(crlPemPath, 700) then
        print("[OpenVPN init - checkServerConfig] couldn't chmod PEM file at "..tostring(crlPemPath));

        return module.errors.CRLPEM_CHMOD_FAIL;
    end

    local askPassPath = general.concatPaths(homeDir, "/openvpn-server.txt");

    if not linux.exists(askPassPath) then
        local askPassHandle = io.open(askPassPath, "wb");

        if not askPassHandle then
            print("[OpenVPN init - checkServerConfig] couldn't open askpass handle at "..tostring(askPassPath));

            return module.errors.ASKPASS_HANDLE_FAIL;
        end

        askPassHandle:write(serverKeyPass);
        askPassHandle:flush();
        askPassHandle:close();
    end

    if not linux.chown(askPassPath, module["openvpn_user"]) then
        print("[OpenVPN init - checkServerConfig] couldn't chown askpass file at "..tostring(askPassPath));

        return module.errors.ASKPASS_CHOWN_FAIL;
    end

    if not linux.chmod(askPassPath, 700) then
        print("[OpenVPN init - checkServerConfig] couldn't chmod askpass file at "..tostring(askPassPath));

        return module.errors.ASKPASS_CHMOD_FAIL;
    end

    if not linux.exists(configFilePath) then
        local configFileContent, paramsToLines = config_handler.parseOpenVPNConfig(sampleConfigFileContent);

        if paramsToLines["crl-verify"] then
            local paramTbl = configFileContent[paramsToLines["crl-verify"]];

            paramTbl["params"][2].val = "crl.pem";
        end

        if paramsToLines["ca"] then
            local paramTbl = configFileContent[paramsToLines["ca"]];

            local origCrtPathInPKI = general.concatPaths(pwd, module.getEasyRSAPKiDir(), "/ca.crt");
            local crtPathInsideHome = general.concatPaths(homeDir, "/ca.crt");

            if not linux.copyAndChown(module["openvpn_user"], origCrtPathInPKI, crtPathInsideHome) then
                print("[OpenVPN init - checkServerConfig] couldn't copy & chown pki ca.crt file to "..tostring(crtPathInsideHome));

                return module.errors.CACRT_COPYCHOWN_FAIL;
            end

            paramTbl["params"][2].val = crtPathInsideHome;
        end

        if paramsToLines["cert"] then
            local paramTbl = configFileContent[paramsToLines["cert"]];

            local origCrtPathInPKI = general.concatPaths(pwd, module.getEasyRSAPKiDir(), "issued", "/"..tostring(module["openvpn_server_name_in_ca"])..".crt");
            local crtPathInsideHome = general.concatPaths(homeDir, "/"..tostring(module["openvpn_server_name_in_ca"])..".crt");

            if not linux.copyAndChown(module["openvpn_user"], origCrtPathInPKI, crtPathInsideHome) then
                print("[OpenVPN init - checkServerConfig] couldn't copy & chown pki server crt file to "..tostring(crtPathInsideHome));

                return module.errors.OPENVPN_CRT_COPYCHOWN_FAIL;
            end

            paramTbl["params"][2].val = crtPathInsideHome;
        end

        if paramsToLines["key"] then
            local paramTbl = configFileContent[paramsToLines["key"]];

            local origKeyPathInPKI = general.concatPaths(pwd, module.getEasyRSAPKiDir(), "private", "/"..tostring(module["openvpn_server_name_in_ca"])..".key");
            local keyPathInsideHome = general.concatPaths(homeDir, "/"..tostring(module["openvpn_server_name_in_ca"])..".key");

            if not linux.copyAndChown(module["openvpn_user"], origKeyPathInPKI, keyPathInsideHome) then
                print("[OpenVPN init - checkServerConfig] couldn't copy & chown server key file to "..tostring(keyPathInsideHome));

                return module.errors.OPENVPN_KEY_COPYCHOWN_FAIL;
            end

            paramTbl["params"][2].val = keyPathInsideHome;
        end

        if paramsToLines["askpass"] then
            local paramTbl = configFileContent[paramsToLines["askpass"]];

            paramTbl["params"][2].val = askPassPath;
        end

        if paramsToLines["tls-crypt"] then
            local paramTbl = configFileContent[paramsToLines["tls-crypt"]];

            paramTbl["params"][2].val = tlsAuthKeyPath;
        end

        if paramsToLines["user"] then
            local paramTbl = configFileContent[paramsToLines["user"]];

            paramTbl["params"][2].val = module["openvpn_user"];
        end

        if paramsToLines["group"] then
            local paramTbl = configFileContent[paramsToLines["group"]];

            paramTbl["params"][2].val = module["openvpn_user"];
        end

        if paramsToLines["chroot"] then
            local paramTbl = configFileContent[paramsToLines["chroot"]];

            paramTbl["params"][2].val = homeDir;
        end

        local configFileHandle = io.open(configFilePath, "wb");

        if not configFileHandle then
            print("[OpenVPN init - checkServerConfig] couldn't open config file handle at "..tostring(configFilePath));

            return module.errors.CONFIG_FILE_HANDLE_FAIL;
        end

        configFileHandle:write(config_handler.writeOpenVPNConfig(configFileContent));
        configFileHandle:flush();
        configFileHandle:close();
    end

    if not linux.exists(tlsAuthKeyPath) then
        local retCode = linux.execCommandWithProcRetCode("openvpn --genkey tls-auth "..tlsAuthKeyPath);

        if retCode ~= 0 then
            print("[OpenVPN init - checkServerConfig] couldn't do tls-auth genkey to "..tostring(tlsAuthKeyPath));

            return module.errors.OPENVPN_GENKEY_FAIL;
        end
    end

    local tmpDirForOpenVPN = general.concatPaths(homeDir, "tmp");

    if not linux.isDir(tmpDirForOpenVPN) then
        if not linux.mkDir(tmpDirForOpenVPN) then
            print("[OpenVPN init - checkServerConfig] couldn't create dir at "..tostring(tmpDirForOpenVPN));

            return module.errors.TMPDIR_CR_FAIL;
        end
    end

    if not linux.chown(tmpDirForOpenVPN, module["openvpn_user"], true) then
        print("[OpenVPN init - checkServerConfig] couldn't chown dir at "..tostring(tmpDirForOpenVPN));

        return module.errors.TMPDIR_CHOWN_FAIL;
    end

    if not linux.chown(tlsAuthKeyPath, module["openvpn_user"]) then
        print("[OpenVPN init - checkServerConfig] couldn't chown file at "..tostring(tlsAuthKeyPath));

        return module.errors.TLSAUTH_CHOWN_FAIL;
    end

    if not linux.chmod(tmpDirForOpenVPN, 700) then
        print("[OpenVPN init - checkServerConfig] couldn't chmod tmp dir at "..tostring(tmpDirForOpenVPN));

        return module.errors.TMPDIR_CHMOD_FAIL;
    end

    return true;
end

function module.checkOpenVPNUserExistence()
    return linux.checkIfUserExists(module["openvpn_user"]);
end

function module.createOpenVPNUser(homeDir)
    return linux.createUserWithName(module["openvpn_user"], module["openvpn_user_comment"], module["openvpn_user_shell"], homeDir);
end

function module.updateExistingOpenVPNUser()
    return linux.updateUser(module["openvpn_user"], module["openvpn_user_comment"], module["openvpn_user_shell"]);
end

function module.getOpenVPNHomeDir()
    return linux.getUserHomeDir(module["openvpn_user"]);
end

registerNewError("EASYRSA_INSTALL_ERROR");
registerNewError("EASYRSA_INIT_ERROR");
registerNewError("USER_CREATION_ERROR");
registerNewError("USER_UPDATE_ERROR");
registerNewError("SERVER_CONFIG_CHECK_ERROR");
registerNewError("ENABLE_AUTOSTART_ERROR");
registerNewError("DAEMON_RELOAD_AND_RESTART_ERROR");

function module.initializeServer()
    local retOfEasyRSAInstall, additionalError = module.installEasyRSA();

    if retOfEasyRSAInstall ~= true then
        return module.errors.EASYRSA_INSTALL_ERROR, retOfEasyRSAInstall, additionalError;
    end

    local easyRsaInitRet, additionalError = module.initEasyRSA();

    if easyRsaInitRet ~= true then
        return module.errors.EASYRSA_INIT_ERROR, easyRsaInitRet, additionalError;
    end

    local openVPNConfigDir = module.getOpenVPNBaseConfigDir();

    local homeOfOpenVPNUser = general.concatPaths(openVPNConfigDir, "h_"..module["openvpn_user"]);

    local openVPNUser = module.checkOpenVPNUserExistence();

    if not openVPNUser then
        local creationRet = module.createOpenVPNUser(homeOfOpenVPNUser);

        if not creationRet then
            return module.errors.USER_CREATION_ERROR, creationRet;
        end
    else
        local updateRet = module.updateExistingOpenVPNUser();

        if not updateRet then
            return module.errors.USER_UPDATE_ERROR, updateRet;
        end
    end

    local serverConfigCheck = module.checkServerConfig(homeOfOpenVPNUser, openVPNConfigDir);

    if serverConfigCheck ~= true then
        return module.errors.SERVER_CONFIG_CHECK_ERROR, serverConfigCheck;
    end

    local autoStartEnable = module.enableAllAutostartInDefault();

    if autoStartEnable ~= 0 then
        return module.errors.ENABLE_AUTOSTART_ERROR, autoStartEnable;
    end

    if not linux.systemctlDaemonReload() then
        return module.errors.DAEMON_RELOAD_AND_RESTART_ERROR, 0;
    end

    if bootstrapModule.isRunning() and not linux.restartService("openvpn") then
        return module.errors.DAEMON_RELOAD_AND_RESTART_ERROR, 1;
    end

    if not module.client_handler then
        module["client_handler"] = require("vpnHandler/OpenVPN_clienthandler_impl")(module);
    end

    return true;
end

return function(_bootstrapModule)
    bootstrapModule = _bootstrapModule;

    module.isRunning = bootstrapModule.isRunning;
    module.stopServer = bootstrapModule.stopServer;
    module.startServer = bootstrapModule.startServer;

    return module;
end
