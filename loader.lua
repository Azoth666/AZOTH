local CONFIG = {
	Name = "AZOTH",
	BaseUrl = "https://raw.githubusercontent.com/Azoth666/AZOTH/main/game/",
	Extension = ".lua",
}

local GAMES = {
	[139717576471404] = "139717576471404",
}

local function log(message)
	warn(("[%s] %s"):format(CONFIG.Name, message))
end

local function resolveModuleName(placeId)
	local moduleName = GAMES[placeId]
	if moduleName == nil then
		return nil, ("PlaceId %s is not supported"):format(tostring(placeId))
	end
	if type(moduleName) ~= "string" or not moduleName:match("^[%w_%-]+$") then
		return nil, ("invalid module name registered for PlaceId %s"):format(tostring(placeId))
	end
	return moduleName
end

local function buildUrl(moduleName)
	return CONFIG.BaseUrl .. moduleName .. CONFIG.Extension
end

local function fetch(url)
	local ok, body = pcall(function()
		return game:HttpGet(url)
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
	local ok, module = xpcall(chunk, debug.traceback, context)
	if not ok then
		return false, "module chunk failed:\n" .. tostring(module)
	end
	if type(module) ~= "table" or type(module.Init) ~= "function" then
		return false, "module must return a table with an Init function"
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

	if type(loadstring) ~= "function" then
		log("loadstring is not available in this environment")
		return false
	end

	local placeId = game.PlaceId
	local moduleName, routeErr = resolveModuleName(placeId)
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
		PlaceId = placeId,
		ModuleName = moduleName,
	})
	if not ok then
		log(("%s (%s)"):format(execErr, url))
		return false
	end

	return true
end

return main()
