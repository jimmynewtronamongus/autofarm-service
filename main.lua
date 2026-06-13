-- Garden automation GUI for private testing in a Grow-a-Garden-style place.
-- Drop this LocalScript in StarterPlayerScripts, or run it from a local test client.

local Players = game:GetService("Players")
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
	autoCollectRainbowSeeds = false,
	autoBuyPets = false,
	performanceMode = false,
	lastStatus = "Ready",
}

local selectedSeeds = {
	Carrot = true,
}

local selectedPetText = "Frog, Bunny, Deer"
local statusValue

local function setStatus(message)
	state.lastStatus = tostring(message)
	if statusValue then
		statusValue.Value = state.lastStatus
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
	seedFrames = {},
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
		if rowButton and rowButton:IsA("GuiButton") and rowButton.Visible and activateButton(rowButton) then
			clicked = true
			task.wait(0.08)
		end

		for _, buttonName in ipairs({ "TextButton", "Sheckles_Buy", "Buy", "CashBuy" }) do
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
	local wildPetSpawns = getWildPetSpawns()
	local petTerm = string.lower(petName)

	for _, descendant in ipairs(getCachedDescendants("wildPets", wildPetSpawns)) do
		if descendant:IsA("ProximityPrompt") then
			local model = descendant:FindFirstAncestorWhichIsA("Model")
			local modelName = model and string.lower(model.Name) or ""
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

	if state.autoCollectRainbowSeeds and timers.autoCollectRainbowSeeds >= CONFIG.rainbowCollectInterval then
		timers.autoCollectRainbowSeeds = 0
		runGuarded("autoCollectRainbowSeeds", autoCollectRainbowSeeds)
	end

	if state.autoBuyPets and timers.autoBuyPets >= CONFIG.petBuyInterval then
		timers.autoBuyPets = 0
		runGuarded("autoBuyPets", buyPets)
	end
end)

setStatus("Garden Tools loaded")
