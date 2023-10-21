local os = require("os");
local packageManager = require("apt_packages");
local linux = require("linux");
local general = require("general");
local nginxConfigHandlerModule = require("nginxHandler/nginx_config_handler");
local inspect = require("inspect");

local sampleConfigForWebsite = [[
    ##
    # You should look at the following URL's in order to grasp a solid understanding
    # of Nginx configuration files in order to fully unleash the power of Nginx.
    # https://www.nginx.com/resources/wiki/start/
    # https://www.nginx.com/resources/wiki/start/topics/tutorials/config_pitfalls/
    # https://wiki.debian.org/Nginx/DirectoryStructure
    #
    # In most cases, administrators will remove this file from sites-enabled/ and
    # leave it as reference inside of sites-available where it will continue to be
    # updated by the nginx packaging team.
    #
    # This file will automatically load configuration files provided by other
    # applications, such as Drupal or Wordpress. These applications will be made
    # available underneath a path with that package name, such as /drupal8.
    #
    # Please see /usr/share/doc/nginx-doc/examples/ for more detailed examples.
    ##
    
    # Default server configuration
    #
    server {
        server_name insert_website_here;
    
        listen 80;
    
        root /home/wwwdata;
    
        # Add index.php to the list if you are using PHP
        index index.html index.htm index.nginx-debian.html;
    
        location / {
            # First attempt to serve request as file, then
            # as directory, then fall back to displaying a 404.
            try_files $uri $uri/ =404;
        }

        # pass PHP scripts to FastCGI server
        #
        #location ~ \.php$ {
        #	include snippets/fastcgi-php.conf;
        #
        #	# With php-fpm (or other unix sockets):
        #	fastcgi_pass unix:/run/php/php7.4-fpm.sock;
        #	# With php-cgi (or other tcp sockets):
        #	fastcgi_pass 127.0.0.1:9000;
        #}
    
        # deny access to .htaccess files, if Apache's document root
        # concurs with nginx's one
        #
        #location ~ /\.ht {
        #	deny all;
        #}
    }    
]];

local module = {
    ["nginx_user"] = "nginx-www",
    ["nginx_user_comment"] = "User for running nginx daemon & websites & PHP-FPM. For higher security, use different user for PHP-FPM per website",
    ["nginx_user_shell"] = "/bin/false",
    ["base_dir"] = nil
};

function module.formatPathInsideBasedir(path)
    return general.concatPaths(module["base_dir"], "/", path);
end

local isInited = false;

function module.init_dirs()
    if isInited then
        return true;
    end

    isInited = true;

    if not module.check_nginx_user_existence() then
        local ret, retForUserCreation = module.create_nginx_user();
    
        if ret ~= true then
            print("[nginx init] Failed to initialize nginx user! Ret: "..tostring(retForUserCreation));

            return false;
        end
    end

    if not module.update_existing_nginx_user() then
        print("[nginx init] Failed to update existing "..tostring(module.nginx_user).." user!");

        return false;
    end

    local nginxHomeDir = module.get_nginx_home_dir();
    module["base_dir"] = nginxHomeDir;

    local pathForConfigs = module.formatPathInsideBasedir("websiteconfigs/");

    if not linux.isdir(pathForConfigs) then
        if not linux.mkdir(pathForConfigs) then
            print("[nginx init] Failed to create website config folder at path "..tostring(pathForConfigs));

            return false;
        end
    end

    if not linux.chown(pathForConfigs, module.nginx_user, true) then
        print("[nginx init] couldn't chown folder at path "..tostring(pathForConfigs).." for user "..tostring(module.nginx_user));

        return false;
    end

    module["website_configs_dir"] = pathForConfigs;

    local pathForWWWDatas = module.formatPathInsideBasedir("wwwdatas/");

    if not linux.isdir(pathForWWWDatas) then
        if not linux.mkdir(pathForWWWDatas) then
            print("[nginx init] Failed to create website wwwdata folder at path "..tostring(pathForWWWDatas));

            return false;
        end
    end

    if not linux.chown(pathForWWWDatas, module.nginx_user, true) then
        print("[nginx init] couldn't chown folder at path "..tostring(pathForWWWDatas).." for user "..tostring(module.nginx_user));

        return false;
    end

    module["www_datas_dir"] = pathForWWWDatas;

    return module.initialize_server();
end

function module.check_nginx_user_existence()
    return linux.check_if_user_exists(module["nginx_user"]);
end

function module.create_nginx_user(homeDir)
    return linux.create_user_with_name(module["nginx_user"], module["nginx_user_comment"], module["nginx_user_shell"], homeDir);
end

function module.update_existing_nginx_user()
    return linux.update_user(module["nginx_user"], module["nginx_user_comment"], module["nginx_user_shell"]);
end

function module.get_nginx_home_dir()
    return linux.get_user_home_dir(module["nginx_user"]);
end

function module.get_nginx_master_config_path_from_daemon()
    if module["cached_nginx_conf_path"] then
        return module["cached_nginx_conf_path"];
    end

    local retLines, retCode = linux.exec_command_with_proc_ret_code("nginx -V", true, nil, true);

    if retCode ~= 0 then
        return false;
    end

    local confPathStartStr = "--conf-path=";
    local confPathStart = retLines:find(confPathStartStr, 0, true);
    local confPathEnd = retLines:find(" --", confPathStart + 1, true);

    local confPath = "";

    if confPathStart then
        if confPathEnd then
            confPath = retLines:sub(confPathStart + #confPathStartStr, confPathEnd - 1);
        else
            confPath = retLines:sub(confPathStart + #confPathStartStr);
        end
    end

    module["cached_nginx_conf_path"] = confPath;

    return confPath;
end

function module.initialize_server()
    local nginxConfFile = module.get_nginx_master_config_path_from_daemon();

    if not nginxConfFile then
        print("[nginx init] couldn't retrieve nginx config file path!");

        return false;
    end

    local nginxFileContents = general.readAllFileContents(nginxConfFile);

    if not nginxFileContents then
        print("[nginx init] nginx master config at "..tostring(nginxConfFile).." doesn't exist!");

        --TODO: maybe regenerate it?

        return false;
    end

    local nginxConfigInstance = nginxConfigHandler:new(nginxFileContents);

    if not nginxConfigInstance then
        print("[nginx init] couldn't parse nginx master config at "..tostring(nginxConfFile));

        --TODO: maybe regenerate it?

        return false;
    end

    local parsedNginxConfDataRaw = nginxConfigInstance:getParsedLines();
    local parsedNginxConfDataLines = nginxConfigInstance:getParamsToIdx();

    --print(inspect(parsedNginxConfDataLines));

    local configNeedsRefreshing = false;

    if parsedNginxConfDataLines["user"] then
        local userIdx = parsedNginxConfDataLines["user"];

        if #userIdx > 1 then
            print("[nginx init] Error while parsing nginx config, user directive should only be once in the config!");

            return false;
        end

        userIdx = userIdx[1];

        local userData = parsedNginxConfDataRaw[userIdx];

        if userData.args[1]["data"] ~= module.nginx_user then
            userData.args[1]["data"] = module.nginx_user;

            configNeedsRefreshing = true;
        end

        --print(inspect(userData));
    else
        nginxConfigInstance:insertNewData({["paramName"] = {
            data = "user"
        }, args = {
            {data = module.nginx_user}
        }}, 1);

        configNeedsRefreshing = true;
    end

    local foundOurIncludeInsideHTTPBlock = false;
    local websiteConfigsFinalPathForNGINX = general.concatPaths(module["website_configs_dir"], "/*.conf");

    if parsedNginxConfDataLines["include"] then
        for t, dataRawIdx in pairs(parsedNginxConfDataLines["include"]) do
            local data = parsedNginxConfDataRaw[dataRawIdx];

            if data.block == "http" and data.args[1].data == websiteConfigsFinalPathForNGINX then
                foundOurIncludeInsideHTTPBlock = true;

                break;
            end
        end
    end

    if not foundOurIncludeInsideHTTPBlock then
        local httpBlockEnd = parsedNginxConfDataLines["blockend:http"];

        if not httpBlockEnd or #httpBlockEnd == 0 then
            print("[nginx init error] there is no http block inside config file at path: "..tostring(nginxConfFile));

            return false;
        end

        local newPos = httpBlockEnd[1];
        local blockDeepness = parsedNginxConfDataRaw[newPos]["blockDeepness"] + 1;

        nginxConfigInstance:insertNewData({["paramName"] = {
            data = "include",
        }, block = "http", blockDeepness = blockDeepness, args = {
            {data = websiteConfigsFinalPathForNGINX}
        }}, newPos);

        configNeedsRefreshing = true;
    end

    if configNeedsRefreshing then
        local configFileHandle = io.open(nginxConfFile, "w");
        
        if not configFileHandle then
            print("[nginx init] Couldn't overwrite nginx config file at path "..tostring(nginxConfFile));

            return false;
        end

        configFileHandle:write(nginxConfigInstance:toString());
        configFileHandle:flush();
        configFileHandle:close();
    end

    --print("new config: \n"..tostring(nginxConfigHandler.write_nginx_config(parsedNginxConfDataRaw)));

    --print("currentWebsitesAvailable: "..tostring(inspect(module.get_current_available_websites())));

    --print("lszlo.ltd creation ret: "..tostring(module.create_new_website("lszlo.ltd")));

    --print("=> currentWebsitesAvailable after: "..tostring(inspect(module.get_current_available_websites())));

    --print("lszlo.ltd deletion ret: "..tostring(module.delete_website("lszlo.ltd")));

    --print("=> currentWebsitesAvailable after: "..tostring(inspect(module.get_current_available_websites())));

    return true;
end

module.WEBSITE_ALREADY_EXISTS = -1;
module.SAMPLE_WEBSITE_CONFIG_PARSE_ERROR = -2;

function module.create_new_website(websiteUrl)
    local websites = module.get_current_available_websites();

    for t, v in pairs(websites) do
        if v.websiteUrl == websiteUrl then
            return module.WEBSITE_ALREADY_EXISTS;
        end
    end

    local fileConfigInstance = nginxConfigHandler:new(sampleConfigForWebsite);

    if not fileConfigInstance then
        return module.SAMPLE_WEBSITE_CONFIG_PARSE_ERROR;
    end

    local paramsToIdx = fileConfigInstance:getParamsToIdx();
    local configData = fileConfigInstance:getParsedLines();

    local websiteConfigFinalPathForNGINX = general.concatPaths(module["website_configs_dir"], "/"..tostring(websiteUrl)..".conf");
    local wwwDataDir = general.concatPaths(module["www_datas_dir"], "/"..tostring(websiteUrl));

    if paramsToIdx["server_name"] then
        local paramIdx = paramsToIdx["server_name"][1];

        configData[paramIdx].args[1].data = websiteUrl;
    end

    if paramsToIdx["root"] then
        local paramIdx = paramsToIdx["root"][1];

        configData[paramIdx].args[1].data = wwwDataDir;
    end

    if not linux.isdir(wwwDataDir) then
        if not linux.mkdir(wwwDataDir) then
            print("[nginx website creation] Failed to create website ("..tostring(websiteUrl)..") wwwdata folder at path "..tostring(wwwDataDir));

            return false;
        end
    end

    if not linux.chown(wwwDataDir, module.nginx_user, true) then
        print("[nginx website creation] couldn't chown folder at path "..tostring(wwwDataDir).." for user "..tostring(module.nginx_user));

        return false;
    end

    local configFileHandle = io.open(websiteConfigFinalPathForNGINX, "w");

    if not configFileHandle then
        print("[nginx website creation] couldn't create new website config at path "..tostring(websiteConfigFinalPathForNGINX));

        return false;
    end

    configFileHandle:write(fileConfigInstance:toString());
    configFileHandle:flush();
    configFileHandle:close();

    local indexPath = general.concatPaths(wwwDataDir, "/index.html");
    local indexFileHandle = io.open(indexPath, "w");

    if not indexFileHandle then
        print("[nginx website creation] couldn't create new website index.html at path "..tostring(indexPath));

        return false;
    end

    indexFileHandle:write("Hey, i'm "..tostring(websiteUrl).."!");
    indexFileHandle:flush();
    indexFileHandle:close();

    if not linux.chown(indexPath, module.nginx_user, true) then
        print("[nginx website creation] couldn't chown index.html at path "..tostring(indexPath).." for user "..tostring(module.nginx_user));

        return false;
    end

    return true;
end

module.WEBSITE_DOESNT_EXIST = -1;

function module.delete_website(websiteUrl)
    local websites = module.get_current_available_websites();
    local foundWebsiteData = false;

    for t, v in pairs(websites) do
        if v.websiteUrl == websiteUrl then
            foundWebsiteData = v;

            break;
        end
    end

    if not foundWebsiteData then
        return module.WEBSITE_DOESNT_EXIST;
    end

    if not linux.deleteDirectory(foundWebsiteData.rootPath) then
        print("[nginx website deletion] failed to delete folder at path "..tostring(foundWebsiteData.rootPath).." for website "..tostring(websiteUrl));

        return false;
    end

    if not linux.deleteFile(foundWebsiteData.configPath) then
        print("[nginx website deletion] failed to delete configuration file at path "..tostring(foundWebsiteData.configPath).." for website "..tostring(websiteUrl));

        return false;
    end

    return true;
end

function module.get_current_available_websites()
    local websites = {};

    local websiteConfigsFinalPathForNGINX = general.concatPaths(module["website_configs_dir"], "/*.conf");

    local configFilePaths = linux.listDirFiles(websiteConfigsFinalPathForNGINX);

    for t, configFilePath in pairs(configFilePaths) do
        local configFileContents = general.readAllFileContents(configFilePath);
        if configFileContents then
            local parsedConfigInstance = nginxConfigHandler:new(configFileContents);
            if parsedConfigInstance then
                local paramsToIdx = parsedConfigInstance:getParamsToIdx();

                local serverName = "";
                local rootPath = "";

                local websiteUrls = {};

                local serverNameIdxes = paramsToIdx["server_name"];
                if serverNameIdxes then
                    for _, paramIdx in pairs(serverNameIdxes) do
                        local paramData = parsedConfigInstance:getParsedLines()[paramIdx];
                        if paramData then
                            table.insert(websiteUrls, paramData.args[1].data);
                        end
                    end
                end

                local rootIdxes = paramsToIdx["root"];
                if rootIdxes then
                    local paramIdx = rootIdxes[1];
                    local paramData = parsedConfigInstance:getParsedLines()[paramIdx];
                    if paramData then
                        rootPath = paramData.args[1].data;
                    end
                end

                if #websiteUrls > 0 then
                    for _, url in pairs(websiteUrls) do
                        table.insert(websites, {websiteUrl = url, rootPath = rootPath, configPath = configFilePath});
                    end
                else
                    table.insert(websites, {websiteUrl = "unknown", rootPath = rootPath, configPath = configFilePath});
                end
            end
        end
    end

    return websites;
end

module.CONFIG_FILE_COULDNT_BE_READ = -4;
module.CONFIG_FILE_COULDNT_BE_PARSED = -5;
module.CONFIG_FILE_COULDNT_BE_WRITTEN = -5;

function module.init_ssl_for_website(webUrl, certDetails)
    local websites = module.get_current_available_websites();
    local data = false;

    for t, v in pairs(websites) do
        if v.websiteUrl == webUrl then
            data = v;

            break;
        end
    end

    if not data then
        return module.WEBSITE_DOESNT_EXIST;
    end

    local configFileContents = general.readAllFileContents(data.configPath);

    if not configFileContents then
        return module.CONFIG_FILE_COULDNT_BE_READ;
    end

    local configInstance = nginxConfigHandler:new(configFileContents);

    if not configInstance then
        return module.CONFIG_FILE_COULDNT_BE_PARSED;
    end

    local rawData = configInstance:getParsedLines();
    local paramsToIdx = configInstance:getParamsToIdx();

    -- print("paramsToIdx: "..tostring(inspect(paramsToIdx)));

    --following https://upcloud.com/resources/tutorials/install-lets-encrypt-nginx & https://beguier.eu/nicolas/articles/nginx-tls-security-configuration.html

    local serverNameIdx = paramsToIdx["server_name"][1];
    local serverNameData = rawData[serverNameIdx];
    local posStart = serverNameIdx + 1;

    --Only use secure protocols
    local ssl_protocolsIdx = paramsToIdx["ssl_protocols"];
    local currentSSLProtocols = {{data = "TLSv1.2"}, {data = "TLSv1.3"}};
    local insertEndingComment = false;

    if ssl_protocolsIdx then
        local data = rawData[ssl_protocolsIdx[1]];

        data.args = currentSSLProtocols;
    else
        configInstance:insertNewData({["comment"] = " SSL Configuration based on https://upcloud.com/resources/tutorials/install-lets-encrypt-nginx & https://beguier.eu/nicolas/articles/nginx-tls-security-configuration.html", blockDeepness = serverNameData.blockDeepness}, posStart);
        posStart = posStart + 1;

        insertEndingComment = true;

        configInstance:insertNewData({["paramName"] = {
            data = "ssl_protocols",
        }, block = serverNameData.block, blockDeepness = serverNameData.blockDeepness, args = currentSSLProtocols}, posStart);

        posStart = posStart + 1;
    end

    --Enable HTTP Strict Transport Security (HSTS)
    local addHeaderIdx = paramsToIdx["add_header"];
    local hstsFound = false;

    if addHeaderIdx then
        for t, v in pairs(addHeaderIdx) do
            local data = rawData[v];

            if data.args[1].data == "Strict-Transport-Security" then
                hstsFound = true;

                break;
            end
        end
    end

    if not hstsFound then
        configInstance:insertNewData({["paramName"] = {
            data = "add_header",
        }, block = serverNameData.block, blockDeepness = serverNameData.blockDeepness, args = {
            {data = "Strict-Transport-Security"}, {data = "max-age=31536000; includeSubdomains", quoteStatus = "d"}
        }}, posStart);

        posStart = posStart + 1;
    end

    --Enhance cypher suites
    local ssl_ciphersIdx = paramsToIdx["ssl_ciphers"];
    local currentSSLCiphers = {{data = "ECDHE-RSA-CHACHA20-POLY1305:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-RSA-AES256-GCM-SHA384:DHE-RSA-AES256-CCM:DHE-RSA-AES256-CCM8:DHE-RSA-AES256-GCM-SHA384:DHE-RSA-AES128-CCM:DHE-RSA-AES128-CCM8:DHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES128-GCM-SHA256"}};

    if ssl_ciphersIdx then
        local data = rawData[ssl_ciphersIdx[1]];

        data.args = currentSSLCiphers;
    else
        configInstance:insertNewData({["paramName"] = {
            data = "ssl_ciphers",
        }, block = serverNameData.block, blockDeepness = serverNameData.blockDeepness, args = currentSSLCiphers}, posStart);

        posStart = posStart + 1;
    end

    
    local ssl_prefer_server_ciphersIdx = paramsToIdx["ssl_prefer_server_ciphers"];

    if ssl_prefer_server_ciphersIdx then
        local data = rawData[ssl_prefer_server_ciphersIdx[1]];

        data.args = {{data = "on"}};
    else
        configInstance:insertNewData({["paramName"] = {
            data = "ssl_prefer_server_ciphers",
        }, block = serverNameData.block, blockDeepness = serverNameData.blockDeepness, args = {{data = "on"}}}, posStart);

        posStart = posStart + 1;
    end

    --Diffie-Hellman Ephemeral algorithm
    local ssl_dhparamIdx = paramsToIdx["ssl_dhparam"];

    if ssl_dhparamIdx then
        local data = rawData[ssl_dhparamIdx[1]];

        data.args = {{data = certDetails.dhParamPath}};
    else
        configInstance:insertNewData({["paramName"] = {
            data = "ssl_dhparam",
        }, block = serverNameData.block, blockDeepness = serverNameData.blockDeepness, args = {{data = certDetails.dhParamPath}}}, posStart);

        posStart = posStart + 1;
    end
    
    --Cert and privatekey files
    local ssl_certificateIdx = paramsToIdx["ssl_certificate"];

    if ssl_certificateIdx then
        local data = rawData[ssl_certificateIdx[1]];

        data.args = {{data = certDetails.certPath}};
    else
        configInstance:insertNewData({["paramName"] = {
            data = "ssl_certificate",
        }, block = serverNameData.block, blockDeepness = serverNameData.blockDeepness, args = {{data = certDetails.certPath}}}, posStart);

        posStart = posStart + 1;
    end

    local ssl_certificate_keyIdx = paramsToIdx["ssl_certificate_key"];

    if ssl_certificate_keyIdx then
        local data = rawData[ssl_certificate_keyIdx[1]];

        data.args = {{data = certDetails.keyPath}};
    else
        configInstance:insertNewData({["paramName"] = {
            data = "ssl_certificate_key",
        }, block = serverNameData.block, blockDeepness = serverNameData.blockDeepness, args = {{data = certDetails.keyPath}}}, posStart);

        posStart = posStart + 1;
    end
    
    --Redirect unencrypted connections
    local blockName = 'if ($scheme != "https")';
    local blockStartSchemeIdx = paramsToIdx["block:"..tostring(blockName)];

    if not blockStartSchemeIdx then
        configInstance:insertNewData({["comment"] = " Redirect unencrypted connections", blockDeepness = serverNameData.blockDeepness}, posStart);
        posStart = posStart + 1;

        local blockDeepness = serverNameData.blockDeepness;

        configInstance:insertNewData({["blockStart"] = blockName, block = serverNameData.block, blockDeepness = serverNameData.blockDeepness, args = {}}, posStart);
        posStart = posStart + 1;
        blockDeepness = blockDeepness + 1;

        configInstance:insertNewData({["paramName"] = 
            {
                data = 'rewrite',
            }, block = blockName, blockDeepness = blockDeepness, args = {{data = "^"}, {data = "https://$host$request_uri?"}, {data = "permanent"}}
        }, posStart);

        posStart = posStart + 1;
        blockDeepness = blockDeepness - 1;

        configInstance:insertNewData({["blockEnd"] = blockName, block = serverNameData.block, blockDeepness = serverNameData.blockDeepness, args = {}}, posStart);
        posStart = posStart + 1;
    end

    local listenIdxes = paramsToIdx["listen"];
    local foundSSLListen = false;

    for t, v in pairs(listenIdxes) do
        local data = rawData[v];

        if data.args and data.args[2] and data.args[2].data == "ssl" then
            foundSSLListen = true;

            break;
        end
    end

    if not foundSSLListen then
        local blockDeepness = serverNameData.blockDeepness;

        configInstance:insertNewData({["paramName"] = 
            {
                data = 'listen',
            }, block = blockName, blockDeepness = blockDeepness, args = {{data = "443"}, {data = "ssl"}}
        }, posStart);
        posStart = posStart + 1;
    end

    if insertEndingComment then
        configInstance:insertNewData({["comment"] = " SSL Configuration end", blockDeepness = serverNameData.blockDeepness}, posStart);
        posStart = posStart + 1;
    end

    local fileHandle = io.open(data.configPath, "wb");

    if not fileHandle then
        return module.CONFIG_FILE_COULDNT_BE_WRITTEN;
    end

    fileHandle:write(configInstance:toString());
    fileHandle:flush();
    fileHandle:close();

    -- print("<=========>SSL ENABLED CONFIG<==============>");
    -- print(tostring(configInstance:toString()));

    return true;
end

return module;
