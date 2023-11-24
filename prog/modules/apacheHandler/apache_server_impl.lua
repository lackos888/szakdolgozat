local os = require("os");
local packageManager = require("apt_packages");
local linux = require("linux");
local general = require("general");
local apacheConfigHandlerModule = require("apacheHandler/apache_config_handler");
local inspect = require("inspect");
local bootstrapModule = false;

local module = {
    ["apacheUser"] = "apache-www",
    ["apacheUserComment"] = "User for running apache daemon.",
    ["apacheUserShell"] = "/bin/false",
    ["baseDir"] = nil,
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

local sampleConfigForWebsite = [[
<VirtualHost *:80>
# The ServerName directive sets the request scheme, hostname and port that
# the server uses to identify itself. This is used when creating
# redirection URLs. In the context of virtual hosts, the ServerName
# specifies what hostname must appear in the request's Host: header to
# match this virtual host. For the default virtual host (this file) this
# value is not decisive as it is used as a last resort host regardless.
# However, you must set it for any further virtual host explicitly.
        ServerName www.example.com

        ServerAdmin webmaster@localhost
        DocumentRoot /home/wwwdata/

# Available loglevels: trace8, ..., trace1, debug, info, notice, warn,
# error, crit, alert, emerg.
# It is also possible to configure the loglevel for particular
# modules, e.g.
#LogLevel info ssl:warn

        ErrorLog ${APACHE_LOG_DIR}/error.log
        CustomLog ${APACHE_LOG_DIR}/access.log combined

# For most configuration files from conf-available/, which are
# enabled or disabled at a global level, it is possible to
# include a line for only one particular virtual host. For example the
# following line enables the CGI configuration for this host only
# after it has been globally disabled with "a2disconf".
#Include conf-available/serve-cgi-bin.conf
</VirtualHost>

# vim: syntax=apache ts=4 sw=4 sts=4 sr noet
]];

function module.formatPathInsideBasedir(path)
    return general.concatPaths(module["baseDir"], "/", path);
end

function module.checkApacheUserExistence()
    return linux.checkIfUserExists(module["apacheUser"]);
end

function module.createApacheUser(homeDir)
    return linux.createUserWithName(module["apacheUser"], module["apacheUserComment"], module["apacheUserShell"], homeDir);
end

function module.updateExistingApacheUser()
    return linux.updateUser(module["apacheUser"], module["apacheUserComment"], module["apacheUserShell"]);
end

function module.getApacheHomeDir()
    return linux.getUserHomeDir(module["apacheUser"]);
end

function module.getApacheMasterConfigPathFromDaemon()
    if module["cached_apache_conf_path"] then
        return module["cached_apache_conf_path"];
    end

    local retLines, retCode = linux.execCommandWithProcRetCode("apache2 -V", true, nil, true);

    if retCode ~= 1 then
        return false;
    end

    local confPath = nil;

    local linesIterator = retLines:gmatch("[^\r\n]+");

    local argsToSearchFor = {
        ["HTTPD_ROOT="] = false,
        ["SERVER_CONFIG_FILE="] = false
    };

    local httpdPath = false;

    for line in linesIterator do
        for key, val in pairs(argsToSearchFor) do
            local strFound = line:find(key, 0, true);

            if strFound then
                strFound = strFound + #key;

                local sub = line:sub(strFound):gsub('"', ''):gsub('\'', '');

                argsToSearchFor[key] = sub;
            end
        end
    end

    if argsToSearchFor["HTTPD_ROOT="] and argsToSearchFor["SERVER_CONFIG_FILE="] then
        confPath = general.concatPaths(argsToSearchFor["HTTPD_ROOT="], "/"..tostring(argsToSearchFor["SERVER_CONFIG_FILE="]));
    end

    module["cached_apache_conf_path"] = confPath;

    return confPath;
end

local areDirsInited = false;
registerNewError("FAILED_TO_INIT_USER");
registerNewError("FAILED_TO_UPDATE_USER");
registerNewError("FAILED_TO_CREATE_WEBSITECONFIGS_DIR");
registerNewError("FAILED_TO_CHOWN_WEBSITECONFIGS_DIR");
registerNewError("FAILED_TO_CREATE_WWWDATAS_DIR");
registerNewError("FAILED_TO_CHOWN_WWWDATAS_DIR")

function module.initDirs()
    if areDirsInited then
        return true;
    end

    areDirsInited = true;

    if not module.checkApacheUserExistence() then
        local ret, retForUserCreation = module.createApacheUser();
    
        if ret ~= true then
            print("[apache initDirs error] Failed to initialize apache user! Ret: "..tostring(retForUserCreation));

            return module.errors.FAILED_TO_INIT_USER;
        end
    end

    if not module.updateExistingApacheUser() then
        print("[apache initDirs error] Failed to update existing "..tostring(module.apacheUser).." user!");

        return module.errors.FAILED_TO_UPDATE_USER;
    end

    local apacheHomeDir = module.getApacheHomeDir();
    module["baseDir"] = apacheHomeDir;

    local pathForConfigs = module.formatPathInsideBasedir("websiteconfigs/");

    if not linux.isDir(pathForConfigs) then
        if not linux.mkDir(pathForConfigs) then
            print("[apache initDirs error] Failed to create website config folder at path "..tostring(pathForConfigs));

            return module.errors.FAILED_TO_CREATE_WEBSITECONFIGS_DIR;
        end
    end

    if not linux.chown(pathForConfigs, module.apacheUser, true) then
        print("[apache initDirs error] couldn't chown folder at path "..tostring(pathForConfigs).." for user "..tostring(module.apacheUser));

        return module.errors.FAILED_TO_CHOWN_WEBSITECONFIGS_DIR;
    end

    module["website_configs_dir"] = pathForConfigs;

    local pathForWWWDatas = module.formatPathInsideBasedir("wwwdatas/");

    if not linux.isDir(pathForWWWDatas) then
        if not linux.mkDir(pathForWWWDatas) then
            print("[apache initDirs error] Failed to create website wwwdata folder at path "..tostring(pathForWWWDatas));

            return module.errors.FAILED_TO_CREATE_WWWDATAS_DIR;
        end
    end

    if not linux.chown(pathForWWWDatas, module.apacheUser, true) then
        print("[apache initDirs error] couldn't chown folder at path "..tostring(pathForWWWDatas).." for user "..tostring(module.apacheUser));

        return module.errors.FAILED_TO_CHOWN_WEBSITECONFIGS_DI;
    end

    module["www_datas_dir"] = pathForWWWDatas;
    areDirsInited = true;

    return true;
end

registerNewError("DIRS_ARENT_INITED");
registerNewError("FAILED_TO_RETRIEVE_MASTER_CONFIG_PATH");
registerNewError("FAILED_TO_READ_MASTER_CONFIG");
registerNewError("FAILED_TO_PARSE_MASTER_CONFIG");
registerNewError("NO_USER_DIRECTIVE_FOUND");
registerNewError("NO_HTTP_BLOCK_FOUND");
registerNewError("COULDNT_OPEN_FILE_HANDLE_TO_CONF");
registerNewError("COULDNT_OPEN_FILE_HANDLE_TO_ENVVARS");

function module.initializeServer()
    if not areDirsInited then
        print("[apache initializeServer error] init_dir didn't finish successfully!");

        return module.errors.DIRS_ARENT_INITED;
    end

    local apacheConfFile = module.getApacheMasterConfigPathFromDaemon();

    if not apacheConfFile then
        print("[apache initializeServer error] couldn't retrieve apache config file path!");

        return module.errors.FAILED_TO_RETRIEVE_MASTER_CONFIG_PATH;
    end

    local apacheFileContents = general.readAllFileContents(apacheConfFile);

    if not apacheFileContents then
        print("[apache initializeServer error] apache master config at "..tostring(apacheConfFile).." doesn't exist!");

        --TODO: maybe regenerate it?

        return module.errors.FAILED_TO_READ_MASTER_CONFI;
    end

    local apacheConfigInstance = apacheConfigHandler:new(apacheFileContents);

    if not apacheConfigInstance then
        print("[apache initializeServer error] couldn't parse apache master config at "..tostring(apacheConfFile));

        --TODO: maybe regenerate it?

        return module.errors.FAILED_TO_PARSE_MASTER_CONFIG;
    end

    local parsedApacheConfDataRaw = apacheConfigInstance:getParsedLines();
    local parsedApacheConfDataLines = apacheConfigInstance:getParamsToIdx();

    local websiteConfigsFinalPathForApache = general.concatPaths(module["website_configs_dir"], "/*.conf");

    local IncludeOptional = parsedApacheConfDataLines["IncludeOptional"];
    local foundOurIncludeOptionalInsideHTTPBlock = false;
    local configNeedsRefreshing = false;

    if IncludeOptional then
        for t, v in pairs(IncludeOptional) do
            local data = parsedApacheConfDataRaw[v];

            if data and data.args and data.args[1] and data.args[1].data == websiteConfigsFinalPathForApache then
                foundOurIncludeOptionalInsideHTTPBlock = true;

                break;
            end
        end
    end

    if not foundOurIncludeOptionalInsideHTTPBlock then
        local newDataToInsert = {
            blockDeepness = 0,
            paramName = {data = "IncludeOptional"},
            args = {
                {data = websiteConfigsFinalPathForApache}
            }
        };

        if IncludeOptional then
            local lastIdx = IncludeOptional[#IncludeOptional];
            local data = parsedApacheConfDataRaw[lastIdx];
            newDataToInsert["blockDeepness"] = data["blockDeepness"];

            apacheConfigInstance:insertNewData(newDataToInsert, lastIdx + 1);
        else
            apacheConfigInstance:insertNewData(newDataToInsert);
        end

        configNeedsRefreshing = true;
    end

    local ourWWWDataIsIncluded = false;

    local directoryIdx = parsedApacheConfDataLines["block:Directory"];
    if directoryIdx then
        for t, v in pairs(directoryIdx) do
            local data = parsedApacheConfDataRaw[v];

            if data.args and data.args[1] and data.args[1].data == module["www_datas_dir"] then
                ourWWWDataIsIncluded = true;
                break;
            end
        end
    end

    if not ourWWWDataIsIncluded then
        local blockDeepness = 0;

        apacheConfigInstance:insertNewData({
            blockStart = "Directory",
            args = {
                {data = module["www_datas_dir"], quoteStatus = "d"}
            },
            blockDeepness = blockDeepness
        });

            blockDeepness = blockDeepness + 1;

            apacheConfigInstance:insertNewData({
                paramName = {data = "Options"},
                args = {
                    {data = "Indexes"},
                    {data = "FollowSymLinks"}
                },
                blockDeepness = blockDeepness
            });

            apacheConfigInstance:insertNewData({
                paramName = {data = "AllowOverride"},
                args = {
                    {data = "None"},
                },
                blockDeepness = blockDeepness
            });

            apacheConfigInstance:insertNewData({
                paramName = {data = "Require"},
                args = {
                    {data = "all"},
                    {data = "granted"}
                },
                blockDeepness = blockDeepness
            });

        blockDeepness = blockDeepness - 1;

        apacheConfigInstance:insertNewData({
            blockEnd = "Directory",
            blockDeepness = blockDeepness
        });

        configNeedsRefreshing = true;
    end

    if configNeedsRefreshing then
        local configFileHandle = io.open(apacheConfFile, "w");
        
        if not configFileHandle then
            print("[apache initializeServer error] Couldn't overwrite apache config file at path "..tostring(apacheConfFile));

            return module.errors.COULDNT_OPEN_FILE_HANDLE_TO_CONF;
        end

        configFileHandle:write(apacheConfigInstance:toString());
        configFileHandle:flush();
        configFileHandle:close();
    end

    local apacheConfigDir = general.extractDirFromPath(apacheConfFile);
    local envVarsPath = general.concatPaths(apacheConfigDir, "/envvars");

    local envVarsContents = general.readAllFileContents(envVarsPath);

    if not envVarsContents then
        print("[apache initializeServer error] Couldn't read envvars content at path "..tostring(envVarsPath));

        return module.errors.COULDNT_OPEN_FILE_HANDLE_TO_ENVVARS;
    end

    local apacheEnvVarsInstance = apacheEnvvarsHandler:new(envVarsContents);
    local envvarsArgs = apacheEnvVarsInstance:getArgs();

    if envvarsArgs["APACHE_RUN_USER"] ~= module["apacheUser"] or envvarsArgs["APACHE_RUN_GROUP"] ~= module["apacheUser"] then
        envvarsArgs["APACHE_RUN_USER"] = module["apacheUser"];
        envvarsArgs["APACHE_RUN_GROUP"] = module["apacheUser"];

        local envvarsFileHandle = io.open(envVarsPath, "wb");

        if not envvarsFileHandle then
            print("[apache initializeServer error] Couldn't open envvars at path "..tostring(envVarsPath).." for writing!");

            return module.errors.COULDNT_OPEN_FILE_HANDLE_TO_ENVVARS;
        end

        envvarsFileHandle:write(apacheEnvVarsInstance:toString());
        envvarsFileHandle:flush();
        envvarsFileHandle:close();
    end

    -- print("[apache] available websites: "..tostring(inspect(module.getCurrentAvailableWebsites())));
    -- print("[apache] lszlo.ltd website creation ret: "..tostring(module.createNewWebsite("lszlo.ltd")));
    -- print("[apache] => available websites: "..tostring(inspect(module.getCurrentAvailableWebsites())));
    -- print("[apache] lszlo.ltd deletion ret: "..tostring(module.deleteWebsite("lszlo.ltd")));
    -- print("[apache] => available websites: "..tostring(inspect(module.getCurrentAvailableWebsites())));

    --[[
    print("<==NEW CONFIG==>");
    print(tostring(apacheConfigInstance:toString()));

    print("<==PARSEDDATARAW==>");
    print(tostring(inspect(parsedApacheConfDataRaw)));

    print("<==PARSEDDATALINES==>");
    print(tostring(inspect(parsedApacheConfDataLines)));
    ]]

    return true;
end

registerNewError("WEBSITE_ALREADY_EXISTS");
registerNewError("SAMPLE_WEBSITE_CONFIG_PARSE_ERROR");
registerNewError("COULDNT_CREATE_WEBSITE_DIR");
registerNewError("COULDNT_CHOWN_WEBSITE_DIR");
registerNewError("COULDNT_CREATE_NEW_WEBSITE_CONF");
registerNewError("COULDNT_CREATE_INDEXHTML");
registerNewError("COULDNT_CHOWN_INDEXHTML");

module.WEBSITE_ALREADY_EXISTS = -1;
module.SAMPLE_WEBSITE_CONFIG_PARSE_ERROR = -2;

function module.createNewWebsite(websiteUrl)
    local websites = module.getCurrentAvailableWebsites();

    for t, v in pairs(websites) do
        if v.websiteUrl == websiteUrl then
            return module.errors.WEBSITE_ALREADY_EXISTS;
        end
    end

    local fileConfigInstance = apacheConfigHandler:new(sampleConfigForWebsite);

    if not fileConfigInstance then
        return module.errors.SAMPLE_WEBSITE_CONFIG_PARSE_ERROR;
    end

    local paramsToIdx = fileConfigInstance:getParamsToIdx();
    local configData = fileConfigInstance:getParsedLines();

    local websiteConfigFinalPathForApache = general.concatPaths(module["website_configs_dir"], "/"..tostring(websiteUrl)..".conf");
    local wwwDataDir = general.concatPaths(module["www_datas_dir"], "/"..tostring(websiteUrl));

    if paramsToIdx["ServerName"] then
        local paramIdx = paramsToIdx["ServerName"][1];

        configData[paramIdx].args[1].data = websiteUrl;
    end

    if paramsToIdx["DocumentRoot"] then
        local paramIdx = paramsToIdx["DocumentRoot"][1];

        configData[paramIdx].args[1].data = wwwDataDir;
    end

    if not linux.isDir(wwwDataDir) then
        if not linux.mkDir(wwwDataDir) then
            print("[apache website creation] Failed to create website ("..tostring(websiteUrl)..") wwwdata folder at path "..tostring(wwwDataDir));

            return module.errors.COULDNT_CREATE_WEBSITE_DIR;
        end
    end

    if not linux.chown(wwwDataDir, module.apacheUser, true) then
        print("[apache website creation] couldn't chown folder at path "..tostring(wwwDataDir).." for user "..tostring(module.apacheUser));

        return module.errors.COULDNT_CHOWN_WEBSITE_DIR;
    end

    local configFileHandle = io.open(websiteConfigFinalPathForApache, "w");

    if not configFileHandle then
        print("[apache website creation] couldn't create new website config at path "..tostring(websiteConfigFinalPathForApache));

        return module.errors.COULDNT_CREATE_NEW_WEBSITE_CONF;
    end

    configFileHandle:write(fileConfigInstance:toString());
    configFileHandle:flush();
    configFileHandle:close();

    local indexPath = general.concatPaths(wwwDataDir, "/index.html");
    local indexFileHandle = io.open(indexPath, "w");

    if not indexFileHandle then
        print("[apache website creation] couldn't create new website index.html at path "..tostring(indexPath));

        return module.errors.COULDNT_CREATE_INDEXHTML;
    end

    indexFileHandle:write("Hey, i'm "..tostring(websiteUrl).."!");
    indexFileHandle:flush();
    indexFileHandle:close();

    if not linux.chown(indexPath, module.apacheUser, true) then
        print("[apache website creation] couldn't chown index.html at path "..tostring(indexPath).." for user "..tostring(module.apacheUser));

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
        print("[apache website deletion] failed to delete folder at path "..tostring(foundWebsiteData.rootPath).." for website "..tostring(websiteUrl));

        return module.errors.COULDNT_DELETE_WEBSITE_DIR;
    end

    if not linux.deleteFile(foundWebsiteData.configPath) then
        print("[apache website deletion] failed to delete configuration file at path "..tostring(foundWebsiteData.configPath).." for website "..tostring(websiteUrl));

        return module.errors.COULDNT_DELETE_WEBSITE_CONFI;
    end

    return true;
end

function module.getCurrentAvailableWebsites(dirPath)
    local websites = {};

    local websiteConfigsFinalPathForApache = dirPath and dirPath or general.concatPaths(module["website_configs_dir"], "/*.conf");

    local configFilePaths = linux.listDirFiles(websiteConfigsFinalPathForApache);

    for t, configFilePath in pairs(configFilePaths) do
        local configFileContents = general.readAllFileContents(configFilePath);

        if configFileContents then
            local parsedConfigInstance = apacheConfigHandler:new(configFileContents);

            if parsedConfigInstance then
                local paramsToIdx = parsedConfigInstance:getParamsToIdx();
                local parsedLines = parsedConfigInstance:getParsedLines();

                local websiteUrls = {};
                local serverName = "";
                local rootPath = "";

                local ServerNameIdxes = paramsToIdx["ServerName"];
                if ServerNameIdxes then
                    local paramIdx = ServerNameIdxes[1];
                    local paramData = parsedLines[paramIdx];
                    if paramData then
                        table.insert(websiteUrls, paramData.args[1].data);
                    end
                end

                local ServerAliasIdxes = paramsToIdx["ServerAlias"];
                if ServerAliasIdxes then
                    for _, paramIdx in pairs(ServerAliasIdxes) do
                        local paramData = parsedLines[paramIdx];
                        if paramData then
                            table.insert(websiteUrls, paramData.args[1].data);
                        end
                    end
                end

                local DocumentRootIdxes = paramsToIdx["DocumentRoot"];
                if DocumentRootIdxes then
                    local paramIdx = DocumentRootIdxes[1];
                    local paramData = parsedLines[paramIdx];
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

registerNewError("COULDNT_ENABLE_HEADERS_MODULE");
registerNewError("COULDNT_ENABLE_SSL_MODULE");
registerNewError("CONFIG_FILE_COULDNT_BE_READ");
registerNewError("CONFIG_FILE_COULDNT_BE_PARSED");
registerNewError("CONFIG_FILE_COULDNT_BE_WRITTEN");
registerNewError("COULDNT_COPY_SAMPLE_APACHE_CONFIG");

function module.initSSLForWebsite(webUrl, certDetails)
    if linux.execCommandWithProcRetCode("a2enmod headers") ~= 0 then
        return module.errors.COULDNT_ENABLE_HEADERS_MODULE;
    end

    if linux.execCommandWithProcRetCode("a2enmod ssl") ~= 0 then
        return module.errors.COULDNT_ENABLE_SSL_MODULE;
    end

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

    local configInstance = apacheConfigHandler:new(configFileContents);

    if not configInstance then
        return module.errors.CONFIG_FILE_COULDNT_BE_PARSED;
    end

    local rawData = configInstance:getParsedLines();
    local paramsToIdx = configInstance:getParamsToIdx();

    local isSSLFound = false;

    local includeIdx = paramsToIdx["Include"];
    local pathForLetsEncryptApacheConfig = "/etc/letsencrypt/options-ssl-apache.conf";

    if not linux.exists(pathForLetsEncryptApacheConfig) then
        local foundStuff = false;

        local retLines, retCode = linux.execCommandWithProcRetCode("find / -name 'options-ssl-apache.conf'", true, nil, true);

        if retLines then
            local linesIterator = retLines:gmatch("[^\r\n]+");

            for line in linesIterator do
                if line == pathForLetsEncryptApacheConfig then
                    foundStuff = true;

                    break;
                end

                if linux.copy(line, pathForLetsEncryptApacheConfig) then
                    foundStuff = true;

                    break;
                else
                    return module.errors.COULDNT_COPY_SAMPLE_APACHE_CONFIG;
                end
            end
        end

        if not foundStuff then
            retLines, retCode = linux.execCommandWithProcRetCode("find / -name 'current-options-ssl-apache.conf'", true, nil, true);

            if retLines then
                local linesIterator = retLines:gmatch("[^\r\n]+");

                for line in linesIterator do
                    if line == pathForLetsEncryptApacheConfig then
                        foundStuff = true;

                        break;
                    end

                    if linux.copy(line, pathForLetsEncryptApacheConfig) then
                        foundStuff = true;

                        break;
                    else
                        return module.errors.COULDNT_COPY_SAMPLE_APACHE_CONFIG;
                    end
                end
            end
        end
    end

    if includeIdx then
        for t, v in pairs(includeIdx) do
            local data = rawData[v];

            if data.args and data.args[1] and data.args[1].data == pathForLetsEncryptApacheConfig then
                isSSLFound = true;

                break;
            end
        end
    end

    if isSSLFound then
        return true;
    end

    local posStart = #rawData;
    local blockDeepness = 0;

    --position variable is not needed here, because it is incremental from the end
    --based on https://pramodshehan.medium.com/ssl-enabled-with-apache-and-certbot-lets-encrypt-3fda4ef92bbc and https://upcloud.com/resources/tutorials/install-lets-encrypt-apache

    configInstance:insertNewData({
        comment = "# SSL Configuration start based on https://pramodshehan.medium.com/ssl-enabled-with-apache-and-certbot-lets-encrypt-3fda4ef92bbc and https://upcloud.com/resources/tutorials/install-lets-encrypt-apache",
        blockDeepness = blockDeepness
    });

    configInstance:insertNewData({
        blockStart = "IfModule",
        args = {
            {data = "mod_ssl.c"}
        },
        blockDeepness = blockDeepness
    });

        blockDeepness = blockDeepness + 1;

        configInstance:insertNewData({
            blockStart = "VirtualHost",
            args = {
                {data = "*:443"}
            },
            blockDeepness = blockDeepness
        });

        blockDeepness = blockDeepness + 1;

            local tempDataContainer = {};

            local serverNameIdx = paramsToIdx["ServerName"]; 
            if serverNameIdx then
                for t, v in pairs(serverNameIdx) do
                    local data = rawData[v];

                    table.insert(tempDataContainer, data);
                end
            end

            for _, data in pairs(tempDataContainer) do
                configInstance:insertNewData({
                    paramName = {data = "ServerName"},
                    args = data.args,
                    blockDeepness = blockDeepness
                });
            end

            tempDataContainer = {};

            local serverAliasIdx = paramsToIdx["ServerAlias"]; 
            if serverAliasIdx then
                for t, v in pairs(serverAliasIdx) do
                    local data = rawData[v];

                    table.insert(tempDataContainer, data);
                end
            end

            for _, data in pairs(tempDataContainer) do
                configInstance:insertNewData({
                    paramName = {data = "ServerAlias"},
                    args = data.args,
                    blockDeepness = blockDeepness
                });
            end

            configInstance:insertNewData({
                paramName = {data = "DocumentRoot"},
                args = {
                    {data = data.rootPath}
                },
                blockDeepness = blockDeepness
            });

            configInstance:insertNewData({
                paramName = {data = "ErrorLog"},
                args = {
                    {data = "${APACHE_LOG_DIR}/error_ssl.log"}
                },
                blockDeepness = blockDeepness
            });

            configInstance:insertNewData({
                paramName = {data = "CustomLog"},
                args = {
                    {data = "${APACHE_LOG_DIR}/access_ssl.log"},
                    {data = "combined"}
                },
                blockDeepness = blockDeepness
            });

            configInstance:insertNewData({
                paramName = {data = "Include"},
                args = {
                    {data = pathForLetsEncryptApacheConfig, quoteStatus = "d"},
                },
                blockDeepness = blockDeepness
            });

            configInstance:insertNewData({
                paramName = {data = "SSLCertificateFile"},
                args = {
                    {data = certDetails.certPath, quoteStatus = "d"},
                },
                blockDeepness = blockDeepness
            });

            configInstance:insertNewData({
                paramName = {data = "SSLCertificateKeyFile"},
                args = {
                    {data = certDetails.keyPath, quoteStatus = "d"},
                },
                blockDeepness = blockDeepness
            });

            configInstance:insertNewData({
                paramName = {data = "SSLOpenSSLConfCmd"},
                args = {
                    {data = "DHParameters"},
                    {data = certDetails.dhParamPath, quoteStatus = "d"},
                },
                blockDeepness = blockDeepness
            });

            configInstance:insertNewData({
                paramName = {data = "SSLCompression"},
                args = {
                    {data = "off"}
                },
                blockDeepness = blockDeepness
            });

            configInstance:insertNewData({
                paramName = {data = "Header"},
                args = {
                    {data = "always"},
                    {data = "set"},
                    {data = "Strict-Transport-Security"},
                    {data = "max-age=31536000; includeSubDomains; preload", quoteStatus = "d"}
                },
                blockDeepness = blockDeepness
            });

        blockDeepness = blockDeepness - 1;

        configInstance:insertNewData({
            blockEnd = "VirtualHost",
            blockDeepness = blockDeepness
        });

    blockDeepness = blockDeepness - 1;

    configInstance:insertNewData({
        blockEnd = "IfModule",
        blockDeepness = blockDeepness
    });

    configInstance:insertNewData({
        comment = "# Redirect every http connection to https",
        blockDeepness = blockDeepness
    });

    configInstance:insertNewData({
        blockStart = "IfModule",
        args = {
            {data = "mod_rewrite.c"}
        },
        blockDeepness = blockDeepness
    });

        blockDeepness = blockDeepness + 1;

        configInstance:insertNewData({
            paramName = {data = "RewriteEngine"},
            args = {
                {data = "On"},
            },
            blockDeepness = blockDeepness
        });

        configInstance:insertNewData({
            paramName = {data = "RewriteCond"},
            args = {
                {data = "%{HTTPS}"},
                {data = "off"}
            },
            blockDeepness = blockDeepness
        });

        configInstance:insertNewData({
            paramName = {data = "RewriteRule"},
            args = {
                {data = "^"},
                {data = "https://%{HTTP_HOST}%{REQUEST_URI}"}
            },
            blockDeepness = blockDeepness
        });

    blockDeepness = blockDeepness - 1;

    configInstance:insertNewData({
        blockEnd = "IfModule",
        blockDeepness = blockDeepness
    });

    configInstance:insertNewData({
        comment = "# SSL Configuration end",
        blockDeepness = blockDeepness
    });

    local fileHandle = io.open(data.configPath, "wb");

    if not fileHandle then
        return module.errors.CONFIG_FILE_COULDNT_BE_WRITTEN;
    end

    fileHandle:write(configInstance:toString());
    fileHandle:flush();
    fileHandle:close();

    return true;
end

return function(_bootstrapModule)
    bootstrapModule = _bootstrapModule;

    module.isRunning = bootstrapModule.isRunning;
    module.stopServer = bootstrapModule.stopServer;
    module.startServer = bootstrapModule.startServer;

    return module;
end
