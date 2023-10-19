local module = {};

function module.getOSType()
    return package.config:sub(1,1) == "\\" and "win" or "unix";
end

module.lineEnding = module.getOSType() == "unix" and "\n" or "\r\n";

function module.concatPaths(...)
    local outputPath = "";
    local args = {...};
    
    for t, v in pairs(args) do
        v = string.gsub(v, '\\', "/");

        if t ~= #args and outputPath:sub(-1) == "/" and v:sub(1, 1) == "/" then
            v = v:sub(2);

            if not v or #v == 0 then
                goto continue
            end
        end

        if t == #args and v:sub(1, 1) == "/" then
            outputPath = outputPath..(v:sub(2));
        else
            if v:sub(-1) == "/" then
                outputPath = outputPath..v;
            else
                outputPath = outputPath..v.."/";
            end
        end

        ::continue::
    end

    return outputPath;
end

function module.extractDirFromPath(path)
    return path:gsub('\\', "/"):match("(.*".."/"..")");
end

function module.readAllFileContents(filePath)
    local fileHandle = io.open(filePath, "r");

    if not fileHandle then
        return false;
    end

    local ret = fileHandle:read("a*");
    fileHandle:close();

    return ret;
end

return module