package.path = package.path..";modules/?.lua";

--import handlers
local OpenVPNHandler = require("vpnHandler/OpenVPN");
local nginxHandler = require("nginxHandler/nginx");
local apacheHandler = require("apacheHandler/apache");
--local nginxConfigHandlerObject = require("nginxHandler/nginx_config_handler");
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
                        local numOfChoice = tonumber(str);

                        if numOfChoice == innerCounter - 1 then
                            break;
                        end

                        if numOfChoice == 1 then
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
                        elseif numOfChoice == 2 then
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

        local numOfChoice = tonumber(readStr);

        if numOfChoice == counter - 1 then
            break;
        end

        if not isInstalled then
            if numOfChoice == 1 then --install
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
            if numOfChoice == 1 then --start/stop
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
            elseif numOfChoice == 2 then --manage current websites
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
                        numOfChoice = tonumber(readStr);

                        if readStr == " " or #readStr == 0 or numOfChoice == counter - 1 then
                            break;
                        end

                        if numOfChoice == 1 then
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
                        elseif numOfChoice == 2 then
                            while true do
                                general.clearScreen();

                                print("=> "..tostring(websiteData.websiteUrl).." weboldal SSL initializációjának lehetőségei: ");

                                counter = 1;

                                printOptionAndIncreaseCounter("=> "..tostring(counter)..". HTTP-01 challenge");
                                printOptionAndIncreaseCounter("=> "..tostring(counter)..". DNS-01 challenge");
                                printOptionAndIncreaseCounter(tostring(counter)..". Visszalépés");

                                readStr = io.read();
                                numOfChoice = tonumber(readStr);

                                if readStr == " " or #readStr == 0 or numOfChoice == counter - 1 then
                                    break;
                                end

                                local challengeType = false;
                                local challengeTypeDisplayStr = false;

                                if numOfChoice == 1 then
                                    challengeType = "http-01";
                                    challengeTypeDisplayStr = "HTTP-01";
                                elseif numOfChoice == 2 then
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
                                        if possibleRetLinesFromCertbot then
                                            print(tostring(possibleRetLinesFromCertbot));
                                        end
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
            elseif numOfChoice == 3 then --create new websites
                general.clearScreen();

                while true do
                    print("Írja be a létrehozandó weboldal címét:");
                    print("Ha vissza szeretne lépni, nyomjon csak simán ENTER-t.");
                
                    readStr = io.read();
                    
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

local function doIptablesMenu()
    while true do
        general.clearScreen();
        print("<=> iptables <=>");

        local counter = 1;
        local printOptionAndIncreaseCounter = function(str)
            print(str);
            counter = counter + 1;
        end
        
        local isInstalled = iptables.is_iptables_installed();

        if not isInstalled then
            printOptionAndIncreaseCounter("=> "..tostring(counter)..". Feltelepítés");
        else
            printOptionAndIncreaseCounter("=> "..tostring(counter)..". Nyitott portok");
            printOptionAndIncreaseCounter("=> "..tostring(counter)..". Zárt portok");
            printOptionAndIncreaseCounter("=> "..tostring(counter)..". Port nyitása");
            printOptionAndIncreaseCounter("=> "..tostring(counter)..". Port zárása");
            printOptionAndIncreaseCounter("=> "..tostring(counter)..". Kifelé irányuló új megengedett kapcsolat létrehozása");
            printOptionAndIncreaseCounter("=> "..tostring(counter)..". Engedélyezett kimenő kapcsolatok");
            printOptionAndIncreaseCounter("=> "..tostring(counter)..". Interface alapú togglek");

            if OpenVPNHandler.is_openvpn_installed() then
                printOptionAndIncreaseCounter("=> "..tostring(counter)..". OpenVPN NAT setup");
            end
        end
        printOptionAndIncreaseCounter(tostring(counter)..". Visszalépés");

        local readStr = io.read();
        local numOfChoice = tonumber(readStr);

        if numOfChoice == counter - 1 then
            break;
        end

        if not isInstalled then
            if numOfChoice == 1 then
                general.clearScreen();

                print("=> iptables telepítése...");

                local installRet, possibleError = iptables.install_iptables();

                if installRet then
                    print("Az iptables sikeresen telepítésre került! Nyomjon ENTER-t a folytatáshoz.");
                else
                    print("=> Hiba történt az iptables telepítése közben!");
                    print("Hiba: "..tostring(possibleError));
                    print("Nyomjon ENTER-t a folytatáshoz.");
                end
                io.read();
            end
        else
            local originallyChosenOption = tonumber(readStr);
            local interfaceSelected = false;
            local needToBreakInterfaceSelector = false;

            while true do
                if needToBreakInterfaceSelector then
                    break;
                end

                general.clearScreen();

                local initModuleRet = iptables.init_module();

                if not initModuleRet then
                    print("Hiba történt az iptables modul inicializálása közben! Hiba: "..tostring(iptables.resolveErrorToStr(initModuleRet)));
                    print("Nyomjon ENTER-t a folytatáshoz.");
                    io.read();
                    break;
                end

                print("Válasszon egy interfacet a továbblépés előtt: ");
                local counter = 1;
                local printOptionAndIncreaseCounter = function(str)
                    print(str);
                    counter = counter + 1;
                end

                if originallyChosenOption ~= 8 or not OpenVPNHandler.is_openvpn_installed() then --OpenVPN nat
                    printOptionAndIncreaseCounter("=> "..tostring(counter)..". Összes (mindegyikre vonatkozik egyszerre)");
                end

                local interfaces = iptables.get_current_network_interfaces();
                for t, v in pairs(interfaces) do
                    printOptionAndIncreaseCounter("=> "..tostring(counter)..". "..tostring(v));
                end
                printOptionAndIncreaseCounter(tostring(counter)..". Visszalépés");
                readStr = io.read();
                local num = tonumber(readStr);

                if num == counter - 1 then
                    break;
                end
                
                if originallyChosenOption ~= 8 or not OpenVPNHandler.is_openvpn_installed() then
                    interfaceSelected = num == 1 and "all" or interfaces[num - 1];
                else --OpenVPN nat
                    interfaceSelected = interfaces[num];
                end

                if not interfaceSelected then
                    print("Hibás szám: "..tostring(num));
                    print("Nyomjon ENTER-t a továbblépéshez.");
                    io.read();
                end

                if originallyChosenOption == 1 then --open ports
                    while true do
                        local needToBreakOpenPorts = true;
                        general.clearScreen();
                        iptables.init_module();

                        print("=> Az összes, felhasználó által kinyitott port a(z) "..tostring(interfaceSelected).." interfacen:");

                        local portsOpened = iptables.get_open_ports(interfaceSelected);

                        if portsOpened == "all" or #portsOpened == 0 then
                            print("Nincs korlátozás, az összes port nyitva van.");
                            print("");
                            print("Nyomjon ENTER-t a továbblépéshez.");
                            io.read();
                        else
                            table.sort(portsOpened, function(a, b)
                                return a.protocol > b.protocol
                            end);

                            for t, v in pairs(portsOpened) do
                                print(tostring(t)..". Protokoll: "..tostring(v.protocol == "all" and "Összes" or v.protocol).." Port: "..tostring(v.dport == "all" and "Összes" or v.dport).." IP korlátozás: "..tostring(v.sourceIP and v.sourceIP or "nincs"));
                            end

                            if not iptables.check_if_inbound_packets_are_being_filtered_already(interfaceSelected, "tcp") and not iptables.check_if_inbound_packets_are_being_filtered_already(interfaceSelected, "udp") then
                                print("=> A(z) "..tostring(interfaceSelected).." interfacen nincs bekapcsolva az, hogy csak engedélyezett bejövő portok legyenek nyitva, így ezek a szabályok jelenleg nem effektívek.");
                            elseif not iptables.check_if_inbound_packets_are_being_filtered_already(interfaceSelected, "tcp") then
                                print("=> A(z) "..tostring(interfaceSelected).." interfacen nincs bekapcsolva az, hogy csak engedélyezett bejövő portok legyenek nyitva TCP protokollon, így a TCP-protokoll alapú szabályok jelenleg nem effektívek.");
                            elseif not iptables.check_if_inbound_packets_are_being_filtered_already(interfaceSelected, "udp") then
                                print("=> A(z) "..tostring(interfaceSelected).." interfacen nincs bekapcsolva az, hogy csak engedélyezett bejövő portok legyenek nyitva UDP protokollon, így az UDP-protokoll alapú szabályok jelenleg nem effektívek.");
                            end

                            print("");
                            print("=> Szabály törléséhez írja be, hogy töröl/torol, majd a sorszámát a szabálynak.");
                            print("Továbblépéshez nyomjon ENTER-t.");
                            readStr = io.read();

                            if readStr and #readStr > 0 and readStr ~= " " and type(readStr) == "string" and readStr:find("töröl", 1, true) == 1 or readStr:find("torol", 1, true) == 1 then
                                local numberStr = "";
                                if readStr:find("töröl", 1, true) == 1 then --unicode stuff
                                    numberStr = readStr:sub(8);
                                else
                                    numberStr = readStr:sub(6);
                                end
                                local num = tonumber(numberStr);

                                local deletionRet = iptables.delete_open_port_rule(interfaceSelected, num);

                                if deletionRet == true then
                                    if iptables.loadOurRulesToIptables() then
                                        print("=> Sikeresen törölve lett a(z) "..tostring(num).." számú szabály.");
                                    else
                                        print("=> Hiba történt az iptables szabályok véglegesítése közben.");
                                    end
                                else
                                    print("=> Hiba történt a(z) "..tostring(num).." számú szabály törlése közben.");
                                end

                                print("Nyomjon ENTER-t a folytatáshoz.");
                                io.read();

                                needToBreakOpenPorts = false;
                            end
                        end

                        if needToBreakOpenPorts then
                            break;
                        end
                    end
                elseif originallyChosenOption == 2 then --closed ports
                    while true do
                        local needToBreakClosePorts = true;
                        general.clearScreen();
                        iptables.init_module();

                        print("=> Az összes, felhasználó által zárt port a(z) "..tostring(interfaceSelected).." interfacen:");

                        local portsClosed = iptables.get_closed_ports(interfaceSelected);

                        if portsClosed == "none" or #portsClosed == 0 then
                            print("Nincs korlátozás, az összes port nyitva van.");
                            print("");
                            print("Nyomjon ENTER-t a továbblépéshez.");
                            io.read();
                        else
                            table.sort(portsClosed, function(a, b)
                                return a.protocol > b.protocol
                            end);

                            for t, v in pairs(portsClosed) do
                                print(tostring(t)..". Protokoll: "..tostring(v.protocol == "all" and "Összes" or v.protocol).." Port: "..tostring(v.dport == "all" and "Összes" or v.dport).." IP korlátozás: "..tostring(v.sourceIP and v.sourceIP or "nincs"));
                            end

                            if iptables.check_if_inbound_packets_are_being_filtered_already(interfaceSelected, "tcp") and iptables.check_if_inbound_packets_are_being_filtered_already(interfaceSelected, "udp") then
                                print("=> A(z) "..tostring(interfaceSelected).." interfacen be van kapcsolva, hogy csak engedélyezett bejövő portok legyenek nyitva. Így ezek a szabályok kiegészítő szabályok. Ha nem léteznének, akkor is le lenne tiltva az összes nem engedélyezett port.");
                            elseif iptables.check_if_inbound_packets_are_being_filtered_already(interfaceSelected, "tcp") then
                                print("=> A(z) "..tostring(interfaceSelected).." interfacen be van kapcsolva, hogy csak engedélyezett bejövő portok legyenek nyitva TCP protokollon, így a TCP-protokoll alapú szabályoknak jelenleg nem kötelező létezniük a portok letiltásához.");
                            elseif iptables.check_if_inbound_packets_are_being_filtered_already(interfaceSelected, "udp") then
                                print("=> A(z) "..tostring(interfaceSelected).." interfacen be van kapcsolva, hogy csak engedélyezett bejövő portok legyenek nyitva UDP protokollon, így az UDP-protokoll alapú szabályoknak jelenleg nem kötelező létezniük a portok letiltásához.");
                            end

                            print("");
                            print("=> Szabály törléséhez írja be, hogy töröl/torol, majd a sorszámát a szabálynak.");
                            readStr = io.read();

                            if readStr and #readStr > 0 and readStr ~= " " and type(readStr) == "string" and readStr:find("töröl", 1, true) == 1 or readStr:find("torol", 1, true) == 1 then
                                local numberStr = "";
                                if readStr:find("töröl", 1, true) == 1 then --unicode stuff
                                    numberStr = readStr:sub(8);
                                else
                                    numberStr = readStr:sub(6);
                                end
                                local num = tonumber(numberStr);

                                local deletionRet = iptables.delete_close_port_rule(interfaceSelected, num);

                                if deletionRet == true then
                                    if iptables.loadOurRulesToIptables() then
                                        print("=> Sikeresen törölve lett a(z) "..tostring(num).." számú szabály.");
                                    else
                                        print("=> Hiba történt az iptables szabályok véglegesítése közben.");
                                    end
                                else
                                    print("=> Hiba történt a(z) "..tostring(num).." számú szabály törlése közben.");
                                end

                                needToBreakClosePorts = false;

                                print("Nyomjon ENTER-t a folytatáshoz.");
                                io.read();
                            end
                        end

                        if needToBreakClosePorts then
                            break;
                        end
                    end
                elseif originallyChosenOption == 3 then --open port
                    general.clearScreen();
                    iptables.init_module();
                    print("=> Port nyitása a(z) "..tostring(interfaceSelected).." interfacen...");

                    local protocol = false;
                    local portNum = 0;
                    local ret = false;

                    while true do
                        print("Írja be az engedélyezett port protokollját (tcp/udp/all (tcp+udp)):");
                        print("Visszalépéshez hagyja üresen.");

                        readStr = io.read():lower();

                        if readStr == " " or #readStr == 0 then
                            goto openPortEnd;
                        end
                    
                        if readStr ~= "tcp" and readStr ~= "udp" and readStr ~= "all" then
                            print("Hibás protokoll: "..tostring(readStr));
                        else
                            protocol = readStr;
                            break;
                        end
                    end

                    while true do
                        print("Írja be a port számát:");

                        readStr = io.read();
                        readStr = tonumber(readStr);

                        if readStr == nil then
                            print("Hibás szám!");
                        elseif readStr < 0 then
                            print("Port csak pozitív szám lehet!");
                        elseif readStr > 65535 then
                            print("A maximum portszám 65535 lehet!");
                        else
                            portNum = readStr;
                            break;
                        end
                    end

                    print("Írja be, hogy mely IP címről szeretne csak kapcsolatot fogadni erre a portra: (Üres esetén bármelyikről)");
                    readStr = io.read();

                    if #readStr == 0 or readStr == " " then
                        readStr = nil;
                    end

                    print("=> Port nyitása a(z) "..tostring(interfaceSelected).." interfacen... Protokoll: "..tostring(protocol).." port: "..tostring(portNum).." IP: "..tostring(readStr and readStr or "nincs megadva"));
                    
                    ret = false;
                    if protocol ~= "all" then
                        ret = iptables.open_port(interfaceSelected, protocol, portNum, readStr);
                    else
                        ret = iptables.open_port(interfaceSelected, "tcp", portNum, readStr);
                        ret = iptables.open_port(interfaceSelected, "udp", portNum, readStr);
                    end

                    if not ret then
                        print("Hiba történt a port nyitás szabály létrehozása közben!");
                    else
                        if iptables.loadOurRulesToIptables() then
                            print("A portot engedélyező szabály sikeresen létrejött.");
                        else
                            print("Hiba történt az iptables szabályok véglegesítése közben.");
                        end
                    end

                    print("Nyomjon ENTER-t a folytatáshoz.");
                    io.read();

                    ::openPortEnd::
                elseif originallyChosenOption == 4 then --close port
                    general.clearScreen();
                    iptables.init_module();
                    print("=> Port letiltása a(z) "..tostring(interfaceSelected).." interfacen...");

                    local protocol = false;
                    local portNum = 0;
                    local ret = false;

                    while true do
                        print("Írja be a letiltott port protokollját (tcp/udp/all (tcp+udp)):");
                        print("Visszalépéshez hagyja üresen.");

                        readStr = io.read():lower();

                        if readStr == " " or #readStr == 0 then
                            goto closePortEnd;
                        end
                    
                        if readStr ~= "tcp" and readStr ~= "udp" and readStr ~= "all" then
                            print("Hibás protokoll: "..tostring(readStr));
                        else
                            protocol = readStr;
                            break;
                        end
                    end

                    while true do
                        print("Írja be a port számát:");

                        readStr = io.read();
                        readStr = tonumber(readStr);

                        if readStr == nil then
                            print("Hibás szám!");
                        elseif readStr < 0 then
                            print("Port csak pozitív szám lehet!");
                        elseif readStr > 65535 then
                            print("A maximum portszám 65535 lehet!");
                        else
                            portNum = readStr;
                            break;
                        end
                    end

                    print("Írja be, hogy mely IP címet szeretné letiltani erről a portról: (Üres esetén az összeset)");
                    readStr = io.read();

                    if #readStr == 0 or readStr == " " then
                        readStr = nil;
                    end

                    print("=> Port zárása a(z) "..tostring(interfaceSelected).." interfacen... Protokoll: "..tostring(protocol).." port: "..tostring(portNum).." IP: "..tostring(readStr and readStr or "nincs megadva"));
                    
                    ret = false;
                    if protocol ~= "all" then
                        ret = iptables.close_port(interfaceSelected, protocol, portNum, readStr);
                    else
                        ret = iptables.close_port(interfaceSelected, "tcp", portNum, readStr);
                        ret = iptables.close_port(interfaceSelected, "udp", portNum, readStr);
                    end

                    if not ret then
                        print("Hiba történt a port zárás szabály létrehozása közben!");
                    else
                        if iptables.loadOurRulesToIptables() then
                            print("A portot tiltó szabály sikeresen létrejött.");
                        else
                            print("Hiba történt az iptables szabályok véglegesítése közben.");
                        end
                    end

                    print("Nyomjon ENTER-t a folytatáshoz.");
                    io.read();
                    ::closePortEnd::
                elseif originallyChosenOption == 5 then --allow outgoing connection
                    general.clearScreen();
                    iptables.init_module();
                    print("=> Kimenő kapcsolat engedélyezése a(z) "..tostring(interfaceSelected).." interfacen...");

                    local protocol = false;
                    local portNum = nil;
                    local ret = false;

                    while true do
                        print("Írja be az engedélyezett kimenő port protokollját (tcp/udp/all (tcp+udp)):");
                        print("Visszalépéshez hagyja üresen.");

                        readStr = io.read():lower();

                        if readStr == " " or #readStr == 0 then
                            goto allowOutgoingEnd;
                        end
                    
                        if readStr ~= "tcp" and readStr ~= "udp" and readStr ~= "all" then
                            print("Hibás protokoll: "..tostring(readStr));
                        else
                            protocol = readStr;
                            break;
                        end
                    end

                    while true do
                        print("Írja be a port számát: (Üresen hagyás esetén az összes portra érvényes)");

                        readStr = io.read();
                        readStr = tonumber(readStr);

                        if readStr == nil then
                            break;
                        elseif readStr < 0 then
                            print("Port csak pozitív szám lehet!");
                        elseif readStr > 65535 then
                            print("A maximum portszám 65535 lehet!");
                        else
                            portNum = readStr;
                            break;
                        end
                    end

                    print("Írja be, hogy mely IP cím felé engedélyezné a kimenő kapcsolatokat: (Üres esetén bármelyik felé az adott portra és protokollra vonatkozóan)");
                    readStr = io.read();

                    if #readStr == 0 or readStr == " " then
                        readStr = nil;
                    end

                    print("=> Kimenő kapcsolatot engedélyező szabály létrehozása a(z) "..tostring(interfaceSelected).." interfacen... Protokoll: "..tostring(protocol).." port: "..tostring(portNum).." IP: "..tostring(readStr and readStr or "nincs megadva"));
                    
                    if protocol ~= "all" then
                        ret = iptables.allow_outgoing_new_connection(interfaceSelected, protocol, readStr, portNum);
                    else
                        ret = iptables.allow_outgoing_new_connection(interfaceSelected, "tcp", readStr, portNum);
                        ret = iptables.allow_outgoing_new_connection(interfaceSelected, "udp", readStr, portNum);
                    end

                    if not ret then
                        print("Hiba történt a kimenő kapcsolatot engedélyező szabály létrehozása közben!");
                    else
                        if iptables.loadOurRulesToIptables() then
                            print("A a kimenő kapcsolatot engedélyező szabály sikeresen létrejött.");
                        else
                            print("Hiba történt az iptables szabályok véglegesítése közben.");
                        end
                    end

                    print("Nyomjon ENTER-t a folytatáshoz.");
                    io.read();

                    ::allowOutgoingEnd::
                elseif originallyChosenOption == 6 then --list allowed outgoing connections
                    while true do
                        local needToBreakOutgoingConnections = true;
                        general.clearScreen();
                        iptables.init_module();

                        print("=> Az összes, felhasználó által engedélyezett kimenő kapcsolatok a(z) "..tostring(interfaceSelected).." interfacen:");

                        local allowedOutgoingConnections = iptables.list_allowed_outgoing_connections(interfaceSelected);

                        if allowedOutgoingConnections == "all" or #allowedOutgoingConnections == 0 then
                            print("Nincs korlátozás, bármelyik IP cím & port felé mehet kimenő kapcsolat.");
                            print("");
                            print("Nyomjon ENTER-t a továbblépéshez.");
                            io.read();
                        else
                            table.sort(allowedOutgoingConnections, function(a, b)
                                return a.protocol > b.protocol
                            end);

                            for t, v in pairs(allowedOutgoingConnections) do
                                print(tostring(t)..". Protokoll: "..tostring(v.protocol == "all" and "Összes" or v.protocol).." Port: "..tostring(v.dport == "all" and "Összes" or v.dport).." IP korlátozás: "..tostring(v.destinationIP and v.destinationIP or "nincs"));
                            end

                            if not iptables.check_if_outbound_packets_are_being_filtered_already(interfaceSelected, "tcp") and not iptables.check_if_outbound_packets_are_being_filtered_already(interfaceSelected, "udp") then
                                print("=> A(z) "..tostring(interfaceSelected).." interfacen nincs bekapcsolva, hogy csak engedélyezett irányba mehessen ki kimenő kapcsolat. Így ezek a szabályok nem effektívek jelenleg.");
                            elseif not iptables.check_if_outbound_packets_are_being_filtered_already(interfaceSelected, "tcp") then
                                print("=> A(z) "..tostring(interfaceSelected).." interfacen nincs bekapcsolva, hogy csak engedélyezett irányba mehessen ki kimenő kapcsolat TCP protokollon. Így a TCP-protokoll alapú szabályok nem effektívek jelenleg.");
                            elseif not iptables.check_if_outbound_packets_are_being_filtered_already(interfaceSelected, "udp") then
                                print("=> A(z) "..tostring(interfaceSelected).." interfacen nincs bekapcsolva, hogy csak engedélyezett irányba mehessen ki kimenő kapcsolat UDP protokollon. Így az UDP-protokoll alapú szabályok nem effektívek jelenleg.");
                            end

                            print("");
                            print("=> Szabály törléséhez írja be, hogy töröl/torol, majd a sorszámát a szabálynak.");
                            print("Továbblépéshez nyomjon ENTER-t.")
                            readStr = io.read();

                            if readStr and #readStr > 0 and readStr ~= " " and type(readStr) == "string" and readStr:find("töröl", 1, true) == 1 or readStr:find("torol", 1, true) == 1 then
                                local numberStr = "";
                                if readStr:find("töröl", 1, true) == 1 then --unicode stuff
                                    numberStr = readStr:sub(8);
                                else
                                    numberStr = readStr:sub(6);
                                end
                                local num = tonumber(numberStr);

                                local deletionRet = iptables.delete_outgoing_rule(interfaceSelected, num);

                                if deletionRet == true then
                                    if iptables.loadOurRulesToIptables() then
                                        print("=> Sikeresen törölve lett a(z) "..tostring(num).." számú szabály.");
                                    else
                                        print("=> Hiba történt az iptables szabályok véglegesítése közben.");
                                    end
                                else
                                    print("=> Hiba történt a(z) "..tostring(num).." számú szabály törlése közben.");
                                end

                                needToBreakOutgoingConnections = false;

                                print("Nyomjon ENTER-t a folytatáshoz.");
                                io.read();
                            end
                        end

                        if needToBreakOutgoingConnections then
                            break;
                        end
                    end
                elseif originallyChosenOption == 7 then --toggle interface stuff
                    while true do
                        general.clearScreen();
                        iptables.init_module();
                        print("=> Beállítások a(z) "..tostring(interfaceSelected).." interfacen...");
                        print("Válasszon az alábbi lehetőségek közül:");
                        local counter = 1;
                        local printOptionAndIncreaseCounter = function(str)
                            print(str);
                            counter = counter + 1;
                        end

                        local inboundFiltered = iptables.check_if_inbound_packets_are_being_filtered_already(interfaceSelected, "all");
                        local outboundFiltered = iptables.check_if_outbound_packets_are_being_filtered_already(interfaceSelected, "all");

                        if inboundFiltered then
                            printOptionAndIncreaseCounter("=> "..tostring(counter)..". Bármely bejövő kapcsolat engedélyezve legyen");
                        else
                            printOptionAndIncreaseCounter("=> "..tostring(counter)..". Az összes olyan bejövő kapcsolat tiltása, amelyre nincs engedélyező szabály");
                        end

                        if outboundFiltered then
                            printOptionAndIncreaseCounter("=> "..tostring(counter)..". Bármely kimenő kapcsolat engedélyezve legyen");
                        else
                            printOptionAndIncreaseCounter("=> "..tostring(counter)..". Az összes olyan kimenő új kapcsolat tiltása, amelyre nincs engedélyező szabály");
                        end

                        printOptionAndIncreaseCounter(tostring(counter)..". Visszalépés");
                        readStr = io.read();
                        local num = tonumber(readStr);

                        if num == counter - 1 then
                            break;
                        end

                        if num == 1 then
                            local sshPorts = iptables.get_current_ssh_ports();
                            local openPorts = iptables.get_open_ports(interfaceSelected);
                            local notAllowedSSHPorts = {};
                            local ret = false;
                            if openPorts == "all" then
                                openPorts = {};
                            end

                            for _, sshPort in pairs(sshPorts) do
                                local add = true;
                                for _, data in pairs(openPorts) do
                                    if data.protocol == "tcp" and (data.dport == tostring(sshPort) or data.dport == "all") then  
                                        add = false;
                                        break;
                                    end
                                end

                                if add then
                                    table.insert(notAllowedSSHPorts, sshPort);
                                end
                            end

                            if #notAllowedSSHPorts > 0 then
                                print("Néhány SSH portnak nincs engedélyező szabálya ezen az interfacen, így megszakadhat a kapcsolat az SSH szerverrel ezzel a beállítással!");
                                print("Az SSH portok, amelyek nincsenek engedélyezve: "..tostring(table.concat(notAllowedSSHPorts, ", ")));
                                print("Kívánja folytatni? (Y/N)");
                                readStr = io.read();

                                if readStr == "N" then
                                    goto continueInside;
                                end
                            end

                            ret = iptables.tog_only_allow_accepted_packets_inbound(not inboundFiltered, interfaceSelected, "all");

                            if ret == true then
                                if iptables.loadOurRulesToIptables() then
                                    print("Sikeres beállítás.");
                                else
                                    print("Hiba történt az iptables szabályok inicializálása közben.");
                                end
                            else
                                print("Hiba történt a beállítás módosítása közben!");
                            end

                            ::continueInside::
                            print("Nyomjon ENTER-t a folytatáshoz.");
                            io.read();
                        elseif num == 2 then
                            local ret = iptables.tog_only_allow_accepted_packets_outbound(not outboundFiltered, interfaceSelected, "all");

                            if ret == true then
                                if iptables.loadOurRulesToIptables() then
                                    print("Sikeres beállítás.");
                                else
                                    print("Hiba történt az iptables szabályok inicializálása közben.");
                                end
                            else
                                print("Hiba történt a beállítás módosítása közben!");
                            end

                            print("Nyomjon ENTER-t a folytatáshoz.");
                            io.read();
                        end
                    end
                elseif originallyChosenOption == 8 then --openvpn nat setup
                    while true do
                        general.clearScreen();

                        local currentNATDatas = iptables.get_current_active_nat_for_openvpn();

                        if not currentNATDatas or #currentNATDatas == 0 then
                            print("=> Nincs még NAT létrehozva egy interfacen sem...");
                            print("=> Szeretné létrehozni a(z) "..tostring(interfaceSelected).." main interfacera bezárólag? (Y/N)");

                            readStr = io.read();

                            if readStr == "Y" then
                                local serverImpl = OpenVPNHandler.server_impl;

                                if serverImpl.init_dirs() ~= true or serverImpl.initialize_server() ~= true then
                                    print("=> Hiba történt az OpenVPN szerver inicializálása közben.");
                                    print("Nyomjon ENTER-t a folytatáshoz.");
                                    io.read();
                                    break;
                                end

                                local subnet = serverImpl.get_openvpn_subnet();

                                if not subnet then
                                    print("=> Hiba történt az OpenVPN subnet lekérdezése közben.");
                                    print("Nyomjon ENTER-t a folytatáshoz.");
                                    io.read();
                                    break;
                                end

                                local creationRet = iptables.init_nat_for_openvpn(interfaceSelected, "tun0", subnet);

                                if creationRet == true then
                                    if iptables.loadOurRulesToIptables() then
                                        print("=> Sikeresen létrehozásra kerültek az OpenVPN natot támogató szabályok! OpenVPN belső ip: "..tostring(subnet));
                                    else
                                        print("=> Hiba történt az OpenVPN nat szabályok véglegesítése közben. OpenVPN belső ip: "..tostring(subnet));
                                    end
                                else
                                    print("=> Hiba történt az OpenVPN nat szabályai létrehozása közben!");
                                end
                                print("Nyomjon ENTER-t a folytatáshoz.");

                                io.read();
                                break;
                            else
                                break;
                            end
                        else
                            print("=> Már van létrehozva NAT! Meglévő NAT-ok:");
                            for t, v in pairs(currentNATDatas) do
                                print(tostring(t)..". Main interface: "..tostring(v.mainInterface).." Tunnel interface: "..tostring(v.outInterface).." subnet: "..tostring(v.subnet));
                            end

                            print("");
                            print("=> Szabály törléséhez írja be, hogy töröl/torol, majd a sorszámát a szabálynak.");
                            print("Továbblépéshez nyomjon ENTER-t.");
                            readStr = io.read();

                            if readStr and #readStr > 0 and readStr ~= " " and type(readStr) == "string" and readStr:find("töröl", 1, true) == 1 or readStr:find("torol", 1, true) == 1 then
                                local numberStr = "";
                                if readStr:find("töröl", 1, true) == 1 then --unicode stuff
                                    numberStr = readStr:sub(8);
                                else
                                    numberStr = readStr:sub(6);
                                end
                                local num = tonumber(numberStr);

                                local data = currentNATDatas[num];

                                if not data then
                                    print("");
                                    print("Hibás szám: "..tostring(numberStr));
                                    print("Továbblépéshez nyomjon ENTER-t.");

                                    io.read();
                                    goto continueInsideNAT;
                                end

                                if iptables.delete_nat_rules(data.mainInterface, data.outInterface, data.forwardTblIdx, data.forwardTblAllIdx, data.postroutingTblAllIdx) == true then
                                    if iptables.loadOurRulesToIptables() then
                                        print("=> Sikeresen törölve lett a(z) "..tostring(num).." számú szabály.");
                                    else
                                        print("=> Hiba történt az iptables szabályok véglegesítése közben.");
                                    end
                                else
                                    print("=> Hiba történt a(z) "..tostring(num).." számú szabály törlése közben.");
                                end

                                print("Nyomjon ENTER-t a folytatáshoz.");
                                io.read();
                            else
                                break;
                            end

                            ::continueInsideNAT::
                        end
                    end
                end
            end

            ::afterLoop1::
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
    local numOfChoice = tonumber(readStr);

    if numOfChoice == counter - 1 then
        return;
    end

    if numOfChoice == 1 then
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
            numOfChoice = tonumber(readStr);

            if numOfChoice == counter - 1 then
                break;
            end

            if not isInstalled then
                if numOfChoice == 1 then
                    doOpenVPNInstall(OpenVPNHandler);
                end
            else
                if numOfChoice == 1 then --start/stop openvpn server
                    doOpenVPNStartStop(isRunning, OpenVPNHandler);
                elseif numOfChoice == 2 then --init openvpn server/refresh server config
                    doOpenVPNInitOrRefresh(isRunning, serverImpl);
                elseif numOfChoice == 3 then --list openvpn clients
                    doOpenVPNClientListing(serverImpl);
                elseif numOfChoice == 4 then --create new openvpn client
                    doOpenVPNClientCreation(serverImpl);
                end
            end
        end
    elseif numOfChoice == 2 then
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
            numOfChoice = tonumber(readStr);

            if numOfChoice == counter - 1 then
                break;
            end

            if numOfChoice == 1 then
                doWebserverMenu("apache");
            elseif numOfChoice == 2 then
                doWebserverMenu("nginx");
            end
        end
    elseif numOfChoice == 3 then
        doIptablesMenu();
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