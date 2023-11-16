local datas = {CERTBOT_DOMAIN = "", CERTBOT_VALIDATION = "",
CERTBOT_TOKEN = "", CERTBOT_REMAINING_CHALLENGES = "",
CERTBOT_ALL_DOMAINS = "",
CERTBOT_AUTH_OUTPUT = ""};

for t, v in pairs(datas) do
	datas[t] = os.getenv(t) or "";
	print(tostring(t).." => "..tostring(datas[t]));
end

local formattedDomainTXTName = "_acme-challenge."..tostring(datas.CERTBOT_DOMAIN);

local args = {...};

if #args < 1 then
	return os.exit(1);
end

--from http://lua-users.org/wiki/SleepFunction
local clock = os.clock
function sleep(n)  -- seconds
  local t0 = clock()
  while clock() - t0 <= n do end
end

local fileName = args[1];
local fileHandle = io.open(fileName, "w");
fileHandle:write(formattedDomainTXTName);
fileHandle:write("\n");
fileHandle:write(datas.CERTBOT_DOMAIN);
fileHandle:write("\n");
fileHandle:write(datas.CERTBOT_VALIDATION);
fileHandle:write("\n");
fileHandle:flush();
fileHandle:close();

print("Data written to "..tostring(fileName).." ... waiting!");

while true do
	local fileHandle = io.open(fileName, "r");

	if fileHandle then
		local readStr = fileHandle:read("*a");
		fileHandle:close();

		if readStr:find("ready", 0, true) == 1 then
			break;
		end
	end

	sleep(1);
end

print("Ready!");