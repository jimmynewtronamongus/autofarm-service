-- Auto-exec performance mode.
-- Put this in auto execute. It runs automatically with no GUI and no saved config.

local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")
local SoundService = game:GetService("SoundService")

local localPlayer = Players.LocalPlayer

local performanceState = {
	optimized = setmetatable({}, { __mode = "k" }),
	hidden = setmetatable({}, { __mode = "k" }),
	watcherConnected = false,
	queue = {},
	queueHead = 1,
	queueRunning = false,
	fullScanDone = false,
	lastGardenHideAt = 0,
}

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
	if not instance or performanceState.optimized[instance] then
		return 0
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
		return 1
	end

	if instance:IsA("PostEffect")
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
		return 1
	end

	return 0
end

local function getGardens()
	local map = workspace:FindFirstChild("Map")
	if map then
		return map:FindFirstChild("Gardens") or map:FindFirstChild("Plots")
	end
	return workspace:FindFirstChild("Gardens") or workspace:FindFirstChild("Plots")
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

local function hidePerformanceVisual(instance)
	if not instance or performanceState.hidden[instance] then
		return 0
	end

	local changed = disableLaggyEffect(instance)
	if instance:IsA("ProximityPrompt") then
		return changed
	end

	if instance:IsA("BasePart") then
		performanceState.hidden[instance] = true
		pcall(function()
			instance.LocalTransparencyModifier = 1
			instance.CastShadow = false
		end)
		return changed + 1
	end

	if instance:IsA("Decal") or instance:IsA("Texture") then
		performanceState.hidden[instance] = true
		pcall(function()
			instance.Transparency = 1
		end)
		return changed + 1
	end

	if instance:IsA("BillboardGui")
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
		return changed + 1
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

	local changed = applyPerformanceGardenHiding(instance)
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
				instance.RenderFidelity = Enum.RenderFidelity.Performance
			end
		end)
		return changed + 1
	end

	if instance:IsA("Decal") or instance:IsA("Texture") then
		performanceState.optimized[instance] = true
		pcall(function()
			instance.Transparency = 1
		end)
		return changed + 1
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

	for _, descendant in ipairs(root:GetDescendants()) do
		changed = changed + optimizePerformanceInstance(descendant)
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
			optimizePerformanceInstance(descendant)
		end
	end)

	pcall(function()
		for _, descendant in ipairs(SoundService:GetDescendants()) do
			optimizePerformanceInstance(descendant)
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
		hidePerformanceGardens()
	end

	if not performanceState.fullScanDone then
		performanceState.fullScanDone = true
		optimizePerformanceTree(workspace, 220)
	end
end

task.spawn(function()
	for _, delaySeconds in ipairs({ 0, 1.5, 4, 8, 15 }) do
		if delaySeconds > 0 then
			task.wait(delaySeconds)
		end
		enablePerformanceMode()
	end
end)
