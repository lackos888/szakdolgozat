local os = require("os");
local packageManager = require("apt_packages");
local linux = require("linux");
local general = require("general");
local nginxConfigHandler = require("nginxHandler/nginx_config_handler");
local inspect = require("inspect");

local module = {
    ["nginx_user"] = "nginx-www",
    ["nginx_user_comment"] = "User for running nginx daemon & websites & PHP-FPM. For higher security, use different user for PHP-FPM per website",
    ["nginx_user_shell"] = "/bin/false",
    ["base_dir"] = nil
};

function module.formatPathInsideBasedir(path)
    return general.concatPaths(module["base_dir"], "/", path);
end

function module.init_dirs()
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

    local pathForConfigs = module.formatPathInsideBasedir("/websiteconfigs/");

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

    local retLines, retCode = linux.exec_command_with_proc_ret_code("nginx -V 2>&1", true);

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

    local parsedNginxConfDataRaw, parsedNginxConfDataLines = nginxConfigHandler.parse_nginx_config(nginxFileContents);

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
        table.insert(parsedNginxConfDataRaw, 1, {["paramName"] = {
            data = "user", quoteStatus = false
        }, ["args"] = {
            {data = module.nginx_user, quoteSatus = false}
        }});

        configNeedsRefreshing = true;

        --TODO: if we use parsedNginxConfDataLines in the future, then adjust indexes by 1
    end

    if configNeedsRefreshing then
        local configFileHandle = io.open(nginxConfFile, "w");
        
        if not configFileHandle then
            print("[nginx init] Couldn't overwrite nginx config file at path "..tostring(nginxConfFile));

            return false;
        end

        configFileHandle:write(nginxConfigHandler.write_nginx_config(parsedNginxConfDataRaw));
        configFileHandle:flush();
        configFileHandle:close();
    end

    --print("new config: \n"..tostring(nginxConfigHandler.write_nginx_config(parsedNginxConfDataRaw)));

    return true;
end

return module;
