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
	collectInterval = 1.5,
	plantInterval = 1.0,
	sellInterval = 12.0,
	buyInterval = 5.0,
	rainbowCollectInterval = 1.5,
	petBuyInterval = 5.0,
	cacheRefreshInterval = 5.0,
	selectedSeed = "Carrot",
	plantRadius = 18,
}

local seedNames = {
	"Carrot",
	"Alien Apple",
	"Strawberry",
	"Blueberry",
	"Tomato",
	"Corn",
	"Watermelon",
	"Pumpkin",
	"Apple",
	"Bamboo",
	"Coconut",
	"Cactus",
	"Dragon Fruit",
	"Mango",
	"Grape",
	"Mushroom",
	"Pepper",
	"Cacao",
	"Beanstalk",
	"Sugar Apple",
	"Burning Bud",
	"Buttercup",
	"Crimson Thorn",
	"Elder Strawberry",
	"Ember Lily",
	"Firefly Spiral",
	"Giant Pinecone",
	"Octobloom",
	"Romanesco",
	"Sunflower",
	"Zebrazinkle",
}

local state = {
	fruitCollector = false,
	seedPlacer = false,
	autoSell = false,
	autoBuySeeds = false,
	autoCollectRainbowSeeds = false,
	autoBuyPets = false,
	performanceMode = false,
	lastStatus = "Ready",
}

local selectedSeeds = {
	Carrot = true,
}

local selectedPetText = ""

local function setStatus(message)
	state.lastStatus = tostring(message)
	if script:FindFirstChild("StatusValue") then
		script.StatusValue.Value = state.lastStatus
	end
end

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

local gameEvents = ReplicatedStorage:FindFirstChild("GameEvents")
local plantUpdate = gameEvents and getPath(gameEvents, "Plant.Update")

local remoteCandidates = {
	buySeed = {
		"GameEvents.BuySeedStock",
		"GameEvents.BuySeedStock_RE",
		"GameEvents.BuySeedStockEvent",
		"GameEvents.BuySeed",
		"GameEvents.Buy_Seed",
		"GameEvents.PurchaseSeed",
		"GameEvents.Purchase_Seed",
		"GameEvents.SeedShop",
		"GameEvents.SeedShop.BuySeed",
		"GameEvents.SeedShopService.BuySeed",
		"GameEvents.SeedShopService.BuySeedStock",
	},
	sell = {
		"GameEvents.Sell_Inventory",
		"GameEvents.SellInventory",
		"GameEvents.Sell_Item",
		"GameEvents.SellItem",
		"GameEvents.SellFruit",
		"GameEvents.Sell_Fruit",
		"GameEvents.ShopEvents.SellInventory",
	},
}

local function resolveRemote(path)
	return getPath(ReplicatedStorage, path)
end

local function fireRemote(remote, ...)
	if not remote then
		return false
	end

	if remote:IsA("RemoteEvent") then
		remote:FireServer(...)
		return true
	end

	if remote:IsA("RemoteFunction") then
		remote:InvokeServer(...)
		return true
	end

	return false
end

local function fireFirstRemote(paths, ...)
	for _, path in ipairs(paths) do
		local remote = resolveRemote(path)
		local ok = pcall(fireRemote, remote, ...)
		if ok and remote then
			return true, path
		end
	end
	return false
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

local cache = {
	workspaceAt = 0,
	workspaceDescendants = {},
	remoteKey = "",
	remoteMatches = {},
	seedFrames = {},
}

local function getWorkspaceDescendants()
	local now = os.clock()
	if now - cache.workspaceAt > CONFIG.cacheRefreshInterval then
		cache.workspaceAt = now
		cache.workspaceDescendants = workspace:GetDescendants()
	end

	return cache.workspaceDescendants
end

local function scanRemotes(terms)
	local key = table.concat(terms, "|")
	if cache.remoteMatches[key] then
		return cache.remoteMatches[key]
	end

	local matches = {}

	for _, descendant in ipairs(ReplicatedStorage:GetDescendants()) do
		if descendant:IsA("RemoteEvent") or descendant:IsA("RemoteFunction") then
			local haystack = string.lower(getObjectPath(descendant))
			local matched = true

			for _, term in ipairs(terms) do
				if not string.find(haystack, string.lower(term), 1, true) then
					matched = false
					break
				end
			end

			if matched then
				table.insert(matches, descendant)
			end
		end
	end

	cache.remoteMatches[key] = matches
	return matches
end

local function tryRemoteCalls(remotes, callSets)
	for _, remote in ipairs(remotes) do
		for _, args in ipairs(callSets) do
			local ok = pcall(function()
				fireRemote(remote, table.unpack(args))
			end)

			if ok then
				return true, getObjectPath(remote)
			end
		end
	end

	return false
end

local function textMatches(instance, terms)
	local haystack = string.lower(table.concat({
		instance.Name or "",
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
	if typeof(firesignal) == "function" then
		pcall(firesignal, button.MouseButton1Click)
		pcall(firesignal, button.Activated)
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

	for _, descendant in ipairs(getWorkspaceDescendants()) do
		if descendant:IsA("ProximityPrompt") and textMatches(descendant, { "collect", "harvest", "pick", "fruit" }) then
			if triggerPrompt(descendant) then
				fired += 1
			end
		end
	end

	local pickupEvent = gameEvents and gameEvents:FindFirstChild("PickupEvent")
	if pickupEvent and pickupEvent:IsA("BindableEvent") then
		for _, descendant in ipairs(getWorkspaceDescendants()) do
			if textMatches(descendant, { "fruit", "crop", "harvest" }) then
				pcall(function()
					pickupEvent:Fire(descendant)
				end)
				fired += 1
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

local function getSeedFrame(seedName)
	if cache.seedFrames[seedName] and cache.seedFrames[seedName].Parent then
		return cache.seedFrames[seedName]
	end

	local seedShop = playerGui:FindFirstChild("Seed_Shop")
	if not seedShop then
		return nil
	end

	local scrollingFrame = seedShop:FindFirstChild("Frame")
		and seedShop.Frame:FindFirstChild("ScrollingFrame")

	if scrollingFrame then
		local direct = scrollingFrame:FindFirstChild(seedName)
		if direct then
			cache.seedFrames[seedName] = direct
			return direct
		end
	end

	for _, descendant in ipairs(seedShop:GetDescendants()) do
		if descendant.Name == seedName then
			cache.seedFrames[seedName] = descendant
			return descendant
		end
	end

	return nil
end

local function getSelectedPetList()
	local selected = {}

	for petName in string.gmatch(selectedPetText, "[^,%s][^,]*") do
		local cleaned = string.gsub(petName, "^%s*(.-)%s*$", "%1")
		if cleaned ~= "" then
			table.insert(selected, cleaned)
		end
	end

	return selected
end

local function getFruitTools()
	local tools = {}
	local character = getCharacter()
	local backpack = localPlayer:FindFirstChildOfClass("Backpack")

	for _, container in ipairs({ character, backpack }) do
		if container then
			for _, item in ipairs(container:GetChildren()) do
				if item:IsA("Tool") then
					local name = string.lower(item.Name)
					local isSeed = string.find(name, "seed", 1, true)
					local isTool = string.find(name, "shovel", 1, true)
						or string.find(name, "sprinkler", 1, true)
						or string.find(name, "trowel", 1, true)
						or string.find(name, "can", 1, true)

					if not isSeed and not isTool then
						table.insert(tools, item)
					end
				end
			end
		end
	end

	return tools
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

local function autoCollectRainbowSeeds()
	local checked = 0
	local pickupEvent = gameEvents and gameEvents:FindFirstChild("PickupEvent")

	for _, descendant in ipairs(getWorkspaceDescendants()) do
		local matchesRainbowSeed = textMatches(descendant, {
			"rainbow",
			"seedrain",
			"seed rain",
			"gold seed",
			"seedpack",
			"seed pack",
		})

		if descendant:IsA("ProximityPrompt") and matchesRainbowSeed then
			if triggerPrompt(descendant) then
				checked += 1
			end
		elseif descendant:IsA("BasePart") and matchesRainbowSeed then
			if touchPart(descendant) then
				checked += 1
			end

			if pickupEvent and pickupEvent:IsA("BindableEvent") then
				pcall(function()
					pickupEvent:Fire(descendant)
				end)
			end
		end
	end

	setStatus(("Rainbow seeds: %d target(s) checked"):format(checked))
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

	local origin = root.Position
	local forward = root.CFrame.LookVector * math.random(4, CONFIG.plantRadius)
	local side = root.CFrame.RightVector * math.random(-CONFIG.plantRadius, CONFIG.plantRadius)
	local targetPosition = origin + forward + side

	if plantUpdate and plantUpdate:IsA("RemoteEvent") then
		local ok = pcall(function()
			plantUpdate:FireServer(targetPosition, CONFIG.selectedSeed)
		end)

		if not ok then
			pcall(function()
				plantUpdate:FireServer(CONFIG.selectedSeed, targetPosition)
			end)
		end
	else
		pcall(function()
			tool:Activate()
		end)
	end

	setStatus(("Seed placer: attempted %s"):format(CONFIG.selectedSeed))
end

local function autoSell()
	local fruitTools = getFruitTools()
	local sellCallSets = {
		{},
		{ "SellInventory" },
		{ "Sell_Inventory" },
		{ "All" },
		{ true },
	}

	for _, tool in ipairs(fruitTools) do
		table.insert(sellCallSets, { tool })
		table.insert(sellCallSets, { tool.Name })
		table.insert(sellCallSets, { "Sell_Item", tool })
		table.insert(sellCallSets, { "Sell_Item", tool.Name })
	end

	local sellRemotes = {}
	for _, path in ipairs(remoteCandidates.sell) do
		local remote = resolveRemote(path)
		if remote then
			table.insert(sellRemotes, remote)
		end
	end

	for _, remote in ipairs(scanRemotes({ "sell" })) do
		table.insert(sellRemotes, remote)
	end

	local usedRemote, path = tryRemoteCalls(sellRemotes, sellCallSets)
	if usedRemote then
		setStatus(("Auto sell: fired %s"):format(path))
		return
	end

	local fired = 0
	for _, descendant in ipairs(getWorkspaceDescendants()) do
		if descendant:IsA("ProximityPrompt") and textMatches(descendant, { "sell" }) then
			if triggerPrompt(descendant) then
				fired += 1
			end
		end
	end

	setStatus(("Auto sell: %d prompt(s) checked"):format(fired))
end

local function buyOneSeed(seedName)
	local buyCallSets = {
		{ seedName },
		{ seedName .. " Seed" },
		{ "BuySeedStock", seedName },
		{ "BuySeed", seedName },
		{ "Seed", seedName },
		{ seedName, 1 },
		{ seedName .. " Seed", 1 },
	}

	local buyRemotes = {}
	for _, path in ipairs(remoteCandidates.buySeed) do
		local remote = resolveRemote(path)
		if remote then
			table.insert(buyRemotes, remote)
		end
	end

	for _, remote in ipairs(scanRemotes({ "buy", "seed" })) do
		table.insert(buyRemotes, remote)
	end

	for _, remote in ipairs(scanRemotes({ "seed", "stock" })) do
		table.insert(buyRemotes, remote)
	end

	local usedRemote, path = tryRemoteCalls(buyRemotes, buyCallSets)
	if usedRemote then
		return true, ("Auto buy: fired %s for %s"):format(path, seedName)
	end

	local seedFrame = getSeedFrame(seedName)

	local clicked = false
	if seedFrame then
		local mainFrame = seedFrame:FindFirstChild("Main_Frame", true)
		if mainFrame and mainFrame:IsA("GuiButton") then
			activateButton(mainFrame)
			task.wait(0.08)
		end

		for _, buttonName in ipairs({ "Sheckles_Buy", "Buy", "CashBuy" }) do
			local button = seedFrame:FindFirstChild(buttonName, true)
			if button and button:IsA("GuiButton") and button.Visible and activateButton(button) then
				clicked = true
				break
			end
		end
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

local function buyOnePet(petName)
	for _, descendant in ipairs(getWorkspaceDescendants()) do
		if descendant:IsA("ProximityPrompt") then
			local isBuyPrompt = textMatches(descendant, { "buy", "purchase", "adopt" })
			local isPetPrompt = textMatches(descendant, { petName })

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

local statusValue = Instance.new("StringValue")
statusValue.Name = "StatusValue"
statusValue.Value = state.lastStatus
statusValue.Parent = script

local gui = make("ScreenGui", {
	Name = "GardenAutomationGui",
	ResetOnSpawn = false,
	IgnoreGuiInset = false,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
}, playerGui)

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

makeToggle("Fruit Collector", "fruitCollector", 1)
makeToggle("Seed Placer", "seedPlacer", 2)
makeToggle("Auto Sell", "autoSell", 3)
makeToggle("Auto Buy Seeds", "autoBuySeeds", 4)
makeToggle("Rainbow Seeds", "autoCollectRainbowSeeds", 5)
makeToggle("Auto Buy Pets", "autoBuyPets", 6)
makeToggle("Performance Mode", "performanceMode", 7)

local selectedSeedLabel = make("TextLabel", {
	Name = "SelectedSeedLabel",
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamSemibold,
	Text = "Seeds to buy",
	TextColor3 = Color3.fromRGB(221, 236, 216),
	TextSize = 13,
	TextXAlignment = Enum.TextXAlignment.Left,
	Size = UDim2.new(1, 0, 0, 18),
	LayoutOrder = 7,
}, content)

local seedRow = make("ScrollingFrame", {
	Name = "SeedSelector",
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	CanvasSize = UDim2.fromOffset(0, 0),
	ScrollBarThickness = 4,
	ScrollingDirection = Enum.ScrollingDirection.Y,
	Size = UDim2.new(1, 0, 0, 92),
	LayoutOrder = 8,
}, content)
make("UIGridLayout", {
	CellPadding = UDim2.fromOffset(6, 6),
	CellSize = UDim2.fromOffset(118, 28),
	SortOrder = Enum.SortOrder.LayoutOrder,
}, seedRow)

local seedLayout = seedRow:FindFirstChildOfClass("UIGridLayout")
local seedButtons = {}

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

for index, seedName in ipairs(seedNames) do
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
		LayoutOrder = index,
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
end

if seedLayout then
	seedLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(refreshSeedCanvas)
end
refreshSeedCanvas()

local selectedPetLabel = make("TextLabel", {
	Name = "SelectedPetLabel",
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamSemibold,
	Text = "Pet names to buy",
	TextColor3 = Color3.fromRGB(221, 236, 216),
	TextSize = 13,
	TextXAlignment = Enum.TextXAlignment.Left,
	Size = UDim2.new(1, 0, 0, 18),
	LayoutOrder = 9,
}, content)

local petBox = make("TextBox", {
	Name = "PetNameBox",
	BackgroundColor3 = Color3.fromRGB(52, 60, 54),
	BorderSizePixel = 0,
	ClearTextOnFocus = false,
	Font = Enum.Font.GothamSemibold,
	PlaceholderText = "Type names, comma separated",
	Text = selectedPetText,
	TextColor3 = Color3.fromRGB(242, 247, 239),
	TextSize = 13,
	TextWrapped = true,
	TextXAlignment = Enum.TextXAlignment.Left,
	Size = UDim2.new(1, 0, 0, 46),
	LayoutOrder = 10,
}, content)
make("UICorner", { CornerRadius = UDim.new(0, 6) }, petBox)
make("UIPadding", {
	PaddingLeft = UDim.new(0, 10),
	PaddingRight = UDim.new(0, 10),
}, petBox)

petBox.FocusLost:Connect(function()
	selectedPetText = petBox.Text
	setStatus("Pet filter: " .. (selectedPetText ~= "" and selectedPetText or "none"))
end)

petBox:GetPropertyChangedSignal("Text"):Connect(function()
	selectedPetText = petBox.Text
end)

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
	autoCollectRainbowSeeds = 0,
	autoBuyPets = 0,
}

RunService.Heartbeat:Connect(function(deltaTime)
	timers.fruitCollector += deltaTime
	timers.seedPlacer += deltaTime
	timers.autoSell += deltaTime
	timers.autoBuySeeds += deltaTime
	timers.autoCollectRainbowSeeds += deltaTime
	timers.autoBuyPets += deltaTime

	if state.fruitCollector and timers.fruitCollector >= CONFIG.collectInterval then
		timers.fruitCollector = 0
		task.spawn(collectFruit)
	end

	if state.seedPlacer and timers.seedPlacer >= CONFIG.plantInterval then
		timers.seedPlacer = 0
		task.spawn(plantSeed)
	end

	if state.autoSell and timers.autoSell >= CONFIG.sellInterval then
		timers.autoSell = 0
		task.spawn(autoSell)
	end

	if state.autoBuySeeds and timers.autoBuySeeds >= CONFIG.buyInterval then
		timers.autoBuySeeds = 0
		task.spawn(buySeed)
	end

	if state.autoCollectRainbowSeeds and timers.autoCollectRainbowSeeds >= CONFIG.rainbowCollectInterval then
		timers.autoCollectRainbowSeeds = 0
		task.spawn(autoCollectRainbowSeeds)
	end

	if state.autoBuyPets and timers.autoBuyPets >= CONFIG.petBuyInterval then
		timers.autoBuyPets = 0
		task.spawn(buyPets)
	end
end)

setStatus("Garden Tools loaded")
