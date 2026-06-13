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
	collectInterval = 0.25,
	plantInterval = 1.0,
	sellInterval = 8.0,
	buyInterval = 2.0,
	selectedSeed = "Carrot",
	plantRadius = 18,
}

local seedNames = {
	"Carrot",
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
}

local state = {
	fruitCollector = false,
	seedPlacer = false,
	autoSell = false,
	autoBuySeeds = false,
	lastStatus = "Ready",
}

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
		"GameEvents.BuySeed",
		"GameEvents.SeedShop.BuySeed",
		"GameEvents.SeedShopService.BuySeed",
	},
	sell = {
		"GameEvents.Sell_Inventory",
		"GameEvents.SellInventory",
		"GameEvents.Sell_Item",
		"GameEvents.SellItem",
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

local function textMatches(instance, terms)
	local haystack = string.lower(table.concat({
		instance.Name or "",
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

	for _, descendant in ipairs(workspace:GetDescendants()) do
		if descendant:IsA("ProximityPrompt") and textMatches(descendant, { "collect", "harvest", "pick", "fruit" }) then
			if triggerPrompt(descendant) then
				fired += 1
			end
		end
	end

	local pickupEvent = gameEvents and gameEvents:FindFirstChild("PickupEvent")
	if pickupEvent and pickupEvent:IsA("BindableEvent") then
		for _, descendant in ipairs(workspace:GetDescendants()) do
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
	local usedRemote, path = fireFirstRemote(remoteCandidates.sell)
	if usedRemote then
		setStatus(("Auto sell: fired %s"):format(path))
		return
	end

	local fired = 0
	for _, descendant in ipairs(workspace:GetDescendants()) do
		if descendant:IsA("ProximityPrompt") and textMatches(descendant, { "sell" }) then
			if triggerPrompt(descendant) then
				fired += 1
			end
		end
	end

	setStatus(("Auto sell: %d prompt(s) checked"):format(fired))
end

local function buySeed()
	local usedRemote, path = fireFirstRemote(remoteCandidates.buySeed, CONFIG.selectedSeed)
	if usedRemote then
		setStatus(("Auto buy: fired %s for %s"):format(path, CONFIG.selectedSeed))
		return
	end

	local seedShop = playerGui:FindFirstChild("Seed_Shop")
	local button = seedShop
		and seedShop:FindFirstChild("Frame")
		and seedShop.Frame:FindFirstChild("ScrollingFrame")
		and seedShop.Frame.ScrollingFrame:FindFirstChild(CONFIG.selectedSeed)
		and seedShop.Frame.ScrollingFrame[CONFIG.selectedSeed]:FindFirstChild("Main_Frame")

	if button and button:IsA("GuiButton") and activateButton(button) then
		setStatus(("Auto buy: clicked %s"):format(CONFIG.selectedSeed))
	else
		setStatus(("Auto buy: no buy remote/button for %s"):format(CONFIG.selectedSeed))
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
	Size = UDim2.fromOffset(286, 362),
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

local content = make("Frame", {
	Name = "Content",
	BackgroundTransparency = 1,
	Position = UDim2.fromOffset(14, 60),
	Size = UDim2.new(1, -28, 1, -74),
}, panel)
make("UIListLayout", {
	Padding = UDim.new(0, 10),
	SortOrder = Enum.SortOrder.LayoutOrder,
}, content)

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
	end)
end

makeToggle("Fruit Collector", "fruitCollector", 1)
makeToggle("Seed Placer", "seedPlacer", 2)
makeToggle("Auto Sell", "autoSell", 3)
makeToggle("Auto Buy Seeds", "autoBuySeeds", 4)

local seedRow = make("Frame", {
	Name = "SeedRow",
	BackgroundTransparency = 1,
	Size = UDim2.new(1, 0, 0, 38),
	LayoutOrder = 5,
}, content)

local seedButton = make("TextButton", {
	Name = "SeedButton",
	AutoButtonColor = true,
	BackgroundColor3 = Color3.fromRGB(52, 60, 54),
	BorderSizePixel = 0,
	Font = Enum.Font.GothamSemibold,
	Text = "Seed: " .. CONFIG.selectedSeed,
	TextColor3 = Color3.fromRGB(242, 247, 239),
	TextSize = 14,
	Size = UDim2.new(1, 0, 1, 0),
}, seedRow)
make("UICorner", { CornerRadius = UDim.new(0, 6) }, seedButton)

local seedIndex = 1
seedButton.Activated:Connect(function()
	seedIndex += 1
	if seedIndex > #seedNames then
		seedIndex = 1
	end

	CONFIG.selectedSeed = seedNames[seedIndex]
	seedButton.Text = "Seed: " .. CONFIG.selectedSeed
	setStatus("Selected seed: " .. CONFIG.selectedSeed)
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
}

RunService.Heartbeat:Connect(function(deltaTime)
	timers.fruitCollector += deltaTime
	timers.seedPlacer += deltaTime
	timers.autoSell += deltaTime
	timers.autoBuySeeds += deltaTime

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
end)

setStatus("Garden Tools loaded")
