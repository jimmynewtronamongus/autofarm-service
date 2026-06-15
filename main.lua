-- Garden automation GUI for private testing in a Grow-a-Garden-style place.
-- Drop this LocalScript in StarterPlayerScripts, or run it from a local test client.

local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local UserInputService = game:GetService("UserInputService")
local virtualInputManager

pcall(function()
	virtualInputManager = game:GetService("VirtualInputManager")
end)

local localPlayer = Players.LocalPlayer
local playerGui = localPlayer:WaitForChild("PlayerGui")

local CONFIG = {
	collectInterval = 0.22,
	plantInterval = 0.45,
	sellInterval = 12.0,
	sellWhenFullInterval = 1.5,
	buyInterval = 1.0,
	rainbowCollectInterval = 2.5,
	petBuyInterval = 0.75,
	cacheRefreshInterval = 12.0,
	dropCacheRefreshInterval = 2.5,
	inventoryRefreshInterval = 1.5,
	guiInventoryRefreshInterval = 5.0,
	maxFruitCollectPerTick = 90,
	maxFruitScanPerRoot = 2500,
	fruitCacheRefreshInterval = 1.15,
	maxFruitTargetsCached = 320,
	maxFruitPromptFallbackPerTick = 18,
	maxSeedPlantPerTick = 22,
	maxSeedPlacementsPerTool = 8,
	seedCountCacheRefreshInterval = 20.0,
	maxSeedBuyPerTick = 6,
	seedBuyRemoteRepeats = 4,
	shovelInterval = 0.35,
	shovelHoldDuration = 3.1,
	maxShovelPerTick = 1,
	maxDropCollectPerTick = 8,
	maxDropScanPerRoot = 2500,
	maxInventoryItems = 200,
	lowRaritySeedLimit = 10,
	selectedSeed = "",
	plantRadius = 18,
	webhookUrl = "",
}

local seedNames = {}

local seedPriority = {}

local state = {
	fruitCollector = false,
	collectTeleport = true,
	seedPlacer = false,
	autoShovel = false,
	autoSell = false,
	sellWhenFull = true,
	autoBuySeeds = false,
	seedShopEnabled = true,
	autoBuyGear = false,
	gearShopEnabled = true,
	autoCollectRainbowSeeds = false,
	autoBuyPets = false,
	performanceMode = false,
	hidePlants = false,
	lastStatus = "Ready",
}

local selectedSeeds = {}

local selectedShovelSeeds = {}

local gearNames = {}

local selectedGears = {}

local petNames = {}

local buyPetNames = {}

local selectedPets = {}

local saveConfig = function() end
local setStatus = function() end

local CONFIG_FOLDER = "GardenTools"
local CONFIG_FILE = CONFIG_FOLDER .. "/config.json"

local function canUseFileConfig()
	return typeof(readfile) == "function"
		and typeof(writefile) == "function"
		and typeof(isfile) == "function"
end

local function copyMap(source)
	local target = {}
	if type(source) ~= "table" then
		return target
	end

	for key, value in pairs(source) do
		if type(key) == "string" and value == true then
			target[key] = true
		end
	end

	return target
end

local function copyKnownValues(source, destination, keys)
	if type(source) ~= "table" then
		return
	end

	for _, key in ipairs(keys) do
		if source[key] ~= nil then
			destination[key] = source[key]
		end
	end
end

local function loadConfig()
	if not canUseFileConfig() then
		return false
	end

	local existsOk, exists = pcall(isfile, CONFIG_FILE)
	if not existsOk or not exists then
		return false
	end

	local ok, decoded = pcall(function()
		return HttpService:JSONDecode(readfile(CONFIG_FILE))
	end)
	if not ok or type(decoded) ~= "table" then
		return false
	end

	copyKnownValues(decoded.config, CONFIG, {
		"sellInterval",
		"sellWhenFullInterval",
		"buyInterval",
		"shovelInterval",
		"lowRaritySeedLimit",
		"selectedSeed",
		"plantRadius",
		"webhookUrl",
	})
	copyKnownValues(decoded.state, state, {
		"fruitCollector",
		"collectTeleport",
		"seedPlacer",
		"autoShovel",
		"autoSell",
		"sellWhenFull",
		"autoBuySeeds",
		"seedShopEnabled",
		"autoBuyGear",
		"gearShopEnabled",
		"autoCollectRainbowSeeds",
		"autoBuyPets",
		"performanceMode",
		"hidePlants",
	})

	selectedSeeds = copyMap(decoded.selectedSeeds)
	selectedShovelSeeds = copyMap(decoded.selectedShovelSeeds)
	selectedGears = copyMap(decoded.selectedGears)
	selectedPets = copyMap(decoded.selectedPets)

	return true
end

saveConfig = function()
	if not canUseFileConfig() then
		return false
	end

	if typeof(isfolder) == "function" and typeof(makefolder) == "function" and not isfolder(CONFIG_FOLDER) then
		pcall(makefolder, CONFIG_FOLDER)
	elseif typeof(makefolder) == "function" then
		pcall(makefolder, CONFIG_FOLDER)
	end

	local payload = {
		version = 1,
		config = {
			sellInterval = CONFIG.sellInterval,
			sellWhenFullInterval = CONFIG.sellWhenFullInterval,
			buyInterval = CONFIG.buyInterval,
			shovelInterval = CONFIG.shovelInterval,
			lowRaritySeedLimit = CONFIG.lowRaritySeedLimit,
			selectedSeed = CONFIG.selectedSeed,
			plantRadius = CONFIG.plantRadius,
			webhookUrl = CONFIG.webhookUrl,
		},
		state = {
			fruitCollector = state.fruitCollector,
			collectTeleport = state.collectTeleport,
			seedPlacer = state.seedPlacer,
			autoShovel = state.autoShovel,
			autoSell = state.autoSell,
			sellWhenFull = state.sellWhenFull,
			autoBuySeeds = state.autoBuySeeds,
			seedShopEnabled = state.seedShopEnabled,
			autoBuyGear = state.autoBuyGear,
			gearShopEnabled = state.gearShopEnabled,
			autoCollectRainbowSeeds = state.autoCollectRainbowSeeds,
			autoBuyPets = state.autoBuyPets,
			performanceMode = state.performanceMode,
			hidePlants = state.hidePlants,
		},
		selectedSeeds = selectedSeeds,
		selectedShovelSeeds = selectedShovelSeeds,
		selectedGears = selectedGears,
		selectedPets = selectedPets,
	}

	local ok, encoded = pcall(function()
		return HttpService:JSONEncode(payload)
	end)
	if not ok then
		return false
	end

	return pcall(writefile, CONFIG_FILE, encoded)
end

local configLoaded = loadConfig()

local webhookSentAt = {}
local getStockItemsFolder
local getShopStockAmount
local getShopPriceAmount

local function getRequestFunction()
	return (syn and syn.request)
		or (http and http.request)
		or http_request
		or request
end

local function sendWebhook(title, description, key)
	if CONFIG.webhookUrl == "" then
		return false
	end

	local now = os.clock()
	if key and webhookSentAt[key] and now - webhookSentAt[key] < 45 then
		return false
	end

	local requestFunction = getRequestFunction()
	if type(requestFunction) ~= "function" then
		setStatus("Webhook: request function unavailable")
		return false
	end

	local payload = {
		username = "Garden Tools",
		embeds = {
			{
				title = title,
				description = description,
				color = 65280,
				timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ"),
			},
		},
	}

	local ok, response = pcall(function()
		return requestFunction({
			Url = CONFIG.webhookUrl,
			Method = "POST",
			Headers = {
				["Content-Type"] = "application/json",
			},
			Body = HttpService:JSONEncode(payload),
		})
	end)

	local statusCode = 200
	if ok and type(response) == "table" then
		statusCode = tonumber(response.StatusCode or response.Status or response.status_code) or statusCode
	end
	local sent = ok and statusCode >= 200 and statusCode < 300

	if sent and key then
		webhookSentAt[key] = now
	elseif not sent then
		setStatus(("Webhook failed%s"):format(ok and (" (" .. tostring(statusCode) .. ")") or ""))
	end

	return sent
end

local function shouldNotifySelected(map, name)
	return name and name ~= "" and map[name] == true
end

local function listHasName(list, name)
	for _, value in ipairs(list) do
		if value == name then
			return true
		end
	end
	return false
end

local function getStockFolderName(shopName)
	if shopName == "Seed shop" then
		return "SeedShop"
	elseif shopName == "Gear shop" then
		return "GearShop"
	end
	return shopName
end

local function itemIsInStock(shopName, itemName)
	return (getShopStockAmount and getShopStockAmount(getStockFolderName(shopName), itemName) or 0) > 0
end

local function notifyStock(shopName, itemName)
	if itemIsInStock(shopName, itemName)
		and (shouldNotifySelected(selectedSeeds, itemName) or shouldNotifySelected(selectedGears, itemName))
	then
		sendWebhook(
			shopName .. " stock",
			("%s is now in stock (%d available)."):format(itemName, getShopStockAmount(getStockFolderName(shopName), itemName)),
			"stock:" .. shopName .. ":" .. itemName
		)
	end
end

local watchedStockItems = {}

local function watchStockItem(shopName, item)
	if not item then
		return
	end

	local key = shopName .. ":" .. item:GetFullName()
	if watchedStockItems[key] then
		return
	end
	watchedStockItems[key] = true

	local function changed()
		task.defer(function()
			notifyStock(shopName == "SeedShop" and "Seed shop" or shopName == "GearShop" and "Gear shop" or shopName, item.Name)
		end)
	end

	if item:IsA("ValueBase") then
		item.Changed:Connect(changed)
	end

	for _, descendant in ipairs(item:GetDescendants()) do
		if descendant:IsA("ValueBase") then
			descendant.Changed:Connect(changed)
		end
	end

	item.DescendantAdded:Connect(function(descendant)
		if descendant:IsA("ValueBase") then
			descendant.Changed:Connect(changed)
			changed()
		end
	end)
	item.ChildAdded:Connect(changed)
	item.ChildRemoved:Connect(changed)
end

local function notifyPetSpawn(petName)
	if shouldNotifySelected(selectedPets, petName) then
		sendWebhook(
			"Pet spawned",
			petName .. " spawned in WildPetSpawns.",
			"pet:" .. petName
		)
	end
end

local petVariantWords = {
	"Big",
	"Huge",
	"Giant",
	"Rainbow",
	"Super",
	"Gold",
	"Golden",
	"Shiny",
}

local statusValue
local statsLabels = {}
local sessionStartedAt = os.clock()

local stats = {
	fruitTargetsChecked = 0,
	fruitCollected = 0,
	collectSkippedFull = 0,
	collectSkippedRange = 0,
	seedsPlanted = 0,
	seedsShoveled = 0,
	seedAttempts = 0,
	seedsSkippedLimit = 0,
	seedsBought = 0,
	gearBought = 0,
	petsBought = 0,
	inventoryItems = 0,
	inventoryCapacity = CONFIG.maxInventoryItems,
	inventoryFull = false,
}

local running = {}

setStatus = function(message)
	state.lastStatus = tostring(message)
	if statusValue then
		statusValue.Value = state.lastStatus
	end
end

local function countSelected(map)
	local count = 0
	for _, enabled in pairs(map) do
		if enabled then
			count += 1
		end
	end
	return count
end

local function countEnabledToggles()
	local count = 0
	for _, key in ipairs({
		"fruitCollector",
		"seedPlacer",
		"autoShovel",
		"autoSell",
		"sellWhenFull",
		"autoBuySeeds",
		"autoBuyGear",
		"autoCollectRainbowSeeds",
		"autoBuyPets",
		"performanceMode",
		"hidePlants",
	}) do
		if state[key] then
			count += 1
		end
	end
	return count
end

local function shortStatus(text, maxLength)
	text = tostring(text or "")
	maxLength = maxLength or 42
	if #text <= maxLength then
		return text
	end
	return string.sub(text, 1, maxLength - 3) .. "..."
end

local function isEnabled(key)
	return state[key] == true
end

local function addUniqueName(list, name)
	if not name or name == "" then
		return
	end

	for _, existing in ipairs(list) do
		if existing == name then
			return
		end
	end

	table.insert(list, name)
end

local function trimText(value)
	return string.gsub(tostring(value or ""), "^%s*(.-)%s*$", "%1")
end

local function stripVariantWords(name)
	local result = tostring(name or "")
	for _, word in ipairs(petVariantWords) do
		result = string.gsub(result, "^" .. word .. "%s+", "")
		result = string.gsub(result, "%s+" .. word .. "$", "")
	end
	return trimText(result)
end

local function extractVariantLabel(assetName, petName)
	if not assetName or assetName == petName then
		return ""
	end

	local startAt, endAt = string.find(assetName, petName, 1, true)
	if not startAt then
		return ""
	end

	local before = trimText(string.sub(assetName, 1, startAt - 1))
	local after = trimText(string.sub(assetName, endAt + 1))
	return trimText((before .. " " .. after))
end

local function getGearImagesFolder()
	local sharedModules = ReplicatedStorage:FindFirstChild("SharedModules")
	return sharedModules and sharedModules:FindFirstChild("GearImages")
end

getStockItemsFolder = function(shopName)
	local stockValues = ReplicatedStorage:FindFirstChild("StockValues")
	local shop = stockValues and stockValues:FindFirstChild(shopName)
	return shop and shop:FindFirstChild("Items")
end

local function getSeedShopGui()
	return StarterGui:FindFirstChild("SeedShop") or playerGui:FindFirstChild("SeedShop")
end

local function getRuntimeSeedShopGui()
	return playerGui:FindFirstChild("SeedShop") or StarterGui:FindFirstChild("SeedShop")
end

local function getNumericFromInstance(instance, keys)
	if not instance then
		return nil
	end

	for _, key in ipairs(keys) do
		local ok, attribute = pcall(function()
			return instance:GetAttribute(key)
		end)
		local number = ok and tonumber(attribute) or nil
		if number then
			return number
		end

		local child = instance:FindFirstChild(key)
		if child and child:IsA("ValueBase") then
			number = tonumber(child.Value)
			if number then
				return number
			end
		end
	end

	return nil
end

getShopStockAmount = function(shopName, itemName)
	local items = getStockItemsFolder and getStockItemsFolder(shopName)
	local stockItem = items and items:FindFirstChild(itemName)
	if not stockItem then
		return 0
	end

	local value = getNumericFromInstance(stockItem, {
		"Stock",
		"StockAmount",
		"CurrentStock",
		"Amount",
		"Quantity",
		"Count",
		"Available",
		"Value",
	})
	if value then
		return math.max(0, math.floor(value))
	end

	if stockItem:IsA("BoolValue") then
		return stockItem.Value and 1 or 0
	end

	for _, descendant in ipairs(stockItem:GetDescendants()) do
		if descendant:IsA("NumberValue") or descendant:IsA("IntValue") then
			local number = tonumber(descendant.Value)
			if number and number > 0 then
				return math.floor(number)
			end
		elseif descendant:IsA("BoolValue") and descendant.Value == true then
			return 1
		end
	end

	return 0
end

getShopPriceAmount = function(shopName, itemName)
	local items = getStockItemsFolder and getStockItemsFolder(shopName)
	local stockItem = items and items:FindFirstChild(itemName)
	if not stockItem then
		return nil
	end

	return getNumericFromInstance(stockItem, {
		"Price",
		"Cost",
		"Value",
		"Sheckles",
		"Coins",
		"BuyPrice",
		"CurrentPrice",
	})
end

local function getSeedMetadataValue(seedName)
	local keys = { "Rarity", "RarityValue", "Tier", "TierValue", "Priority", "PriorityValue", "Price", "Cost", "Worth" }
	local items = getStockItemsFolder("SeedShop")
	local stockItem = items and items:FindFirstChild(seedName)
	local value = getNumericFromInstance(stockItem, keys)
	if value then
		return value
	end

	for _, path in ipairs({
		{ "SharedModules", "SeedData" },
		{ "SharedData", "SeedData" },
		{ "PlantGenerationModules", "Fruits" },
		{ "PlantGenerationModules", "Plants" },
		{ "Assets", "Plants" },
	}) do
		local current = ReplicatedStorage
		for _, part in ipairs(path) do
			current = current and current:FindFirstChild(part)
		end

		local instance = current and current:FindFirstChild(seedName)
		value = getNumericFromInstance(instance, keys)
		if value then
			return value
		end

		if instance and instance:IsA("ModuleScript") then
			local ok, data = pcall(require, instance)
			if ok and type(data) == "table" then
				for _, key in ipairs(keys) do
					value = tonumber(data[key])
					if value then
						return value
					end
				end
			end
		end
	end

	return 0
end

local function refreshNamesFromStock(shopName, targetList)
	local items = getStockItemsFolder(shopName)
	if not items then
		return
	end

	for _, item in ipairs(items:GetChildren()) do
		if not string.find(string.lower(item.Name), "template", 1, true) then
			addUniqueName(targetList, item.Name)
			if shopName == "SeedShop" and seedPriority[item.Name] == nil then
				seedPriority[item.Name] = getSeedMetadataValue(item.Name)
			end
		end
	end

	table.sort(targetList)
end

local function refreshSeedNamesFromStockValues()
	refreshNamesFromStock("SeedShop", seedNames)
end

local function refreshGearNamesFromStockValues()
	refreshNamesFromStock("GearShop", gearNames)
end

local function refreshPetNamesFromAssets()
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local pets = assets and assets:FindFirstChild("Pets")
	if not pets then
		return
	end

	for _, pet in ipairs(pets:GetChildren()) do
		addUniqueName(petNames, stripVariantWords(pet.Name))
	end

	table.sort(petNames)
end

refreshSeedNamesFromStockValues()
refreshGearNamesFromStockValues()
refreshPetNamesFromAssets()

local function getCharacter()
	return localPlayer.Character or localPlayer.CharacterAdded:Wait()
end

local function getRoot()
	local character = getCharacter()
	return character:FindFirstChild("HumanoidRootPart")
end

local function getHumanoid()
	local character = getCharacter()
	return character:FindFirstChildOfClass("Humanoid")
end

local function getPath(root, path)
	local current = root
	for part in string.gmatch(path, "[^%.]+") do
		current = current and current:FindFirstChild(part)
	end
	return current
end

local function getObjectPath(instance)
	local parts = {}
	local current = instance
	while current and current ~= game do
		table.insert(parts, 1, current.Name)
		current = current.Parent
	end
	return table.concat(parts, ".")
end

local function safeText(value)
	if value == nil then
		return ""
	end

	return tostring(value)
end

local packetModule

local function getPacketModule()
	if packetModule ~= nil then
		return packetModule
	end

	packetModule = false
	local sharedModules = ReplicatedStorage:FindFirstChild("SharedModules")
	local packetScript = sharedModules and sharedModules:FindFirstChild("Packet")
	if packetScript and packetScript:IsA("ModuleScript") then
		pcall(function()
			packetModule = require(packetScript)
		end)
	end

	return packetModule
end

local packetRemote

local function getPacketRemote()
	if packetRemote and packetRemote.Parent then
		return packetRemote
	end

	local sharedModules = ReplicatedStorage:FindFirstChild("SharedModules")
	local packetScript = sharedModules and sharedModules:FindFirstChild("Packet")
	packetRemote = packetScript and packetScript:FindFirstChild("RemoteEvent")

	if not packetRemote then
		packetRemote = ReplicatedStorage:FindFirstChild("RemoteEvent", true)
	end

	if packetRemote and packetRemote:IsA("RemoteEvent") then
		return packetRemote
	end

	packetRemote = nil
	return nil
end

local function firePacketRemote(packetName, ...)
	local remote = getPacketRemote()
	if not remote then
		return false
	end

	local id = remote:GetAttribute(packetName)
	for _, firstArg in ipairs({ packetName, id }) do
		if firstArg ~= nil then
			local ok = pcall(function(...)
				remote:FireServer(firstArg, ...)
			end, ...)
			if ok then
				return true
			end
		end
	end

	return false
end

local function tryPacketEntry(entry, ...)
	if type(entry) == "table" then
		for _, methodName in ipairs({ "Fire", "FireServer", "Send", "SendToServer" }) do
			if type(entry[methodName]) == "function" then
				if pcall(entry[methodName], entry, ...) or pcall(entry[methodName], ...) then
					return true
				end
			end
		end
	elseif type(entry) == "function" then
		if pcall(entry, ...) then
			return true
		end
	end

	return false
end

local function findPacketEntry(root, packetName, seen)
	if type(root) ~= "table" then
		return nil
	end

	seen = seen or {}
	if seen[root] then
		return nil
	end
	seen[root] = true

	if root[packetName] ~= nil then
		return root[packetName]
	end

	for _, value in pairs(root) do
		if type(value) == "table" then
			local found = findPacketEntry(value, packetName, seen)
			if found ~= nil then
				return found
			end
		end
	end

	return nil
end

local function sendPacket(packetName, ...)
	local packet = getPacketModule()
	if type(packet) == "table" then
		local entry = findPacketEntry(packet, packetName)
		if tryPacketEntry(entry, ...) then
			return true
		end

		for _, methodName in ipairs({ "Fire", "FireServer", "Send", "SendToServer" }) do
			if type(packet[methodName]) == "function" then
				if pcall(packet[methodName], packet, packetName, ...) or pcall(packet[methodName], packetName, ...) then
					return true
				end
			end
		end
	elseif type(packet) == "function" then
		local ok = pcall(packet, packetName, ...)
		if ok then
			return true
		end
	end

	return firePacketRemote(packetName, ...)
end

local function sendAnyPacket(packetNames, ...)
	for _, packetName in ipairs(packetNames) do
		if sendPacket(packetName, ...) then
			return true, packetName
		end
	end

	return false, nil
end

local cache = {
	seedFrames = {},
	gearFrames = {},
}

local touchPart
local getPromptPart
local triggerPrompt
local triggerPromptFast
local teleportToPart
local teleportToModelOrPart
local isInventorySeedTool
local enablePerformanceMode
local enableHidePlants

local function getCachedDescendants(key, root, maxAge)
	local now = os.clock()
	local atKey = key .. "At"
	local listKey = key .. "Descendants"
	maxAge = maxAge or CONFIG.cacheRefreshInterval

	if not root then
		cache[atKey] = now
		cache[listKey] = {}
		return cache[listKey]
	end

	if not cache[atKey] or now - cache[atKey] > maxAge then
		cache[atKey] = now
		cache[listKey] = root:GetDescendants()
	end

	return cache[listKey]
end

local function getMap()
	return workspace:FindFirstChild("Map")
end

local function getGardens()
	return workspace:FindFirstChild("Gardens")
end

local dropCacheRoots = {}

local function invalidateDropCaches()
	cache.rainbow1At = nil
	cache.rainbow2At = nil
end

local function watchDropRoot(root)
	if not root or dropCacheRoots[root] then
		return
	end

	dropCacheRoots[root] = true
end

local function watchDropRoots()
	watchDropRoot(getMap())
	watchDropRoot(getGardens())
end

local function getWildPetSpawns()
	local map = getMap()
	return map and map:FindFirstChild("WildPetSpawns")
end

local function refreshBuyPetNamesFromWildSpawns()
	local wildPetSpawns = getWildPetSpawns()
	if not wildPetSpawns then
		return
	end

	for _, descendant in ipairs(wildPetSpawns:GetDescendants()) do
		local model
		if descendant:IsA("ProximityPrompt") then
			model = descendant:FindFirstAncestorWhichIsA("Model")
		elseif descendant:IsA("Model") and descendant:FindFirstChildWhichIsA("ProximityPrompt", true) then
			model = descendant
		end

		if model then
			local petName = stripVariantWords(model.Name)
			addUniqueName(buyPetNames, petName)
			notifyPetSpawn(petName)
		end
	end

	table.sort(buyPetNames)
end

local function valueMatchesLocalPlayer(value)
	if value == localPlayer then
		return true
	end

	if typeof(value) == "Instance" and value:IsA("Player") then
		return value == localPlayer
	end

	local text = tostring(value or "")
	return text == tostring(localPlayer.UserId) or string.lower(text) == string.lower(localPlayer.Name)
end

local function plotBelongsToLocalPlayer(plot)
	if not plot then
		return false
	end

	if valueMatchesLocalPlayer(plot.Name) then
		return true
	end

	for _, key in ipairs({ "Owner", "OwnerId", "UserId", "Player", "PlayerName" }) do
		local ok, attribute = pcall(function()
			return plot:GetAttribute(key)
		end)
		if ok and valueMatchesLocalPlayer(attribute) then
			return true
		end

		local child = plot:FindFirstChild(key, true)
		if child and child:IsA("ValueBase") and valueMatchesLocalPlayer(child.Value) then
			return true
		end
	end

	return false
end

local ownGardenCache = {
	roots = {},
	checkedAt = 0,
}

local fruitTargetCache = {
	targets = {},
	refreshedAt = 0,
	cursor = 1,
	rootCount = 0,
}

local function invalidateOwnGardenCache()
	ownGardenCache.checkedAt = 0
	cache.ownGardenDescendants = nil
	cache.ownGardenAt = nil
	fruitTargetCache.refreshedAt = 0
	fruitTargetCache.targets = {}
	fruitTargetCache.cursor = 1
end

local function addUniqueInstance(list, instance)
	if not instance then
		return false
	end

	for _, existing in ipairs(list) do
		if existing == instance then
			return false
		end
	end

	table.insert(list, instance)
	return true
end

local function collectNamedDescendantRoots(root, names, results, limit)
	if not root then
		return
	end

	local wanted = {}
	for _, name in ipairs(names) do
		wanted[string.lower(name)] = true
	end

	for _, descendant in ipairs(root:GetDescendants()) do
		if wanted[string.lower(descendant.Name)] then
			addUniqueInstance(results, descendant)
			if #results >= (limit or 8) then
				return
			end
		end
	end
end

local function getOwnGardenRoots()
	local now = os.clock()
	if now - ownGardenCache.checkedAt < 5 and #ownGardenCache.roots > 0 then
		return ownGardenCache.roots
	end

	local gardens = getGardens()
	local userId = tostring(localPlayer.UserId)
	local roots = {}

	if not gardens then
		return roots
	end

	local function addOwnPlot(plot)
		if not plot then
			return
		end

		local added = false
		local rootNames = { "Plants", "Fruits", "Fruit", "Crops", "Harvest", "Harvests", "Drops" }
		for _, name in ipairs(rootNames) do
			local child = plot:FindFirstChild(name)
			if child then
				added = addUniqueInstance(roots, child) or added
			end
		end

		if not added then
			local before = #roots
			collectNamedDescendantRoots(plot, rootNames, roots, 10)
			added = #roots > before
		end

		if not added then
			addUniqueInstance(roots, plot)
		end
	end

	for _, plot in ipairs(gardens:GetChildren()) do
		local plants = plot:FindFirstChild("Plants")
		if plants and plotBelongsToLocalPlayer(plot) then
			addOwnPlot(plot)
		elseif plants then
			for _, plant in ipairs(plants:GetChildren()) do
				if string.sub(plant.Name, 1, #userId + 1) == userId .. "_" then
					addOwnPlot(plot)
					break
				end
			end
		elseif plotBelongsToLocalPlayer(plot) then
			addOwnPlot(plot)
		end
	end

	ownGardenCache.roots = roots
	ownGardenCache.checkedAt = now
	return roots
end

local function getGardenAnchorPart(root)
	if not root then
		return nil
	end

	if root:IsA("BasePart") then
		return root
	end

	local parent = root.Parent
	for _, name in ipairs({ "PlantingGround", "PlantingArea", "Soil", "Dirt", "Ground", "Base", "Plot" }) do
		local direct = root:FindFirstChild(name) or (parent and parent:FindFirstChild(name))
		if direct and direct:IsA("BasePart") then
			return direct
		end
	end

	if parent then
		for _, descendant in ipairs(parent:GetChildren()) do
			if descendant:IsA("BasePart") then
				local lowered = string.lower(descendant.Name)
				if string.find(lowered, "soil", 1, true)
					or string.find(lowered, "dirt", 1, true)
					or string.find(lowered, "ground", 1, true)
					or string.find(lowered, "plot", 1, true)
					or string.find(lowered, "plant", 1, true)
				then
					return descendant
				end
			end
		end
	end

	if parent and parent:IsA("Model") then
		local ok, cframe = pcall(function()
			return parent:GetBoundingBox()
		end)
		if ok then
			return cframe.Position
		end
	end

	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("BasePart") then
			return descendant
		end
	end

	return nil
end

local function getOwnGardenAnchor()
	for _, root in ipairs(getOwnGardenRoots()) do
		local part = getGardenAnchorPart(root)
		if part then
			return part
		end
	end

	return nil
end

local gardensForCache = getGardens()
if gardensForCache then
	gardensForCache.ChildAdded:Connect(invalidateOwnGardenCache)
	gardensForCache.ChildRemoved:Connect(invalidateOwnGardenCache)
end

workspace.ChildAdded:Connect(function(child)
	if child.Name == "Gardens" then
		invalidateOwnGardenCache()
		child.ChildAdded:Connect(invalidateOwnGardenCache)
		child.ChildRemoved:Connect(invalidateOwnGardenCache)
		if state.performanceMode or state.hidePlants then
			task.defer(function()
				if state.performanceMode and enablePerformanceMode then
					enablePerformanceMode()
				elseif enableHidePlants then
					enableHidePlants()
				end
			end)
		end
	elseif child.Name == "Map" and (state.performanceMode or state.hidePlants) then
		task.defer(function()
			if state.performanceMode and enablePerformanceMode then
				enablePerformanceMode()
			elseif enableHidePlants then
				enableHidePlants()
			end
		end)
	end
end)

local function textMatches(instance, terms)
	local instanceText = ""
	pcall(function()
		instanceText = safeText(instance.Text)
	end)

	local metadata = {}
	pcall(function()
		for name, value in pairs(instance:GetAttributes()) do
			table.insert(metadata, safeText(name))
			table.insert(metadata, safeText(value))
		end
	end)
	pcall(function()
		for _, tag in ipairs(CollectionService:GetTags(instance)) do
			table.insert(metadata, safeText(tag))
		end
	end)
	for _, childName in ipairs({ "Variant", "Mutation", "Mutations", "Rarity" }) do
		local child = instance:FindFirstChild(childName)
		if child and child:IsA("ValueBase") then
			table.insert(metadata, childName)
			table.insert(metadata, safeText(child.Value))
		end
	end

	local haystack = string.lower(table.concat({
		safeText(instance.Name),
		instanceText,
		getObjectPath(instance),
		table.concat(metadata, " "),
		instance:IsA("ProximityPrompt") and safeText(instance.ActionText) or "",
		instance:IsA("ProximityPrompt") and safeText(instance.ObjectText) or "",
	}, " "))

	for _, term in ipairs(terms) do
		if string.find(haystack, string.lower(term), 1, true) then
			return true
		end
	end

	return false
end

local function treeTextMatches(instance, terms, maxAncestors)
	local current = instance
	local checked = 0

	while current and current ~= workspace and checked <= (maxAncestors or 4) do
		if textMatches(current, terms) then
			return true
		end
		current = current.Parent
		checked += 1
	end

	return false
end

local function getToolContainers()
	return {
		getCharacter(),
		localPlayer:FindFirstChildOfClass("Backpack"),
	}
end

local function countInventoryTools()
	local count = 0
	for _, container in ipairs(getToolContainers()) do
		if container then
			for _, item in ipairs(container:GetChildren()) do
				if item:IsA("Tool") then
					count += 1
				end
			end
		end
	end
	return count
end

local function guiShowsInventoryFull()
	for _, descendant in ipairs(playerGui:GetDescendants()) do
		if descendant:IsA("TextLabel") or descendant:IsA("TextButton") or descendant:IsA("TextBox") then
			local ok, visible = pcall(function()
				return descendant.Visible
			end)
			if ok and visible and textMatches(descendant, { "inventory full", "backpack full", "bag full", "storage full" }) then
				return true
			end
		end
	end
	return false
end

local inventoryCache = {
	items = 0,
	capacity = CONFIG.maxInventoryItems,
	full = false,
	guiFull = false,
	checkedAt = 0,
	guiCheckedAt = 0,
}

local function refreshInventoryStats(force)
	local now = os.clock()
	if not force and now - inventoryCache.checkedAt < CONFIG.inventoryRefreshInterval then
		stats.inventoryItems = inventoryCache.items
		stats.inventoryCapacity = inventoryCache.capacity
		stats.inventoryFull = inventoryCache.full
		return stats.inventoryFull, stats.inventoryItems, stats.inventoryCapacity
	end

	local count = countInventoryTools()
	local capacity = CONFIG.maxInventoryItems
	if force or now - inventoryCache.guiCheckedAt >= CONFIG.guiInventoryRefreshInterval then
		inventoryCache.guiCheckedAt = now
		inventoryCache.guiFull = guiShowsInventoryFull()
	end
	local full = count >= capacity or inventoryCache.guiFull

	inventoryCache.items = count
	inventoryCache.capacity = capacity
	inventoryCache.full = full
	inventoryCache.checkedAt = now
	stats.inventoryItems = count
	stats.inventoryCapacity = capacity
	stats.inventoryFull = full

	return full, count, capacity
end

local function updateStatsUI()
	local elapsedMinutes = math.max((os.clock() - sessionStartedAt) / 60, 0.01)
	local fruitRate = math.floor((stats.fruitCollected / elapsedMinutes) + 0.5)
	local freeSlots = math.max((stats.inventoryCapacity or CONFIG.maxInventoryItems) - (stats.inventoryItems or 0), 0)

	for key, label in pairs(statsLabels) do
		if label and label.Parent then
			if key == "status" then
				label.Text = ("Status: %s"):format(shortStatus(state.lastStatus, 46))
			elseif key == "systems" then
				label.Text = ("Enabled: %d systems | Teleport %s"):format(countEnabledToggles(), state.collectTeleport and "ON" or "OFF")
			elseif key == "inventory" then
				label.Text = ("Inventory: %d/%d (%d free)%s"):format(stats.inventoryItems, stats.inventoryCapacity, freeSlots, stats.inventoryFull and " FULL" or "")
			elseif key == "collect" then
				label.Text = ("Fruit: %d total | %d/min | %d targets scanned"):format(stats.fruitCollected, fruitRate, stats.fruitTargetsChecked)
			elseif key == "planting" then
				label.Text = ("Planting: %d placed | %d shoveled | %d seed(s) selected"):format(stats.seedsPlanted, stats.seedsShoveled, countSelected(selectedSeeds))
			elseif key == "shops" then
				label.Text = ("Bought: %d seeds | %d gear | %d pets"):format(stats.seedsBought, stats.gearBought, stats.petsBought)
			elseif key == "limits" then
				label.Text = ("Blocked: %d full | %d range | %d seed limit"):format(stats.collectSkippedFull, stats.collectSkippedRange, stats.seedsSkippedLimit)
			end
		end
	end
end

local function getSeedRarity(seedName)
	return seedPriority[seedName] or 0
end

local function readNumericMetadata(instance, keys, maxAncestors)
	local best = 0
	local current = instance
	local checked = 0

	while current and current ~= workspace and checked <= (maxAncestors or 5) do
		for _, key in ipairs(keys) do
			local ok, attribute = pcall(function()
				return current:GetAttribute(key)
			end)
			local number = ok and tonumber(attribute) or nil
			if number then
				best = math.max(best, number)
			end

			local child = current:FindFirstChild(key)
			if child and child:IsA("ValueBase") then
				number = tonumber(child.Value)
				if number then
					best = math.max(best, number)
				end
			end
		end

		current = current.Parent
		checked += 1
	end

	return best
end

local function getSortedSeedList(list)
	table.sort(list, function(left, right)
		local leftRarity = getSeedRarity(left)
		local rightRarity = getSeedRarity(right)
		if leftRarity ~= rightRarity then
			return leftRarity > rightRarity
		end
		return left < right
	end)
	return list
end

local function getInstanceTextBlob(instance, maxAncestors)
	local parts = {}
	local current = instance
	local checked = 0

	while current and current ~= workspace and checked <= (maxAncestors or 4) do
		table.insert(parts, safeText(current.Name))
		if current:IsA("ProximityPrompt") then
			table.insert(parts, safeText(current.ActionText))
			table.insert(parts, safeText(current.ObjectText))
		end
		pcall(function()
			for name, value in pairs(current:GetAttributes()) do
				table.insert(parts, safeText(name))
				table.insert(parts, safeText(value))
			end
		end)
		for _, childName in ipairs({ "Variant", "Mutation", "Mutations", "Rarity", "Weight" }) do
			local child = current:FindFirstChild(childName)
			if child and child:IsA("ValueBase") then
				table.insert(parts, childName)
				table.insert(parts, safeText(child.Value))
			end
		end
		current = current.Parent
		checked += 1
	end

	return string.lower(table.concat(parts, " "))
end

local function getFruitWeight(instance)
	local blob = getInstanceTextBlob(instance, 5)
	local weight = tonumber(string.match(blob, "([%d%.]+)%s*kg"))
		or tonumber(string.match(blob, "([%d%.]+)%s*g"))
		or tonumber(string.match(blob, "([%d%.]+)%s*lb"))
		or 0

	if string.find(blob, "kg", 1, true) then
		weight *= 1000
	elseif string.find(blob, "lb", 1, true) then
		weight *= 453.592
	end

	return weight
end

local function getFruitRarity(instance)
	return readNumericMetadata(instance, { "Rarity", "RarityValue", "Tier", "TierValue", "Priority", "Value" }, 5)
end

local function getFruitMutationValue(instance)
	return readNumericMetadata(instance, { "MutationValue", "MutationMultiplier", "MutationPrice", "MutationWorth", "VariantValue", "VariantMultiplier" }, 5)
end

local function getPromptDistance(prompt)
	local root = getRoot()
	local part = getPromptPart and getPromptPart(prompt)
	if not root or not part then
		return math.huge
	end
	return (root.Position - part.Position).Magnitude
end

local function isHarvestPrompt(prompt)
	if not prompt or not prompt:IsA("ProximityPrompt") then
		return false
	end

	if prompt.Name == "StealPrompt" or prompt.ActionText == "Steal" then
		return false
	end

	return prompt.Name == "HarvestPrompt"
		or treeTextMatches(prompt, { "harvestprompt", "collect", "harvest", "pick", "fruit" }, 3)
end

local function isUsableHarvestPrompt(prompt)
	if not isHarvestPrompt(prompt) then
		return false
	end

	local ok, enabled = pcall(function()
		return prompt.Enabled
	end)

	return not ok or enabled
end

local function getCollectFruitTarget(prompt)
	local current = prompt and prompt.Parent

	while current and current ~= workspace do
		if current.Parent and current.Parent.Name == "Fruits" then
			return current
		end
		current = current.Parent
	end

	return prompt and prompt.Parent
end

local function getFruitPlantTarget(fruit)
	local current = fruit
	while current and current ~= workspace do
		if current.Parent and current.Parent.Name == "Fruits" then
			return current.Parent.Parent
		end
		current = current.Parent
	end
	return nil
end

local function collectFruitPacket(target)
	if not target then
		return false
	end

	local fruit = target
	local current = target
	while current and current ~= workspace do
		if current.Parent and current.Parent.Name == "Fruits" then
			fruit = current
			break
		end
		current = current.Parent
	end

	local plant = getFruitPlantTarget(fruit)
	local tries = {
		{ fruit },
		{ fruit and fruit.Name },
		{ target },
		{ target and target.Name },
		{ plant, fruit },
		{ plant and plant.Name, fruit and fruit.Name },
		{ plant and plant.Name, fruit },
	}
	local unpackArgs = table.unpack or unpack

	for _, args in ipairs(tries) do
		local clean = {}
		for _, value in ipairs(args) do
			if value ~= nil then
				table.insert(clean, value)
			end
		end
		if #clean > 0 and sendPacket("CollectFruit", unpackArgs(clean)) then
			return true
		end
	end

	return false
end

local function collectionTookEffect(target, beforeInventoryCount)
	task.wait(0.12)

	if target and not target.Parent then
		return true
	end

	if target and target.Parent and not target:IsDescendantOf(workspace) then
		return true
	end

	local afterInventoryCount = countInventoryTools()
	return beforeInventoryCount ~= nil and afterInventoryCount > beforeInventoryCount
end

local function isFruitContainer(instance)
	local current = instance
	local checked = 0
	while current and current ~= workspace and checked <= 5 do
		local name = string.lower(current.Name)
		if name == "fruits" or name == "fruit" then
			return true
		end
		current = current.Parent
		checked += 1
	end
	return false
end

local function getFruitObjectTarget(instance)
	local current = instance
	while current and current ~= workspace do
		if current.Parent and current.Parent.Name == "Fruits" then
			return current
		end
		current = current.Parent
	end
	return instance
end

local function isLikelyFruitTarget(instance)
	if not instance or instance:IsA("ProximityPrompt") then
		return false
	end

	if not (instance:IsA("Model") or instance:IsA("BasePart")) then
		return false
	end

	local blob = getInstanceTextBlob(instance, 3)
	if isFruitContainer(instance) then
		return true
	end

	if string.find(blob, "kg", 1, true)
		or string.find(blob, "lb", 1, true)
		or string.find(blob, "fruit", 1, true)
		or string.find(blob, "mutation", 1, true)
	then
		return true
	end

	return false
end

local function getTargetPart(target)
	if not target then
		return nil
	end
	if target:IsA("BasePart") then
		return target
	end
	if target:IsA("Model") then
		return target.PrimaryPart
			or target:FindFirstChild("HumanoidRootPart", true)
			or target:FindFirstChildWhichIsA("BasePart", true)
	end
	if target:IsA("Folder") then
		return target:FindFirstChildWhichIsA("BasePart", true)
	end
	return nil
end

local function collectPrompt(prompt)
	local part = getPromptPart and getPromptPart(prompt)
	if part and not state.collectTeleport and getPromptDistance(prompt) > (prompt.MaxActivationDistance or 10) then
		stats.collectSkippedRange += 1
		return false
	end

	local target = getCollectFruitTarget(prompt)
	local beforeInventoryCount = countInventoryTools()
	if target ~= nil then
		collectFruitPacket(target)
	end

	if part and state.collectTeleport then
		teleportToPart(part, 2)
	end

	triggerPrompt(prompt, true)
	if target ~= nil then
		collectFruitPacket(target)
	end

	return collectionTookEffect(target or prompt, beforeInventoryCount)
end

local function getHarvestPromptInTarget(target)
	if not target then
		return nil
	end

	if target:IsA("ProximityPrompt") and isUsableHarvestPrompt(target) then
		return target
	end

	if target:IsA("Model") or target:IsA("BasePart") or target:IsA("Folder") then
		for _, descendant in ipairs(target:GetDescendants()) do
			if isUsableHarvestPrompt(descendant) then
				return descendant
			end
		end
	end

	return nil
end

local function collectFruitTarget(target)
	if not target then
		return false
	end

	local beforeInventoryCount = countInventoryTools()
	collectFruitPacket(target)
	sendPacket("HarvestFruit", target)
	sendPacket("Collect", target)
	sendPacket("Harvest", target)

	local part = getTargetPart(target)
	if part and state.collectTeleport then
		local model = target:IsA("Model") and target or target:FindFirstAncestorWhichIsA("Model")
		if model then
			teleportToModelOrPart(model, part, 3)
		else
			teleportToPart(part, 3)
		end
	elseif part and not state.collectTeleport then
		local root = getRoot()
		if root and (root.Position - part.Position).Magnitude > 16 then
			stats.collectSkippedRange += 1
			return false
		end
	end

	local prompt = getHarvestPromptInTarget(target)
	if prompt then
		collectPrompt(prompt)
	end

	collectFruitPacket(target)
	sendPacket("HarvestFruit", target)
	sendPacket("Collect", target)
	sendPacket("Harvest", target)

	if part then
		touchPart(part, state.collectTeleport)
	end

	return collectionTookEffect(target, beforeInventoryCount)
end

local function getTargetDistance(target)
	local root = getRoot()
	local part = target and getTargetPart(target)
	if not root or not part then
		return math.huge
	end
	return (root.Position - part.Position).Magnitude
end

local function getFruitPriority(instance)
	local weight = getFruitWeight(instance)
	local rarity = getFruitRarity(instance)
	local mutation = getFruitMutationValue(instance)
	local haystack = string.lower(getObjectPath(instance))
	local priority = 0

	priority += weight * 1000000
	priority += rarity * 10000
	priority += mutation * 100

	if string.find(haystack, "rainbow", 1, true) then
		priority += 10000
	end
	if string.find(haystack, "golden", 1, true) or string.find(haystack, "gold", 1, true) then
		priority += 6000
	end
	if string.find(haystack, "huge", 1, true) or string.find(haystack, "giant", 1, true) then
		priority += 3000
	end

	return priority
end

local function isLiveFruitEntry(entry)
	if not entry then
		return false
	end

	local target = entry.target or entry.prompt
	if not target or not target.Parent then
		return false
	end

	if not target:IsDescendantOf(workspace) then
		return false
	end

	if entry.prompt and (not entry.prompt.Parent or not isUsableHarvestPrompt(entry.prompt)) then
		return false
	end

	return true
end

local function addFruitTarget(targets, seenTargets, prompt, target)
	target = target or prompt
	if not target or seenTargets[target] then
		return
	end

	seenTargets[target] = true
	table.insert(targets, {
		prompt = prompt,
		target = target,
		priority = getFruitPriority(target),
	})
end

local function rebuildFruitTargetCache(roots)
	local targets = {}
	local seenTargets = {}

	for index, root in ipairs(roots) do
		if not root then
			continue
		end

		local scanned = 0
		local descendants = getCachedDescendants("fruitFast" .. index, root, CONFIG.fruitCacheRefreshInterval)
		for _, descendant in ipairs(descendants) do
			if #targets >= CONFIG.maxFruitTargetsCached then
				break
			end

			scanned += 1
			if scanned > CONFIG.maxFruitScanPerRoot then
				break
			end

			if isUsableHarvestPrompt(descendant) then
				addFruitTarget(targets, seenTargets, descendant, getCollectFruitTarget(descendant))
			end
		end
	end

	if #targets == 0 then
		for index, root in ipairs(roots) do
			if not root then
				continue
			end

			local scanned = 0
			local descendants = getCachedDescendants("fruitFallback" .. index, root, CONFIG.fruitCacheRefreshInterval)
			for _, descendant in ipairs(descendants) do
				if #targets >= CONFIG.maxFruitTargetsCached then
					break
				end

				scanned += 1
				if scanned > math.floor(CONFIG.maxFruitScanPerRoot / 3) then
					break
				end

				if isLikelyFruitTarget(descendant) then
					addFruitTarget(targets, seenTargets, nil, getFruitObjectTarget(descendant))
				end
			end
		end
	end

	table.sort(targets, function(left, right)
		if left.priority ~= right.priority then
			return left.priority > right.priority
		end
		return getTargetDistance(left.target) < getTargetDistance(right.target)
	end)

	fruitTargetCache.targets = targets
	fruitTargetCache.refreshedAt = os.clock()
	fruitTargetCache.cursor = 1
	fruitTargetCache.rootCount = #roots
	return targets
end

local function getFruitTargetBatch(roots)
	local now = os.clock()
	local targets = fruitTargetCache.targets
	if #targets == 0
		or now - fruitTargetCache.refreshedAt > CONFIG.fruitCacheRefreshInterval
		or fruitTargetCache.rootCount ~= #roots
	then
		targets = rebuildFruitTargetCache(roots)
	end

	local batch = {}
	local checked = 0
	while #batch < CONFIG.maxFruitCollectPerTick and checked < #targets do
		if fruitTargetCache.cursor > #targets then
			fruitTargetCache.cursor = 1
		end

		local entry = targets[fruitTargetCache.cursor]
		fruitTargetCache.cursor += 1
		checked += 1

		if isLiveFruitEntry(entry) then
			table.insert(batch, entry)
		end
	end

	if #batch == 0 and #targets > 0 then
		targets = rebuildFruitTargetCache(roots)
		for index, entry in ipairs(targets) do
			if index > CONFIG.maxFruitCollectPerTick then
				break
			end
			if isLiveFruitEntry(entry) then
				table.insert(batch, entry)
			end
		end
	end

	return batch, #targets
end

local function pruneFruitTargetCache()
	local live = {}
	for _, entry in ipairs(fruitTargetCache.targets) do
		if isLiveFruitEntry(entry) then
			table.insert(live, entry)
		end
	end

	fruitTargetCache.targets = live
	if fruitTargetCache.cursor > #live then
		fruitTargetCache.cursor = 1
	end
end

local function collectFruitEntryFast(entry)
	if not isLiveFruitEntry(entry) then
		return false
	end

	local target = entry.target
	local prompt = entry.prompt or getHarvestPromptInTarget(target)
	local part = prompt and getPromptPart(prompt) or getTargetPart(target)

	if part and state.collectTeleport then
		local root = getRoot()
		local maxDistance = (prompt and prompt.MaxActivationDistance) or 16
		if not root or (root.Position - part.Position).Magnitude > math.max(maxDistance - 2, 6) then
			local model = target and target:IsA("Model") and target or (target and target:FindFirstAncestorWhichIsA("Model"))
			if model then
				teleportToModelOrPart(model, part, 2.5)
			else
				teleportToPart(part, 2.5)
			end
		end
	elseif part and not state.collectTeleport then
		local root = getRoot()
		if root and (root.Position - part.Position).Magnitude > ((prompt and prompt.MaxActivationDistance) or 16) then
			stats.collectSkippedRange += 1
			return false
		end
	end

	local fired = false
	if target then
		fired = collectFruitPacket(target) or fired
		fired = sendPacket("HarvestFruit", target) or fired
		fired = sendPacket("Collect", target) or fired
		fired = sendPacket("Harvest", target) or fired
	end

	if prompt then
		fired = triggerPromptFast(prompt) or fired
	end

	if target then
		fired = collectFruitPacket(target) or fired
	end

	if part then
		fired = touchPart(part, state.collectTeleport) or fired
	end

	return fired
end

local function collectFruitEntryRemoteOnly(entry)
	if not isLiveFruitEntry(entry) then
		return false
	end

	local target = entry.target
	local prompt = entry.prompt
	if not target and prompt then
		target = getCollectFruitTarget(prompt)
	end

	if not target then
		return false
	end

	local fired = collectFruitPacket(target)
	fired = sendPacket("CollectFruit", target) or fired
	return fired
end

function triggerPrompt(prompt, skipTouch)
	local part = getPromptPart and getPromptPart(prompt)
	if part and not skipTouch then
		teleportToPart(part, 3)
		task.wait(0.05)
	end

	local oldHoldDuration
	local oldRequiresLineOfSight
	local oldMaxActivationDistance
	pcall(function()
		oldHoldDuration = prompt.HoldDuration
		oldRequiresLineOfSight = prompt.RequiresLineOfSight
		oldMaxActivationDistance = prompt.MaxActivationDistance
		prompt.HoldDuration = 0
		prompt.RequiresLineOfSight = false
		prompt.MaxActivationDistance = math.max(prompt.MaxActivationDistance, 20)
	end)

	local fired = false
	if typeof(fireproximityprompt) == "function" then
		fired = pcall(fireproximityprompt, prompt)
			or pcall(fireproximityprompt, prompt, 1)
			or pcall(fireproximityprompt, prompt, 0)
	end

	local ok = pcall(function()
		prompt:InputHoldBegin()
		task.wait(math.max(prompt.HoldDuration or 0, 0.08))
		prompt:InputHoldEnd()
	end)

	if ok then
		fired = true
	end

	if virtualInputManager then
		local keyOk = pcall(function()
			virtualInputManager:SendKeyEvent(true, prompt.KeyboardKeyCode or Enum.KeyCode.E, false, game)
			task.wait(0.05)
			virtualInputManager:SendKeyEvent(false, prompt.KeyboardKeyCode or Enum.KeyCode.E, false, game)
		end)
		if keyOk then
			fired = true
		end
	end

	pcall(function()
		if oldHoldDuration ~= nil then
			prompt.HoldDuration = oldHoldDuration
		end
		if oldRequiresLineOfSight ~= nil then
			prompt.RequiresLineOfSight = oldRequiresLineOfSight
		end
		if oldMaxActivationDistance ~= nil then
			prompt.MaxActivationDistance = oldMaxActivationDistance
		end
	end)

	return fired
end

triggerPromptFast = function(prompt)
	if not prompt or not prompt.Parent then
		return false
	end

	local oldHoldDuration
	local oldRequiresLineOfSight
	local oldMaxActivationDistance
	pcall(function()
		oldHoldDuration = prompt.HoldDuration
		oldRequiresLineOfSight = prompt.RequiresLineOfSight
		oldMaxActivationDistance = prompt.MaxActivationDistance
		prompt.HoldDuration = 0
		prompt.RequiresLineOfSight = false
		prompt.MaxActivationDistance = math.max(prompt.MaxActivationDistance, 24)
	end)

	local fired = false
	if typeof(fireproximityprompt) == "function" then
		fired = pcall(fireproximityprompt, prompt)
			or pcall(fireproximityprompt, prompt, 0)
			or pcall(fireproximityprompt, prompt, 1)
	end

	local ok = pcall(function()
		prompt:InputHoldBegin()
		prompt:InputHoldEnd()
	end)
	fired = fired or ok

	pcall(function()
		if oldHoldDuration ~= nil then
			prompt.HoldDuration = oldHoldDuration
		end
		if oldRequiresLineOfSight ~= nil then
			prompt.RequiresLineOfSight = oldRequiresLineOfSight
		end
		if oldMaxActivationDistance ~= nil then
			prompt.MaxActivationDistance = oldMaxActivationDistance
		end
	end)

	return fired
end

local function activateButton(button)
	local fired = false

	if typeof(getconnections) == "function" then
		for _, signal in ipairs({ button.Activated, button.MouseButton1Click, button.MouseButton1Down }) do
			for _, connection in ipairs(getconnections(signal)) do
				pcall(function()
					if connection.Function then
						connection.Function()
					elseif connection.Fire then
						connection:Fire()
					end
				end)
				fired = true
			end
		end
	end

	if typeof(firesignal) == "function" then
		pcall(firesignal, button.MouseButton1Click)
		pcall(firesignal, button.Activated)
		pcall(firesignal, button.MouseButton1Down)
		fired = true
	end

	if fired then
		return true
	end

	local position = button.AbsolutePosition + button.AbsoluteSize / 2
	if not virtualInputManager then
		return false
	end

	local ok = pcall(function()
		virtualInputManager:SendMouseButtonEvent(position.X, position.Y, 0, true, game, 1)
		virtualInputManager:SendMouseButtonEvent(position.X, position.Y, 0, false, game, 1)
	end)

	return ok
end

local function collectFruit()
	if not isEnabled("fruitCollector") then
		return
	end

	local inventoryFull = refreshInventoryStats()
	if inventoryFull then
		stats.collectSkippedFull += 1
		updateStatsUI()
		setStatus(("Fruit collector: inventory full (%d/%d)"):format(stats.inventoryItems, stats.inventoryCapacity))
		return
	end

	local roots = getOwnGardenRoots()

	if #roots == 0 then
		setStatus("Fruit collector: no owned garden found")
		return
	end

	local targets, totalCached = getFruitTargetBatch(roots)

	if #targets == 0 then
		updateStatsUI()
		setStatus(("Fruit collector: no harvest targets found (%d root(s))"):format(#roots))
		return
	end

	local beforeInventoryCount = countInventoryTools()
	local fired = 0
	local fallback = 0
	for index, entry in ipairs(targets) do
		if not isEnabled("fruitCollector") then
			return
		end

		if collectFruitEntryRemoteOnly(entry) then
			fired += 1
		end

		if index % 30 == 0 then
			task.wait()
		end
	end

	task.wait(0.03)
	for _, entry in ipairs(targets) do
		if not isEnabled("fruitCollector") then
			return
		end

		if fallback >= CONFIG.maxFruitPromptFallbackPerTick then
			break
		end

		if isLiveFruitEntry(entry) and collectFruitEntryFast(entry) then
			fallback += 1
		end

		if fallback > 0 and fallback % 15 == 0 then
			task.wait()
		end
	end

	task.wait(0.03)
	local afterInventoryCount = countInventoryTools()
	local gained = math.max((afterInventoryCount or 0) - (beforeInventoryCount or 0), 0)
	stats.fruitCollected += gained
	stats.fruitTargetsChecked += totalCached
	pruneFruitTargetCache()
	refreshInventoryStats()
	updateStatsUI()
	if fired == 0 then
		fruitTargetCache.refreshedAt = 0
		setStatus(("Fruit collector: found %d cached target(s), failed to trigger"):format(totalCached))
	else
		setStatus(("Fruit collector: fast %d/%d, fallback %d, inventory +%d"):format(fired, #targets, fallback, gained))
	end
end

local function findSeedTool(seedName, shouldEquip)
	local character = getCharacter()
	local backpack = localPlayer:FindFirstChildOfClass("Backpack")
	local humanoid = getHumanoid()
	local targetSeed = seedName or CONFIG.selectedSeed
	if not targetSeed or targetSeed == "" then
		return nil
	end

	for _, container in ipairs({ character, backpack }) do
		if container then
			for _, item in ipairs(container:GetChildren()) do
				if item:IsA("Tool")
					and isInventorySeedTool
					and isInventorySeedTool(item)
					and string.find(string.lower(item.Name), string.lower(targetSeed), 1, true)
				then
					if shouldEquip and item.Parent ~= character and humanoid then
						humanoid:EquipTool(item)
					end
					return item
				end
			end
		end
	end

	return nil
end

local function getEquippedSeedTool(seedName)
	return findSeedTool(seedName, true)
end

local function getSeedToolAmount(tool)
	if not tool then
		return 1
	end

	for _, key in ipairs({ "Count", "Amount", "Quantity", "Stack", "Uses", "SeedCount" }) do
		local ok, attribute = pcall(function()
			return tool:GetAttribute(key)
		end)
		local amount = ok and tonumber(attribute) or nil
		if amount and amount > 0 then
			return math.floor(amount)
		end

		local child = tool:FindFirstChild(key)
		if child and child:IsA("ValueBase") then
			amount = tonumber(child.Value)
			if amount and amount > 0 then
				return math.floor(amount)
			end
		end
	end

	local stack = string.match(tool.Name, "[xX](%d+)")
		or string.match(tool.Name, "%((%d+)%)")
		or string.match(tool.Name, "%[(%d+)%]")
	local amount = tonumber(stack)
	if amount and amount > 0 then
		return math.floor(amount)
	end

	return 1
end

local function getSelectedSeedList()
	local selected = {}
	local seen = {}

	for _, seedName in ipairs(seedNames) do
		if selectedSeeds[seedName] then
			seen[seedName] = true
			table.insert(selected, seedName)
		end
	end

	for seedName, enabled in pairs(selectedSeeds) do
		if enabled and not seen[seedName] then
			addUniqueName(seedNames, seedName)
			seedPriority[seedName] = seedPriority[seedName] or getSeedMetadataValue(seedName)
			table.insert(selected, seedName)
		end
	end

	return getSortedSeedList(selected)
end

local function countPlacedSeed(seedName)
	local count = 0
	local needle = string.lower(seedName)

	for _, root in ipairs(getOwnGardenRoots()) do
		for _, descendant in ipairs(getCachedDescendants("seedCount" .. seedName, root, CONFIG.seedCountCacheRefreshInterval)) do
			if descendant:IsA("Model") and string.find(string.lower(descendant.Name), needle, 1, true) then
				count += 1
			end
		end
	end

	return count
end

local function canPlaceSeed(seedName)
	if selectedSeeds[seedName] then
		return true
	end

	local seedRarityValue = getSeedRarity(seedName)
	if seedRarityValue > 0 and seedRarityValue <= 3 and countPlacedSeed(seedName) >= CONFIG.lowRaritySeedLimit then
		stats.seedsSkippedLimit += 1
		return false, "limit"
	end

	return true
end

local function getSeedPlantPosition(index, center)
	local root = getRoot()
	if not root then
		return nil
	end

	local step = math.max(index or 1, 1)
	local angle = step * 2.399963229728653
	local radius = math.min(CONFIG.plantRadius, 2.75 + math.sqrt(step) * 2.15)
	local offset = Vector3.new(math.cos(angle), 0, math.sin(angle)) * radius
	local basePosition = center or root.Position
	local origin = basePosition + offset + Vector3.new(0, 12, 0)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { getCharacter() }

	local result = workspace:Raycast(origin, Vector3.new(0, -80, 0), params)
	if result then
		return result.Position
	end

	return basePosition + offset
end

local function tryPlantSeedRemote(seedName, position)
	local attempts = 0
	local cframe = CFrame.new(position)
	local packets = { "PlantSeed", "PlaceSeed", "Plant", "GrowPlant" }
	local unpackArgs = table.unpack or unpack

	for _, packetName in ipairs(packets) do
		for _, args in ipairs({
			{ seedName, position },
			{ position, seedName },
			{ seedName, cframe },
		}) do
			attempts += 1
			sendPacket(packetName, unpackArgs(args))
		end
	end

	return attempts
end

local function moveToOwnGarden()
	local root = getRoot()
	if not root then
		return nil, "character"
	end

	local anchor = getOwnGardenAnchor()
	if not anchor then
		return nil, "garden"
	end

	local gardenPosition = typeof(anchor) == "Vector3" and anchor or anchor.Position
	if (root.Position - gardenPosition).Magnitude > math.max(CONFIG.plantRadius, 18) then
		root.CFrame = CFrame.new(gardenPosition + Vector3.new(0, 4, 0))
		task.wait(0.15)
	end

	return gardenPosition, nil
end

isInventorySeedTool = function(item)
	if not item or not item:IsA("Tool") then
		return false
	end

	local name = string.lower(item.Name)
	for _, word in ipairs({ "kg", " lb", "fruit", "harvest", "picked", "mutation", "rainbow", "golden" }) do
		if string.find(name, word, 1, true) then
			return false
		end
	end

	if string.find(name, "seed", 1, true) then
		return true
	end

	for _, seedName in ipairs(seedNames) do
		if string.find(name, string.lower(seedName), 1, true) then
			return true
		end
	end

	return false
end

local function toolHasValue(item, keys)
	if not item then
		return false
	end

	for _, key in ipairs(keys) do
		local ok, attribute = pcall(function()
			return item:GetAttribute(key)
		end)
		if ok and attribute ~= nil and attribute ~= false and tostring(attribute) ~= "" then
			return true
		end

		local child = item:FindFirstChild(key)
		if child and child:IsA("ValueBase") and child.Value ~= nil and tostring(child.Value) ~= "" then
			return true
		end
	end

	return false
end

local function toolNameMatchesList(item, list)
	local name = string.lower(item and item.Name or "")
	if name == "" then
		return false
	end

	for _, knownName in ipairs(list) do
		local known = string.lower(tostring(knownName or ""))
		if known ~= "" and (name == known or string.find(name, known, 1, true)) then
			return true
		end
	end

	return false
end

local function isKnownGearTool(item)
	if not item or not item:IsA("Tool") then
		return false
	end

	if toolNameMatchesList(item, gearNames) then
		return true
	end

	local name = string.lower(item.Name)
	for _, word in ipairs({
		"watering can",
		"sprinkler",
		"trowel",
		"wheelbarrow",
		"teleporter",
		"gnome",
		"lantern",
		"flashbang",
		"shovel",
		"rake",
		"tool",
		"gear",
	}) do
		if string.find(name, word, 1, true) then
			return true
		end
	end

	return false
end

local function isKnownPetTool(item)
	if not item or not item:IsA("Tool") then
		return false
	end

	if item:GetAttribute("Pet") or item:GetAttribute("PetName") then
		return true
	end

	if toolNameMatchesList(item, petNames) or toolNameMatchesList(item, buyPetNames) then
		return true
	end

	local name = string.lower(item.Name)
	return string.find(name, "pet", 1, true) ~= nil
		or string.find(name, "egg", 1, true) ~= nil
end

local function isLikelyFruitTool(item)
	if not item
		or not item:IsA("Tool")
		or isInventorySeedTool(item)
		or isKnownGearTool(item)
		or isKnownPetTool(item)
	then
		return false
	end

	local name = string.lower(item.Name)
	local hasHarvestValue = toolHasValue(item, {
		"Weight",
		"WeightKg",
		"WeightKG",
		"KG",
		"Mass",
		"Mutation",
		"Mutations",
		"Fruit",
		"FruitName",
		"Harvested",
		"SellValue",
	})

	if hasHarvestValue
		or string.find(name, "kg", 1, true)
		or string.find(name, "lb", 1, true)
		or string.find(name, "fruit", 1, true)
		or string.find(name, "harvest", 1, true)
	then
		return true
	end

	for _, childName in ipairs({ "Weight", "Mutation", "Mutations", "Fruit", "FruitName", "Harvested" }) do
		if item:FindFirstChild(childName, true) then
			return true
		end
	end

	return false
end

local function getSellableFruitTools()
	local tools = {}
	local character = getCharacter()
	local backpack = localPlayer:FindFirstChildOfClass("Backpack")

	for _, container in ipairs({ character, backpack }) do
		if container then
			for _, item in ipairs(container:GetChildren()) do
				if isLikelyFruitTool(item) then
					table.insert(tools, item)
				end
			end
		end
	end

	table.sort(tools, function(left, right)
		local leftName = string.lower(left.Name)
		local rightName = string.lower(right.Name)
		local leftRare = (string.find(leftName, "rainbow", 1, true) and 3)
			or (string.find(leftName, "gold", 1, true) and 2)
			or (string.find(leftName, "golden", 1, true) and 2)
			or 1
		local rightRare = (string.find(rightName, "rainbow", 1, true) and 3)
			or (string.find(rightName, "gold", 1, true) and 2)
			or (string.find(rightName, "golden", 1, true) and 2)
			or 1

		if leftRare ~= rightRare then
			return leftRare > rightRare
		end

		return left.Name < right.Name
	end)

	return tools
end

local function getSelectedGearList()
	local selected = {}

	for _, gearName in ipairs(gearNames) do
		if selectedGears[gearName] then
			table.insert(selected, gearName)
		end
	end

	return selected
end

local function getSeedFrame(seedName)
	if cache.seedFrames[seedName] and cache.seedFrames[seedName].Parent then
		return cache.seedFrames[seedName]
	end

	local seedShop = getRuntimeSeedShopGui()
	if not seedShop then
		return nil
	end

	local frame = seedShop:FindFirstChild("Frame")
	if frame then
		local normalShop = frame:FindFirstChild("NormalShop")
		local direct = normalShop and normalShop:FindFirstChild(seedName)
		if direct then
			cache.seedFrames[seedName] = direct
			return direct
		end

		local scrollingFrame = frame:FindFirstChild("ScrollingFrame")
		direct = scrollingFrame and scrollingFrame:FindFirstChild(seedName)
		if direct then
			cache.seedFrames[seedName] = direct
			return direct
		end
	end

	for _, descendant in ipairs(seedShop:GetDescendants()) do
		if descendant.Name == seedName and descendant.Name ~= "ItemTemplate" then
			cache.seedFrames[seedName] = descendant
			return descendant
		end
	end

	return nil
end

local function getGearFrame(gearName)
	if cache.gearFrames[gearName] and cache.gearFrames[gearName].Parent then
		return cache.gearFrames[gearName]
	end

	local gearShop = playerGui:FindFirstChild("GearShop")
	if not gearShop then
		return nil
	end

	local frame = gearShop:FindFirstChild("Frame")
	local scrollingFrame = frame and frame:FindFirstChild("ScrollingFrame")
	local direct = scrollingFrame and scrollingFrame:FindFirstChild(gearName)
	if direct then
		cache.gearFrames[gearName] = direct
		return direct
	end

	for _, descendant in ipairs(gearShop:GetDescendants()) do
		if descendant.Name == gearName and descendant.Name ~= "ItemTemplate" then
			cache.gearFrames[gearName] = descendant
			return descendant
		end
	end

	return nil
end

local function getSelectedPetList()
	local selected = {}

	for _, petName in ipairs(petNames) do
		if selectedPets[petName] then
			table.insert(selected, petName)
		end
	end

	return selected
end

function touchPart(part, allowTeleportFallback)
	local root = getRoot()
	if not root or not part or not part:IsA("BasePart") then
		return false
	end

	if allowTeleportFallback == nil then
		allowTeleportFallback = true
	end

	if typeof(firetouchinterest) == "function" then
		pcall(firetouchinterest, root, part, 0)
		task.wait()
		pcall(firetouchinterest, root, part, 1)
		return true
	end

	if not allowTeleportFallback then
		return false
	end

	local oldCFrame = root.CFrame
	local ok = pcall(function()
		root.CFrame = part.CFrame + Vector3.new(0, 3, 0)
		task.wait(0.05)
		root.CFrame = oldCFrame
	end)

	return ok
end

teleportToPart = function(part, height)
	local root = getRoot()
	if not root or not part or not part:IsA("BasePart") then
		return false
	end

	local character = getCharacter()
	local targetCFrame = part.CFrame + Vector3.new(0, height or 3, 0)
	local ok = pcall(function()
		if character and character.PivotTo then
			character:PivotTo(targetCFrame)
		end
		root.CFrame = targetCFrame
		root.AssemblyLinearVelocity = Vector3.zero
		root.AssemblyAngularVelocity = Vector3.zero
	end)
	if ok then
		task.wait(0.15)
	end
	return ok
end

teleportToModelOrPart = function(model, part, height)
	if model and model:IsA("Model") then
		local pivotOk, pivot = pcall(function()
			return model:GetPivot()
		end)
		if pivotOk then
			local root = getRoot()
			local character = getCharacter()
			local targetCFrame = CFrame.new(pivot.Position + Vector3.new(0, height or 3, 0))
			local ok = pcall(function()
				if character and character.PivotTo then
					character:PivotTo(targetCFrame)
				end
				if root then
					root.CFrame = targetCFrame
					root.AssemblyLinearVelocity = Vector3.zero
					root.AssemblyAngularVelocity = Vector3.zero
				end
			end)
			if ok then
				task.wait(0.15)
				return true
			end
		end
	end

	return teleportToPart(part, height)
end

function getPromptPart(prompt)
	local current = prompt.Parent
	while current and current ~= workspace do
		if current:IsA("BasePart") then
			return current
		end
		current = current.Parent
	end
	return nil
end

local function triggerBuyPrompt(prompt)
	local part = getPromptPart(prompt)
	if part then
		teleportToPart(part, 3)
		task.wait(0.05)
	end

	return triggerPrompt(prompt, true)
end

local function purchaseSeedRemote(seedName)
	local variants = {
		seedName,
		string.gsub(seedName, "%s+", "_"),
		string.gsub(seedName, "%s+", ""),
	}
	local bought = 0

	for repeatIndex = 1, CONFIG.seedBuyRemoteRepeats do
		for _, variant in ipairs(variants) do
			if sendPacket("PurchaseSeed", variant) then
				bought += 1
			end

			if sendPacket("PurchaseSeed", variant, 1) then
				bought += 1
			end
		end

		task.wait()
	end

	return bought > 0, bought
end

function looksLikeGoldRainbowDrop(instance)
	local parts = {}
	local current = instance
	local checked = 0
	while current and current ~= workspace and checked < 4 do
		table.insert(parts, safeText(current.Name))
		current = current.Parent
		checked += 1
	end

	local text = string.lower(table.concat(parts, " "))
	local hasValuableWord = string.find(text, "rainbow", 1, true)
		or string.find(text, "gold", 1, true)
		or string.find(text, "golden", 1, true)
	local hasDropWord = string.find(text, "seed", 1, true)
		or string.find(text, "pack", 1, true)
		or string.find(text, "drop", 1, true)
		or string.find(text, "rain", 1, true)
		or string.find(text, "collect", 1, true)

	return hasValuableWord and hasDropWord
end

function autoCollectRainbowSeeds()
	if not isEnabled("autoCollectRainbowSeeds") then
		return
	end

	local inventoryFull = refreshInventoryStats()
	if inventoryFull then
		stats.collectSkippedFull += 1
		updateStatsUI()
		setStatus(("Gold/rainbow seeds: inventory full (%d/%d)"):format(stats.inventoryItems, stats.inventoryCapacity))
		return
	end

	local checked = 0
	local targets = {}
	local roots = { getMap(), getGardens() }
	watchDropRoots()

	for rootIndex, root in ipairs(roots) do
		if not isEnabled("autoCollectRainbowSeeds") then
			return
		end

		local scanned = 0
		for _, descendant in ipairs(getCachedDescendants("rainbow" .. rootIndex, root, CONFIG.dropCacheRefreshInterval)) do
			if not isEnabled("autoCollectRainbowSeeds") then
				return
			end

			if #targets >= CONFIG.maxDropCollectPerTick then
				break
			end
			scanned += 1
			if scanned >= CONFIG.maxDropScanPerRoot then
				break
			end

			if not looksLikeGoldRainbowDrop(descendant) then
				continue
			end

			local matchesRainbowSeed = treeTextMatches(descendant, {
				"rainbow",
				"gold",
				"golden",
				"seedrain",
				"seed rain",
				"gold seed",
				"seedpack",
				"seed pack",
			}, 3)

			if descendant:IsA("ProximityPrompt") and descendant.Name ~= "StealPrompt" and matchesRainbowSeed then
				table.insert(targets, descendant)
			elseif descendant:IsA("BasePart")
				and descendant.CanTouch
				and matchesRainbowSeed
				and treeTextMatches(descendant, { "seed", "pack", "drop", "collect", "pickup", "rain" }, 3)
			then
				table.insert(targets, descendant)
			end
		end

		if #targets >= CONFIG.maxDropCollectPerTick then
			break
		end
	end

	local root = getRoot()
	local rootPosition = root and root.Position
	table.sort(targets, function(left, right)
		local leftPart = left:IsA("ProximityPrompt") and getPromptPart(left) or left
		local rightPart = right:IsA("ProximityPrompt") and getPromptPart(right) or right
		local leftDistance = rootPosition and leftPart and (rootPosition - leftPart.Position).Magnitude or math.huge
		local rightDistance = rootPosition and rightPart and (rootPosition - rightPart.Position).Magnitude or math.huge
		return leftDistance < rightDistance
	end)

	for _, target in ipairs(targets) do
		if not isEnabled("autoCollectRainbowSeeds") then
			return
		end

		if checked >= CONFIG.maxDropCollectPerTick then
			break
		end

		local part = target:IsA("ProximityPrompt") and getPromptPart(target) or target
		local model = target:IsA("ProximityPrompt") and target:FindFirstAncestorWhichIsA("Model") or nil
		local moved = part and (model and teleportToModelOrPart(model, part, 3) or teleportToPart(part, 3))
		if moved then
			if target:IsA("ProximityPrompt") then
				if triggerPrompt(target, true) then
					checked += 1
				end
			elseif touchPart(target) then
				checked += 1
			end
			task.wait(0.05)
		end
	end

	refreshInventoryStats()
	updateStatsUI()
	setStatus(("Gold/rainbow drops: collected %d/%d target(s)"):format(checked, #targets))
end

local performanceOptimized = setmetatable({}, { __mode = "k" })
local performanceHidden = setmetatable({}, { __mode = "k" })
local performanceWatcherConnected = false

function getGardenPlotForInstance(instance)
	local gardens = getGardens()
	local current = instance
	while gardens and current and current ~= workspace do
		if current.Parent == gardens then
			return current
		end
		current = current.Parent
	end
	return nil
end

function gardenPlotIsOwn(plot)
	if not plot then
		return false
	end

	if plotBelongsToLocalPlayer(plot) then
		return true
	end

	local plants = plot:FindFirstChild("Plants")
	local userId = tostring(localPlayer.UserId)
	if plants then
		for _, plant in ipairs(plants:GetChildren()) do
			if string.sub(plant.Name, 1, #userId + 1) == userId .. "_" then
				return true
			end
		end
	end

	return false
end

function isOwnPlantVisual(instance, plot)
	local current = instance
	while current and current ~= plot and current ~= workspace do
		local parent = current.Parent
		local parentName = parent and string.lower(parent.Name) or ""
		if parentName == "plants"
			or parentName == "fruits"
			or parentName == "fruit"
			or parentName == "crops"
			or parentName == "harvest"
			or parentName == "harvests"
		then
			return true
		end
		current = parent
	end
	return false
end

function hidePerformanceVisual(instance, hidePrompts)
	if not instance or performanceHidden[instance] then
		return 0
	end

	local changed = 0
	if instance:IsA("BasePart") then
		performanceHidden[instance] = true
		pcall(function()
			instance.LocalTransparencyModifier = 1
			instance.CastShadow = false
		end)
		changed = 1
	elseif instance:IsA("Decal") or instance:IsA("Texture") then
		performanceHidden[instance] = true
		pcall(function()
			instance.Transparency = 1
		end)
		changed = 1
	elseif instance:IsA("ParticleEmitter")
		or instance:IsA("Trail")
		or instance:IsA("Beam")
		or instance:IsA("Smoke")
		or instance:IsA("Fire")
		or instance:IsA("Sparkles")
		or instance:IsA("PointLight")
		or instance:IsA("SpotLight")
		or instance:IsA("SurfaceLight")
	then
		performanceHidden[instance] = true
		pcall(function()
			instance.Enabled = false
		end)
		changed = 1
	elseif instance:IsA("BillboardGui")
		or instance:IsA("SurfaceGui")
		or instance:IsA("Highlight")
	then
		performanceHidden[instance] = true
		pcall(function()
			instance.Enabled = false
		end)
		changed = 1
	elseif hidePrompts and instance:IsA("ProximityPrompt") then
		performanceHidden[instance] = true
		pcall(function()
			instance.Enabled = false
		end)
		changed = 1
	end

	return changed
end

function applyPerformanceGardenHiding(instance)
	local plot = getGardenPlotForInstance(instance)
	if not plot then
		return 0
	end

	if gardenPlotIsOwn(plot) then
		if isOwnPlantVisual(instance, plot) then
			return hidePerformanceVisual(instance, false)
		end
		return 0
	end

	return hidePerformanceVisual(instance, true)
end

function optimizePerformanceInstance(instance)
	if not instance then
		return 0
	end

	local changed = 0
	if state.performanceMode or state.hidePlants then
		changed = applyPerformanceGardenHiding(instance)
	end
	if not state.performanceMode then
		return changed
	end

	if performanceOptimized[instance] then
		return changed
	end

	if instance:IsA("BasePart") then
		performanceOptimized[instance] = true
		pcall(function()
			instance.Material = Enum.Material.SmoothPlastic
			instance.Reflectance = 0
			instance.CastShadow = false
			if instance:IsA("MeshPart") then
				instance.RenderFidelity = Enum.RenderFidelity.Performance
			end
		end)
		changed = 1
	elseif instance:IsA("Decal") or instance:IsA("Texture") then
		performanceOptimized[instance] = true
		pcall(function()
			instance.Transparency = 1
		end)
		changed = 1
	elseif instance:IsA("ParticleEmitter")
		or instance:IsA("Trail")
		or instance:IsA("Beam")
		or instance:IsA("Smoke")
		or instance:IsA("Fire")
		or instance:IsA("Sparkles")
	then
		performanceOptimized[instance] = true
		pcall(function()
			instance.Enabled = false
		end)
		changed = 1
	elseif instance:IsA("PointLight")
		or instance:IsA("SpotLight")
		or instance:IsA("SurfaceLight")
	then
		performanceOptimized[instance] = true
		pcall(function()
			instance.Enabled = false
		end)
		changed = 1
	end

	return changed
end

function optimizePerformanceTree(root, budget)
	local changed = 0
	local processed = 0
	for _, descendant in ipairs(root:GetDescendants()) do
		changed += optimizePerformanceInstance(descendant)
		processed += 1
		if budget and processed % budget == 0 then
			task.wait()
		end
	end
	return changed
end

function connectPerformanceWatcher()
	if performanceWatcherConnected then
		return
	end

	performanceWatcherConnected = true
	workspace.DescendantAdded:Connect(function(descendant)
		if state.performanceMode or state.hidePlants then
			optimizePerformanceInstance(descendant)
		end
	end)
end

enableHidePlants = function()
	connectPerformanceWatcher()
	local changed = 0
	local gardens = getGardens()
	if gardens then
		changed += optimizePerformanceTree(gardens, 250)
	end
	setStatus(("Hide plants: hidden %d garden object(s)"):format(changed))
end

enablePerformanceMode = function()
	local changed = 0

	connectPerformanceWatcher()

	pcall(function()
		settings().Rendering.QualityLevel = Enum.QualityLevel.Level01
	end)

	pcall(function()
		workspace.Terrain.WaterWaveSize = 0
		workspace.Terrain.WaterWaveSpeed = 0
		workspace.Terrain.WaterReflectance = 0
		workspace.Terrain.WaterTransparency = 1
		workspace.Terrain.Decoration = false
	end)

	changed += optimizePerformanceTree(workspace, 300)

	setStatus(("Performance mode: simplified %d object(s)"):format(changed))
end

function schedulePerformanceModeRestore()
	if not state.performanceMode and not state.hidePlants then
		return
	end

	task.spawn(function()
		for _, delaySeconds in ipairs({ 0, 1.5, 4, 8 }) do
			if delaySeconds > 0 then
				task.wait(delaySeconds)
			end
			if state.performanceMode then
				enablePerformanceMode()
			elseif state.hidePlants then
				enableHidePlants()
			end
		end
	end)
end

function plantSeed()
	if not isEnabled("seedPlacer") then
		return
	end

	local root = getRoot()
	if not root then
		setStatus("Seed placer: character root missing")
		return
	end

	local planted = 0
	local attempts = 0
	local missing = 0
	local readySeeds = {}
	local selectedList = getSelectedSeedList()

	for _, seedName in ipairs(selectedList) do
		if not isEnabled("seedPlacer") then
			return
		end

		local canPlace, reason = canPlaceSeed(seedName)
		if not canPlace then
			missing += 1
			continue
		end

		if findSeedTool(seedName, false) then
			table.insert(readySeeds, seedName)
		else
			missing += 1
		end
	end

	if #readySeeds == 0 then
		setStatus(("Seed placer: no selected seeds ready (%d skipped)"):format(missing))
		return
	end

	if not isEnabled("seedPlacer") then
		return
	end

	local gardenPosition, moveReason = moveToOwnGarden()
	if not gardenPosition then
		setStatus(moveReason == "garden" and "Seed placer: own garden not found" or "Seed placer: character root missing")
		return
	end

	local placementIndex = 0
	for _, seedName in ipairs(readySeeds) do
		if not isEnabled("seedPlacer") then
			return
		end

		if planted >= CONFIG.maxSeedPlantPerTick then
			break
		end

		local tool = getEquippedSeedTool(seedName)
		if tool and tool.Parent then
			local amount = math.min(getSeedToolAmount(tool), CONFIG.maxSeedPlacementsPerTool, CONFIG.maxSeedPlantPerTick - planted)
			for _ = 1, amount do
				if not isEnabled("seedPlacer") then
					return
				end

				if not tool.Parent then
					break
				end

				placementIndex += 1
				local position = getSeedPlantPosition(placementIndex, gardenPosition)
				if position then
					attempts += tryPlantSeedRemote(seedName, position)
				end

				pcall(function()
					tool:Activate()
				end)

				planted += 1
				if planted >= CONFIG.maxSeedPlantPerTick then
					break
				end
				task.wait()
			end

			pcall(function()
				tool:Activate()
			end)
		else
			missing += 1
		end
	end

	stats.seedsPlanted += planted
	stats.seedAttempts += attempts
	refreshInventoryStats()
	updateStatsUI()

	if planted > 0 then
		setStatus(("Seed placer: placed %d seed(s) in garden, %d remote try(s)"):format(planted, attempts))
	else
		setStatus(("Seed placer: no selected seed tool found (%d missing)"):format(missing))
	end
end

function getSelectedShovelSeedList()
	local selected = {}
	local seen = {}

	for _, seedName in ipairs(seedNames) do
		if selectedShovelSeeds[seedName] then
			seen[seedName] = true
			table.insert(selected, seedName)
		end
	end

	for seedName, enabled in pairs(selectedShovelSeeds) do
		if enabled and not seen[seedName] then
			addUniqueName(seedNames, seedName)
			seedPriority[seedName] = seedPriority[seedName] or getSeedMetadataValue(seedName)
			table.insert(selected, seedName)
		end
	end

	return getSortedSeedList(selected)
end

function getShovelTool()
	local character = getCharacter()
	local backpack = localPlayer:FindFirstChildOfClass("Backpack")
	local humanoid = getHumanoid()

	for _, container in ipairs({ character, backpack }) do
		if container then
			for _, item in ipairs(container:GetChildren()) do
				if item:IsA("Tool") and string.find(string.lower(item.Name), "shovel", 1, true) then
					if item.Parent ~= character and humanoid then
						humanoid:EquipTool(item)
					end
					return item
				end
			end
		end
	end

	return nil
end

function getPlantNameForShovel(instance)
	local current = instance
	local best = instance
	while current and current ~= workspace do
		local parent = current.Parent
		local parentName = parent and string.lower(parent.Name) or ""
		if (current:IsA("Model") or current:IsA("Folder") or current:IsA("BasePart"))
			and (parentName == "plants" or parentName == "crops" or parentName == "plant")
		then
			best = current
			break
		end
		current = parent
	end
	return best and best.Name or ""
end

function getPlantModelForShovel(instance)
	local current = instance
	while current and current ~= workspace do
		local parent = current.Parent
		local parentName = parent and string.lower(parent.Name) or ""
		if (current:IsA("Model") or current:IsA("Folder") or current:IsA("BasePart"))
			and (parentName == "plants" or parentName == "crops" or parentName == "plant")
		then
			return current
		end
		current = parent
	end
	return nil
end

function plantHasPromptText(plant, seedName)
	if not plant or not seedName then
		return false
	end

	local lowered = string.lower(seedName)
	local compactSeed = string.gsub(lowered, "[%s_%-]", "")
	for _, descendant in ipairs(plant:GetDescendants()) do
		if descendant:IsA("ProximityPrompt") and descendant.Name ~= "StealPrompt" then
			local text = string.lower((descendant.ObjectText or "") .. " " .. (descendant.ActionText or "") .. " " .. descendant.Name)
			local compactText = string.gsub(text, "[%s_%-]", "")
			if string.find(text, lowered, 1, true) or string.find(compactText, compactSeed, 1, true) then
				return true
			end
		end
	end

	return false
end

function getPlantShovelIdentifiers(plant, part)
	local identifiers = { plant, plant.Name }

	for _, attributeName in ipairs({
		"ID",
		"Id",
		"UUID",
		"Guid",
		"PlantId",
		"PlantID",
		"Seed",
		"SeedName",
	}) do
		local ok, value = pcall(function()
			return plant:GetAttribute(attributeName)
		end)
		if ok and value ~= nil then
			table.insert(identifiers, value)
		end
	end

	for _, child in ipairs(plant:GetChildren()) do
		if child:IsA("ValueBase") then
			local ok, value = pcall(function()
				return child.Value
			end)
			if ok and value ~= nil then
				table.insert(identifiers, value)
			end
		end
	end

	if part then
		table.insert(identifiers, part.Position)
	end

	return identifiers
end

function plantMatchesShovelSelection(plant, selected)
	local plantName = string.lower(getPlantNameForShovel(plant))
	local pathText = string.lower(getObjectPath(plant))
	local compactPlantName = string.gsub(plantName, "[%s_%-]", "")
	local compactPath = string.gsub(pathText, "[%s_%-]", "")
	if plantName == "" and pathText == "" then
		return false
	end

	for _, seedName in ipairs(selected) do
		local lowered = string.lower(seedName)
		local compactSeed = string.gsub(lowered, "[%s_%-]", "")
		if string.find(plantName, lowered, 1, true)
			or string.find(compactPlantName, compactSeed, 1, true)
			or string.find(pathText, lowered, 1, true)
			or string.find(compactPath, compactSeed, 1, true)
			or plantHasPromptText(plant, seedName)
			or treeTextMatches(plant, { seedName }, 3)
		then
			return true
		end
	end

	return false
end

function getShovelPrompt(target)
	if not target then
		return nil
	end

	if target:IsA("ProximityPrompt") then
		local text = string.lower((target.ActionText or "") .. " " .. (target.ObjectText or "") .. " " .. target.Name)
		if string.find(text, "shovel", 1, true)
			or string.find(text, "remove", 1, true)
			or string.find(text, "delete", 1, true)
			or string.find(text, "dig", 1, true)
		then
			return target
		end
	end

	for _, descendant in ipairs(target:GetDescendants()) do
		if descendant:IsA("ProximityPrompt") and descendant.Name ~= "StealPrompt" then
			local text = string.lower((descendant.ActionText or "") .. " " .. (descendant.ObjectText or "") .. " " .. descendant.Name)
			if string.find(text, "shovel", 1, true)
				or string.find(text, "remove", 1, true)
				or string.find(text, "delete", 1, true)
				or string.find(text, "dig", 1, true)
			then
				return descendant
			end
		end
	end

	return nil
end

function aimAndHoldPart(part, holdDuration, tool)
	if not part or not part:IsA("BasePart") then
		return false
	end

	local camera = workspace.CurrentCamera
	if not camera then
		return false
	end

	local root = getRoot()
	if root then
		pcall(function()
			root.CFrame = CFrame.lookAt(root.Position, Vector3.new(part.Position.X, root.Position.Y, part.Position.Z))
		end)
	end

	pcall(function()
		camera.CFrame = CFrame.lookAt(camera.CFrame.Position, part.Position)
	end)

	local viewportPoint, onScreen = camera:WorldToViewportPoint(part.Position)
	if virtualInputManager and onScreen then
		pcall(function()
			virtualInputManager:SendMouseMoveEvent(viewportPoint.X, viewportPoint.Y, game)
			virtualInputManager:SendMouseButtonEvent(viewportPoint.X, viewportPoint.Y, 0, true, game, 0)
			local startedAt = os.clock()
			while os.clock() - startedAt < (holdDuration or CONFIG.shovelHoldDuration) do
				if tool and tool.Parent then
					pcall(function()
						tool:Activate()
					end)
				end
				virtualInputManager:SendMouseMoveEvent(viewportPoint.X, viewportPoint.Y, game)
				task.wait(0.18)
			end
			virtualInputManager:SendMouseButtonEvent(viewportPoint.X, viewportPoint.Y, 0, false, game, 0)
		end)
		return true
	end

	return false
end

function shovelPlantTarget(plant)
	if not plant or not plant.Parent then
		return false
	end

	plant = getPlantModelForShovel(plant)
	if not plant or not plant.Parent then
		return false
	end

	local part = getTargetPart(plant)
	local root = getRoot()
	if part and root and (root.Position - part.Position).Magnitude > 18 then
		teleportToModelOrPart(plant:IsA("Model") and plant or nil, part, 3)
		task.wait(0.08)
	end

	local shovelTool = getShovelTool()
	local prompt = getShovelPrompt(plant)
	local fired = false
	local beforeParent = plant.Parent
	local plantName = plant.Name
	local plantPosition = part and part.Position
	local identifiers = getPlantShovelIdentifiers(plant, part)

	if shovelTool then
		pcall(function()
			shovelTool:Activate()
		end)
		fired = true
	end

	if part then
		fired = aimAndHoldPart(part, CONFIG.shovelHoldDuration, shovelTool) or fired
	end

	for _, packetName in ipairs({
		"SwingShovel",
		"UseShovel",
	}) do
		fired = sendPacket(packetName) or fired
		fired = sendPacket(packetName, plant) or fired
		fired = sendPacket(packetName, plantName) or fired
		if plantPosition then
			fired = sendPacket(packetName, plantPosition) or fired
			fired = sendPacket(packetName, plant, plantPosition) or fired
			fired = sendPacket(packetName, plantName, plantPosition) or fired
		end
		for _, identifier in ipairs(identifiers) do
			fired = sendPacket(packetName, identifier) or fired
			if plantPosition and identifier ~= plantPosition then
				fired = sendPacket(packetName, identifier, plantPosition) or fired
				fired = sendPacket(packetName, plantPosition, identifier) or fired
			end
		end
	end

	if prompt then
		fired = triggerPromptFast(prompt) or fired
	end

	if shovelTool then
		pcall(function()
			shovelTool:Activate()
		end)
		fired = true
	end

	if part then
		fired = aimAndHoldPart(part, 0.35, shovelTool) or fired
	end

	task.wait(0.12)
	return fired or not plant.Parent or plant.Parent ~= beforeParent or not plant:IsDescendantOf(workspace)
end

function autoShovel()
	if not isEnabled("autoShovel") then
		return
	end

	local selected = getSelectedShovelSeedList()
	if #selected == 0 then
		setStatus("Auto shovel: no seeds selected")
		return
	end

	local roots = getOwnGardenRoots()
	if #roots == 0 then
		setStatus("Auto shovel: own garden not found")
		return
	end

	local targets = {}
	local seen = {}
	for index, root in ipairs(roots) do
		for _, descendant in ipairs(getCachedDescendants("shovelPlants" .. index, root, CONFIG.cacheRefreshInterval)) do
			if #targets >= CONFIG.maxShovelPerTick then
				break
			end

			if descendant.Parent
				and descendant:IsDescendantOf(workspace)
			then
				local plant = getPlantModelForShovel(descendant)
				if plant
					and plant.Parent
					and plant:IsDescendantOf(workspace)
					and not seen[plant]
					and plantMatchesShovelSelection(plant, selected)
				then
					seen[plant] = true
					table.insert(targets, plant)
				end
			end
		end

		if #targets >= CONFIG.maxShovelPerTick then
			break
		end
	end

	if #targets == 0 then
		setStatus(("Auto shovel: no matching planted seeds found (%d selected)"):format(#selected))
		return
	end

	local actions = 0
	for _, plant in ipairs(targets) do
		if not isEnabled("autoShovel") then
			return
		end

		if shovelPlantTarget(plant) then
			actions += 1
			task.wait(0.05)
		end
	end

	stats.seedsShoveled += actions
	updateStatsUI()
	setStatus(("Auto shovel: tried %d/%d matching plant(s)"):format(actions, #targets))
end

function autoSell(force)
	if not force and not isEnabled("autoSell") then
		return
	end

	local sellableTools = getSellableFruitTools()
	if #sellableTools == 0 then
		setStatus("Sell: nothing to sell")
		return
	end

	local actions = 0
	local stand = getPath(workspace, "Map.Stands.Sell.Part")
	if not force and not isEnabled("autoSell") then
		return
	end

	if stand and stand:IsA("BasePart") and touchPart(stand) then
		actions += 1
		task.wait(0.15)
	end

	local stevenPrompt = getPath(workspace, "NPCS.Steven.HumanoidRootPart.ProximityPrompt")
	if stevenPrompt and stevenPrompt:IsA("ProximityPrompt") and triggerBuyPrompt(stevenPrompt) then
		actions += 1
		task.wait(0.15)
	end

	for _, packetName in ipairs({ "SellAll", "SellInventory", "PreviewSellAll" }) do
		if not force and not isEnabled("autoSell") then
			return
		end

		if sendPacket(packetName) then
			actions += 1
			task.wait(0.05)
		end
	end

	for _, tool in ipairs(sellableTools) do
		if not force and not isEnabled("autoSell") then
			return
		end

		if sendPacket("SellItem", tool) then
			actions += 1
			task.wait(0.03)
		end

		if sendPacket("SellFruit", tool) then
			actions += 1
			task.wait(0.03)
		end

		if sendPacket("SellItem", tool.Name) then
			actions += 1
			task.wait(0.03)
		end
	end

	for _, descendant in ipairs(playerGui:GetDescendants()) do
		if not force and not isEnabled("autoSell") then
			return
		end

		if descendant:IsA("GuiButton")
			and descendant.Visible
			and textMatches(descendant, { "sell all", "sell inventory", "sell" })
		then
			if activateButton(descendant) then
				actions += 1
				task.wait(0.05)
			end
		end
	end

	setStatus(("Sell: %d action(s) for %d item(s)"):format(actions, #sellableTools))
end

function buyOneSeed(seedName)
	local remoteOk, remoteCount = purchaseSeedRemote(seedName)
	if remoteOk then
		return true, "Seed: " .. seedName, remoteCount or 1
	end

	local seedFrame = getSeedFrame(seedName)

	local clicked = false
	if seedFrame then
		local mainFrame = seedFrame:FindFirstChild("Main_Frame", true)
		local rowButton = mainFrame and mainFrame:FindFirstChild("TextButton")
		if rowButton and rowButton:IsA("GuiButton") and activateButton(rowButton) then
			clicked = true
			task.wait()
		end

		for _, buttonName in ipairs({ "Sheckles_Buy", "CashBuy", "Buy", "TextButton" }) do
			local button = seedFrame:FindFirstChild(buttonName, true)
			if button and button:IsA("GuiButton") and activateButton(button) then
				clicked = true
				task.wait()
				break
			end
		end

		if not clicked then
			for _, descendant in ipairs(seedFrame:GetDescendants()) do
				if descendant:IsA("GuiButton") and descendant ~= rowButton and activateButton(descendant) then
					clicked = true
					task.wait()
					break
				end
			end
		end
	end

	if clicked then
		return true, "Seed: fallback " .. seedName, 1
	else
		return false, "Seed: failed " .. seedName, 0
	end
end

function buySeed()
	if not isEnabled("autoBuySeeds") then
		return
	end

	if not state.seedShopEnabled then
		setStatus("Auto buy: seed shop disabled")
		return
	end

	local bought = 0
	local attempts = 0
	local lastMessage = "Auto buy: no seeds selected"

	for _, seedName in ipairs(getSelectedSeedList()) do
		if not isEnabled("autoBuySeeds") then
			return
		end

		if attempts >= CONFIG.maxSeedBuyPerTick then
			break
		end

		local ok, message, count = buyOneSeed(seedName)
		lastMessage = message
		if ok then
			bought += math.max(count or 1, 1)
		end
		attempts += 1
		task.wait()
	end

	if bought > 0 then
		stats.seedsBought += bought
		refreshInventoryStats()
		updateStatsUI()
		setStatus(("Auto buy: sent %d buy action(s) across %d seed(s)"):format(bought, attempts))
	else
		setStatus(lastMessage)
	end
end

function buyOneGear(gearName)
	if sendPacket("PurchaseGear", gearName) or sendPacket("PurchaseGear", gearName, 1) then
		return true, "Gear: " .. gearName
	end

	local gearFrame = getGearFrame(gearName)

	local clicked = false
	if gearFrame then
		local mainFrame = gearFrame:FindFirstChild("Main_Frame", true)
		local rowButton = mainFrame and mainFrame:FindFirstChild("TextButton")
		if rowButton and rowButton:IsA("GuiButton") and activateButton(rowButton) then
			clicked = true
			task.wait(0.08)
		end

		for _, buttonName in ipairs({ "Sheckles_Buy", "CashBuy", "Buy", "TextButton" }) do
			local button = gearFrame:FindFirstChild(buttonName, true)
			if button and button:IsA("GuiButton") and activateButton(button) then
				clicked = true
				task.wait(0.04)
			end
		end

		for _, descendant in ipairs(gearFrame:GetDescendants()) do
			if descendant:IsA("GuiButton") and descendant ~= rowButton and activateButton(descendant) then
				clicked = true
				task.wait(0.04)
			end
		end
	end

	if clicked then
		return true, "Gear: fallback " .. gearName
	else
		return false, "Gear: failed " .. gearName
	end
end

function buyGear()
	if not isEnabled("autoBuyGear") then
		return
	end

	if not state.gearShopEnabled then
		setStatus("Auto gear: gear shop disabled")
		return
	end

	local bought = 0
	local lastMessage = "Auto gear: no gear selected"

	for _, gearName in ipairs(getSelectedGearList()) do
		if not isEnabled("autoBuyGear") then
			return
		end

		local ok, message = buyOneGear(gearName)
		lastMessage = message
		if ok then
			bought += 1
			task.wait(0.12)
		end
	end

	if bought > 0 then
		stats.gearBought += bought
		refreshInventoryStats()
		updateStatsUI()
		setStatus(("Auto gear: tried %d selected item(s)"):format(bought))
	else
		setStatus(lastMessage)
	end
end

function buyOnePet(petName)
	if not isEnabled("autoBuyPets") then
		return false, "Auto pets: disabled"
	end

	local wildPetSpawns = getWildPetSpawns()
	local petTerm = string.lower(string.gsub(petName, "%s+", ""))

	for _, descendant in ipairs(getCachedDescendants("wildPets", wildPetSpawns)) do
		if not isEnabled("autoBuyPets") then
			return false, "Auto pets: disabled"
		end

		if descendant:IsA("ProximityPrompt") then
			local model = descendant:FindFirstAncestorWhichIsA("Model")
			local modelName = model and string.lower(string.gsub(model.Name, "%s+", "")) or ""
			local isBuyPrompt = descendant.Name == "BuyPrompt" or textMatches(descendant, { "buy", "purchase", "adopt" })
			local isPetPrompt = string.find(modelName, petTerm, 1, true) ~= nil or textMatches(descendant, { petName })

			if isBuyPrompt and isPetPrompt then
				local part = getPromptPart(descendant)
				if part then
					teleportToModelOrPart(model, part, 3)
				end

				local root = getRoot()
				local inRange = not root or not part or (root.Position - part.Position).Magnitude <= ((descendant.MaxActivationDistance or 10) + 4)
				if inRange and triggerPrompt(descendant, true) then
					return true, ("Auto pets: moved in range and bought %s"):format(petName)
				end
			end
		end
	end

	return false, ("Auto pets: no matching prompt for %s"):format(petName)
end

function buyPets()
	if not isEnabled("autoBuyPets") then
		return
	end

	local bought = 0
	local lastMessage = "Auto pets: no pets selected"

	for _, petName in ipairs(getSelectedPetList()) do
		if not isEnabled("autoBuyPets") then
			return
		end

		local ok, message = buyOnePet(petName)
		lastMessage = message
		if ok then
			bought += 1
			task.wait(0.12)
		end
	end

	if bought > 0 then
		stats.petsBought += bought
		refreshInventoryStats()
		updateStatsUI()
		setStatus(("Auto pets: tried %d selected pet(s)"):format(bought))
	else
		setStatus(lastMessage)
	end
end

function getPetsFolder()
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	return assets and assets:FindFirstChild("Pets")
end

function compactName(value)
	return string.lower(string.gsub(tostring(value or ""), "[%s_%-]", ""))
end

function getPetModulesFolder()
	local sharedModules = ReplicatedStorage:FindFirstChild("SharedModules")
	return sharedModules and sharedModules:FindFirstChild("PetModules")
end

function hasKnownPetBase(baseName)
	local wanted = compactName(baseName)
	if wanted == "" then
		return false
	end

	for _, petName in ipairs(petNames) do
		if compactName(petName) == wanted then
			return true
		end
	end

	local petsFolder = getPetsFolder()
	if petsFolder then
		for _, pet in ipairs(petsFolder:GetChildren()) do
			if compactName(stripVariantWords(pet.Name)) == wanted then
				return true
			end
		end
	end

	local petModules = getPetModulesFolder()
	if petModules then
		for _, module in ipairs(petModules:GetChildren()) do
			if compactName(module.Name) == wanted then
				return true
			end
		end
	end

	return false
end

function refreshPetNamesFromGearImages()
	local gearImages = getGearImagesFolder()
	if not gearImages then
		return
	end

	for _, imageValue in ipairs(gearImages:GetChildren()) do
		if imageValue:IsA("StringValue") then
			local baseName = stripVariantWords(imageValue.Name)
			if hasKnownPetBase(baseName) then
				addUniqueName(petNames, baseName)
			end
		end
	end

	table.sort(petNames)
end

refreshPetNamesFromGearImages()
function make(className, properties, parent)
	local instance = Instance.new(className)
	for key, value in pairs(properties or {}) do
		instance[key] = value
	end
	instance.Parent = parent
	return instance
end

function matchesSelectorFilter(name, query)
	query = string.lower(tostring(query or ""))
	if query == "" then
		return true
	end

	local haystack = string.lower(tostring(name or ""))
	local compactHaystack = string.gsub(haystack, "[%s_%-']", "")
	local compactQuery = string.gsub(query, "[%s_%-']", "")
	return string.find(haystack, query, 1, true) ~= nil
		or string.find(compactHaystack, compactQuery, 1, true) ~= nil
end

function makeSelectorSearch(parent, order, placeholder, onChanged)
	local box = make("TextBox", {
		Name = string.gsub(placeholder, "%s+", "") .. "Search",
		BackgroundColor3 = Color3.fromRGB(18, 23, 24),
		BorderSizePixel = 0,
		ClearTextOnFocus = false,
		Font = Enum.Font.Gotham,
		PlaceholderText = placeholder,
		Text = "",
		TextColor3 = Color3.fromRGB(242, 247, 239),
		TextSize = 11,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Size = UDim2.new(1, 0, 0, 24),
		LayoutOrder = order,
	}, parent)
	make("UICorner", { CornerRadius = UDim.new(0, 6) }, box)
	make("UIPadding", {
		PaddingLeft = UDim.new(0, 9),
		PaddingRight = UDim.new(0, 9),
	}, box)

	box:GetPropertyChangedSignal("Text"):Connect(function()
		onChanged(box.Text)
	end)

	return box
end

function refreshSelectorFilter(buttons, names, query, row, columns)
	local visible = 0
	for _, name in ipairs(names) do
		local button = buttons[name]
		if button then
			local show = matchesSelectorFilter(name, query)
			button.Visible = show
			if show then
				visible += 1
			end
		end
	end

	row.CanvasSize = UDim2.fromOffset(0, math.max(1, math.ceil(visible / (columns or 2))) * 28)
end

function buildUI()
local existing = playerGui:FindFirstChild("GardenAutomationGui")
if existing then
	existing:Destroy()
end

statusValue = Instance.new("StringValue")
statusValue.Name = "StatusValue"
statusValue.Value = state.lastStatus

local gui = make("ScreenGui", {
	Name = "GardenAutomationGui",
	ResetOnSpawn = false,
	IgnoreGuiInset = false,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
}, playerGui)
statusValue.Parent = gui

local panel = make("Frame", {
	Name = "Panel",
	AnchorPoint = Vector2.new(0, 0.5),
	BackgroundColor3 = Color3.fromRGB(22, 28, 30),
	BorderSizePixel = 0,
	Position = UDim2.fromOffset(24, 280),
	Size = UDim2.fromOffset(304, 500),
}, gui)
make("UICorner", { CornerRadius = UDim.new(0, 8) }, panel)
make("UIStroke", { Color = Color3.fromRGB(81, 113, 91), Thickness = 1 }, panel)

local header = make("TextButton", {
	Name = "Header",
	AutoButtonColor = false,
	BackgroundColor3 = Color3.fromRGB(41, 74, 52),
	BorderSizePixel = 0,
	Font = Enum.Font.GothamBold,
	Text = "Garden Tools",
	TextColor3 = Color3.fromRGB(246, 255, 242),
	TextSize = 16,
	Size = UDim2.new(1, 0, 0, 38),
}, panel)
make("UICorner", { CornerRadius = UDim.new(0, 8) }, header)

local content = make("ScrollingFrame", {
	Name = "Content",
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	CanvasSize = UDim2.fromOffset(0, 0),
	Position = UDim2.fromOffset(10, 48),
	ScrollBarThickness = 4,
	Size = UDim2.new(1, -20, 1, -58),
}, panel)
local contentLayout = make("UIListLayout", {
	Padding = UDim.new(0, 6),
	SortOrder = Enum.SortOrder.LayoutOrder,
}, content)

contentLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
	content.CanvasSize = UDim2.fromOffset(0, contentLayout.AbsoluteContentSize.Y + 8)
end)

local statusLabel = make("TextLabel", {
	Name = "Status",
	BackgroundColor3 = Color3.fromRGB(14, 18, 19),
	BorderSizePixel = 0,
	Font = Enum.Font.Gotham,
	Text = state.lastStatus,
	TextColor3 = Color3.fromRGB(201, 219, 202),
	TextSize = 12,
	TextWrapped = true,
	TextXAlignment = Enum.TextXAlignment.Left,
	Size = UDim2.new(1, 0, 0, 34),
	LayoutOrder = 99,
}, content)
make("UICorner", { CornerRadius = UDim.new(0, 6) }, statusLabel)
make("UIPadding", {
	PaddingLeft = UDim.new(0, 10),
	PaddingRight = UDim.new(0, 10),
}, statusLabel)

statusValue.Changed:Connect(function(value)
	statusLabel.Text = value
end)

local function makeToggle(label, key, order)
	local enabled = state[key] == true
	local button = make("TextButton", {
		Name = key,
		AutoButtonColor = false,
		BackgroundColor3 = enabled and Color3.fromRGB(58, 111, 67) or Color3.fromRGB(34, 41, 42),
		BorderSizePixel = 0,
		Font = Enum.Font.GothamSemibold,
		Text = ("%s: %s"):format(label, enabled and "ON" or "OFF"),
		TextColor3 = Color3.fromRGB(235, 244, 233),
		TextSize = 12,
		TextWrapped = true,
		Size = UDim2.new(1, 0, 0, 30),
		LayoutOrder = order,
	}, content)
	make("UICorner", { CornerRadius = UDim.new(0, 6) }, button)

	button.Activated:Connect(function()
		state[key] = not state[key]
		if not state[key] then
			running[key] = false
		end
		button.Text = ("%s: %s"):format(label, state[key] and "ON" or "OFF")
		button.BackgroundColor3 = state[key] and Color3.fromRGB(58, 111, 67) or Color3.fromRGB(34, 41, 42)
		saveConfig()
		setStatus(("%s %s"):format(label, state[key] and "enabled" or "disabled"))

		if key == "performanceMode" and state[key] then
			task.spawn(enablePerformanceMode)
		elseif key == "hidePlants" and state[key] then
			task.spawn(enableHidePlants)
		end
	end)
end

local function makeSectionLabel(text, order)
	return make("TextLabel", {
		Name = string.gsub(text, "%s+", "") .. "Section",
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamSemibold,
		Text = text,
		TextColor3 = Color3.fromRGB(174, 211, 178),
		TextSize = 11,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, 0, 0, 13),
		LayoutOrder = order,
	}, content)
end

makeSectionLabel("Priority", 1)
makeToggle("Auto Buy Pets", "autoBuyPets", 2)
makeToggle("Collect Gold/Rainbow Drops", "autoCollectRainbowSeeds", 3)
makeSectionLabel("Farm", 4)
makeToggle("Fruit Collector", "fruitCollector", 5)
makeToggle("Teleport To Fruit", "collectTeleport", 6)
makeToggle("Seed Placer", "seedPlacer", 7)
makeToggle("Auto Shovel Plants", "autoShovel", 8)
makeToggle("Auto Sell Inventory", "autoSell", 9)
makeToggle("Sell When Backpack Full", "sellWhenFull", 10)
makeSectionLabel("Shops", 10)
makeToggle("Auto Buy Seeds", "autoBuySeeds", 11)
makeToggle("Use Seed Shop", "seedShopEnabled", 12)
makeToggle("Auto Buy Gear", "autoBuyGear", 13)
makeToggle("Use Gear Shop", "gearShopEnabled", 14)
makeToggle("Performance Mode", "performanceMode", 15)
makeToggle("Hide Plants", "hidePlants", 16)

local webhookBox = make("TextBox", {
	Name = "WebhookUrl",
	BackgroundColor3 = Color3.fromRGB(34, 41, 42),
	BorderSizePixel = 0,
	ClearTextOnFocus = false,
	Font = Enum.Font.GothamSemibold,
	PlaceholderText = "Webhook URL for selected stock/pets",
	Text = CONFIG.webhookUrl,
	TextColor3 = Color3.fromRGB(242, 247, 239),
	TextSize = 12,
	TextTruncate = Enum.TextTruncate.AtEnd,
	Size = UDim2.new(1, 0, 0, 30),
	LayoutOrder = 17,
}, content)
make("UICorner", { CornerRadius = UDim.new(0, 6) }, webhookBox)
make("UIPadding", {
	PaddingLeft = UDim.new(0, 10),
	PaddingRight = UDim.new(0, 10),
}, webhookBox)
webhookBox.FocusLost:Connect(function()
	CONFIG.webhookUrl = tostring(webhookBox.Text or "")
	saveConfig()
	setStatus(CONFIG.webhookUrl ~= "" and "Webhook URL saved" or "Webhook URL cleared")
end)

local statsTitle = make("TextLabel", {
	Name = "StatsTitle",
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamSemibold,
	Text = "Stats",
	TextColor3 = Color3.fromRGB(221, 236, 216),
	TextSize = 13,
	TextXAlignment = Enum.TextXAlignment.Left,
	Size = UDim2.new(1, 0, 0, 15),
	LayoutOrder = 18,
}, content)

local statsFrame = make("Frame", {
	Name = "Stats",
	BackgroundColor3 = Color3.fromRGB(14, 18, 19),
	BorderSizePixel = 0,
	Size = UDim2.new(1, 0, 0, 128),
	LayoutOrder = 19,
}, content)
make("UICorner", { CornerRadius = UDim.new(0, 6) }, statsFrame)
make("UIPadding", {
	PaddingTop = UDim.new(0, 6),
	PaddingBottom = UDim.new(0, 6),
	PaddingLeft = UDim.new(0, 10),
	PaddingRight = UDim.new(0, 10),
}, statsFrame)
make("UIListLayout", {
	Padding = UDim.new(0, 2),
	SortOrder = Enum.SortOrder.LayoutOrder,
}, statsFrame)

local function makeStatsLabel(key, order)
	local label = make("TextLabel", {
		Name = key,
		BackgroundTransparency = 1,
		Font = Enum.Font.Gotham,
		Text = "",
		TextColor3 = Color3.fromRGB(201, 219, 202),
		TextSize = 11,
		TextTruncate = Enum.TextTruncate.AtEnd,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, 0, 0, 14),
		LayoutOrder = order,
	}, statsFrame)
	statsLabels[key] = label
	return label
end

makeStatsLabel("status", 1)
makeStatsLabel("systems", 2)
makeStatsLabel("inventory", 3)
makeStatsLabel("collect", 4)
makeStatsLabel("planting", 5)
makeStatsLabel("shops", 6)
makeStatsLabel("limits", 7)
refreshInventoryStats()
updateStatsUI()

local function buildSeedSelector()
local selectedSeedLabel = make("TextLabel", {
	Name = "SelectedSeedLabel",
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamSemibold,
	Text = "Seeds to buy",
	TextColor3 = Color3.fromRGB(221, 236, 216),
	TextSize = 13,
	TextXAlignment = Enum.TextXAlignment.Left,
	Size = UDim2.new(1, 0, 0, 15),
	LayoutOrder = 20,
}, content)

local seedRow = make("ScrollingFrame", {
	Name = "SeedSelector",
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	CanvasSize = UDim2.fromOffset(0, 0),
	ScrollBarThickness = 4,
	ScrollingDirection = Enum.ScrollingDirection.Y,
	Size = UDim2.new(1, 0, 0, 66),
	LayoutOrder = 22,
}, content)
make("UIGridLayout", {
	CellPadding = UDim2.fromOffset(6, 6),
	CellSize = UDim2.fromOffset(136, 24),
	SortOrder = Enum.SortOrder.LayoutOrder,
}, seedRow)

local seedLayout = seedRow:FindFirstChildOfClass("UIGridLayout")
local seedButtons = {}
local seedButtonCount = 0
local seedFilterText = ""

makeSelectorSearch(content, 21, "Search seeds to buy", function(text)
	seedFilterText = text
	refreshSelectorFilter(seedButtons, seedNames, seedFilterText, seedRow, 2)
end)

local function refreshSeedButton(seedName)
	local button = seedButtons[seedName]
	if not button then
		return
	end

	local enabled = selectedSeeds[seedName] == true
	button.Text = (enabled and "[x] " or "[ ] ") .. seedName
	button.BackgroundColor3 = enabled and Color3.fromRGB(58, 111, 67) or Color3.fromRGB(52, 60, 54)
end

local function refreshSeedCanvas()
	refreshSelectorFilter(seedButtons, seedNames, seedFilterText, seedRow, 2)
end

local function makeSeedButton(seedName)
	if seedButtons[seedName] then
		return
	end

	seedButtonCount += 1

	local button = make("TextButton", {
		Name = seedName,
		AutoButtonColor = false,
		BackgroundColor3 = Color3.fromRGB(52, 60, 54),
		BorderSizePixel = 0,
		Font = Enum.Font.GothamSemibold,
		Text = seedName,
		TextColor3 = Color3.fromRGB(242, 247, 239),
		TextSize = 12,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Size = UDim2.fromOffset(136, 24),
		LayoutOrder = seedButtonCount,
	}, seedRow)
	make("UICorner", { CornerRadius = UDim.new(0, 6) }, button)

	seedButtons[seedName] = button
	refreshSeedButton(seedName)
	button.Visible = matchesSelectorFilter(seedName, seedFilterText)

	button.Activated:Connect(function()
		selectedSeeds[seedName] = not selectedSeeds[seedName]
		CONFIG.selectedSeed = seedName
		refreshSeedButton(seedName)
		saveConfig()
		setStatus((selectedSeeds[seedName] and "Selected " or "Unselected ") .. seedName)
		if selectedSeeds[seedName] then
			notifyStock("Seed shop", seedName)
		end
	end)

	refreshSeedCanvas()
end

local function scanSeedShopNames()
	refreshSeedNamesFromStockValues()
	for _, seedName in ipairs(seedNames) do
		makeSeedButton(seedName)
	end

	local seedShop = getSeedShopGui()
	local frame = seedShop and seedShop:FindFirstChild("Frame")
	local normalShop = frame and frame:FindFirstChild("NormalShop")
	local scrollingFrame = frame and frame:FindFirstChild("ScrollingFrame")

	for _, container in ipairs({ normalShop, scrollingFrame }) do
		if container then
			for _, child in ipairs(container:GetChildren()) do
				if child.Name ~= "ItemTemplate" and not string.find(string.lower(child.Name), "shelf", 1, true) then
					if child:FindFirstChild("Main_Frame", true) or child:FindFirstChildWhichIsA("GuiButton", true) then
						addUniqueName(seedNames, child.Name)
						makeSeedButton(child.Name)
					end
				end
			end
		end
	end
end

for _, seedName in ipairs(seedNames) do
	makeSeedButton(seedName)
end

if seedLayout then
	seedLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(refreshSeedCanvas)
end
refreshSeedCanvas()
scanSeedShopNames()

local seedStockItems = getStockItemsFolder("SeedShop")
if seedStockItems then
	for _, item in ipairs(seedStockItems:GetChildren()) do
		addUniqueName(seedNames, item.Name)
		seedPriority[item.Name] = seedPriority[item.Name] or getSeedMetadataValue(item.Name)
		makeSeedButton(item.Name)
		watchStockItem("SeedShop", item)
		notifyStock("Seed shop", item.Name)
	end

	seedStockItems.ChildAdded:Connect(function(item)
		addUniqueName(seedNames, item.Name)
		seedPriority[item.Name] = getSeedMetadataValue(item.Name)
		table.sort(seedNames)
		makeSeedButton(item.Name)
		watchStockItem("SeedShop", item)
		notifyStock("Seed shop", item.Name)
	end)
end

playerGui.ChildAdded:Connect(function(child)
	if child.Name == "SeedShop" then
		task.wait(0.25)
		scanSeedShopNames()
	end
end)
StarterGui.ChildAdded:Connect(function(child)
	if child.Name == "SeedShop" then
		task.wait(0.25)
		scanSeedShopNames()
	end
end)
end
buildSeedSelector()

local function buildShovelSeedSelector()
local shovelSeedLabel = make("TextLabel", {
	Name = "ShovelSeedLabel",
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamSemibold,
	Text = "Seeds to shovel",
	TextColor3 = Color3.fromRGB(221, 236, 216),
	TextSize = 13,
	TextXAlignment = Enum.TextXAlignment.Left,
	Size = UDim2.new(1, 0, 0, 15),
	LayoutOrder = 23,
}, content)

local shovelSeedRow = make("ScrollingFrame", {
	Name = "ShovelSeedSelector",
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	CanvasSize = UDim2.fromOffset(0, 0),
	ScrollBarThickness = 4,
	ScrollingDirection = Enum.ScrollingDirection.Y,
	Size = UDim2.new(1, 0, 0, 66),
	LayoutOrder = 25,
}, content)
make("UIGridLayout", {
	CellPadding = UDim2.fromOffset(6, 6),
	CellSize = UDim2.fromOffset(136, 24),
	SortOrder = Enum.SortOrder.LayoutOrder,
}, shovelSeedRow)

local shovelSeedLayout = shovelSeedRow:FindFirstChildOfClass("UIGridLayout")
local shovelSeedButtons = {}
local shovelSeedButtonCount = 0
local shovelSeedFilterText = ""

makeSelectorSearch(content, 24, "Search seeds to shovel", function(text)
	shovelSeedFilterText = text
	refreshSelectorFilter(shovelSeedButtons, seedNames, shovelSeedFilterText, shovelSeedRow, 2)
end)

local function refreshShovelSeedButton(seedName)
	local button = shovelSeedButtons[seedName]
	if not button then
		return
	end

	local enabled = selectedShovelSeeds[seedName] == true
	button.Text = (enabled and "[x] " or "[ ] ") .. seedName
	button.BackgroundColor3 = enabled and Color3.fromRGB(122, 65, 50) or Color3.fromRGB(52, 60, 54)
end

local function refreshShovelSeedCanvas()
	refreshSelectorFilter(shovelSeedButtons, seedNames, shovelSeedFilterText, shovelSeedRow, 2)
end

local function makeShovelSeedButton(seedName)
	if shovelSeedButtons[seedName] then
		return
	end

	shovelSeedButtonCount += 1
	local button = make("TextButton", {
		Name = "Shovel" .. seedName,
		AutoButtonColor = false,
		BackgroundColor3 = Color3.fromRGB(52, 60, 54),
		BorderSizePixel = 0,
		Font = Enum.Font.GothamSemibold,
		Text = seedName,
		TextColor3 = Color3.fromRGB(242, 247, 239),
		TextSize = 12,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Size = UDim2.fromOffset(136, 24),
		LayoutOrder = shovelSeedButtonCount,
	}, shovelSeedRow)
	make("UICorner", { CornerRadius = UDim.new(0, 6) }, button)

	shovelSeedButtons[seedName] = button
	refreshShovelSeedButton(seedName)
	button.Visible = matchesSelectorFilter(seedName, shovelSeedFilterText)

	button.Activated:Connect(function()
		selectedShovelSeeds[seedName] = not selectedShovelSeeds[seedName]
		refreshShovelSeedButton(seedName)
		saveConfig()
		setStatus((selectedShovelSeeds[seedName] and "Will shovel " or "Stopped shoveling ") .. seedName)
	end)

	refreshShovelSeedCanvas()
end

for _, seedName in ipairs(seedNames) do
	makeShovelSeedButton(seedName)
end

if shovelSeedLayout then
	shovelSeedLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(refreshShovelSeedCanvas)
end
refreshShovelSeedCanvas()

local shovelSeedStockItems = getStockItemsFolder("SeedShop")
if shovelSeedStockItems then
	for _, item in ipairs(shovelSeedStockItems:GetChildren()) do
		makeShovelSeedButton(item.Name)
	end

	shovelSeedStockItems.ChildAdded:Connect(function(item)
		task.wait()
		makeShovelSeedButton(item.Name)
	end)
end
end
buildShovelSeedSelector()

local function buildGearSelector()
local selectedGearLabel = make("TextLabel", {
	Name = "SelectedGearLabel",
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamSemibold,
	Text = "Gear to buy",
	TextColor3 = Color3.fromRGB(221, 236, 216),
	TextSize = 13,
	TextXAlignment = Enum.TextXAlignment.Left,
	Size = UDim2.new(1, 0, 0, 15),
	LayoutOrder = 26,
}, content)

local gearRow = make("ScrollingFrame", {
	Name = "GearSelector",
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	CanvasSize = UDim2.fromOffset(0, 0),
	ScrollBarThickness = 4,
	ScrollingDirection = Enum.ScrollingDirection.Y,
	Size = UDim2.new(1, 0, 0, 66),
	LayoutOrder = 28,
}, content)
make("UIGridLayout", {
	CellPadding = UDim2.fromOffset(6, 6),
	CellSize = UDim2.fromOffset(136, 24),
	SortOrder = Enum.SortOrder.LayoutOrder,
}, gearRow)

local gearLayout = gearRow:FindFirstChildOfClass("UIGridLayout")
local gearButtons = {}
local gearButtonCount = 0
local gearFilterText = ""

makeSelectorSearch(content, 27, "Search gear to buy", function(text)
	gearFilterText = text
	refreshSelectorFilter(gearButtons, gearNames, gearFilterText, gearRow, 2)
end)

local function refreshGearButton(gearName)
	local button = gearButtons[gearName]
	if not button then
		return
	end

	local enabled = selectedGears[gearName] == true
	local price = getShopPriceAmount and getShopPriceAmount("GearShop", gearName)
	local stock = getShopStockAmount and getShopStockAmount("GearShop", gearName) or 0
	local suffix = ""
	if price and price > 0 then
		suffix = (" - $%s"):format(tostring(math.floor(price)))
	end
	if stock > 0 then
		suffix = suffix .. (" [%d]"):format(stock)
	end
	button.Text = (enabled and "[x] " or "[ ] ") .. gearName .. suffix
	button.BackgroundColor3 = enabled and Color3.fromRGB(58, 111, 67) or Color3.fromRGB(52, 60, 54)
end

local function refreshGearCanvas()
	refreshSelectorFilter(gearButtons, gearNames, gearFilterText, gearRow, 2)
end

local function makeGearButton(gearName)
	if gearButtons[gearName] then
		return
	end

	gearButtonCount += 1

	local button = make("TextButton", {
		Name = gearName,
		AutoButtonColor = false,
		BackgroundColor3 = Color3.fromRGB(52, 60, 54),
		BorderSizePixel = 0,
		Font = Enum.Font.GothamSemibold,
		Text = gearName,
		TextColor3 = Color3.fromRGB(242, 247, 239),
		TextSize = 12,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Size = UDim2.fromOffset(136, 24),
		LayoutOrder = gearButtonCount,
	}, gearRow)
	make("UICorner", { CornerRadius = UDim.new(0, 6) }, button)

	gearButtons[gearName] = button
	refreshGearButton(gearName)
	button.Visible = matchesSelectorFilter(gearName, gearFilterText)

	button.Activated:Connect(function()
		selectedGears[gearName] = not selectedGears[gearName]
		refreshGearButton(gearName)
		saveConfig()
		setStatus((selectedGears[gearName] and "Selected " or "Unselected ") .. gearName)
		if selectedGears[gearName] then
			notifyStock("Gear shop", gearName)
		end
	end)

	refreshGearCanvas()
end

local function scanGearShopNames()
	refreshGearNamesFromStockValues()

	local gearShop = playerGui:FindFirstChild("GearShop")
	local frame = gearShop and gearShop:FindFirstChild("Frame")
	local scrollingFrame = frame and frame:FindFirstChild("ScrollingFrame")
	if scrollingFrame then
		for _, child in ipairs(scrollingFrame:GetChildren()) do
			if child.Name ~= "ItemTemplate" and not string.find(string.lower(child.Name), "shelf", 1, true) then
				if child:FindFirstChild("Main_Frame", true) or child:FindFirstChildWhichIsA("GuiButton", true) then
					addUniqueName(gearNames, child.Name)
				end
			end
		end
	end

	table.sort(gearNames)
	for _, gearName in ipairs(gearNames) do
		makeGearButton(gearName)
	end
end

if gearLayout then
	gearLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(refreshGearCanvas)
end
refreshGearCanvas()
scanGearShopNames()

local gearStockItems = getStockItemsFolder("GearShop")
if gearStockItems then
	for _, item in ipairs(gearStockItems:GetChildren()) do
		addUniqueName(gearNames, item.Name)
		makeGearButton(item.Name)
		watchStockItem("GearShop", item)
		notifyStock("Gear shop", item.Name)
	end

	gearStockItems.ChildAdded:Connect(function(item)
		addUniqueName(gearNames, item.Name)
		table.sort(gearNames)
		makeGearButton(item.Name)
		watchStockItem("GearShop", item)
		notifyStock("Gear shop", item.Name)
	end)
end

playerGui.ChildAdded:Connect(function(child)
	if child.Name == "GearShop" then
		task.wait(0.25)
		scanGearShopNames()
	end
end)
end
buildGearSelector()

local function buildPetSelector()
local selectedPetLabel = make("TextLabel", {
	Name = "SelectedPetLabel",
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamSemibold,
	Text = "Pets to buy",
	TextColor3 = Color3.fromRGB(221, 236, 216),
	TextSize = 13,
	TextXAlignment = Enum.TextXAlignment.Left,
	Size = UDim2.new(1, 0, 0, 15),
	LayoutOrder = 29,
}, content)

local petRow = make("ScrollingFrame", {
	Name = "PetSelector",
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	CanvasSize = UDim2.fromOffset(0, 0),
	ScrollBarThickness = 4,
	ScrollingDirection = Enum.ScrollingDirection.Y,
	Size = UDim2.new(1, 0, 0, 66),
	LayoutOrder = 31,
}, content)
make("UIGridLayout", {
	CellPadding = UDim2.fromOffset(6, 6),
	CellSize = UDim2.fromOffset(136, 24),
	SortOrder = Enum.SortOrder.LayoutOrder,
}, petRow)

local petLayout = petRow:FindFirstChildOfClass("UIGridLayout")
local petButtons = {}
local petButtonCount = 0
local petFilterText = ""

makeSelectorSearch(content, 30, "Search pets to buy", function(text)
	petFilterText = text
	refreshSelectorFilter(petButtons, petNames, petFilterText, petRow, 2)
end)

local function refreshPetButton(petName)
	local button = petButtons[petName]
	if not button then
		return
	end

	local enabled = selectedPets[petName] == true
	button.Text = (enabled and "[x] " or "[ ] ") .. petName
	button.BackgroundColor3 = enabled and Color3.fromRGB(58, 111, 67) or Color3.fromRGB(52, 60, 54)
end

local function refreshPetCanvas()
	refreshSelectorFilter(petButtons, petNames, petFilterText, petRow, 2)
end

local function makePetButton(petName)
	if petButtons[petName] then
		return
	end

	petButtonCount += 1

	local button = make("TextButton", {
		Name = petName,
		AutoButtonColor = false,
		BackgroundColor3 = Color3.fromRGB(52, 60, 54),
		BorderSizePixel = 0,
		Font = Enum.Font.GothamSemibold,
		Text = petName,
		TextColor3 = Color3.fromRGB(242, 247, 239),
		TextSize = 12,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Size = UDim2.fromOffset(136, 24),
		LayoutOrder = petButtonCount,
	}, petRow)
	make("UICorner", { CornerRadius = UDim.new(0, 6) }, button)

	petButtons[petName] = button
	refreshPetButton(petName)
	button.Visible = matchesSelectorFilter(petName, petFilterText)

	button.Activated:Connect(function()
		selectedPets[petName] = not selectedPets[petName]
		refreshPetButton(petName)
		saveConfig()
		setStatus((selectedPets[petName] and "Selected " or "Unselected ") .. petName)
		if selectedPets[petName] and listHasName(buyPetNames, petName) then
			notifyPetSpawn(petName)
		end
	end)

	refreshPetCanvas()
end

local function scanPetBuyNames()
	refreshPetNamesFromAssets()
	refreshBuyPetNamesFromWildSpawns()

	for _, petName in ipairs(petNames) do
		makePetButton(petName)
	end
end

for _, petName in ipairs(petNames) do
	makePetButton(petName)
end

if petLayout then
	petLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(refreshPetCanvas)
end
refreshPetCanvas()
scanPetBuyNames()

local assetsForPetBuy = ReplicatedStorage:FindFirstChild("Assets")
local petsFolderForBuy = assetsForPetBuy and assetsForPetBuy:FindFirstChild("Pets")
if petsFolderForBuy then
	petsFolderForBuy.ChildAdded:Connect(function(pet)
		local baseName = stripVariantWords(pet.Name)
		addUniqueName(petNames, baseName)
		table.sort(petNames)
		makePetButton(baseName)
	end)
end

local wildPetSpawnsForBuy = getWildPetSpawns()
if wildPetSpawnsForBuy then
	wildPetSpawnsForBuy.DescendantAdded:Connect(function(descendant)
		local model
		if descendant:IsA("ProximityPrompt") then
			model = descendant:FindFirstAncestorWhichIsA("Model")
		elseif descendant:IsA("Model") and descendant:FindFirstChildWhichIsA("ProximityPrompt", true) then
			model = descendant
		end
		if model then
			local baseName = stripVariantWords(model.Name)
			addUniqueName(buyPetNames, baseName)
			addUniqueName(petNames, baseName)
			table.sort(buyPetNames)
			table.sort(petNames)
			makePetButton(baseName)
			notifyPetSpawn(baseName)
		end
	end)
end
local mapForPetBuy = getMap()
if mapForPetBuy then
	mapForPetBuy.ChildAdded:Connect(function(child)
		if child.Name == "WildPetSpawns" then
			task.wait(0.25)
			scanPetBuyNames()
			child.DescendantAdded:Connect(function(descendant)
				local model
				if descendant:IsA("ProximityPrompt") then
					model = descendant:FindFirstAncestorWhichIsA("Model")
				elseif descendant:IsA("Model") and descendant:FindFirstChildWhichIsA("ProximityPrompt", true) then
					model = descendant
				end
				if model then
					local baseName = stripVariantWords(model.Name)
					addUniqueName(buyPetNames, baseName)
					addUniqueName(petNames, baseName)
					table.sort(buyPetNames)
					table.sort(petNames)
					makePetButton(baseName)
					notifyPetSpawn(baseName)
				end
			end)
		end
	end)
end
end
buildPetSelector()

local dragStart
local startPos
local dragging = false

header.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		dragging = true
		dragStart = input.Position
		startPos = panel.Position
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		dragging = false
	end
end)

UserInputService.InputChanged:Connect(function(input)
	if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
		local delta = input.Position - dragStart
		panel.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
	end
end)
end

buildUI()

schedulePerformanceModeRestore()

timers = {
	fruitCollector = 0,
	seedPlacer = 0,
	autoShovel = 0,
	autoSell = 0,
	sellWhenFull = 0,
	autoBuySeeds = 0,
	autoBuyGear = 0,
	autoCollectRainbowSeeds = 0,
	autoBuyPets = 0,
	stats = 0,
	guiInventoryFull = false,
	lastInventoryRefresh = 0,
	lastGuiInventoryRefresh = 0,
}

function runGuarded(key, callback)
	if running[key] then
		return
	end

	running[key] = true
	task.spawn(function()
		local ok, err = pcall(callback)
		if not ok then
			setStatus(("%s error: %s"):format(key, tostring(err)))
		end
		running[key] = false
	end)
end

RunService.Heartbeat:Connect(function(deltaTime)
	local jobsStarted = 0
	local maxJobsThisFrame = 2
	local function tryRun(key, callback)
		if jobsStarted >= maxJobsThisFrame or running[key] then
			return false
		end

		jobsStarted += 1
		runGuarded(key, callback)
		return true
	end

	timers.fruitCollector = state.fruitCollector and (timers.fruitCollector + deltaTime) or 0
	timers.seedPlacer = state.seedPlacer and (timers.seedPlacer + deltaTime) or 0
	timers.autoShovel = state.autoShovel and (timers.autoShovel + deltaTime) or 0
	timers.autoSell = state.autoSell and (timers.autoSell + deltaTime) or 0
	timers.sellWhenFull = state.sellWhenFull and (timers.sellWhenFull + deltaTime) or 0
	timers.autoBuySeeds = state.autoBuySeeds and (timers.autoBuySeeds + deltaTime) or 0
	timers.autoBuyGear = state.autoBuyGear and (timers.autoBuyGear + deltaTime) or 0
	timers.autoCollectRainbowSeeds = state.autoCollectRainbowSeeds and (timers.autoCollectRainbowSeeds + deltaTime) or 0
	timers.autoBuyPets = state.autoBuyPets and (timers.autoBuyPets + deltaTime) or 0
	timers.stats += deltaTime

	if timers.stats >= 2.5 then
		timers.stats = 0
		refreshInventoryStats()
		updateStatsUI()
	end

	local shovelDue = state.autoShovel and timers.autoShovel >= CONFIG.shovelInterval
	if shovelDue then
		if tryRun("autoShovel", autoShovel) then
			timers.autoShovel = 0
		end
	end

	local movementLocked = shovelDue or running.autoShovel

	if state.autoBuyPets and timers.autoBuyPets >= CONFIG.petBuyInterval and not movementLocked then
		if tryRun("autoBuyPets", buyPets) then
			timers.autoBuyPets = 0
		end
	end

	if state.autoCollectRainbowSeeds and timers.autoCollectRainbowSeeds >= CONFIG.rainbowCollectInterval and not movementLocked then
		if tryRun("autoCollectRainbowSeeds", autoCollectRainbowSeeds) then
			timers.autoCollectRainbowSeeds = 0
		end
	end

	if state.fruitCollector and timers.fruitCollector >= CONFIG.collectInterval then
		if movementLocked then
			timers.fruitCollector = CONFIG.collectInterval
		else
			if tryRun("fruitCollector", collectFruit) then
				timers.fruitCollector = 0
			end
		end
	end

	if state.seedPlacer and timers.seedPlacer >= CONFIG.plantInterval and not movementLocked then
		if tryRun("seedPlacer", plantSeed) then
			timers.seedPlacer = 0
		end
	end

	if state.sellWhenFull and timers.sellWhenFull >= CONFIG.sellWhenFullInterval and not movementLocked then
		timers.sellWhenFull = 0
		if refreshInventoryStats() then
			tryRun("sellWhenFull", function()
				autoSell(true)
			end)
		end
	end

	if state.autoSell and timers.autoSell >= CONFIG.sellInterval and not movementLocked then
		if tryRun("autoSell", autoSell) then
			timers.autoSell = 0
		end
	end

	if state.autoBuySeeds and timers.autoBuySeeds >= CONFIG.buyInterval and not movementLocked then
		if tryRun("autoBuySeeds", buySeed) then
			timers.autoBuySeeds = 0
		end
	end

	if state.autoBuyGear and timers.autoBuyGear >= CONFIG.buyInterval and not movementLocked then
		if tryRun("autoBuyGear", buyGear) then
			timers.autoBuyGear = 0
		end
	end

end)

if configLoaded then
	setStatus("Garden Tools loaded - config restored")
elseif canUseFileConfig() then
	setStatus("Garden Tools loaded - config ready")
else
	setStatus("Garden Tools loaded - config files unsupported")
end

