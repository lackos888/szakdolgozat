local os = require("os");
local packageManager = require("apt_packages");
local linux = require("linux");
local general = require("general");
local apacheConfigHandlerModule = require("apacheHandler/apache_config_handler");
local inspect = require("inspect");

local module = {
    ["apache_user"] = "apache-www",
    ["apache_user_comment"] = "User for running apache daemon.",
    ["apache_user_shell"] = "/bin/false",
    ["base_dir"] = nil
};

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
    return general.concatPaths(module["base_dir"], "/", path);
end

function module.check_apache_user_existence()
    return linux.check_if_user_exists(module["apache_user"]);
end

function module.create_apache_user(homeDir)
    return linux.create_user_with_name(module["apache_user"], module["apache_user_comment"], module["apache_user_shell"], homeDir);
end

function module.update_existing_apache_user()
    return linux.update_user(module["apache_user"], module["apache_user_comment"], module["apache_user_shell"]);
end

function module.get_apache_home_dir()
    return linux.get_user_home_dir(module["apache_user"]);
end

function module.get_apache_master_config_path_from_daemon()
    if module["cached_apache_conf_path"] then
        return module["cached_apache_conf_path"];
    end

    local retLines, retCode = linux.exec_command_with_proc_ret_code("apache2 -V", true, nil, true);

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

function module.init_dirs()
    if not module.check_apache_user_existence() then
        local ret, retForUserCreation = module.create_apache_user();
    
        if ret ~= true then
            print("[apache init] Failed to initialize apache user! Ret: "..tostring(retForUserCreation));

            return false;
        end
    end

    if not module.update_existing_apache_user() then
        print("[apache init] Failed to update existing "..tostring(module.apache_user).." user!");

        return false;
    end

    local apacheHomeDir = module.get_apache_home_dir();
    module["base_dir"] = apacheHomeDir;

    local pathForConfigs = module.formatPathInsideBasedir("websiteconfigs/");

    if not linux.isdir(pathForConfigs) then
        if not linux.mkdir(pathForConfigs) then
            print("[apache init] Failed to create website config folder at path "..tostring(pathForConfigs));

            return false;
        end
    end

    if not linux.chown(pathForConfigs, module.apache_user, true) then
        print("[apache init] couldn't chown folder at path "..tostring(pathForConfigs).." for user "..tostring(module.apache_user));

        return false;
    end

    module["website_configs_dir"] = pathForConfigs;

    local pathForWWWDatas = module.formatPathInsideBasedir("wwwdatas/");

    if not linux.isdir(pathForWWWDatas) then
        if not linux.mkdir(pathForWWWDatas) then
            print("[apache init] Failed to create website wwwdata folder at path "..tostring(pathForWWWDatas));

            return false;
        end
    end

    if not linux.chown(pathForWWWDatas, module.apache_user, true) then
        print("[apache init] couldn't chown folder at path "..tostring(pathForWWWDatas).." for user "..tostring(module.apache_user));

        return false;
    end

    module["www_datas_dir"] = pathForWWWDatas;

    return module.initialize_server();
end

function module.initialize_server()
    local apacheConfFile = module.get_apache_master_config_path_from_daemon();

    if not apacheConfFile then
        print("[apache init] couldn't retrieve apache config file path!");

        return false;
    end

    local apacheFileContents = general.readAllFileContents(apacheConfFile);

    if not apacheFileContents then
        print("[apache init] apache master config at "..tostring(apacheConfFile).." doesn't exist!");

        --TODO: maybe regenerate it?

        return false;
    end

    local apacheConfigInstance = apacheConfigHandler:new(apacheFileContents);

    if not apacheConfigInstance then
        print("[apache init] couldn't parse apache master config at "..tostring(apacheConfFile));

        --TODO: maybe regenerate it?

        return false;
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

            if data.args[1].data == websiteConfigsFinalPathForApache then
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

    if configNeedsRefreshing then
        local configFileHandle = io.open(apacheConfFile, "w");
        
        if not configFileHandle then
            print("[apache init] Couldn't overwrite apache config file at path "..tostring(apacheConfFile));

            return false;
        end

        configFileHandle:write(apacheConfigInstance:toString());
        configFileHandle:flush();
        configFileHandle:close();
    end

    local apacheConfigDir = general.extractDirFromPath(apacheConfFile);
    local envVarsPath = general.concatPaths(apacheConfigDir, "/envvars");

    local envVarsContents = general.readAllFileContents(envVarsPath);

    if not envVarsContents then
        print("[apache init] Couldn't read envvars content at path "..tostring(envVarsPath));

        return false;
    end

    local apacheEnvVarsInstance = apacheEnvvarsHandler:new(envVarsContents);
    local envvarsArgs = apacheEnvVarsInstance:getArgs();

    if envvarsArgs["APACHE_RUN_USER"] ~= module["apache_user"] or envvarsArgs["APACHE_RUN_GROUP"] ~= module["apache_user"] then
        envvarsArgs["APACHE_RUN_USER"] = module["apache_user"];
        envvarsArgs["APACHE_RUN_GROUP"] = module["apache_user"];

        local envvarsFileHandle = io.open(envVarsPath, "w");

        if not envvarsFileHandle then
            print("[apache init] Couldn't open envvars at path "..tostring(envVarsPath).." for writing!");

            return false;
        end

        envvarsFileHandle:write(apacheEnvVarsInstance:toString());
        envvarsFileHandle:flush();
        envvarsFileHandle:close();
    end

    -- print("[apache] available websites: "..tostring(inspect(module.get_current_available_websites())));
    -- print("[apache] lszlo.ltd website creation ret: "..tostring(module.create_new_website("lszlo.ltd")));
    -- print("[apache] => available websites: "..tostring(inspect(module.get_current_available_websites())));
    -- print("[apache] lszlo.ltd deletion ret: "..tostring(module.delete_website("lszlo.ltd")));
    -- print("[apache] => available websites: "..tostring(inspect(module.get_current_available_websites())));

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

module.WEBSITE_ALREADY_EXISTS = -1;
module.SAMPLE_WEBSITE_CONFIG_PARSE_ERROR = -2;

function module.create_new_website(websiteUrl)
    local websites = module.get_current_available_websites();

    for t, v in pairs(websites) do
        if v.websiteUrl == websiteUrl then
            return module.WEBSITE_ALREADY_EXISTS;
        end
    end

    local fileConfigInstance = apacheConfigHandler:new(sampleConfigForWebsite);

    if not fileConfigInstance then
        return module.SAMPLE_WEBSITE_CONFIG_PARSE_ERROR;
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

    if not linux.isdir(wwwDataDir) then
        if not linux.mkdir(wwwDataDir) then
            print("[apache website creation] Failed to create website ("..tostring(websiteUrl)..") wwwdata folder at path "..tostring(wwwDataDir));

            return false;
        end
    end

    if not linux.chown(wwwDataDir, module.apache_user, true) then
        print("[apache website creation] couldn't chown folder at path "..tostring(wwwDataDir).." for user "..tostring(module.apache_user));

        return false;
    end

    local configFileHandle = io.open(websiteConfigFinalPathForApache, "w");

    if not configFileHandle then
        print("[apache website creation] couldn't create new website config at path "..tostring(websiteConfigFinalPathForApache));

        return false;
    end

    configFileHandle:write(fileConfigInstance:toString());
    configFileHandle:flush();
    configFileHandle:close();

    local indexPath = general.concatPaths(wwwDataDir, "/index.html");
    local indexFileHandle = io.open(indexPath, "w");

    if not indexFileHandle then
        print("[apache website creation] couldn't create new website index.html at path "..tostring(indexPath));

        return false;
    end

    indexFileHandle:write("Hey, i'm "..tostring(websiteUrl).."!");
    indexFileHandle:flush();
    indexFileHandle:close();

    if not linux.chown(indexPath, module.apache_user, true) then
        print("[apache website creation] couldn't chown index.html at path "..tostring(indexPath).." for user "..tostring(module.apache_user));

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
        print("[apache website deletion] failed to delete folder at path "..tostring(foundWebsiteData.rootPath).." for website "..tostring(websiteUrl));

        return false;
    end

    if not linux.deleteFile(foundWebsiteData.configPath) then
        print("[apache website deletion] failed to delete configuration file at path "..tostring(foundWebsiteData.configPath).." for website "..tostring(websiteUrl));

        return false;
    end

    return true;
end

function module.get_current_available_websites(dirPath)
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

return module;
