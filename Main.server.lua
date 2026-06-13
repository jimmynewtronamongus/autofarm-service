-- Main.server.lua
-- Client-safe script hub loader for loadstring/executor-style environments.
-- This does not bypass server authority. Gameplay actions only work when the
-- place already has compatible DevScriptHubRemotes exposed by your own server.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
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

local refs = {}
local actionRemote = nil
local statusRemote = nil

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
		Thickness = thickness,
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

local function label(text, size, color)
	return create("TextLabel", {
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamMedium,
		Text = text,
		TextColor3 = color or Color3.fromRGB(226, 232, 240),
		TextSize = size or 13,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
		TextWrapped = true,
	})
end

local function button(text, color)
	return create("TextButton", {
		AutoButtonColor = true,
		BackgroundColor3 = color or Color3.fromRGB(38, 50, 68),
		BorderSizePixel = 0,
		Font = Enum.Font.GothamBold,
		Text = text,
		TextColor3 = Color3.fromRGB(248, 250, 252),
		TextSize = 13,
		TextWrapped = true,
	}, {
		corner(8),
		stroke(Color3.fromRGB(87, 100, 125), 1, 0.3),
	})
end

local function field(text)
	return create("TextBox", {
		BackgroundColor3 = Color3.fromRGB(15, 23, 42),
		BorderSizePixel = 0,
		ClearTextOnFocus = false,
		Font = Enum.Font.GothamMedium,
		PlaceholderColor3 = Color3.fromRGB(148, 163, 184),
		Text = text,
		TextColor3 = Color3.fromRGB(248, 250, 252),
		TextSize = 13,
		TextWrapped = true,
	}, {
		corner(8),
		stroke(Color3.fromRGB(71, 85, 105), 1, 0.2),
		padding(10, 0, 10, 0),
	})
end

local function findRemotes()
	local folder = ReplicatedStorage:FindFirstChild(REMOTE_FOLDER_NAME)
	if not folder then
		actionRemote = nil
		statusRemote = nil
		return false
	end

	local foundAction = folder:FindFirstChild(ACTION_REMOTE_NAME)
	local foundStatus = folder:FindFirstChild(STATUS_REMOTE_NAME)
	if foundAction and foundAction:IsA("RemoteEvent") then
		actionRemote = foundAction
	end
	if foundStatus and foundStatus:IsA("RemoteFunction") then
		statusRemote = foundStatus
	end

	return actionRemote ~= nil or statusRemote ~= nil
end

local function formatEnabled(value)
	return value and "ON" or "OFF"
end

local function setButtonState(buttonRef, enabled)
	buttonRef.Text = buttonRef:GetAttribute("Label") .. ": " .. formatEnabled(enabled)
	buttonRef.BackgroundColor3 = enabled and Color3.fromRGB(22, 101, 52) or Color3.fromRGB(38, 50, 68)
end

local function updateStatus(nextState)
	if typeof(nextState) == "table" then
		for key, value in pairs(nextState) do
			state[key] = value
		end
	end

	if refs.masterToggle then
		setButtonState(refs.masterToggle, state.enabled)
		setButtonState(refs.buyToggle, state.autoBuy)
		setButtonState(refs.plantToggle, state.autoPlant)
		setButtonState(refs.harvestToggle, state.autoHarvest)
		setButtonState(refs.sellToggle, state.autoSell)
		refs.seedBox.Text = state.seedName or ""
		refs.amountBox.Text = tostring(state.buyAmount or 1)
		refs.radiusBox.Text = tostring(state.harvestRadius or 250)
		refs.status.Text = "Status: " .. tostring(state.lastResult or "idle")
		refs.counters.Text = ("Bought %d  Planted %d  Harvested %d  Sold %d"):format(
			tonumber(state.totalBought) or 0,
			tonumber(state.totalPlanted) or 0,
			tonumber(state.totalHarvested) or 0,
			tonumber(state.totalSold) or 0
		)
	end
end

local function requestStatus()
	findRemotes()
	if not statusRemote then
		state.lastResult = "server hub not found"
		updateStatus()
		return
	end

	local ok, success, result = pcall(function()
		return statusRemote:InvokeServer()
	end)

	if not ok then
		state.lastResult = "server did not answer"
		updateStatus()
	elseif success then
		updateStatus(result)
	else
		state.lastResult = tostring(result)
		updateStatus()
	end
end

local function send(actionName, payload)
	findRemotes()
	if not actionRemote then
		state.lastResult = "server hub not found"
		updateStatus()
		return
	end

	actionRemote:FireServer(actionName, payload or {})
end

local function makeToggle(parent, text, stateKey, modeName)
	local item = button(text .. ": OFF")
	item:SetAttribute("Label", text)
	item.Size = UDim2.new(1, 0, 0, 38)
	item.Parent = parent
	item.MouseButton1Click:Connect(function()
		send("setMode", {
			mode = modeName,
			enabled = not state[stateKey],
		})
	end)
	return item
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

	local launcher = button("Hub", Color3.fromRGB(20, 83, 45))
	launcher.Name = "Launcher"
	launcher.Position = UDim2.new(0, 18, 0.5, -22)
	launcher.Size = UDim2.new(0, 72, 0, 44)
	launcher.Parent = screen

	local panel = create("Frame", {
		Name = "Panel",
		AnchorPoint = Vector2.new(0, 0.5),
		BackgroundColor3 = Color3.fromRGB(8, 13, 24),
		BorderSizePixel = 0,
		Position = UDim2.new(0, 104, 0.5, 0),
		Size = UDim2.new(0, 360, 0, 482),
		Visible = true,
	}, {
		corner(10),
		stroke(Color3.fromRGB(71, 85, 105), 1, 0.1),
		padding(14, 14, 14, 14),
	})
	panel.Parent = screen

	local title = label("Grow a Garden 2 Script Hub", 16, Color3.fromRGB(250, 250, 250))
	title.Font = Enum.Font.GothamBold
	title.Size = UDim2.new(1, -46, 0, 28)
	title.Parent = panel

	local close = button("X", Color3.fromRGB(69, 26, 26))
	close.Position = UDim2.new(1, -36, 0, 0)
	close.Size = UDim2.new(0, 36, 0, 30)
	close.Parent = panel

	refs.status = label("Status: loading", 12, Color3.fromRGB(203, 213, 225))
	refs.status.Position = UDim2.new(0, 0, 0, 34)
	refs.status.Size = UDim2.new(1, 0, 0, 22)
	refs.status.Parent = panel

	refs.counters = label("Bought 0  Planted 0  Harvested 0  Sold 0", 12, Color3.fromRGB(148, 163, 184))
	refs.counters.Position = UDim2.new(0, 0, 0, 58)
	refs.counters.Size = UDim2.new(1, 0, 0, 34)
	refs.counters.Parent = panel

	refs.masterToggle = button("Auto Farm: OFF", Color3.fromRGB(38, 50, 68))
	refs.masterToggle:SetAttribute("Label", "Auto Farm")
	refs.masterToggle.Position = UDim2.new(0, 0, 0, 102)
	refs.masterToggle.Size = UDim2.new(1, 0, 0, 42)
	refs.masterToggle.Parent = panel
	refs.masterToggle.MouseButton1Click:Connect(function()
		send("setEnabled", {
			enabled = not state.enabled,
		})
	end)

	local grid = create("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 0, 0, 156),
		Size = UDim2.new(1, 0, 0, 86),
	}, {
		create("UIGridLayout", {
			CellPadding = UDim2.new(0, 8, 0, 8),
			CellSize = UDim2.new(0.5, -4, 0, 38),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})
	grid.Parent = panel

	refs.buyToggle = makeToggle(grid, "Buy", "autoBuy", "autoBuy")
	refs.plantToggle = makeToggle(grid, "Plant", "autoPlant", "autoPlant")
	refs.harvestToggle = makeToggle(grid, "Harvest", "autoHarvest", "autoHarvest")
	refs.sellToggle = makeToggle(grid, "Sell", "autoSell", "autoSell")

	local form = create("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 0, 0, 256),
		Size = UDim2.new(1, 0, 0, 122),
	}, {
		create("UIListLayout", {
			Padding = UDim.new(0, 8),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})
	form.Parent = panel

	local function row(rowLabel, boxRef, applyText, applyAction)
		local item = create("Frame", {
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, 34),
		})
		local text = label(rowLabel, 12, Color3.fromRGB(203, 213, 225))
		text.Size = UDim2.new(0, 92, 1, 0)
		text.Parent = item

		local input = field("")
		input.Position = UDim2.new(0, 98, 0, 0)
		input.Size = UDim2.new(1, -174, 1, 0)
		input.Parent = item

		local apply = button(applyText, Color3.fromRGB(30, 64, 175))
		apply.Position = UDim2.new(1, -68, 0, 0)
		apply.Size = UDim2.new(0, 68, 1, 0)
		apply.Parent = item
		apply.MouseButton1Click:Connect(function()
			applyAction(input.Text)
		end)

		item.Parent = form
		refs[boxRef] = input
	end

	row("Seed", "seedBox", "Set", function(text)
		send("setSeed", {
			seedName = text,
		})
	end)

	row("Buy amount", "amountBox", "Set", function(text)
		send("setBuyAmount", {
			amount = tonumber(text),
		})
	end)

	row("Radius", "radiusBox", "Set", function(text)
		send("setHarvestRadius", {
			radius = tonumber(text),
		})
	end)

	local quickSeeds = create("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 0, 0, 388),
		Size = UDim2.new(1, 0, 0, 38),
	}, {
		create("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			Padding = UDim.new(0, 8),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})
	quickSeeds.Parent = panel

	local seedIndex = 1
	local previousSeed = button("<", Color3.fromRGB(51, 65, 85))
	previousSeed.Size = UDim2.new(0, 42, 1, 0)
	previousSeed.Parent = quickSeeds

	local nextSeed = button("Next seed", Color3.fromRGB(51, 65, 85))
	nextSeed.Size = UDim2.new(1, -100, 1, 0)
	nextSeed.Parent = quickSeeds

	local nextArrow = button(">", Color3.fromRGB(51, 65, 85))
	nextArrow.Size = UDim2.new(0, 42, 1, 0)
	nextArrow.Parent = quickSeeds

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

	previousSeed.MouseButton1Click:Connect(function()
		chooseSeed(-1)
	end)
	nextSeed.MouseButton1Click:Connect(function()
		chooseSeed(1)
	end)
	nextArrow.MouseButton1Click:Connect(function()
		chooseSeed(1)
	end)

	local actions = create("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 0, 1, -42),
		Size = UDim2.new(1, 0, 0, 42),
	}, {
		create("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			Padding = UDim.new(0, 8),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})
	actions.Parent = panel

	local step = button("Run once", Color3.fromRGB(30, 64, 175))
	step.Size = UDim2.new(0.5, -4, 1, 0)
	step.Parent = actions
	step.MouseButton1Click:Connect(function()
		send("stepOnce")
	end)

	local stop = button("Stop all", Color3.fromRGB(127, 29, 29))
	stop.Size = UDim2.new(0.5, -4, 1, 0)
	stop.Parent = actions
	stop.MouseButton1Click:Connect(function()
		send("stopAll")
	end)

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
end

buildGui()
requestStatus()

if actionRemote then
	actionRemote.OnClientEvent:Connect(function(success, result)
		if success then
			updateStatus(result)
		else
			state.lastResult = tostring(result)
			updateStatus()
		end
	end)
end

task.spawn(function()
	while task.wait(2) do
		requestStatus()
	end
end)

print("[ScriptHub] Client loader started.")
