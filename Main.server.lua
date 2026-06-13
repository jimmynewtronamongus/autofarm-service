-- Main.server.lua
-- Standalone server bootstrap for the dev script hub.
-- Put this Script in ServerScriptService.
-- Put ScriptHub.client.lua in StarterPlayerScripts.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local OWNER_USER_IDS = {
	-- Add your Roblox user id(s) here.
	-- [123456789] = true,
}

local REMOTE_FOLDER_NAME = "DevScriptHubRemotes"
local ACTION_REMOTE_NAME = "Action"
local STATUS_REMOTE_NAME = "Status"

local DEFAULT_CONFIG = {
	tickSeconds = 1.25,
	maxActionsPerTick = 4,
	defaultSeed = "Carrot",
	defaultBuyAmount = 1,
	defaultHarvestRadius = 250,
}

local AutoFarmService = {}
AutoFarmService.__index = AutoFarmService

local function noop()
	return false
end

local function mergeConfig(config)
	local merged = {}
	for key, value in pairs(DEFAULT_CONFIG) do
		merged[key] = value
	end
	for key, value in pairs(config or {}) do
		merged[key] = value
	end
	return merged
end

function AutoFarmService.new(adapter, config)
	local self = setmetatable({}, AutoFarmService)

	self.adapter = adapter or {}
	self.config = mergeConfig(config)
	self.sessions = {}
	self.connection = nil

	self.adapter.canUse = self.adapter.canUse or function()
		return RunService:IsStudio()
	end
	self.adapter.buySeed = self.adapter.buySeed or noop
	self.adapter.plantSeed = self.adapter.plantSeed or noop
	self.adapter.harvestReady = self.adapter.harvestReady or function()
		return 0
	end
	self.adapter.sellInventory = self.adapter.sellInventory or noop
	self.adapter.getStats = self.adapter.getStats or function()
		return {}
	end

	return self
end

function AutoFarmService:GetSession(player)
	local session = self.sessions[player]
	if session then
		return session
	end

	session = {
		enabled = false,
		autoBuy = false,
		autoPlant = false,
		autoHarvest = false,
		autoSell = false,
		seedName = self.config.defaultSeed,
		buyAmount = self.config.defaultBuyAmount,
		harvestRadius = self.config.defaultHarvestRadius,
		totalBought = 0,
		totalPlanted = 0,
		totalHarvested = 0,
		totalSold = 0,
		lastResult = "idle",
		_elapsed = 0,
	}

	self.sessions[player] = session
	return session
end

function AutoFarmService:RemoveSession(player)
	self.sessions[player] = nil
end

function AutoFarmService:Status(player)
	local session = self:GetSession(player)
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
		stats = self.adapter.getStats(player),
	}
end

function AutoFarmService:SetEnabled(player, enabled)
	if not self.adapter.canUse(player) then
		return false, "not authorized"
	end
	self:GetSession(player).enabled = enabled == true
	return true, self:Status(player)
end

function AutoFarmService:SetMode(player, modeName, enabled)
	if not self.adapter.canUse(player) then
		return false, "not authorized"
	end

	local session = self:GetSession(player)
	if session[modeName] == nil then
		return false, "unknown mode"
	end

	session[modeName] = enabled == true
	session.lastResult = modeName .. (session[modeName] and " on" or " off")
	return true, self:Status(player)
end

function AutoFarmService:SetSeed(player, seedName)
	if not self.adapter.canUse(player) then
		return false, "not authorized"
	end
	if typeof(seedName) ~= "string" or seedName == "" then
		return false, "invalid seed"
	end

	local session = self:GetSession(player)
	session.seedName = seedName
	session.lastResult = "seed set"
	return true, self:Status(player)
end

function AutoFarmService:SetBuyAmount(player, amount)
	if not self.adapter.canUse(player) then
		return false, "not authorized"
	end

	local value = tonumber(amount)
	if not value then
		return false, "invalid amount"
	end

	local session = self:GetSession(player)
	session.buyAmount = math.floor(math.clamp(value, 1, 100))
	session.lastResult = "buy amount set"
	return true, self:Status(player)
end

function AutoFarmService:SetHarvestRadius(player, radius)
	if not self.adapter.canUse(player) then
		return false, "not authorized"
	end

	local value = tonumber(radius)
	if not value then
		return false, "invalid radius"
	end

	local session = self:GetSession(player)
	session.harvestRadius = math.floor(math.clamp(value, 5, 1000))
	session.lastResult = "harvest radius set"
	return true, self:Status(player)
end

function AutoFarmService:StopAll(player)
	if not self.adapter.canUse(player) then
		return false, "not authorized"
	end

	local session = self:GetSession(player)
	session.enabled = false
	session.autoBuy = false
	session.autoPlant = false
	session.autoHarvest = false
	session.autoSell = false
	session.lastResult = "stopped"
	return true, self:Status(player)
end

function AutoFarmService:StepOnce(player)
	if not self.adapter.canUse(player) then
		return false, "not authorized"
	end

	local session = self:GetSession(player)
	local actions = 0

	if session.autoBuy and actions < self.config.maxActionsPerTick then
		if self.adapter.buySeed(player, session.seedName, session.buyAmount) then
			session.totalBought += session.buyAmount
			session.lastResult = "bought " .. session.seedName
		end
		actions += 1
	end

	if session.autoPlant and actions < self.config.maxActionsPerTick then
		if self.adapter.plantSeed(player, session.seedName) then
			session.totalPlanted += 1
			session.lastResult = "planted " .. session.seedName
		end
		actions += 1
	end

	if session.autoHarvest and actions < self.config.maxActionsPerTick then
		local harvested = self.adapter.harvestReady(player, session.harvestRadius)
		if typeof(harvested) == "number" and harvested > 0 then
			session.totalHarvested += harvested
			session.lastResult = "harvested " .. tostring(harvested)
		end
		actions += 1
	end

	if session.autoSell and actions < self.config.maxActionsPerTick then
		if self.adapter.sellInventory(player) then
			session.totalSold += 1
			session.lastResult = "sold inventory"
		end
		actions += 1
	end

	return true, self:Status(player)
end

function AutoFarmService:Start()
	if self.connection then
		return
	end

	self.connection = RunService.Heartbeat:Connect(function(deltaTime)
		for player, session in pairs(self.sessions) do
			if not player.Parent then
				self.sessions[player] = nil
				continue
			end

			if session.enabled and self.adapter.canUse(player) then
				session._elapsed += deltaTime
				if session._elapsed >= self.config.tickSeconds then
					session._elapsed = 0
					self:StepOnce(player)
				end
			end
		end
	end)
end

local adapter = {}

function adapter.canUse(player)
	return RunService:IsStudio() or OWNER_USER_IDS[player.UserId] == true
end

function adapter.buySeed(player, seedName, amount)
	-- Replace with your real server-authoritative shop call.
	-- Example:
	-- return require(game.ServerScriptService.Services.ShopService):BuySeed(player, seedName, amount)
	warn(("[AutoFarm] buySeed not wired: %s x%d for %s"):format(seedName, amount, player.Name))
	return false
end

function adapter.plantSeed(player, seedName)
	-- Replace with your real server-authoritative planting call.
	-- Example:
	-- return require(game.ServerScriptService.Services.GardenService):PlantNextAvailable(player, seedName)
	warn(("[AutoFarm] plantSeed not wired: %s for %s"):format(seedName, player.Name))
	return false
end

function adapter.harvestReady(player, radius)
	-- Replace with your real server-authoritative harvest call.
	-- Example:
	-- return require(game.ServerScriptService.Services.GardenService):HarvestReady(player, radius)
	warn(("[AutoFarm] harvestReady not wired: radius %d for %s"):format(radius, player.Name))
	return 0
end

function adapter.sellInventory(player)
	-- Replace with your real server-authoritative sell call.
	-- Example:
	-- return require(game.ServerScriptService.Services.SellService):SellInventory(player)
	warn(("[AutoFarm] sellInventory not wired for %s"):format(player.Name))
	return false
end

function adapter.getStats(player)
	return {
		name = player.Name,
		userId = player.UserId,
		studio = RunService:IsStudio(),
	}
end

local farm = AutoFarmService.new(adapter, {
	tickSeconds = 1.25,
	maxActionsPerTick = 4,
	defaultSeed = "Carrot",
	defaultBuyAmount = 1,
	defaultHarvestRadius = 250,
})

farm:Start()

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

local actions = {
	setEnabled = function(player, payload)
		return farm:SetEnabled(player, payload.enabled)
	end,
	setMode = function(player, payload)
		return farm:SetMode(player, payload.mode, payload.enabled)
	end,
	setSeed = function(player, payload)
		return farm:SetSeed(player, payload.seedName)
	end,
	setBuyAmount = function(player, payload)
		return farm:SetBuyAmount(player, payload.amount)
	end,
	setHarvestRadius = function(player, payload)
		return farm:SetHarvestRadius(player, payload.radius)
	end,
	stepOnce = function(player)
		return farm:StepOnce(player)
	end,
	stopAll = function(player)
		return farm:StopAll(player)
	end,
}

statusRemote.OnServerInvoke = function(player)
	if not adapter.canUse(player) then
		return false, "not authorized"
	end

	return true, farm:Status(player)
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

Players.PlayerRemoving:Connect(function(player)
	farm:RemoveSession(player)
end)

_G.AutoFarm = farm

print("[ScriptHub] Loaded. Configure adapters in Main.server.lua, then use the client hub from StarterPlayerScripts.")
