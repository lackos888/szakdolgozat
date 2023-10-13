local os = require("os");
local packageManager = require("apt_packages");
local linux = require("linux");
local general = require("general");
local apacheConfigHandlerModule = require("apacheHandler/apache_config_handler");
local inspect = require("inspect");

local module = {
    ["base_dir"] = nil
};

function module.formatPathInsideBasedir(path)
    return general.concatPaths(module["base_dir"], "/", path);
end

function module.init_dirs()
    return module.initialize_server();
end

function module.initialize_server()
    local apacheConfFile = "/etc/apache2/sites-enabled/000-default.conf";

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

    local parsedapacheConfDataRaw = apacheConfigInstance:getParsedLines();
    local parsedapacheConfDataLines = apacheConfigInstance:getParamsToIdx();

    return true;
end

return module;
