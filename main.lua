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
	collectInterval = 1.15,
	plantInterval = 0.9,
	sellInterval = 12.0,
	buyInterval = 5.0,
	rainbowCollectInterval = 2.5,
	petBuyInterval = 0.75,
	cacheRefreshInterval = 12.0,
	dropCacheRefreshInterval = 2.5,
	inventoryRefreshInterval = 1.5,
	guiInventoryRefreshInterval = 5.0,
	maxFruitCollectPerTick = 32,
	maxFruitScanPerRoot = 1200,
	maxDropCollectPerTick = 8,
	maxDropScanPerRoot = 2500,
	maxInventoryItems = 200,
	lowRaritySeedLimit = 10,
	maxVisualPets = 24,
	maxVisualPetTools = 24,
	maxEquippedVisualPets = 3,
	visualPetAmount = 24,
	visualPetVariant = "Normal",
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
	autoSell = false,
	autoBuySeeds = false,
	seedShopEnabled = true,
	autoBuyGear = false,
	gearShopEnabled = true,
	autoCollectRainbowSeeds = false,
	autoBuyPets = false,
	performanceMode = false,
	lastStatus = "Ready",
}

local selectedSeeds = {}

local blacklistedSeeds = {}

local gearNames = {}

local selectedGears = {}

local petNames = {}

local buyPetNames = {}

local selectedPets = {}

local selectedVisualPets = {}

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
		"buyInterval",
		"lowRaritySeedLimit",
		"visualPetAmount",
		"visualPetVariant",
		"selectedSeed",
		"plantRadius",
		"webhookUrl",
	})
	copyKnownValues(decoded.state, state, {
		"collectTeleport",
		"seedShopEnabled",
		"gearShopEnabled",
	})

	selectedSeeds = copyMap(decoded.selectedSeeds)
	blacklistedSeeds = copyMap(decoded.blacklistedSeeds)
	selectedGears = copyMap(decoded.selectedGears)
	selectedPets = copyMap(decoded.selectedPets)
	selectedVisualPets = copyMap(decoded.selectedVisualPets)

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
			buyInterval = CONFIG.buyInterval,
			lowRaritySeedLimit = CONFIG.lowRaritySeedLimit,
			visualPetAmount = CONFIG.visualPetAmount,
			visualPetVariant = CONFIG.visualPetVariant,
			selectedSeed = CONFIG.selectedSeed,
			plantRadius = CONFIG.plantRadius,
			webhookUrl = CONFIG.webhookUrl,
		},
		state = {
			fruitCollector = state.fruitCollector,
			collectTeleport = state.collectTeleport,
			seedPlacer = state.seedPlacer,
			autoSell = state.autoSell,
			autoBuySeeds = state.autoBuySeeds,
			seedShopEnabled = state.seedShopEnabled,
			autoBuyGear = state.autoBuyGear,
			gearShopEnabled = state.gearShopEnabled,
			autoCollectRainbowSeeds = state.autoCollectRainbowSeeds,
			autoBuyPets = state.autoBuyPets,
			performanceMode = state.performanceMode,
		},
		selectedSeeds = selectedSeeds,
		blacklistedSeeds = blacklistedSeeds,
		selectedGears = selectedGears,
		selectedPets = selectedPets,
		selectedVisualPets = selectedVisualPets,
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

	local ok = pcall(function()
		requestFunction({
			Url = CONFIG.webhookUrl,
			Method = "POST",
			Headers = {
				["Content-Type"] = "application/json",
			},
			Body = HttpService:JSONEncode(payload),
		})
	end)

	if ok and key then
		webhookSentAt[key] = now
	end

	return ok
end

local function shouldNotifySelected(map, name)
	return name and name ~= "" and map[name] == true
end

local function notifyStock(shopName, itemName)
	if shouldNotifySelected(selectedSeeds, itemName) or shouldNotifySelected(selectedGears, itemName) then
		sendWebhook(
			shopName .. " stock",
			itemName .. " is now in stock.",
			"stock:" .. shopName .. ":" .. itemName
		)
	end
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

local visualVariantWords = {
	"Big",
	"Huge",
	"Giant",
	"Rainbow",
	"Super",
	"Gold",
	"Golden",
	"Shiny",
}

local visualPetVariants = {
	"Normal",
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
	seedAttempts = 0,
	seedsSkippedLimit = 0,
	seedsSkippedBlacklist = 0,
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
		"autoSell",
		"autoBuySeeds",
		"autoBuyGear",
		"autoCollectRainbowSeeds",
		"autoBuyPets",
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
	for _, word in ipairs(visualVariantWords) do
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

local function getStockItemsFolder(shopName)
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
local teleportToPart
local teleportToModelOrPart
local isInventorySeedTool

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

local function invalidateOwnGardenCache()
	ownGardenCache.checkedAt = 0
	cache.ownGardenDescendants = nil
	cache.ownGardenAt = nil
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
		for _, name in ipairs({ "Plants", "Fruits", "Fruit", "Crops", "Harvest", "Harvests", "Drops" }) do
			local child = plot:FindFirstChild(name)
			if child then
				added = addUniqueInstance(roots, child) or added
			end
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
				label.Text = ("Planting: %d placed | %d seed(s) selected | %d avoided"):format(stats.seedsPlanted, countSelected(selectedSeeds), countSelected(blacklistedSeeds))
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
	return nil
end

local function collectPrompt(prompt)
	local part = getPromptPart and getPromptPart(prompt)
	if part and not state.collectTeleport and getPromptDistance(prompt) > (prompt.MaxActivationDistance or 10) then
		stats.collectSkippedRange += 1
		return false
	end

	local target = getCollectFruitTarget(prompt)
	local packeted = target ~= nil and sendPacket("CollectFruit", target)
	if packeted then
		return true
	end

	if part and state.collectTeleport then
		local model = prompt and prompt:FindFirstAncestorWhichIsA("Model")
		if model then
			teleportToModelOrPart(model, part, 3)
		else
			teleportToPart(part, 3)
		end
	end

	local prompted = triggerPrompt(prompt, true)
	packeted = target ~= nil and sendPacket("CollectFruit", target)

	return prompted or packeted
end

local function collectFruitTarget(target)
	if not target then
		return false
	end

	local sent = sendPacket("CollectFruit", target)
		or sendPacket("HarvestFruit", target)
		or sendPacket("Collect", target)
		or sendPacket("Harvest", target)
	if sent then
		return true
	end

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

	sent = sendPacket("CollectFruit", target)
		or sendPacket("HarvestFruit", target)
		or sendPacket("Collect", target)
		or sendPacket("Harvest", target)

	if not sent and part then
		sent = touchPart(part)
	end

	return sent
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

	for index, seedName in ipairs(seedNames) do
		if string.find(haystack, string.lower(seedName), 1, true) then
			priority += index * 10
		end
	end

	return priority
end

function triggerPrompt(prompt, skipTouch)
	local part = getPromptPart and getPromptPart(prompt)
	if part and not skipTouch then
		teleportToPart(part, 3)
		task.wait(0.05)
	end

	if typeof(fireproximityprompt) == "function" then
		fireproximityprompt(prompt)
		return true
	end

	local ok = pcall(function()
		prompt:InputHoldBegin()
		task.wait(math.max(prompt.HoldDuration, 0.05))
		prompt:InputHoldEnd()
	end)

	if ok then
		return true
	end

	return false
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

	local fired = 0
	local targets = {}
	local seenTargets = {}
	local roots = getOwnGardenRoots()

	if #roots == 0 then
		setStatus("Fruit collector: no owned garden found")
		return
	end

	for index, root in ipairs(roots) do
		if not isEnabled("fruitCollector") then
			return
		end

		local scanned = 0
		for _, descendant in ipairs(getCachedDescendants("garden" .. index, root)) do
			if not isEnabled("fruitCollector") then
				return
			end

			if isUsableHarvestPrompt(descendant) then
				local target = getCollectFruitTarget(descendant) or descendant
				if not seenTargets[target] then
					seenTargets[target] = true
					table.insert(targets, {
						prompt = descendant,
						target = target,
						priority = getFruitPriority(descendant),
					})
				end
			elseif isLikelyFruitTarget(descendant) then
				local target = getFruitObjectTarget(descendant)
				if not seenTargets[target] then
					seenTargets[target] = true
					table.insert(targets, {
						target = target,
						priority = getFruitPriority(target),
					})
				end
			end

			if #targets >= CONFIG.maxFruitCollectPerTick * 2 then
				break
			end
			scanned += 1
			if scanned >= CONFIG.maxFruitScanPerRoot then
				break
			end
		end

		if #targets >= CONFIG.maxFruitCollectPerTick * 2 then
			break
		end
	end

	table.sort(targets, function(left, right)
		return left.priority > right.priority
	end)

	for index, entry in ipairs(targets) do
		if not isEnabled("fruitCollector") then
			return
		end

		if index > CONFIG.maxFruitCollectPerTick then
			break
		end
		local collected = entry.prompt and collectPrompt(entry.prompt) or collectFruitTarget(entry.target)
		if collected then
			fired += 1
			stats.fruitCollected += 1
			task.wait(0.015)
		end
	end

	stats.fruitTargetsChecked += #targets
	refreshInventoryStats()
	updateStatsUI()
	setStatus(("Fruit collector: collected %d/%d target(s)"):format(fired, #targets))
end

local function getEquippedSeedTool(seedName)
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

local function getSelectedSeedList()
	local selected = {}
	local seen = {}

	for _, seedName in ipairs(seedNames) do
		if selectedSeeds[seedName] and not blacklistedSeeds[seedName] then
			seen[seedName] = true
			table.insert(selected, seedName)
		end
	end

	for seedName, enabled in pairs(selectedSeeds) do
		if enabled and not blacklistedSeeds[seedName] and not seen[seedName] then
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
		for _, descendant in ipairs(getCachedDescendants("seedCount" .. seedName, root)) do
			if descendant:IsA("Model") and string.find(string.lower(descendant.Name), needle, 1, true) then
				count += 1
			end
		end
	end

	return count
end

local function canPlaceSeed(seedName)
	if blacklistedSeeds[seedName] then
		stats.seedsSkippedBlacklist += 1
		return false, "avoid"
	end

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

	local angle = ((index or 1) - 1) * math.rad(45)
	local offset = Vector3.new(math.cos(angle), 0, math.sin(angle)) * math.min(CONFIG.plantRadius, 6)
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
			task.wait(0.005)
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

	if item:GetAttribute("VisualPetTool") or item:GetAttribute("Pet") or item:GetAttribute("PetName") then
		return true
	end

	local parent = item.Parent
	while parent do
		if parent.Name == "GardenToolsVisualPets" then
			return true
		end
		parent = parent.Parent
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

local function getSelectedVisualPetList()
	local selected = {}

	for _, petName in ipairs(petNames) do
		if selectedVisualPets[petName] then
			table.insert(selected, petName)
		end
	end

	return selected
end

function touchPart(part)
	local root = getRoot()
	if not root or not part or not part:IsA("BasePart") then
		return false
	end

	if typeof(firetouchinterest) == "function" then
		pcall(firetouchinterest, root, part, 0)
		task.wait()
		pcall(firetouchinterest, root, part, 1)
		return true
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

	for _, variant in ipairs(variants) do
		if sendPacket("PurchaseSeed", variant) then
			return true
		end

		if sendPacket("PurchaseSeed", variant, 1) then
			return true
		end
	end

	return false
end

local function looksLikeGoldRainbowDrop(instance)
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

local function autoCollectRainbowSeeds()
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

local function enablePerformanceMode()
	local changed = 0

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

	for _, descendant in ipairs(workspace:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.Material = Enum.Material.SmoothPlastic
			descendant.Reflectance = 0
			descendant.CastShadow = false
			changed += 1
		elseif descendant:IsA("Decal") or descendant:IsA("Texture") then
			descendant.Transparency = 1
			changed += 1
		elseif descendant:IsA("ParticleEmitter")
			or descendant:IsA("Trail")
			or descendant:IsA("Beam")
			or descendant:IsA("Smoke")
			or descendant:IsA("Fire")
			or descendant:IsA("Sparkles")
		then
			descendant.Enabled = false
			changed += 1
		elseif descendant:IsA("PointLight")
			or descendant:IsA("SpotLight")
			or descendant:IsA("SurfaceLight")
		then
			descendant.Enabled = false
			changed += 1
		end
	end

	setStatus(("Performance mode: simplified %d object(s)"):format(changed))
end

local function plantSeed()
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

	for index, seedName in ipairs(getSelectedSeedList()) do
		if not isEnabled("seedPlacer") then
			return
		end

		local canPlace, reason = canPlaceSeed(seedName)
		if not canPlace then
			missing += 1
			if reason == "avoid" then
				task.wait(0.02)
			end
			continue
		end

		local tool = getEquippedSeedTool(seedName)
		if tool then
			table.insert(readySeeds, {
				name = seedName,
				tool = tool,
			})
		else
			missing += 1
		end
	end

	if #readySeeds == 0 then
		setStatus(("Seed placer: no selected seed tool found (%d missing)"):format(missing))
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

	for index, entry in ipairs(readySeeds) do
		if not isEnabled("seedPlacer") then
			return
		end

		local tool = entry.tool
		if tool and tool.Parent then
			local position = getSeedPlantPosition(index, gardenPosition)
			pcall(function()
				tool:Activate()
			end)

			if position then
				attempts += tryPlantSeedRemote(entry.name, position)
			end

			pcall(function()
				tool:Activate()
			end)

			planted += 1
			task.wait(0.025)
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

local function autoSell()
	if not isEnabled("autoSell") then
		return
	end

	local sellableTools = getSellableFruitTools()
	if #sellableTools == 0 then
		setStatus("Sell: nothing to sell")
		return
	end

	local actions = 0
	local stand = getPath(workspace, "Map.Stands.Sell.Part")
	if not isEnabled("autoSell") then
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
		if not isEnabled("autoSell") then
			return
		end

		if sendPacket(packetName) then
			actions += 1
			task.wait(0.05)
		end
	end

	for _, tool in ipairs(sellableTools) do
		if not isEnabled("autoSell") then
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
		if not isEnabled("autoSell") then
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

local function buyOneSeed(seedName)
	if purchaseSeedRemote(seedName) then
		return true, "Seed: " .. seedName
	end

	local seedFrame = getSeedFrame(seedName)

	local clicked = false
	if seedFrame then
		local mainFrame = seedFrame:FindFirstChild("Main_Frame", true)
		local rowButton = mainFrame and mainFrame:FindFirstChild("TextButton")
		if rowButton and rowButton:IsA("GuiButton") and activateButton(rowButton) then
			clicked = true
			task.wait(0.08)
		end

		for _, buttonName in ipairs({ "Sheckles_Buy", "CashBuy", "Buy", "TextButton" }) do
			local button = seedFrame:FindFirstChild(buttonName, true)
			if button and button:IsA("GuiButton") and activateButton(button) then
				clicked = true
				task.wait(0.04)
			end
		end

		for _, descendant in ipairs(seedFrame:GetDescendants()) do
			if descendant:IsA("GuiButton") and descendant ~= rowButton and activateButton(descendant) then
				clicked = true
				task.wait(0.04)
			end
		end
	end

	if clicked then
		return true, "Seed: fallback " .. seedName
	else
		return false, "Seed: failed " .. seedName
	end
end

local function buySeed()
	if not isEnabled("autoBuySeeds") then
		return
	end

	if not state.seedShopEnabled then
		setStatus("Auto buy: seed shop disabled")
		return
	end

	local bought = 0
	local lastMessage = "Auto buy: no seeds selected"

	for _, seedName in ipairs(getSelectedSeedList()) do
		if not isEnabled("autoBuySeeds") then
			return
		end

		local ok, message = buyOneSeed(seedName)
		lastMessage = message
		if ok then
			bought += 1
			task.wait(0.12)
		end
	end

	if bought > 0 then
		stats.seedsBought += bought
		refreshInventoryStats()
		updateStatsUI()
		setStatus(("Auto buy: tried %d selected seed(s)"):format(bought))
	else
		setStatus(lastMessage)
	end
end

local function buyOneGear(gearName)
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

local function buyGear()
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

local function buyOnePet(petName)
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

local function buyPets()
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

local visualPetFolder
local showPetInfo = function() end

local function getPetsFolder()
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	return assets and assets:FindFirstChild("Pets")
end

local function getVisualPetFolder()
	if visualPetFolder and visualPetFolder.Parent then
		return visualPetFolder
	end

	visualPetFolder = workspace:FindFirstChild("GardenToolsVisualPets")
	if not visualPetFolder then
		visualPetFolder = Instance.new("Folder")
		visualPetFolder.Name = "GardenToolsVisualPets"
		visualPetFolder.Parent = workspace
	end

	return visualPetFolder
end

local function getModelRootPart(instance)
	if instance:IsA("BasePart") then
		return instance
	end

	if not instance:IsA("Model") then
		return nil
	end

	return instance.PrimaryPart
		or instance:FindFirstChild("RootPart", true)
		or instance:FindFirstChild("HumanoidRootPart", true)
		or instance:FindFirstChildWhichIsA("BasePart", true)
end

local function prepVisualPet(instance, anchorRootOnly)
	local rootPart = anchorRootOnly and getModelRootPart(instance) or nil

	for _, descendant in ipairs(instance:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.Anchored = anchorRootOnly and descendant == rootPart or not anchorRootOnly
			descendant.CanCollide = false
			descendant.CanTouch = false
			descendant.CanQuery = false
			descendant.CastShadow = false
		elseif descendant:IsA("Script") or descendant:IsA("LocalScript") then
			descendant.Disabled = true
		end
	end

	if instance:IsA("BasePart") then
		instance.Anchored = true
		instance.CanCollide = false
		instance.CanTouch = false
		instance.CanQuery = false
		instance.CastShadow = false
	end
end

local petDataModule

local function getPetDataModule()
	if petDataModule ~= nil then
		return petDataModule
	end

	petDataModule = false
	local sharedData = ReplicatedStorage:FindFirstChild("SharedData")
	local petDataScript = sharedData and sharedData:FindFirstChild("PetData")
	if petDataScript and petDataScript:IsA("ModuleScript") then
		pcall(function()
			petDataModule = require(petDataScript)
		end)
	end

	return petDataModule
end

local function normalizeIconAsset(value)
	if type(value) == "number" then
		return "rbxassetid://" .. tostring(value)
	end

	if type(value) ~= "string" or value == "" then
		return ""
	end

	if string.find(value, "rbxasset", 1, true) or string.find(value, "http", 1, true) then
		return value
	end

	if tonumber(value) then
		return "rbxassetid://" .. value
	end

	return ""
end

local function compactName(value)
	return string.lower(string.gsub(tostring(value or ""), "[%s_%-]", ""))
end

local function getPetModulesFolder()
	local sharedModules = ReplicatedStorage:FindFirstChild("SharedModules")
	return sharedModules and sharedModules:FindFirstChild("PetModules")
end

local function getGearImageValue(name)
	local gearImages = getGearImagesFolder()
	local value = gearImages and gearImages:FindFirstChild(name)
	if value and value:IsA("StringValue") then
		return normalizeIconAsset(value.Value)
	end
	return ""
end

local function hasKnownPetBase(baseName)
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

local function refreshPetNamesFromGearImages()
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

local function findIconField(data)
	if type(data) ~= "table" then
		return ""
	end

	for _, key in ipairs({ "Icon", "IconId", "Image", "ImageId", "InventoryIcon", "InventoryImage", "Thumbnail", "ThumbnailImage", "TextureId", "TextureID" }) do
		local icon = normalizeIconAsset(data[key])
		if icon ~= "" then
			return icon
		end
	end

	return ""
end

local function findPetIconInData(data, petName, seen)
	if type(data) ~= "table" then
		return ""
	end

	seen = seen or {}
	if seen[data] then
		return ""
	end
	seen[data] = true

	local wanted = compactName(petName)
	for key, value in pairs(data) do
		if compactName(key) == wanted then
			local icon = normalizeIconAsset(value)
			if icon ~= "" then
				return icon
			end

			icon = findIconField(value)
			if icon ~= "" then
				return icon
			end
		end

		if type(value) == "table" then
			local nameMatches = compactName(value.Name) == wanted
				or compactName(value.DisplayName) == wanted
				or compactName(value.Pet) == wanted
				or compactName(value.PetName) == wanted
			if nameMatches then
				local icon = findIconField(value)
				if icon ~= "" then
					return icon
				end
			end

			local nestedIcon = findPetIconInData(value, petName, seen)
			if nestedIcon ~= "" then
				return nestedIcon
			end
		end
	end

	return ""
end

local function getPetIcon(petName, template, displayName)
	local gearIcon = getGearImageValue(displayName or petName)
	if gearIcon ~= "" then
		return gearIcon
	end

	gearIcon = getGearImageValue(petName)
	if gearIcon ~= "" then
		return gearIcon
	end

	local petData = getPetDataModule()
	local dataIcon = findPetIconInData(petData, petName)
	if dataIcon ~= "" then
		return dataIcon
	end

	for _, attrName in ipairs({ "Icon", "IconId", "Image", "ImageId", "InventoryIcon", "InventoryImage", "Thumbnail", "ThumbnailImage" }) do
		local value = template:GetAttribute(attrName)
		local icon = normalizeIconAsset(value)
		if icon ~= "" then
			return icon
		end
	end

	return ""
end

local function getVariantFlags(variant)
	variant = tostring(variant or "Normal")
	local isHuge = string.find(variant, "Giant", 1, true) ~= nil or string.find(variant, "Huge", 1, true) ~= nil
	local isBig = string.find(variant, "Big", 1, true) ~= nil
	local isRainbow = string.find(variant, "Rainbow", 1, true) ~= nil
	local isGold = string.find(variant, "Gold", 1, true) ~= nil or string.find(variant, "Golden", 1, true) ~= nil
	return isHuge, isRainbow, isBig, isGold
end

local function findBasePetTemplate(petsFolder, petName)
	local exact = petsFolder:FindFirstChild(petName)
	if exact then
		return exact
	end

	local wanted = compactName(petName)
	for _, child in ipairs(petsFolder:GetChildren()) do
		if compactName(stripVariantWords(child.Name)) == wanted then
			return child
		end
	end

	return nil
end

local function findVisualPetTemplate(petsFolder, petName, variant)
	variant = variant or "Normal"
	if variant == "Normal" then
		return findBasePetTemplate(petsFolder, petName), "Normal", false
	end

	local compactPet = compactName(petName)
	local compactVariant = compactName(variant)
	for _, child in ipairs(petsFolder:GetChildren()) do
		local childVariant = extractVariantLabel(child.Name, stripVariantWords(child.Name))
		local baseName = stripVariantWords(child.Name)
		if compactName(baseName) == compactPet and compactName(childVariant) == compactVariant then
			return child, childVariant, true
		end
	end

	local displayName = variant .. " " .. petName
	if getGearImageValue(displayName) ~= "" then
		local baseTemplate = findBasePetTemplate(petsFolder, petName)
		if baseTemplate then
			return baseTemplate, variant, false
		end
	end

	local baseTemplate = findBasePetTemplate(petsFolder, petName)
	if baseTemplate then
		return baseTemplate, variant, false
	end

	return nil, nil, false
end

local function refreshVisualPetVariantsFromAssets()
	local petsFolder = getPetsFolder()
	if petsFolder then
		for _, pet in ipairs(petsFolder:GetChildren()) do
			local baseName = stripVariantWords(pet.Name)
			local variant = extractVariantLabel(pet.Name, baseName)
			if variant ~= "" then
				addUniqueName(visualPetVariants, variant)
			end
		end
	end

	local gearImages = getGearImagesFolder()
	if gearImages then
		for _, imageValue in ipairs(gearImages:GetChildren()) do
			if imageValue:IsA("StringValue") then
				local baseName = stripVariantWords(imageValue.Name)
				local variant = extractVariantLabel(imageValue.Name, baseName)
				if variant ~= "" and hasKnownPetBase(baseName) then
					addUniqueName(visualPetVariants, variant)
				end
			end
		end
	end

	table.sort(visualPetVariants, function(a, b)
		if a == "Normal" then
			return true
		elseif b == "Normal" then
			return false
		end
		return a < b
	end)
end

local function isVisualVariantAvailable(variant)
	if variant == "Normal" then
		return true
	end

	local petsFolder = getPetsFolder()
	if not petsFolder then
		return false
	end

	local selected = getSelectedVisualPetList()
	if #selected == 0 then
		for _, petName in ipairs(petNames) do
			table.insert(selected, petName)
		end
	end

	for _, petName in ipairs(selected) do
		if findVisualPetTemplate(petsFolder, petName, variant) then
			return true
		end
	end

	return false
end

local function applyVisualPetVariant(instance, variant, usedVariantAsset)
	local wantsGiant, wantsRainbow, wantsBig, wantsGold = getVariantFlags(variant)
	if variant and variant ~= "Normal" then
		instance:SetAttribute("Variant", variant)
	end

	if wantsGiant then
		instance:SetAttribute("Giant", true)
		instance:SetAttribute("SizeMultiplier", 2)
	elseif wantsBig then
		instance:SetAttribute("Big", true)
		instance:SetAttribute("SizeMultiplier", 1.45)
	end

	if wantsRainbow then
		instance:SetAttribute("Mutation", "Rainbow")
		instance:SetAttribute("Rainbow", true)
	elseif wantsGold then
		instance:SetAttribute("Mutation", "Gold")
		instance:SetAttribute("Gold", true)
	end

	if (wantsGiant or wantsBig) and not usedVariantAsset and instance:IsA("Model") then
		pcall(function()
			instance:ScaleTo(wantsGiant and 2 or 1.45)
		end)
	end

	if not usedVariantAsset and (wantsRainbow or wantsGold) then
		local rootPart = getModelRootPart(instance)
		if instance:IsA("BasePart") then
			if wantsGold then
				instance.Color = Color3.fromRGB(255, 198, 54)
				instance.Material = Enum.Material.Neon
				instance.Reflectance = math.max(instance.Reflectance, 0.18)
			elseif wantsRainbow then
				instance.Material = Enum.Material.Neon
				instance.Reflectance = math.max(instance.Reflectance, 0.12)
			end
		end

		for _, descendant in ipairs(instance:GetDescendants()) do
			if descendant:IsA("BasePart") then
				if wantsGold then
					descendant.Color = Color3.fromRGB(255, 198, 54)
					descendant.Material = Enum.Material.Neon
					descendant.Reflectance = math.max(descendant.Reflectance, 0.18)
				elseif wantsRainbow then
					descendant.Material = Enum.Material.Neon
					descendant.Reflectance = math.max(descendant.Reflectance, 0.12)
				end
			end
		end

		if rootPart then
			local light = Instance.new("PointLight")
			light.Name = "VariantGlow"
			light.Brightness = wantsGold and 1.8 or 1.4
			light.Range = wantsGold and 12 or 14
			light.Color = wantsGold and Color3.fromRGB(255, 213, 74) or Color3.fromRGB(170, 92, 255)
			light.Parent = rootPart

			if wantsRainbow then
				local sparkles = Instance.new("Sparkles")
				sparkles.Name = "RainbowVariantSparkles"
				sparkles.SparkleColor = Color3.fromRGB(160, 95, 255)
				sparkles.Parent = rootPart
			end
		end
	end
end

local function playPetAnimations(instance)
	for _, descendant in ipairs(instance:GetDescendants()) do
		if descendant:IsA("Animator") then
			for _, track in ipairs(descendant:GetPlayingAnimationTracks()) do
				pcall(function()
					track:Stop(0)
				end)
			end
		end
	end
end

local function makeLocalPetTool(petName, template, slot, variant, usedVariantAsset)
	local backpack = localPlayer:FindFirstChildOfClass("Backpack")
	if not backpack then
		return false
	end

	local wantsGiant, wantsRainbow, wantsBig, wantsGold = getVariantFlags(variant)
	local toolName = petName
	if variant and variant ~= "Normal" then
		toolName = variant .. " " .. petName
	end

	local tool = Instance.new("Tool")
	tool.Name = toolName
	tool.ToolTip = toolName
	tool.RequiresHandle = true
	tool.CanBeDropped = false
	tool:SetAttribute("VisualPetTool", true)
	tool:SetAttribute("PetName", petName)
	tool:SetAttribute("Pet", petName)
	tool:SetAttribute("PetId", ("local-%s-%d-%d"):format(string.gsub(petName, "%s+", "-"), slot or 0, math.floor(os.clock() * 1000)))
	tool:SetAttribute("Count", 0)
	tool:SetAttribute("Slot", slot or 0)
	if variant and variant ~= "Normal" then
		tool:SetAttribute("Variant", variant)
	end
	if wantsGiant then
		tool:SetAttribute("Giant", true)
		tool:SetAttribute("SizeMultiplier", 2)
	elseif wantsBig then
		tool:SetAttribute("Big", true)
		tool:SetAttribute("SizeMultiplier", 1.45)
	end
	if wantsRainbow then
		tool:SetAttribute("Mutation", "Rainbow")
		tool:SetAttribute("Rainbow", true)
	elseif wantsGold then
		tool:SetAttribute("Mutation", "Gold")
		tool:SetAttribute("Gold", true)
	end

	local icon = getPetIcon(petName, template, toolName)
	if icon ~= "" then
		tool.TextureId = icon
		tool:SetAttribute("Icon", icon)
		tool:SetAttribute("InventoryIcon", icon)
	end

	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(1, 1, 1)
	handle.Transparency = 1
	handle.CanCollide = false
	handle.CanTouch = false
	handle.CanQuery = false
	handle.Massless = true
	handle.Parent = tool

	tool.Activated:Connect(function()
		showPetInfo(petName, variant or "Normal", icon, tool)
	end)

	tool.Parent = backpack
	return true
end

local function clearVisualPetTools()
	local backpack = localPlayer:FindFirstChildOfClass("Backpack")
	local character = localPlayer.Character

	for _, container in ipairs({ backpack, character }) do
		if container then
			for _, child in ipairs(container:GetChildren()) do
				if child:IsA("Tool") and child:GetAttribute("VisualPetTool") then
					child:Destroy()
				end
			end
		end
	end
end

local function countVisualPetTools()
	local count = 0
	local backpack = localPlayer:FindFirstChildOfClass("Backpack")
	local character = localPlayer.Character

	for _, container in ipairs({ backpack, character }) do
		if container then
			for _, child in ipairs(container:GetChildren()) do
				if child:IsA("Tool") and child:GetAttribute("VisualPetTool") then
					count += 1
				end
			end
		end
	end

	return count
end

local function trimVisualPets()
	local folder = getVisualPetFolder()
	local children = folder:GetChildren()
	table.sort(children, function(a, b)
		return (a:GetAttribute("SpawnedAt") or 0) < (b:GetAttribute("SpawnedAt") or 0)
	end)

	while #children > CONFIG.maxVisualPets do
		local oldest = table.remove(children, 1)
		if oldest then
			oldest:Destroy()
		end
	end
end

local function getPetPivot(instance)
	if instance:IsA("Model") then
		return instance:GetPivot()
	end

	if instance:IsA("BasePart") then
		return instance.CFrame
	end

	return nil
end

local function storeVisualOrientationOffset(instance)
	local pivot = getPetPivot(instance)
	if not pivot then
		return
	end

	local offset = Instance.new("CFrameValue")
	offset.Name = "VisualOrientationOffset"
	offset.Value = pivot.Rotation
	offset.Parent = instance
end

local function applyVisualOrientationOffset(instance, target)
	local offset = instance:FindFirstChild("VisualOrientationOffset")
	if offset and offset:IsA("CFrameValue") then
		return CFrame.new(target.Position) * offset.Value
	end

	return target
end

local function moveVisualPet(instance, target)
	pcall(function()
		target = applyVisualOrientationOffset(instance, target)
		if instance:IsA("Model") then
			instance:PivotTo(target)
		elseif instance:IsA("BasePart") then
			instance.CFrame = target
		end
	end)
end

local function addVisualPetNameplate(instance, petName, variant)
	local rootPart = getModelRootPart(instance)
	if not rootPart then
		return
	end

	local labelText = petName
	if variant and variant ~= "Normal" then
		labelText = variant .. " " .. petName
	end

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "PetNameplate"
	billboard.AlwaysOnTop = true
	billboard.Enabled = false
	billboard.LightInfluence = 0
	billboard.MaxDistance = 90
	billboard.Size = UDim2.fromOffset(170, 36)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, 3.2, 0)
	billboard.Parent = rootPart

	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.BorderSizePixel = 0
	label.Font = Enum.Font.GothamBlack
	label.Text = labelText
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.TextScaled = true
	label.TextStrokeColor3 = Color3.fromRGB(18, 18, 18)
	label.TextStrokeTransparency = 0
	label.Size = UDim2.fromScale(1, 1)
	label.Parent = billboard
	return billboard
end

local function attachVisualPetInfoPrompt(instance, petName, variant, icon)
	local rootPart = getModelRootPart(instance)
	if not rootPart then
		return
	end

	local click = Instance.new("ClickDetector")
	click.Name = "PetInfoClick"
	click.MaxActivationDistance = 24
	click.Parent = rootPart
	click.MouseClick:Connect(function(player)
		if player == localPlayer then
			showPetInfo(petName, variant or "Normal", icon, instance)
		end
	end)

	local nameplate = addVisualPetNameplate(instance, petName, variant)
	click.MouseHoverEnter:Connect(function(player)
		if player == localPlayer and nameplate then
			nameplate.Enabled = true
		end
	end)
	click.MouseHoverLeave:Connect(function(player)
		if player == localPlayer and nameplate then
			nameplate.Enabled = false
		end
	end)
end

local function updateVisualPetBehavior()
	return
end

local function clearVisualPets()
	local folder = getVisualPetFolder()
	for _, child in ipairs(folder:GetChildren()) do
		child:Destroy()
	end
	setStatus("Visuals cleared")
end

local function spawnVisualPets()
	local root = getRoot()
	local petsFolder = getPetsFolder()
	if not root then
		setStatus("Visual pets: character root missing")
		return
	end

	if not petsFolder then
		setStatus("Visual pets: Assets.Pets missing")
		return
	end

	local selected = getSelectedVisualPetList()
	if #selected == 0 then
		for _, petName in ipairs(petNames) do
			table.insert(selected, petName)
		end
	end

	local spawned = 0
	local toolCount = 0
	local folder = getVisualPetFolder()
	local amount = math.floor(tonumber(CONFIG.visualPetAmount) or 1)
	local equipped = #folder:GetChildren()
	local availableSlots = math.max(CONFIG.maxEquippedVisualPets - equipped, 0)
	local equippedAmount = math.clamp(amount, 1, CONFIG.maxEquippedVisualPets)
	equippedAmount = math.min(equippedAmount, availableSlots)
	local availableToolSlots = math.max(CONFIG.maxVisualPetTools - countVisualPetTools(), 0)
	local toolAmount = availableToolSlots
	local totalAmount = math.max(equippedAmount, toolAmount)
	if totalAmount <= 0 then
		setStatus(("Visual pets: max equipped %d/%d, backpack full %d/%d"):format(equipped, CONFIG.maxEquippedVisualPets, CONFIG.maxVisualPetTools, CONFIG.maxVisualPetTools))
		return
	end
	local startSlot = #folder:GetChildren()
	local unavailable = 0

	for index = 1, totalAmount do
		local petName = selected[((index - 1) % #selected) + 1]
		local template, actualVariant, usedVariantAsset = findVisualPetTemplate(petsFolder, petName, CONFIG.visualPetVariant)
		if template then
			local slot = startSlot + index
			local displayName = actualVariant ~= "Normal" and (actualVariant .. " " .. petName) or petName
			local icon = getPetIcon(petName, template, displayName)

			if index <= equippedAmount and #folder:GetChildren() < CONFIG.maxEquippedVisualPets then
				local clone = template:Clone()
				clone.Name = petName
				clone:SetAttribute("PetName", petName)
				clone:SetAttribute("Slot", slot)
				clone:SetAttribute("SpawnedAt", os.clock())
				applyVisualPetVariant(clone, actualVariant, usedVariantAsset)
				prepVisualPet(clone)
				storeVisualOrientationOffset(clone)
				clone.Parent = folder
				playPetAnimations(clone)
				attachVisualPetInfoPrompt(clone, petName, actualVariant, icon)

				local angle = ((index - 1) / math.max(equippedAmount, 1)) * math.pi * 2
				local radius = 6 + (spawned % 3) * 2
				local offset = Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
				local position = root.Position + offset
				local rayParams = RaycastParams.new()
				rayParams.FilterType = Enum.RaycastFilterType.Exclude
				rayParams.FilterDescendantsInstances = { localPlayer.Character, folder }
				local rayResult = workspace:Raycast(position + Vector3.new(0, 20, 0), Vector3.new(0, -80, 0), rayParams)
				if rayResult then
					position = rayResult.Position + Vector3.new(0, 1.5, 0)
				else
					position += Vector3.new(0, -2, 0)
				end
				local target = CFrame.new(position, Vector3.new(root.Position.X, position.Y, root.Position.Z))

				moveVisualPet(clone, target)
				spawned += 1
			end

			if toolCount < toolAmount and makeLocalPetTool(petName, template, slot, actualVariant, usedVariantAsset) then
				toolCount += 1
			end

			task.wait(0.03)
		else
			unavailable += 1
		end
	end

	trimVisualPets()
	pcall(updateVisualPetBehavior)
	if spawned == 0 and toolCount == 0 and unavailable > 0 then
		setStatus(("Visual pets: %s not available for selected pet(s)"):format(CONFIG.visualPetVariant))
		return
	end
	setStatus(("Visual pets: equipped %d/%d, %d backpack item(s)"):format(#folder:GetChildren(), CONFIG.maxEquippedVisualPets, toolCount))
end

local function make(className, properties, parent)
	local instance = Instance.new(className)
	for key, value in pairs(properties or {}) do
		instance[key] = value
	end
	instance.Parent = parent
	return instance
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

local petInfoFrame = make("Frame", {
	Name = "PetInfo",
	AnchorPoint = Vector2.new(0.5, 0.5),
	BackgroundColor3 = Color3.fromRGB(96, 48, 27),
	BorderSizePixel = 0,
	Position = UDim2.fromScale(0.5, 0.48),
	Size = UDim2.fromOffset(560, 230),
	Visible = false,
	ZIndex = 20,
}, gui)
make("UICorner", { CornerRadius = UDim.new(0, 8) }, petInfoFrame)
make("UIStroke", { Color = Color3.fromRGB(40, 20, 10), Thickness = 5 }, petInfoFrame)

local petInfoHeader = make("Frame", {
	Name = "Header",
	BackgroundColor3 = Color3.fromRGB(91, 194, 66),
	BorderSizePixel = 0,
	Size = UDim2.new(1, 0, 0, 54),
	ZIndex = 21,
}, petInfoFrame)
make("UICorner", { CornerRadius = UDim.new(0, 8) }, petInfoHeader)
make("UIStroke", { Color = Color3.fromRGB(35, 88, 26), Thickness = 2 }, petInfoHeader)

make("TextLabel", {
	Name = "Heart",
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBlack,
	Text = "<3",
	TextColor3 = Color3.fromRGB(225, 36, 32),
	TextScaled = true,
	TextStrokeColor3 = Color3.fromRGB(104, 16, 16),
	TextStrokeTransparency = 0,
	Position = UDim2.fromOffset(12, 7),
	Size = UDim2.fromOffset(38, 38),
	ZIndex = 22,
}, petInfoHeader)

make("TextLabel", {
	Name = "Title",
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBlack,
	Text = "Pet Info",
	TextColor3 = Color3.fromRGB(255, 255, 245),
	TextScaled = true,
	TextStrokeColor3 = Color3.fromRGB(25, 25, 25),
	TextStrokeTransparency = 0,
	TextXAlignment = Enum.TextXAlignment.Left,
	Position = UDim2.fromOffset(62, 8),
	Size = UDim2.new(1, -120, 0, 36),
	ZIndex = 22,
}, petInfoHeader)

local petInfoClose = make("TextButton", {
	Name = "Close",
	AutoButtonColor = true,
	BackgroundColor3 = Color3.fromRGB(222, 35, 35),
	BorderSizePixel = 0,
	Font = Enum.Font.GothamBlack,
	Text = "X",
	TextColor3 = Color3.fromRGB(255, 255, 255),
	TextScaled = true,
	TextStrokeColor3 = Color3.fromRGB(80, 0, 0),
	TextStrokeTransparency = 0,
	Position = UDim2.new(1, -46, 0, 8),
	Size = UDim2.fromOffset(34, 34),
	ZIndex = 23,
}, petInfoHeader)
make("UICorner", { CornerRadius = UDim.new(0, 4) }, petInfoClose)
petInfoClose.Activated:Connect(function()
	petInfoFrame.Visible = false
end)

local petInfoIcon = make("ImageLabel", {
	Name = "Icon",
	BackgroundColor3 = Color3.fromRGB(54, 27, 15),
	BorderSizePixel = 0,
	Image = "",
	Position = UDim2.fromOffset(28, 82),
	ScaleType = Enum.ScaleType.Fit,
	Size = UDim2.fromOffset(126, 126),
	ZIndex = 21,
}, petInfoFrame)
make("UIStroke", { Color = Color3.fromRGB(24, 12, 8), Thickness = 4 }, petInfoIcon)

local petInfoName = make("TextLabel", {
	Name = "PetName",
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBlack,
	Text = "Pet",
	TextColor3 = Color3.fromRGB(255, 255, 255),
	TextScaled = true,
	TextStrokeColor3 = Color3.fromRGB(18, 18, 18),
	TextStrokeTransparency = 0,
	TextXAlignment = Enum.TextXAlignment.Left,
	Position = UDim2.fromOffset(178, 76),
	Size = UDim2.new(1, -205, 0, 48),
	ZIndex = 21,
}, petInfoFrame)

local petInfoDesc = make("TextLabel", {
	Name = "Description",
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamSemibold,
	Text = "Follows you around the garden.",
	TextColor3 = Color3.fromRGB(255, 240, 225),
	TextSize = 17,
	TextWrapped = true,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextYAlignment = Enum.TextYAlignment.Top,
	Position = UDim2.fromOffset(180, 124),
	Size = UDim2.new(1, -205, 0, 52),
	ZIndex = 21,
}, petInfoFrame)

local petInfoTag1 = make("TextLabel", {
	Name = "Tag1",
	BackgroundColor3 = Color3.fromRGB(140, 53, 204),
	BorderSizePixel = 0,
	Font = Enum.Font.GothamBlack,
	Text = "NORMAL",
	TextColor3 = Color3.fromRGB(255, 255, 255),
	TextScaled = true,
	TextStrokeColor3 = Color3.fromRGB(32, 18, 38),
	TextStrokeTransparency = 0.15,
	Position = UDim2.fromOffset(184, 180),
	Size = UDim2.fromOffset(126, 36),
	ZIndex = 21,
}, petInfoFrame)
make("UICorner", { CornerRadius = UDim.new(0, 5) }, petInfoTag1)
make("UIStroke", { Color = Color3.fromRGB(68, 26, 102), Thickness = 2 }, petInfoTag1)

local petInfoTag2 = make("TextLabel", {
	Name = "Tag2",
	BackgroundColor3 = Color3.fromRGB(237, 65, 139),
	BorderSizePixel = 0,
	Font = Enum.Font.GothamBlack,
	Text = "Visual",
	TextColor3 = Color3.fromRGB(255, 255, 255),
	TextScaled = true,
	TextStrokeColor3 = Color3.fromRGB(70, 15, 38),
	TextStrokeTransparency = 0.15,
	Position = UDim2.fromOffset(326, 180),
	Size = UDim2.fromOffset(126, 36),
	ZIndex = 21,
}, petInfoFrame)
make("UICorner", { CornerRadius = UDim.new(0, 5) }, petInfoTag2)
make("UIStroke", { Color = Color3.fromRGB(128, 25, 78), Thickness = 2 }, petInfoTag2)

showPetInfo = function(petName, variant, icon)
	variant = variant or "Normal"
	local displayName = petName
	if variant ~= "Normal" then
		displayName = variant .. " " .. petName
	end

	local wantsHuge, wantsRainbow, wantsBig = getVariantFlags(variant)
	local infoIcon = icon or ""
	if infoIcon == "" then
		infoIcon = getGearImageValue(displayName)
	end
	if infoIcon == "" then
		infoIcon = getGearImageValue(petName)
	end

	petInfoName.Text = displayName
	petInfoDesc.Text = ("Follows you around your garden and keeps close to your character. Equipped %d/%d."):format(math.min(#getVisualPetFolder():GetChildren(), CONFIG.maxEquippedVisualPets), CONFIG.maxEquippedVisualPets)
	petInfoIcon.Image = infoIcon
	petInfoTag1.Text = string.upper(variant)
	petInfoTag1.BackgroundColor3 = wantsRainbow and Color3.fromRGB(138, 45, 214)
		or (variant == "Normal" and Color3.fromRGB(73, 148, 215) or Color3.fromRGB(63, 155, 224))
	petInfoTag2.Text = wantsHuge and "Huge" or (wantsBig and "Big" or "Super")
	petInfoTag2.BackgroundColor3 = wantsHuge and Color3.fromRGB(243, 78, 134)
		or (wantsBig and Color3.fromRGB(244, 148, 54) or Color3.fromRGB(92, 197, 82))
	petInfoFrame.Visible = true
end

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
		end
	end)
end

local function makeActionButton(label, order, callback)
	local button = make("TextButton", {
		Name = string.gsub(label, "%s+", ""),
		AutoButtonColor = true,
		BackgroundColor3 = Color3.fromRGB(52, 60, 54),
		BorderSizePixel = 0,
		Font = Enum.Font.GothamSemibold,
		Text = label,
		TextColor3 = Color3.fromRGB(242, 247, 239),
		TextSize = 12,
		Size = UDim2.new(1, 0, 0, 30),
		LayoutOrder = order,
	}, content)
	make("UICorner", { CornerRadius = UDim.new(0, 6) }, button)

	button.Activated:Connect(function()
		task.spawn(callback)
	end)

	return button
end

local visualControls = {}
local visualControlsVisible = false
local visualControlsToggle

local function refreshVisualControlsVisibility()
	for _, control in ipairs(visualControls) do
		if control and control.Parent then
			control.Visible = visualControlsVisible
		end
	end

	if visualControlsToggle then
		visualControlsToggle.Text = "Visuals: " .. (visualControlsVisible and "ON" or "OFF")
		visualControlsToggle.BackgroundColor3 = visualControlsVisible and Color3.fromRGB(58, 111, 67) or Color3.fromRGB(34, 41, 42)
	end

	content.CanvasSize = UDim2.fromOffset(0, contentLayout.AbsoluteContentSize.Y + 8)
end

local function registerVisualControl(control)
	table.insert(visualControls, control)
	control.Visible = visualControlsVisible
	return control
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
makeToggle("Auto Sell Inventory", "autoSell", 8)
makeSectionLabel("Shops", 9)
makeToggle("Auto Buy Seeds", "autoBuySeeds", 10)
makeToggle("Use Seed Shop", "seedShopEnabled", 11)
makeToggle("Auto Buy Gear", "autoBuyGear", 12)
makeToggle("Use Gear Shop", "gearShopEnabled", 13)
makeToggle("Performance Mode", "performanceMode", 14)

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
	LayoutOrder = 15,
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
	LayoutOrder = 16,
}, content)

local statsFrame = make("Frame", {
	Name = "Stats",
	BackgroundColor3 = Color3.fromRGB(14, 18, 19),
	BorderSizePixel = 0,
	Size = UDim2.new(1, 0, 0, 128),
	LayoutOrder = 17,
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

visualControlsToggle = make("TextButton", {
	Name = "VisualControlsToggle",
	AutoButtonColor = false,
	BackgroundColor3 = Color3.fromRGB(34, 41, 42),
	BorderSizePixel = 0,
	Font = Enum.Font.GothamSemibold,
	Text = "Visuals: OFF",
	TextColor3 = Color3.fromRGB(235, 244, 233),
	TextSize = 12,
	Size = UDim2.new(1, 0, 0, 30),
	LayoutOrder = 18,
}, content)
make("UICorner", { CornerRadius = UDim.new(0, 6) }, visualControlsToggle)
visualControlsToggle.Activated:Connect(function()
	visualControlsVisible = not visualControlsVisible
	refreshVisualControlsVisibility()
	setStatus("Visual controls " .. (visualControlsVisible and "shown" or "hidden"))
end)

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
	LayoutOrder = 19,
}, content)

local seedRow = make("ScrollingFrame", {
	Name = "SeedSelector",
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	CanvasSize = UDim2.fromOffset(0, 0),
	ScrollBarThickness = 4,
	ScrollingDirection = Enum.ScrollingDirection.Y,
	Size = UDim2.new(1, 0, 0, 66),
	LayoutOrder = 20,
}, content)
make("UIGridLayout", {
	CellPadding = UDim2.fromOffset(6, 6),
	CellSize = UDim2.fromOffset(136, 24),
	SortOrder = Enum.SortOrder.LayoutOrder,
}, seedRow)

local seedLayout = seedRow:FindFirstChildOfClass("UIGridLayout")
local seedButtons = {}
local seedButtonCount = 0
local makeAvoidSeedButton

local avoidSeedLabel = make("TextLabel", {
	Name = "AvoidSeedLabel",
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamSemibold,
	Text = "Seeds to avoid",
	TextColor3 = Color3.fromRGB(221, 236, 216),
	TextSize = 13,
	TextXAlignment = Enum.TextXAlignment.Left,
	Size = UDim2.new(1, 0, 0, 15),
	LayoutOrder = 21,
}, content)

local avoidSeedRow = make("ScrollingFrame", {
	Name = "AvoidSeedSelector",
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
}, avoidSeedRow)

local avoidSeedLayout = avoidSeedRow:FindFirstChildOfClass("UIGridLayout")
local avoidSeedButtons = {}
local avoidSeedButtonCount = 0

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
	local rows = math.ceil(#seedNames / 2)
	seedRow.CanvasSize = UDim2.fromOffset(0, rows * 28)
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

	button.Activated:Connect(function()
		selectedSeeds[seedName] = not selectedSeeds[seedName]
		CONFIG.selectedSeed = seedName
		refreshSeedButton(seedName)
		saveConfig()
		setStatus((selectedSeeds[seedName] and "Selected " or "Unselected ") .. seedName)
	end)

	refreshSeedCanvas()
	if makeAvoidSeedButton then
		makeAvoidSeedButton(seedName)
	end
end

local function refreshAvoidSeedButton(seedName)
	local button = avoidSeedButtons[seedName]
	if not button then
		return
	end

	local enabled = blacklistedSeeds[seedName] == true
	button.Text = (enabled and "[x] " or "[ ] ") .. seedName
	button.BackgroundColor3 = enabled and Color3.fromRGB(122, 65, 50) or Color3.fromRGB(52, 60, 54)
end

local function refreshAvoidSeedCanvas()
	local rows = math.ceil(#seedNames / 2)
	avoidSeedRow.CanvasSize = UDim2.fromOffset(0, rows * 28)
end

makeAvoidSeedButton = function(seedName)
	if avoidSeedButtons[seedName] then
		return
	end

	avoidSeedButtonCount += 1

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
		LayoutOrder = avoidSeedButtonCount,
	}, avoidSeedRow)
	make("UICorner", { CornerRadius = UDim.new(0, 6) }, button)

	avoidSeedButtons[seedName] = button
	refreshAvoidSeedButton(seedName)

	button.Activated:Connect(function()
		blacklistedSeeds[seedName] = not blacklistedSeeds[seedName]
		refreshAvoidSeedButton(seedName)
		saveConfig()
		setStatus((blacklistedSeeds[seedName] and "Avoiding " or "Allowing ") .. seedName)
	end)

	refreshAvoidSeedCanvas()
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
if avoidSeedLayout then
	avoidSeedLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(refreshAvoidSeedCanvas)
end
refreshSeedCanvas()
refreshAvoidSeedCanvas()
scanSeedShopNames()

local seedStockItems = getStockItemsFolder("SeedShop")
if seedStockItems then
	seedStockItems.ChildAdded:Connect(function(item)
		addUniqueName(seedNames, item.Name)
		seedPriority[item.Name] = getSeedMetadataValue(item.Name)
		table.sort(seedNames)
		makeSeedButton(item.Name)
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
	LayoutOrder = 23,
}, content)

local gearRow = make("ScrollingFrame", {
	Name = "GearSelector",
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	CanvasSize = UDim2.fromOffset(0, 0),
	ScrollBarThickness = 4,
	ScrollingDirection = Enum.ScrollingDirection.Y,
	Size = UDim2.new(1, 0, 0, 66),
	LayoutOrder = 24,
}, content)
make("UIGridLayout", {
	CellPadding = UDim2.fromOffset(6, 6),
	CellSize = UDim2.fromOffset(136, 24),
	SortOrder = Enum.SortOrder.LayoutOrder,
}, gearRow)

local gearLayout = gearRow:FindFirstChildOfClass("UIGridLayout")
local gearButtons = {}
local gearButtonCount = 0

local function refreshGearButton(gearName)
	local button = gearButtons[gearName]
	if not button then
		return
	end

	local enabled = selectedGears[gearName] == true
	button.Text = (enabled and "[x] " or "[ ] ") .. gearName
	button.BackgroundColor3 = enabled and Color3.fromRGB(58, 111, 67) or Color3.fromRGB(52, 60, 54)
end

local function refreshGearCanvas()
	local rows = math.ceil(#gearNames / 2)
	gearRow.CanvasSize = UDim2.fromOffset(0, rows * 28)
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

	button.Activated:Connect(function()
		selectedGears[gearName] = not selectedGears[gearName]
		refreshGearButton(gearName)
		saveConfig()
		setStatus((selectedGears[gearName] and "Selected " or "Unselected ") .. gearName)
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
	gearStockItems.ChildAdded:Connect(function(item)
		addUniqueName(gearNames, item.Name)
		table.sort(gearNames)
		makeGearButton(item.Name)
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
	LayoutOrder = 25,
}, content)

local petRow = make("ScrollingFrame", {
	Name = "PetSelector",
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	CanvasSize = UDim2.fromOffset(0, 0),
	ScrollBarThickness = 4,
	ScrollingDirection = Enum.ScrollingDirection.Y,
	Size = UDim2.new(1, 0, 0, 66),
	LayoutOrder = 26,
}, content)
make("UIGridLayout", {
	CellPadding = UDim2.fromOffset(6, 6),
	CellSize = UDim2.fromOffset(136, 24),
	SortOrder = Enum.SortOrder.LayoutOrder,
}, petRow)

local petLayout = petRow:FindFirstChildOfClass("UIGridLayout")
local petButtons = {}
local petButtonCount = 0

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
	local rows = math.ceil(#petNames / 2)
	petRow.CanvasSize = UDim2.fromOffset(0, rows * 28)
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

	button.Activated:Connect(function()
		selectedPets[petName] = not selectedPets[petName]
		refreshPetButton(petName)
		saveConfig()
		setStatus((selectedPets[petName] and "Selected " or "Unselected ") .. petName)
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

local function buildVisualPetSelector()
local selectedVisualPetLabel = make("TextLabel", {
	Name = "SelectedVisualPetLabel",
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamSemibold,
	Text = "Pets to visually spawn",
	TextColor3 = Color3.fromRGB(221, 236, 216),
	TextSize = 13,
	TextXAlignment = Enum.TextXAlignment.Left,
	Size = UDim2.new(1, 0, 0, 15),
	LayoutOrder = 27,
}, content)
registerVisualControl(selectedVisualPetLabel)

local visualPetRow = make("ScrollingFrame", {
	Name = "VisualPetSelector",
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	CanvasSize = UDim2.fromOffset(0, 0),
	ScrollBarThickness = 4,
	ScrollingDirection = Enum.ScrollingDirection.Y,
	Size = UDim2.new(1, 0, 0, 66),
	LayoutOrder = 28,
}, content)
registerVisualControl(visualPetRow)
make("UIGridLayout", {
	CellPadding = UDim2.fromOffset(6, 6),
	CellSize = UDim2.fromOffset(136, 24),
	SortOrder = Enum.SortOrder.LayoutOrder,
}, visualPetRow)

local visualPetLayout = visualPetRow:FindFirstChildOfClass("UIGridLayout")
local visualPetButtons = {}
local visualPetButtonCount = 0
local refreshVariantButtons

local function refreshVisualPetButton(petName)
	local button = visualPetButtons[petName]
	if not button then
		return
	end

	local enabled = selectedVisualPets[petName] == true
	button.Text = (enabled and "[x] " or "[ ] ") .. petName
	button.BackgroundColor3 = enabled and Color3.fromRGB(58, 111, 67) or Color3.fromRGB(52, 60, 54)
end

local function refreshVisualPetCanvas()
	local rows = math.ceil(#petNames / 2)
	visualPetRow.CanvasSize = UDim2.fromOffset(0, rows * 28)
end

local function makeVisualPetButton(petName)
	if visualPetButtons[petName] then
		return
	end

	visualPetButtonCount += 1

	local button = make("TextButton", {
		Name = "Visual" .. petName,
		AutoButtonColor = false,
		BackgroundColor3 = Color3.fromRGB(52, 60, 54),
		BorderSizePixel = 0,
		Font = Enum.Font.GothamSemibold,
		Text = petName,
		TextColor3 = Color3.fromRGB(242, 247, 239),
		TextSize = 12,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Size = UDim2.fromOffset(136, 24),
		LayoutOrder = visualPetButtonCount,
	}, visualPetRow)
	make("UICorner", { CornerRadius = UDim.new(0, 6) }, button)

	visualPetButtons[petName] = button
	refreshVisualPetButton(petName)

	button.Activated:Connect(function()
		selectedVisualPets[petName] = not selectedVisualPets[petName]
		refreshVisualPetButton(petName)
		if refreshVariantButtons then
			refreshVariantButtons()
		end
		saveConfig()
		setStatus((selectedVisualPets[petName] and "Selected spawn " or "Unselected spawn ") .. petName)
	end)

	refreshVisualPetCanvas()
end

for _, petName in ipairs(petNames) do
	makeVisualPetButton(petName)
end

if visualPetLayout then
	visualPetLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(refreshVisualPetCanvas)
end
refreshVisualPetCanvas()

local selectedVisualVariantLabel = make("TextLabel", {
	Name = "SelectedVisualVariantLabel",
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamSemibold,
	Text = "Visual pet variant",
	TextColor3 = Color3.fromRGB(221, 236, 216),
	TextSize = 13,
	TextXAlignment = Enum.TextXAlignment.Left,
	Size = UDim2.new(1, 0, 0, 15),
	LayoutOrder = 29,
}, content)
registerVisualControl(selectedVisualVariantLabel)

local variantRow = make("ScrollingFrame", {
	Name = "VisualPetVariantSelector",
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	CanvasSize = UDim2.fromOffset(0, 0),
	ScrollBarThickness = 4,
	ScrollingDirection = Enum.ScrollingDirection.Y,
	Size = UDim2.new(1, 0, 0, 58),
	LayoutOrder = 30,
}, content)
registerVisualControl(variantRow)
local variantLayout = make("UIGridLayout", {
	CellPadding = UDim2.fromOffset(6, 6),
	CellSize = UDim2.fromOffset(136, 24),
	SortOrder = Enum.SortOrder.LayoutOrder,
}, variantRow)

local variantButtons = {}
local variantButtonCount = 0

local function makeVariantButton(variantName)
	if variantButtons[variantName] then
		return
	end

	variantButtonCount += 1

	local button = make("TextButton", {
		Name = "Variant" .. string.gsub(variantName, "%s+", ""),
		AutoButtonColor = false,
		BackgroundColor3 = Color3.fromRGB(52, 60, 54),
		BorderSizePixel = 0,
		Font = Enum.Font.GothamSemibold,
		Text = variantName,
		TextColor3 = Color3.fromRGB(242, 247, 239),
		TextSize = 12,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Size = UDim2.fromOffset(136, 24),
		LayoutOrder = variantButtonCount,
	}, variantRow)
	make("UICorner", { CornerRadius = UDim.new(0, 6) }, button)

	variantButtons[variantName] = button
	button.Activated:Connect(function()
		if not isVisualVariantAvailable(variantName) then
			setStatus("Variant unavailable for selected pet(s): " .. variantName)
			return
		end
		CONFIG.visualPetVariant = variantName
		refreshVariantButtons()
		saveConfig()
		setStatus("Visual pet variant set to " .. variantName)
	end)
end

refreshVariantButtons = function()
	refreshVisualPetVariantsFromAssets()
	for _, variantName in ipairs(visualPetVariants) do
		makeVariantButton(variantName)
	end
	variantRow.CanvasSize = UDim2.fromOffset(0, variantLayout.AbsoluteContentSize.Y + 6)

	if not isVisualVariantAvailable(CONFIG.visualPetVariant) then
		CONFIG.visualPetVariant = "Normal"
	end

	for variantName, button in pairs(variantButtons) do
		local available = isVisualVariantAvailable(variantName)
		local enabled = CONFIG.visualPetVariant == variantName
		button.Text = (enabled and "[x] " or "[ ] ") .. variantName
		button.TextColor3 = available and Color3.fromRGB(242, 247, 239) or Color3.fromRGB(150, 150, 150)
		button.BackgroundColor3 = enabled and Color3.fromRGB(58, 111, 67)
			or (available and Color3.fromRGB(52, 60, 54) or Color3.fromRGB(33, 35, 34))
	end
end
refreshVariantButtons()

local visualPetAmountBox = make("TextBox", {
	Name = "VisualPetAmountBox",
	BackgroundColor3 = Color3.fromRGB(34, 41, 42),
	BorderSizePixel = 0,
	ClearTextOnFocus = false,
	Font = Enum.Font.GothamSemibold,
	PlaceholderText = "Visual pet amount",
	Text = tostring(CONFIG.visualPetAmount),
	TextColor3 = Color3.fromRGB(242, 247, 239),
	TextSize = 13,
	Size = UDim2.new(1, 0, 0, 34),
	LayoutOrder = 31,
}, content)
registerVisualControl(visualPetAmountBox)
make("UICorner", { CornerRadius = UDim.new(0, 6) }, visualPetAmountBox)
make("UIPadding", {
	PaddingLeft = UDim.new(0, 10),
	PaddingRight = UDim.new(0, 10),
}, visualPetAmountBox)

local function refreshVisualPetAmount()
	local amount = math.floor(tonumber(visualPetAmountBox.Text) or CONFIG.visualPetAmount)
	amount = math.clamp(amount, 1, CONFIG.maxVisualPetTools)
	CONFIG.visualPetAmount = amount
	visualPetAmountBox.Text = tostring(amount)
	saveConfig()
	setStatus(("Visual pet amount set to %d"):format(amount))
end

visualPetAmountBox.FocusLost:Connect(refreshVisualPetAmount)

local assets = ReplicatedStorage:FindFirstChild("Assets")
local petsFolder = assets and assets:FindFirstChild("Pets")
if petsFolder then
	petsFolder.ChildAdded:Connect(function(pet)
		local baseName = stripVariantWords(pet.Name)
		addUniqueName(petNames, baseName)
		makeVisualPetButton(baseName)
		refreshVariantButtons()
	end)
end

local gearImages = getGearImagesFolder()
if gearImages then
	gearImages.ChildAdded:Connect(function(imageValue)
		if imageValue:IsA("StringValue") then
			local baseName = stripVariantWords(imageValue.Name)
			if hasKnownPetBase(baseName) then
				addUniqueName(petNames, baseName)
				makeVisualPetButton(baseName)
			end
			refreshVariantButtons()
		end
	end)
end
end
buildVisualPetSelector()

registerVisualControl(makeActionButton("Spawn", 32, spawnVisualPets))
registerVisualControl(makeActionButton("Clear", 33, clearVisualPets))
refreshVisualControlsVisibility()

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

local timers = {
	fruitCollector = 0,
	seedPlacer = 0,
	autoSell = 0,
	autoBuySeeds = 0,
	autoBuyGear = 0,
	autoCollectRainbowSeeds = 0,
	autoBuyPets = 0,
	stats = 0,
	guiInventoryFull = false,
	lastInventoryRefresh = 0,
	lastGuiInventoryRefresh = 0,
}

local function runGuarded(key, callback)
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
	timers.fruitCollector = state.fruitCollector and (timers.fruitCollector + deltaTime) or 0
	timers.seedPlacer = state.seedPlacer and (timers.seedPlacer + deltaTime) or 0
	timers.autoSell = state.autoSell and (timers.autoSell + deltaTime) or 0
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

	if state.autoBuyPets and timers.autoBuyPets >= CONFIG.petBuyInterval then
		timers.autoBuyPets = 0
		runGuarded("autoBuyPets", buyPets)
	end

	if state.autoCollectRainbowSeeds and timers.autoCollectRainbowSeeds >= CONFIG.rainbowCollectInterval then
		timers.autoCollectRainbowSeeds = 0
		runGuarded("autoCollectRainbowSeeds", autoCollectRainbowSeeds)
	end

	if state.fruitCollector and timers.fruitCollector >= CONFIG.collectInterval then
		timers.fruitCollector = 0
		runGuarded("fruitCollector", collectFruit)
	end

	if state.seedPlacer and timers.seedPlacer >= CONFIG.plantInterval then
		timers.seedPlacer = 0
		runGuarded("seedPlacer", plantSeed)
	end

	if state.autoSell and timers.autoSell >= CONFIG.sellInterval then
		timers.autoSell = 0
		runGuarded("autoSell", autoSell)
	end

	if state.autoBuySeeds and timers.autoBuySeeds >= CONFIG.buyInterval then
		timers.autoBuySeeds = 0
		runGuarded("autoBuySeeds", buySeed)
	end

	if state.autoBuyGear and timers.autoBuyGear >= CONFIG.buyInterval then
		timers.autoBuyGear = 0
		runGuarded("autoBuyGear", buyGear)
	end

end)

if configLoaded then
	setStatus("Garden Tools loaded - config restored")
elseif canUseFileConfig() then
	setStatus("Garden Tools loaded - config ready")
else
	setStatus("Garden Tools loaded - config files unsupported")
end

