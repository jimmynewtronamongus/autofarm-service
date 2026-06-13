-- Garden automation GUI for private testing in a Grow-a-Garden-style place.
-- Drop this LocalScript in StarterPlayerScripts, or run it from a local test client.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
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
	maxVisualPets = 24,
	maxVisualPetTools = 24,
	visualPetAmount = 3,
	selectedSeed = "Carrot",
	plantRadius = 18,
}

local seedNames = {
	"Carrot",
	"Strawberry",
	"Blueberry",
	"Tulip",
	"Tomato",
	"Apple",
	"Bamboo",
	"Corn",
	"Cactus",
	"Banana",
	"Acorn",
	"Grape",
	"Cherry",
	"Dragon's Breath",
	"Dragon Fruit",
	"Mushroom",
	"Sunflower",
	"Coconut",
	"Green Bean",
	"Mango",
	"Pineapple",
	"Pomegranate",
	"Poison Apple",
	"Venus Fly Trap",
	"Moon Bloom",
}

local state = {
	fruitCollector = false,
	seedPlacer = false,
	autoSell = false,
	autoBuySeeds = false,
	autoBuyGear = false,
	autoCollectRainbowSeeds = false,
	autoBuyPets = false,
	performanceMode = false,
	lastStatus = "Ready",
}

local selectedSeeds = {
	Carrot = true,
}

local gearNames = {
	"Common Watering Can",
	"Super Watering Can",
	"Common Sprinkler",
	"Uncommon Sprinkler",
	"Rare Sprinkler",
	"Super Sprinkler",
	"Legendary Sprinkler",
	"Trowel",
	"Basic Pot",
	"Wheelbarrow",
	"Teleporter",
	"Gnome",
	"Sign",
	"Lantern",
	"Flashbang",
	"Jump Mushroom",
	"Speed Mushroom",
	"Shrink Mushroom",
	"Supersize Mushroom",
	"Invisibility Mushroom",
}

local selectedGears = {
	["Common Watering Can"] = true,
}

local petNames = {
	"Frog",
	"Bunny",
	"Deer",
	"Dragonfly",
}

local selectedPets = {
	Frog = true,
	Bunny = true,
	Deer = true,
}

local selectedVisualPets = {
	Dragonfly = true,
}

local statusValue

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

local function refreshPetNamesFromAssets()
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local pets = assets and assets:FindFirstChild("Pets")
	if not pets then
		return
	end

	for _, pet in ipairs(pets:GetChildren()) do
		addUniqueName(petNames, pet.Name)
	end

	table.sort(petNames)
end

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

local cache = {
	seedFrames = {},
	gearFrames = {},
}

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

local function getOwnGardenRoots()
	local gardens = getGardens()
	local userId = tostring(localPlayer.UserId)
	local roots = {}

	if not gardens then
		return roots
	end

	for _, plot in ipairs(gardens:GetChildren()) do
		local plants = plot:FindFirstChild("Plants")
		if plants then
			for _, plant in ipairs(plants:GetChildren()) do
				if string.sub(plant.Name, 1, #userId + 1) == userId .. "_" then
					table.insert(roots, plants)
					break
				end
			end
		end
	end

	if #roots == 0 then
		table.insert(roots, gardens)
	end

	return roots
end

local function textMatches(instance, terms)
	local instanceText = ""
	pcall(function()
		instanceText = instance.Text or ""
	end)

	local haystack = string.lower(table.concat({
		instance.Name or "",
		instanceText,
		getObjectPath(instance),
		instance:IsA("ProximityPrompt") and instance.ActionText or "",
		instance:IsA("ProximityPrompt") and instance.ObjectText or "",
	}, " "))

	for _, term in ipairs(terms) do
		if string.find(haystack, string.lower(term), 1, true) then
			return true
		end
	end

	return false
end

local function triggerPrompt(prompt)
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
	local fired = 0

	for index, root in ipairs(getOwnGardenRoots()) do
		for _, descendant in ipairs(getCachedDescendants("garden" .. index, root)) do
			if descendant:IsA("ProximityPrompt")
				and descendant.Name ~= "StealPrompt"
				and descendant.ActionText ~= "Steal"
				and textMatches(descendant, { "collect", "harvest", "pick", "fruit" })
			then
				if triggerPrompt(descendant) then
					fired += 1
					task.wait(0.03)
				end
			end
		end
	end

	setStatus(("Fruit collector: %d target(s) checked"):format(fired))
end

local function getEquippedSeedTool()
	local character = getCharacter()
	local backpack = localPlayer:FindFirstChildOfClass("Backpack")
	local humanoid = getHumanoid()

	for _, container in ipairs({ character, backpack }) do
		if container then
			for _, item in ipairs(container:GetChildren()) do
				if item:IsA("Tool") and string.find(string.lower(item.Name), string.lower(CONFIG.selectedSeed), 1, true) then
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
		if selectedSeeds[seedName] then
			table.insert(selected, seedName)
		end
	end

	if #selected == 0 then
		table.insert(selected, CONFIG.selectedSeed)
	end

	return selected
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

	local seedShop = playerGui:FindFirstChild("SeedShop")
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

local function touchPart(part)
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

local function getPromptPart(prompt)
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
	local checked = 0
	local roots = { getMap(), getGardens() }

	for rootIndex, root in ipairs(roots) do
		for _, descendant in ipairs(getCachedDescendants("rainbow" .. rootIndex, root)) do
			local matchesRainbowSeed = textMatches(descendant, {
				"rainbow",
				"seedrain",
				"seed rain",
				"gold seed",
				"seedpack",
				"seed pack",
			})

			if descendant:IsA("ProximityPrompt") and descendant.Name ~= "StealPrompt" and matchesRainbowSeed then
				if triggerPrompt(descendant) then
					checked += 1
					task.wait(0.03)
				end
			elseif descendant:IsA("BasePart") and matchesRainbowSeed then
				if touchPart(descendant) then
					checked += 1
					task.wait(0.03)
				end

			end
		end
	end

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

	local tool = getEquippedSeedTool()
	if not tool then
		setStatus("Seed placer: no matching seed tool found")
		return
	end

	pcall(function()
		tool:Activate()
	end)

	setStatus(("Seed placer: attempted %s"):format(CONFIG.selectedSeed))
end

local function autoSell()
	local fired = 0

	local stand = getPath(workspace, "Map.Stands.Sell.Part")
	if stand and stand:IsA("BasePart") and touchPart(stand) then
		fired += 1
		task.wait(0.15)
	end

	local stevenPrompt = getPath(workspace, "NPCS.Steven.HumanoidRootPart.ProximityPrompt")
	if stevenPrompt and stevenPrompt:IsA("ProximityPrompt") and triggerBuyPrompt(stevenPrompt) then
		fired += 1
		task.wait(0.15)
	end

	for _, descendant in ipairs(playerGui:GetDescendants()) do
		if descendant:IsA("GuiButton") and descendant.Visible and textMatches(descendant, { "sell" }) then
			if activateButton(descendant) then
				fired += 1
				task.wait(0.05)
			end
		end
	end

	setStatus(("Auto sell: %d prompt(s) checked"):format(fired))
end

local function buyOneSeed(seedName)
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

	if purchaseSeedRemote(seedName) then
		return true, ("Auto buy: sent PurchaseSeed for %s"):format(seedName)
	end

	if clicked then
		return true, ("Auto buy: clicked %s"):format(seedName)
	else
		return false, ("Auto buy: no working remote/button for %s"):format(seedName)
	end
end

local function buySeed()
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
		setStatus(("Auto buy: tried %d selected seed(s)"):format(bought))
	else
		setStatus(lastMessage)
	end
end

local function buyOneGear(gearName)
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

	if sendPacket("PurchaseGear", gearName) or sendPacket("PurchaseGear", gearName, 1) then
		return true, ("Auto gear: sent PurchaseGear for %s"):format(gearName)
	end

	if clicked then
		return true, ("Auto gear: clicked %s"):format(gearName)
	else
		return false, ("Auto gear: no working button for %s"):format(gearName)
	end
end

local function buyGear()
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
		setStatus(("Auto pets: tried %d selected pet(s)"):format(bought))
	else
		setStatus(lastMessage)
	end
end

local visualPetFolder

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

local function getPetIcon(petName, template)
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

local function playPetAnimations(instance)
	local animator
	for _, descendant in ipairs(instance:GetDescendants()) do
		if descendant:IsA("Animator") then
			animator = descendant
			break
		end
	end

	if not animator then
		local controller = instance:FindFirstChildWhichIsA("AnimationController", true)
		if controller then
			animator = Instance.new("Animator")
			animator.Parent = controller
		end
	end

	if not animator then
		return
	end

	local played = 0
	for _, descendant in ipairs(instance:GetDescendants()) do
		if descendant:IsA("Animation") and descendant.AnimationId ~= "" then
			local lowerName = string.lower(descendant.Name)
			if string.find(lowerName, "idle", 1, true) or string.find(lowerName, "walk", 1, true) or played == 0 then
				local ok, track = pcall(function()
					return animator:LoadAnimation(descendant)
				end)
				if ok and track then
					track.Looped = true
					track:Play(0.15, 1, string.find(lowerName, "walk", 1, true) and 1.15 or 1)
					played += 1
				end
			end

			if played >= 2 then
				break
			end
		end
	end
end

local function makeLocalPetTool(petName, template, slot)
	local backpack = localPlayer:FindFirstChildOfClass("Backpack")
	if not backpack then
		return false
	end

	local tool = Instance.new("Tool")
	tool.Name = petName
	tool.ToolTip = petName
	tool.RequiresHandle = true
	tool.CanBeDropped = false
	tool:SetAttribute("VisualPetTool", true)
	tool:SetAttribute("PetName", petName)
	tool:SetAttribute("Pet", petName)
	tool:SetAttribute("PetId", ("local-%s-%d-%d"):format(string.gsub(petName, "%s+", "-"), slot or 0, math.floor(os.clock() * 1000)))
	tool:SetAttribute("Count", 0)
	tool:SetAttribute("Slot", slot or 0)

	local icon = getPetIcon(petName, template)
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

	local clone = template:Clone()
	clone.Name = "PetPreview"
	prepVisualPet(clone)
	clone.Parent = tool

	pcall(function()
		if clone:IsA("Model") then
			clone:PivotTo(handle.CFrame)
		elseif clone:IsA("BasePart") then
			clone.CFrame = handle.CFrame
		end
	end)

	for _, descendant in ipairs(clone:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.Anchored = false
			descendant.Massless = true
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = handle
			weld.Part1 = descendant
			weld.Parent = handle
		end
	end

	if clone:IsA("BasePart") then
		clone.Anchored = false
		clone.Massless = true
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = handle
		weld.Part1 = clone
		weld.Parent = handle
	end

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

local function moveVisualPet(instance, target)
	pcall(function()
		if instance:IsA("Model") then
			instance:PivotTo(target)
		elseif instance:IsA("BasePart") then
			instance.CFrame = target
		end
	end)
end

local function updateVisualPetBehavior()
	local root = getRoot()
	if not root or not visualPetFolder or not visualPetFolder.Parent then
		return
	end

	local pets = visualPetFolder:GetChildren()
	if #pets == 0 then
		return
	end
	table.sort(pets, function(a, b)
		local slotA = a:GetAttribute("Slot") or 0
		local slotB = b:GetAttribute("Slot") or 0
		if slotA == slotB then
			return (a:GetAttribute("SpawnedAt") or 0) < (b:GetAttribute("SpawnedAt") or 0)
		end
		return slotA < slotB
	end)

	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.FilterDescendantsInstances = { localPlayer.Character, visualPetFolder }
	local now = os.clock()

	for index, pet in ipairs(pets) do
		local ring = math.floor((index - 1) / 6)
		local ringIndex = (index - 1) % 6
		local ringCount = math.min(#pets - ring * 6, 6)
		local arc = math.rad(150)
		local step = ringCount > 1 and arc / (ringCount - 1) or 0
		local angle = -math.rad(75) + step * ringIndex
		local radius = 7 + ring * 4
		local sideOffset = math.sin(angle) * radius
		local backOffset = math.cos(angle) * radius + 3 + ring * 1.5
		local bob = math.sin(now * 2.4 + index) * 0.18
		local desired = root.Position - (root.CFrame.LookVector * backOffset) + (root.CFrame.RightVector * sideOffset)
		local rayResult = workspace:Raycast(desired + Vector3.new(0, 24, 0), Vector3.new(0, -90, 0), rayParams)
		if rayResult then
			desired = rayResult.Position + Vector3.new(0, 1.4 + bob, 0)
		else
			desired += Vector3.new(0, 1.2, 0)
		end

		local lookAt = Vector3.new(root.Position.X, desired.Y, root.Position.Z)
		if (lookAt - desired).Magnitude < 0.1 then
			lookAt = desired + root.CFrame.LookVector
		end
		local target = CFrame.new(desired, lookAt)
		local current = getPetPivot(pet)
		if current and (current.Position - desired).Magnitude < 45 then
			moveVisualPet(pet, current:Lerp(target, 0.35))
		else
			moveVisualPet(pet, target)
		end
	end
end

local function clearVisualPets()
	local folder = getVisualPetFolder()
	for _, child in ipairs(folder:GetChildren()) do
		child:Destroy()
	end
	clearVisualPetTools()
	setStatus("Visual pets cleared")
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
	amount = math.clamp(amount, 1, CONFIG.maxVisualPets)
	local startSlot = #folder:GetChildren()

	for index = 1, amount do
		if #folder:GetChildren() >= CONFIG.maxVisualPets then
			break
		end

		local petName = selected[((index - 1) % #selected) + 1]
		local template = petsFolder:FindFirstChild(petName)
		if template then
			local slot = startSlot + spawned + 1
			local clone = template:Clone()
			clone.Name = petName
			clone:SetAttribute("PetName", petName)
			clone:SetAttribute("Slot", slot)
			clone:SetAttribute("SpawnedAt", os.clock())
			prepVisualPet(clone, true)
			clone.Parent = folder
			playPetAnimations(clone)

			local angle = ((index - 1) / amount) * math.pi * 2
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

			if toolCount < CONFIG.maxVisualPetTools and makeLocalPetTool(petName, template, slot) then
				toolCount += 1
			end

			spawned += 1
			task.wait(0.03)
		end
	end

	trimVisualPets()
	pcall(updateVisualPetBehavior)
	setStatus(("Visual pets: spawned %d clone(s), %d backpack item(s)"):format(spawned, toolCount))
end

local function make(className, properties, parent)
	local instance = Instance.new(className)
	for key, value in pairs(properties or {}) do
		instance[key] = value
	end
	instance.Parent = parent
	return instance
end

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

local function makeToggle(label, key, order)
	local button = make("TextButton", {
		Name = key,
		AutoButtonColor = false,
		BackgroundColor3 = Color3.fromRGB(34, 41, 42),
		BorderSizePixel = 0,
		Font = Enum.Font.GothamSemibold,
		Text = label .. ": OFF",
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

makeToggle("Fruit Collector", "fruitCollector", 1)
makeToggle("Seed Placer", "seedPlacer", 2)
makeToggle("Auto Sell", "autoSell", 3)
makeToggle("Auto Buy Seeds", "autoBuySeeds", 4)
makeToggle("Auto Buy Gear", "autoBuyGear", 5)
makeToggle("AutoCollect Gold/Rainbow Seeds", "autoCollectRainbowSeeds", 6)
makeToggle("Auto Buy Pets", "autoBuyPets", 7)
makeToggle("Performance Mode", "performanceMode", 8)

local selectedSeedLabel = make("TextLabel", {
	Name = "SelectedSeedLabel",
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamSemibold,
	Text = "Seeds to buy",
	TextColor3 = Color3.fromRGB(221, 236, 216),
	TextSize = 13,
	TextXAlignment = Enum.TextXAlignment.Left,
	Size = UDim2.new(1, 0, 0, 18),
	LayoutOrder = 10,
}, content)

local seedRow = make("ScrollingFrame", {
	Name = "SeedSelector",
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	CanvasSize = UDim2.fromOffset(0, 0),
	ScrollBarThickness = 4,
	ScrollingDirection = Enum.ScrollingDirection.Y,
	Size = UDim2.new(1, 0, 0, 92),
	LayoutOrder = 11,
}, content)
make("UIGridLayout", {
	CellPadding = UDim2.fromOffset(6, 6),
	CellSize = UDim2.fromOffset(118, 28),
	SortOrder = Enum.SortOrder.LayoutOrder,
}, seedRow)

local seedLayout = seedRow:FindFirstChildOfClass("UIGridLayout")
local seedButtons = {}
local seedButtonCount = 0

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
end

local function scanSeedShopNames()
	local seedShop = playerGui:FindFirstChild("SeedShop")
	local frame = seedShop and seedShop:FindFirstChild("Frame")
	local normalShop = frame and frame:FindFirstChild("NormalShop")
	if not normalShop then
		return
	end

	for _, child in ipairs(normalShop:GetChildren()) do
		if child.Name ~= "ItemTemplate" and not string.find(string.lower(child.Name), "shelf", 1, true) then
			if child:FindFirstChild("Main_Frame", true) or child:FindFirstChildWhichIsA("GuiButton", true) then
				addUniqueName(seedNames, child.Name)
				makeSeedButton(child.Name)
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

playerGui.ChildAdded:Connect(function(child)
	if child.Name == "SeedShop" then
		task.wait(0.25)
		scanSeedShopNames()
	end
end)

local selectedGearLabel = make("TextLabel", {
	Name = "SelectedGearLabel",
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamSemibold,
	Text = "Gear to buy",
	TextColor3 = Color3.fromRGB(221, 236, 216),
	TextSize = 13,
	TextXAlignment = Enum.TextXAlignment.Left,
	Size = UDim2.new(1, 0, 0, 18),
	LayoutOrder = 12,
}, content)

local gearRow = make("ScrollingFrame", {
	Name = "GearSelector",
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	CanvasSize = UDim2.fromOffset(0, 0),
	ScrollBarThickness = 4,
	ScrollingDirection = Enum.ScrollingDirection.Y,
	Size = UDim2.new(1, 0, 0, 92),
	LayoutOrder = 13,
}, content)
make("UIGridLayout", {
	CellPadding = UDim2.fromOffset(6, 6),
	CellSize = UDim2.fromOffset(118, 28),
	SortOrder = Enum.SortOrder.LayoutOrder,
}, gearRow)

local gearLayout = gearRow:FindFirstChildOfClass("UIGridLayout")
local gearButtons = {}

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

for index, gearName in ipairs(gearNames) do
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
		LayoutOrder = index,
	}, gearRow)
	make("UICorner", { CornerRadius = UDim.new(0, 6) }, button)

	gearButtons[gearName] = button
	refreshGearButton(gearName)

	button.Activated:Connect(function()
		selectedGears[gearName] = not selectedGears[gearName]
		refreshGearButton(gearName)
		setStatus((selectedGears[gearName] and "Selected " or "Unselected ") .. gearName)
	end)
end

if gearLayout then
	gearLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(refreshGearCanvas)
end
refreshGearCanvas()

local selectedPetLabel = make("TextLabel", {
	Name = "SelectedPetLabel",
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamSemibold,
	Text = "Pets to buy",
	TextColor3 = Color3.fromRGB(221, 236, 216),
	TextSize = 13,
	TextXAlignment = Enum.TextXAlignment.Left,
	Size = UDim2.new(1, 0, 0, 18),
	LayoutOrder = 14,
}, content)

local petRow = make("ScrollingFrame", {
	Name = "PetSelector",
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	CanvasSize = UDim2.fromOffset(0, 0),
	ScrollBarThickness = 4,
	ScrollingDirection = Enum.ScrollingDirection.Y,
	Size = UDim2.new(1, 0, 0, 92),
	LayoutOrder = 15,
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

for _, petName in ipairs(petNames) do
	makePetButton(petName)
end

if petLayout then
	petLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(refreshPetCanvas)
end
refreshPetCanvas()

local selectedVisualPetLabel = make("TextLabel", {
	Name = "SelectedVisualPetLabel",
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamSemibold,
	Text = "Pets to visually spawn",
	TextColor3 = Color3.fromRGB(221, 236, 216),
	TextSize = 13,
	TextXAlignment = Enum.TextXAlignment.Left,
	Size = UDim2.new(1, 0, 0, 18),
	LayoutOrder = 16,
}, content)

local visualPetRow = make("ScrollingFrame", {
	Name = "VisualPetSelector",
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	CanvasSize = UDim2.fromOffset(0, 0),
	ScrollBarThickness = 4,
	ScrollingDirection = Enum.ScrollingDirection.Y,
	Size = UDim2.new(1, 0, 0, 92),
	LayoutOrder = 17,
}, content)
make("UIGridLayout", {
	CellPadding = UDim2.fromOffset(6, 6),
	CellSize = UDim2.fromOffset(118, 28),
	SortOrder = Enum.SortOrder.LayoutOrder,
}, visualPetRow)

local visualPetLayout = visualPetRow:FindFirstChildOfClass("UIGridLayout")
local visualPetButtons = {}
local visualPetButtonCount = 0

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
	LayoutOrder = 18,
}, content)
make("UICorner", { CornerRadius = UDim.new(0, 6) }, visualPetAmountBox)
make("UIPadding", {
	PaddingLeft = UDim.new(0, 10),
	PaddingRight = UDim.new(0, 10),
}, visualPetAmountBox)

local function refreshVisualPetAmount()
	local amount = math.floor(tonumber(visualPetAmountBox.Text) or CONFIG.visualPetAmount)
	amount = math.clamp(amount, 1, CONFIG.maxVisualPets)
	CONFIG.visualPetAmount = amount
	visualPetAmountBox.Text = tostring(amount)
	setStatus(("Visual pet amount set to %d"):format(amount))
end

visualPetAmountBox.FocusLost:Connect(refreshVisualPetAmount)

local assets = ReplicatedStorage:FindFirstChild("Assets")
local petsFolder = assets and assets:FindFirstChild("Pets")
if petsFolder then
	petsFolder.ChildAdded:Connect(function(pet)
		addUniqueName(petNames, pet.Name)
		makePetButton(pet.Name)
		makeVisualPetButton(pet.Name)
	end)
end

makeActionButton("Spawn Visual Pets", 19, spawnVisualPets)
makeActionButton("Clear Visual Pets", 20, clearVisualPets)

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

local timers = {
	fruitCollector = 0,
	seedPlacer = 0,
	autoSell = 0,
	autoBuySeeds = 0,
	autoBuyGear = 0,
	autoCollectRainbowSeeds = 0,
	autoBuyPets = 0,
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
