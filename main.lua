-- Garden automation GUI for private testing in a Grow-a-Garden-style place.
-- Drop this LocalScript in StarterPlayerScripts, or run it from a local test client.

local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
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
	collectInterval = 2.5,
	plantInterval = 1.5,
	sellInterval = 12.0,
	buyInterval = 5.0,
	rainbowCollectInterval = 2.5,
	petBuyInterval = 6.0,
	cacheRefreshInterval = 7.0,
	maxInventoryItems = 200,
	lowRaritySeedLimit = 10,
	maxVisualPets = 24,
	maxVisualPetTools = 24,
	maxEquippedVisualPets = 3,
	visualPetAmount = 24,
	visualPetVariant = "Normal",
	selectedSeed = "",
	plantRadius = 18,
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

local selectedPets = {}

local selectedVisualPets = {}

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

local function setStatus(message)
	state.lastStatus = tostring(message)
	if statusValue then
		statusValue.Value = state.lastStatus
	end
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
	if #seedNames > 0 and CONFIG.selectedSeed == "" then
		CONFIG.selectedSeed = seedNames[1]
		selectedSeeds[CONFIG.selectedSeed] = true
	end
end

local function refreshGearNamesFromStockValues()
	refreshNamesFromStock("GearShop", gearNames)
	if #gearNames > 0 and next(selectedGears) == nil then
		selectedGears[gearNames[1]] = true
	end
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
	if #petNames > 0 and next(selectedPets) == nil then
		selectedPets[petNames[1]] = true
	end
	if #petNames > 0 and next(selectedVisualPets) == nil then
		selectedVisualPets[petNames[1]] = true
	end
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

local function getCachedDescendants(key, root)
	local now = os.clock()
	local atKey = key .. "At"
	local listKey = key .. "Descendants"

	if not root then
		cache[atKey] = now
		cache[listKey] = {}
		return cache[listKey]
	end

	if not cache[atKey] or now - cache[atKey] > CONFIG.cacheRefreshInterval then
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

local function getWildPetSpawns()
	local map = getMap()
	return map and map:FindFirstChild("WildPetSpawns")
end

local function valueMatchesLocalPlayer(value)
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

		local child = plot:FindFirstChild(key)
		if child and child:IsA("ValueBase") and valueMatchesLocalPlayer(child.Value) then
			return true
		end
	end

	return false
end

local function getOwnGardenRoots()
	local gardens = getGardens()
	local userId = tostring(localPlayer.UserId)
	local roots = {}

	if not gardens then
		return roots
	end

	for _, plot in ipairs(gardens:GetChildren()) do
		local plants = plot:FindFirstChild("Plants")
		if plants and plotBelongsToLocalPlayer(plot) then
			table.insert(roots, plants)
		elseif plants then
			for _, plant in ipairs(plants:GetChildren()) do
				if string.sub(plant.Name, 1, #userId + 1) == userId .. "_" then
					table.insert(roots, plants)
					break
				end
			end
		end
	end

	return roots
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

local function refreshInventoryStats()
	local count = countInventoryTools()
	local capacity = CONFIG.maxInventoryItems
	local full = count >= capacity or guiShowsInventoryFull()

	stats.inventoryItems = count
	stats.inventoryCapacity = capacity
	stats.inventoryFull = full

	return full, count, capacity
end

local function updateStatsUI()
	for key, label in pairs(statsLabels) do
		if label and label.Parent then
			if key == "inventory" then
				label.Text = ("Inventory: %d/%d%s"):format(stats.inventoryItems, stats.inventoryCapacity, stats.inventoryFull and " FULL" or "")
			elseif key == "fruit" then
				label.Text = ("Fruit: %d collected, %d checked"):format(stats.fruitCollected, stats.fruitTargetsChecked)
			elseif key == "seed" then
				label.Text = ("Seeds: %d planted, %d remote try(s)"):format(stats.seedsPlanted, stats.seedAttempts)
			elseif key == "shop" then
				label.Text = ("Shop: %d seed buy(s), %d gear buy(s), %d pet buy(s)"):format(stats.seedsBought, stats.gearBought, stats.petsBought)
			elseif key == "skips" then
				label.Text = ("Skips: %d full, %d range, %d limit, %d avoid"):format(stats.collectSkippedFull, stats.collectSkippedRange, stats.seedsSkippedLimit, stats.seedsSkippedBlacklist)
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

local function collectPrompt(prompt)
	local part = getPromptPart and getPromptPart(prompt)
	if part and not state.collectTeleport and getPromptDistance(prompt) > (prompt.MaxActivationDistance or 10) then
		stats.collectSkippedRange += 1
		return false
	end

	if part and touchPart and state.collectTeleport then
		touchPart(part)
		task.wait(0.03)
	end

	local prompted = triggerPrompt(prompt, true)
	local target = getCollectFruitTarget(prompt)
	local packeted = target ~= nil and sendPacket("CollectFruit", target)

	return prompted or packeted
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
	if part and touchPart and not skipTouch then
		touchPart(part)
		task.wait(0.03)
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
	local inventoryFull = refreshInventoryStats()
	if inventoryFull then
		stats.collectSkippedFull += 1
		updateStatsUI()
		setStatus(("Fruit collector: inventory full (%d/%d)"):format(stats.inventoryItems, stats.inventoryCapacity))
		return
	end

	local fired = 0
	local prompts = {}
	local roots = getOwnGardenRoots()

	if #roots == 0 then
		setStatus("Fruit collector: no owned garden found")
		return
	end

	for index, root in ipairs(roots) do
		for _, descendant in ipairs(getCachedDescendants("garden" .. index, root)) do
			if isHarvestPrompt(descendant) then
				table.insert(prompts, descendant)
			end
		end
	end

	table.sort(prompts, function(left, right)
		return getFruitPriority(left) > getFruitPriority(right)
	end)

	for _, prompt in ipairs(prompts) do
		if collectPrompt(prompt) then
			fired += 1
			stats.fruitCollected += 1
			task.wait(0.03)
		end
	end

	stats.fruitTargetsChecked += #prompts
	refreshInventoryStats()
	updateStatsUI()
	setStatus(("Fruit collector: %d target(s) checked"):format(fired))
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
				if item:IsA("Tool") and string.find(string.lower(item.Name), string.lower(targetSeed), 1, true) then
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

	for _, seedName in ipairs(seedNames) do
		if selectedSeeds[seedName] and not blacklistedSeeds[seedName] then
			table.insert(selected, seedName)
		end
	end

	if #selected == 0 and CONFIG.selectedSeed ~= "" and not blacklistedSeeds[CONFIG.selectedSeed] then
		table.insert(selected, CONFIG.selectedSeed)
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

local function getSeedPlantPosition(index)
	local root = getRoot()
	if not root then
		return nil
	end

	local angle = ((index or 1) - 1) * math.rad(45)
	local offset = Vector3.new(math.cos(angle), 0, math.sin(angle)) * math.min(CONFIG.plantRadius, 6)
	local origin = root.Position + offset + Vector3.new(0, 12, 0)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { getCharacter() }

	local result = workspace:Raycast(origin, Vector3.new(0, -80, 0), params)
	if result then
		return result.Position
	end

	return root.Position + offset
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
			{ cframe, seedName },
			{ seedName, position.X, position.Y, position.Z },
			{ { seed = seedName, seedName = seedName, position = position, cframe = cframe } },
		}) do
			attempts += 1
			sendPacket(packetName, unpackArgs(args))
			task.wait(0.02)
		end
	end

	return attempts
end

local function isInventorySeedTool(item)
	if not item or not item:IsA("Tool") then
		return false
	end

	local name = string.lower(item.Name)
	if string.find(name, "seed", 1, true) then
		return true
	end

	for _, seedName in ipairs(seedNames) do
		if string.find(name, string.lower(seedName), 1, true) and string.find(name, "pack", 1, true) then
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

	if toolNameMatchesList(item, petNames) then
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
		touchPart(part)
		task.wait(0.05)
	end

	return triggerPrompt(prompt)
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

local function autoCollectRainbowSeeds()
	local inventoryFull = refreshInventoryStats()
	if inventoryFull then
		stats.collectSkippedFull += 1
		updateStatsUI()
		setStatus(("Gold/rainbow seeds: inventory full (%d/%d)"):format(stats.inventoryItems, stats.inventoryCapacity))
		return
	end

	local checked = 0
	local roots = { getMap(), getGardens() }

	for rootIndex, root in ipairs(roots) do
		for _, descendant in ipairs(getCachedDescendants("rainbow" .. rootIndex, root)) do
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
				if triggerPrompt(descendant) then
					checked += 1
					task.wait(0.03)
				end
			elseif descendant:IsA("BasePart")
				and descendant.CanTouch
				and matchesRainbowSeed
				and treeTextMatches(descendant, { "seed", "pack", "drop", "collect", "pickup", "rain" }, 3)
			then
				if touchPart(descendant) then
					checked += 1
					task.wait(0.03)
				end

			end
		end
	end

	refreshInventoryStats()
	updateStatsUI()
	setStatus(("Gold/rainbow seeds: %d target(s) checked"):format(checked))
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
	local root = getRoot()
	if not root then
		setStatus("Seed placer: character root missing")
		return
	end

	local planted = 0
	local attempts = 0
	local missing = 0

	for index, seedName in ipairs(getSelectedSeedList()) do
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
			local position = getSeedPlantPosition(index)
			if position then
				attempts += tryPlantSeedRemote(seedName, position)
			end

			pcall(function()
				tool:Activate()
			end)

			planted += 1
			task.wait(0.08)
		else
			missing += 1
		end
	end

	stats.seedsPlanted += planted
	stats.seedAttempts += attempts
	refreshInventoryStats()
	updateStatsUI()

	if planted > 0 then
		setStatus(("Seed placer: %d seed(s), %d remote try(s)"):format(planted, attempts))
	else
		setStatus(("Seed placer: no selected seed tool found (%d missing)"):format(missing))
	end
end

local function autoSell()
	local sellableTools = getSellableFruitTools()
	if #sellableTools == 0 then
		setStatus("Sell: nothing to sell")
		return
	end

	local actions = 0
	local stand = getPath(workspace, "Map.Stands.Sell.Part")
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
		if sendPacket(packetName) then
			actions += 1
			task.wait(0.05)
		end
	end

	for _, tool in ipairs(sellableTools) do
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
	if not state.seedShopEnabled then
		setStatus("Auto buy: seed shop disabled")
		return
	end

	local bought = 0
	local lastMessage = "Auto buy: no seeds selected"

	for _, seedName in ipairs(getSelectedSeedList()) do
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
	if not state.gearShopEnabled then
		setStatus("Auto gear: gear shop disabled")
		return
	end

	local bought = 0
	local lastMessage = "Auto gear: no gear selected"

	for _, gearName in ipairs(getSelectedGearList()) do
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
	local wildPetSpawns = getWildPetSpawns()
	local petTerm = string.lower(string.gsub(petName, "%s+", ""))

	for _, descendant in ipairs(getCachedDescendants("wildPets", wildPetSpawns)) do
		if descendant:IsA("ProximityPrompt") then
			local model = descendant:FindFirstAncestorWhichIsA("Model")
			local modelName = model and string.lower(string.gsub(model.Name, "%s+", "")) or ""
			local isBuyPrompt = descendant.Name == "BuyPrompt" or textMatches(descendant, { "buy", "purchase", "adopt" })
			local isPetPrompt = string.find(modelName, petTerm, 1, true) ~= nil or textMatches(descendant, { petName })

			if isBuyPrompt and isPetPrompt and triggerBuyPrompt(descendant) then
				return true, ("Auto pets: triggered prompt for %s"):format(petName)
			end
		end
	end

	return false, ("Auto pets: no matching prompt for %s"):format(petName)
end

local function buyPets()
	local bought = 0
	local lastMessage = "Auto pets: no pets selected"

	for _, petName in ipairs(getSelectedPetList()) do
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
	Size = UDim2.fromOffset(286, 520),
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
	TextSize = 18,
	Size = UDim2.new(1, 0, 0, 46),
}, panel)
make("UICorner", { CornerRadius = UDim.new(0, 8) }, header)

local content = make("ScrollingFrame", {
	Name = "Content",
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	CanvasSize = UDim2.fromOffset(0, 0),
	Position = UDim2.fromOffset(14, 60),
	ScrollBarThickness = 4,
	Size = UDim2.new(1, -28, 1, -74),
}, panel)
local contentLayout = make("UIListLayout", {
	Padding = UDim.new(0, 10),
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
	Size = UDim2.new(1, 0, 0, 42),
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
		TextSize = 14,
		Size = UDim2.new(1, 0, 0, 38),
		LayoutOrder = order,
	}, content)
	make("UICorner", { CornerRadius = UDim.new(0, 6) }, button)

	button.Activated:Connect(function()
		state[key] = not state[key]
		button.Text = ("%s: %s"):format(label, state[key] and "ON" or "OFF")
		button.BackgroundColor3 = state[key] and Color3.fromRGB(58, 111, 67) or Color3.fromRGB(34, 41, 42)
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
		TextSize = 13,
		Size = UDim2.new(1, 0, 0, 34),
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

makeToggle("Collect", "fruitCollector", 1)
makeToggle("Teleport", "collectTeleport", 2)
makeToggle("Plant", "seedPlacer", 3)
makeToggle("Sell", "autoSell", 4)
makeToggle("Seeds", "autoBuySeeds", 5)
makeToggle("Seed shop", "seedShopEnabled", 6)
makeToggle("Gear", "autoBuyGear", 7)
makeToggle("Gear shop", "gearShopEnabled", 8)
makeToggle("Drops", "autoCollectRainbowSeeds", 9)
makeToggle("Pets", "autoBuyPets", 10)
makeToggle("FPS", "performanceMode", 11)

local statsTitle = make("TextLabel", {
	Name = "StatsTitle",
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamSemibold,
	Text = "Stats",
	TextColor3 = Color3.fromRGB(221, 236, 216),
	TextSize = 13,
	TextXAlignment = Enum.TextXAlignment.Left,
	Size = UDim2.new(1, 0, 0, 18),
	LayoutOrder = 12,
}, content)

local statsFrame = make("Frame", {
	Name = "Stats",
	BackgroundColor3 = Color3.fromRGB(14, 18, 19),
	BorderSizePixel = 0,
	Size = UDim2.new(1, 0, 0, 112),
	LayoutOrder = 13,
}, content)
make("UICorner", { CornerRadius = UDim.new(0, 6) }, statsFrame)
make("UIPadding", {
	PaddingTop = UDim.new(0, 8),
	PaddingBottom = UDim.new(0, 8),
	PaddingLeft = UDim.new(0, 10),
	PaddingRight = UDim.new(0, 10),
}, statsFrame)
make("UIListLayout", {
	Padding = UDim.new(0, 4),
	SortOrder = Enum.SortOrder.LayoutOrder,
}, statsFrame)

local function makeStatsLabel(key, order)
	local label = make("TextLabel", {
		Name = key,
		BackgroundTransparency = 1,
		Font = Enum.Font.Gotham,
		Text = "",
		TextColor3 = Color3.fromRGB(201, 219, 202),
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, 0, 0, 16),
		LayoutOrder = order,
	}, statsFrame)
	statsLabels[key] = label
	return label
end

makeStatsLabel("inventory", 1)
makeStatsLabel("fruit", 2)
makeStatsLabel("seed", 3)
makeStatsLabel("shop", 4)
makeStatsLabel("skips", 5)
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
	TextSize = 14,
	Size = UDim2.new(1, 0, 0, 38),
	LayoutOrder = 14,
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
	Size = UDim2.new(1, 0, 0, 18),
	LayoutOrder = 15,
}, content)

local seedRow = make("ScrollingFrame", {
	Name = "SeedSelector",
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	CanvasSize = UDim2.fromOffset(0, 0),
	ScrollBarThickness = 4,
	ScrollingDirection = Enum.ScrollingDirection.Y,
	Size = UDim2.new(1, 0, 0, 92),
	LayoutOrder = 16,
}, content)
make("UIGridLayout", {
	CellPadding = UDim2.fromOffset(6, 6),
	CellSize = UDim2.fromOffset(118, 28),
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
	Size = UDim2.new(1, 0, 0, 18),
	LayoutOrder = 17,
}, content)

local avoidSeedRow = make("ScrollingFrame", {
	Name = "AvoidSeedSelector",
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	CanvasSize = UDim2.fromOffset(0, 0),
	ScrollBarThickness = 4,
	ScrollingDirection = Enum.ScrollingDirection.Y,
	Size = UDim2.new(1, 0, 0, 92),
	LayoutOrder = 18,
}, content)
make("UIGridLayout", {
	CellPadding = UDim2.fromOffset(6, 6),
	CellSize = UDim2.fromOffset(118, 28),
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
	seedRow.CanvasSize = UDim2.fromOffset(0, rows * 34)
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
		Size = UDim2.fromOffset(118, 28),
		LayoutOrder = seedButtonCount,
	}, seedRow)
	make("UICorner", { CornerRadius = UDim.new(0, 6) }, button)

	seedButtons[seedName] = button
	refreshSeedButton(seedName)

	button.Activated:Connect(function()
		selectedSeeds[seedName] = not selectedSeeds[seedName]
		CONFIG.selectedSeed = seedName
		refreshSeedButton(seedName)
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
	avoidSeedRow.CanvasSize = UDim2.fromOffset(0, rows * 34)
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
		Size = UDim2.fromOffset(118, 28),
		LayoutOrder = avoidSeedButtonCount,
	}, avoidSeedRow)
	make("UICorner", { CornerRadius = UDim.new(0, 6) }, button)

	avoidSeedButtons[seedName] = button
	refreshAvoidSeedButton(seedName)

	button.Activated:Connect(function()
		blacklistedSeeds[seedName] = not blacklistedSeeds[seedName]
		refreshAvoidSeedButton(seedName)
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
	Size = UDim2.new(1, 0, 0, 18),
	LayoutOrder = 19,
}, content)

local gearRow = make("ScrollingFrame", {
	Name = "GearSelector",
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	CanvasSize = UDim2.fromOffset(0, 0),
	ScrollBarThickness = 4,
	ScrollingDirection = Enum.ScrollingDirection.Y,
	Size = UDim2.new(1, 0, 0, 92),
	LayoutOrder = 20,
}, content)
make("UIGridLayout", {
	CellPadding = UDim2.fromOffset(6, 6),
	CellSize = UDim2.fromOffset(118, 28),
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
	gearRow.CanvasSize = UDim2.fromOffset(0, rows * 34)
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
		Size = UDim2.fromOffset(118, 28),
		LayoutOrder = gearButtonCount,
	}, gearRow)
	make("UICorner", { CornerRadius = UDim.new(0, 6) }, button)

	gearButtons[gearName] = button
	refreshGearButton(gearName)

	button.Activated:Connect(function()
		selectedGears[gearName] = not selectedGears[gearName]
		refreshGearButton(gearName)
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
	Size = UDim2.new(1, 0, 0, 18),
	LayoutOrder = 21,
}, content)

local petRow = make("ScrollingFrame", {
	Name = "PetSelector",
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	CanvasSize = UDim2.fromOffset(0, 0),
	ScrollBarThickness = 4,
	ScrollingDirection = Enum.ScrollingDirection.Y,
	Size = UDim2.new(1, 0, 0, 92),
	LayoutOrder = 22,
}, content)
make("UIGridLayout", {
	CellPadding = UDim2.fromOffset(6, 6),
	CellSize = UDim2.fromOffset(118, 28),
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
	petRow.CanvasSize = UDim2.fromOffset(0, rows * 34)
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
		Size = UDim2.fromOffset(118, 28),
		LayoutOrder = petButtonCount,
	}, petRow)
	make("UICorner", { CornerRadius = UDim.new(0, 6) }, button)

	petButtons[petName] = button
	refreshPetButton(petName)

	button.Activated:Connect(function()
		selectedPets[petName] = not selectedPets[petName]
		refreshPetButton(petName)
		setStatus((selectedPets[petName] and "Selected " or "Unselected ") .. petName)
	end)

	refreshPetCanvas()
end

local function scanPetBuyNames()
	refreshPetNamesFromAssets()

	local wildPetSpawns = getWildPetSpawns()
	if wildPetSpawns then
		for _, descendant in ipairs(wildPetSpawns:GetDescendants()) do
			if descendant:IsA("Model") then
				addUniqueName(petNames, stripVariantWords(descendant.Name))
			elseif descendant:IsA("ProximityPrompt") then
				local model = descendant:FindFirstAncestorWhichIsA("Model")
				if model then
					addUniqueName(petNames, stripVariantWords(model.Name))
				end
			end
		end
	end

	table.sort(petNames)
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
		makePetButton(baseName)
	end)
end

local wildPetSpawnsForBuy = getWildPetSpawns()
if wildPetSpawnsForBuy then
	wildPetSpawnsForBuy.DescendantAdded:Connect(function(descendant)
		local model = descendant:IsA("Model") and descendant or descendant:FindFirstAncestorWhichIsA("Model")
		if model then
			local baseName = stripVariantWords(model.Name)
			addUniqueName(petNames, baseName)
			makePetButton(baseName)
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
	Size = UDim2.new(1, 0, 0, 18),
	LayoutOrder = 23,
}, content)
registerVisualControl(selectedVisualPetLabel)

local visualPetRow = make("ScrollingFrame", {
	Name = "VisualPetSelector",
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	CanvasSize = UDim2.fromOffset(0, 0),
	ScrollBarThickness = 4,
	ScrollingDirection = Enum.ScrollingDirection.Y,
	Size = UDim2.new(1, 0, 0, 92),
	LayoutOrder = 24,
}, content)
registerVisualControl(visualPetRow)
make("UIGridLayout", {
	CellPadding = UDim2.fromOffset(6, 6),
	CellSize = UDim2.fromOffset(118, 28),
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
	visualPetRow.CanvasSize = UDim2.fromOffset(0, rows * 34)
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
		Size = UDim2.fromOffset(118, 28),
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
	Size = UDim2.new(1, 0, 0, 18),
	LayoutOrder = 25,
}, content)
registerVisualControl(selectedVisualVariantLabel)

local variantRow = make("ScrollingFrame", {
	Name = "VisualPetVariantSelector",
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	CanvasSize = UDim2.fromOffset(0, 0),
	ScrollBarThickness = 4,
	ScrollingDirection = Enum.ScrollingDirection.Y,
	Size = UDim2.new(1, 0, 0, 70),
	LayoutOrder = 26,
}, content)
registerVisualControl(variantRow)
local variantLayout = make("UIGridLayout", {
	CellPadding = UDim2.fromOffset(6, 6),
	CellSize = UDim2.fromOffset(118, 28),
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
		Size = UDim2.fromOffset(118, 28),
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
	LayoutOrder = 27,
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

registerVisualControl(makeActionButton("Spawn", 28, spawnVisualPets))
registerVisualControl(makeActionButton("Clear", 29, clearVisualPets))
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
}

local running = {}

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
	timers.fruitCollector += deltaTime
	timers.seedPlacer += deltaTime
	timers.autoSell += deltaTime
	timers.autoBuySeeds += deltaTime
	timers.autoBuyGear += deltaTime
	timers.autoCollectRainbowSeeds += deltaTime
	timers.autoBuyPets += deltaTime
	timers.stats += deltaTime

	if timers.stats >= 1 then
		timers.stats = 0
		refreshInventoryStats()
		updateStatsUI()
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

	if state.autoCollectRainbowSeeds and timers.autoCollectRainbowSeeds >= CONFIG.rainbowCollectInterval then
		timers.autoCollectRainbowSeeds = 0
		runGuarded("autoCollectRainbowSeeds", autoCollectRainbowSeeds)
	end

	if state.autoBuyPets and timers.autoBuyPets >= CONFIG.petBuyInterval then
		timers.autoBuyPets = 0
		runGuarded("autoBuyPets", buyPets)
	end

	local ok, err = pcall(updateVisualPetBehavior)
	if not ok then
		setStatus(("visualPetFollow error: %s"):format(tostring(err)))
	end
end)

setStatus("Garden Tools loaded")
