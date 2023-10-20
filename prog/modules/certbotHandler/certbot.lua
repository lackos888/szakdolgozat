local os = require("os");
local aptPackageManager = require("apt_packages");
local snapPackageManager = require("snapd");
local linux = require("linux");
local inspect = require("inspect");
local nginx = require("nginxHandler/nginx");
local apache = require("apacheHandler/apache");
local certFileName = "fullchain.pem";
local keyFileName = "privkey.pem";

local module = {};

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

function module.install_certbot()
    if not isSnapdInstalled() then
        if not installSnapd() then
            return module.SNAPD_INSTALL_ERROR;
        end
    end

    if module.is_certbot_installed() then
        linux.exec_command_with_proc_ret_code("ln -s /snap/bin/certbot /usr/bin/certbot");

        return module.ALREADY_INSTALLED_ERROR;
    end

    if snapPackageManager.install_package("certbot", true) then
        linux.exec_command_with_proc_ret_code("ln -s /snap/bin/certbot /usr/bin/certbot");

        return true;
    end
    
    return false;
end

module.INVALID_WEBSERVER_TYPE = -1;
module.NON_EXISTENT_WEBSITE = -2;
module.CERTBOT_IS_NOT_INSTALLED = -3;
module.CERTBOT_ERROR = -4;

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

        local retLines, retCode = linux.exec_command_with_proc_ret_code("certbot certonly -n --agree-tos --no-eff-email --email \"\" --webroot --webroot-path "..tostring(websiteData.rootPath).." -d "..tostring(domain), true, nil, true);

        local hasCertificate = retCode == 0;
        local certAndKeyDir = "/etc/letsencrypt/live/"..tostring(domain).."/";

        if retLines and retLines:find("You have an existing certificate that has exactly the same domains or certificate name you requested and isn't close to expiry.", 0, true) then
            hasCertificate = true;
        elseif retLines and retLines:find("Successfully received certificate.") then
            hasCertificate = true;
        end

        if retCode ~= 0 then
            return module.CERTBOT_ERROR, retCode, retLines;
        end

        if webserverType == "nginx" then
            nginx.server_impl.init_ssl_for_website(domain, {
                certPath = certAndKeyDir..certFileName,
                keyPath = certAndKeyDir..keyFileName
            });
        elseif webserverType == "apache" then
            apache.server_impl.init_ssl_for_website(domain, {
                certPath = certAndKeyDir..certFileName,
                keyPath = certAndKeyDir..keyFileName
            });
        end

        return true;
    end

    return false;
end

function module.init()
    print("Certbot install ret: "..tostring(module.install_certbot()));
    print("certdatas: "..tostring(inspect(module.get_cert_datas())));
    print("ssl certificate creation: "..tostring(module.try_ssl_certification_creation("http-01", "lszlo.ltd", "nginx")));
end

return module
