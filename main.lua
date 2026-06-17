-- Garden automation GUI for private testing in a Grow-a-Garden-style place.
-- Drop this LocalScript in StarterPlayerScripts, or run it from a local test client.

Players = game:GetService("Players")
CollectionService = game:GetService("CollectionService")
HttpService = game:GetService("HttpService")
ReplicatedStorage = game:GetService("ReplicatedStorage")
RunService = game:GetService("RunService")
StarterGui = game:GetService("StarterGui")
UserInputService = game:GetService("UserInputService")

localPlayer = Players.LocalPlayer
playerGui = localPlayer:WaitForChild("PlayerGui")

CONFIG = {
	collectInterval = 0.25,
	sellInterval = 12.0,
	sellWhenFullInterval = 1.5,
	schedulerInterval = 0.25,
	maxSellAttempts = 2,
	sellCooldown = 3.0,
	sellResumeFreeSlots = 8,
	buyInterval = 1.5,
	mailInterval = 6.0,
	petSellInterval = 5.0,
	petBuyInterval = 1.5,
	cacheRefreshInterval = 25.0,
	inventoryRefreshInterval = 1.0,
	guiInventoryRefreshInterval = 30.0,
	maxFruitCollectPerTick = 32,
	maxFruitScanPerRoot = 1800,
	fruitCacheRefreshInterval = 1.5,
	maxFruitTargetsCached = 420,
	maxFruitPromptFallbackPerTick = 32,
	maxSeedBuyPerTick = 3,
	seedBuyRemoteRepeats = 4,
	maxInventoryItems = 100,
	movePlantPosition = nil,
	petSellMutationFilter = "",
	petSellVariantFilter = "",
	petSellExcludeVariantFilter = "",
	keepAllPetVariants = true,
	webhookUrl = "",
	statsWebhookInterval = 180.0,
}

seedNames = {}

seedPriority = {}

state = {
	fruitCollector = false,
	autoSell = false,
	sellWhenFull = true,
	autoBuySeeds = false,
	autoBuyGear = false,
	autoMovePlants = false,
	autoAcceptMail = false,
	autoBuyPets = false,
	autoSellPets = false,
	performanceMode = false,
	hideGameButtons = false,
	hidePlotIcons = false,
	hideOwnPlants = false,
	lastStatus = "Ready",
}

selectedSeeds = {}

selectedMoveSeeds = {}

gearNames = {}

selectedGears = {}

petNames = {}

buyPetNames = {}

selectedPets = {}
selectedSellPets = {}

plantPromptTextCache = setmetatable({}, { __mode = "k" })
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
		"mailInterval",
		"petSellInterval",
		"movePlantPosition",
		"petSellMutationFilter",
		"petSellVariantFilter",
		"petSellExcludeVariantFilter",
		"keepAllPetVariants",
		"webhookUrl",
		"statsWebhookInterval",
	})
	copyKnownValues(decoded.state, state, {
		"fruitCollector",
		"autoSell",
		"sellWhenFull",
		"autoBuySeeds",
		"autoBuyGear",
		"autoMovePlants",
		"autoAcceptMail",
		"autoBuyPets",
		"autoSellPets",
		"performanceMode",
		"hideGameButtons",
		"hidePlotIcons",
		"hideOwnPlants",
	})
	if decoded.state and decoded.state.hidePlants == true then
		state.performanceMode = true
	end

	selectedSeeds = copyMap(decoded.selectedSeeds)
	selectedMoveSeeds = copyMap(decoded.selectedMoveSeeds)
	selectedGears = copyMap(decoded.selectedGears)
	selectedPets = copyMap(decoded.selectedPets)
	selectedSellPets = copyMap(decoded.selectedSellPets)

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
			mailInterval = CONFIG.mailInterval,
			petSellInterval = CONFIG.petSellInterval,
			movePlantPosition = CONFIG.movePlantPosition,
			petSellMutationFilter = CONFIG.petSellMutationFilter,
			petSellVariantFilter = CONFIG.petSellVariantFilter,
			petSellExcludeVariantFilter = CONFIG.petSellExcludeVariantFilter,
			keepAllPetVariants = CONFIG.keepAllPetVariants,
			webhookUrl = CONFIG.webhookUrl,
			statsWebhookInterval = CONFIG.statsWebhookInterval,
		},
		state = {
			fruitCollector = state.fruitCollector,
			autoSell = state.autoSell,
			sellWhenFull = state.sellWhenFull,
			autoBuySeeds = state.autoBuySeeds,
			autoBuyGear = state.autoBuyGear,
			autoMovePlants = state.autoMovePlants,
			autoAcceptMail = state.autoAcceptMail,
			autoBuyPets = state.autoBuyPets,
			autoSellPets = state.autoSellPets,
			performanceMode = state.performanceMode,
			hideGameButtons = state.hideGameButtons,
			hidePlotIcons = state.hidePlotIcons,
			hideOwnPlants = state.hideOwnPlants,
		},
		selectedSeeds = selectedSeeds,
		selectedMoveSeeds = selectedMoveSeeds,
		selectedGears = selectedGears,
		selectedPets = selectedPets,
		selectedSellPets = selectedSellPets,
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
local stockWebhookQueue = {}
local stockWebhookScheduled = false
local activityWebhookQueue = {}
local activityWebhookScheduled = false
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

function compactName(value)
	return string.gsub(string.lower(tostring(value or "")), "[^%w]", "")
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

function flushStockWebhookQueue()
	stockWebhookScheduled = false
	local queued = stockWebhookQueue
	stockWebhookQueue = {}

	local byShop = {}
	local keys = {}
	for _, entry in pairs(queued) do
		if entry.amount and entry.amount > 0 then
			byShop[entry.shopName] = byShop[entry.shopName] or {}
			table.insert(byShop[entry.shopName], ("- %s (%d available)"):format(entry.itemName, entry.amount))
			table.insert(keys, entry.key)
		end
	end

	local sections = {}
	for shopName, lines in pairs(byShop) do
		table.sort(lines)
		table.insert(sections, ("**%s**\n%s"):format(shopName, table.concat(lines, "\n")))
	end
	table.sort(sections)

	if #sections == 0 then
		return
	end

	local sent = sendWebhook("Stock update", table.concat(sections, "\n\n"), nil)
	if sent then
		local now = os.clock()
		for _, key in ipairs(keys) do
			webhookSentAt[key] = now
		end
	end
end

function queueStockWebhook(shopName, itemName, stockAmount, key)
	stockWebhookQueue[key] = {
		shopName = shopName,
		itemName = itemName,
		amount = stockAmount,
		key = key,
	}

	if stockWebhookScheduled then
		return
	end
	stockWebhookScheduled = true
	task.delay(1.25, flushStockWebhookQueue)
end

function flushActivityWebhookQueue()
	activityWebhookScheduled = false
	local queued = activityWebhookQueue
	activityWebhookQueue = {}

	if #queued == 0 then
		return
	end

	sendWebhook("Activity update", table.concat(queued, "\n"), nil)
end

function queueActivityWebhook(line)
	if CONFIG.webhookUrl == "" or not line or line == "" then
		return false
	end

	table.insert(activityWebhookQueue, "- " .. tostring(line))
	if activityWebhookScheduled then
		return true
	end

	activityWebhookScheduled = true
	task.delay(1.5, flushActivityWebhookQueue)
	return true
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

	if force or previousAmount == nil or previousAmount <= 0 then
		if not webhookSentAt[key] or os.clock() - webhookSentAt[key] >= 45 then
			queueStockWebhook(shopName, itemName, stockAmount, key)
		end
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
		queueActivityWebhook(("Pet spawned: `%s`"):format(petName))
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
	seedsBought = 0,
	gearBought = 0,
	petsBought = 0,
	petsSold = 0,
	mailClaimed = 0,
	mailChecks = 0,
	sheckles = 0,
	startSheckles = nil,
	shecklesFarmed = 0,
	inventoryItems = 0,
	inventoryCapacity = CONFIG.maxInventoryItems,
	inventoryFull = false,
}

local running = {}
local stopTokens = {}
local lastAutoSellAttemptAt = 0
local fruitCollectionPausedUntil = 0

function bumpStopToken(key)
	stopTokens[key] = (stopTokens[key] or 0) + 1
end

function getStopToken(key)
	return stopTokens[key] or 0
end

function runStopped(key, token)
	return key and (not isEnabled(key) or getStopToken(key) ~= token)
end

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
		"autoSell",
		"sellWhenFull",
		"autoBuySeeds",
		"autoBuyGear",
		"autoMovePlants",
		"autoBuyPets",
		"autoSellPets",
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

local packetIdKeys = {
	"Id",
	"ID",
	"UUID",
	"Guid",
	"UID",
	"UniqueId",
	"UniqueID",
	"InstanceId",
	"InstanceID",
	"FruitId",
	"FruitID",
	"ItemId",
	"ItemID",
	"PetId",
	"PetID",
}

function getInstancePacketId(instance)
	if typeof(instance) ~= "Instance" then
		return nil
	end

	for _, key in ipairs(packetIdKeys) do
		local ok, value = pcall(function()
			return instance:GetAttribute(key)
		end)
		if ok and value ~= nil and tostring(value) ~= "" then
			return value
		end

		local child = instance:FindFirstChild(key)
		if child and child:IsA("ValueBase") and child.Value ~= nil and tostring(child.Value) ~= "" then
			return child.Value
		end
	end

	local nameId = string.match(instance.Name, "[%w]+_[%w%-]+_([%w%-]+)$")
		or string.match(instance.Name, "([0-9a-fA-F]+%-[0-9a-fA-F]+%-[0-9a-fA-F]+%-[0-9a-fA-F]+%-[0-9a-fA-F]+)")
	if nameId and nameId ~= "" then
		return nameId
	end

	return nil
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
local runtimePacketEntryCache = {}
local packetSendMethodNames = {
	"Fire",
	"fire",
	"FireServer",
	"fireServer",
	"Send",
	"send",
	"SendToServer",
	"sendToServer",
	"SendServer",
	"sendServer",
	"Invoke",
	"invoke",
	"InvokeServer",
	"invokeServer",
	"Call",
	"call",
}

function tryPacketMethod(target, methodName, ...)
	if type(target) ~= "table" and typeof(target) ~= "Instance" then
		return false
	end
	local method = target[methodName]
	if type(method) ~= "function" then
		return false
	end
	return pcall(method, target, ...) or pcall(method, ...)
end

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
	return false
end

function tryPacketEntry(entry, ...)
	if type(entry) == "table" then
		for _, methodName in ipairs(packetSendMethodNames) do
			if tryPacketMethod(entry, methodName, ...) then
				return true
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
		for _, key in ipairs({ "new", "New", "create", "Create", "get", "Get", "packet", "Packet", "fromName", "FromName" }) do
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
	for _, methodName in ipairs(packetSendMethodNames) do
		if tryPacketMethod(object, methodName, ...) then
			actions += 1
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

function packetFieldMatchesPacket(value, packetName, packetId)
	if value == nil then
		return false
	end
	if value == packetName then
		return true
	end
	if packetId ~= nil and value == packetId then
		return true
	end
	local text = tostring(value)
	return text == packetName or (packetId ~= nil and text == tostring(packetId))
end

function tableLooksLikePacketEntry(value, packetName, packetId)
	if type(value) ~= "table" then
		return false
	end

	for _, key in ipairs({ "Name", "name", "_name", "PacketName", "packetName", "Id", "ID", "_id", "Identifier", "identifier" }) do
		local ok, field = pcall(function()
			return value[key]
		end)
		if ok and packetFieldMatchesPacket(field, packetName, packetId) then
			return true
		end
	end

	local matched = false
	pcall(function()
		local checked = 0
		for key, field in pairs(value) do
			checked += 1
			if packetFieldMatchesPacket(key, packetName, packetId) or packetFieldMatchesPacket(field, packetName, packetId) then
				matched = true
				break
			end
			if checked >= 40 then
				break
			end
		end
	end)

	return matched
end

function addRuntimePacketCandidate(results, seen, candidate)
	if candidate == nil or seen[candidate] then
		return
	end
	local candidateType = type(candidate)
	if candidateType ~= "table" and candidateType ~= "function" then
		return
	end
	seen[candidate] = true
	table.insert(results, candidate)
end

function findRuntimePacketEntries(packetName)
	local now = os.clock()
	local cached = runtimePacketEntryCache[packetName]
	if cached and now - cached.checkedAt < 8 then
		return cached.entries
	end

	local results = {}
	local seen = {}
	local remote = getPacketRemote()
	local packetId = remote and remote:GetAttribute(packetName) or nil

	local packet = getPacketModule()
	if type(packet) == "table" then
		addRuntimePacketCandidate(results, seen, findPacketEntry(packet, packetName))
	end

	if typeof(getgc) == "function" then
		local ok, objects = pcall(getgc, true)
		if ok and type(objects) == "table" then
			for _, object in ipairs(objects) do
				if type(object) == "table" then
					local entry
					pcall(function()
						entry = object[packetName]
					end)
					addRuntimePacketCandidate(results, seen, entry)
					if tableLooksLikePacketEntry(object, packetName, packetId) then
						addRuntimePacketCandidate(results, seen, object)
					end
				end
			end
		end
	end

	runtimePacketEntryCache[packetName] = {
		checkedAt = now,
		entries = results,
	}
	return results
end

function fireRuntimePacketEntries(packetName, ...)
	local actions = 0
	for _, entry in ipairs(findRuntimePacketEntries(packetName)) do
		if tryPacketEntry(entry, ...) then
			actions += 1
		end
	end
	return actions > 0, actions
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
		if fireRuntimePacketEntries(packetName, ...) then
			return true
		end

		for _, methodName in ipairs(packetSendMethodNames) do
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

	if fireRuntimePacketEntries(packetName, ...) then
		return true
	end

	return firePacketRemote(packetName, ...)
end

function sendExactPacket(packetName, ...)
	if not packetNameExists(packetName) then
		return false, 0
	end

	local actions = 0
	local runtimeTried = false
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
		local runtimeOk, runtimeCount = fireRuntimePacketEntries(packetName, ...)
		runtimeTried = true
		if runtimeOk then
			actions += runtimeCount or 1
		end

		for _, methodName in ipairs(packetSendMethodNames) do
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

	if not runtimeTried then
		local runtimeOk, runtimeCount = fireRuntimePacketEntries(packetName, ...)
		if runtimeOk then
			actions += runtimeCount or 1
		end
	end

	if firePacketRemote(packetName, ...) then
		actions += 1
	end

	return actions > 0, actions
end

local unpackArgs = table.unpack or unpack

function sendPacketArgVariants(packetName, variants)
	local actions = 0
	for _, args in ipairs(variants or {}) do
		local exactOk, count = sendExactPacket(packetName, unpackArgs(args))
		if exactOk then
			actions += count or 1
		elseif sendPacket(packetName, unpackArgs(args)) then
			actions += 1
		end
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

	if #roots == 0 then
		for _, plot in ipairs(gardens:GetChildren()) do
			if plot:FindFirstChild("Plants") or plot:FindFirstChild("Fruits") then
				addOwnPlot(plot)
			end
			if #roots >= 8 then
				break
			end
		end
	end

	ownGardenCache.roots = roots
	ownGardenCache.checkedAt = now
	return roots
end

local gardensForCache = getGardens()
if gardensForCache then
	gardensForCache.ChildAdded:Connect(invalidateOwnGardenCache)
	gardensForCache.ChildRemoved:Connect(invalidateOwnGardenCache)
end

local performanceRefreshQueued = false
function queuePerformanceRefresh(delaySeconds)
	if performanceRefreshQueued or not state.performanceMode then
		return
	end
	performanceRefreshQueued = true
	task.delay(delaySeconds or 1, function()
		performanceRefreshQueued = false
		if state.performanceMode and enablePerformanceMode then
			enablePerformanceMode()
		end
	end)
end

workspace.ChildAdded:Connect(function(child)
	if child.Name == "Gardens" then
		invalidateOwnGardenCache()
		child.ChildAdded:Connect(invalidateOwnGardenCache)
		child.ChildRemoved:Connect(invalidateOwnGardenCache)
		queuePerformanceRefresh(1)
	elseif child.Name == "Map" and state.performanceMode then
		queuePerformanceRefresh(1)
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
		petsSold = stats.petsSold,
		mailClaimed = stats.mailClaimed,
		mailChecks = stats.mailChecks,
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
		("Mail: `%s` claimed across `%s` check(s)"):format(formatNumber(snapshot.mailClaimed), formatNumber(snapshot.mailChecks)),
		("Pets sold: `%s`"):format(formatNumber(snapshot.petsSold)),
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
	if type(getSellableFruitTools) == "function" then
		count = #getSellableFruitTools(force == true)
	end
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
	if full ~= true then
		return false
	end

	invalidateSellableInventoryCache()
	return #getSellableFruitTools(true) > 0
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
				label.Text = ("Run: %s | Enabled: %d"):format(snapshot.runtime, snapshot.enabled)
			elseif key == "systems" then
				label.Text = ("Sheckles: %s"):format(formatNumber(snapshot.sheckles))
			elseif key == "inventory" then
				label.Text = ("Farmed this run: +%s sheckles"):format(formatNumber(snapshot.shecklesFarmed))
			elseif key == "collect" then
				label.Text = ("Fruit: %s total | %s/min"):format(formatNumber(snapshot.fruitCollected), formatNumber(snapshot.fruitRate))
			elseif key == "mail" then
				label.Text = ("Mail: %s claimed | %s checks"):format(formatNumber(snapshot.mailClaimed), formatNumber(snapshot.mailChecks))
			elseif key == "shops" then
				label.Text = ("Bought: %s seeds | %s gear | %s pets | Sold pets: %s"):format(formatNumber(snapshot.seedsBought), formatNumber(snapshot.gearBought), formatNumber(snapshot.petsBought), formatNumber(snapshot.petsSold))
			elseif key == "limits" then
				label.Text = ("Inv: %s/%s (%s free)%s | Mail: %s/%s"):format(formatNumber(snapshot.inventoryItems), formatNumber(snapshot.inventoryCapacity), formatNumber(snapshot.freeSlots), snapshot.inventoryFull and " FULL" or "", formatNumber(snapshot.mailClaimed), formatNumber(snapshot.mailChecks))
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
		if current.Parent and current.Parent.Name == "Plants" then
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

	local plant = getFruitPlantTarget(fruit)
	local fruitId = getInstancePacketId(fruit)
	local plantId = getInstancePacketId(plant)
	local variants = {
		{ fruit },
		{ fruit.Name },
	}
	if fruitId ~= nil then
		table.insert(variants, { fruitId })
		table.insert(variants, { { Id = fruitId } })
		table.insert(variants, { { FruitId = fruitId } })
		table.insert(variants, { { UID = fruitId } })
	end
	if target ~= fruit then
		table.insert(variants, { target })
		table.insert(variants, { target.Name })
	end
	if plant then
		table.insert(variants, { plant, fruit })
		table.insert(variants, { plant.Name, fruit.Name })
		table.insert(variants, { plant.Name, fruit })
		table.insert(variants, { plant, fruit.Name })
		if plantId ~= nil then
			table.insert(variants, { plantId, fruitId or fruit.Name })
			table.insert(variants, { { PlantId = plantId, FruitId = fruitId or fruit.Name } })
		end
	end

	local ok = sendPacketArgVariants("CollectFruit", variants)
	if ok then
		return true
	end

	if not heavy then
		return false
	end

	if plant and sendExactPacket("CollectFruit", plant, fruit) then
		return true
	end

	if plant and sendExactPacket("CollectFruit", plant.Name, fruit and fruit.Name) then
		return true
	end

	if plant and sendExactPacket("CollectFruit", plant.Name, fruit) then
		return true
	end

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
	local target = getCollectFruitTarget(prompt)
	local beforeInventoryCount = countInventoryTools()
	local fired = false
	if target ~= nil then
		fired = collectFruitPacket(target, true) or fired
		if collectionTookEffect(target or prompt, beforeInventoryCount) then
			return true
		end
	end

	return fired
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

	return true
end

function addFruitTarget(targets, seenTargets, prompt, target)
	if prompt and not isUsableHarvestPrompt(prompt) then
		return
	end

	target = target or getCollectFruitTarget(prompt)
	if not target then
		return
	end

	local key = target or prompt
	if seenTargets[key] then
		return
	end

	seenTargets[key] = true
	table.insert(targets, {
		prompt = prompt,
		target = target,
		priority = getFruitPriority(target),
	})
end

function isFruitModelCandidate(instance)
	if not instance or not instance.Parent then
		return false
	end
	if not (instance:IsA("Model") or instance:IsA("Folder") or instance:IsA("BasePart")) then
		return false
	end
	local parent = instance.Parent
	if parent and parent.Name == "Fruits" then
		return true
	end
	local pathText = string.lower(getObjectPath(instance))
	return string.find(pathText, ".fruits.", 1, true) ~= nil
		or string.find(pathText, ".fruit.", 1, true) ~= nil
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
			elseif isFruitModelCandidate(descendant) then
				addFruitTarget(targets, seenTargets, nil, descendant)
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

	local beforeInventoryCount = countInventoryTools()
	local fired = false
	if target then
		fired = collectFruitPacket(target, true) or fired
		if collectionTookEffect(target or prompt, beforeInventoryCount) then
			return true
		end
	end

	return fired
end

function sellSucceeded(beforeInventoryCount, beforeSheckles)
	local currentInventoryCount = type(getSellableFruitTools) == "function" and #getSellableFruitTools(true) or countInventoryTools()
	local currentSheckles = refreshCurrencyStats(true)
	return currentInventoryCount < beforeInventoryCount
		or (currentSheckles and beforeSheckles and currentSheckles > beforeSheckles),
		currentInventoryCount,
		currentSheckles
end

function getToolPacketId(tool)
	return getInstancePacketId(tool)
end

function sellToolByRemote(tool)
	if not tool then
		return false
	end

	local id = getToolPacketId(tool)
	local variants = {
		{ tool },
		{ tool.Name },
	}
	if id ~= nil then
		table.insert(variants, 1, { id })
		table.insert(variants, { { Id = id } })
		table.insert(variants, { { ItemId = id } })
		table.insert(variants, { { FruitId = id } })
		table.insert(variants, { { UID = id } })
		table.insert(variants, { id, tool.Name })
		table.insert(variants, { tool.Name, id })
	end

	local soldItem = sendPacketArgVariants("SellItem", variants)
	local soldFruit = sendPacketArgVariants("SellFruit", variants)
	local soldPreview = sendPacketArgVariants("PreviewSellAll", variants)
	return soldItem or soldFruit or soldPreview
end

function sellInventoryByRemote(sellableTools)
	local actions = 0
	local toolIds = {}
	for _, tool in ipairs(sellableTools or {}) do
		local id = getToolPacketId(tool)
		if id ~= nil then
			table.insert(toolIds, id)
		end
	end
	local sellAllVariants = {
		{},
		{ "Fruit" },
		{ "Fruits" },
		{ "Inventory" },
		{ "All" },
		{ true },
		{ sellableTools or {} },
		{ toolIds },
		{ { Type = "Fruit" } },
		{ { Category = "Fruit" } },
		{ { Items = toolIds } },
	}
	local ok, count = sendPacketArgVariants("SellAll", sellAllVariants)
	if ok then
		actions += count
	end
	local previewOk, previewCount = sendPacketArgVariants("PreviewSellAll", sellAllVariants)
	if previewOk then
		actions += previewCount
	end

	for _, tool in ipairs(sellableTools or {}) do
		if sellToolByRemote(tool) then
			actions += 1
		end
	end

	return actions
end

function collectFruit()
	if not isEnabled("fruitCollector") then
		return
	end

	if state.sellWhenFull or state.autoSell then
		invalidateSellableInventoryCache()
		refreshInventoryStats(true)
	end
	if state.performanceMode then
		restoreOwnGardenAutomationPrompts()
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
	local failedRemoteHarvests = 0
	for index, entry in ipairs(targets) do
		if not isEnabled("fruitCollector") then
			return
		end
		if shouldPauseFruitCollection() then
			stats.collectSkippedFull += 1
			setStatus(("Fruit collector paused: sell needed (%d/%d)"):format(stats.inventoryItems, stats.inventoryCapacity))
			return
		end

		if fallback < fallbackLimit and isLiveFruitEntry(entry) and entry.target then
			if collectFruitEntryFast(entry, heavyFallback) then
				fallback += 1
				fired += 1
				failedRemoteHarvests = 0
			else
				failedRemoteHarvests += 1
				fruitTargetCache.refreshedAt = 0
				if failedRemoteHarvests >= 2 then
					setStatus("Fruit collector: remote harvest failed, waiting before next target")
					break
				end
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
		invalidateSellableInventoryCache()
		fruitTargetCache.noGainStreak = 0
	else
		fruitTargetCache.noGainStreak = math.min(fruitTargetCache.noGainStreak + 1, 3)
	end
	pruneFruitTargetCache()
	refreshInventoryStats()
	updateStatsUI()
	if fired == 0 and fallback == 0 then
		fruitTargetCache.refreshedAt = 0
		setStatus(("Fruit collector: found %d cached target(s), remote failed"):format(totalCached))
	else
		setStatus(("Fruit collector: remote %d/%d, inventory +%d"):format(fallback, #targets, gained))
	end
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

isInventorySeedTool = function(item)
	if not item or not item:IsA("Tool") then
		return false
	end

	local name = string.lower(item.Name)
	local compact = compactName(item.Name)
	for _, word in ipairs({ "kg", " lb", "fruit", "harvest", "picked", "mutation", "rainbow", "golden" }) do
		if string.find(name, word, 1, true) then
			return false
		end
	end

	if string.find(name, "seed", 1, true) then
		return true
	end

	for _, key in ipairs({ "Seed", "SeedName", "ItemName", "Name" }) do
		local ok, attribute = pcall(function()
			return item:GetAttribute(key)
		end)
		if ok and attribute ~= nil and tostring(attribute) ~= "" then
			local value = tostring(attribute)
			if string.find(string.lower(value), "seed", 1, true) then
				return true
			end
			for _, seedName in ipairs(seedNames) do
				local seedCompact = compactName(seedName)
				if seedCompact ~= "" and string.find(compactName(value), seedCompact, 1, true) then
					return true
				end
			end
		end

		local child = item:FindFirstChild(key)
		if child and child:IsA("ValueBase") and child.Value ~= nil then
			local value = tostring(child.Value)
			if string.find(string.lower(value), "seed", 1, true) then
				return true
			end
		end
	end

	for _, seedName in ipairs(seedNames) do
		local seedCompact = compactName(seedName)
		if string.find(name, string.lower(seedName), 1, true)
			or (seedCompact ~= "" and string.find(compact, seedCompact, 1, true))
			or (seedCompact ~= "" and string.find(compact, seedCompact .. "seed", 1, true))
		then
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
		or toolNameMatchesList(item, seedNames)
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

local sellableInventoryCache = {
	tools = {},
	count = 0,
	checkedAt = 0,
	dirty = true,
}

function invalidateSellableInventoryCache()
	sellableInventoryCache.dirty = true
end

function scanSellableFruitTools()
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

function getSellableFruitTools(force)
	local now = os.clock()
	if not force
		and not sellableInventoryCache.dirty
		and now - sellableInventoryCache.checkedAt < 1.0
	then
		return sellableInventoryCache.tools
	end

	local tools = scanSellableFruitTools()
	sellableInventoryCache.tools = tools
	sellableInventoryCache.count = #tools
	sellableInventoryCache.checkedAt = now
	sellableInventoryCache.dirty = false
	return tools
end

function hasSellableFruitTools()
	return #getSellableFruitTools(false) > 0
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

function hasAutomationPrompt(instance)
	if not instance then
		return false
	end

	if instance:IsA("ProximityPrompt") then
		return true
	end

	return instance:FindFirstChildWhichIsA("ProximityPrompt", true) ~= nil
end

function hidePerformanceVisual(instance, hidePrompts)
	if not instance or performanceState.hidden[instance] then
		return 0
	end

	local changed = 0
	changed += disableLaggyEffect(instance)
	if instance:IsA("ProximityPrompt") then
		return changed
	end

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

function restoreOwnGardenAutomationPrompts()
	local restored = 0
	for _, root in ipairs(getOwnGardenRoots()) do
		for _, descendant in ipairs(root:GetDescendants()) do
			if descendant:IsA("ProximityPrompt")
				and descendant.Name ~= "StealPrompt"
				and isHarvestPrompt(descendant)
			then
				local ok = pcall(function()
					if descendant.Enabled == false then
						descendant.Enabled = true
						restored += 1
					end
				end)
				if not ok then
					continue
				end
			end
		end
	end
	return restored
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
		changed += restoreOwnGardenAutomationPrompts()
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

function getSelectedMoveSeedList()
	local selected = {}
	local seen = {}

	for _, seedName in ipairs(seedNames) do
		if selectedMoveSeeds[seedName] then
			seen[seedName] = true
			table.insert(selected, seedName)
		end
	end

	for seedName, enabled in pairs(selectedMoveSeeds) do
		if enabled and not seen[seedName] then
			addUniqueName(seedNames, seedName)
			seedPriority[seedName] = seedPriority[seedName] or getSeedMetadataValue(seedName)
			table.insert(selected, seedName)
		end
	end

	return getSortedSeedList(selected)
end

function getTrowelTool()
	return getToolByWords({ "trowel" })
end

function movePlantTarget(plant, targetPosition)
	if not plant or not plant.Parent or not targetPosition then
		return false
	end

	plant = getPlantModel(plant)
	if not plant or not plant.Parent then
		return false
	end

	local part = getTargetPart(plant)
	local tool = getTrowelTool()
	if tool and part then
		useToolAtPosition(tool, part.Position, 0.45)
		task.wait(0.1)
		useToolAtPosition(tool, targetPosition, 0.45)
	end

	return sendPacket("MovePlant", plant, targetPosition)
		or sendPacket("MovePlant", plant.Name, targetPosition)
		or sendPacket("TrowelPlant", plant, targetPosition)
		or sendPacket("TrowelPlant", plant.Name, targetPosition)
		or sendPacket("UseTrowel", plant, targetPosition)
		or sendPacket("UseTrowel", targetPosition)
		or tool ~= nil
end

function autoMovePlants()
	if not isEnabled("autoMovePlants") then
		return
	end

	local targetPosition = vectorFromConfigPosition(CONFIG.movePlantPosition)
	if not targetPosition then
		setStatus("Move plants: save a move position first")
		return
	end

	local selected = getSelectedMoveSeedList()
	if #selected == 0 then
		setStatus("Move plants: select planted seed types first")
		return
	end

	local moved = 0
	local checked = 0
	local seen = {}
	for _, root in ipairs(getOwnGardenRoots()) do
		for _, descendant in ipairs(getCachedDescendants("movePlants", root, CONFIG.cacheRefreshInterval)) do
			if not isEnabled("autoMovePlants") then
				return
			end
			if moved >= 2 or checked >= 60 then
				break
			end

			local plant = getPlantModel(descendant)
			if plant and not seen[plant] and plantMatchesSelection(plant, selected) then
				seen[plant] = true
				checked += 1
				if movePlantTarget(plant, targetPosition) then
					moved += 1
					task.wait(0.25)
				end
			end
		end
		if moved >= 2 or checked >= 60 then
			break
		end
	end

	setStatus(("Move plants: moved %d matching plant(s)"):format(moved))
end

function getPlantName(instance)
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

function getPlantModel(instance)
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

function plantMatchesSelection(plant, selected)
	local plantName = string.lower(getPlantName(plant))
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

function activateToolOnly(tool)
	if tool and tool.Parent then
		return pcall(function()
			tool:Activate()
		end)
	end

	return false
end

function vectorFromConfigPosition(value)
	if type(value) ~= "table" then
		return nil
	end
	local x, y, z = tonumber(value.x), tonumber(value.y), tonumber(value.z)
	if x and y and z then
		return Vector3.new(x, y, z)
	end
	return nil
end

function getToolByWords(words)
	local character = getCharacter()
	local humanoid = getHumanoid()
	for _, container in ipairs(getToolContainers()) do
		if container then
			for _, item in ipairs(container:GetChildren()) do
				if item:IsA("Tool") then
					local lowered = string.lower(item.Name)
					for _, word in ipairs(words) do
						if string.find(lowered, string.lower(word), 1, true) then
							if item.Parent ~= character and humanoid then
								humanoid:EquipTool(item)
								task.wait(0.05)
							end
							return item
						end
					end
				end
			end
		end
	end
	return nil
end

function useToolAtPosition(tool, position, holdSeconds)
	if not tool or not position then
		return false
	end

	return activateToolOnly(tool)
end

function autoAcceptMail()
	if not isEnabled("autoAcceptMail") then
		return
	end
	stats.mailChecks += 1
	local actions = 0
	local beforeInventoryCount = countInventoryTools()

	if sendExactPacket("MailboxList") then
		actions += 1
	end
	if sendExactPacket("MailboxOpenInbox") then
		actions += 1
	end
	if sendExactPacket("MailboxClaim") then
		actions += 1
	end
	for index = 1, 50 do
		if sendExactPacket("MailboxClaim", index) then
			actions += 1
		end
		if sendExactPacket("MailboxClaim", tostring(index)) then
			actions += 1
		end
	end
	task.wait(0.25)

	local afterInventoryCount = countInventoryTools()
	local claimed = math.max((afterInventoryCount or 0) - (beforeInventoryCount or 0), 0)
	if claimed > 0 then
		stats.mailClaimed += claimed
		refreshInventoryStats(true)
		updateStatsUI()
	end
	setStatus(("Mail: remote checked (%d action(s)), inventory +%d"):format(actions, claimed))
end

function applyPlayerVisualSettings()
	local changed = 0
	local ownGui = playerGui:FindFirstChild("GardenAutomationGui")
	for _, guiObject in ipairs(playerGui:GetDescendants()) do
		if guiObject:IsA("GuiObject") and (not ownGui or not guiObject:IsDescendantOf(ownGui)) then
			local text = string.lower(safeText(guiObject.Name))
			pcall(function()
				text = text .. " " .. string.lower(safeText(guiObject.Text))
			end)
			if state.hideGameButtons and (string.find(text, "button", 1, true) or string.find(text, "shop", 1, true) or string.find(text, "gift", 1, true)) then
				guiObject.Visible = false
				changed += 1
			elseif state.hidePlotIcons and (string.find(text, "plot", 1, true) or string.find(text, "icon", 1, true)) then
				guiObject.Visible = false
				changed += 1
			end
		end
	end
	if state.hideOwnPlants then
		for _, root in ipairs(getOwnGardenRoots()) do
			for _, descendant in ipairs(root:GetDescendants()) do
				if isOwnPlantVisual(descendant, getGardenPlotForInstance(descendant)) then
					changed += hidePerformanceVisual(descendant, false)
				end
			end
		end
	end
	setStatus(("Player settings: hidden %d object(s)"):format(changed))
end

function autoSell(force)
	local stopKey = force and "sellWhenFull" or "autoSell"
	local token = getStopToken(stopKey)
	if runStopped(stopKey, token) then
		return
	end
	local now = os.clock()
	if now - lastAutoSellAttemptAt < CONFIG.sellCooldown then
		return
	end
	lastAutoSellAttemptAt = now
	fruitCollectionPausedUntil = now + 2.5

	local inventoryFull = refreshInventoryStats(true)
	local sellableTools = getSellableFruitTools(true)
	if #sellableTools <= 0 then
		refreshInventoryStats(true)
		if not force then
			setStatus("Sell: nothing to sell")
		else
			setStatus(("Sell: inventory empty (%d/%d)"):format(stats.inventoryItems, stats.inventoryCapacity))
		end
		return
	end
	local beforeInventoryCount = #sellableTools

	local beforeSheckles = refreshCurrencyStats(true)
	local farmedBeforeSell = stats.shecklesFarmed or 0

	for attempt = 1, CONFIG.maxSellAttempts do
		if runStopped(stopKey, token) then
			return
		end
		if #getSellableFruitTools(true) <= 0 then
			setStatus("Sell: no sellable fruit in inventory")
			return
		end

		local remoteActions = sellInventoryByRemote(getSellableFruitTools(true))
		if remoteActions > 0 then
			task.wait(0.45)
			local sold = sellSucceeded(beforeInventoryCount, beforeSheckles)
			if sold then
				setStatus(("Sell: remote sold inventory (%d action(s))"):format(remoteActions))
				break
			end
		end

		if #getSellableFruitTools(true) == 0 then
			break
		end
	end

	task.wait(0.15)
	local afterSheckles = refreshCurrencyStats(true)
	if afterSheckles and beforeSheckles and afterSheckles > beforeSheckles then
		stats.shecklesFarmed = math.max(stats.shecklesFarmed or 0, farmedBeforeSell + (afterSheckles - beforeSheckles))
	end

	refreshInventoryStats(true)
	invalidateSellableInventoryCache()
	local afterInventoryCount = #getSellableFruitTools(true)
	local sold = afterInventoryCount < beforeInventoryCount
		or (afterSheckles and beforeSheckles and afterSheckles > beforeSheckles)
	if sold then
		fruitCollectionPausedUntil = 0
		fruitTargetCache.refreshedAt = 0
		if timers then
			timers.sellWhenFull = 0
			timers.autoSell = 0
			timers.fruitCollector = CONFIG.collectInterval
		end
	end
	updateStatsUI()
	if not sold then
		setStatus(("Sell failed: remote made no change (%d/%d)"):format(stats.inventoryItems, stats.inventoryCapacity))
	else
		setStatus(("Sell: inventory %d -> %d"):format(beforeInventoryCount, afterInventoryCount))
	end
end

function buyOneSeed(seedName)
	local remoteOk, remoteCount = purchaseSeedRemote(seedName)
	if remoteOk then
		return true, "Seed: " .. seedName, remoteCount or 1
	end

	return false, "Seed: remote failed " .. seedName, 0
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
	local compact = string.gsub(tostring(gearName or ""), "%s+", "")
	local underscored = string.gsub(tostring(gearName or ""), "%s+", "_")
	local ok = sendPacketArgVariants("PurchaseGear", {
		{ gearName },
		{ gearName, 1 },
		{ underscored },
		{ underscored, 1 },
		{ compact },
		{ compact, 1 },
		{ { Name = gearName } },
		{ { Gear = gearName } },
		{ { Item = gearName } },
		{ { ItemName = gearName } },
		{ { Name = gearName, Quantity = 1 } },
	})
	if ok then
		return true, "Gear: " .. gearName
	end

	return false, "Gear: remote failed " .. gearName
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

function getPetSpawnId(model, prompt)
	return getInstancePacketId(model)
		or getInstancePacketId(prompt)
		or (model and string.match(model.Name, "([%w%-]+)$"))
		or (model and model.Name)
end

function buyPetRemote(petName, model, prompt)
	local spawnId = getPetSpawnId(model, prompt)
	local modelName = model and model.Name or petName
	local variants = {
		{ petName },
		{ modelName },
		{ model },
		{ prompt },
		{ { Name = petName } },
		{ { Pet = petName } },
		{ { PetName = petName } },
	}
	if spawnId ~= nil then
		table.insert(variants, 1, { spawnId })
		table.insert(variants, { spawnId, petName })
		table.insert(variants, { petName, spawnId })
		table.insert(variants, { { Id = spawnId } })
		table.insert(variants, { { PetId = spawnId } })
		table.insert(variants, { { SpawnId = spawnId } })
		table.insert(variants, { { UID = spawnId } })
		table.insert(variants, { { Id = spawnId, PetName = petName } })
	end

	local tameOk = sendPacketArgVariants("WildPetTame", variants)
	local collectedOk = sendPacketArgVariants("WildPetCollected", variants)
	return tameOk or collectedOk
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
				if buyPetRemote(petName, model, descendant) then
					markPetSpawnHandled(model, descendant, 25)
					return true, ("Auto pets: remote requested %s"):format(petName)
				end
			end
		end
	end

	if buyPetRemote(petName) then
		return true, ("Auto pets: remote requested %s"):format(petName)
	end

	return false, ("Auto pets: no matching remote target for %s"):format(petName)
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
		queueActivityWebhook(("Bought `%d` selected pet(s)."):format(bought))
		setStatus(("Auto pets: verified %d purchase(s)"):format(bought))
	else
		setStatus(lastMessage)
	end
end

function splitFilterTerms(value)
	local terms = {}
	for term in string.gmatch(tostring(value or ""), "([^,]+)") do
		term = trimText(term)
		if term ~= "" then
			table.insert(terms, string.lower(term))
		end
	end
	return terms
end

function filterAllowsValue(filterText, value)
	local terms = splitFilterTerms(filterText)
	if #terms == 0 then
		return true
	end
	local lowered = string.lower(tostring(value or ""))
	for _, term in ipairs(terms) do
		if term == "any" or term == "*" or string.find(lowered, term, 1, true) then
			return true
		end
	end
	return false
end

function filterRejectsValue(filterText, value)
	local terms = splitFilterTerms(filterText)
	if #terms == 0 then
		return false
	end
	local lowered = string.lower(tostring(value or ""))
	for _, term in ipairs(terms) do
		if term ~= "any" and term ~= "*" and string.find(lowered, term, 1, true) then
			return true
		end
	end
	return false
end

function petInfoHasVariant(info)
	if not info then
		return false
	end
	local haystack = string.lower(table.concat({
		tostring(info.variant or ""),
		tostring(info.mutation or ""),
		info.tool and tostring(info.tool.Name) or "",
	}, " "))
	for _, variant in ipairs(petVariantWords) do
		if string.find(haystack, string.lower(variant), 1, true) then
			return true
		end
	end
	return false
end

function getPetToolInfo(tool)
	if not tool or not tool:IsA("Tool") then
		return nil
	end

	local name = tool:GetAttribute("PetName")
		or tool:GetAttribute("Pet")
		or tool:GetAttribute("Type")
		or tool:GetAttribute("Name")
		or stripVariantWords(tool.Name)
	local variant = tool:GetAttribute("Variant")
		or tool:GetAttribute("Size")
		or tool:GetAttribute("Rarity")
		or ""
	local mutation = tool:GetAttribute("Mutation")
		or tool:GetAttribute("Mutations")
		or ""
	local id = getToolPacketId(tool)

	for _, childName in ipairs({ "PetName", "Pet", "Type", "Variant", "Mutation", "Mutations", "Id", "ID", "UUID", "Guid", "UID", "UniqueId", "UniqueID", "PetId", "PetID" }) do
		local child = tool:FindFirstChild(childName)
		if child and child:IsA("ValueBase") then
			if childName == "PetName" or childName == "Pet" or childName == "Type" then
				name = name or child.Value
			elseif childName == "Variant" then
				variant = child.Value
			elseif childName == "Mutation" or childName == "Mutations" then
				mutation = child.Value
			elseif id == nil then
				id = child.Value
			end
		end
	end

	local baseName = stripVariantWords(name or tool.Name)
	if not isKnownPetTool(tool) and not hasKnownPetBase(baseName) then
		return nil
	end

	return {
		tool = tool,
		name = baseName,
		variant = tostring(variant or ""),
		mutation = tostring(mutation or ""),
		id = id,
	}
end

function selectedSellPetList()
	local selected = {}
	for _, petName in ipairs(petNames) do
		if selectedSellPets[petName] then
			table.insert(selected, petName)
		end
	end
	return selected
end

function petSellInfoMatches(info)
	if not info then
		return false
	end
	local selected = selectedSellPetList()
	if #selected == 0 then
		return false
	end
	local matchedName = false
	local wanted = compactName(info.name)
	for _, petName in ipairs(selected) do
		if compactName(petName) == wanted then
			matchedName = true
			break
		end
	end
	if not matchedName then
		return false
	end
	if CONFIG.keepAllPetVariants and petInfoHasVariant(info) then
		return false
	end
	return true
end

function getSellablePetTools()
	local tools = {}
	for _, container in ipairs(getToolContainers()) do
		if container then
			for _, item in ipairs(container:GetChildren()) do
				local info = getPetToolInfo(item)
				if petSellInfoMatches(info) then
					table.insert(tools, info)
				end
			end
		end
	end
	return tools
end

function sellPetTool(info)
	if not info then
		return false
	end

	local variants = {
		{ info.tool },
		{ info.name },
	}
	if info.id ~= nil then
		table.insert(variants, 1, { info.id })
		table.insert(variants, { { Id = info.id } })
		table.insert(variants, { { PetId = info.id } })
		table.insert(variants, { { UID = info.id } })
		table.insert(variants, { info.id, info.name })
		table.insert(variants, { info.name, info.id })
	end

	local ok = sendPacketArgVariants("SellPet", variants)
	local itemOk = sendPacketArgVariants("SellItem", variants)
	return ok or itemOk
end

function autoSellPets()
	if not isEnabled("autoSellPets") then
		return
	end

	local sold = 0
	local petTools = getSellablePetTools()
	for _, info in ipairs(petTools) do
		if not isEnabled("autoSellPets") then
			return
		end
		local before = countInventoryTools()
		if sellPetTool(info) then
			task.wait(0.2)
			if not info.tool.Parent or countInventoryTools() < before then
				sold += 1
			end
		end
	end

	if sold > 0 then
		stats.petsSold += sold
		refreshInventoryStats(true)
		updateStatsUI()
		setStatus(("Pet sell: sold %d selected pet(s)"):format(sold))
	else
		setStatus(#petTools == 0 and "Pet sell: no matching pets" or "Pet sell: sell packet made no change")
	end
end

function getPetsFolder()
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	return assets and assets:FindFirstChild("Pets")
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
		TextSize = 9,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Size = UDim2.new(1, 0, 0, 18),
		LayoutOrder = order,
	}, parent)
	make("UICorner", { CornerRadius = UDim.new(0, 6) }, box)
	make("UIPadding", {
		PaddingLeft = UDim.new(0, 7),
		PaddingRight = UDim.new(0, 7),
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

	row.CanvasSize = UDim2.fromOffset(0, math.max(1, math.ceil(visible / (columns or 2))) * 20)
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
	Position = UDim2.fromOffset(18, 250),
	Size = UDim2.fromOffset(238, 350),
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
	TextSize = 12,
	Size = UDim2.new(1, 0, 0, 22),
}, panel)
make("UICorner", { CornerRadius = UDim.new(0, 8) }, header)

local content = make("ScrollingFrame", {
	Name = "Content",
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	CanvasSize = UDim2.fromOffset(0, 0),
	Position = UDim2.fromOffset(5, 27),
	ScrollBarThickness = 3,
	Size = UDim2.new(1, -10, 1, -32),
}, panel)
local contentLayout = make("UIListLayout", {
	Padding = UDim.new(0, 2),
	SortOrder = Enum.SortOrder.LayoutOrder,
}, content)

contentLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
	content.CanvasSize = UDim2.fromOffset(0, contentLayout.AbsoluteContentSize.Y + 8)
end)

local tabButtons = {}
local tabPages = {}
local currentTabParent
local activeTabName = "Farm"

local tabBar = make("Frame", {
	Name = "Tabs",
	BackgroundTransparency = 1,
	Size = UDim2.new(1, 0, 0, 22),
	LayoutOrder = 1,
}, content)
make("UIListLayout", {
	FillDirection = Enum.FillDirection.Horizontal,
	Padding = UDim.new(0, 3),
	SortOrder = Enum.SortOrder.LayoutOrder,
}, tabBar)

local function refreshTabButtons()
	for name, button in pairs(tabButtons) do
		local active = name == activeTabName
		button.BackgroundColor3 = active and Color3.fromRGB(58, 111, 67) or Color3.fromRGB(34, 41, 42)
		button.TextColor3 = active and Color3.fromRGB(246, 255, 242) or Color3.fromRGB(201, 219, 202)
	end
	for name, page in pairs(tabPages) do
		local active = name == activeTabName
		page.Visible = active
		local layout = page:FindFirstChildOfClass("UIListLayout")
		if layout then
			page.Size = active and UDim2.new(1, 0, 0, layout.AbsoluteContentSize.Y + 4) or UDim2.new(1, 0, 0, 0)
		end
	end
end

local function makeTab(name, order)
	local button = make("TextButton", {
		Name = name .. "Tab",
		AutoButtonColor = false,
		BackgroundColor3 = Color3.fromRGB(34, 41, 42),
		BorderSizePixel = 0,
		Font = Enum.Font.GothamSemibold,
		Text = name,
		TextColor3 = Color3.fromRGB(201, 219, 202),
		TextSize = 9,
		Size = UDim2.new(0.25, -3, 1, 0),
		LayoutOrder = order,
	}, tabBar)
	make("UICorner", { CornerRadius = UDim.new(0, 6) }, button)
	tabButtons[name] = button
	button.Activated:Connect(function()
		activeTabName = name
		refreshTabButtons()
		content.CanvasPosition = Vector2.new(0, 0)
	end)

	local page = make("Frame", {
		Name = name .. "Page",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 1),
		LayoutOrder = 10,
		Visible = name == activeTabName,
	}, content)
	local pageLayout = make("UIListLayout", {
		Padding = UDim.new(0, 2),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, page)
	pageLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
		if page.Visible then
			page.Size = UDim2.new(1, 0, 0, pageLayout.AbsoluteContentSize.Y + 4)
		end
	end)
	tabPages[name] = page
	return page
end

makeTab("Farm", 1)
makeTab("Shops", 2)
makeTab("Pets", 3)
makeTab("Settings", 4)
currentTabParent = tabPages.Farm
refreshTabButtons()

local function setBuildTab(name)
	currentTabParent = tabPages[name] or tabPages.Farm
end

local statusLabel = make("TextLabel", {
	Name = "Status",
	BackgroundColor3 = Color3.fromRGB(14, 18, 19),
	BorderSizePixel = 0,
	Font = Enum.Font.Gotham,
	Text = state.lastStatus,
	TextColor3 = Color3.fromRGB(201, 219, 202),
	TextSize = 9,
	TextWrapped = true,
	TextXAlignment = Enum.TextXAlignment.Left,
	Size = UDim2.new(1, 0, 0, 20),
	LayoutOrder = 2,
}, content)
make("UICorner", { CornerRadius = UDim.new(0, 6) }, statusLabel)
make("UIPadding", {
	PaddingLeft = UDim.new(0, 7),
	PaddingRight = UDim.new(0, 7),
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
		TextSize = 9,
		TextWrapped = true,
		Size = UDim2.new(1, 0, 0, 18),
		LayoutOrder = order,
	}, currentTabParent or content)
	make("UICorner", { CornerRadius = UDim.new(0, 6) }, button)

	button.Activated:Connect(function()
		state[key] = not state[key]
		if not state[key] then
			bumpStopToken(key)
			running[key] = false
			if timers and timers[key] ~= nil then
				timers[key] = 0
			end
			if key == "autoSell" then
				bumpStopToken("sellWhenFull")
				running.sellWhenFull = false
				if timers then
					timers.sellWhenFull = 0
				end
			elseif key == "sellWhenFull" then
				bumpStopToken("autoSell")
				running.autoSell = false
				if timers then
					timers.autoSell = 0
				end
			elseif key == "fruitCollector" then
				fruitTargetCache.refreshedAt = 0
			end
		else
			bumpStopToken(key)
		end
		button.Text = ("%s: %s"):format(label, state[key] and "ON" or "OFF")
		button.BackgroundColor3 = state[key] and Color3.fromRGB(58, 111, 67) or Color3.fromRGB(34, 41, 42)
		saveConfig()
		setStatus(("%s %s"):format(label, state[key] and "enabled" or "disabled"))

		if key == "performanceMode" and state[key] then
			task.spawn(enablePerformanceMode)
		elseif (key == "hideGameButtons" or key == "hidePlotIcons" or key == "hideOwnPlants") and state[key] then
			task.spawn(applyPlayerVisualSettings)
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
		TextSize = 9,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, 0, 0, 10),
		LayoutOrder = order,
	}, currentTabParent or content)
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
		TextSize = 9,
		TextWrapped = true,
		Size = UDim2.new(1, 0, 0, 18),
		LayoutOrder = order,
	}, currentTabParent or content)
	make("UICorner", { CornerRadius = UDim.new(0, 6) }, button)
	button.Activated:Connect(onClick)
	return button
end

setBuildTab("Pets")
makeSectionLabel("Priority", 1)
makeToggle("Auto Buy Pets", "autoBuyPets", 2)
makeToggle("Auto Sell Pets", "autoSellPets", 3)
setBuildTab("Farm")
makeSectionLabel("Farm", 1)
makeToggle("Fruit Collector", "fruitCollector", 2)
makeToggle("Trowel Plants", "autoMovePlants", 3)
makeCommandButton("Set Trowel Target", 4, function()
	local root = getRoot()
	if root then
		CONFIG.movePlantPosition = { x = root.Position.X, y = root.Position.Y, z = root.Position.Z }
		saveConfig()
		setStatus("Saved current position for trowel target")
	end
end)
makeToggle("Auto Sell Inventory", "autoSell", 5)
setBuildTab("Shops")
makeSectionLabel("Shops", 1)
makeToggle("Auto Buy Seeds", "autoBuySeeds", 2)
makeToggle("Auto Buy Gear", "autoBuyGear", 3)
makeToggle("Auto Accept Mail", "autoAcceptMail", 4)
setBuildTab("Settings")
makeSectionLabel("Settings", 1)
makeToggle("Performance Mode", "performanceMode", 2)

local webhookBox = make("TextBox", {
	Name = "WebhookUrl",
	BackgroundColor3 = Color3.fromRGB(34, 41, 42),
	BorderSizePixel = 0,
	ClearTextOnFocus = false,
	Font = Enum.Font.GothamSemibold,
	PlaceholderText = "Webhook URL for selected stock/pets",
	Text = CONFIG.webhookUrl,
	TextColor3 = Color3.fromRGB(242, 247, 239),
	TextSize = 9,
	TextTruncate = Enum.TextTruncate.AtEnd,
	Size = UDim2.new(1, 0, 0, 20),
	LayoutOrder = 34,
}, currentTabParent or content)
make("UICorner", { CornerRadius = UDim.new(0, 6) }, webhookBox)
make("UIPadding", {
	PaddingLeft = UDim.new(0, 7),
	PaddingRight = UDim.new(0, 7),
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
	TextSize = 9,
	TextXAlignment = Enum.TextXAlignment.Left,
	Size = UDim2.new(1, 0, 0, 10),
	LayoutOrder = 35,
}, currentTabParent or content)

local statsFrame = make("Frame", {
	Name = "Stats",
	BackgroundColor3 = Color3.fromRGB(14, 18, 19),
	BorderSizePixel = 0,
	Size = UDim2.new(1, 0, 0, 74),
	LayoutOrder = 36,
}, currentTabParent or content)
make("UICorner", { CornerRadius = UDim.new(0, 6) }, statsFrame)
make("UIPadding", {
	PaddingTop = UDim.new(0, 3),
	PaddingBottom = UDim.new(0, 3),
	PaddingLeft = UDim.new(0, 6),
	PaddingRight = UDim.new(0, 6),
}, statsFrame)
make("UIListLayout", {
	Padding = UDim.new(0, 1),
	SortOrder = Enum.SortOrder.LayoutOrder,
}, statsFrame)

function makeStatsLabel(key, order)
	local label = make("TextLabel", {
		Name = key,
		BackgroundTransparency = 1,
		Font = Enum.Font.Gotham,
		Text = "",
		TextColor3 = Color3.fromRGB(201, 219, 202),
		TextSize = 9,
		TextTruncate = Enum.TextTruncate.AtEnd,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, 0, 0, 9),
		LayoutOrder = order,
	}, statsFrame)
	statsLabels[key] = label
	return label
end

makeStatsLabel("status", 1)
makeStatsLabel("systems", 2)
makeStatsLabel("inventory", 3)
makeStatsLabel("collect", 4)
makeStatsLabel("mail", 5)
makeStatsLabel("shops", 6)
makeStatsLabel("limits", 7)
refreshInventoryStats()
updateStatsUI()

function buildSeedSelector()
local parent = currentTabParent or content
local selectedSeedLabel = make("TextLabel", {
	Name = "SelectedSeedLabel",
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamSemibold,
	Text = "Seeds to buy",
	TextColor3 = Color3.fromRGB(221, 236, 216),
	TextSize = 9,
	TextXAlignment = Enum.TextXAlignment.Left,
	Size = UDim2.new(1, 0, 0, 10),
	LayoutOrder = 24,
}, parent)

local seedRow = make("ScrollingFrame", {
	Name = "SeedSelector",
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	CanvasSize = UDim2.fromOffset(0, 0),
	ScrollBarThickness = 3,
	ScrollingDirection = Enum.ScrollingDirection.Y,
	Size = UDim2.new(1, 0, 0, 42),
	LayoutOrder = 26,
}, parent)
make("UIGridLayout", {
	CellPadding = UDim2.fromOffset(3, 3),
	CellSize = UDim2.fromOffset(108, 16),
	SortOrder = Enum.SortOrder.LayoutOrder,
}, seedRow)

local seedLayout = seedRow:FindFirstChildOfClass("UIGridLayout")
local seedButtons = {}
local seedButtonCount = 0
local seedFilterText = ""

makeSelectorSearch(parent, 25, "Search seeds to buy", function(text)
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
		TextSize = 9,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Size = UDim2.fromOffset(108, 16),
		LayoutOrder = seedButtonCount,
	}, seedRow)
	make("UICorner", { CornerRadius = UDim.new(0, 6) }, button)

	seedButtons[seedName] = button
	refreshSeedButton(seedName)
	button.Visible = matchesSelectorFilter(seedName, seedFilterText)

	button.Activated:Connect(function()
		selectedSeeds[seedName] = not selectedSeeds[seedName]
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
setBuildTab("Shops")
buildSeedSelector()

function buildMoveSeedSelector()
local parent = currentTabParent or content
local moveSeedLabel = make("TextLabel", {
	Name = "MoveSeedLabel",
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamSemibold,
	Text = "Plants to move",
	TextColor3 = Color3.fromRGB(221, 236, 216),
	TextSize = 9,
	TextXAlignment = Enum.TextXAlignment.Left,
	Size = UDim2.new(1, 0, 0, 10),
	LayoutOrder = 30,
}, parent)

local moveSeedRow = make("ScrollingFrame", {
	Name = "MoveSeedSelector",
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	CanvasSize = UDim2.fromOffset(0, 0),
	ScrollBarThickness = 3,
	ScrollingDirection = Enum.ScrollingDirection.Y,
	Size = UDim2.new(1, 0, 0, 42),
	LayoutOrder = 32,
}, parent)
make("UIGridLayout", {
	CellPadding = UDim2.fromOffset(3, 3),
	CellSize = UDim2.fromOffset(108, 16),
	SortOrder = Enum.SortOrder.LayoutOrder,
}, moveSeedRow)

local moveSeedLayout = moveSeedRow:FindFirstChildOfClass("UIGridLayout")
local moveSeedButtons = {}
local moveSeedButtonCount = 0
local moveSeedFilterText = ""

makeSelectorSearch(parent, 31, "Search plants to move", function(text)
	moveSeedFilterText = text
	refreshSelectorFilter(moveSeedButtons, seedNames, moveSeedFilterText, moveSeedRow, 2)
end)

function refreshMoveSeedButton(seedName)
	local button = moveSeedButtons[seedName]
	if not button then
		return
	end

	local enabled = selectedMoveSeeds[seedName] == true
	button.Text = (enabled and "[x] " or "[ ] ") .. seedName
	button.BackgroundColor3 = enabled and Color3.fromRGB(58, 89, 121) or Color3.fromRGB(52, 60, 54)
end

function refreshMoveSeedCanvas()
	refreshSelectorFilter(moveSeedButtons, seedNames, moveSeedFilterText, moveSeedRow, 2)
end

function makeMoveSeedButton(seedName)
	if moveSeedButtons[seedName] then
		return
	end

	moveSeedButtonCount += 1
	local button = make("TextButton", {
		Name = "Move" .. seedName,
		AutoButtonColor = false,
		BackgroundColor3 = Color3.fromRGB(52, 60, 54),
		BorderSizePixel = 0,
		Font = Enum.Font.GothamSemibold,
		Text = seedName,
		TextColor3 = Color3.fromRGB(242, 247, 239),
		TextSize = 9,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Size = UDim2.fromOffset(108, 16),
		LayoutOrder = moveSeedButtonCount,
	}, moveSeedRow)
	make("UICorner", { CornerRadius = UDim.new(0, 6) }, button)

	moveSeedButtons[seedName] = button
	refreshMoveSeedButton(seedName)
	button.Visible = matchesSelectorFilter(seedName, moveSeedFilterText)

	button.Activated:Connect(function()
		selectedMoveSeeds[seedName] = not selectedMoveSeeds[seedName]
		refreshMoveSeedButton(seedName)
		saveConfig()
		setStatus((selectedMoveSeeds[seedName] and "Will move " or "Stopped moving ") .. seedName)
	end)

	refreshMoveSeedCanvas()
end

for _, seedName in ipairs(seedNames) do
	makeMoveSeedButton(seedName)
end

if moveSeedLayout then
	moveSeedLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(refreshMoveSeedCanvas)
end
refreshMoveSeedCanvas()

local moveSeedStockItems = getStockItemsFolder("SeedShop")
if moveSeedStockItems then
	for _, item in ipairs(moveSeedStockItems:GetChildren()) do
		makeMoveSeedButton(item.Name)
	end

	moveSeedStockItems.ChildAdded:Connect(function(item)
		task.wait()
		makeMoveSeedButton(item.Name)
	end)
end
end
setBuildTab("Farm")
buildMoveSeedSelector()

function buildGearSelector()
local parent = currentTabParent or content
local selectedGearLabel = make("TextLabel", {
	Name = "SelectedGearLabel",
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamSemibold,
	Text = "Gear to buy",
	TextColor3 = Color3.fromRGB(221, 236, 216),
	TextSize = 9,
	TextXAlignment = Enum.TextXAlignment.Left,
	Size = UDim2.new(1, 0, 0, 10),
	LayoutOrder = 30,
}, parent)

local gearRow = make("ScrollingFrame", {
	Name = "GearSelector",
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	CanvasSize = UDim2.fromOffset(0, 0),
	ScrollBarThickness = 3,
	ScrollingDirection = Enum.ScrollingDirection.Y,
	Size = UDim2.new(1, 0, 0, 42),
	LayoutOrder = 32,
}, parent)
make("UIGridLayout", {
	CellPadding = UDim2.fromOffset(3, 3),
	CellSize = UDim2.fromOffset(108, 16),
	SortOrder = Enum.SortOrder.LayoutOrder,
}, gearRow)

local gearLayout = gearRow:FindFirstChildOfClass("UIGridLayout")
local gearButtons = {}
local gearButtonCount = 0
local gearFilterText = ""

makeSelectorSearch(parent, 31, "Search gear to buy", function(text)
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
		TextSize = 9,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Size = UDim2.fromOffset(108, 16),
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
setBuildTab("Shops")
buildGearSelector()

function buildPetSelector()
local parent = currentTabParent or content
local selectedPetLabel = make("TextLabel", {
	Name = "SelectedPetLabel",
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamSemibold,
	Text = "Pets to buy",
	TextColor3 = Color3.fromRGB(221, 236, 216),
	TextSize = 9,
	TextXAlignment = Enum.TextXAlignment.Left,
	Size = UDim2.new(1, 0, 0, 10),
	LayoutOrder = 33,
}, parent)

local petRow = make("ScrollingFrame", {
	Name = "PetSelector",
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	CanvasSize = UDim2.fromOffset(0, 0),
	ScrollBarThickness = 3,
	ScrollingDirection = Enum.ScrollingDirection.Y,
	Size = UDim2.new(1, 0, 0, 42),
	LayoutOrder = 35,
}, parent)
make("UIGridLayout", {
	CellPadding = UDim2.fromOffset(3, 3),
	CellSize = UDim2.fromOffset(108, 16),
	SortOrder = Enum.SortOrder.LayoutOrder,
}, petRow)

local petLayout = petRow:FindFirstChildOfClass("UIGridLayout")
local petButtons = {}
local petButtonCount = 0
local petFilterText = ""

makeSelectorSearch(parent, 34, "Search pets to buy", function(text)
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
		TextSize = 9,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Size = UDim2.fromOffset(108, 16),
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
setBuildTab("Pets")
buildPetSelector()

function buildPetSellSelector()
local parent = currentTabParent or content
local petSellLabel = make("TextLabel", {
	Name = "SellPetLabel",
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamSemibold,
	Text = "Pets to sell",
	TextColor3 = Color3.fromRGB(221, 236, 216),
	TextSize = 9,
	TextXAlignment = Enum.TextXAlignment.Left,
	Size = UDim2.new(1, 0, 0, 10),
	LayoutOrder = 36,
}, parent)

local keepVariantsButton
keepVariantsButton = make("TextButton", {
	Name = "KeepAllPetVariants",
	AutoButtonColor = false,
	BackgroundColor3 = CONFIG.keepAllPetVariants and Color3.fromRGB(58, 111, 67) or Color3.fromRGB(34, 41, 42),
	BorderSizePixel = 0,
	Font = Enum.Font.GothamSemibold,
	Text = "Keep All Variants: " .. (CONFIG.keepAllPetVariants and "ON" or "OFF"),
	TextColor3 = Color3.fromRGB(235, 244, 233),
	TextSize = 9,
	TextWrapped = true,
	Size = UDim2.new(1, 0, 0, 18),
	LayoutOrder = 37,
}, parent)
make("UICorner", { CornerRadius = UDim.new(0, 6) }, keepVariantsButton)
keepVariantsButton.Activated:Connect(function()
	CONFIG.keepAllPetVariants = not CONFIG.keepAllPetVariants
	keepVariantsButton.Text = "Keep All Variants: " .. (CONFIG.keepAllPetVariants and "ON" or "OFF")
	keepVariantsButton.BackgroundColor3 = CONFIG.keepAllPetVariants and Color3.fromRGB(58, 111, 67) or Color3.fromRGB(34, 41, 42)
	saveConfig()
	setStatus("Pet sell keep all variants " .. (CONFIG.keepAllPetVariants and "enabled" or "disabled"))
end)

local petSellRow = make("ScrollingFrame", {
	Name = "PetSellSelector",
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	CanvasSize = UDim2.fromOffset(0, 0),
	ScrollBarThickness = 3,
	ScrollingDirection = Enum.ScrollingDirection.Y,
	Size = UDim2.new(1, 0, 0, 38),
	LayoutOrder = 39,
}, parent)
make("UIGridLayout", {
	CellPadding = UDim2.fromOffset(3, 3),
	CellSize = UDim2.fromOffset(108, 16),
	SortOrder = Enum.SortOrder.LayoutOrder,
}, petSellRow)

local petSellLayout = petSellRow:FindFirstChildOfClass("UIGridLayout")
local petSellButtons = {}
local petSellButtonCount = 0
local petSellFilterText = ""

makeSelectorSearch(parent, 38, "Search pets to sell", function(text)
	petSellFilterText = text
	refreshSelectorFilter(petSellButtons, petNames, petSellFilterText, petSellRow, 2)
end)

function refreshPetSellButton(petName)
	local button = petSellButtons[petName]
	if not button then
		return
	end
	local enabled = selectedSellPets[petName] == true
	button.Text = (enabled and "[x] " or "[ ] ") .. petName
	button.BackgroundColor3 = enabled and Color3.fromRGB(122, 65, 50) or Color3.fromRGB(52, 60, 54)
end

function refreshPetSellCanvas()
	refreshSelectorFilter(petSellButtons, petNames, petSellFilterText, petSellRow, 2)
end

function makePetSellButton(petName)
	if petSellButtons[petName] then
		return
	end
	petSellButtonCount += 1
	local button = make("TextButton", {
		Name = "Sell" .. petName,
		AutoButtonColor = false,
		BackgroundColor3 = Color3.fromRGB(52, 60, 54),
		BorderSizePixel = 0,
		Font = Enum.Font.GothamSemibold,
		Text = petName,
		TextColor3 = Color3.fromRGB(242, 247, 239),
		TextSize = 9,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Size = UDim2.fromOffset(108, 16),
		LayoutOrder = petSellButtonCount,
	}, petSellRow)
	make("UICorner", { CornerRadius = UDim.new(0, 6) }, button)
	petSellButtons[petName] = button
	refreshPetSellButton(petName)
	button.Visible = matchesSelectorFilter(petName, petSellFilterText)
	button.Activated:Connect(function()
		selectedSellPets[petName] = not selectedSellPets[petName]
		refreshPetSellButton(petName)
		saveConfig()
		setStatus((selectedSellPets[petName] and "Sell selected " or "Sell unselected ") .. petName)
	end)
	refreshPetSellCanvas()
end

for _, petName in ipairs(petNames) do
	makePetSellButton(petName)
end
if petSellLayout then
	petSellLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(refreshPetSellCanvas)
end
refreshPetSellCanvas()

local assetsForPetSell = ReplicatedStorage:FindFirstChild("Assets")
local petsFolderForSell = assetsForPetSell and assetsForPetSell:FindFirstChild("Pets")
if petsFolderForSell then
	petsFolderForSell.ChildAdded:Connect(function(pet)
		local baseName = stripVariantWords(pet.Name)
		addUniqueName(petNames, baseName)
		table.sort(petNames)
		makePetSellButton(baseName)
	end)
end
end
setBuildTab("Pets")
buildPetSellSelector()

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
	autoSell = 0,
	sellWhenFull = 0,
	autoMovePlants = 0,
	autoAcceptMail = 0,
	autoBuySeeds = 0,
	autoBuyGear = 0,
	autoBuyPets = 0,
	autoSellPets = 0,
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

function watchToolContainer(container)
	if not container then
		return
	end
	container.ChildAdded:Connect(invalidateSellableInventoryCache)
	container.ChildRemoved:Connect(invalidateSellableInventoryCache)
end

watchToolContainer(localPlayer:FindFirstChildOfClass("Backpack"))
localPlayer.ChildAdded:Connect(function(child)
	if child:IsA("Backpack") then
		watchToolContainer(child)
		invalidateSellableInventoryCache()
	end
end)
if localPlayer.Character then
	watchToolContainer(localPlayer.Character)
end
localPlayer.CharacterAdded:Connect(function(character)
	watchToolContainer(character)
	invalidateSellableInventoryCache()
end)

RunService.Heartbeat:Connect(function(deltaTime)
	schedulerAccumulator += deltaTime
	if schedulerAccumulator < CONFIG.schedulerInterval then
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
	timers.autoSell = state.autoSell and (timers.autoSell + deltaTime) or 0
	timers.sellWhenFull = state.sellWhenFull and (timers.sellWhenFull + deltaTime) or 0
	timers.autoMovePlants = state.autoMovePlants and (timers.autoMovePlants + deltaTime) or 0
	timers.autoAcceptMail = state.autoAcceptMail and (timers.autoAcceptMail + deltaTime) or 0
	timers.autoBuySeeds = state.autoBuySeeds and (timers.autoBuySeeds + deltaTime) or 0
	timers.autoBuyGear = state.autoBuyGear and (timers.autoBuyGear + deltaTime) or 0
	timers.autoBuyPets = state.autoBuyPets and (timers.autoBuyPets + deltaTime) or 0
	timers.autoSellPets = state.autoSellPets and (timers.autoSellPets + deltaTime) or 0
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
	local hasSellableInventory = false
	if state.sellWhenFull or state.autoSell then
		inventoryFull = refreshInventoryStats(false)
		if inventoryFull then
			invalidateSellableInventoryCache()
			inventoryFull = refreshInventoryStats(true)
		end
		hasSellableInventory = hasSellableFruitTools()
		sellNeeded = inventoryFull and hasSellableInventory
	end
	local urgentSellDue = hasSellableInventory and inventoryFull and (state.sellWhenFull or state.autoSell)
	local sellDue = hasSellableInventory and (urgentSellDue
		or (state.autoSell and timers.autoSell >= CONFIG.sellInterval))

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
	elseif not hasSellableInventory then
		timers.autoSell = 0
		timers.sellWhenFull = 0
	end

	local movementLocked = running.autoMovePlants
		or running.autoBuyPets
		or running.autoSellPets
		or sellDue
		or running.autoSell
		or running.sellWhenFull

	if state.autoMovePlants and timers.autoMovePlants >= 1.0 and not movementLocked then
		if tryRun("autoMovePlants", autoMovePlants) then
			timers.autoMovePlants = 0
		end
	end

	movementLocked = movementLocked or running.autoMovePlants
	local fruitMovementLocked = running.autoMovePlants
		or (hasSellableInventory and inventoryFull and (sellDue or running.autoSell or running.sellWhenFull))

	if state.autoAcceptMail and timers.autoAcceptMail >= CONFIG.mailInterval then
		if tryRun("autoAcceptMail", autoAcceptMail) then
			timers.autoAcceptMail = 0
		end
	end

	if state.autoBuyPets and timers.autoBuyPets >= CONFIG.petBuyInterval and not movementLocked then
		if tryRun("autoBuyPets", buyPets) then
			timers.autoBuyPets = 0
		end
	end

	if state.autoSellPets and timers.autoSellPets >= CONFIG.petSellInterval and not movementLocked then
		if tryRun("autoSellPets", autoSellPets) then
			timers.autoSellPets = 0
		end
	end

	if state.fruitCollector and timers.fruitCollector >= CONFIG.collectInterval then
		if fruitMovementLocked or os.clock() < fruitCollectionPausedUntil then
			timers.fruitCollector = CONFIG.collectInterval
		else
			if tryRun("fruitCollector", collectFruit) then
				timers.fruitCollector = 0
			end
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

