-- AutoFarmService.module.lua
-- Server-authoritative autofarm loop for your own Roblox experience.
-- Require this module from ServerScriptService and wire the adapter callbacks
-- to your real shop, garden, inventory, and sell systems.

local RunService = game:GetService("RunService")

local AutoFarmService = {}
AutoFarmService.__index = AutoFarmService

local DEFAULT_CONFIG = {
	tickSeconds = 1.25,
	maxActionsPerTick = 4,
	defaultSeed = "Carrot",
	defaultBuyAmount = 1,
	defaultHarvestRadius = 250,
}

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

function AutoFarmService:Destroy()
	if self.connection then
		self.connection:Disconnect()
		self.connection = nil
	end
	table.clear(self.sessions)
end

return AutoFarmService
