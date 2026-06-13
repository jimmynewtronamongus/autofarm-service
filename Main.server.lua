-- Main.server.lua
-- Server bootstrap for AutoFarmService.module.lua.
-- Put this Script and AutoFarmService.module.lua in ServerScriptService.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local AutoFarmService = require(script.Parent:WaitForChild("AutoFarmService"))

local OWNER_USER_IDS = {
	-- Add your Roblox user id(s) here.
	-- [123456789] = true,
}

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

Players.PlayerRemoving:Connect(function(player)
	farm:RemoveSession(player)
end)

_G.AutoFarm = farm

print("[AutoFarm] Loaded. Configure adapters in Main.server.lua, then use _G.AutoFarm from trusted server code.")
