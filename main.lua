-- Garden automation GUI for private testing in a Grow-a-Garden-style place.
-- Drop this LocalScript in StarterPlayerScripts, or run it from a local test client.

Players = game:GetService("Players")
CollectionService = game:GetService("CollectionService")
HttpService = game:GetService("HttpService")
ReplicatedStorage = game:GetService("ReplicatedStorage")
RunService = game:GetService("RunService")
StarterGui = game:GetService("StarterGui")
UserInputService = game:GetService("UserInputService")
virtualInputManager = nil

pcall(function()
	virtualInputManager = game:GetService("VirtualInputManager")
end)

localPlayer = Players.LocalPlayer
playerGui = localPlayer:WaitForChild("PlayerGui")

CONFIG = {
	collectInterval = 0.25,
	plantInterval = 1.3,
	sellInterval = 12.0,
	sellWhenFullInterval = 1.5,
	sellResumeFreeSlots = 8,
	buyInterval = 1.5,
	rainbowCollectInterval = 4.5,
	petBuyInterval = 1.5,
	cacheRefreshInterval = 25.0,
	dropCacheRefreshInterval = 5.0,
	inventoryRefreshInterval = 3.5,
	guiInventoryRefreshInterval = 30.0,
	maxFruitCollectPerTick = 28,
	maxFruitScanPerRoot = 1600,
	fruitCacheRefreshInterval = 2.0,
	maxFruitTargetsCached = 260,
	maxFruitPromptFallbackPerTick = 28,
	maxSeedPlantPerTick = 3,
	maxSeedPlacementsPerTool = 2,
	seedCountCacheRefreshInterval = 45.0,
	maxSeedBuyPerTick = 3,
	seedBuyRemoteRepeats = 4,
	shovelInterval = 0.35,
	shovelHoldDuration = 3.1,
	maxShovelPerTick = 1,
	maxDropCollectPerTick = 3,
	maxDropScanPerRoot = 450,
	maxInventoryItems = 200,
	lowRaritySeedLimit = 10,
	maxGardenPlants = 500,
	seedPlacementMode = "Farm Corner",
	undergroundStacking = false,
	savedPlantPosition = nil,
	selectedSeed = "",
	plantRadius = 18,
	webhookUrl = "",
	statsWebhookInterval = 180.0,
}

seedNames = {}

seedPriority = {}

state = {
	fruitCollector = false,
	collectTeleport = true,
	seedPlacer = false,
	autoShovel = false,
	autoSell = false,
	sellWhenFull = true,
	autoBuySeeds = false,
	autoBuyGear = false,
	autoCollectRainbowSeeds = false,
	autoBuyPets = false,
	performanceMode = false,
	lastStatus = "Ready",
}

selectedSeeds = {}

selectedShovelSeeds = {}

gearNames = {}

selectedGears = {}

petNames = {}

buyPetNames = {}

selectedPets = {}

plantPromptTextCache = setmetatable({}, { __mode = "k" })
shovelPromptCache = setmetatable({}, { __mode = "k" })
harvestPromptCache = setmetatable({}, { __mode = "k" })
handledPetSpawns = setmetatable({}, { __mode = "k" })

saveConfig = function() end
setStatus = function() end

CONFIG_FOLDER = "GardenTools"
CONFIG_FILE = CONFIG_FOLDER .. "/config.json"

function canUseFileConfig()
	return typeof(readfile) == "function"
		and typeof(writefile) == "function"
		and typeof(isfile) == "function"
end

function copyMap(source)
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

function copyKnownValues(source, destination, keys)
	if type(source) ~= "table" then
		return
	end

	for _, key in ipairs(keys) do
		if source[key] ~= nil then
			destination[key] = source[key]
		end
	end
end

function loadConfig()
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
		"sellResumeFreeSlots",
		"buyInterval",
		"shovelInterval",
		"lowRaritySeedLimit",
		"maxGardenPlants",
		"seedPlacementMode",
		"undergroundStacking",
		"savedPlantPosition",
		"selectedSeed",
		"plantRadius",
		"webhookUrl",
		"statsWebhookInterval",
	})
	copyKnownValues(decoded.state, state, {
		"fruitCollector",
		"collectTeleport",
		"seedPlacer",
		"autoShovel",
		"autoSell",
		"sellWhenFull",
		"autoBuySeeds",
		"autoBuyGear",
		"autoCollectRainbowSeeds",
		"autoBuyPets",
		"performanceMode",
	})
	if decoded.state and decoded.state.hidePlants == true then
		state.performanceMode = true
	end

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
			sellResumeFreeSlots = CONFIG.sellResumeFreeSlots,
			buyInterval = CONFIG.buyInterval,
			shovelInterval = CONFIG.shovelInterval,
			lowRaritySeedLimit = CONFIG.lowRaritySeedLimit,
			maxGardenPlants = CONFIG.maxGardenPlants,
			seedPlacementMode = CONFIG.seedPlacementMode,
			undergroundStacking = CONFIG.undergroundStacking,
			savedPlantPosition = CONFIG.savedPlantPosition,
			selectedSeed = CONFIG.selectedSeed,
			plantRadius = CONFIG.plantRadius,
			webhookUrl = CONFIG.webhookUrl,
			statsWebhookInterval = CONFIG.statsWebhookInterval,
		},
		state = {
			fruitCollector = state.fruitCollector,
			collectTeleport = state.collectTeleport,
			seedPlacer = state.seedPlacer,
			autoShovel = state.autoShovel,
			autoSell = state.autoSell,
			sellWhenFull = state.sellWhenFull,
			autoBuySeeds = state.autoBuySeeds,
			autoBuyGear = state.autoBuyGear,
			autoCollectRainbowSeeds = state.autoCollectRainbowSeeds,
			autoBuyPets = state.autoBuyPets,
			performanceMode = state.performanceMode,
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
local stockLastAmounts = {}
local getStockItemsFolder
local getShopStockAmount
local getShopPriceAmount

function getRequestFunction()
	return (syn and syn.request)
		or (http and http.request)
		or http_request
		or request
end

function sendWebhook(title, description, key)
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

function shouldNotifySelected(map, name)
	return name and name ~= "" and map[name] == true
end

function listHasName(list, name)
	for _, value in ipairs(list) do
		if value == name then
			return true
		end
	end
	return false
end

function getStockFolderName(shopName)
	if shopName == "Seed shop" then
		return "SeedShop"
	elseif shopName == "Gear shop" then
		return "GearShop"
	end
	return shopName
end

function getShopGuiRoot(shopName)
	local guiName = getStockFolderName(shopName)
	return playerGui:FindFirstChild(guiName) or StarterGui:FindFirstChild(guiName)
end

function shopGuiShowsItem(shopName, itemName)
	local shopGui = getShopGuiRoot(shopName)
	if not shopGui then
		return false
	end

	for _, descendant in ipairs(shopGui:GetDescendants()) do
		if descendant.Name == itemName and descendant.Name ~= "ItemTemplate" then
			if descendant:FindFirstChild("Main_Frame", true) or descendant:FindFirstChildWhichIsA("GuiButton", true) then
				return true
			end
		end
	end

	return false
end

function itemIsInStock(shopName, itemName)
	local stockFolderName = getStockFolderName(shopName)
	local stockAmount = getShopStockAmount and getShopStockAmount(stockFolderName, itemName) or 0
	return stockAmount > 0
end

function notifyStock(shopName, itemName, force)
	local stockFolderName = getStockFolderName(shopName)
	local stockAmount = getShopStockAmount(stockFolderName, itemName)
	local key = "stock:" .. shopName .. ":" .. itemName
	local previousAmount = stockLastAmounts[key]
	stockLastAmounts[key] = stockAmount

	if stockAmount <= 0 then
		webhookSentAt[key] = nil
		return
	end

	if (force or previousAmount == nil or previousAmount <= 0)
		and (shouldNotifySelected(selectedSeeds, itemName) or shouldNotifySelected(selectedGears, itemName))
	then
		sendWebhook(
			shopName .. " stock",
			("%s is now in stock (%d available)."):format(itemName, stockAmount),
			key
		)
	end
end

local watchedStockItems = {}

function watchStockItem(shopName, item)
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

	for _, attributeName in ipairs({
		"Stock",
		"StockAmount",
		"CurrentStock",
		"Amount",
		"Quantity",
		"Count",
		"Available",
	}) do
		item:GetAttributeChangedSignal(attributeName):Connect(changed)
	end

	if item:IsA("ValueBase") then
		item.Changed:Connect(changed)
	end

	for _, descendant in ipairs(item:GetDescendants()) do
		for _, attributeName in ipairs({
			"Stock",
			"StockAmount",
			"CurrentStock",
			"Amount",
			"Quantity",
			"Count",
			"Available",
		}) do
			descendant:GetAttributeChangedSignal(attributeName):Connect(changed)
		end
		if descendant:IsA("ValueBase") then
			descendant.Changed:Connect(changed)
		end
	end

	item.DescendantAdded:Connect(function(descendant)
		for _, attributeName in ipairs({
			"Stock",
			"StockAmount",
			"CurrentStock",
			"Amount",
			"Quantity",
			"Count",
			"Available",
		}) do
			descendant:GetAttributeChangedSignal(attributeName):Connect(changed)
		end
		if descendant:IsA("ValueBase") then
			descendant.Changed:Connect(changed)
			changed()
		end
	end)
	item.ChildAdded:Connect(changed)
	item.ChildRemoved:Connect(changed)
end

function notifyPetSpawn(petName)
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
local lastStatusSetAt = 0
local pendingStatusMessage
local lastStatsUIUpdateAt = 0
local schedulerAccumulator = 0
local lastStatsWebhookAt = 0

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
	sheckles = 0,
	startSheckles = nil,
	shecklesFarmed = 0,
	inventoryItems = 0,
	inventoryCapacity = CONFIG.maxInventoryItems,
	inventoryFull = false,
}

local running = {}

setStatus = function(message)
	local text = tostring(message)
	local now = os.clock()
	state.lastStatus = text
	if statusValue then
		if now - lastStatusSetAt >= 0.8 then
			lastStatusSetAt = now
			statusValue.Value = text
			pendingStatusMessage = nil
		else
			pendingStatusMessage = text
		end
	end
end

function countEnabledToggles()
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
	}) do
		if state[key] then
			count += 1
		end
	end
	return count
end

function formatNumber(value)
	value = tonumber(value) or 0
	local sign = value < 0 and "-" or ""
	value = math.abs(math.floor(value + 0.5))
	local text = tostring(value)
	while true do
		local replaced
		text, replaced = string.gsub(text, "^(%d+)(%d%d%d)", "%1,%2")
		if replaced == 0 then
			break
		end
	end
	return sign .. text
end

function parseAmountText(text)
	text = tostring(text or "")
	local lowered = string.lower(text)
	local multiplier = 1
	if string.find(lowered, "b", 1, true) then
		multiplier = 1000000000
	elseif string.find(lowered, "m", 1, true) then
		multiplier = 1000000
	elseif string.find(lowered, "k", 1, true) then
		multiplier = 1000
	end

	local raw = string.match(text, "[-]?[%d,]+%.?%d*")
	if not raw then
		return nil
	end

	raw = string.gsub(raw, ",", "")
	local amount = tonumber(raw)
	if not amount then
		return nil
	end
	return math.floor(amount * multiplier + 0.5)
end

function isEnabled(key)
	return state[key] == true
end

function addUniqueName(list, name)
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

function trimText(value)
	return string.gsub(tostring(value or ""), "^%s*(.-)%s*$", "%1")
end

function stripVariantWords(name)
	local result = tostring(name or "")
	for _, word in ipairs(petVariantWords) do
		result = string.gsub(result, "^" .. word .. "%s+", "")
		result = string.gsub(result, "%s+" .. word .. "$", "")
	end
	return trimText(result)
end

function getGearImagesFolder()
	local sharedModules = ReplicatedStorage:FindFirstChild("SharedModules")
	return sharedModules and sharedModules:FindFirstChild("GearImages")
end

getStockItemsFolder = function(shopName)
	local stockValues = ReplicatedStorage:FindFirstChild("StockValues")
	local shop = stockValues and stockValues:FindFirstChild(shopName)
	return shop and shop:FindFirstChild("Items")
end

function getSeedShopGui()
	return StarterGui:FindFirstChild("SeedShop") or playerGui:FindFirstChild("SeedShop")
end

function getRuntimeSeedShopGui()
	return playerGui:FindFirstChild("SeedShop") or StarterGui:FindFirstChild("SeedShop")
end

function getNumericFromInstance(instance, keys)
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

function stockKeyLooksValid(name)
	local lowered = string.lower(tostring(name or ""))
	return lowered == "stock"
		or lowered == "stockamount"
		or lowered == "currentstock"
		or lowered == "amount"
		or lowered == "quantity"
		or lowered == "count"
		or lowered == "available"
		or string.find(lowered, "stock", 1, true) ~= nil
end

getShopStockAmount = function(shopName, itemName)
	local items = getStockItemsFolder and getStockItemsFolder(shopName)
	local stockItem = items and items:FindFirstChild(itemName)
	if not stockItem then
		return 0
	end

	if stockItem:IsA("NumberValue") or stockItem:IsA("IntValue") then
		return math.max(0, math.floor(tonumber(stockItem.Value) or 0))
	end

	if stockItem:IsA("BoolValue") then
		return stockItem.Value and 1 or 0
	end

	local value = getNumericFromInstance(stockItem, {
		"Stock",
		"StockAmount",
		"CurrentStock",
		"Amount",
		"Quantity",
		"Count",
		"Available",
	})
	if value then
		return math.max(0, math.floor(value))
	end

	for _, descendant in ipairs(stockItem:GetDescendants()) do
		if stockKeyLooksValid(descendant.Name) and (descendant:IsA("NumberValue") or descendant:IsA("IntValue")) then
			local number = tonumber(descendant.Value)
			if number and number > 0 then
				return math.floor(number)
			end
		elseif stockKeyLooksValid(descendant.Name) and descendant:IsA("BoolValue") and descendant.Value == true then
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

function getSeedMetadataValue(seedName)
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

function refreshNamesFromStock(shopName, targetList)
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

function refreshSeedNamesFromStockValues()
	refreshNamesFromStock("SeedShop", seedNames)
end

function refreshGearNamesFromStockValues()
	refreshNamesFromStock("GearShop", gearNames)
end

function refreshPetNamesFromAssets()
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

function getCharacter()
	return localPlayer.Character or localPlayer.CharacterAdded:Wait()
end

function getRoot()
	local character = getCharacter()
	return character:FindFirstChild("HumanoidRootPart")
end

function getHumanoid()
	local character = getCharacter()
	return character:FindFirstChildOfClass("Humanoid")
end

function getObjectPath(instance)
	local parts = {}
	local current = instance
	while current and current ~= game do
		table.insert(parts, 1, current.Name)
		current = current.Parent
	end
	return table.concat(parts, ".")
end

function safeText(value)
	if value == nil then
		return ""
	end

	return tostring(value)
end

local packetModule

function getPacketModule()
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
local packetEntryCache = {}
local packetObjectCache = {}

function getPacketRemote()
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

function packetNameExists(packetName)
	local remote = getPacketRemote()
	if not remote then
		return true
	end
	return remote:GetAttribute(packetName) ~= nil
end

function firePacketRemote(packetName, ...)
	local remote = getPacketRemote()
	if not remote then
		return false
	end

	local id = remote:GetAttribute(packetName)
	if id == nil then
		return false
	end
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

function tryPacketEntry(entry, ...)
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

function buildPacketObject(packetName)
	local packet = getPacketModule()
	if not packet then
		return nil
	end

	local constructors = {}
	if type(packet) == "function" then
		table.insert(constructors, packet)
	elseif type(packet) == "table" then
		for _, key in ipairs({ "new", "New", "Create", "Packet" }) do
			if type(packet[key]) == "function" then
				table.insert(constructors, function(name)
					return packet[key](packet, name)
				end)
				table.insert(constructors, packet[key])
			end
		end
	end

	for _, constructor in ipairs(constructors) do
		local ok, object = pcall(constructor, packetName)
		if ok and (type(object) == "table" or typeof(object) == "Instance") then
			return object
		end
	end

	return nil
end

function getPacketObject(packetName)
	local cached = packetObjectCache[packetName]
	if cached ~= nil then
		return cached ~= false and cached or nil
	end

	local object = buildPacketObject(packetName)
	if object then
		packetObjectCache[packetName] = object
		return object
	end

	packetObjectCache[packetName] = false
	return nil
end

function firePacketObject(packetName, ...)
	local object = getPacketObject(packetName)
	if not object then
		return false, 0
	end

	local actions = 0
	for _, methodName in ipairs({ "Fire", "FireServer", "Send", "SendToServer" }) do
		if type(object[methodName]) == "function" then
			if pcall(object[methodName], object, ...) then
				actions += 1
			end
			if pcall(object[methodName], ...) then
				actions += 1
			end
		end
	end

	return actions > 0, actions
end

function findPacketEntry(root, packetName, seen)
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

function sendPacket(packetName, ...)
	if not packetNameExists(packetName) then
		return false
	end

	local packet = getPacketModule()
	if type(packet) == "table" then
		local entry = packetEntryCache[packetName]
		if entry == nil then
			entry = findPacketEntry(packet, packetName)
			if entry == nil then
				entry = false
			end
			packetEntryCache[packetName] = entry
		end
		if entry == false then
			entry = nil
		end
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

function sendExactPacket(packetName, ...)
	if not packetNameExists(packetName) then
		return false, 0
	end

	local actions = 0
	local ok, count = firePacketObject(packetName, ...)
	if ok then
		actions += count or 1
	end

	local packet = getPacketModule()
	if type(packet) == "table" then
		local entry = packetEntryCache[packetName]
		if entry == nil then
			entry = findPacketEntry(packet, packetName)
			if entry == nil then
				entry = false
			end
			packetEntryCache[packetName] = entry
		end
		if entry ~= false and tryPacketEntry(entry, ...) then
			actions += 1
		end

		for _, methodName in ipairs({ "Fire", "FireServer", "Send", "SendToServer" }) do
			if type(packet[methodName]) == "function" then
				if pcall(packet[methodName], packet, packetName, ...) then
					actions += 1
				end
				if pcall(packet[methodName], packetName, ...) then
					actions += 1
				end
			end
		end
	elseif type(packet) == "function" then
		if pcall(packet, packetName, ...) then
			actions += 1
		end
	end

	if firePacketRemote(packetName, ...) then
		actions += 1
	end

	return actions > 0, actions
end

local cache = {
	seedFrames = {},
	gearFrames = {},
}
local nextDescendantRefreshAt = 0

function getCachedDescendants(key, root, maxAge)
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
		if cache[listKey] and now < nextDescendantRefreshAt then
			return cache[listKey]
		end
		nextDescendantRefreshAt = now + 0.35
		cache[atKey] = now
		cache[listKey] = root:GetDescendants()
	end

	return cache[listKey]
end

function maybeYieldScan(startedAt, budgetSeconds)
	if os.clock() - startedAt >= (budgetSeconds or 0.012) then
		task.wait()
		return os.clock()
	end
	return startedAt
end

function getMap()
	return workspace:FindFirstChild("Map")
end

function getGardens()
	return workspace:FindFirstChild("Gardens")
end

local dropCacheRoots = {}

function watchDropRoot(root)
	if not root or dropCacheRoots[root] then
		return
	end

	dropCacheRoots[root] = true
end

function watchDropRoots()
	watchDropRoot(getMap())
	watchDropRoot(getGardens())
end

function getWildPetSpawns()
	local map = getMap()
	return map and map:FindFirstChild("WildPetSpawns")
end

function refreshBuyPetNamesFromWildSpawns()
	local wildPetSpawns = getWildPetSpawns()
	if not wildPetSpawns then
		return
	end

	for _, descendant in ipairs(wildPetSpawns:GetDescendants()) do
		local model
		if descendant:IsA("ProximityPrompt") and descendant.Parent and descendant:IsDescendantOf(workspace) then
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

function valueMatchesLocalPlayer(value)
	if value == localPlayer then
		return true
	end

	if typeof(value) == "Instance" and value:IsA("Player") then
		return value == localPlayer
	end

	local text = tostring(value or "")
	return text == tostring(localPlayer.UserId) or string.lower(text) == string.lower(localPlayer.Name)
end

function plotBelongsToLocalPlayer(plot)
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
	noGainStreak = 0,
}

function invalidateOwnGardenCache()
	ownGardenCache.checkedAt = 0
	cache.ownGardenDescendants = nil
	cache.ownGardenAt = nil
	fruitTargetCache.refreshedAt = 0
	fruitTargetCache.targets = {}
	fruitTargetCache.cursor = 1
	fruitTargetCache.noGainStreak = 0
end

function addUniqueInstance(list, instance)
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

function collectNamedDescendantRoots(root, names, results, limit)
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

function getOwnGardenRoots()
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

function getGardenAnchorPart(root)
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

function getOwnGardenAnchor()
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
		if state.performanceMode then
			task.defer(function()
				if enablePerformanceMode then
					enablePerformanceMode()
				end
			end)
		end
	elseif child.Name == "Map" and state.performanceMode then
		task.defer(function()
			if enablePerformanceMode then
				enablePerformanceMode()
			end
		end)
	end
end)

function textMatches(instance, terms)
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

function treeTextMatches(instance, terms, maxAncestors)
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

function getToolContainers()
	return {
		getCharacter(),
		localPlayer:FindFirstChildOfClass("Backpack"),
	}
end

function countInventoryTools()
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

function guiShowsInventoryFull()
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

local currencyCache = {
	value = 0,
	checkedAt = 0,
}

function nameLooksLikeCurrency(name)
	local lowered = string.lower(tostring(name or ""))
	return string.find(lowered, "sheck", 1, true)
		or string.find(lowered, "money", 1, true)
		or string.find(lowered, "cash", 1, true)
		or string.find(lowered, "coin", 1, true)
		or string.find(lowered, "currency", 1, true)
end

function readCurrencyValueObject(root)
	if not root then
		return nil
	end

	for _, child in ipairs(root:GetChildren()) do
		if child:IsA("ValueBase") and nameLooksLikeCurrency(child.Name) then
			local amount = tonumber(child.Value)
			if amount then
				return amount
			end
		end
	end

	return nil
end

function readCurrencyFromGui()
	for _, descendant in ipairs(playerGui:GetDescendants()) do
		if descendant:IsA("TextLabel") or descendant:IsA("TextButton") or descendant:IsA("TextBox") then
			local ok, visible = pcall(function()
				return descendant.Visible
			end)
			if ok and visible then
				local text = tostring(descendant.Text or "")
				local lowered = string.lower(text .. " " .. descendant.Name)
				if string.find(lowered, "sheck", 1, true)
					or string.find(lowered, "$", 1, true)
					or string.find(lowered, "cash", 1, true)
					or string.find(lowered, "money", 1, true)
				then
					local amount = parseAmountText(text)
					if amount then
						return amount
					end
				end
			end
		end
	end
	return nil
end

function refreshCurrencyStats(force)
	local now = os.clock()
	if not force and now - currencyCache.checkedAt < 5 then
		return stats.sheckles
	end

	local amount = readCurrencyValueObject(localPlayer:FindFirstChild("leaderstats"))
		or readCurrencyValueObject(localPlayer)
		or readCurrencyFromGui()

	if amount then
		stats.sheckles = amount
		if stats.startSheckles == nil then
			stats.startSheckles = amount
		end
		stats.shecklesFarmed = math.max(stats.shecklesFarmed or 0, amount - (stats.startSheckles or amount), 0)
		currencyCache.value = amount
	end

	currencyCache.checkedAt = now
	return stats.sheckles
end

function getRuntimeText()
	local elapsed = math.floor(os.clock() - sessionStartedAt)
	local hours = math.floor(elapsed / 3600)
	local minutes = math.floor((elapsed % 3600) / 60)
	local seconds = elapsed % 60
	if hours > 0 then
		return ("%dh %dm %ds"):format(hours, minutes, seconds)
	end
	return ("%dm %ds"):format(minutes, seconds)
end

function buildStatsSnapshot()
	refreshCurrencyStats()
	local elapsedMinutes = math.max((os.clock() - sessionStartedAt) / 60, 0.01)
	local fruitRate = math.floor((stats.fruitCollected / elapsedMinutes) + 0.5)
	local freeSlots = math.max((stats.inventoryCapacity or CONFIG.maxInventoryItems) - (stats.inventoryItems or 0), 0)

	return {
		runtime = getRuntimeText(),
		enabled = countEnabledToggles(),
		sheckles = stats.sheckles or 0,
		shecklesFarmed = stats.shecklesFarmed or 0,
		fruitCollected = stats.fruitCollected,
		fruitRate = fruitRate,
		seedsBought = stats.seedsBought,
		gearBought = stats.gearBought,
		petsBought = stats.petsBought,
		seedsPlanted = stats.seedsPlanted,
		seedsShoveled = stats.seedsShoveled,
		inventoryItems = stats.inventoryItems,
		inventoryCapacity = stats.inventoryCapacity,
		freeSlots = freeSlots,
		inventoryFull = stats.inventoryFull,
	}
end

function buildStatsWebhookDescription(snapshot)
	return table.concat({
		("Runtime: `%s`"):format(snapshot.runtime),
		("Sheckles: `%s`"):format(formatNumber(snapshot.sheckles)),
		("Sheckles farmed since start: `+%s`"):format(formatNumber(snapshot.shecklesFarmed)),
		("Fruit collected: `%s` (`%s/min`)"):format(formatNumber(snapshot.fruitCollected), formatNumber(snapshot.fruitRate)),
		("Bought: `%s` seeds | `%s` gear | `%s` pets"):format(formatNumber(snapshot.seedsBought), formatNumber(snapshot.gearBought), formatNumber(snapshot.petsBought)),
		("Plants: `%s` placed | `%s` shoveled"):format(formatNumber(snapshot.seedsPlanted), formatNumber(snapshot.seedsShoveled)),
		("Inventory: `%s/%s` (`%s` free)%s"):format(formatNumber(snapshot.inventoryItems), formatNumber(snapshot.inventoryCapacity), formatNumber(snapshot.freeSlots), snapshot.inventoryFull and " FULL" or ""),
		("Enabled systems: `%d`"):format(snapshot.enabled),
	}, "\n")
end

function sendStatsWebhook(force)
	if CONFIG.webhookUrl == "" then
		return false
	end

	local now = os.clock()
	if not force and now - lastStatsWebhookAt < CONFIG.statsWebhookInterval then
		return false
	end

	local snapshot = buildStatsSnapshot()
	local sent = sendWebhook("Garden Tools Stats", buildStatsWebhookDescription(snapshot), force and "stats:manual" or "stats:auto")
	if sent then
		lastStatsWebhookAt = now
	end
	return sent
end

function refreshInventoryStats(force)
	local now = os.clock()
	if not force and now - inventoryCache.checkedAt < CONFIG.inventoryRefreshInterval then
		stats.inventoryItems = inventoryCache.items
		stats.inventoryCapacity = inventoryCache.capacity
		stats.inventoryFull = inventoryCache.full
		return stats.inventoryFull, stats.inventoryItems, stats.inventoryCapacity
	end

	local count = countInventoryTools()
	local capacity = CONFIG.maxInventoryItems
	local nearCapacity = count >= math.max(capacity - 15, 1)
	if count < math.max(capacity - 20, 1) then
		inventoryCache.guiFull = false
	elseif (force or nearCapacity or inventoryCache.guiFull) and (force or now - inventoryCache.guiCheckedAt >= CONFIG.guiInventoryRefreshInterval) then
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

function purchaseChanged(beforeInventoryCount, beforeSheckles)
	task.wait(0.25)
	local afterInventoryCount = countInventoryTools()
	local afterSheckles = refreshCurrencyStats(true)
	return (afterInventoryCount and beforeInventoryCount and afterInventoryCount > beforeInventoryCount)
		or (afterSheckles and beforeSheckles and afterSheckles < beforeSheckles),
		afterInventoryCount,
		afterSheckles
end

function shouldPauseFruitCollection()
	if not (state.sellWhenFull or state.autoSell) then
		return false
	end

	local full = refreshInventoryStats(false)
	return full == true
end

function updateStatsUI()
	local now = os.clock()
	if now - lastStatsUIUpdateAt < 1.5 then
		return
	end
	lastStatsUIUpdateAt = now
	if pendingStatusMessage and statusValue then
		statusValue.Value = pendingStatusMessage
		pendingStatusMessage = nil
		lastStatusSetAt = now
	end

	local snapshot = buildStatsSnapshot()

	for key, label in pairs(statsLabels) do
		if label and label.Parent then
			if key == "status" then
				label.Text = ("Run: %s | Enabled: %d | TP %s"):format(snapshot.runtime, snapshot.enabled, state.collectTeleport and "ON" or "OFF")
			elseif key == "systems" then
				label.Text = ("Sheckles: %s"):format(formatNumber(snapshot.sheckles))
			elseif key == "inventory" then
				label.Text = ("Farmed this run: +%s sheckles"):format(formatNumber(snapshot.shecklesFarmed))
			elseif key == "collect" then
				label.Text = ("Fruit: %s total | %s/min"):format(formatNumber(snapshot.fruitCollected), formatNumber(snapshot.fruitRate))
			elseif key == "planting" then
				label.Text = ("Plants: %s placed | %s shoveled"):format(formatNumber(snapshot.seedsPlanted), formatNumber(snapshot.seedsShoveled))
			elseif key == "shops" then
				label.Text = ("Bought: %s seeds | %s gear | %s pets"):format(formatNumber(snapshot.seedsBought), formatNumber(snapshot.gearBought), formatNumber(snapshot.petsBought))
			elseif key == "limits" then
				label.Text = ("Inventory: %s/%s (%s free)%s"):format(formatNumber(snapshot.inventoryItems), formatNumber(snapshot.inventoryCapacity), formatNumber(snapshot.freeSlots), snapshot.inventoryFull and " FULL" or "")
			end
		end
	end
end

function getSeedRarity(seedName)
	return seedPriority[seedName] or 0
end

function readNumericMetadata(instance, keys, maxAncestors)
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

function getSortedSeedList(list)
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

function getInstanceTextBlob(instance, maxAncestors)
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

function getFruitWeight(instance)
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

function getFruitRarity(instance)
	return readNumericMetadata(instance, { "Rarity", "RarityValue", "Tier", "TierValue", "Priority", "Value" }, 5)
end

function getFruitMutationValue(instance)
	return readNumericMetadata(instance, { "MutationValue", "MutationMultiplier", "MutationPrice", "MutationWorth", "VariantValue", "VariantMultiplier" }, 5)
end

function getPromptDistance(prompt)
	local root = getRoot()
	local part = getPromptPart and getPromptPart(prompt)
	if not root or not part then
		return math.huge
	end
	return (root.Position - part.Position).Magnitude
end

function isHarvestPrompt(prompt)
	if not prompt or not prompt:IsA("ProximityPrompt") then
		return false
	end

	if prompt.Name == "StealPrompt" or prompt.ActionText == "Steal" then
		return false
	end

	return prompt.Name == "HarvestPrompt"
		or treeTextMatches(prompt, { "harvestprompt", "collect", "harvest", "pick", "fruit" }, 3)
end

function isUsableHarvestPrompt(prompt)
	if not isHarvestPrompt(prompt) then
		return false
	end

	local ok, enabled = pcall(function()
		return prompt.Enabled
	end)

	return not ok or enabled
end

function getCollectFruitTarget(prompt)
	local current = prompt and prompt.Parent

	while current and current ~= workspace do
		if current.Parent and current.Parent.Name == "Fruits" then
			return current
		end
		current = current.Parent
	end

	return prompt and prompt.Parent
end

function getFruitPlantTarget(fruit)
	local current = fruit
	while current and current ~= workspace do
		if current.Parent and current.Parent.Name == "Fruits" then
			return current.Parent.Parent
		end
		current = current.Parent
	end
	return nil
end

function collectFruitPacket(target, heavy)
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

	if sendPacket("CollectFruit", fruit) then
		return true
	end

	if not heavy then
		return false
	end

	local plant = getFruitPlantTarget(fruit)
	if fruit and sendPacket("CollectFruit", fruit.Name) then
		return true
	end

	if target ~= fruit and sendPacket("CollectFruit", target) then
		return true
	end

	if target ~= fruit and target and sendPacket("CollectFruit", target.Name) then
		return true
	end

	if plant and sendPacket("CollectFruit", plant, fruit) then
		return true
	end

	if plant and sendPacket("CollectFruit", plant.Name, fruit and fruit.Name) then
		return true
	end

	if plant and sendPacket("CollectFruit", plant.Name, fruit) then
		return true
	end

	return false
end

function collectionTookEffect(target, beforeInventoryCount)
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

function getTargetPart(target)
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

function collectPrompt(prompt)
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
		collectFruitPacket(target, true)
	end

	return collectionTookEffect(target or prompt, beforeInventoryCount)
end

function getHarvestPromptInTarget(target)
	if not target then
		return nil
	end

	local cached = harvestPromptCache[target]
	if cached ~= nil then
		if cached == false or (cached.Parent and cached:IsDescendantOf(workspace)) then
			return cached ~= false and cached or nil
		end
		harvestPromptCache[target] = nil
	end

	if target:IsA("ProximityPrompt") and isUsableHarvestPrompt(target) then
		harvestPromptCache[target] = target
		return target
	end

	if target:IsA("Model") or target:IsA("BasePart") or target:IsA("Folder") then
		for _, descendant in ipairs(target:GetDescendants()) do
			if isUsableHarvestPrompt(descendant) then
				harvestPromptCache[target] = descendant
				return descendant
			end
		end
	end

	harvestPromptCache[target] = false
	return nil
end

function getTargetDistance(target)
	local root = getRoot()
	local part = target and getTargetPart(target)
	if not root or not part then
		return math.huge
	end
	return (root.Position - part.Position).Magnitude
end

function getFruitPriority(instance)
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

function isLiveFruitEntry(entry)
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

	if not entry.prompt then
		return false
	end

	return true
end

function addFruitTarget(targets, seenTargets, prompt, target)
	if not prompt or not isUsableHarvestPrompt(prompt) then
		return
	end

	target = target or getCollectFruitTarget(prompt)
	if not target or seenTargets[prompt] then
		return
	end

	seenTargets[prompt] = true
	table.insert(targets, {
		prompt = prompt,
		target = target,
		priority = getFruitPriority(target),
	})
end

function rebuildFruitTargetCache(roots, forceDescendantRefresh)
	local targets = {}
	local seenTargets = {}

	for index, root in ipairs(roots) do
		if not root then
			continue
		end

		local scanned = 0
		local scanStartedAt = os.clock()
		if forceDescendantRefresh then
			cache["fruitFast" .. index .. "At"] = nil
		end
		local descendants = getCachedDescendants("fruitFast" .. index, root, CONFIG.fruitCacheRefreshInterval)
		for _, descendant in ipairs(descendants) do
			scanStartedAt = maybeYieldScan(scanStartedAt, 0.01)
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

function getFruitTargetBatch(roots)
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
		targets = rebuildFruitTargetCache(roots, true)
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

function pruneFruitTargetCache()
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

function collectFruitEntryFast(entry, heavy)
	if not isLiveFruitEntry(entry) then
		return false
	end

	local target = entry.target
	local prompt = entry.prompt
	if not prompt or not isUsableHarvestPrompt(prompt) then
		return false
	end

	local part = getPromptPart(prompt)

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
	if prompt then
		fired = triggerPromptFast(prompt) or fired
		task.wait(0.03)
	end

	if target then
		fired = collectFruitPacket(target) or fired
	end

	if heavy and target then
		fired = collectFruitPacket(target, true) or fired
	end

	if part and (heavy or state.collectTeleport) then
		fired = touchPart(part, state.collectTeleport) or fired
	end

	if heavy and target and not fired then
		fired = collectFruitPacket(target, true) or fired
	end

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

function activateButton(button)
	local fired = false

	if button:IsA("GuiButton") and typeof(getconnections) == "function" then
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

	if button:IsA("GuiButton") and typeof(firesignal) == "function" then
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
		task.wait(0.04)
		virtualInputManager:SendMouseButtonEvent(position.X, position.Y, 0, false, game, 1)
	end)

	return ok
end

function findSellPrompt()
	local npcs = workspace:FindFirstChild("NPCS") or workspace:FindFirstChild("NPCs")
	local steven = npcs and npcs:FindFirstChild("Steven")
	local root = steven and steven:FindFirstChild("HumanoidRootPart")
	local fallback

	for _, searchRoot in ipairs({ root, steven }) do
		if searchRoot then
			for _, descendant in ipairs(searchRoot:GetDescendants()) do
				if descendant:IsA("ProximityPrompt") then
					local text = string.lower((descendant.ActionText or "") .. " " .. (descendant.ObjectText or "") .. " " .. descendant.Name)
					local dontShow = descendant:GetAttribute("DontShow") ~= nil
					if not dontShow and string.find(text, "steven", 1, true) and string.find(text, "talk", 1, true) then
						return descendant
					end
					if not fallback and not dontShow and (string.find(text, "steven", 1, true) or string.find(text, "sell", 1, true)) then
						fallback = descendant
					end
				end
			end
		end
	end

	local map = getMap()
	local stand = map and map:FindFirstChild("Stands") and map.Stands:FindFirstChild("Sell")
	for _, searchRoot in ipairs({ stand }) do
		if searchRoot then
			for _, descendant in ipairs(searchRoot:GetDescendants()) do
				if descendant:IsA("ProximityPrompt") then
					local text = string.lower((descendant.ActionText or "") .. " " .. (descendant.ObjectText or "") .. " " .. descendant.Name)
					if string.find(text, "sell", 1, true) or string.find(text, "talk", 1, true) then
						return descendant
					end
				end
			end
		end
	end

	return fallback
end

function guiButtonText(button)
	local parts = { safeText(button.Name) }
	pcall(function()
		table.insert(parts, safeText(button.Text))
	end)

	local scanned = 0
	for _, descendant in ipairs(button:GetDescendants()) do
		if scanned >= 20 then
			break
		end
		scanned += 1
		if descendant:IsA("TextLabel") or descendant:IsA("TextButton") or descendant:IsA("TextBox") then
			table.insert(parts, safeText(descendant.Name))
			table.insert(parts, safeText(descendant.Text))
		end
	end

	return string.lower(table.concat(parts, " "))
end

function guiObjectVisible(object)
	local current = object
	while current and current ~= playerGui do
		if current:IsA("GuiObject") and not current.Visible then
			return false
		end
		current = current.Parent
	end
	return true
end

function findAncestorButton(instance)
	local current = instance
	while current and current ~= playerGui do
		if current:IsA("GuiButton") then
			return current
		end
		current = current.Parent
	end
	return nil
end

function findFirstVisibleButton(root)
	if not root then
		return nil
	end
	if root:IsA("GuiButton") and guiObjectVisible(root) then
		return root
	end
	for _, child in ipairs(root:GetDescendants()) do
		if child:IsA("GuiButton") and guiObjectVisible(child) then
			return child
		end
	end
	return nil
end

function findNearbyOptionButton(instance)
	local ancestorButton = findAncestorButton(instance)
	if ancestorButton then
		return ancestorButton
	end

	local current = instance
	while current and current ~= playerGui do
		local directButton = findFirstVisibleButton(current)
		if directButton then
			return directButton
		end
		local parent = current.Parent
		if parent and parent:IsA("GuiObject") then
			for _, sibling in ipairs(parent:GetChildren()) do
				local siblingButton = findFirstVisibleButton(sibling)
				if siblingButton then
					return siblingButton
				end
			end
		end
		current = parent
	end

	return instance:IsA("GuiObject") and instance or nil
end

function findClickableGuiObject(instance)
	return findNearbyOptionButton(instance)
end

function findSellInventoryButton()
	local ownGui = playerGui:FindFirstChild("GardenAutomationGui")
	local fallbackButton
	local scanned = 0
	for _, descendant in ipairs(playerGui:GetDescendants()) do
		if scanned >= 800 then
			break
		end
		if descendant:IsA("GuiObject") and guiObjectVisible(descendant) and (not ownGui or not descendant:IsDescendantOf(ownGui)) then
			scanned += 1
			local text
			if descendant:IsA("GuiButton") then
				text = guiButtonText(descendant)
			elseif descendant:IsA("TextLabel") or descendant:IsA("TextBox") then
				text = string.lower(safeText(descendant.Name) .. " " .. safeText(descendant.Text))
			else
				text = string.lower(safeText(descendant.Name))
			end
			local button = findClickableGuiObject(descendant)
			if string.find(text, "sell inventory", 1, true)
				or string.find(text, "sell my inventory", 1, true)
				or string.find(text, "sell all my", 1, true)
				or string.find(text, "inventory", 1, true) and string.find(text, "sell", 1, true)
			then
				return button
			end
			if not fallbackButton
				and (string.find(text, "sell my inventory", 1, true)
					or string.find(text, "sell all", 1, true)
					or string.find(text, "i want to sell", 1, true))
			then
				fallbackButton = button
			end
		end
	end

	return fallbackButton
end

function clickSellInventoryButton(timeoutSeconds)
	local startedAt = os.clock()
	repeat
		local button = findSellInventoryButton()
		if button and activateButton(button) then
			setStatus("Sell: clicked Sell Inventory option")
			return 1
		end
		task.wait(0.08)
	until not timeoutSeconds or timeoutSeconds <= 0 or os.clock() - startedAt >= timeoutSeconds
	setStatus("Sell: Sell Inventory option not found")
	return 0
end

function getControllerModule(pathNames)
	local current = localPlayer:FindFirstChild("PlayerScripts")
	for _, name in ipairs(pathNames) do
		current = current and current:FindFirstChild(name)
	end
	if current and current:IsA("ModuleScript") then
		local ok, module = pcall(require, current)
		if ok then
			return module
		end
	end
	return nil
end

function callSellFunctionsIn(value, seen)
	if type(value) ~= "table" then
		return 0
	end
	seen = seen or {}
	if seen[value] then
		return 0
	end
	seen[value] = true

	local actions = 0
	for key, child in pairs(value) do
		local name = string.lower(tostring(key))
		if type(child) == "function" then
			if string.find(name, "sell", 1, true)
				and (string.find(name, "inventory", 1, true)
					or string.find(name, "all", 1, true)
					or string.find(name, "fruit", 1, true))
			then
				if pcall(child, value) then
					actions += 1
				end
				if pcall(child) then
					actions += 1
				end
			end
		elseif type(child) == "table" then
			actions += callSellFunctionsIn(child, seen)
		end
	end
	return actions
end

function callSellControllerFallback()
	local actions = 0
	for _, path in ipairs({
		{ "Controllers", "NPCController", "Sell_Steven" },
		{ "Controllers", "NPCController" },
		{ "Controllers", "NPCDialogueController" },
	}) do
		local module = getControllerModule(path)
		actions += callSellFunctionsIn(module)
	end
	return actions
end

function sellViaStevenDialogue(allowTeleport)
	local prompt = findSellPrompt()
	if not prompt then
		return callSellControllerFallback()
	end

	local part = getPromptPart(prompt)
	if part then
		local root = getRoot()
		local maxDistance = prompt.MaxActivationDistance or 10
		if root and (root.Position - part.Position).Magnitude > maxDistance + 2 and not allowTeleport then
			return 0
		end
		if (not root or (root.Position - part.Position).Magnitude > math.max(maxDistance - 2, 6)) and allowTeleport then
			teleportToPart(part, 3)
			task.wait(0.15)
		end
	end

	local root = getRoot()
	if part and root and (root.Position - part.Position).Magnitude > ((prompt.MaxActivationDistance or 10) + 3) then
		return 0
	end

	local actions = 0
	for _ = 1, 2 do
		if triggerPrompt(prompt, true) then
			actions += 1
		end
		task.wait(0.25)
		local clicked = clickSellInventoryButton(1.2)
		actions += clicked
		if clicked > 0 then
			break
		end
	end

	if actions <= 0 then
		actions += callSellControllerFallback()
	end

	return actions
end

function sellSucceeded(beforeInventoryCount, beforeSheckles)
	local currentInventoryCount = countInventoryTools()
	local currentSheckles = refreshCurrencyStats(true)
	return currentInventoryCount < beforeInventoryCount
		or (currentSheckles and beforeSheckles and currentSheckles > beforeSheckles),
		currentInventoryCount,
		currentSheckles
end

function sellThroughStevenFallback(allowTeleport)
	return sellViaStevenDialogue(allowTeleport)
end

function moveToStevenForSell(allowTeleport)
	local prompt = findSellPrompt()
	if not prompt then
		return false, nil
	end

	local part = getPromptPart(prompt)
	if not part then
		return false, prompt
	end

	local root = getRoot()
	local maxDistance = prompt.MaxActivationDistance or 10
	if not root or (root.Position - part.Position).Magnitude > math.max(maxDistance - 2, 6) then
		if not allowTeleport then
			return false, prompt
		end
		teleportToPart(part, 3)
		task.wait(0.15)
	end

	return true, prompt
end

function collectFruit()
	if not isEnabled("fruitCollector") then
		return
	end

	local inventoryFull = shouldPauseFruitCollection()
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
		fruitTargetCache.refreshedAt = 0
		targets = rebuildFruitTargetCache(roots, true)
		totalCached = #targets
	end

	if #targets == 0 then
		updateStatsUI()
		setStatus(("Fruit collector: no harvest targets found (%d root(s))"):format(#roots))
		return
	end

	local beforeInventoryCount = countInventoryTools()
	local fired = 0
	local fallback = 0
	local fallbackLimit = CONFIG.maxFruitPromptFallbackPerTick
	if fruitTargetCache.noGainStreak >= 1 then
		fallbackLimit = math.min(math.ceil(CONFIG.maxFruitCollectPerTick / 2), fallbackLimit + 10)
	end
	if fruitTargetCache.noGainStreak >= 2 then
		fallbackLimit = CONFIG.maxFruitCollectPerTick
	end

	local heavyFallback = fruitTargetCache.noGainStreak >= 1
	for index, entry in ipairs(targets) do
		if not isEnabled("fruitCollector") then
			return
		end
		if shouldPauseFruitCollection() then
			stats.collectSkippedFull += 1
			setStatus(("Fruit collector paused: sell needed (%d/%d)"):format(stats.inventoryItems, stats.inventoryCapacity))
			return
		end

		if fallback < fallbackLimit and isLiveFruitEntry(entry) and (entry.prompt or heavyFallback) then
			if collectFruitEntryFast(entry, heavyFallback) then
				fallback += 1
				fired += 1
			end
		end

		if index % 8 == 0 then
			task.wait()
		end
	end

	task.wait(0.08)
	local afterInventoryCount = countInventoryTools()
	local gained = math.max((afterInventoryCount or 0) - (beforeInventoryCount or 0), 0)
	stats.fruitCollected += gained
	stats.fruitTargetsChecked += totalCached
	if gained > 0 then
		fruitTargetCache.noGainStreak = 0
	else
		fruitTargetCache.noGainStreak = math.min(fruitTargetCache.noGainStreak + 1, 3)
	end
	pruneFruitTargetCache()
	refreshInventoryStats()
	updateStatsUI()
	if fired == 0 and fallback == 0 then
		fruitTargetCache.refreshedAt = 0
		setStatus(("Fruit collector: found %d cached target(s), failed to trigger"):format(totalCached))
	else
		setStatus(("Fruit collector: prompt-only %d/%d, inventory +%d"):format(fallback, #targets, gained))
	end
end

function findSeedTool(seedName, shouldEquip)
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

function getEquippedSeedTool(seedName)
	return findSeedTool(seedName, true)
end

function getSeedToolAmount(tool)
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

function getSelectedSeedList()
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

function countPlacedSeed(seedName)
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

function countGardenPlants()
	local count = 0
	for _, root in ipairs(getOwnGardenRoots()) do
		local plants = root:FindFirstChild("Plants") or root:FindFirstChild("Crops")
		if plants then
			for _, child in ipairs(plants:GetChildren()) do
				if child:IsA("Model") or child:IsA("Folder") or child:IsA("BasePart") then
					count += 1
				end
			end
		end
	end
	return count
end

function canPlaceSeed(seedName)
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

function getSeedPlantPosition(index, center)
	local root = getRoot()
	if not root then
		return nil
	end

	local step = math.max(index or 1, 1)
	local basePosition = center or root.Position
	local offset

	if CONFIG.seedPlacementMode == "Saved Position" and type(CONFIG.savedPlantPosition) == "table" then
		basePosition = Vector3.new(
			tonumber(CONFIG.savedPlantPosition.x) or basePosition.X,
			tonumber(CONFIG.savedPlantPosition.y) or basePosition.Y,
			tonumber(CONFIG.savedPlantPosition.z) or basePosition.Z
		)
		offset = Vector3.new(0, CONFIG.undergroundStacking and (-0.05 * (step - 1)) or (0.03 * (step - 1)), 0)
	elseif CONFIG.seedPlacementMode == "Farm Corner" then
		local direction = Vector3.new((step % 2 == 0) and 1 or -1, 0, (math.floor(step / 2) % 2 == 0) and 1 or -1)
		local ring = math.ceil(math.sqrt(step))
		local row = (step - 1) % ring
		local column = math.floor((step - 1) / ring)
		local corner = Vector3.new(direction.X * CONFIG.plantRadius, 0, direction.Z * CONFIG.plantRadius)
		offset = corner - Vector3.new(direction.X * row * 3.2, 0, direction.Z * column * 3.2)
	else
		local rng = Random.new()
		local angle = rng:NextNumber(0, math.pi * 2)
		local radius = math.sqrt(rng:NextNumber()) * CONFIG.plantRadius
		offset = Vector3.new(math.cos(angle), 0, math.sin(angle)) * radius
	end

	local origin = basePosition + offset + Vector3.new(0, 12, 0)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { getCharacter() }

	local result = workspace:Raycast(origin, Vector3.new(0, -80, 0), params)
	if result then
		local position = result.Position
		if CONFIG.seedPlacementMode == "Saved Position" and CONFIG.undergroundStacking then
			position += Vector3.new(0, -0.35 - (step * 0.03), 0)
		end
		return position
	end

	return basePosition + offset
end

function tryPlantSeedRemote(seedName, position)
	local attempts = 0
	local cframe = CFrame.new(position)
	local unpackArgs = table.unpack or unpack

	for _, args in ipairs({
		{ seedName, position },
		{ position, seedName },
		{ seedName, cframe },
	}) do
		attempts += 1
		sendPacket("PlantSeed", unpackArgs(args))
	end

	return attempts
end

function moveToOwnGarden()
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

function toolHasValue(item, keys)
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

function toolNameMatchesList(item, list)
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

function isKnownGearTool(item)
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

function isKnownPetTool(item)
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

function isLikelyFruitTool(item)
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

	return true
end

function getSellableFruitTools()
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

function getSelectedGearList()
	local selected = {}

	for _, gearName in ipairs(gearNames) do
		if selectedGears[gearName] then
			table.insert(selected, gearName)
		end
	end

	return selected
end

function getSeedFrame(seedName)
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

function getGearFrame(gearName)
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

function getSelectedPetList()
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

function purchaseSeedRemote(seedName)
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
		local scanStartedAt = os.clock()
		for _, descendant in ipairs(getCachedDescendants("rainbow" .. rootIndex, root, CONFIG.dropCacheRefreshInterval)) do
			scanStartedAt = maybeYieldScan(scanStartedAt, 0.01)
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

performanceState = {
	optimized = setmetatable({}, { __mode = "k" }),
	hidden = setmetatable({}, { __mode = "k" }),
	watcherConnected = false,
	queue = {},
	queueHead = 1,
	queueRunning = false,
	fullScanDone = false,
	lastTreeScanAt = 0,
	lastGardenHideAt = 0,
}

function isLaggyEffectInstance(instance)
	return instance:IsA("ParticleEmitter")
		or instance:IsA("Trail")
		or instance:IsA("Beam")
		or instance:IsA("Smoke")
		or instance:IsA("Fire")
		or instance:IsA("Sparkles")
		or instance:IsA("PointLight")
		or instance:IsA("SpotLight")
		or instance:IsA("SurfaceLight")
		or instance:IsA("Highlight")
		or instance:IsA("Explosion")
		or instance:IsA("ForceField")
		or instance:IsA("Sound")
		or instance:IsA("ReverbSoundEffect")
		or instance:IsA("ChorusSoundEffect")
		or instance:IsA("DistortionSoundEffect")
		or instance:IsA("EchoSoundEffect")
		or instance:IsA("FlangeSoundEffect")
		or instance:IsA("EqualizerSoundEffect")
		or instance:IsA("PitchShiftSoundEffect")
		or instance:IsA("CompressorSoundEffect")
end

function disableLaggyEffect(instance)
	local changed = 0
	if not instance or performanceState.optimized[instance] then
		return changed
	end

	if isLaggyEffectInstance(instance) then
		performanceState.optimized[instance] = true
		pcall(function()
			if instance:IsA("Sound") then
				instance.Volume = 0
				instance.Playing = false
			elseif instance:IsA("Explosion") then
				instance.BlastPressure = 0
				instance.BlastRadius = 0
			end
		end)
		pcall(function()
			instance.Enabled = false
		end)
		pcall(function()
			instance.Visible = false
		end)
		changed = 1
	elseif instance:IsA("PostEffect")
		or instance:IsA("BloomEffect")
		or instance:IsA("BlurEffect")
		or instance:IsA("ColorCorrectionEffect")
		or instance:IsA("DepthOfFieldEffect")
		or instance:IsA("SunRaysEffect")
	then
		performanceState.optimized[instance] = true
		pcall(function()
			instance.Enabled = false
		end)
		changed = 1
	end

	return changed
end

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
	while current and current ~= workspace do
		if current == plot then
			return false
		end
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

function hidePerformanceTree(instance, hidePrompts)
	return hidePerformanceVisual(instance, hidePrompts)
end

function hidePerformanceVisual(instance, hidePrompts)
	if not instance or performanceState.hidden[instance] then
		return 0
	end

	local changed = 0
	changed += disableLaggyEffect(instance)
	if instance:IsA("BasePart") then
		performanceState.hidden[instance] = true
		pcall(function()
			instance.LocalTransparencyModifier = 1
			instance.CastShadow = false
		end)
		changed = 1
	elseif instance:IsA("Decal") or instance:IsA("Texture") then
		performanceState.hidden[instance] = true
		pcall(function()
			instance.Transparency = 1
		end)
		changed = 1
	elseif instance:IsA("BillboardGui")
		or instance:IsA("SurfaceGui")
		or instance:IsA("Highlight")
		or instance:IsA("SelectionBox")
		or instance:IsA("SelectionSphere")
		or instance:IsA("Handles")
		or instance:IsA("ArcHandles")
	then
		performanceState.hidden[instance] = true
		pcall(function()
			instance.Enabled = false
		end)
		changed = 1
	elseif hidePrompts and instance:IsA("ProximityPrompt") then
		performanceState.hidden[instance] = true
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
			return hidePerformanceTree(instance, false)
		end
		return 0
	end

	return hidePerformanceTree(instance, true)
end

function hidePerformanceGardenPlot(plot)
	if not plot then
		return 0
	end

	local changed = 0
	local ownPlot = gardenPlotIsOwn(plot)
	if ownPlot then
		for _, name in ipairs({ "Plants", "Fruits", "Fruit", "Crops", "Harvest", "Harvests" }) do
			local folder = plot:FindFirstChild(name, true)
			if folder then
				changed += hidePerformanceTree(folder, false)
				local processed = 0
				for _, descendant in ipairs(folder:GetDescendants()) do
					changed += hidePerformanceTree(descendant, false)
					processed += 1
					if processed % 120 == 0 then
						task.wait()
					end
				end
			end
		end
		return changed
	end

	changed += hidePerformanceTree(plot, true)
	local processed = 0
	for _, descendant in ipairs(plot:GetDescendants()) do
		changed += hidePerformanceTree(descendant, true)
		processed += 1
		if processed % 120 == 0 then
			task.wait()
		end
	end

	return changed
end

function hidePerformanceGardens()
	local gardens = getGardens()
	if not gardens then
		return 0
	end

	local changed = 0
	for _, plot in ipairs(gardens:GetChildren()) do
		changed += hidePerformanceGardenPlot(plot)
		task.wait()
	end
	return changed
end

function optimizePerformanceInstance(instance)
	if not instance then
		return 0
	end

	local changed = 0
	if state.performanceMode then
		changed = applyPerformanceGardenHiding(instance)
	end
	if not state.performanceMode then
		return changed
	end

	if performanceState.optimized[instance] then
		return changed
	end

	changed += disableLaggyEffect(instance)
	if performanceState.optimized[instance] then
		return changed
	end

	if instance:IsA("BasePart") then
		performanceState.optimized[instance] = true
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
		performanceState.optimized[instance] = true
		pcall(function()
			instance.Transparency = 1
		end)
		changed = 1
	elseif instance:IsA("BillboardGui")
		or instance:IsA("SurfaceGui")
		or instance:IsA("Highlight")
		or instance:IsA("SelectionBox")
		or instance:IsA("SelectionSphere")
		or instance:IsA("Handles")
		or instance:IsA("ArcHandles")
	then
		performanceState.optimized[instance] = true
		pcall(function()
			instance.Enabled = false
		end)
		changed = 1
	elseif instance:IsA("Animator") then
		performanceState.optimized[instance] = true
		pcall(function()
			for _, track in ipairs(instance:GetPlayingAnimationTracks()) do
				track:Stop(0)
			end
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
	if performanceState.watcherConnected then
		return
	end

	performanceState.watcherConnected = true
	workspace.DescendantAdded:Connect(function(descendant)
		if state.performanceMode then
			if #performanceState.queue - performanceState.queueHead < 800 then
				performanceState.queue[#performanceState.queue + 1] = descendant
			end
			if not performanceState.queueRunning then
				performanceState.queueRunning = true
				task.spawn(function()
					while state.performanceMode and performanceState.queueHead <= #performanceState.queue do
						for _ = 1, 18 do
							local item = performanceState.queue[performanceState.queueHead]
							performanceState.queue[performanceState.queueHead] = nil
							performanceState.queueHead += 1
							if not item then
								break
							end
							optimizePerformanceInstance(item)
						end
						if performanceState.queueHead > 300 then
							local compacted = {}
							for index = performanceState.queueHead, #performanceState.queue do
								compacted[#compacted + 1] = performanceState.queue[index]
							end
							performanceState.queue = compacted
							performanceState.queueHead = 1
						end
						task.wait(0.15)
					end
					if performanceState.queueHead > #performanceState.queue then
						performanceState.queue = {}
						performanceState.queueHead = 1
					end
					performanceState.queueRunning = false
				end)
			end
		end
	end)
end

enablePerformanceMode = function()
	local changed = 0
	local now = os.clock()

	connectPerformanceWatcher()

	pcall(function()
		settings().Rendering.QualityLevel = Enum.QualityLevel.Level01
	end)

	pcall(function()
		local lighting = game:GetService("Lighting")
		lighting.GlobalShadows = false
		lighting.EnvironmentDiffuseScale = 0
		lighting.EnvironmentSpecularScale = 0
		lighting.Brightness = math.min(lighting.Brightness, 1)
		for _, descendant in ipairs(lighting:GetDescendants()) do
			changed += optimizePerformanceInstance(descendant)
		end
	end)

	pcall(function()
		local soundService = game:GetService("SoundService")
		for _, descendant in ipairs(soundService:GetDescendants()) do
			changed += optimizePerformanceInstance(descendant)
		end
	end)

	pcall(function()
		workspace.Terrain.WaterWaveSize = 0
		workspace.Terrain.WaterWaveSpeed = 0
		workspace.Terrain.WaterReflectance = 0
		workspace.Terrain.WaterTransparency = 1
		workspace.Terrain.Decoration = false
	end)

	if now - performanceState.lastGardenHideAt > 5 then
		performanceState.lastGardenHideAt = now
		changed += hidePerformanceGardens()
	end

	if not performanceState.fullScanDone and now - performanceState.lastTreeScanAt > 10 then
		performanceState.lastTreeScanAt = now
		performanceState.fullScanDone = true
		changed += optimizePerformanceTree(workspace, 220)
	end

	setStatus(("Performance mode: simplified %d object(s)"):format(changed))
end

function schedulePerformanceModeRestore()
	if not state.performanceMode then
		return
	end

	task.spawn(function()
		for _, delaySeconds in ipairs({ 0, 1.5, 4, 8 }) do
			if delaySeconds > 0 then
				task.wait(delaySeconds)
			end
			if state.performanceMode then
				enablePerformanceMode()
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
	local gardenPlantCount = countGardenPlants()

	if gardenPlantCount >= CONFIG.maxGardenPlants then
		stats.seedsSkippedLimit += 1
		updateStatsUI()
		setStatus(("Seed placer: garden plant limit reached (%d/%d)"):format(gardenPlantCount, CONFIG.maxGardenPlants))
		return
	end

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
				if planted >= CONFIG.maxSeedPlantPerTick or gardenPlantCount + planted >= CONFIG.maxGardenPlants then
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

	local seedCache = plantPromptTextCache[plant]
	if not seedCache then
		seedCache = {}
		plantPromptTextCache[plant] = seedCache
	elseif seedCache[seedName] ~= nil then
		return seedCache[seedName]
	end

	local lowered = string.lower(seedName)
	local compactSeed = string.gsub(lowered, "[%s_%-]", "")
	for _, descendant in ipairs(plant:GetDescendants()) do
		if descendant:IsA("ProximityPrompt") and descendant.Name ~= "StealPrompt" then
			local text = string.lower((descendant.ObjectText or "") .. " " .. (descendant.ActionText or "") .. " " .. descendant.Name)
			local compactText = string.gsub(text, "[%s_%-]", "")
			if string.find(text, lowered, 1, true) or string.find(compactText, compactSeed, 1, true) then
				seedCache[seedName] = true
				return true
			end
		end
	end

	seedCache[seedName] = false
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

	local cached = shovelPromptCache[target]
	if cached ~= nil then
		if cached == false or (cached.Parent and cached:IsDescendantOf(workspace)) then
			return cached ~= false and cached or nil
		end
		shovelPromptCache[target] = nil
	end

	if target:IsA("ProximityPrompt") then
		local text = string.lower((target.ActionText or "") .. " " .. (target.ObjectText or "") .. " " .. target.Name)
		if string.find(text, "shovel", 1, true)
			or string.find(text, "remove", 1, true)
			or string.find(text, "delete", 1, true)
			or string.find(text, "dig", 1, true)
		then
			shovelPromptCache[target] = target
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
				shovelPromptCache[target] = descendant
				return descendant
			end
		end
	end

	shovelPromptCache[target] = false
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
		local scanStartedAt = os.clock()
		for _, descendant in ipairs(getCachedDescendants("shovelPlants" .. index, root, CONFIG.cacheRefreshInterval)) do
			scanStartedAt = maybeYieldScan(scanStartedAt, 0.01)
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

	local inventoryFull = refreshInventoryStats(true)
	local beforeInventoryCount = countInventoryTools()
	local sellableTools = getSellableFruitTools()
	if #sellableTools <= 0 then
		refreshInventoryStats(true)
		if not force then
			setStatus("Sell: nothing to sell")
		else
			setStatus(("Sell: inventory empty (%d/%d)"):format(stats.inventoryItems, stats.inventoryCapacity))
		end
		return
	end

	local beforeSheckles = refreshCurrencyStats(true)
	local farmedBeforeSell = stats.shecklesFarmed or 0
	local actions = 0
	local allowTeleport = force == true or state.autoSell == true or inventoryFull == true
	local movedToSteven = false

	for attempt = 1, 4 do
		if not force and not isEnabled("autoSell") then
			return
		end

		if attempt == 1 or not movedToSteven then
			movedToSteven = select(1, moveToStevenForSell(allowTeleport))
		end

		if movedToSteven then
			actions += sellViaStevenDialogue(false)
			task.wait(0.45)
			local sold = sellSucceeded(beforeInventoryCount, beforeSheckles)
			if sold then
				break
			end
			actions += callSellControllerFallback()
			task.wait(0.35)
			sold = sellSucceeded(beforeInventoryCount, beforeSheckles)
			if sold then
				break
			end
		end

		local ok, count = sendExactPacket("PreviewSellAll")
		if ok then
			actions += count or 1
		end
		task.wait(0.08)
		ok, count = sendExactPacket("SellAll")
		if ok then
			actions += count or 1
		end

		task.wait(0.35)
		local sold = sellSucceeded(beforeInventoryCount, beforeSheckles)
		if sold then
			break
		end

		if movedToSteven then
			for _, tool in ipairs(getSellableFruitTools()) do
				if not tool or not tool.Parent then
					continue
				end
				ok, count = sendExactPacket("SellItem", tool)
				if ok then
					actions += count or 1
				end
				ok, count = sendExactPacket("SellFruit", tool)
				if ok then
					actions += count or 1
				end
			end
			task.wait(0.3)
			sold = sellSucceeded(beforeInventoryCount, beforeSheckles)
			if sold then
				break
			end
		end

		if #getSellableFruitTools() == 0 then
			break
		end
	end

	task.wait(0.15)
	local afterSheckles = refreshCurrencyStats(true)
	if afterSheckles and beforeSheckles and afterSheckles > beforeSheckles then
		stats.shecklesFarmed = math.max(stats.shecklesFarmed or 0, farmedBeforeSell + (afterSheckles - beforeSheckles))
	end

	refreshInventoryStats(true)
	local afterInventoryCount = countInventoryTools()
	updateStatsUI()
	if afterInventoryCount >= beforeInventoryCount and (not afterSheckles or not beforeSheckles or afterSheckles <= beforeSheckles) then
		setStatus(("Sell failed: remote/NPC fallback made no change (%d/%d)"):format(stats.inventoryItems, stats.inventoryCapacity))
	else
		setStatus(("Sell: inventory %d -> %d"):format(beforeInventoryCount, afterInventoryCount))
	end
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

		local beforeInventoryCount = countInventoryTools()
		local beforeSheckles = refreshCurrencyStats(true)
		local ok, message = buyOneSeed(seedName)
		lastMessage = message
		if ok then
			local changed = purchaseChanged(beforeInventoryCount, beforeSheckles)
			if changed then
				bought += 1
			else
				lastMessage = "Auto buy: no verified seed purchase for " .. seedName
			end
		end
		attempts += 1
		task.wait()
	end

	if bought > 0 then
		stats.seedsBought += bought
		refreshInventoryStats()
		updateStatsUI()
		setStatus(("Auto buy: verified %d seed purchase(s) across %d attempt(s)"):format(bought, attempts))
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

	local bought = 0
	local lastMessage = "Auto gear: no gear selected"

	for _, gearName in ipairs(getSelectedGearList()) do
		if not isEnabled("autoBuyGear") then
			return
		end

		local beforeInventoryCount = countInventoryTools()
		local beforeSheckles = refreshCurrencyStats(true)
		local ok, message = buyOneGear(gearName)
		lastMessage = message
		if ok then
			local changed = purchaseChanged(beforeInventoryCount, beforeSheckles)
			if changed then
				bought += 1
			else
				lastMessage = "Auto gear: no verified purchase for " .. gearName
			end
			task.wait(0.12)
		end
	end

	if bought > 0 then
		stats.gearBought += bought
		refreshInventoryStats()
		updateStatsUI()
		setStatus(("Auto gear: verified %d purchase(s)"):format(bought))
	else
		setStatus(lastMessage)
	end
end

function petSpawnHandled(model, prompt)
	local now = os.clock()
	local handledUntil = handledPetSpawns[model] or handledPetSpawns[prompt]
	if handledUntil and now < handledUntil then
		return true
	end
	if prompt and (not prompt.Parent or not prompt:IsDescendantOf(workspace)) then
		return true
	end
	if model and (not model.Parent or not model:IsDescendantOf(workspace)) then
		return true
	end
	local ok, enabled = pcall(function()
		return prompt.Enabled
	end)
	return ok and enabled == false
end

function markPetSpawnHandled(model, prompt, seconds)
	local untilTime = os.clock() + (seconds or 20)
	if model then
		handledPetSpawns[model] = untilTime
	end
	if prompt then
		handledPetSpawns[prompt] = untilTime
	end
	cache.wildPetsAt = 0
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

		if descendant:IsA("ProximityPrompt") and descendant.Parent and descendant:IsDescendantOf(workspace) then
			local model = descendant:FindFirstAncestorWhichIsA("Model")
			if petSpawnHandled(model, descendant) then
				continue
			end

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
					markPetSpawnHandled(model, descendant, 25)
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

		local beforeInventoryCount = countInventoryTools()
		local beforeSheckles = refreshCurrencyStats(true)
		local ok, message = buyOnePet(petName)
		lastMessage = message
		if ok then
			local changed = purchaseChanged(beforeInventoryCount, beforeSheckles)
			if changed then
				bought += 1
			else
				lastMessage = "Auto pets: no verified purchase for " .. petName
			end
			task.wait(0.12)
		end
	end

	if bought > 0 then
		stats.petsBought += bought
		refreshInventoryStats()
		updateStatsUI()
		setStatus(("Auto pets: verified %d purchase(s)"):format(bought))
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
		TextSize = 10,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Size = UDim2.new(1, 0, 0, 20),
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

	row.CanvasSize = UDim2.fromOffset(0, math.max(1, math.ceil(visible / (columns or 2))) * 23)
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
	Size = UDim2.fromOffset(280, 430),
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
	TextSize = 14,
	Size = UDim2.new(1, 0, 0, 30),
}, panel)
make("UICorner", { CornerRadius = UDim.new(0, 8) }, header)

local content = make("ScrollingFrame", {
	Name = "Content",
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	CanvasSize = UDim2.fromOffset(0, 0),
	Position = UDim2.fromOffset(8, 38),
	ScrollBarThickness = 4,
	Size = UDim2.new(1, -16, 1, -46),
}, panel)
local contentLayout = make("UIListLayout", {
	Padding = UDim.new(0, 4),
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
	TextSize = 10,
	TextWrapped = true,
	TextXAlignment = Enum.TextXAlignment.Left,
	Size = UDim2.new(1, 0, 0, 28),
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

function makeToggle(label, key, order)
	local enabled = state[key] == true
	local button = make("TextButton", {
		Name = key,
		AutoButtonColor = false,
		BackgroundColor3 = enabled and Color3.fromRGB(58, 111, 67) or Color3.fromRGB(34, 41, 42),
		BorderSizePixel = 0,
		Font = Enum.Font.GothamSemibold,
		Text = ("%s: %s"):format(label, enabled and "ON" or "OFF"),
		TextColor3 = Color3.fromRGB(235, 244, 233),
		TextSize = 11,
		TextWrapped = true,
		Size = UDim2.new(1, 0, 0, 24),
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
		end
	end)
end

function makeSectionLabel(text, order)
	return make("TextLabel", {
		Name = string.gsub(text, "%s+", "") .. "Section",
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamSemibold,
		Text = text,
		TextColor3 = Color3.fromRGB(174, 211, 178),
		TextSize = 10,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, 0, 0, 12),
		LayoutOrder = order,
	}, content)
end

function makeCommandButton(label, order, onClick)
	local button = make("TextButton", {
		Name = string.gsub(label, "%s+", "") .. "Button",
		AutoButtonColor = false,
		BackgroundColor3 = Color3.fromRGB(34, 41, 42),
		BorderSizePixel = 0,
		Font = Enum.Font.GothamSemibold,
		Text = label,
		TextColor3 = Color3.fromRGB(235, 244, 233),
		TextSize = 11,
		TextWrapped = true,
		Size = UDim2.new(1, 0, 0, 24),
		LayoutOrder = order,
	}, content)
	make("UICorner", { CornerRadius = UDim.new(0, 6) }, button)
	button.Activated:Connect(onClick)
	return button
end

makeSectionLabel("Priority", 1)
makeToggle("Auto Buy Pets", "autoBuyPets", 2)
makeToggle("Collect Gold/Rainbow Drops", "autoCollectRainbowSeeds", 3)
makeSectionLabel("Farm", 4)
makeToggle("Fruit Collector", "fruitCollector", 5)
makeToggle("Teleport To Fruit", "collectTeleport", 6)
makeToggle("Seed Placer", "seedPlacer", 7)
makeToggle("Auto Shovel Plants", "autoShovel", 8)
local placementModes = { "Farm Corner", "Random", "Saved Position" }
local placementButton
placementButton = makeCommandButton("Placement Mode: " .. CONFIG.seedPlacementMode, 9, function()
	local currentIndex = 1
	for index, mode in ipairs(placementModes) do
		if mode == CONFIG.seedPlacementMode then
			currentIndex = index
			break
		end
	end
	CONFIG.seedPlacementMode = placementModes[(currentIndex % #placementModes) + 1]
	placementButton.Text = "Placement Mode: " .. CONFIG.seedPlacementMode
	saveConfig()
	setStatus("Seed placement mode: " .. CONFIG.seedPlacementMode)
end)
makeCommandButton("Save Plant Position", 10, function()
	local root = getRoot()
	if root then
		CONFIG.savedPlantPosition = { x = root.Position.X, y = root.Position.Y, z = root.Position.Z }
		CONFIG.seedPlacementMode = "Saved Position"
		placementButton.Text = "Placement Mode: " .. CONFIG.seedPlacementMode
		saveConfig()
		setStatus("Saved current position for seed placement")
	end
end)
makeCommandButton("Underground Stacking: " .. (CONFIG.undergroundStacking and "ON" or "OFF"), 11, function()
	CONFIG.undergroundStacking = not CONFIG.undergroundStacking
	saveConfig()
	setStatus("Underground stacking " .. (CONFIG.undergroundStacking and "enabled" or "disabled"))
	buildUI()
end)
makeCommandButton(("Max Garden Plants: %d"):format(CONFIG.maxGardenPlants), 12, function()
	CONFIG.maxGardenPlants += 50
	if CONFIG.maxGardenPlants > 1000 then
		CONFIG.maxGardenPlants = 100
	end
	saveConfig()
	setStatus(("Max garden plants set to %d"):format(CONFIG.maxGardenPlants))
	buildUI()
end)
makeToggle("Auto Sell Inventory", "autoSell", 13)
makeToggle("Sell When Backpack Full", "sellWhenFull", 14)
makeSectionLabel("Shops", 15)
makeToggle("Auto Buy Seeds", "autoBuySeeds", 16)
makeToggle("Auto Buy Gear", "autoBuyGear", 17)
makeToggle("Performance Mode", "performanceMode", 18)

local webhookBox = make("TextBox", {
	Name = "WebhookUrl",
	BackgroundColor3 = Color3.fromRGB(34, 41, 42),
	BorderSizePixel = 0,
	ClearTextOnFocus = false,
	Font = Enum.Font.GothamSemibold,
	PlaceholderText = "Webhook URL for selected stock/pets",
	Text = CONFIG.webhookUrl,
	TextColor3 = Color3.fromRGB(242, 247, 239),
	TextSize = 10,
	TextTruncate = Enum.TextTruncate.AtEnd,
	Size = UDim2.new(1, 0, 0, 24),
	LayoutOrder = 21,
}, content)
make("UICorner", { CornerRadius = UDim.new(0, 6) }, webhookBox)
make("UIPadding", {
	PaddingLeft = UDim.new(0, 10),
	PaddingRight = UDim.new(0, 10),
}, webhookBox)
webhookBox.FocusLost:Connect(function()
	CONFIG.webhookUrl = string.gsub(tostring(webhookBox.Text or ""), "^%s*(.-)%s*$", "%1")
	webhookBox.Text = CONFIG.webhookUrl
	saveConfig()
	setStatus(CONFIG.webhookUrl ~= "" and "Webhook URL saved" or "Webhook URL cleared")
	if CONFIG.webhookUrl ~= "" then
		sendStatsWebhook(true)
	end
end)

local statsTitle = make("TextLabel", {
	Name = "StatsTitle",
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamSemibold,
	Text = "Session Stats",
	TextColor3 = Color3.fromRGB(221, 236, 216),
	TextSize = 11,
	TextXAlignment = Enum.TextXAlignment.Left,
	Size = UDim2.new(1, 0, 0, 12),
	LayoutOrder = 22,
}, content)

local statsFrame = make("Frame", {
	Name = "Stats",
	BackgroundColor3 = Color3.fromRGB(14, 18, 19),
	BorderSizePixel = 0,
	Size = UDim2.new(1, 0, 0, 94),
	LayoutOrder = 23,
}, content)
make("UICorner", { CornerRadius = UDim.new(0, 6) }, statsFrame)
make("UIPadding", {
	PaddingTop = UDim.new(0, 4),
	PaddingBottom = UDim.new(0, 4),
	PaddingLeft = UDim.new(0, 8),
	PaddingRight = UDim.new(0, 8),
}, statsFrame)
make("UIListLayout", {
	Padding = UDim.new(0, 2),
	SortOrder = Enum.SortOrder.LayoutOrder,
}, statsFrame)

function makeStatsLabel(key, order)
	local label = make("TextLabel", {
		Name = key,
		BackgroundTransparency = 1,
		Font = Enum.Font.Gotham,
		Text = "",
		TextColor3 = Color3.fromRGB(201, 219, 202),
		TextSize = 10,
		TextTruncate = Enum.TextTruncate.AtEnd,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, 0, 0, 12),
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

function buildSeedSelector()
local selectedSeedLabel = make("TextLabel", {
	Name = "SelectedSeedLabel",
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamSemibold,
	Text = "Seeds to buy",
	TextColor3 = Color3.fromRGB(221, 236, 216),
	TextSize = 11,
	TextXAlignment = Enum.TextXAlignment.Left,
	Size = UDim2.new(1, 0, 0, 12),
	LayoutOrder = 24,
}, content)

local seedRow = make("ScrollingFrame", {
	Name = "SeedSelector",
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	CanvasSize = UDim2.fromOffset(0, 0),
	ScrollBarThickness = 4,
	ScrollingDirection = Enum.ScrollingDirection.Y,
	Size = UDim2.new(1, 0, 0, 54),
	LayoutOrder = 26,
}, content)
make("UIGridLayout", {
	CellPadding = UDim2.fromOffset(4, 4),
	CellSize = UDim2.fromOffset(128, 20),
	SortOrder = Enum.SortOrder.LayoutOrder,
}, seedRow)

local seedLayout = seedRow:FindFirstChildOfClass("UIGridLayout")
local seedButtons = {}
local seedButtonCount = 0
local seedFilterText = ""

makeSelectorSearch(content, 25, "Search seeds to buy", function(text)
	seedFilterText = text
	refreshSelectorFilter(seedButtons, seedNames, seedFilterText, seedRow, 2)
end)

function refreshSeedButton(seedName)
	local button = seedButtons[seedName]
	if not button then
		return
	end

	local enabled = selectedSeeds[seedName] == true
	button.Text = (enabled and "[x] " or "[ ] ") .. seedName
	button.BackgroundColor3 = enabled and Color3.fromRGB(58, 111, 67) or Color3.fromRGB(52, 60, 54)
end

function refreshSeedCanvas()
	refreshSelectorFilter(seedButtons, seedNames, seedFilterText, seedRow, 2)
end

function makeSeedButton(seedName)
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
		TextSize = 10,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Size = UDim2.fromOffset(128, 20),
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
			notifyStock("Seed shop", seedName, true)
		end
	end)

	refreshSeedCanvas()
end

function scanSeedShopNames()
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

function buildShovelSeedSelector()
local shovelSeedLabel = make("TextLabel", {
	Name = "ShovelSeedLabel",
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamSemibold,
	Text = "Seeds to shovel",
	TextColor3 = Color3.fromRGB(221, 236, 216),
	TextSize = 11,
	TextXAlignment = Enum.TextXAlignment.Left,
	Size = UDim2.new(1, 0, 0, 12),
	LayoutOrder = 27,
}, content)

local shovelSeedRow = make("ScrollingFrame", {
	Name = "ShovelSeedSelector",
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	CanvasSize = UDim2.fromOffset(0, 0),
	ScrollBarThickness = 4,
	ScrollingDirection = Enum.ScrollingDirection.Y,
	Size = UDim2.new(1, 0, 0, 54),
	LayoutOrder = 28,
}, content)
make("UIGridLayout", {
	CellPadding = UDim2.fromOffset(4, 4),
	CellSize = UDim2.fromOffset(128, 20),
	SortOrder = Enum.SortOrder.LayoutOrder,
}, shovelSeedRow)

local shovelSeedLayout = shovelSeedRow:FindFirstChildOfClass("UIGridLayout")
local shovelSeedButtons = {}
local shovelSeedButtonCount = 0
local shovelSeedFilterText = ""

makeSelectorSearch(content, 29, "Search seeds to shovel", function(text)
	shovelSeedFilterText = text
	refreshSelectorFilter(shovelSeedButtons, seedNames, shovelSeedFilterText, shovelSeedRow, 2)
end)

function refreshShovelSeedButton(seedName)
	local button = shovelSeedButtons[seedName]
	if not button then
		return
	end

	local enabled = selectedShovelSeeds[seedName] == true
	button.Text = (enabled and "[x] " or "[ ] ") .. seedName
	button.BackgroundColor3 = enabled and Color3.fromRGB(122, 65, 50) or Color3.fromRGB(52, 60, 54)
end

function refreshShovelSeedCanvas()
	refreshSelectorFilter(shovelSeedButtons, seedNames, shovelSeedFilterText, shovelSeedRow, 2)
end

function makeShovelSeedButton(seedName)
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
		TextSize = 10,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Size = UDim2.fromOffset(128, 20),
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

function buildGearSelector()
local selectedGearLabel = make("TextLabel", {
	Name = "SelectedGearLabel",
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamSemibold,
	Text = "Gear to buy",
	TextColor3 = Color3.fromRGB(221, 236, 216),
	TextSize = 11,
	TextXAlignment = Enum.TextXAlignment.Left,
	Size = UDim2.new(1, 0, 0, 12),
	LayoutOrder = 30,
}, content)

local gearRow = make("ScrollingFrame", {
	Name = "GearSelector",
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	CanvasSize = UDim2.fromOffset(0, 0),
	ScrollBarThickness = 4,
	ScrollingDirection = Enum.ScrollingDirection.Y,
	Size = UDim2.new(1, 0, 0, 54),
	LayoutOrder = 32,
}, content)
make("UIGridLayout", {
	CellPadding = UDim2.fromOffset(4, 4),
	CellSize = UDim2.fromOffset(128, 20),
	SortOrder = Enum.SortOrder.LayoutOrder,
}, gearRow)

local gearLayout = gearRow:FindFirstChildOfClass("UIGridLayout")
local gearButtons = {}
local gearButtonCount = 0
local gearFilterText = ""

makeSelectorSearch(content, 31, "Search gear to buy", function(text)
	gearFilterText = text
	refreshSelectorFilter(gearButtons, gearNames, gearFilterText, gearRow, 2)
end)

function refreshGearButton(gearName)
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

function refreshGearCanvas()
	refreshSelectorFilter(gearButtons, gearNames, gearFilterText, gearRow, 2)
end

function makeGearButton(gearName)
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
		TextSize = 10,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Size = UDim2.fromOffset(128, 20),
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
			notifyStock("Gear shop", gearName, true)
		end
	end)

	refreshGearCanvas()
end

function scanGearShopNames()
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

function buildPetSelector()
local selectedPetLabel = make("TextLabel", {
	Name = "SelectedPetLabel",
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamSemibold,
	Text = "Pets to buy",
	TextColor3 = Color3.fromRGB(221, 236, 216),
	TextSize = 11,
	TextXAlignment = Enum.TextXAlignment.Left,
	Size = UDim2.new(1, 0, 0, 12),
	LayoutOrder = 33,
}, content)

local petRow = make("ScrollingFrame", {
	Name = "PetSelector",
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	CanvasSize = UDim2.fromOffset(0, 0),
	ScrollBarThickness = 4,
	ScrollingDirection = Enum.ScrollingDirection.Y,
	Size = UDim2.new(1, 0, 0, 54),
	LayoutOrder = 35,
}, content)
make("UIGridLayout", {
	CellPadding = UDim2.fromOffset(4, 4),
	CellSize = UDim2.fromOffset(128, 20),
	SortOrder = Enum.SortOrder.LayoutOrder,
}, petRow)

local petLayout = petRow:FindFirstChildOfClass("UIGridLayout")
local petButtons = {}
local petButtonCount = 0
local petFilterText = ""

makeSelectorSearch(content, 34, "Search pets to buy", function(text)
	petFilterText = text
	refreshSelectorFilter(petButtons, petNames, petFilterText, petRow, 2)
end)

function refreshPetButton(petName)
	local button = petButtons[petName]
	if not button then
		return
	end

	local enabled = selectedPets[petName] == true
	button.Text = (enabled and "[x] " or "[ ] ") .. petName
	button.BackgroundColor3 = enabled and Color3.fromRGB(58, 111, 67) or Color3.fromRGB(52, 60, 54)
end

function refreshPetCanvas()
	refreshSelectorFilter(petButtons, petNames, petFilterText, petRow, 2)
end

function makePetButton(petName)
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
		TextSize = 10,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Size = UDim2.fromOffset(128, 20),
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

function scanPetBuyNames()
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
	statsWebhook = 0,
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
	schedulerAccumulator += deltaTime
	if schedulerAccumulator < 0.1 then
		return
	end
	deltaTime = schedulerAccumulator
	schedulerAccumulator = 0

	local jobsStarted = 0
	local maxJobsThisFrame = 1
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
	timers.statsWebhook += deltaTime

	if timers.stats >= 5.0 then
		timers.stats = 0
		refreshInventoryStats()
		updateStatsUI()
	end

	if timers.statsWebhook >= CONFIG.statsWebhookInterval then
		timers.statsWebhook = 0
		sendStatsWebhook(false)
	end

	local inventoryFull = false
	local sellNeeded = false
	if state.sellWhenFull or state.autoSell then
		inventoryFull = refreshInventoryStats(false)
		sellNeeded = inventoryFull
	end
	local urgentSellDue = inventoryFull and (state.sellWhenFull or state.autoSell)
	local sellDue = urgentSellDue
		or (state.autoSell and timers.autoSell >= CONFIG.sellInterval)

	if sellDue and not running.autoSell and not running.sellWhenFull then
		if state.sellWhenFull and sellNeeded then
			if tryRun("sellWhenFull", function()
				autoSell(true)
			end) then
				timers.sellWhenFull = 0
				timers.autoSell = 0
			end
		elseif state.autoSell then
			if tryRun("autoSell", autoSell) then
				timers.autoSell = 0
			end
		end
	end

	local shovelDue = state.autoShovel and timers.autoShovel >= CONFIG.shovelInterval
	local movementLocked = running.autoShovel or sellDue or running.autoSell or running.sellWhenFull

	if shovelDue and not movementLocked then
		if tryRun("autoShovel", autoShovel) then
			timers.autoShovel = 0
		end
	end

	movementLocked = movementLocked or running.autoShovel
	local fruitMovementLocked = running.autoShovel
		or (inventoryFull and (sellDue or running.autoSell or running.sellWhenFull))

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
		if fruitMovementLocked then
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

