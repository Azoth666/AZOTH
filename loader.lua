local CONFIG = {
	Name = "AZOTH",
	BaseUrl = "https://raw.githubusercontent.com/Azoth666/AZOTH/main/game/",
	Extension = ".lua",
	BlockedExecutors = { "solara", "xeno" },
}

local GAMES = {
	["139717576471444"] = { 10768845402 },
	["120219252362013"] = { 10766972131 },
	["74183246285569"] = { 10770228857 },
}
local function log(message)
	warn(("[%s] %s"):format(CONFIG.Name, message))
end

local function buildUniverseIndex(games)
	local index = {}
	for moduleName, universeIds in pairs(games) do
		for _, universeId in ipairs(universeIds) do
			if index[universeId] ~= nil and index[universeId] ~= moduleName then
				log(("UniverseId %d is registered for both %s and %s"):format(universeId, index[universeId], moduleName))
			end
			index[universeId] = moduleName
		end
	end
	return index
end

local UNIVERSE_INDEX = buildUniverseIndex(GAMES)

local function getBlockedExecutor()
	if type(identifyexecutor) ~= "function" then
		return nil
	end
	local ok, name = pcall(identifyexecutor)
	if not ok or name == nil then
		return nil
	end
	local lowered = tostring(name):lower()
	for _, blocked in ipairs(CONFIG.BlockedExecutors) do
		if lowered:find(blocked, 1, true) then
			return tostring(name)
		end
	end
	return nil
end

local function resolveModuleName(universeId)
	local moduleName = UNIVERSE_INDEX[universeId]
	if moduleName == nil then
		return nil, ("UniverseId %s is not supported"):format(tostring(universeId))
	end
	if type(moduleName) ~= "string" or not moduleName:match("^[%w_%-]+$") then
		return nil, ("invalid module name registered for UniverseId %s"):format(tostring(universeId))
	end
	return moduleName
end

local function buildUrl(moduleName)
	return CONFIG.BaseUrl .. moduleName .. CONFIG.Extension
end

local function fetch(url)
	local ok, body = pcall(function()
		return game:HttpGet(url .. "?t=" .. os.time(), true) -- skip stale raw/executor caches
	end)
	if not ok then
		return nil, "request failed: " .. tostring(body)
	end
	return body
end

local function validate(body)
	if type(body) ~= "string" then
		return false, "response is not a string"
	end
	if body:match("^%s*$") then
		return false, "response is empty"
	end
	if body:match("^404: Not Found") then
		return false, "module file not found (404)"
	end
	return true
end

local function compile(source)
	local chunk, err = loadstring(source)
	if not chunk then
		return nil, "compile error: " .. tostring(err)
	end
	return chunk
end

local function execute(chunk, context)
	local ok, module = xpcall(chunk, debug.traceback)
	if not ok then
		return false, "module chunk failed:\n" .. tostring(module)
	end
	-- plain scripts run fully in the chunk above; Init is optional
	if type(module) ~= "table" or type(module.Init) ~= "function" then
		return true
	end
	local initOk, initErr = xpcall(module.Init, debug.traceback, context)
	if not initOk then
		return false, "Init failed:\n" .. tostring(initErr)
	end
	return true
end

local function main()
	if not game:IsLoaded() then
		game.Loaded:Wait()
	end

	local blocked = getBlockedExecutor()
	if blocked then
		log(("executor %s is not supported"):format(blocked))
		return false
	end

	if type(loadstring) ~= "function" then
		log("loadstring is not available in this environment")
		return false
	end

	local universeId = game.GameId
	local moduleName, routeErr = resolveModuleName(universeId)
	if not moduleName then
		log(routeErr)
		return false
	end

	local url = buildUrl(moduleName)

	local body, fetchErr = fetch(url)
	if not body then
		log(("%s (%s)"):format(fetchErr, url))
		return false
	end

	log(("fetched %d bytes: %s"):format(#body, body:sub(1, 45):gsub("%s+", " "))) -- temporary: remove once loading works

	local valid, validateErr = validate(body)
	if not valid then
		log(("%s (%s)"):format(validateErr, url))
		return false
	end

	local chunk, compileErr = compile(body)
	if not chunk then
		log(("%s (%s)"):format(compileErr, url))
		return false
	end

	local ok, execErr = execute(chunk, {
		Name = CONFIG.Name,
		PlaceId = game.PlaceId,
		UniverseId = universeId,
		ModuleName = moduleName,
	})
	if not ok then
		log(("%s (%s)"):format(execErr, url))
		return false
	end

	return true
end

return main()
