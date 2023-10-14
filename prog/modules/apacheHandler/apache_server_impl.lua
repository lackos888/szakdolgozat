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
    local apacheConfFile = "/etc/apache2/apache2.conf";

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

    print("<==NEW CONFIG==>");
    print(tostring(apacheConfigInstance:toString()));

    print("<==PARSEDDATARAW==>");
    print(tostring(inspect(parsedapacheConfDataRaw)));

    print("<==PARSEDDATALINES==>");
    print(tostring(inspect(parsedapacheConfDataLines)));

    local documentRoot = parsedapacheConfDataLines["DocumentRoot"];

    if documentRoot then
        for t, v in pairs(documentRoot) do
            local data = parsedapacheConfDataRaw[v];

            print("DocumentRoot "..tostring(t).." => "..tostring(data.args[1].data));
        end
    end

    return true;
end

return module;
