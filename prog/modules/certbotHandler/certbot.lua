local os = require("os");
local aptPackageManager = require("apt_packages");
local snapPackageManager = require("snapd");
local linux = require("linux");
local nginx = require("nginxHandler/nginx");

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

function module.try_ssl_certification_creation(method, domain, webserverType)
    if webserverType ~= "nginx" and webserverType ~= "apache" then
        return module.INVALID_WEBSERVER_TYPE;
    end

    if method == "http-01" then
        if webserverType == "nginx" then
            if not module.install_certbot() then
                return module.CERTBOT_IS_NOT_INSTALLED;
            end

            local websites = nginx.server_impl.get_current_available_websites();

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

            local retLines, retCode = linux.exec_command_with_proc_ret_code("certbot certonly --agree-tos --no-eff-email --email \"\"--nginx -d "..tostring(domain), true, nil, true);

            if retCode == 1 then
                return module.CERTBOT_ERROR, retCode, retLines;
            end
        end
    end

    return false;
end

function module.init()
    print("Certbot install ret: "..tostring(module.install_certbot()));
end

return module
