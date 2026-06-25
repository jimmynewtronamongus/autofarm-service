-- Auto-exec performance mode.
-- Put this in auto execute. It runs automatically with no GUI and no saved config.

local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local localPlayer = Players.LocalPlayer
local playerGui = localPlayer:WaitForChild("PlayerGui", 30)

local AGGRESSIVE_HIDE_WORKSPACE = true
local AUTO_SCAN_INTERVAL = 4

local debugState = {
	status = "Starting",
	lastReady = false,
	loadingGui = false,
	coreReady = false,
	gardenReady = false,
	scans = 0,
	optimized = 0,
	hidden = 0,
	plantsHidden = 0,
	texturesStripped = 0,
	effectsDisabled = 0,
	lastChanged = 0,
}

local performanceState = {
	optimized = setmetatable({}, { __mode = "k" }),
	hidden = setmetatable({}, { __mode = "k" }),
	watcherConnected = false,
	queue = {},
	queueHead = 1,
	queueRunning = false,
	fullScanDone = false,
	replicatedScanDone = false,
	lastGardenHideAt = 0,
}

local updateDebugGui = function() end

local function setDebugStatus(status)
	debugState.status = status
	updateDebugGui()
end

local function addDebugCount(key, amount)
	debugState[key] = (debugState[key] or 0) + (amount or 1)
end

local function isLaggyEffectInstance(instance)
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

local function disableLaggyEffect(instance)
	if not instance then
		return 0
	end

	if isLaggyEffectInstance(instance) then
		local firstPass = performanceState.optimized[instance] ~= true
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
		performanceState.optimized[instance] = true
		if firstPass then
			addDebugCount("effectsDisabled", 1)
			return 1
		end
		return 0
	end

	if instance:IsA("PostEffect")
		or instance:IsA("BloomEffect")
		or instance:IsA("BlurEffect")
		or instance:IsA("ColorCorrectionEffect")
		or instance:IsA("DepthOfFieldEffect")
		or instance:IsA("SunRaysEffect")
	then
		local firstPass = performanceState.optimized[instance] ~= true
		pcall(function()
			instance.Enabled = false
		end)
		performanceState.optimized[instance] = true
		if firstPass then
			addDebugCount("effectsDisabled", 1)
			return 1
		end
		return 0
	end

	return 0
end

local function stripTextureInstance(instance)
	if not instance then
		return 0
	end

	if instance:IsA("Decal") or instance:IsA("Texture") then
		pcall(function()
			instance.Transparency = 1
		end)
		addDebugCount("texturesStripped", 1)
		return 1
	end

	if instance:IsA("SurfaceAppearance") then
		pcall(function()
			instance:Destroy()
		end)
		addDebugCount("texturesStripped", 1)
		return 1
	end

	if instance:IsA("Sky") or instance:IsA("Clouds") then
		pcall(function()
			instance:Destroy()
		end)
		addDebugCount("texturesStripped", 1)
		return 1
	end

	if instance:IsA("SpecialMesh") then
		pcall(function()
			instance.TextureId = ""
		end)
		addDebugCount("texturesStripped", 1)
		return 1
	end

	if instance:IsA("MeshPart") then
		pcall(function()
			instance.TextureID = ""
		end)
		addDebugCount("texturesStripped", 1)
		return 1
	end

	return 0
end

local function isLocalCharacterDescendant(instance)
	local character = localPlayer.Character
	return character ~= nil and instance ~= nil and instance:IsDescendantOf(character)
end

local function getGardens()
	local map = workspace:FindFirstChild("Map")
	if map then
		return map:FindFirstChild("Gardens") or map:FindFirstChild("Plots")
	end
	return workspace:FindFirstChild("Gardens") or workspace:FindFirstChild("Plots")
end

local function hasVisibleLoadingGui()
	if not playerGui then
		return false
	end

	for _, descendant in ipairs(playerGui:GetDescendants()) do
		local name = string.lower(descendant.Name or "")
		if name == "loadinggui"
			or name == "loading screen"
			or name == "loadingscreen"
			or name == "countertxt"
			or name == "pressanytxt"
		then
			local visible = true
			pcall(function()
				visible = descendant.Visible ~= false
			end)
			if visible then
				return true
			end
		end
	end

	return false
end

local function hasGardenReady()
	local gardens = getGardens()
	if not gardens then
		return false
	end

	local plotCount = 0
	for _, plot in ipairs(gardens:GetChildren()) do
		if string.find(string.lower(plot.Name or ""), "plot", 1, true) then
			plotCount = plotCount + 1
			if plot:FindFirstChild("Plants") or plot:FindFirstChild("Signs") then
				return true
			end
		end
	end

	return plotCount >= 3
end

local function hasCoreGameReplicated()
	local stockValues = ReplicatedStorage:FindFirstChild("StockValues")
	local packetFolder = ReplicatedStorage:FindFirstChild("SharedModules")
	local map = workspace:FindFirstChild("Map")
	local gardens = getGardens()

	return stockValues ~= nil
		and packetFolder ~= nil
		and map ~= nil
		and gardens ~= nil
end

local function waitForGrowAGardenReady()
	local startedAt = os.clock()
	setDebugStatus("Waiting for Roblox load")

	if not game:IsLoaded() then
		game.Loaded:Wait()
	end

	setDebugStatus("Waiting for character")
	while not localPlayer.Character and os.clock() - startedAt < 90 do
		task.wait(0.25)
	end

	setDebugStatus("Waiting for GAG2 map")
	local stableChecks = 0
	while os.clock() - startedAt < 120 do
		debugState.coreReady = hasCoreGameReplicated()
		debugState.gardenReady = hasGardenReady()
		debugState.loadingGui = hasVisibleLoadingGui()
		updateDebugGui()

		if debugState.coreReady and debugState.gardenReady and not debugState.loadingGui then
			stableChecks = stableChecks + 1
			setDebugStatus(("Ready check %d/6"):format(stableChecks))
			if stableChecks >= 6 then
				task.wait(2)
				debugState.lastReady = true
				setDebugStatus("Loaded, optimizing")
				return true
			end
		else
			stableChecks = 0
			setDebugStatus("Waiting for full load")
		end

		task.wait(0.5)
	end

	setDebugStatus("Load wait timed out, optimizing anyway")
	return false
end

local function refreshDebugReadiness()
	debugState.coreReady = hasCoreGameReplicated()
	debugState.gardenReady = hasGardenReady()
	debugState.loadingGui = hasVisibleLoadingGui()
	updateDebugGui()
end

local function textMatchesLocalPlayer(text)
	text = tostring(text or "")
	return text == tostring(localPlayer.UserId) or string.lower(text) == string.lower(localPlayer.Name)
end

local function plotBelongsToLocalPlayer(plot)
	if not plot then
		return false
	end

	for _, descendant in ipairs(plot:GetDescendants()) do
		if descendant:IsA("ObjectValue") and descendant.Value == localPlayer then
			return true
		end

		if descendant:IsA("StringValue") or descendant:IsA("IntValue") or descendant:IsA("NumberValue") then
			if textMatchesLocalPlayer(descendant.Value) then
				return true
			end
		end

		if descendant:IsA("TextLabel") or descendant:IsA("TextButton") then
			if textMatchesLocalPlayer(descendant.Text) then
				return true
			end
		end
	end

	return false
end

local function gardenPlotIsOwn(plot)
	if plotBelongsToLocalPlayer(plot) then
		return true
	end

	local plants = plot and plot:FindFirstChild("Plants")
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

local function getGardenPlotForInstance(instance)
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

local function isOwnPlantVisual(instance, plot)
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

local plantFolderNames = {
	plants = true,
	plant = true,
	fruits = true,
	fruit = true,
	crops = true,
	crop = true,
	harvest = true,
	harvests = true,
}

local plantNameTerms = {
	"plant",
	"fruit",
	"crop",
	"tree",
	"bush",
	"flower",
	"harvest",
}

local function isPlantVisualInstance(instance)
	if not instance then
		return false
	end

	local current = instance
	while current and current ~= workspace do
		local name = string.lower(current.Name or "")
		if plantFolderNames[name] then
			return true
		end

		local parent = current.Parent
		local parentName = parent and string.lower(parent.Name or "") or ""
		if plantFolderNames[parentName] then
			return true
		end

		for _, term in ipairs(plantNameTerms) do
			if string.find(name, term, 1, true) then
				return true
			end
		end

		current = parent
	end

	return false
end

local function shouldAggressivelyHide(instance)
	if not AGGRESSIVE_HIDE_WORKSPACE or not instance or isLocalCharacterDescendant(instance) then
		return false
	end

	if not instance:IsDescendantOf(workspace) then
		return false
	end

	return instance:IsA("BasePart")
		or instance:IsA("Decal")
		or instance:IsA("Texture")
		or instance:IsA("SurfaceAppearance")
		or instance:IsA("SpecialMesh")
		or instance:IsA("BillboardGui")
		or instance:IsA("SurfaceGui")
		or instance:IsA("Highlight")
		or instance:IsA("SelectionBox")
		or instance:IsA("SelectionSphere")
		or instance:IsA("Handles")
		or instance:IsA("ArcHandles")
end

local function hidePerformanceVisual(instance)
	if not instance or isLocalCharacterDescendant(instance) then
		return 0
	end

	local changed = disableLaggyEffect(instance)
	if instance:IsA("ProximityPrompt") then
		return changed
	end

	if instance:IsA("BasePart") then
		local firstPass = performanceState.hidden[instance] ~= true
		pcall(function()
			if instance:IsA("MeshPart") then
				instance.TextureID = ""
			end
			instance.Material = Enum.Material.SmoothPlastic
			instance.Reflectance = 0
			instance.LocalTransparencyModifier = 1
			instance.CastShadow = false
		end)
		performanceState.hidden[instance] = true
		if firstPass then
			addDebugCount("hidden", 1)
			return changed + 1
		end
		return changed
	end

	if instance:IsA("Decal")
		or instance:IsA("Texture")
		or instance:IsA("SurfaceAppearance")
		or instance:IsA("SpecialMesh")
		or instance:IsA("Sky")
		or instance:IsA("Clouds")
	then
		local firstPass = performanceState.hidden[instance] ~= true
		changed = changed + stripTextureInstance(instance)
		performanceState.hidden[instance] = true
		return firstPass and changed or 0
	end

	if instance:IsA("BillboardGui")
		or instance:IsA("SurfaceGui")
		or instance:IsA("Highlight")
		or instance:IsA("SelectionBox")
		or instance:IsA("SelectionSphere")
		or instance:IsA("Handles")
		or instance:IsA("ArcHandles")
	then
		local firstPass = performanceState.hidden[instance] ~= true
		pcall(function()
			instance.Enabled = false
		end)
		performanceState.hidden[instance] = true
		return firstPass and (changed + 1) or changed
	end

	return changed
end

local function applyPerformanceGardenHiding(instance)
	local plot = getGardenPlotForInstance(instance)
	if not plot then
		return 0
	end

	if gardenPlotIsOwn(plot) then
		if isOwnPlantVisual(instance, plot) then
			return hidePerformanceVisual(instance)
		end
		return 0
	end

	return hidePerformanceVisual(instance)
end

local function hidePerformanceGardenPlot(plot)
	local changed = 0
	local ownPlot = gardenPlotIsOwn(plot)

	if ownPlot then
		for _, name in ipairs({ "Plants", "Fruits", "Fruit", "Crops", "Harvest", "Harvests" }) do
			local folder = plot:FindFirstChild(name, true)
			if folder then
				changed = changed + hidePerformanceVisual(folder)
				local processed = 0
				for _, descendant in ipairs(folder:GetDescendants()) do
					changed = changed + hidePerformanceVisual(descendant)
					processed = processed + 1
					if processed % 120 == 0 then
						task.wait()
					end
				end
			end
		end
		return changed
	end

	changed = changed + hidePerformanceVisual(plot)
	local processed = 0
	for _, descendant in ipairs(plot:GetDescendants()) do
		changed = changed + hidePerformanceVisual(descendant)
		processed = processed + 1
		if processed % 120 == 0 then
			task.wait()
		end
	end

	return changed
end

local function hidePerformanceGardens()
	local gardens = getGardens()
	if not gardens then
		return 0
	end

	local changed = 0
	for _, plot in ipairs(gardens:GetChildren()) do
		changed = changed + hidePerformanceGardenPlot(plot)
		task.wait()
	end
	return changed
end

local function optimizePerformanceInstance(instance)
	if not instance then
		return 0
	end
	if isLocalCharacterDescendant(instance) then
		return disableLaggyEffect(instance)
	end

	local changed = applyPerformanceGardenHiding(instance)
	if isPlantVisualInstance(instance) then
		local plantChanged = hidePerformanceVisual(instance)
		if plantChanged > 0 then
			addDebugCount("plantsHidden", plantChanged)
		end
		changed = changed + plantChanged
	end
	if shouldAggressivelyHide(instance) then
		changed = changed + hidePerformanceVisual(instance)
	end

	if performanceState.optimized[instance] then
		return changed
	end

	changed = changed + disableLaggyEffect(instance)
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
				instance.TextureID = ""
				instance.RenderFidelity = Enum.RenderFidelity.Performance
			end
		end)
		addDebugCount("optimized", 1)
		return changed + 1
	end

	if instance:IsA("Decal")
		or instance:IsA("Texture")
		or instance:IsA("SurfaceAppearance")
		or instance:IsA("SpecialMesh")
		or instance:IsA("Sky")
		or instance:IsA("Clouds")
	then
		performanceState.optimized[instance] = true
		return changed + stripTextureInstance(instance)
	end

	if instance:IsA("BillboardGui")
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
		return changed + 1
	end

	if instance:IsA("Animator") then
		performanceState.optimized[instance] = true
		pcall(function()
			for _, track in ipairs(instance:GetPlayingAnimationTracks()) do
				track:Stop(0)
			end
		end)
		return changed + 1
	end

	return changed
end

local function optimizePerformanceTree(root, budget)
	local changed = 0
	local processed = 0

	changed = changed + optimizePerformanceInstance(root)
	for _, descendant in ipairs(root:GetDescendants()) do
		changed = changed + optimizePerformanceInstance(descendant)
		processed = processed + 1
		if budget and processed % budget == 0 then
			task.wait()
		end
	end

	return changed
end

local function hideDetectedPlants(root, budget)
	local changed = 0
	local processed = 0

	for _, descendant in ipairs(root:GetDescendants()) do
		if isPlantVisualInstance(descendant) then
			local hidden = hidePerformanceVisual(descendant)
			changed = changed + hidden
			if hidden > 0 then
				addDebugCount("plantsHidden", hidden)
			end
		end

		processed = processed + 1
		if budget and processed % budget == 0 then
			task.wait()
		end
	end

	return changed
end

local function connectPerformanceWatcher()
	if performanceState.watcherConnected then
		return
	end

	performanceState.watcherConnected = true
	workspace.DescendantAdded:Connect(function(descendant)
		if #performanceState.queue - performanceState.queueHead < 800 then
			performanceState.queue[#performanceState.queue + 1] = descendant
		end

		if performanceState.queueRunning then
			return
		end

		performanceState.queueRunning = true
		task.spawn(function()
			while performanceState.queueHead <= #performanceState.queue do
				for _ = 1, 18 do
					local item = performanceState.queue[performanceState.queueHead]
					performanceState.queue[performanceState.queueHead] = nil
					performanceState.queueHead = performanceState.queueHead + 1
					if not item then
						break
					end
					optimizePerformanceInstance(item)
					if item.Parent then
						optimizePerformanceTree(item, 80)
					end
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

			performanceState.queue = {}
			performanceState.queueHead = 1
			performanceState.queueRunning = false
		end)
	end)
end

local function enablePerformanceMode()
	local now = os.clock()
	local changed = 0

	refreshDebugReadiness()
	setDebugStatus("Optimizing")

	connectPerformanceWatcher()

	pcall(function()
		settings().Rendering.QualityLevel = Enum.QualityLevel.Level01
	end)

	pcall(function()
		Lighting.GlobalShadows = false
		Lighting.EnvironmentDiffuseScale = 0
		Lighting.EnvironmentSpecularScale = 0
		Lighting.Brightness = math.min(Lighting.Brightness, 1)
		for _, descendant in ipairs(Lighting:GetDescendants()) do
			changed = changed + optimizePerformanceInstance(descendant)
		end
	end)

	pcall(function()
		for _, descendant in ipairs(SoundService:GetDescendants()) do
			changed = changed + optimizePerformanceInstance(descendant)
		end
	end)

	if not performanceState.replicatedScanDone then
		performanceState.replicatedScanDone = true
		changed = changed + optimizePerformanceTree(ReplicatedStorage, 320)
	end

	pcall(function()
		workspace.Terrain.WaterWaveSize = 0
		workspace.Terrain.WaterWaveSpeed = 0
		workspace.Terrain.WaterReflectance = 0
		workspace.Terrain.WaterTransparency = 1
		workspace.Terrain.Decoration = false
	end)

	if now - performanceState.lastGardenHideAt > 5 then
		performanceState.lastGardenHideAt = now
		changed = changed + hidePerformanceGardens()
		changed = changed + hideDetectedPlants(workspace, 220)
	end

	performanceState.fullScanDone = true
	changed = changed + optimizePerformanceTree(workspace, 260)

	debugState.scans = debugState.scans + 1
	debugState.lastChanged = changed
	setDebugStatus(("Optimized, changed %d"):format(changed))
end

local function make(parent, className, properties)
	local instance = Instance.new(className)
	for key, value in pairs(properties or {}) do
		instance[key] = value
	end
	instance.Parent = parent
	return instance
end

local function createDebugGui()
	if not playerGui then
		return
	end

	local old = playerGui:FindFirstChild("PerformanceDebugGui")
	if old then
		old:Destroy()
	end

	local gui = make(playerGui, "ScreenGui", {
		Name = "PerformanceDebugGui",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
	})

	local panel = make(gui, "Frame", {
		Name = "Panel",
		AnchorPoint = Vector2.new(1, 0),
		BackgroundColor3 = Color3.fromRGB(18, 21, 22),
		BorderSizePixel = 0,
		Position = UDim2.new(1, -10, 0, 74),
		Size = UDim2.fromOffset(210, 168),
	})
	make(panel, "UICorner", { CornerRadius = UDim.new(0, 7) })
	make(panel, "UIPadding", {
		PaddingTop = UDim.new(0, 7),
		PaddingBottom = UDim.new(0, 7),
		PaddingLeft = UDim.new(0, 7),
		PaddingRight = UDim.new(0, 7),
	})
	make(panel, "UIListLayout", {
		Padding = UDim.new(0, 4),
		SortOrder = Enum.SortOrder.LayoutOrder,
	})

	make(panel, "TextLabel", {
		Name = "Title",
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		Text = "Perf Debug",
		TextColor3 = Color3.fromRGB(239, 248, 240),
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, 0, 0, 16),
		LayoutOrder = 1,
	})

	local statusLabel = make(panel, "TextLabel", {
		Name = "Status",
		BackgroundTransparency = 1,
		Font = Enum.Font.Gotham,
		Text = "",
		TextColor3 = Color3.fromRGB(205, 221, 207),
		TextSize = 10,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, 0, 0, 38),
		LayoutOrder = 2,
	})

	local countersLabel = make(panel, "TextLabel", {
		Name = "Counters",
		BackgroundTransparency = 1,
		Font = Enum.Font.Code,
		Text = "",
		TextColor3 = Color3.fromRGB(187, 213, 190),
		TextSize = 10,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, 0, 0, 52),
		LayoutOrder = 3,
	})

	local buttons = make(panel, "Frame", {
		Name = "Buttons",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 24),
		LayoutOrder = 4,
	})
	make(buttons, "UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, 4),
		SortOrder = Enum.SortOrder.LayoutOrder,
	})

	local optimizeButton = make(buttons, "TextButton", {
		Name = "OptimizeNow",
		AutoButtonColor = false,
		BackgroundColor3 = Color3.fromRGB(48, 112, 63),
		BorderSizePixel = 0,
		Font = Enum.Font.GothamSemibold,
		Text = "Optimize",
		TextColor3 = Color3.fromRGB(245, 250, 245),
		TextSize = 10,
		Size = UDim2.new(0.5, -2, 1, 0),
	})
	make(optimizeButton, "UICorner", { CornerRadius = UDim.new(0, 5) })

	local plantsButton = make(buttons, "TextButton", {
		Name = "HidePlants",
		AutoButtonColor = false,
		BackgroundColor3 = Color3.fromRGB(58, 70, 78),
		BorderSizePixel = 0,
		Font = Enum.Font.GothamSemibold,
		Text = "Hide Plants",
		TextColor3 = Color3.fromRGB(245, 250, 245),
		TextSize = 10,
		Size = UDim2.new(0.5, -2, 1, 0),
	})
	make(plantsButton, "UICorner", { CornerRadius = UDim.new(0, 5) })

	updateDebugGui = function()
		if not statusLabel.Parent then
			return
		end

		statusLabel.Text = ("Status: %s\nCore:%s Garden:%s Loading:%s Ready:%s"):format(
			debugState.status,
			tostring(debugState.coreReady),
			tostring(debugState.gardenReady),
			tostring(debugState.loadingGui),
			tostring(debugState.lastReady)
		)

		countersLabel.Text = ("Scans:%d Last:%d\nOptimized:%d Hidden:%d\nPlants:%d Textures:%d Effects:%d"):format(
			debugState.scans,
			debugState.lastChanged,
			debugState.optimized,
			debugState.hidden,
			debugState.plantsHidden,
			debugState.texturesStripped,
			debugState.effectsDisabled
		)
	end

	optimizeButton.Activated:Connect(function()
		task.spawn(function()
			performanceState.fullScanDone = false
			enablePerformanceMode()
		end)
	end)

	plantsButton.Activated:Connect(function()
		task.spawn(function()
			setDebugStatus("Manual plant scan")
			local changed = hidePerformanceGardens() + hideDetectedPlants(workspace, 180)
			debugState.lastChanged = changed
			debugState.scans = debugState.scans + 1
			setDebugStatus(("Plant scan changed %d"):format(changed))
		end)
	end)

	updateDebugGui()
end

createDebugGui()

task.spawn(function()
	connectPerformanceWatcher()
	setDebugStatus("Auto potato mode")
	while true do
		enablePerformanceMode()
		task.wait(AUTO_SCAN_INTERVAL)
	end
end)
