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
    ["nginxUser"] = "nginx-www",
    ["nginxUserComment"] = "User for running nginx daemon & websites & PHP-FPM. For higher security, use different user for PHP-FPM per website",
    ["nginxUserShell"] = "/bin/false",
    ["baseDir"] = nil,
    ["errors"] = {}
};

local bootstrapModule = false;

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

function module.formatPathInsideBasedir(path)
    return general.concatPaths(module["baseDir"], "/", path);
end

local areDirsInited = false;
registerNewError("FAILED_TO_INIT_USER");
registerNewError("FAILED_TO_UPDATE_USER");
registerNewError("FAILED_TO_CREATE_WEBSITECONFIGS_DIR");
registerNewError("FAILED_TO_CHOWN_WEBSITECONFIGS_DIR");
registerNewError("FAILED_TO_CREATE_WWWDATAS_DIR");
registerNewError("FAILED_TO_CHOWN_WWWDATAS_DIR");

function module.initDirs()
    if areDirsInited then
        return true;
    end

    if not module.checkNginxUserExistence() then
        local ret, retForUserCreation = module.createNginxUser();
    
        if ret ~= true then
            print("[nginx initDirs error] Failed to initialize nginx user! Ret: "..tostring(retForUserCreation));

            return module.errors.FAILED_TO_INIT_USER;
        end
    end

    if not module.updateExistingNginxUser() then
        print("[nginx initDirs error] Failed to update existing "..tostring(module.nginxUser).." user!");

        return module.errors.FAILED_TO_UPDATE_USER;
    end

    local nginxHomeDir = module.getNginxHomeDir();
    module["baseDir"] = nginxHomeDir;

    local pathForConfigs = module.formatPathInsideBasedir("websiteconfigs/");

    if not linux.isDir(pathForConfigs) then
        if not linux.mkDir(pathForConfigs) then
            print("[nginx initDirs error] Failed to create website config folder at path "..tostring(pathForConfigs));

            return module.errors.FAILED_TO_CREATE_WEBSITECONFIGS_DIR;
        end
    end

    if not linux.chown(pathForConfigs, module.nginxUser, true) then
        print("[nginx initDirs error] couldn't chown folder at path "..tostring(pathForConfigs).." for user "..tostring(module.nginxUser));

        return module.errors.FAILED_TO_CHOWN_WEBSITECONFIGS_DIR;
    end

    module["website_configs_dir"] = pathForConfigs;

    local pathForWWWDatas = module.formatPathInsideBasedir("wwwdatas/");

    if not linux.isDir(pathForWWWDatas) then
        if not linux.mkDir(pathForWWWDatas) then
            print("[nginx initDirs error] Failed to create website wwwdata folder at path "..tostring(pathForWWWDatas));

            return module.errors.FAILED_TO_CREATE_WWWDATAS_DIR;
        end
    end

    if not linux.chown(pathForWWWDatas, module.nginxUser, true) then
        print("[nginx initDirs error] couldn't chown folder at path "..tostring(pathForWWWDatas).." for user "..tostring(module.nginxUser));

        return module.errors.FAILED_TO_CHOWN_WEBSITECONFIGS_DIR;
    end

    module["www_datas_dir"] = pathForWWWDatas;

    areDirsInited = true;

    return true;
end

function module.checkNginxUserExistence()
    return linux.checkIfUserExists(module["nginxUser"]);
end

function module.createNginxUser(homeDir)
    return linux.createUserWithName(module["nginxUser"], module["nginxUserComment"], module["nginxUserShell"], homeDir);
end

function module.updateExistingNginxUser()
    return linux.updateUser(module["nginxUser"], module["nginxUserComment"], module["nginxUserShell"]);
end

function module.getNginxHomeDir()
    return linux.getUserHomeDir(module["nginxUser"]);
end

function module.getNginxMasterConfigPathFromDaemon()
    if module["cached_nginx_conf_path"] then
        return module["cached_nginx_conf_path"];
    end

    local retLines, retCode = linux.execCommandWithProcRetCode("nginx -V", true, nil, true);

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

registerNewError("DIRS_ARENT_INITED");
registerNewError("FAILED_TO_RETRIEVE_MASTER_CONFIG_PATH");
registerNewError("FAILED_TO_READ_MASTER_CONFIG");
registerNewError("FAILED_TO_PARSE_MASTER_CONFIG");
registerNewError("NO_USER_DIRECTIVE_FOUND");
registerNewError("NO_HTTP_BLOCK_FOUND");
registerNewError("COULDNT_OPEN_FILE_HANDLE_TO_CONF");

function module.initializeServer()
    if not areDirsInited then
        print("[nginx initializeServer error] init_dir didn't finish successfully!");

        return module.errors.DIRS_ARENT_INITED;
    end

    local nginxConfFile = module.getNginxMasterConfigPathFromDaemon();

    if not nginxConfFile then
        print("[nginx initializeServer error] couldn't retrieve nginx config file path!");

        return module.errors.FAILED_TO_RETRIEVE_MASTER_CONFIG_PATH;
    end

    local nginxFileContents = general.readAllFileContents(nginxConfFile);

    if not nginxFileContents then
        print("[nginx initializeServer error] nginx master config at "..tostring(nginxConfFile).." doesn't exist!");

        --TODO: maybe regenerate it?

        return module.errors.FAILED_TO_READ_MASTER_CONFIG;
    end

    local nginxConfigInstance = nginxConfigHandler:new(nginxFileContents);

    if not nginxConfigInstance then
        print("[nginx initializeServer error] couldn't parse nginx master config at "..tostring(nginxConfFile));

        --TODO: maybe regenerate it?

        return module.errors.FAILED_TO_PARSE_MASTER_CONFIG;
    end

    local parsedNginxConfDataRaw = nginxConfigInstance:getParsedLines();
    local parsedNginxConfDataLines = nginxConfigInstance:getParamsToIdx();

    --print(inspect(parsedNginxConfDataLines));

    local configNeedsRefreshing = false;

    if parsedNginxConfDataLines["user"] then
        local userIdx = parsedNginxConfDataLines["user"];

        if #userIdx > 1 then
            print("[nginx initializeServer error] Error while parsing nginx config, user directive should only be once in the config!");

            return module.errors.NO_USER_DIRECTIVE_FOUND;
        end

        userIdx = userIdx[1];

        local userData = parsedNginxConfDataRaw[userIdx];

        if userData.args[1]["data"] ~= module.nginxUser then
            userData.args[1]["data"] = module.nginxUser;

            configNeedsRefreshing = true;
        end

        --print(inspect(userData));
    else
        nginxConfigInstance:insertNewData({["paramName"] = {
            data = "user"
        }, args = {
            {data = module.nginxUser}
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
            print("[nginx initializeServer error] there is no http block inside config file at path: "..tostring(nginxConfFile));

            return module.errors.NO_HTTP_BLOCK_FOUND;
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
            print("[nginx initializeServer error] Couldn't overwrite nginx config file at path "..tostring(nginxConfFile));

            return module.errors.COULDNT_OPEN_FILE_HANDLE_TO_CONF;
        end

        configFileHandle:write(nginxConfigInstance:toString());
        configFileHandle:flush();
        configFileHandle:close();
    end

    --print("new config: \n"..tostring(nginxConfigHandler.writeNginxConfig(parsedNginxConfDataRaw)));

    --print("currentWebsitesAvailable: "..tostring(inspect(module.getCurrentAvailableWebsites())));

    --print("lszlo.ltd creation ret: "..tostring(module.createNewWebsite("lszlo.ltd")));

    --print("=> currentWebsitesAvailable after: "..tostring(inspect(module.getCurrentAvailableWebsites())));

    --print("lszlo.ltd deletion ret: "..tostring(module.deleteWebsite("lszlo.ltd")));

    --print("=> currentWebsitesAvailable after: "..tostring(inspect(module.getCurrentAvailableWebsites())));

    return true;
end

registerNewError("WEBSITE_ALREADY_EXISTS");
registerNewError("SAMPLE_WEBSITE_CONFIG_PARSE_ERROR");
registerNewError("COULDNT_CREATE_WEBSITE_DIR");
registerNewError("COULDNT_CHOWN_WEBSITE_DIR");
registerNewError("COULDNT_CREATE_NEW_WEBSITE_CONF");
registerNewError("COULDNT_CREATE_INDEXHTML");
registerNewError("COULDNT_CHOWN_INDEXHTML");

function module.createNewWebsite(websiteUrl)
    if not areDirsInited then
        return module.errors.DIRS_ARENT_INITED;
    end

    local websites = module.getCurrentAvailableWebsites();

    for t, v in pairs(websites) do
        if v.websiteUrl == websiteUrl then
            return module.errors.WEBSITE_ALREADY_EXISTS;
        end
    end

    local fileConfigInstance = nginxConfigHandler:new(sampleConfigForWebsite);

    if not fileConfigInstance then
        return module.errors.SAMPLE_WEBSITE_CONFIG_PARSE_ERROR;
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

    if not linux.isDir(wwwDataDir) then
        if not linux.mkDir(wwwDataDir) then
            print("[nginx website creation] Failed to create website ("..tostring(websiteUrl)..") wwwdata folder at path "..tostring(wwwDataDir));

            return module.errors.COULDNT_CREATE_WEBSITE_DIR;
        end
    end

    if not linux.chown(wwwDataDir, module.nginxUser, true) then
        print("[nginx website creation] couldn't chown folder at path "..tostring(wwwDataDir).." for user "..tostring(module.nginxUser));

        return module.errors.COULDNT_CHOWN_WEBSITE_DIR;
    end

    local configFileHandle = io.open(websiteConfigFinalPathForNGINX, "w");

    if not configFileHandle then
        print("[nginx website creation] couldn't create new website config at path "..tostring(websiteConfigFinalPathForNGINX));

        return module.errors.COULDNT_CREATE_NEW_WEBSITE_CONF;
    end

    configFileHandle:write(fileConfigInstance:toString());
    configFileHandle:flush();
    configFileHandle:close();

    local indexPath = general.concatPaths(wwwDataDir, "/index.html");
    local indexFileHandle = io.open(indexPath, "w");

    if not indexFileHandle then
        print("[nginx website creation] couldn't create new website index.html at path "..tostring(indexPath));

        return module.errors.COULDNT_CREATE_INDEXHTML;
    end

    indexFileHandle:write("Hey, i'm "..tostring(websiteUrl).."!");
    indexFileHandle:flush();
    indexFileHandle:close();

    if not linux.chown(indexPath, module.nginxUser, true) then
        print("[nginx website creation] couldn't chown index.html at path "..tostring(indexPath).." for user "..tostring(module.nginxUser));

        return module.errors.COULDNT_CHOWN_INDEXHTML;
    end

    return true;
end

registerNewError("WEBSITE_DOESNT_EXIST");
registerNewError("COULDNT_DELETE_WEBSITE_DIR");
registerNewError("COULDNT_DELETE_WEBSITE_CONFIG");

function module.deleteWebsite(websiteUrl)
    local websites = module.getCurrentAvailableWebsites();
    local foundWebsiteData = false;

    for t, v in pairs(websites) do
        if v.websiteUrl == websiteUrl then
            foundWebsiteData = v;

            break;
        end
    end

    if not foundWebsiteData then
        return module.errors.WEBSITE_DOESNT_EXIST;
    end

    if not linux.deleteDirectory(foundWebsiteData.rootPath) then
        print("[nginx website deletion] failed to delete folder at path "..tostring(foundWebsiteData.rootPath).." for website "..tostring(websiteUrl));

        return module.errors.COULDNT_DELETE_WEBSITE_DIR;
    end

    if not linux.deleteFile(foundWebsiteData.configPath) then
        print("[nginx website deletion] failed to delete configuration file at path "..tostring(foundWebsiteData.configPath).." for website "..tostring(websiteUrl));

        return module.errors.COULDNT_DELETE_WEBSITE_CONFIG;
    end

    return true;
end

function module.getCurrentAvailableWebsites()
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

registerNewError("CONFIG_FILE_COULDNT_BE_READ");
registerNewError("CONFIG_FILE_COULDNT_BE_PARSED");
registerNewError("CONFIG_FILE_COULDNT_BE_WRITTEN");
registerNewError("COULDNT_COPY_SAMPLE_NGINX_CONFIG");

function module.initSSLForWebsite(webUrl, certDetails)
    local websites = module.getCurrentAvailableWebsites();
    local data = false;

    for t, v in pairs(websites) do
        if v.websiteUrl == webUrl then
            data = v;

            break;
        end
    end

    if not data then
        return module.errors.WEBSITE_DOESNT_EXIST;
    end

    local configFileContents = general.readAllFileContents(data.configPath);

    if not configFileContents then
        return module.errors.CONFIG_FILE_COULDNT_BE_READ;
    end

    local configInstance = nginxConfigHandler:new(configFileContents);

    if not configInstance then
        return module.errors.CONFIG_FILE_COULDNT_BE_PARSED;
    end

    local rawData = configInstance:getParsedLines();
    local paramsToIdx = configInstance:getParamsToIdx();

    -- print("paramsToIdx: "..tostring(inspect(paramsToIdx)));

    --following https://upcloud.com/resources/tutorials/install-lets-encrypt-nginx & https://beguier.eu/nicolas/articles/nginx-tls-security-configuration.html

    local serverNameIdx = paramsToIdx["server_name"][1];
    local serverNameData = rawData[serverNameIdx];
    local posStart = serverNameIdx + 1;

    --Include best practices from Let's Encrypt
    local includeIdx = paramsToIdx["include"];
    local letsEncryptIncludeFound = false;
    local letsEncryptIncludePath = "/etc/letsencrypt/options-ssl-nginx.conf";

    if not linux.exists(letsEncryptIncludePath) then
        local retLines, retCode = linux.execCommandWithProcRetCode("find / -name 'options-ssl-nginx.conf'", true, nil, true);

        if retLines then
            local linesIterator = retLines:gmatch("[^\r\n]+");

            for line in linesIterator do
                if line == letsEncryptIncludePath then
                    break;
                end

                if linux.copy(line, letsEncryptIncludePath) then
                    break;
                else
                    return module.errors.COULDNT_COPY_SAMPLE_NGINX_CONFIG;
                end
            end
        end
    end

    if includeIdx then
        for _, v in pairs(includeIdx) do
            local data = rawData[v];

            if data.args[1].data == letsEncryptIncludePath then
                letsEncryptIncludeFound = true;
                break;
            end
        end
    end

    local insertEndingComment = false;

    if not letsEncryptIncludeFound then
        configInstance:insertNewData({["comment"] = " SSL Configuration based on https://upcloud.com/resources/tutorials/install-lets-encrypt-nginx & https://beguier.eu/nicolas/articles/nginx-tls-security-configuration.html", blockDeepness = serverNameData.blockDeepness}, posStart);
        posStart = posStart + 1;

        configInstance:insertNewData({["paramName"] = {
            data = "include",
        }, block = serverNameData.block, blockDeepness = serverNameData.blockDeepness, args = {
            {data = letsEncryptIncludePath, quoteStatus = "d"}
        }}, posStart);

        posStart = posStart + 1;

        insertEndingComment = true;
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
            {data = "Strict-Transport-Security"}, {data = "max-age=31536000; includeSubdomains; preload", quoteStatus = "d"}
        }}, posStart);

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
        }, block = serverNameData.block, blockDeepness = serverNameData.blockDeepness, args = {{data = certDetails.dhParamPath, quoteStatus = "d"}}}, posStart);

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
        }, block = serverNameData.block, blockDeepness = serverNameData.blockDeepness, args = {{data = certDetails.certPath, quoteStatus = "d"}}}, posStart);

        posStart = posStart + 1;
    end

    local ssl_certificate_keyIdx = paramsToIdx["ssl_certificate_key"];

    if ssl_certificate_keyIdx then
        local data = rawData[ssl_certificate_keyIdx[1]];

        data.args = {{data = certDetails.keyPath}};
    else
        configInstance:insertNewData({["paramName"] = {
            data = "ssl_certificate_key",
        }, block = serverNameData.block, blockDeepness = serverNameData.blockDeepness, args = {{data = certDetails.keyPath, quoteStatus = "d"}}}, posStart);

        posStart = posStart + 1;
    end
    
    --Redirect unencrypted connections
    local blockName = 'if ($scheme != "https")';
    local blockStartSchemeIdx = paramsToIdx["block:"..tostring(blockName)];

    if not blockStartSchemeIdx then
        local blockDeepness = serverNameData.blockDeepness;

        configInstance:insertNewData({["comment"] = " Redirect unencrypted connections", blockDeepness = serverNameData.blockDeepness}, posStart);
        posStart = posStart + 1;

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
        return module.errors.CONFIG_FILE_COULDNT_BE_WRITTEN;
    end

    fileHandle:write(configInstance:toString());
    fileHandle:flush();
    fileHandle:close();

    -- print("<=========>SSL ENABLED CONFIG<==============>");
    -- print(tostring(configInstance:toString()));

    if module.isRunning() then
        module.stopServer();
        module.startServer();
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
