-- GAG2 potato mode.
-- Auto-exec friendly: runs immediately, keeps rescanning, no buttons required.

local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local Workspace = game:GetService("Workspace")

local localPlayer = Players.LocalPlayer
local playerGui = localPlayer:WaitForChild("PlayerGui", 30)

local SCAN_DELAY = 2.5
local PET_SCAN_DELAY = 0.75
local BATCH_SIZE = 450
local HIDE_PLAYER_CHARACTER = false

local stats = {
	status = "Starting",
	scans = 0,
	lastChanged = 0,
	parts = 0,
	textures = 0,
	effects = 0,
	pets = 0,
	sounds = 0,
	lighting = 0,
}

local statusLabel
local statsLabel

local function isOwnCharacter(instance)
	local character = localPlayer.Character
	return character ~= nil and instance ~= nil and instance:IsDescendantOf(character)
end

local function safeSet(callback)
	local ok = pcall(callback)
	return ok and 1 or 0
end

local function updateGui()
	if not statusLabel or not statusLabel.Parent then
		return
	end

	statusLabel.Text = ("Status: %s\nScans: %d  Last: %d"):format(stats.status, stats.scans, stats.lastChanged)
	statsLabel.Text = ("Parts:%d Textures:%d\nEffects:%d Sounds:%d\nPets:%d Lighting:%d"):format(
		stats.parts,
		stats.textures,
		stats.effects,
		stats.sounds,
		stats.pets,
		stats.lighting
	)
end

local function setStatus(text)
	stats.status = text
	updateGui()
end

local function addStat(name, amount)
	stats[name] = (stats[name] or 0) + (amount or 1)
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

	local old = playerGui:FindFirstChild("GAG2PotatoDebug")
	if old then
		old:Destroy()
	end

	local gui = make(playerGui, "ScreenGui", {
		Name = "GAG2PotatoDebug",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 999999,
	})

	local panel = make(gui, "Frame", {
		Name = "Panel",
		AnchorPoint = Vector2.new(1, 0),
		BackgroundColor3 = Color3.fromRGB(12, 14, 15),
		BorderSizePixel = 0,
		Position = UDim2.new(1, -8, 0, 72),
		Size = UDim2.fromOffset(190, 112),
	})
	make(panel, "UICorner", { CornerRadius = UDim.new(0, 6) })
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
		Text = "GAG2 Potato",
		TextColor3 = Color3.fromRGB(242, 248, 242),
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, 0, 0, 16),
		LayoutOrder = 1,
	})

	statusLabel = make(panel, "TextLabel", {
		Name = "Status",
		BackgroundTransparency = 1,
		Font = Enum.Font.Gotham,
		Text = "",
		TextColor3 = Color3.fromRGB(204, 224, 205),
		TextSize = 10,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, 0, 0, 28),
		LayoutOrder = 2,
	})

	statsLabel = make(panel, "TextLabel", {
		Name = "Stats",
		BackgroundTransparency = 1,
		Font = Enum.Font.Code,
		Text = "",
		TextColor3 = Color3.fromRGB(178, 211, 181),
		TextSize = 10,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, 0, 0, 42),
		LayoutOrder = 3,
	})

	updateGui()
end

local function killEffect(instance)
	if instance:IsA("ParticleEmitter")
		or instance:IsA("Trail")
		or instance:IsA("Beam")
		or instance:IsA("Smoke")
		or instance:IsA("Fire")
		or instance:IsA("Sparkles")
		or instance:IsA("PointLight")
		or instance:IsA("SpotLight")
		or instance:IsA("SurfaceLight")
		or instance:IsA("Highlight")
	then
		local changed = safeSet(function()
			instance.Enabled = false
		end)
		changed = changed + safeSet(function()
			instance.Rate = 0
		end)
		changed = changed + safeSet(function()
			instance.Brightness = 0
		end)
		addStat("effects", changed)
		return changed
	end

	if instance:IsA("Explosion") then
		local changed = safeSet(function()
			instance.BlastPressure = 0
			instance.BlastRadius = 0
		end)
		addStat("effects", changed)
		return changed
	end

	if instance:IsA("PostEffect")
		or instance:IsA("BloomEffect")
		or instance:IsA("BlurEffect")
		or instance:IsA("ColorCorrectionEffect")
		or instance:IsA("DepthOfFieldEffect")
		or instance:IsA("SunRaysEffect")
	then
		local changed = safeSet(function()
			instance.Enabled = false
		end)
		addStat("effects", changed)
		return changed
	end

	return 0
end

local function killSound(instance)
	if not instance:IsA("Sound") then
		return 0
	end

	local changed = safeSet(function()
		instance.Volume = 0
		instance.Playing = false
		instance.Looped = false
	end)
	addStat("sounds", changed)
	return changed
end

local function killTexture(instance)
	local changed = 0

	if instance:IsA("Decal") or instance:IsA("Texture") then
		changed = changed + safeSet(function()
			instance.Transparency = 1
		end)
	elseif instance:IsA("SurfaceAppearance") then
		changed = changed + safeSet(function()
			instance:Destroy()
		end)
	elseif instance:IsA("SpecialMesh") then
		changed = changed + safeSet(function()
			instance.TextureId = ""
		end)
	elseif instance:IsA("MeshPart") then
		changed = changed + safeSet(function()
			instance.TextureID = ""
		end)
	elseif instance:IsA("Sky") or instance:IsA("Clouds") then
		changed = changed + safeSet(function()
			instance:Destroy()
		end)
	end

	if changed > 0 then
		addStat("textures", changed)
	end
	return changed
end

local function hidePart(instance)
	if not instance:IsA("BasePart") then
		return 0
	end

	if not HIDE_PLAYER_CHARACTER and isOwnCharacter(instance) then
		return 0
	end

	local changed = safeSet(function()
		instance.LocalTransparencyModifier = 1
		instance.Transparency = 1
		instance.Material = Enum.Material.SmoothPlastic
		instance.Reflectance = 0
		instance.CastShadow = false
	end)

	if instance:IsA("MeshPart") then
		changed = changed + killTexture(instance)
	end

	if changed > 0 then
		addStat("parts", changed)
	end
	return changed
end

local optimizeService

local function isGuiInstance(instance)
	return instance:IsA("GuiObject")
		or instance:IsA("LayerCollector")
		or instance:IsA("BillboardGui")
		or instance:IsA("SurfaceGui")
		or instance:IsA("UIComponent")
		or instance:IsA("UILayout")
end

local function optimizeInstance(instance)
	if not instance then
		return 0
	end

	if isGuiInstance(instance) then
		return 0
	end

	local changed = 0
	changed = changed + killEffect(instance)
	changed = changed + killSound(instance)
	changed = changed + killTexture(instance)
	changed = changed + hidePart(instance)
	return changed
end

local function isPetVisualRoot(instance)
	if not instance then
		return false
	end

	local name = string.lower(instance.Name or "")
	local parent = instance.Parent
	local parentName = parent and string.lower(parent.Name or "") or ""

	return string.find(name, "wildpet", 1, true) ~= nil
		or string.find(name, "pet", 1, true) ~= nil
		or string.find(parentName, "wildpet", 1, true) ~= nil
		or string.find(parentName, "pet", 1, true) ~= nil
end

local function optimizePetVisuals()
	local changed = 0
	local map = Workspace:FindFirstChild("Map")
	local wildPetSpawns = map and map:FindFirstChild("WildPetSpawns")

	if wildPetSpawns then
		changed = changed + optimizeService(wildPetSpawns, 120)
	end

	for _, descendant in ipairs(Workspace:GetDescendants()) do
		if isPetVisualRoot(descendant) then
			changed = changed + optimizeInstance(descendant)
			for _, child in ipairs(descendant:GetDescendants()) do
				changed = changed + optimizeInstance(child)
			end
		end
	end

	if changed > 0 then
		addStat("pets", changed)
	end
	return changed
end

optimizeService = function(root, batchSize)
	local changed = optimizeInstance(root)
	local processed = 0

	for _, descendant in ipairs(root:GetDescendants()) do
		changed = changed + optimizeInstance(descendant)
		processed = processed + 1
		if processed % batchSize == 0 then
			task.wait()
		end
	end

	return changed
end

local function optimizeLighting()
	local changed = 0

	changed = changed + safeSet(function()
		settings().Rendering.QualityLevel = Enum.QualityLevel.Level01
	end)

	changed = changed + safeSet(function()
		Lighting.GlobalShadows = false
		Lighting.EnvironmentDiffuseScale = 0
		Lighting.EnvironmentSpecularScale = 0
		Lighting.Brightness = 0
		Lighting.ClockTime = 12
		Lighting.FogEnd = 1000000
		Lighting.ExposureCompensation = 0
	end)

	changed = changed + safeSet(function()
		Workspace.Terrain.WaterWaveSize = 0
		Workspace.Terrain.WaterWaveSpeed = 0
		Workspace.Terrain.WaterReflectance = 0
		Workspace.Terrain.WaterTransparency = 1
		Workspace.Terrain.Decoration = false
	end)

	addStat("lighting", changed)
	return changed
end

local queued = {}
local queueRunning = false

local function drainQueue()
	if queueRunning then
		return
	end

	queueRunning = true
	task.spawn(function()
		while #queued > 0 do
			setStatus(("Queue %d"):format(#queued))
			for _ = 1, 80 do
				local instance = table.remove(queued)
				if not instance then
					break
				end
				optimizeInstance(instance)
				if isPetVisualRoot(instance) then
					addStat("pets", optimizeService(instance, 120))
				end
				for _, descendant in ipairs(instance:GetDescendants()) do
					optimizeInstance(descendant)
				end
			end
			task.wait()
		end
		queueRunning = false
	end)
end

local function watch(root)
	root.DescendantAdded:Connect(function(instance)
		queued[#queued + 1] = instance
		drainQueue()
	end)
end

local function scanEverything()
	setStatus("Scanning")
	local changed = 0

	changed = changed + optimizeLighting()
	changed = changed + optimizeService(Lighting, BATCH_SIZE)
	changed = changed + optimizeService(SoundService, BATCH_SIZE)
	changed = changed + optimizeService(Workspace, BATCH_SIZE)
	changed = changed + optimizePetVisuals()
	changed = changed + optimizeService(ReplicatedStorage, BATCH_SIZE)

	stats.scans = stats.scans + 1
	stats.lastChanged = changed
	setStatus(("Potato applied: %d"):format(changed))
	updateGui()
end

createDebugGui()
setStatus("Running")

watch(Workspace)
watch(Lighting)
watch(SoundService)
watch(ReplicatedStorage)

task.spawn(function()
	while true do
		scanEverything()
		task.wait(SCAN_DELAY)
	end
end)

task.spawn(function()
	while true do
		local changed = optimizePetVisuals()
		if changed > 0 then
			stats.lastChanged = changed
			setStatus(("Pets optimized: %d"):format(changed))
		end
		task.wait(PET_SCAN_DELAY)
	end
end)
