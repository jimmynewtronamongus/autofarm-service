-- Main.server.lua
-- Client-safe script hub loader. It can be used as a loadstring, but it does
-- not bypass server authority. Farm actions only work when your own server has
-- compatible DevScriptHubRemotes in ReplicatedStorage.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
if not player then
	warn("[ScriptHub] This script must run on the client.")
	return
end

local playerGui = player:WaitForChild("PlayerGui")

local REMOTE_FOLDER_NAME = "DevScriptHubRemotes"
local ACTION_REMOTE_NAME = "Action"
local STATUS_REMOTE_NAME = "Status"

local COLORS = {
	bg = Color3.fromRGB(9, 12, 18),
	panel = Color3.fromRGB(15, 20, 30),
	panel2 = Color3.fromRGB(21, 28, 40),
	card = Color3.fromRGB(25, 34, 48),
	stroke = Color3.fromRGB(76, 90, 112),
	text = Color3.fromRGB(241, 245, 249),
	muted = Color3.fromRGB(148, 163, 184),
	green = Color3.fromRGB(31, 122, 73),
	green2 = Color3.fromRGB(19, 83, 45),
	blue = Color3.fromRGB(37, 99, 235),
	red = Color3.fromRGB(153, 43, 43),
	yellow = Color3.fromRGB(202, 138, 4),
}

local SEED_OPTIONS = {
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
	"Moon Bloom",
}

local PRESETS = {
	{
		name = "Collector",
		buyAmount = 1,
		harvestRadius = 250,
		modes = {
			autoBuy = false,
			autoPlant = false,
			autoHarvest = true,
			autoSell = false,
		},
	},
	{
		name = "Replant",
		buyAmount = 1,
		harvestRadius = 500,
		modes = {
			autoBuy = false,
			autoPlant = true,
			autoHarvest = true,
			autoSell = false,
		},
	},
	{
		name = "Full Autofarm",
		buyAmount = 5,
		harvestRadius = 750,
		modes = {
			autoBuy = true,
			autoPlant = true,
			autoHarvest = true,
			autoSell = true,
		},
	},
}

local state = {
	enabled = false,
	autoBuy = false,
	autoPlant = false,
	autoHarvest = false,
	autoSell = false,
	seedName = "Carrot",
	buyAmount = 1,
	harvestRadius = 250,
	totalBought = 0,
	totalPlanted = 0,
	totalHarvested = 0,
	totalSold = 0,
	lastResult = "server hub not found",
}

local refs = {
	tabButtons = {},
	pages = {},
	statLabels = {},
}

local actionRemote = nil
local statusRemote = nil
local actionConnection = nil
local activeTab = "Farm"
local seedIndex = 1
local refreshUi = nil

local function create(className, props, children)
	local object = Instance.new(className)
	for key, value in pairs(props or {}) do
		object[key] = value
	end
	for _, child in ipairs(children or {}) do
		child.Parent = object
	end
	return object
end

local function corner(radius)
	return create("UICorner", {
		CornerRadius = UDim.new(0, radius),
	})
end

local function stroke(color, thickness, transparency)
	return create("UIStroke", {
		Color = color,
		Thickness = thickness or 1,
		Transparency = transparency or 0,
	})
end

local function padding(left, top, right, bottom)
	return create("UIPadding", {
		PaddingLeft = UDim.new(0, left),
		PaddingTop = UDim.new(0, top),
		PaddingRight = UDim.new(0, right),
		PaddingBottom = UDim.new(0, bottom),
	})
end

local function label(text, size, color, font)
	return create("TextLabel", {
		BackgroundTransparency = 1,
		Font = font or Enum.Font.GothamMedium,
		Text = text,
		TextColor3 = color or COLORS.text,
		TextSize = size or 13,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
		TextWrapped = true,
	})
end

local function button(text, color)
	return create("TextButton", {
		AutoButtonColor = true,
		BackgroundColor3 = color or COLORS.card,
		BorderSizePixel = 0,
		Font = Enum.Font.GothamBold,
		Text = text,
		TextColor3 = COLORS.text,
		TextSize = 13,
		TextWrapped = true,
	}, {
		corner(8),
		stroke(COLORS.stroke, 1, 0.35),
	})
end

local function field(text)
	return create("TextBox", {
		BackgroundColor3 = COLORS.bg,
		BorderSizePixel = 0,
		ClearTextOnFocus = false,
		Font = Enum.Font.GothamMedium,
		PlaceholderColor3 = COLORS.muted,
		Text = text,
		TextColor3 = COLORS.text,
		TextSize = 13,
		TextWrapped = true,
	}, {
		corner(8),
		stroke(COLORS.stroke, 1, 0.3),
		padding(10, 0, 10, 0),
	})
end

local function card(parent, y, height)
	local frame = create("Frame", {
		BackgroundColor3 = COLORS.card,
		BorderSizePixel = 0,
		Position = UDim2.new(0, 0, 0, y),
		Size = UDim2.new(1, 0, 0, height),
	}, {
		corner(10),
		stroke(COLORS.stroke, 1, 0.55),
		padding(12, 10, 12, 10),
	})
	frame.Parent = parent
	return frame
end

local function setStatus(message, color)
	state.lastResult = message
	if refs.status then
		refs.status.Text = "Status: " .. tostring(message)
		refs.status.TextColor3 = color or COLORS.muted
	end
end

local function connectActionRemote()
	if actionConnection then
		actionConnection:Disconnect()
		actionConnection = nil
	end

	if actionRemote then
		actionConnection = actionRemote.OnClientEvent:Connect(function(success, result)
			if success then
				if typeof(result) == "table" then
					for key, value in pairs(result) do
						state[key] = value
					end
					setStatus(state.lastResult or "updated", COLORS.green)
				else
					setStatus("updated", COLORS.green)
				end
			else
				setStatus(tostring(result), COLORS.red)
			end
			if refs.panel then
				task.defer(function()
					if refs.refresh then
						refs.refresh()
					end
				end)
			end
		end)
	end
end

local function findRemotes()
	local folder = ReplicatedStorage:FindFirstChild(REMOTE_FOLDER_NAME)
	local previousAction = actionRemote

	actionRemote = nil
	statusRemote = nil

	if folder then
		local foundAction = folder:FindFirstChild(ACTION_REMOTE_NAME)
		local foundStatus = folder:FindFirstChild(STATUS_REMOTE_NAME)
		if foundAction and foundAction:IsA("RemoteEvent") then
			actionRemote = foundAction
		end
		if foundStatus and foundStatus:IsA("RemoteFunction") then
			statusRemote = foundStatus
		end
	end

	if previousAction ~= actionRemote then
		connectActionRemote()
	end

	return actionRemote ~= nil or statusRemote ~= nil
end

local function send(actionName, payload)
	findRemotes()
	if not actionRemote then
		if actionName == "setEnabled" then
			state.enabled = payload and payload.enabled == true
		elseif actionName == "setMode" and payload then
			state[payload.mode] = payload.enabled == true
		elseif actionName == "setSeed" and payload then
			state.seedName = payload.seedName or state.seedName
		elseif actionName == "setBuyAmount" and payload then
			state.buyAmount = tonumber(payload.amount) or state.buyAmount
		elseif actionName == "setHarvestRadius" and payload then
			state.harvestRadius = tonumber(payload.radius) or state.harvestRadius
		elseif actionName == "stopAll" then
			state.enabled = false
			state.autoBuy = false
			state.autoPlant = false
			state.autoHarvest = false
			state.autoSell = false
		end
		setStatus("server remotes required", COLORS.yellow)
		refreshUi()
		return
	end

	actionRemote:FireServer(actionName, payload or {})
end

local function requestStatus()
	findRemotes()
	if not statusRemote then
		setStatus("server hub not found", COLORS.yellow)
		return
	end

	local ok, success, result = pcall(function()
		return statusRemote:InvokeServer()
	end)

	if not ok then
		setStatus("server did not answer", COLORS.red)
	elseif success then
		if typeof(result) == "table" then
			for key, value in pairs(result) do
				state[key] = value
			end
		end
		setStatus(state.lastResult or "ready", COLORS.green)
	else
		setStatus(tostring(result), COLORS.red)
	end
end

local function setButtonState(buttonRef, enabled)
	buttonRef.Text = buttonRef:GetAttribute("Label") .. ": " .. (enabled and "ON" or "OFF")
	buttonRef.BackgroundColor3 = enabled and COLORS.green2 or COLORS.card
end

refreshUi = function()
	if not refs.panel then
		return
	end

	setButtonState(refs.masterToggle, state.enabled)
	setButtonState(refs.buyToggle, state.autoBuy)
	setButtonState(refs.plantToggle, state.autoPlant)
	setButtonState(refs.harvestToggle, state.autoHarvest)
	setButtonState(refs.sellToggle, state.autoSell)

	refs.seedBox.Text = state.seedName or "Carrot"
	refs.amountBox.Text = tostring(state.buyAmount or 1)
	refs.radiusBox.Text = tostring(state.harvestRadius or 250)

	refs.statLabels.bought.Text = tostring(state.totalBought or 0)
	refs.statLabels.planted.Text = tostring(state.totalPlanted or 0)
	refs.statLabels.harvested.Text = tostring(state.totalHarvested or 0)
	refs.statLabels.sold.Text = tostring(state.totalSold or 0)

	refs.connection.Text = ("Remotes: %s / %s"):format(actionRemote and "Action" or "No action", statusRemote and "Status" or "No status")
	refs.connection.TextColor3 = (actionRemote or statusRemote) and COLORS.green or COLORS.yellow
	refs.status.Text = "Status: " .. tostring(state.lastResult or "idle")
end

refs.refresh = refreshUi

local function applyPreset(preset)
	send("setBuyAmount", {
		amount = preset.buyAmount,
	})
	send("setHarvestRadius", {
		radius = preset.harvestRadius,
	})
	for modeName, enabled in pairs(preset.modes) do
		send("setMode", {
			mode = modeName,
			enabled = enabled,
		})
	end
	setStatus("applied " .. preset.name, COLORS.green)
end

local function makeToggle(parent, text, stateKey, modeName, position)
	local item = button(text .. ": OFF")
	item:SetAttribute("Label", text)
	item.Position = position
	item.Size = UDim2.new(0.5, -6, 0, 38)
	item.Parent = parent
	item.MouseButton1Click:Connect(function()
		send("setMode", {
			mode = modeName,
			enabled = not state[stateKey],
		})
	end)
	return item
end

local function makeStat(parent, title, key, x)
	local item = create("Frame", {
		BackgroundColor3 = COLORS.panel2,
		BorderSizePixel = 0,
		Position = UDim2.new(x, 0, 0, 0),
		Size = UDim2.new(0.25, -7, 1, 0),
	}, {
		corner(8),
		padding(8, 6, 8, 6),
	})
	item.Parent = parent

	local value = label("0", 16, COLORS.text, Enum.Font.GothamBold)
	value.Size = UDim2.new(1, 0, 0, 22)
	value.Parent = item

	local name = label(title, 10, COLORS.muted)
	name.Position = UDim2.new(0, 0, 0, 23)
	name.Size = UDim2.new(1, 0, 0, 16)
	name.Parent = item

	refs.statLabels[key] = value
end

local function setTab(tabName)
	activeTab = tabName
	for name, page in pairs(refs.pages) do
		page.Visible = name == tabName
	end
	for name, tabButton in pairs(refs.tabButtons) do
		tabButton.BackgroundColor3 = name == tabName and COLORS.blue or COLORS.panel2
	end
end

local function enableDragging(handle, target)
	local dragging = false
	local dragStart = nil
	local startPosition = nil

	handle.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			dragStart = input.Position
			startPosition = target.Position
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
			target.Position = UDim2.new(startPosition.X.Scale, startPosition.X.Offset + delta.X, startPosition.Y.Scale, startPosition.Y.Offset + delta.Y)
		end
	end)
end

local function buildGui()
	local existing = playerGui:FindFirstChild("DevScriptHub")
	if existing then
		existing:Destroy()
	end

	local screen = create("ScreenGui", {
		Name = "DevScriptHub",
		DisplayOrder = 50,
		IgnoreGuiInset = false,
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	})

	local launcher = button("Hub", COLORS.green2)
	launcher.Name = "Launcher"
	launcher.Position = UDim2.new(0, 18, 0.5, -22)
	launcher.Size = UDim2.new(0, 74, 0, 44)
	launcher.Parent = screen

	local panel = create("Frame", {
		Name = "Panel",
		AnchorPoint = Vector2.new(0, 0.5),
		BackgroundColor3 = COLORS.panel,
		BorderSizePixel = 0,
		Position = UDim2.new(0, 110, 0.5, 0),
		Size = UDim2.new(0, 430, 0, 520),
		Visible = true,
	}, {
		corner(12),
		stroke(COLORS.stroke, 1, 0.2),
		padding(14, 14, 14, 14),
	})
	panel.Parent = screen
	refs.panel = panel

	local header = create("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 54),
	})
	header.Parent = panel
	enableDragging(header, panel)

	local title = label("Grow a Garden 2 Autofarm", 18, COLORS.text, Enum.Font.GothamBold)
	title.Size = UDim2.new(1, -92, 0, 26)
	title.Parent = header

	refs.status = label("Status: loading", 12, COLORS.muted)
	refs.status.Position = UDim2.new(0, 0, 0, 27)
	refs.status.Size = UDim2.new(1, -92, 0, 20)
	refs.status.Parent = header

	local refresh = button("Sync", COLORS.blue)
	refresh.Position = UDim2.new(1, -88, 0, 2)
	refresh.Size = UDim2.new(0, 48, 0, 30)
	refresh.Parent = header
	refresh.MouseButton1Click:Connect(function()
		requestStatus()
		refreshUi()
	end)

	local close = button("X", COLORS.red)
	close.Position = UDim2.new(1, -34, 0, 2)
	close.Size = UDim2.new(0, 34, 0, 30)
	close.Parent = header

	local tabs = create("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 0, 0, 62),
		Size = UDim2.new(1, 0, 0, 36),
	})
	tabs.Parent = panel

	local tabLayout = create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
	})
	tabLayout.Parent = tabs

	for _, tabName in ipairs({ "Farm", "Presets", "Tools" }) do
		local tabButton = button(tabName, tabName == activeTab and COLORS.blue or COLORS.panel2)
		tabButton.Size = UDim2.new(0.333, -6, 1, 0)
		tabButton.Parent = tabs
		tabButton.MouseButton1Click:Connect(function()
			setTab(tabName)
		end)
		refs.tabButtons[tabName] = tabButton
	end

	local pageHolder = create("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 0, 0, 112),
		Size = UDim2.new(1, 0, 1, -112),
	})
	pageHolder.Parent = panel

	for _, tabName in ipairs({ "Farm", "Presets", "Tools" }) do
		refs.pages[tabName] = create("Frame", {
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 1, 0),
			Visible = tabName == activeTab,
		})
		refs.pages[tabName].Parent = pageHolder
	end

	local farmPage = refs.pages.Farm

	local stats = card(farmPage, 0, 58)
	stats.Size = UDim2.new(1, 0, 0, 58)
	makeStat(stats, "Bought", "bought", 0)
	makeStat(stats, "Planted", "planted", 0.25)
	makeStat(stats, "Harvested", "harvested", 0.5)
	makeStat(stats, "Sold", "sold", 0.75)

	refs.masterToggle = button("Auto Farm: OFF", COLORS.card)
	refs.masterToggle:SetAttribute("Label", "Auto Farm")
	refs.masterToggle.Position = UDim2.new(0, 0, 0, 72)
	refs.masterToggle.Size = UDim2.new(1, 0, 0, 42)
	refs.masterToggle.Parent = farmPage
	refs.masterToggle.MouseButton1Click:Connect(function()
		send("setEnabled", {
			enabled = not state.enabled,
		})
	end)

	local toggleCard = card(farmPage, 128, 98)
	refs.harvestToggle = makeToggle(toggleCard, "Fruit Collector", "autoHarvest", "autoHarvest", UDim2.new(0, 0, 0, 0))
	refs.plantToggle = makeToggle(toggleCard, "Seed Placer", "autoPlant", "autoPlant", UDim2.new(0.5, 6, 0, 0))
	refs.sellToggle = makeToggle(toggleCard, "Auto Sell", "autoSell", "autoSell", UDim2.new(0, 0, 0, 46))
	refs.buyToggle = makeToggle(toggleCard, "Auto Buy Seeds", "autoBuy", "autoBuy", UDim2.new(0.5, 6, 0, 46))

	local form = card(farmPage, 240, 124)

	local function row(rowLabel, boxRef, y, applyAction)
		local text = label(rowLabel, 12, COLORS.muted)
		text.Position = UDim2.new(0, 0, 0, y)
		text.Size = UDim2.new(0, 96, 0, 34)
		text.Parent = form

		local input = field("")
		input.Position = UDim2.new(0, 104, 0, y)
		input.Size = UDim2.new(1, -178, 0, 34)
		input.Parent = form

		local apply = button("Set", COLORS.blue)
		apply.Position = UDim2.new(1, -64, 0, y)
		apply.Size = UDim2.new(0, 64, 0, 34)
		apply.Parent = form
		apply.MouseButton1Click:Connect(function()
			applyAction(input.Text)
		end)

		refs[boxRef] = input
	end

	row("Seed", "seedBox", 0, function(text)
		send("setSeed", {
			seedName = text,
		})
	end)
	row("Seed buy x", "amountBox", 42, function(text)
		send("setBuyAmount", {
			amount = tonumber(text),
		})
	end)
	row("Collect radius", "radiusBox", 84, function(text)
		send("setHarvestRadius", {
			radius = tonumber(text),
		})
	end)

	local quickSeeds = create("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 0, 0, 378),
		Size = UDim2.new(1, 0, 0, 38),
	})
	quickSeeds.Parent = farmPage

	local prevSeed = button("<", COLORS.panel2)
	prevSeed.Position = UDim2.new(0, 0, 0, 0)
	prevSeed.Size = UDim2.new(0, 42, 1, 0)
	prevSeed.Parent = quickSeeds

	local seedPick = button("Next seed", COLORS.panel2)
	seedPick.Position = UDim2.new(0, 50, 0, 0)
	seedPick.Size = UDim2.new(1, -100, 1, 0)
	seedPick.Parent = quickSeeds

	local nextSeed = button(">", COLORS.panel2)
	nextSeed.Position = UDim2.new(1, -42, 0, 0)
	nextSeed.Size = UDim2.new(0, 42, 1, 0)
	nextSeed.Parent = quickSeeds

	local function chooseSeed(delta)
		seedIndex += delta
		if seedIndex < 1 then
			seedIndex = #SEED_OPTIONS
		elseif seedIndex > #SEED_OPTIONS then
			seedIndex = 1
		end
		send("setSeed", {
			seedName = SEED_OPTIONS[seedIndex],
		})
	end

	prevSeed.MouseButton1Click:Connect(function()
		chooseSeed(-1)
	end)
	seedPick.MouseButton1Click:Connect(function()
		chooseSeed(1)
	end)
	nextSeed.MouseButton1Click:Connect(function()
		chooseSeed(1)
	end)

	local actions = create("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 0, 1, -42),
		Size = UDim2.new(1, 0, 0, 42),
	})
	actions.Parent = farmPage

	local step = button("Run once", COLORS.blue)
	step.Position = UDim2.new(0, 0, 0, 0)
	step.Size = UDim2.new(0.5, -5, 1, 0)
	step.Parent = actions
	step.MouseButton1Click:Connect(function()
		send("stepOnce")
	end)

	local stop = button("Stop all", COLORS.red)
	stop.Position = UDim2.new(0.5, 5, 0, 0)
	stop.Size = UDim2.new(0.5, -5, 1, 0)
	stop.Parent = actions
	stop.MouseButton1Click:Connect(function()
		send("stopAll")
	end)

	local presetPage = refs.pages.Presets
	for index, preset in ipairs(PRESETS) do
		local presetCard = card(presetPage, (index - 1) * 98, 84)
		local presetTitle = label(preset.name, 15, COLORS.text, Enum.Font.GothamBold)
		presetTitle.Size = UDim2.new(1, -92, 0, 24)
		presetTitle.Parent = presetCard

		local presetText = label(("Auto buy x%d | Collect radius %d"):format(preset.buyAmount, preset.harvestRadius), 12, COLORS.muted)
		presetText.Position = UDim2.new(0, 0, 0, 28)
		presetText.Size = UDim2.new(1, -92, 0, 22)
		presetText.Parent = presetCard

		local apply = button("Apply", COLORS.green2)
		apply.Position = UDim2.new(1, -80, 0, 13)
		apply.Size = UDim2.new(0, 80, 0, 40)
		apply.Parent = presetCard
		apply.MouseButton1Click:Connect(function()
			applyPreset(preset)
		end)
	end

	local toolsPage = refs.pages.Tools
	local diag = card(toolsPage, 0, 148)

	refs.connection = label("Remotes: checking", 13, COLORS.muted)
	refs.connection.Size = UDim2.new(1, 0, 0, 28)
	refs.connection.Parent = diag

	local account = label(("Player: %s (%d)"):format(player.Name, player.UserId), 12, COLORS.muted)
	account.Position = UDim2.new(0, 0, 0, 32)
	account.Size = UDim2.new(1, 0, 0, 24)
	account.Parent = diag

	local place = label(("PlaceId: %d"):format(game.PlaceId), 12, COLORS.muted)
	place.Position = UDim2.new(0, 0, 0, 56)
	place.Size = UDim2.new(1, 0, 0, 24)
	place.Parent = diag

	local reconnect = button("Reconnect remotes", COLORS.blue)
	reconnect.Position = UDim2.new(0, 0, 0, 92)
	reconnect.Size = UDim2.new(0.5, -5, 0, 38)
	reconnect.Parent = diag
	reconnect.MouseButton1Click:Connect(function()
		findRemotes()
		requestStatus()
		refreshUi()
	end)

	local hide = button("Hide panel", COLORS.panel2)
	hide.Position = UDim2.new(0.5, 5, 0, 92)
	hide.Size = UDim2.new(0.5, -5, 0, 38)
	hide.Parent = diag
	hide.MouseButton1Click:Connect(function()
		panel.Visible = false
	end)

	local note = card(toolsPage, 164, 90)
	local noteText = label("Fruit Collector, Seed Placer, Auto Sell, and Auto Buy Seeds require matching server remotes. Without them, the UI can save choices but cannot change gameplay.", 12, COLORS.muted)
	noteText.Size = UDim2.new(1, 0, 1, 0)
	noteText.Parent = note

	launcher.MouseButton1Click:Connect(function()
		panel.Visible = not panel.Visible
	end)
	close.MouseButton1Click:Connect(function()
		panel.Visible = false
	end)

	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then
			return
		end
		if input.KeyCode == Enum.KeyCode.RightShift then
			panel.Visible = not panel.Visible
		end
	end)

	screen.Parent = playerGui
	setTab(activeTab)
	refreshUi()

	panel.BackgroundTransparency = 1
	TweenService:Create(panel, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		BackgroundTransparency = 0,
	}):Play()
end

buildGui()
findRemotes()
requestStatus()
refreshUi()

task.spawn(function()
	while task.wait(2) do
		requestStatus()
		refreshUi()
	end
end)

print("[ScriptHub] Client loader started.")
