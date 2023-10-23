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
local dryRunStr = "";

local module = {};

--from http://lua-users.org/wiki/SleepFunction
local clock = os.clock
local function sleep(n)  -- seconds
  local t0 = clock()
  while clock() - t0 <= n do end
end

module.ALREADY_INSTALLED_ERROR = -1;
module.SNAPD_INSTALL_ERROR = -2;

local function isSnapdInstalled()
    return aptPackageManager.is_package_is_installed("snapd");
end

local function installSnapd()
    if isSnapdInstalled() then
        return module.ALREADY_INSTALLED_ERROR;
    end

    local ret1 = aptPackageManager.install_package("snapd");

    if ret1 ~= 0 then
        return module.SNAPD_INSTALL_ERROR;
    end

    local ret2 = snapPackageManager.install_package("core");

    if ret2 ~= 0 then
        return module.SNAPD_INSTALL_ERROR;
    end

    return true;
end

function module.is_certbot_installed()
    if not isSnapdInstalled() then
        return module.ALREADY_INSTALLED_ERROR;
    end

    return snapPackageManager.is_package_installed("certbot");
end

function module.create_certbot_symlink()
    if not linux.exists("/usr/bin/certbot") then
        linux.exec_command_with_proc_ret_code("ln -s /snap/bin/certbot /usr/bin/certbot");
    end
end

function module.install_certbot()
    if not isSnapdInstalled() then
        if not installSnapd() then
            return module.SNAPD_INSTALL_ERROR;
        end
    end

    if module.is_certbot_installed() then
        module.create_certbot_symlink();

        return module.ALREADY_INSTALLED_ERROR;
    end

    if snapPackageManager.install_package("certbot", true) then
        module.create_certbot_symlink();

        return true;
    end
    
    return false;
end

module.INVALID_WEBSERVER_TYPE = -1;
module.NON_EXISTENT_WEBSITE = -2;
module.CERTBOT_IS_NOT_INSTALLED = -3;
module.CERTBOT_ERROR = -4;
module.OPENSSL_DHPARAM_GENERATING_ERROR = -5;
module.CONFIG_INIT_ERROR = -6;
module.EXEC_FAILED = -7;
module.CERTBOT_TIMEOUT_ERROR = -8;

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

function module.try_ssl_certification_creation(method, domain, webserverType)
    if webserverType ~= "nginx" and webserverType ~= "apache" then
        return module.INVALID_WEBSERVER_TYPE;
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
            return module.CERTBOT_IS_NOT_INSTALLED;
        end

        local websiteData = false;

        for t, v in pairs(websites) do
            if v.websiteUrl == domain then
                websiteData = v;
                break;
            end
        end

        if not websiteData then
            return module.NON_EXISTENT_WEBSITE;
        end

        local retLines, retCode = linux.exec_command_with_proc_ret_code("certbot certonly -n "..tostring(dryRunStr).." --agree-tos --no-eff-email --email \"\" --webroot --webroot-path "..tostring(websiteData.rootPath).." -d "..tostring(domain), true, nil, true);
        -- local retCode = 0; --FOR TESTING PURPOSES

        local hasCertificate = retCode == 0;
        local domainPath = "/etc/letsencrypt/live/"..tostring(domain).."/";

        if retLines and retLines:find("You have an existing certificate that has exactly the same domains or certificate name you requested and isn't close to expiry.", 0, true) then
            hasCertificate = true;
        elseif retLines and retLines:find("Successfully received certificate.") then
            hasCertificate = true;
        end

        if retCode ~= 0 then
            return module.CERTBOT_ERROR, retCode, retLines;
        end

        --Diffie-Hellman Ephemeral algorithm
        local filePathForDHParam = domainPath..dhParamFileName;

        if not linux.exists(filePathForDHParam) then
            local retLines, retCode = linux.exec_command_with_proc_ret_code("openssl dhparam -out "..tostring(filePathForDHParam).." 4096");

            if retCode ~= 0 then
                return module.OPENSSL_DHPARAM_GENERATING_ERROR;
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

        if not configInit then
            return module.CONFIG_INIT_ERROR;
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
            return module.CERTBOT_IS_NOT_INSTALLED;
        end

        local websiteData = false;

        for t, v in pairs(websites) do
            if v.websiteUrl == domain then
                websiteData = v;
                break;
            end
        end

        if not websiteData then
            return module.NON_EXISTENT_WEBSITE;
        end

        local tempFileName = os.tmpname();
        local tempFileNameForStdOut = os.tmpname();

        local certbotPIDStuff = general.readAllFileContents("certbot_pid.txt");

        if certbotPIDStuff then
            os.execute("kill -9 "..tostring(certbotPIDStuff));
        end

        linux.deleteFile("certbot_pid.txt");

        local formattedCmd = "(certbot certonly -n "..tostring(dryRunStr).." --agree-tos --no-eff-email --email \"\" --manual --preferred-challenges dns --manual-auth-hook \"sh ./authenticator.sh \""..tostring(tempFileName).."\"\" -d "..tostring(domain).." > \""..tostring(tempFileNameForStdOut).."\" 2>&1; echo $? > \""..tostring(tempFileName).."\") & echo $! > certbot_pid.txt";

        os.execute(formattedCmd);

        if not linux.exists("certbot_pid.txt") then
            return module.EXEC_FAILED;
        end

        local timeoutCounter = 0;
        local retCode = -1;

        local cleanupCertBot = function(killPID)
            linux.deleteFile(tempFileName);
            linux.deleteFile(tempFileNameForStdOut);
            linux.deleteFile("certbot_pid.txt");

            local certbotPIDStuff = general.readAllFileContents("certbot_pid.txt");

            if certbotPIDStuff and killPID then
                os.execute("kill -9 "..tostring(certbotPIDStuff));
            end
        end;

        print("[Certbot DNS] Waiting for certbot start!");
        
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

                        print("[Certbot DNS] You need to create a DNS TXT record at domain "..tostring(domain).." to proceed.");
                        print("[Certbot DNS] => DNS record name: "..tostring(dnsTXTName));
                        print("[Certbot DNS] => DNS record value: "..tostring(dnsTXTValue));
                        print("[Certbot DNS] Type ready when you are ready and press ENTER: ");

                        while true do
                            local readData = io.stdin:read();

                            if readData == "ready" then
                                print("[Certbot DNS] Sending ready command to certbot running in background!");

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

                return module.CERTBOT_TIMEOUT_ERROR;
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
            return module.CERTBOT_ERROR, retCode, retLines;
        end

        --Diffie-Hellman Ephemeral algorithm
        local filePathForDHParam = domainPath..dhParamFileName;

        if not linux.exists(filePathForDHParam) then
            local retLines, retCode = linux.exec_command_with_proc_ret_code("openssl dhparam -out "..tostring(filePathForDHParam).." 4096");

            if retCode ~= 0 then
                return module.OPENSSL_DHPARAM_GENERATING_ERROR;
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

        if not configInit then
            return module.CONFIG_INIT_ERROR;
        end

        return true;
    end

    return false;
end

function module.init()
    print("Certbot install ret: "..tostring(module.install_certbot()));
    --print("certdatas: "..tostring(inspect(module.get_cert_datas())));
    --print("ssl certificate creation: "..tostring(module.try_ssl_certification_creation("http-01", "lszlo.ltd", "nginx")));
end

return module
