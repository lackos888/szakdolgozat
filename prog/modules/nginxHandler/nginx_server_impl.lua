local os = require("os");
local packageManager = require("apt_packages");
local linux = require("linux");
local module = {};

function module.formatPathInsideBasedir(path)
    return module["base_dir"].."/"..path;
end

function module.init_dirs()
    return true;
end

function module.initialize_server()
end

return module;
