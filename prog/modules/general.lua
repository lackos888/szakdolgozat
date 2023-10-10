local module = {};

function module.concatPaths(...)
    local outputPath = "";
    local args = {...};
    
    for t, v in pairs(args) do
        v = string.gsub(v, "%\\", "/");

        if t == #args and v:sub(1, 1) == "/" then
            outputPath = outputPath..(v:sub(2));
        else
            if v:sub(#v, #v) == "/" then
                outputPath = outputPath..v;
            else
                outputPath = outputPath..v.."/";
            end
        end
    end

    return outputPath;
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