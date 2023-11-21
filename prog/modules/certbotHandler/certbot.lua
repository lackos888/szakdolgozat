local os = require("os");
local aptPackageManager = require("apt_packages");
local snapPackageManager = require("snapd");
local linux = require("linux");
local general = require("general");
local inspect = require("inspect");
local nginx = require("nginxHandler/nginx");
local apache = require("apacheHandler/apache");
local certFileName = "fullchain.pem";
local keyFileName = "privkey.pem";
local dhParamFileName = "dhparam.pem";
local dryRunStr = ""; --dry-run if debugging;
local dhParamBytes = "1024"; --in real life it could be 4096 aswell, decreased to speed up generation

local module = {
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

--from http://lua-users.org/wiki/SleepFunction
local clock = os.clock
local function sleep(n)  -- seconds
  local t0 = clock()
  while clock() - t0 <= n do end
end

registerNewError("ALREADY_INSTALLED_ERROR");
registerNewError("SNAPD_INSTALL_ERROR");

function module.is_certbot_installed()
    if not snapPackageManager.isSnapdInstalled() then
        return false;
    end

    return snapPackageManager.is_package_installed("certbot");
end

function module.create_certbot_symlink()
    if not linux.exists("/usr/bin/certbot") then
        linux.exec_command_with_proc_ret_code("ln -s /snap/bin/certbot /usr/bin/certbot");
    end
end

function module.install_certbot()
    if not snapPackageManager.isSnapdInstalled() then
        if not snapPackageManager.installSnapd() then
            return module.errors.SNAPD_INSTALL_ERROR;
        end
    end

    if module.is_certbot_installed() then
        module.create_certbot_symlink();

        return module.errors.ALREADY_INSTALLED_ERROR;
    end

    if snapPackageManager.install_package("certbot", true) then
        module.create_certbot_symlink();

        return true;
    end
    
    return false;
end

function module.get_cert_datas(domain)
    local retLines, retCode = linux.exec_command_with_proc_ret_code(domain and ("certbot certificates -d "..tostring(domain)) or ("certbot certificates"), true);

    if retCode ~= 0 then
        return false;
    end

    local linesIterator = retLines:gmatch("[^\r\n]+");
    local str1 = "Domains: ";
    local str2 = "Certificate Path: ";
    local str3 = "Private Key Path: ";
    local certDatas = {};
    local currentDomain = "";

    for line in linesIterator do
        local foundLoc1 = line:find(str1, 0, true);
        if foundLoc1 then
            currentDomain = line:sub(foundLoc1 + #str1);
            certDatas[currentDomain] = {};
        end

        local foundLoc2 = line:find(str2, 0, true);
        if foundLoc2 then
            certDatas[currentDomain]["certPath"] = line:sub(foundLoc2 + #str2);
        end

        local foundLoc3 = line:find(str3, 0, true);
        if foundLoc3 then
            certDatas[currentDomain]["keyPath"] = line:sub(foundLoc3 + #str2);
        end
    end

    return certDatas;
end

registerNewError("INVALID_WEBSERVER_TYPE");
registerNewError("NON_EXISTENT_WEBSITE");
registerNewError("CERTBOT_IS_NOT_INSTALLED");
registerNewError("CERTBOT_ERROR");
registerNewError("OPENSSL_DHPARAM_GENERATING_ERROR");
registerNewError("CONFIG_INIT_ERROR");
registerNewError("EXEC_FAILED");
registerNewError("CERTBOT_TIMEOUT_ERROR");

function module.try_ssl_certification_creation(method, domain, webserverType)
    if webserverType ~= "nginx" and webserverType ~= "apache" then
        return module.errors.INVALID_WEBSERVER_TYPE;
    end

    if method == "http-01" then
        local websites = {};

        if webserverType == "nginx" then
            nginx.init_dirs();

            websites = nginx.server_impl.get_current_available_websites();
        elseif webserverType == "apache" then
            apache.init_dirs();

            websites = apache.server_impl.get_current_available_websites();
        end

        if not module.install_certbot() then
            return module.errors.CERTBOT_IS_NOT_INSTALLED;
        end

        local websiteData = false;

        for t, v in pairs(websites) do
            if v.websiteUrl == domain then
                websiteData = v;
                break;
            end
        end

        if not websiteData then
            return module.errors.NON_EXISTENT_WEBSITE;
        end

        local retLines, retCode = linux.exec_command_with_proc_ret_code("certbot certonly -n "..tostring(dryRunStr).." --agree-tos --register-unsafely-without-email --no-eff-email --webroot --webroot-path "..tostring(websiteData.rootPath).." -d "..tostring(domain), true, nil, true);
        -- local retCode = 0; --FOR TESTING PURPOSES

        local hasCertificate = retCode == 0;
        local domainPath = "/etc/letsencrypt/live/"..tostring(domain).."/";

        if retLines and retLines:find("You have an existing certificate that has exactly the same domains or certificate name you requested and isn't close to expiry.", 0, true) then
            hasCertificate = true;
        elseif retLines and retLines:find("Successfully received certificate.") then
            hasCertificate = true;
        end

        if retCode ~= 0 then
            return module.errors.CERTBOT_ERROR, retCode, retLines;
        end

        --Diffie-Hellman Ephemeral algorithm
        local filePathForDHParam = domainPath..dhParamFileName;

        if not linux.exists(filePathForDHParam) then
            local retLines, retCode = linux.exec_command_with_proc_ret_code("openssl dhparam -out "..tostring(filePathForDHParam).." "..tostring(dhParamBytes), nil, nil, true);

            if retCode ~= 0 then
                return module.errors.OPENSSL_DHPARAM_GENERATING_ERROR, retCode, retLines;
            end
        end

        local configInit = false;

        if webserverType == "nginx" then
            configInit = nginx.server_impl.init_ssl_for_website(domain, {
                certPath = domainPath..certFileName,
                keyPath = domainPath..keyFileName,
                dhParamPath = filePathForDHParam
            });
        elseif webserverType == "apache" then
            configInit = apache.server_impl.init_ssl_for_website(domain, {
                certPath = domainPath..certFileName,
                keyPath = domainPath..keyFileName,
                dhParamPath = filePathForDHParam
            });
        end

        if configInit ~= true then
            return module.errors.CONFIG_INIT_ERROR;
        end

        return true;
    end

    if method == "dns" then
        local websites = {};

        if webserverType == "nginx" then
            nginx.init_dirs();

            websites = nginx.server_impl.get_current_available_websites();
        elseif webserverType == "apache" then
            apache.init_dirs();

            websites = apache.server_impl.get_current_available_websites();
        end

        if not module.install_certbot() then
            return module.errors.CERTBOT_IS_NOT_INSTALLED;
        end

        local websiteData = false;

        for t, v in pairs(websites) do
            if v.websiteUrl == domain then
                websiteData = v;
                break;
            end
        end

        if not websiteData then
            return module.errors.NON_EXISTENT_WEBSITE;
        end

        local tempFileName = os.tmpname();
        local tempFileNameForStdOut = os.tmpname();

        local certbotPIDStuff = general.readAllFileContents("certbot_pid.txt");

        if certbotPIDStuff then
            os.execute("kill -9 "..tostring(certbotPIDStuff));
        end

        linux.deleteFile("certbot_pid.txt");

        print("[Certbot DNS] Várunk a certbot háttérbeli elindulására...");

        local formattedCmd = "(certbot certonly -n "..tostring(dryRunStr).." --agree-tos --register-unsafely-without-email --no-eff-email --manual --preferred-challenges dns --manual-auth-hook \"sh ./authenticator.sh \""..tostring(tempFileName).."\"\" -d "..tostring(domain).." > \""..tostring(tempFileNameForStdOut).."\" 2>&1; echo $? > \""..tostring(tempFileName).."\") & echo $! > certbot_pid.txt";

        os.execute(formattedCmd);

        if not linux.exists("certbot_pid.txt") then
            return module.errors.EXEC_FAILED;
        end

        local timeoutCounter = 0;
        local retCode = -1;

        local cleanupCertBot = function(killPID)
            linux.deleteFile(tempFileName);
            linux.deleteFile(tempFileNameForStdOut);

            local certbotPIDStuff = general.readAllFileContents("certbot_pid.txt");

            if certbotPIDStuff and killPID then
                os.execute("kill -9 "..tostring(certbotPIDStuff));
            end

            linux.deleteFile("certbot_pid.txt");
        end;
        
        while true do
            timeoutCounter = timeoutCounter + 1;

            local fileHandle = io.open(tempFileName, "r");

            if fileHandle then
                local readData = fileHandle:read("*a");
                fileHandle:close();

                local linesIterator = readData:gmatch("[^\r\n]+");

                if linesIterator then
                    local lines = {};

                    for line in linesIterator do
                        table.insert(lines, line);
                    end

                    if #lines == 1 and lines[1] ~= "ready" then
                        retCode = tonumber(lines[1]);

                        break;
                    elseif #lines == 3 then
                        local dnsTXTName = lines[1];
                        local domain = lines[2];
                        local dnsTXTValue = lines[3];

                        print("[Certbot DNS] Létre kell hozzon egy DNS TXT rekordot a(z) "..tostring(domain).." weboldalnál az ellenőrzéshez.");
                        print("[Certbot DNS] => DNS rekord név: "..tostring(dnsTXTName));
                        print("[Certbot DNS] => DNS rekord érték: "..tostring(dnsTXTValue));
                        print("[Certbot DNS] Írja be, hogy ready, ha a DNS rekordot sikeresen létrehozta, majd nyomjon ENTER-t: ");

                        while true do
                            local readData = io.stdin:read();

                            if readData == "ready" then
                                print("[Certbot DNS] Jel küldése a háttérben futó certbot processznek...");

                                break;
                            end
                        end

                        local writeFileHandle = io.open(tempFileName, "w");

                        if not writeFileHandle then
                            print("[Certbot DNS] error while opening "..tostring(tempFileName).." for writing!");

                            cleanupCertBot(true);

                            return false;
                        end

                        writeFileHandle:write("ready");
                        writeFileHandle:flush();
                        writeFileHandle:close();
                    end
                end
            end

            if timeoutCounter >= 60 then
                cleanupCertBot(true);

                return module.errors.CERTBOT_TIMEOUT_ERROR;
            end

            sleep(1);
        end

        local retLines = general.readAllFileContents(tempFileNameForStdOut);

        cleanupCertBot();

        print("[Certbot DNS] retcode: "..tostring(retCode).." retLines: "..tostring(retLines));

        local hasCertificate = retCode == 0;
        local domainPath = "/etc/letsencrypt/live/"..tostring(domain).."/";

        if retLines and retLines:find("You have an existing certificate that has exactly the same domains or certificate name you requested and isn't close to expiry.", 0, true) then
            hasCertificate = true;
        elseif retLines and retLines:find("Successfully received certificate.") then
            hasCertificate = true;
        end

        if retCode ~= 0 then
            return module.errors.CERTBOT_ERROR, retCode, retLines;
        end

        --Diffie-Hellman Ephemeral algorithm
        local filePathForDHParam = domainPath..dhParamFileName;

        if not linux.exists(filePathForDHParam) then
            local retLines, retCode = linux.exec_command_with_proc_ret_code("openssl dhparam -out "..tostring(filePathForDHParam).." "..tostring(dhParamBytes), nil, nil, true);

            if retCode ~= 0 then
                return module.errors.OPENSSL_DHPARAM_GENERATING_ERROR, retCode, retLines;
            end
        end

        local configInit = false;

        if webserverType == "nginx" then
            configInit = nginx.server_impl.init_ssl_for_website(domain, {
                certPath = domainPath..certFileName,
                keyPath = domainPath..keyFileName,
                dhParamPath = filePathForDHParam
            });
        elseif webserverType == "apache" then
            configInit = apache.server_impl.init_ssl_for_website(domain, {
                certPath = domainPath..certFileName,
                keyPath = domainPath..keyFileName,
                dhParamPath = filePathForDHParam
            });
        end

        if configInit ~= true then
            return module.errors.CONFIG_INIT_ERROR, configInit;
        end

        return true;
    end

    return false;
end

function module.init()
    return module.install_certbot();
    --print("Certbot install ret: "..tostring(module.install_certbot()));
    --print("certdatas: "..tostring(inspect(module.get_cert_datas())));
    --print("ssl certificate creation: "..tostring(module.try_ssl_certification_creation("http-01", "lszlo.ltd", "nginx")));
end

return module
