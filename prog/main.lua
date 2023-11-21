package.path = package.path..";modules/?.lua";

--import handlers
local OpenVPNHandler = require("vpnHandler/OpenVPN");
local nginxHandler = require("nginxHandler/nginx");
local apacheHandler = require("apacheHandler/apache");
local nginxConfigHandlerObject = require("nginxHandler/nginx_config_handler");
local certbotHandler = require("certbotHandler/certbot");
local iptables = require("iptablesHandler/iptables");
local certbot = require("certbotHandler/certbot");
local general = require("general");
local inspect = require("inspect");
local function doOpenVPNInstall(OpenVPNHandler)
    print("==> Elkezdődött az OpenVPN szerver telepítése, kérlek várj...");

    local installRet, aptRet = OpenVPNHandler.install_openvpn();

    if installRet then
        print("==> Sikeresen feltelepítésre került az OpenVPN szerver. Nyomjon ENTER-t a folytatáshoz.");
    else
        print("==> Hiba történt az OpenVPN szerver feltelepítése közben. Nyomjon ENTER-t a folytatáshoz.");
        print(tostring(aptRet));
    end
    io.read();
end

local function doOpenVPNStartStop(isRunning, OpenVPNHandler)
    local func = isRunning and OpenVPNHandler.stop_server or OpenVPNHandler.start_server;

    if isRunning then
        if func() then
            print("==> Leállításra került az OpenVPN szerver. Nyomjon ENTER-t a folytatáshoz.");
        else
            print("==> Hiba történt az OpenVPN szerver leállítása közben. Nyomjon ENTER-t a folytatáshoz.");
        end
    else
        if func() then
            print("==> Elindításra került az OpenVPN szerver. Nyomjon ENTER-t a folytatáshoz.");
        else
            print("==> Hiba történt az OpenVPN szerver elindítása közben. Nyomjon ENTER-t a folytatáshoz.");
        end
    end
    io.read();
end

local function doOpenVPNInitOrRefresh(isRunning, serverImpl)
    print("==> Szerver inicializálása folyamatban...");

    if isRunning then
        serverImpl.stop_server();
    end

    local retOfInitDirs = serverImpl.init_dirs();
    local retOfInitialize, possibleError, possibleError2 = false, false, false; --elore definialas a goto miatt

    if not retOfInitDirs then
        print("==> Nem sikerült az OpenVPN könyvtárának inicializálása! Nyomjon ENTER-t a folytatáshoz.");

        goto serverInitGoto;
    end

    retOfInitialize, possibleError, possibleError2 = serverImpl.initialize_server();

    if isRunning then
        serverImpl.start_server();
    end

    if retOfInitialize ~= true then
        print("==> Hiba történt az OpenVPN szerver initializálása, konfigurálása közben. Nyomjon ENTER-t a folytatáshoz.");
        print("Hiba: "..tostring(serverImpl.resolveErrorToStr(retOfInitialize)));
        print("Hiba #2: "..tostring(serverImpl.resolveErrorToStr(possibleError)));
        print("Hiba #3: "..tostring(serverImpl.resolveErrorToStr(possibleError2)));
    else
        print("==> Sikeresen beinicializálásra és bekonfigurálásra került az OpenVPN szerver. Nyomjon ENTER-t a folytatáshoz.");
    end
    ::serverInitGoto::
    io.read();
end

local function doOpenVPNClientListing(serverImpl)
    general.clearScreen();
    serverImpl.init_dirs();
    serverImpl.initialize_server();

    local clientHandler = serverImpl.client_handler;

    if not clientHandler then
        print("Nem sikerült lekérdezni a klienseket, mivel még nincs beinicializálva az OpenVPN szerver. Próbálkozzon a konfiguráció frissítésével!");
        print("Nyomjon ENTER-t a folytatáshoz.");

        goto openvpn_clients_continue;
    end

    ::openvpn_clients_continue::
    while true do
        general.clearScreen();

        local validClients = clientHandler.get_valid_clients();

        print("<==> OpenVPN BEKONFIGURÁLT KLIENSEK <==>");

        if #validClients == 0 then
            print("Nincs egyetlen bekonfigurált kliens sem, amely hozzáféréssel rendelkezik még. Nyomjon ENTER-t a folytatáshoz.");
        else
            print("Visszalépéshez nyomjon ENTER-t.");

            for t, v in pairs(validClients) do
                print("=> "..tostring(t)..".: "..tostring(v));
            end
        end

        if #validClients > 0 then
            print("Amelyik klienst kezelni szeretné, írja be a számát:");
        end
        
        readStr = io.read();

        if readStr == " " or #readStr == 0 then
            break;
        end

        if validClients and #validClients ~= 0 then
            local clientName = validClients[tonumber(readStr)];

            if not clientName then
                print("=> Hibás sorszám: "..tostring(readStr));
            else
                local clientInstance = Client:new(clientName);
                if not clientInstance:isValidClient() then
                    print("=> Nem teljes értékű, hibás kliens: "..tostring(clientName));
                else
                    local clientSelected = clientInstance;

                    while true do
                        general.clearScreen();
                        print("=> Ön a(z) "..tostring(clientSelected.name).." nevű klienst választotta. A lehetőségei:");
                        local innerCounter = 1;
                        local printOptionAndIncreaseCounter = function(str)
                            print(str);
                            innerCounter = innerCounter + 1;
                        end
                        printOptionAndIncreaseCounter(tostring(innerCounter)..". Kliens konfigurációjának kiiratása");
                        printOptionAndIncreaseCounter(tostring(innerCounter)..". Kliens hozzáférésének visszavonása");
                        printOptionAndIncreaseCounter(tostring(innerCounter)..". Visszalépés");
                        
                        local str = io.read();
                        local firstChar = str:sub(1, 1);

                        if firstChar == tostring(innerCounter - 1) then
                            break;
                        end

                        if firstChar == "1" then
                            local retOfClientConfigBuild, cfg = clientInstance:generateClientConfig();

                            if retOfClientConfigBuild == true then
                                print("=> A(z) "..tostring(clientSelected.name).." kliens konfigurációja:");
                                print(cfg);
                                print("Nyomjon ENTER-t a folytatáshoz.");
                            else
                                print("=> A(z) "..tostring(clientSelected.name).." kliens konfigurációjának lekérdezése közben hiba történt!");
                                print("Hiba: "..tostring(clientHandler.resolveErrorToStr(retOfClientConfigBuild)));
                                print("Nyomjon ENTER-t a folytatáshoz.");
                            end
                            io.read();
                        elseif firstChar == "2" then
                            local retOfRevoke = clientInstance:revoke();

                            if retOfRevoke == true then
                                print("=> A(z) "..tostring(clientSelected.name).." kliens hozzáférése visszavonásra került! Nyomjon ENTER-t a folytatáshoz.");
                                io.read();
                                break;
                            else
                                print("=> A(z) "..tostring(clientSelected.name).." kliens hozzáférésének visszavonása közben hiba történt! Nyomjon ENTER-t a folytatáshoz.");
                                print("Hiba: "..tostring(clientHandler.resolveErrorToStr(retOfRevoke)));
                                io.read();
                            end
                        end
                    end
                end
            end
        end
    end
end

local function doOpenVPNClientCreation(serverImpl)
    general.clearScreen();
    serverImpl.init_dirs();
    serverImpl.initialize_server();

    local clientHandler = serverImpl.client_handler;
    local clientInstance = false;
    local ret, possibleError = false;

    local clientName = false;
    local pass = false;

    if not clientHandler then
        print("Nem sikerült lekérdezni a klienseket, mivel még nincs beinicializálva az OpenVPN szerver. Próbálkozzon a konfiguráció frissítésével!");
        print("Nyomjon ENTER-t a folytatáshoz.");

        goto openvpn_newclient_continue;
    end

    print("<==> OpenVPN új kliens bekonfigurálása <==>");

    while true do
        print("Adja meg az új kliens nevét:");

        clientName = io.read();

        if #clientName == 0 or clientName == " " then
            print("Üres szöveget nem adhat meg. Nyomjon ENTER-t a továbblépéshez.");

            goto openvpn_newclient_continue;
        end

        if clientName:match("%W") then
            print("=> Kizárólag alfanumerikus lehet az új kliens neve...");
        else
            break;
        end
    end

    while true do
        print("Adja meg a kliens kulcsának jelszavát:");

        pass = io.read();

        if #pass == 0 or pass == " " then
            print("=> Nem lehet üres a jelszó!");
        else
            break;
        end
    end

    general.clearScreen();

    print("<==> OpenVPN új kliens bekonfigurálása: "..tostring(clientName).."<==>");

    clientInstance = Client:new(clientName);
    ret, possibleError = clientInstance:genKeyAndCRT(pass);

    if ret == true then
        print("Sikeresen létrehozásra került a(z) "..tostring(clientName).." nevű kliens!");

        local possibleError, retOfClientConfig = clientInstance:generateClientConfig();

        if possibleError == true then
            print("=> A kliens konfigurációja: ");
            print(tostring(retOfClientConfig));
            print("Ne felejtse el kicserélni a konfigurációban az IP-címet a megfelelő IP címre!");
        else
            print("=> Hiba történt a kliens konfigurációjának generálása közben: "..tostring(clientHandler.resolveErrorToStr(possibleError)));
        end
        print("Nyomjon ENTER-t a folytatáshoz.");
    else
        print("Nem sikerült létrehozni a(z) "..tostring(clientName).." nevű klienst. Hiba: "..tostring(clientHandler.resolveErrorToStr(ret)));
    end

    ::openvpn_newclient_continue::
    io.read();
end

local function doWebserverMenu(webserverType)
    while true do
        general.clearScreen();

        local webserverBootstrapModule = webserverType == "apache" and apacheHandler or nginxHandler;

        local isInstalled = webserverBootstrapModule.is_installed();
        local isRunning = webserverBootstrapModule.is_running();
        local serverImpl = webserverBootstrapModule.server_impl;
        local errors = serverImpl.errors;

        local counter = 1;
        local printOptionAndIncreaseCounter = function(str)
            print(str);
            counter = counter + 1;
        end

        local readStr = "";
        local firstChar = "";

        local currentWebserverType = tostring(webserverType == "apache" and "Apache" or "nginx");

        print("<=> "..currentWebserverType.." szerver <=>");

        if not isInstalled then
            printOptionAndIncreaseCounter("=> "..tostring(counter)..". Feltelepítés");
        else
            printOptionAndIncreaseCounter("=> "..tostring(counter)..". "..tostring(isRunning and "Leállítás" or "Elindítás"));
            printOptionAndIncreaseCounter("=> "..tostring(counter)..". Jelenlegi weboldalak kezelése");
            printOptionAndIncreaseCounter("=> "..tostring(counter)..". Új weboldal létrehozása");
        end

        printOptionAndIncreaseCounter(""..tostring(counter)..". Visszalépés");

        readStr = io.read();
        firstChar = readStr:sub(1, 1);

        if firstChar == tostring(counter - 1) then
            break;
        end

        if not isInstalled then
            if firstChar == "1" then --install
                general.clearScreen();
                print("=> "..tostring(webserverType).." telepítésének megkezdése...");

                local installRet, additionalError = webserverBootstrapModule.install();

                if installRet then
                    print("A(z) "..tostring(webserverType).." webszerver sikeresen telepítésre került. Nyomjon ENTER-t a folytatáshoz.");
                else
                    print("Nem sikerült felrakni a(z) "..tostring(webserverType).." webszervert!");
                    print(tostring(additionalError));
                    print("Nyomjon ENTER-t a folytatáshoz.");
                end

                io.read();
            end
        else
            if firstChar == "1" then --start/stop
                general.clearScreen();

                if isRunning then
                    print(tostring(webserverType).." webszerver leállítása...");

                    if webserverBootstrapModule.stop_server() then
                        print("=> "..tostring(webserverType).." sikeresen leállításra került!");
                    else
                        print("=> Hiba történt a(z) "..tostring(webserverType).." leállítása közben!");
                    end
                else
                    print(tostring(webserverType).." webszerver elindítása...");

                    if webserverBootstrapModule.start_server() then
                        print("=> "..tostring(webserverType).." sikeresen elindításra került!");
                    else
                        print("=> Hiba történt a(z) "..tostring(webserverType).." elindítása közben!");
                    end
                end

                print("Nyomjon ENTER-t a folytatáshoz.");
                io.read();
            elseif firstChar == "2" then --manage current websites
                if not serverImpl.init_dirs() or not serverImpl.initialize_server() then
                    print("Nem sikerült inicializálni a(z) "..tostring(webserverType).." webszervert!");
                    print("Nyomjon ENTER-t a folytatáshoz.");
                    io.read();
                    goto continueWebsiteMainMenu;
                end

                local counter = 1;
                local printOptionAndIncreaseCounter = function(str)
                    print(str);
                    counter = counter + 1;
                end

                while true do
                    general.clearScreen();

                    local websites = serverImpl.get_current_available_websites();

                    if #websites == 0 then
                        print("Nincs még egyetlen weboldal sem létrehozva. Hozzon létre egyet először.");
                        print("Nyomjon ENTER-t a folytatáshoz.");
                        io.read();
                        goto continueWebsiteMainMenu;
                    end

                    print("<==> "..tostring(webserverType).." jelenlegi weboldalak <==>");
                    print("A visszalépéshez nyomjon ENTER-t.");

                    for t, v in pairs(websites) do
                        print("=> "..tostring(t)..". "..tostring(v.websiteUrl));
                    end

                    readStr = io.read();
                    firstChar = readStr:sub(1, 1);

                    if readStr == " " or #readStr == 0 then
                        break;
                    end

                    local idx = tonumber(readStr);
                    local websiteData = websites[idx];

                    if not websiteData then
                        print("Hibás weboldal sorszám: "..tostring(readStr));

                        goto continueWebsite;
                    end

                    while true do
                        general.clearScreen();

                        counter = 1;

                        print("<==> A kiválasztott weboldal: "..tostring(websiteData.websiteUrl).." rootPath: "..tostring(websiteData.rootPath).." configPath: "..tostring(websiteData.configPath).." <==>");
                        printOptionAndIncreaseCounter("=> "..tostring(counter)..". Weboldal törlése");
                        printOptionAndIncreaseCounter("=> "..tostring(counter)..". Weboldal SSL initializációja Let's Encrypt segítségével");
                        printOptionAndIncreaseCounter("=> "..tostring(counter)..". Visszalépés");

                        readStr = io.read();
                        firstChar = readStr:sub(1, 1);

                        if readStr == " " or #readStr == 0 or firstChar == tostring(counter - 1) then
                            break;
                        end

                        if firstChar == "1" then
                            general.clearScreen();

                            print("=> "..tostring(websiteData.websiteUrl).." weboldal törlése...");

                            local websiteDeletionRet = serverImpl.delete_website(websiteData.websiteUrl);

                            if websiteDeletionRet == true then
                                if isRunning then
                                    serverImpl.stop_server();
                                    serverImpl.start_server();
                                end

                                print("Sikeresen törlésre került a(z) "..tostring(websiteData.websiteUrl).." weboldal!");
                            else
                                print("Hiba történt a(z) "..tostring(websiteData.websiteUrl).." weboldal törlése közben!");
                                print("Hiba: "..tostring(serverImpl.resolveErrorToStr(websiteDeletionRet)));
                            end

                            print("Nyomjon ENTER-t a folytatáshoz.");
                            io.read();
                            break;
                        elseif firstChar == "2" then
                            while true do
                                general.clearScreen();

                                print("=> "..tostring(websiteData.websiteUrl).." weboldal SSL initializációjának lehetőségei: ");

                                counter = 1;

                                printOptionAndIncreaseCounter("=> "..tostring(counter)..". HTTP-01 challenge");
                                printOptionAndIncreaseCounter("=> "..tostring(counter)..". DNS-01 challenge");
                                printOptionAndIncreaseCounter("=> "..tostring(counter)..". Visszalépés");

                                readStr = io.read();
                                firstChar = readStr:sub(1, 1);

                                if readStr == " " or #readStr == 0 or firstChar == tostring(counter - 1) then
                                    goto continueWebsiteInnerLoop;
                                end

                                local challengeType = false;
                                local challengeTypeDisplayStr = false;

                                if firstChar == "1" then
                                    challengeType = "http-01";
                                    challengeTypeDisplayStr = "HTTP-01";
                                elseif firstChar == "2" then
                                    challengeType = "dns";
                                    challengeTypeDisplayStr = "DNS-01";
                                end

                                if challengeType then
                                    general.clearScreen();

                                    local certbotInitRet = certbot.init();

                                    if not certbotInitRet then
                                        print("Hiba történt a certbot inicializálása közben!");
                                        print("Hiba: "..tostring(certbotInitRet));
                                        goto continueWebsiteInnerLoop;
                                    end
                                    
                                    print("=> SSL certificate létrehozása "..tostring(challengeTypeDisplayStr).." challenge segítségével a(z) "..tostring(websiteData.websiteUrl).." weboldal számára...");

                                    local retOfSSLCreation, possibleRetCode, possibleRetLinesFromCertbot = certbot.try_ssl_certification_creation(challengeType, tostring(websiteData.websiteUrl), webserverType);

                                    if retOfSSLCreation == true then
                                        print("=> Sikeresen létrehozásra került az SSL certificate "..tostring(challengeTypeDisplayStr).." challenge segítségével a(z) "..tostring(websiteData.websiteUrl).." weboldal számára!");
                                        print("Nyomjon ENTER-t a folytatáshoz.");
                                        io.read();
                                        break;
                                    else
                                        print("=> Hiba történt az SSL certificate ("..tostring(challengeTypeDisplayStr)..") létrehozása közben a(z) "..tostring(websiteData.websiteUrl).." weboldalnál!");
                                        print("Hiba: "..tostring(certbot.resolveErrorToStr(retOfSSLCreation)));
                                        
                                        if possibleRetCode and possibleRetCode < 0 then
                                            local errorStr = serverImpl.resolveErrorToStr(possibleRetCode);
                                            if errorStr then
                                                print("Hiba #2: "..tostring(errorStr));
                                            end
                                        end

                                        if possibleRetLinesFromCertbot then
                                            print(tostring(possibleRetLinesFromCertbot));
                                        end

                                        print("Nyomjon ENTER-t a folytatáshoz.");
                                        io.read();
                                    end
                                end
                                ::continueWebsiteInnerLoop::
                            end
                        end
                    end

                    ::continueWebsite::
                end

                ::continueWebsiteMainMenu::
            elseif firstChar == "3" then --create new websites
                general.clearScreen();

                while true do
                    print("Írja be a létrehozandó weboldal címét:");
                    print("Ha vissza szeretne lépni, nyomjon csak simán ENTER-t.");
                
                    readStr = io.read();
                    firstChar = readStr:sub(1, 1);

                    if readStr == " " or #readStr == 0 then
                        break;
                    end

                    if readStr:match("[a-z]*://[^ >,;]*") then --from https://stackoverflow.com/questions/68694608/how-to-check-url-whether-url-is-valid-in-lua
                        print("=> Kizárólag alfanumerikus lehet az új weboldal címe...");
                    else
                        if not serverImpl.init_dirs() or not serverImpl.initialize_server() then
                            print("Nem sikerült inicializálni a(z) "..tostring(webserverType).." webszervert!");
                            print("Nyomjon ENTER-t a folytatáshoz.");
                            io.read();
                            break;
                        end

                        if isRunning then
                            webserverBootstrapModule.stop_server();
                        end

                        local websiteCreationRet = serverImpl.create_new_website(readStr);

                        if websiteCreationRet ~= true then
                            print("=> Hiba történt a weboldal létrehozása közben!");
                            print("Hiba: "..tostring(serverImpl.resolveErrorToStr(websiteCreationRet)));
                        else
                            print("=> Sikeresen létrehozásra került a(z) "..tostring(readStr).." weboldal!");
                        end

                        if isRunning then
                            webserverBootstrapModule.start_server();
                        end

                        print("Nyomjon ENTER-t a folytatáshoz.");
                        io.read();

                        break;
                    end
                end
            end
        end
    end
end

--main interface starts here

while true do
    general.clearScreen();

    local counter = 1;
    local printOptionAndIncreaseCounter = function(str)
        print(str);
        counter = counter + 1;
    end

    print('Válasszon az alábbi lehetőségek közül: ');

    printOptionAndIncreaseCounter('=> '..tostring(counter)..'. OpenVPN szerver');
    printOptionAndIncreaseCounter('=> '..tostring(counter)..'. Webszerverek');
    printOptionAndIncreaseCounter('=> '..tostring(counter)..'. Tűzfal (iptables)');
    printOptionAndIncreaseCounter(''..tostring(counter)..'. Kilépés');

    local readStr = io.read();
    local firstChar = readStr:sub(1, 1);

    if firstChar == tostring(counter - 1) then
        return;
    end

    if firstChar == "1" then
        while true do
            general.clearScreen();

            local isInstalled = OpenVPNHandler.is_openvpn_installed();
            local isRunning = OpenVPNHandler.is_running();
            local serverImpl = OpenVPNHandler.server_impl;
            local errors = serverImpl.errors;

            local counter = 1;
            local printOptionAndIncreaseCounter = function(str)
                print(str);
                counter = counter + 1;
            end
            
            print("<=> OpenVPN szerver <=>");
            if not isInstalled then
                printOptionAndIncreaseCounter("=> "..tostring(counter)..". Feltelepítés");
            else  
                printOptionAndIncreaseCounter("=> "..tostring(counter)..". "..tostring(isRunning and "Leállítás" or "Elindítás"));

                if not serverImpl.is_easy_rsa_installed() then
                    printOptionAndIncreaseCounter("=> "..tostring(counter)..". Szerver automatikus bekonfigurálása");
                else
                    printOptionAndIncreaseCounter("=> "..tostring(counter)..". Szerver konfigurációjának frissítése");
                    printOptionAndIncreaseCounter("=> "..tostring(counter)..". Bekonfigurált kliensek listázása");
                    printOptionAndIncreaseCounter("=> "..tostring(counter)..". Új kliens bekonfigurálása");
                end
            end

            printOptionAndIncreaseCounter(""..tostring(counter)..". Visszalépés");

            readStr = io.read();
            firstChar = readStr:sub(1, 1);

            if firstChar == tostring(counter - 1) then
                break;
            end

            if not isInstalled then
                if firstChar == "1" then
                    doOpenVPNInstall(OpenVPNHandler);
                end
            else
                if firstChar == "1" then --start/stop openvpn server
                    doOpenVPNStartStop(isRunning, OpenVPNHandler);
                elseif firstChar == "2" then --init openvpn server/refresh server config
                    doOpenVPNInitOrRefresh(isRunning, serverImpl);
                elseif firstChar == "3" then --list openvpn clients
                    doOpenVPNClientListing(serverImpl);
                elseif firstChar == "4" then --create new openvpn client
                    doOpenVPNClientCreation(serverImpl);
                end
            end
        end
    elseif firstChar == "2" then
        while true do
            general.clearScreen();

            print("Válasszon a további lehetőségek közül: ");

            local counter = 1;
            local printOptionAndIncreaseCounter = function(str)
                print(str);
                counter = counter + 1;
            end

            printOptionAndIncreaseCounter("=> "..tostring(counter)..". Apache");
            printOptionAndIncreaseCounter("=> "..tostring(counter)..". nginx");
            printOptionAndIncreaseCounter(""..tostring(counter)..". Visszalépés");
            
            readStr = io.read();
            firstChar = readStr:sub(1, 1);

            if firstChar == tostring(counter - 1) then
                break;
            end

            if firstChar == "1" then
                doWebserverMenu("apache");
            elseif firstChar == "2" then
                doWebserverMenu("nginx");
            end
        end
    end
end

--initialize handlers
--OpenVPNHandler.init_dirs();
-- nginxHandler.init_dirs(); --TODO: reverse proxy
-- apacheHandler.init_dirs(); --TODO: reverse proxy
-- certbotHandler.init();

-- print("Apache website creation: "..tostring(apacheHandler.server_impl.create_new_website("lszlo.ltd")));
-- print("Certbot test: "..tostring(certbotHandler.try_ssl_certification_creation("dns", "lszlo.ltd", "apache")));

--[[ print("ssh port: "..tostring(inspect(iptables.get_current_ssh_ports())));
print("module init: "..tostring(iptables.init_module())); ]]

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