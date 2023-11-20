local module = {};

function module.getOSType()
    return package.config:sub(1,1) == "\\" and "win" or "unix";
end

function module.clearScreen()
    if module.getOSType() == "win" then
        return os.execute("cls");
    end

    return os.execute("clear");
end

--from http://lua-users.org/wiki/SleepFunction
local clock = os.clock
function module.sleep(n)  -- seconds
  local t0 = clock()
  while clock() - t0 <= n do end
end

module.lineEnding = module.getOSType() == "unix" and "\n" or "\r\n";

function module.strSplit(str, sep)
    local result = {}
    local regex = ("([^%s]+)"):format(sep)
    for each in str:gmatch(regex) do
       table.insert(result, each)
    end
    return result
 end

 --https://gist.github.com/sapphyrus/fd9aeb871e3ce966cc4b0b969f62f539
function module.deep_compare(tbl1, tbl2)
	if tbl1 == tbl2 then
		return true
	elseif type(tbl1) == "table" and type(tbl2) == "table" then
		for key1, value1 in pairs(tbl1) do
			local value2 = tbl2[key1]

			if value2 == nil then
				-- avoid the type call for missing keys in tbl2 by directly comparing with nil
				return false
			elseif value1 ~= value2 then
				if type(value1) == "table" and type(value2) == "table" then
					if not module.deep_compare(value1, value2) then
						return false
					end
				else
					return false
				end
			end
		end

		-- check for missing keys in tbl1
		for key2, _ in pairs(tbl2) do
			if tbl1[key2] == nil then
				return false
			end
		end

		return true
	end

	return false
end

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