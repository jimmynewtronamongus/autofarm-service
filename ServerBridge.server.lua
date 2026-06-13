-- ServerBridge.server.lua
-- Put this Script in ServerScriptService in your own game.
-- The executor/local UI in Main.server.lua controls this bridge through
-- ReplicatedStorage.DevScriptHubRemotes.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local OWNER_USER_IDS = {
	-- Add your Roblox user id(s) here.
	-- [123456789] = true,
}

local REMOTE_FOLDER_NAME = "DevScriptHubRemotes"
local ACTION_REMOTE_NAME = "Action"
local STATUS_REMOTE_NAME = "Status"
local ADAPTER_FOLDER_NAME = "DevScriptHubActions"

local DEFAULT_CONFIG = {
	tickSeconds = 1.25,
	maxActionsPerTick = 4,
	defaultSeed = "Carrot",
	defaultBuyAmount = 1,
	defaultHarvestRadius = 250,
}

local sessions = {}

local function canUse(player)
	return RunService:IsStudio() or OWNER_USER_IDS[player.UserId] == true
end

local function getSession(player)
	local session = sessions[player]
	if session then
		return session
	end

	session = {
		enabled = false,
		autoBuy = false,
		autoPlant = false,
		autoHarvest = false,
		autoSell = false,
		seedName = DEFAULT_CONFIG.defaultSeed,
		buyAmount = DEFAULT_CONFIG.defaultBuyAmount,
		harvestRadius = DEFAULT_CONFIG.defaultHarvestRadius,
		totalBought = 0,
		totalPlanted = 0,
		totalHarvested = 0,
		totalSold = 0,
		lastResult = "ready",
		_elapsed = 0,
	}

	sessions[player] = session
	return session
end

local function status(player)
	local session = getSession(player)
	return {
		enabled = session.enabled,
		autoBuy = session.autoBuy,
		autoPlant = session.autoPlant,
		autoHarvest = session.autoHarvest,
		autoSell = session.autoSell,
		seedName = session.seedName,
		buyAmount = session.buyAmount,
		harvestRadius = session.harvestRadius,
		totalBought = session.totalBought,
		totalPlanted = session.totalPlanted,
		totalHarvested = session.totalHarvested,
		totalSold = session.totalSold,
		lastResult = session.lastResult,
		stats = {
			name = player.Name,
			userId = player.UserId,
		},
	}
end

local adapterFolder = ServerScriptService:FindFirstChild(ADAPTER_FOLDER_NAME)
if not adapterFolder then
	adapterFolder = Instance.new("Folder")
	adapterFolder.Name = ADAPTER_FOLDER_NAME
	adapterFolder.Parent = ServerScriptService
end

local function ensureBindable(name)
	local bindable = adapterFolder:FindFirstChild(name)
	if not bindable then
		bindable = Instance.new("BindableFunction")
		bindable.Name = name
		bindable.Parent = adapterFolder
		bindable.OnInvoke = function()
			return false, name .. " is not wired"
		end
	end
	return bindable
end

local adapters = {
	BuySeed = ensureBindable("BuySeed"),
	PlaceSeed = ensureBindable("PlaceSeed"),
	CollectFruit = ensureBindable("CollectFruit"),
	SellInventory = ensureBindable("SellInventory"),
}

local remoteFolder = ReplicatedStorage:FindFirstChild(REMOTE_FOLDER_NAME)
if not remoteFolder then
	remoteFolder = Instance.new("Folder")
	remoteFolder.Name = REMOTE_FOLDER_NAME
	remoteFolder.Parent = ReplicatedStorage
end

local actionRemote = remoteFolder:FindFirstChild(ACTION_REMOTE_NAME)
if not actionRemote then
	actionRemote = Instance.new("RemoteEvent")
	actionRemote.Name = ACTION_REMOTE_NAME
	actionRemote.Parent = remoteFolder
end

local statusRemote = remoteFolder:FindFirstChild(STATUS_REMOTE_NAME)
if not statusRemote then
	statusRemote = Instance.new("RemoteFunction")
	statusRemote.Name = STATUS_REMOTE_NAME
	statusRemote.Parent = remoteFolder
end

local function respond(player, ok, result)
	actionRemote:FireClient(player, ok == true, result)
end

local function invokeAdapter(name, ...)
	local ok, result, message = pcall(function(...)
		return adapters[name]:Invoke(...)
	end, ...)

	if not ok then
		return false, result
	end

	return result, message
end

local function stepOnce(player)
	if not canUse(player) then
		return false, "not authorized"
	end

	local session = getSession(player)
	local actions = 0

	if session.autoBuy and actions < DEFAULT_CONFIG.maxActionsPerTick then
		local ok, message = invokeAdapter("BuySeed", player, session.seedName, session.buyAmount)
		if ok then
			session.totalBought += session.buyAmount
			session.lastResult = "bought " .. session.seedName
		elseif message then
			session.lastResult = tostring(message)
		end
		actions += 1
	end

	if session.autoPlant and actions < DEFAULT_CONFIG.maxActionsPerTick then
		local ok, message = invokeAdapter("PlaceSeed", player, session.seedName)
		if ok then
			session.totalPlanted += 1
			session.lastResult = "placed " .. session.seedName
		elseif message then
			session.lastResult = tostring(message)
		end
		actions += 1
	end

	if session.autoHarvest and actions < DEFAULT_CONFIG.maxActionsPerTick then
		local collected, message = invokeAdapter("CollectFruit", player, session.harvestRadius)
		if typeof(collected) == "number" and collected > 0 then
			session.totalHarvested += collected
			session.lastResult = "collected " .. tostring(collected)
		elseif collected == true then
			session.totalHarvested += 1
			session.lastResult = "collected fruit"
		elseif message then
			session.lastResult = tostring(message)
		end
		actions += 1
	end

	if session.autoSell and actions < DEFAULT_CONFIG.maxActionsPerTick then
		local ok, message = invokeAdapter("SellInventory", player)
		if ok then
			session.totalSold += 1
			session.lastResult = "sold inventory"
		elseif message then
			session.lastResult = tostring(message)
		end
		actions += 1
	end

	return true, status(player)
end

local actions = {
	setEnabled = function(player, payload)
		if not canUse(player) then
			return false, "not authorized"
		end
		local session = getSession(player)
		session.enabled = payload.enabled == true
		session.lastResult = session.enabled and "autofarm on" or "autofarm off"
		return true, status(player)
	end,
	setMode = function(player, payload)
		if not canUse(player) then
			return false, "not authorized"
		end
		local session = getSession(player)
		if session[payload.mode] == nil then
			return false, "unknown mode"
		end
		session[payload.mode] = payload.enabled == true
		session.lastResult = payload.mode .. (session[payload.mode] and " on" or " off")
		return true, status(player)
	end,
	setSeed = function(player, payload)
		if not canUse(player) then
			return false, "not authorized"
		end
		if typeof(payload.seedName) ~= "string" or payload.seedName == "" then
			return false, "invalid seed"
		end
		local session = getSession(player)
		session.seedName = payload.seedName
		session.lastResult = "seed set"
		return true, status(player)
	end,
	setBuyAmount = function(player, payload)
		if not canUse(player) then
			return false, "not authorized"
		end
		local amount = tonumber(payload.amount)
		if not amount then
			return false, "invalid amount"
		end
		local session = getSession(player)
		session.buyAmount = math.floor(math.clamp(amount, 1, 100))
		session.lastResult = "buy amount set"
		return true, status(player)
	end,
	setHarvestRadius = function(player, payload)
		if not canUse(player) then
			return false, "not authorized"
		end
		local radius = tonumber(payload.radius)
		if not radius then
			return false, "invalid radius"
		end
		local session = getSession(player)
		session.harvestRadius = math.floor(math.clamp(radius, 5, 1000))
		session.lastResult = "collect radius set"
		return true, status(player)
	end,
	stepOnce = stepOnce,
	stopAll = function(player)
		if not canUse(player) then
			return false, "not authorized"
		end
		local session = getSession(player)
		session.enabled = false
		session.autoBuy = false
		session.autoPlant = false
		session.autoHarvest = false
		session.autoSell = false
		session.lastResult = "stopped"
		return true, status(player)
	end,
}

statusRemote.OnServerInvoke = function(player)
	if not canUse(player) then
		return false, "not authorized"
	end
	return true, status(player)
end

actionRemote.OnServerEvent:Connect(function(player, actionName, payload)
	if typeof(actionName) ~= "string" then
		respond(player, false, "invalid action")
		return
	end

	local action = actions[actionName]
	if not action then
		respond(player, false, "unknown action")
		return
	end

	local ok, result = action(player, typeof(payload) == "table" and payload or {})
	respond(player, ok, result)
end)

RunService.Heartbeat:Connect(function(deltaTime)
	for player, session in pairs(sessions) do
		if not player.Parent then
			sessions[player] = nil
			continue
		end
		if session.enabled and canUse(player) then
			session._elapsed += deltaTime
			if session._elapsed >= DEFAULT_CONFIG.tickSeconds then
				session._elapsed = 0
				stepOnce(player)
			end
		end
	end
end)

Players.PlayerRemoving:Connect(function(leavingPlayer)
	sessions[leavingPlayer] = nil
end)

print("[ScriptHubBridge] Loaded. Wire ServerScriptService.DevScriptHubActions bindables to your game systems.")
