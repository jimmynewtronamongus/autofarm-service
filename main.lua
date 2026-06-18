-- Garden automation GUI for private testing in a Grow-a-Garden-style place.
-- Drop this LocalScript in StarterPlayerScripts, or run it from a local test client.

Players = game:GetService("Players")
CollectionService = game:GetService("CollectionService")
HttpService = game:GetService("HttpService")
ReplicatedStorage = game:GetService("ReplicatedStorage")
RunService = game:GetService("RunService")
StarterGui = game:GetService("StarterGui")
UserInputService = game:GetService("UserInputService")
PathfindingService = game:GetService("PathfindingService")

localPlayer = Players.LocalPlayer
playerGui = localPlayer:WaitForChild("PlayerGui")

CONFIG = {
	collectInterval = 0.15,
	sellInterval = 5.0,
	sellWhenFullInterval = 0.75,
	schedulerInterval = 0.1,
	maxSellAttempts = 2,
	sellCooldown = 1.0,
	sellResumeFreeSlots = 8,
	buyInterval = 1.5,
	mailInterval = 6.0,
	petSellInterval = 5.0,
	petBuyInterval = 0.6,
	petWalkDistance = 10.5,
	petWalkTimeout = 4.5,
	petPathRefreshInterval = 0.35,
	petPathTargetMoveThreshold = 4.0,
	stockWebhookCooldown = 10.0,
	cacheRefreshInterval = 25.0,
	inventoryRefreshInterval = 1.0,
	guiInventoryRefreshInterval = 30.0,
	maxFruitCollectPerTick = 30,
	maxFruitScanPerRoot = 900,
	fruitCacheRefreshInterval = 0.65,
	maxFruitTargetsCached = 500,
	maxFruitPromptFallbackPerTick = 24,
	deepPacketDiscovery = false,
	packetDiscoveryCooldown = 60.0,
	packetDiscoveryLimit = 1200,
	maxSeedBuyPerTick = 3,
	seedBuyRemoteRepeats = 4,
	maxGearBuyPerTick = 3,
	gearBuyRemoteRepeats = 4,
	maxInventoryItems = 100,
	movePlantPosition = nil,
	petSellMutationFilter = "",
	petSellVariantFilter = "",
	petSellExcludeVariantFilter = "",
	keepAllPetVariants = true,
	webhookUrl = "",
	officialStockWebhookUrl = "",
	predictorWebhookUrl = "",
	statsWebhookInterval = 180.0,
	stockPredictorLeadSeconds = 30,
	maxPetBuyPerTick = 1,
}

seedNames = {}

seedPriority = {}

state = {
	fruitCollector = false,
	autoSell = false,
	sellWhenFull = true,
	autoBuySeeds = false,
	autoBuyGear = false,
	autoMovePlants = false,
	autoAcceptMail = false,
	autoBuyPets = false,
	autoSellPets = false,
	performanceMode = false,
	hideGameButtons = false,
	hidePlotIcons = false,
	hideOwnPlants = false,
	lastStatus = "Ready",
}

selectedSeeds = {}

selectedMoveSeeds = {}

gearNames = {}

selectedGears = {}

petNames = {}

buyPetNames = {}

selectedPets = {}
selectedSellPets = {}
stockPredictionHistory = {}
stockPredictionShops = {}

plantPromptTextCache = setmetatable({}, { __mode = "k" })
harvestPromptCache = setmetatable({}, { __mode = "k" })
handledPetSpawns = setmetatable({}, { __mode = "k" })

saveConfig = function() end
setStatus = function() end

CONFIG_FOLDER = "GardenTools"
CONFIG_FILE = CONFIG_FOLDER .. "/config.json"

function canUseFileConfig()
	return typeof(readfile) == "function"
		and typeof(writefile) == "function"
		and typeof(isfile) == "function"
end

function copyMap(source)
	local target = {}
	if type(source) ~= "table" then
		return target
	end

	for key, value in pairs(source) do
		if type(key) == "string" and value == true then
			target[key] = true
		end
	end

	return target
end

function copyKnownValues(source, destination, keys)
	if type(source) ~= "table" then
		return
	end

	for _, key in ipairs(keys) do
		if source[key] ~= nil then
			destination[key] = source[key]
		end
	end
end

function loadConfig()
	if not canUseFileConfig() then
		return false
	end

	local existsOk, exists = pcall(isfile, CONFIG_FILE)
	if not existsOk or not exists then
		return false
	end

	local ok, decoded = pcall(function()
		return HttpService:JSONDecode(readfile(CONFIG_FILE))
	end)
	if not ok or type(decoded) ~= "table" then
		return false
	end

	copyKnownValues(decoded.config, CONFIG, {
		"sellInterval",
		"sellWhenFullInterval",
		"sellResumeFreeSlots",
		"buyInterval",
		"mailInterval",
		"petSellInterval",
		"movePlantPosition",
		"petSellMutationFilter",
		"petSellVariantFilter",
		"petSellExcludeVariantFilter",
		"keepAllPetVariants",
		"webhookUrl",
		"officialStockWebhookUrl",
		"predictorWebhookUrl",
		"statsWebhookInterval",
		"stockWebhookCooldown",
		"stockPredictorLeadSeconds",
	})
	copyKnownValues(decoded.state, state, {
		"fruitCollector",
		"autoSell",
		"sellWhenFull",
		"autoBuySeeds",
		"autoBuyGear",
		"autoMovePlants",
		"autoAcceptMail",
		"autoBuyPets",
		"autoSellPets",
		"performanceMode",
		"hideGameButtons",
		"hidePlotIcons",
		"hideOwnPlants",
	})
	if decoded.state and decoded.state.hidePlants == true then
		state.performanceMode = true
	end

	selectedSeeds = copyMap(decoded.selectedSeeds)
	selectedMoveSeeds = copyMap(decoded.selectedMoveSeeds)
	selectedGears = copyMap(decoded.selectedGears)
	selectedPets = copyMap(decoded.selectedPets)
	selectedSellPets = copyMap(decoded.selectedSellPets)
	if decoded.stockPredictionVersion == 2 and type(decoded.stockPredictionHistory) == "table" then
		stockPredictionHistory = decoded.stockPredictionHistory
	end
	if decoded.stockPredictionVersion == 2 and type(decoded.stockPredictionShops) == "table" then
		stockPredictionShops = decoded.stockPredictionShops
	elseif type(decoded.stockPredictionShops) == "table" and decoded.stockPredictionShops.webhookMessageId then
		stockPredictionShops.webhookMessageId = decoded.stockPredictionShops.webhookMessageId
	end

	return true
end

saveConfig = function()
	if not canUseFileConfig() then
		return false
	end

	if typeof(isfolder) == "function" and typeof(makefolder) == "function" and not isfolder(CONFIG_FOLDER) then
		pcall(makefolder, CONFIG_FOLDER)
	elseif typeof(makefolder) == "function" then
		pcall(makefolder, CONFIG_FOLDER)
	end

	local payload = {
		version = 1,
		config = {
			sellInterval = CONFIG.sellInterval,
			sellWhenFullInterval = CONFIG.sellWhenFullInterval,
			sellResumeFreeSlots = CONFIG.sellResumeFreeSlots,
			buyInterval = CONFIG.buyInterval,
			mailInterval = CONFIG.mailInterval,
			petSellInterval = CONFIG.petSellInterval,
			movePlantPosition = CONFIG.movePlantPosition,
			petSellMutationFilter = CONFIG.petSellMutationFilter,
			petSellVariantFilter = CONFIG.petSellVariantFilter,
			petSellExcludeVariantFilter = CONFIG.petSellExcludeVariantFilter,
			keepAllPetVariants = CONFIG.keepAllPetVariants,
			webhookUrl = CONFIG.webhookUrl,
			officialStockWebhookUrl = CONFIG.officialStockWebhookUrl,
			predictorWebhookUrl = CONFIG.predictorWebhookUrl,
			statsWebhookInterval = CONFIG.statsWebhookInterval,
			stockWebhookCooldown = CONFIG.stockWebhookCooldown,
			stockPredictorLeadSeconds = CONFIG.stockPredictorLeadSeconds,
		},
		state = {
			fruitCollector = state.fruitCollector,
			autoSell = state.autoSell,
			sellWhenFull = state.sellWhenFull,
			autoBuySeeds = state.autoBuySeeds,
			autoBuyGear = state.autoBuyGear,
			autoMovePlants = state.autoMovePlants,
			autoAcceptMail = state.autoAcceptMail,
			autoBuyPets = state.autoBuyPets,
			autoSellPets = state.autoSellPets,
			performanceMode = state.performanceMode,
			hideGameButtons = state.hideGameButtons,
			hidePlotIcons = state.hidePlotIcons,
			hideOwnPlants = state.hideOwnPlants,
		},
		selectedSeeds = selectedSeeds,
		selectedMoveSeeds = selectedMoveSeeds,
		selectedGears = selectedGears,
		selectedPets = selectedPets,
		selectedSellPets = selectedSellPets,
		stockPredictionVersion = 2,
		stockPredictionHistory = stockPredictionHistory,
		stockPredictionShops = stockPredictionShops,
	}

	local ok, encoded = pcall(function()
		return HttpService:JSONEncode(payload)
	end)
	if not ok then
		return false
	end

	return pcall(writefile, CONFIG_FILE, encoded)
end

local configLoaded = loadConfig()

local webhookSentAt = {}
local stockLastAmounts = {}
local stockPredictionSeenAt = {}
local stockWebhookQueue = {}
local stockWebhookScheduled = false
local activityWebhookQueue = {}
local activityWebhookScheduled = false
local predictorWebhookUpdateScheduled = false
local getStockItemsFolder
local getShopStockAmount
local getShopPriceAmount

function getRequestFunction()
	return (syn and syn.request)
		or (http and http.request)
		or http_request
		or request
end

function sendWebhookEmbeds(embeds, key, targetUrl, username)
	local url = targetUrl or CONFIG.webhookUrl
	if url == "" or type(embeds) ~= "table" or #embeds == 0 then
		return false
	end

	local now = os.clock()
	local throttleKey = key and ((targetUrl and targetUrl ~= CONFIG.webhookUrl) and (key .. ":secondary") or key)
	if throttleKey and webhookSentAt[throttleKey] and now - webhookSentAt[throttleKey] < 45 then
		return false
	end

	local requestFunction = getRequestFunction()
	if type(requestFunction) ~= "function" then
		setStatus("Webhook: request function unavailable")
		return false
	end

	local payload = {
		username = username or "Garden Tools",
		embeds = embeds,
	}

	local ok, response = pcall(function()
		return requestFunction({
			Url = url,
			Method = "POST",
			Headers = {
				["Content-Type"] = "application/json",
			},
			Body = HttpService:JSONEncode(payload),
		})
	end)

	local statusCode = 200
	if ok and type(response) == "table" then
		statusCode = tonumber(response.StatusCode or response.Status or response.status_code) or statusCode
	end
	local sent = ok and statusCode >= 200 and statusCode < 300

	if sent and throttleKey then
		webhookSentAt[throttleKey] = now
	elseif not sent then
		setStatus(("Webhook failed%s"):format(ok and (" (" .. tostring(statusCode) .. ")") or ""))
	end

	return sent
end

function sendWebhook(title, description, key, targetUrl)
	return sendWebhookEmbeds({
		{
			title = title,
			description = description,
			color = 65280,
			timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ"),
		},
	}, key, targetUrl)
end

function requestPredictorWebhookMessage(embeds)
	if not canSendPredictorWebhook() or type(embeds) ~= "table" or #embeds == 0 then
		return false
	end

	local requestFunction = getRequestFunction()
	if type(requestFunction) ~= "function" then
		setStatus("Predictor webhook: request function unavailable")
		return false
	end

	local webhookUrl = string.gsub(CONFIG.predictorWebhookUrl, "%?.*$", "")
	local messageId = tostring(stockPredictionShops.webhookMessageId or "")
	local createBody = HttpService:JSONEncode({
		username = "Stock Predictor",
		embeds = embeds,
	})
	local editBody = HttpService:JSONEncode({
		embeds = embeds,
	})

	local function perform(method, url, requestBody)
		local ok, response = pcall(function()
			return requestFunction({
				Url = url,
				Method = method,
				Headers = {
					["Content-Type"] = "application/json",
				},
				Body = requestBody,
			})
		end)
		local statusCode = ok and type(response) == "table"
			and tonumber(response.StatusCode or response.Status or response.status_code)
			or 0
		return ok and statusCode >= 200 and statusCode < 300, response, statusCode
	end

	if messageId ~= "" then
		local edited = perform("PATCH", webhookUrl .. "/messages/" .. messageId, editBody)
		if edited then
			return true
		end
		stockPredictionShops.webhookMessageId = nil
	end

	local sent, response, statusCode = perform("POST", webhookUrl .. "?wait=true", createBody)
	if not sent then
		setStatus(("Predictor webhook failed (%s)"):format(tostring(statusCode)))
		return false
	end

	local responseBody = type(response) == "table" and (response.Body or response.body) or nil
	if type(responseBody) == "string" then
		local decodedOk, decoded = pcall(HttpService.JSONDecode, HttpService, responseBody)
		if decodedOk and type(decoded) == "table" and decoded.id then
			stockPredictionShops.webhookMessageId = tostring(decoded.id)
		end
	end
	saveConfig()
	return true
end

function canSendOfficialStockWebhook()
	return CONFIG.officialStockWebhookUrl ~= "" and string.lower(localPlayer.Name or "") == "saraoliver6"
end

function canSendPredictorWebhook()
	return CONFIG.predictorWebhookUrl ~= "" and string.lower(localPlayer.Name or "") == "saraoliver6"
end

function getStockPredictionKey(shopName, itemName)
	return tostring(shopName) .. ":" .. tostring(itemName)
end

function getSelectedPredictionMap(shopName)
	return shopName == "SeedShop" and selectedSeeds or selectedGears
end

function getShopRestockTimes(shopName)
	local stockValues = ReplicatedStorage:FindFirstChild("StockValues")
	local shop = stockValues and stockValues:FindFirstChild(shopName)
	if not shop then
		return nil, nil
	end

	local lastValue = shop:FindFirstChild("UnixLastRestock")
	local nextValue = shop:FindFirstChild("UnixNextRestock")
	local lastRestock = lastValue and tonumber(lastValue.Value) or nil
	local nextRestock = nextValue and tonumber(nextValue.Value) or nil
	return lastRestock, nextRestock
end

function recordStockPredictionCycle(shopName, restockUnix)
	restockUnix = tonumber(restockUnix)
	if not restockUnix or restockUnix <= 0 then
		return false
	end

	local shopHistory = stockPredictionShops[shopName]
	if type(shopHistory) ~= "table" then
		shopHistory = {}
		stockPredictionShops[shopName] = shopHistory
	end
	if tonumber(shopHistory.lastObservedRestock) == restockUnix then
		return false
	end

	shopHistory.lastObservedRestock = restockUnix
	shopHistory.observations = math.max(0, tonumber(shopHistory.observations) or 0) + 1

	local items = getStockItemsFolder and getStockItemsFolder(shopName)
	if items then
		for _, item in ipairs(items:GetChildren()) do
			if not string.find(string.lower(item.Name), "template", 1, true) then
				local key = getStockPredictionKey(shopName, item.Name)
				local history = stockPredictionHistory[key]
				if type(history) ~= "table" then
					history = {}
					stockPredictionHistory[key] = history
				end

				history.observations = math.max(0, tonumber(history.observations) or 0) + 1
				local stockAmount = getShopStockAmount and getShopStockAmount(shopName, item.Name) or 0
				local seenRestock = tonumber(stockPredictionSeenAt[key])
				if stockAmount > 0 or seenRestock == restockUnix then
					history.hits = math.max(0, tonumber(history.hits) or 0) + 1
					local previousHit = tonumber(history.lastHitRestock)
					if previousHit and previousHit < restockUnix then
						local cycleSeconds = tonumber(shopHistory.cycleSeconds) or 300
						local gap = math.max(1, math.floor(((restockUnix - previousHit) / math.max(cycleSeconds, 1)) + 0.5))
						history.gapTotal = math.max(0, tonumber(history.gapTotal) or 0) + gap
						history.gapCount = math.max(0, tonumber(history.gapCount) or 0) + 1
						history.gapMin = math.min(tonumber(history.gapMin) or gap, gap)
						history.gapMax = math.max(tonumber(history.gapMax) or gap, gap)
					end
					history.lastHitRestock = restockUnix
					if stockAmount > 0 then
						history.lastAmount = stockAmount
					end
				end
			end
		end
	end

	saveConfig()
	if canSendPredictorWebhook() then
		task.defer(function()
			if type(queueStockPredictionUpdate) == "function" then
				queueStockPredictionUpdate()
			end
		end)
	end
	return true
end

function getStockItemEmoji(shopName, itemName)
	local name = string.lower(tostring(itemName or ""))
	local exact = {
		["bamboo"] = "🎋",
		["corn"] = "🌽",
		["tulip"] = "🌷",
		["tomato"] = "🍅",
		["carrot"] = "🥕",
		["strawberry"] = "🍓",
		["blueberry"] = "🫐",
		["mushroom"] = "🍄",
		["acorn"] = "🌰",
		["sunflower"] = "🌻",
		["moon bloom"] = "🌙",
		["poison apple"] = "🍏",
		["trowel"] = "🔧",
		["teleporter"] = "🛰️",
		["flashbang"] = "💣",
		["basic pot"] = "📦",
	}
	if exact[name] then
		return exact[name]
	end
	if string.find(name, "watering", 1, true) then
		return "💧"
	elseif string.find(name, "sprinkler", 1, true) then
		return "🚿"
	elseif string.find(name, "mushroom", 1, true) then
		return "🍄"
	elseif string.find(name, "dragon", 1, true) then
		return "🐉"
	elseif string.find(name, "berry", 1, true) then
		return "🫐"
	elseif string.find(name, "seed", 1, true) then
		return "🌱"
	end
	return shopName == "SeedShop" and "🌱" or "🧰"
end

function getStockPredictionEstimate(shopName, itemName, nextRestock)
	local shopHistory = stockPredictionShops[shopName] or {}
	local cycleSeconds = math.max(1, tonumber(shopHistory.cycleSeconds) or 300)
	local history = stockPredictionHistory[getStockPredictionKey(shopName, itemName)] or {}
	local observations = math.max(0, tonumber(history.observations) or 0)
	local hits = math.max(0, tonumber(history.hits) or 0)
	local probability = observations > 0 and math.clamp(hits / observations, 0, 1) or nil
	local gapCount = math.max(0, tonumber(history.gapCount) or 0)
	local gapTotal = math.max(0, tonumber(history.gapTotal) or 0)
	local lastHitRestock = tonumber(history.lastHitRestock)
	if hits <= 0 then
		return nil, probability, hits, observations, nil, "never_seen"
	end
	if hits < 2 or gapCount <= 0 or not lastHitRestock then
		return nil, probability, hits, observations, nil, "needs_more_sightings"
	end

	local averageGap = math.max(1, math.floor((gapTotal / gapCount) + 0.5))
	local likelyUnix = lastHitRestock + (averageGap * cycleSeconds)
	while likelyUnix < nextRestock do
		likelyUnix += averageGap * cycleSeconds
	end
	local cycles = math.max(1, math.floor(((likelyUnix - nextRestock) / cycleSeconds) + 0.5) + 1)
	return likelyUnix, probability, hits, observations, cycles, "learned"
end

function getStockPredictionConfidenceText(probability, hits, observations, cycles, status)
	observations = math.max(0, tonumber(observations) or 0)
	hits = math.max(0, tonumber(hits) or 0)
	cycles = math.max(1, tonumber(cycles) or 1)

	if status == "never_seen" or hits <= 0 then
		return observations > 0 and ("never seen in %d checks"):format(observations) or "no data yet"
	end
	if status == "needs_more_sightings" then
		return ("seen %d/%d, learning pattern"):format(hits, observations)
	end

	local rateText = ("%.0f%%"):format(math.clamp((probability or 0) * 100, 0, 100))
	if cycles > 1 then
		return ("%s observed, ~%d cycles"):format(rateText, cycles)
	end
	return ("%s observed"):format(rateText)
end

function buildLegacyStockPredictionEmbed(shopName)
	local _, nextRestock = getShopRestockTimes(shopName)
	nextRestock = tonumber(nextRestock)
	if not nextRestock or nextRestock <= 0 then
		return nil
	end

	local currentStock = {}
	local upcoming = {}
	local items = getStockItemsFolder and getStockItemsFolder(shopName)
	if items then
		for _, item in ipairs(items:GetChildren()) do
			if not string.find(string.lower(item.Name), "template", 1, true) then
				local emoji = getStockItemEmoji(shopName, item.Name)
				local amount = getShopStockAmount and getShopStockAmount(shopName, item.Name) or 0
				local likelyUnix, probability, hits, observations, _, status = getStockPredictionEstimate(shopName, item.Name, nextRestock)
				if amount > 0 then
					table.insert(currentStock, {
						name = item.Name,
						line = ("• %s **%s** `x%d`"):format(emoji, item.Name, amount),
					})
				elseif likelyUnix and status == "learned" then
					table.insert(upcoming, {
						name = item.Name,
						time = likelyUnix,
						line = ("• %s **%s** · estimated <t:%d:R> · `%.0f%% observed rate`"):format(
							emoji,
							item.Name,
							likelyUnix,
							(probability or 0) * 100
						),
					})
				end
			end
		end
	end

	table.sort(currentStock, function(left, right)
		return left.name < right.name
	end)
	table.sort(upcoming, function(left, right)
		if left.time ~= right.time then
			return left.time < right.time
		end
		return left.name < right.name
	end)

	local currentStockLines = {}
	for _, entry in ipairs(currentStock) do
		table.insert(currentStockLines, entry.line)
	end
	local upcomingLines = {}
	for index, entry in ipairs(upcoming) do
		if index > 20 then
			break
		end
		table.insert(upcomingLines, entry.line)
	end

	local isSeed = shopName == "SeedShop"
	local description = table.concat({
		"🔵 Exact shop timer; item estimates use observed restock history",
		("**%s Next Restock · <t:%d:R>**"):format(isSeed and "🌱" or "🧰", nextRestock),
		"",
		("**%s Legacy Stock Snapshot**"):format(isSeed and "🌱" or "🧰"),
		#currentStockLines > 0 and table.concat(currentStockLines, "\n") or "• No legacy stock lines",
		"",
		("**%s Learned Estimates**"):format(isSeed and "🌹 Seeds" or "🧰 Gears"),
		#upcomingLines > 0 and table.concat(upcomingLines, "\n") or "• At least 3 observed restocks are required",
	}, "\n")

	return {
		title = isSeed and "🌿 Seed Shop Stock Forecast" or "🧰 Gear Shop Stock Forecast",
		description = description,
		color = isSeed and 5763719 or 3447003,
		footer = {
			text = (isSeed and "Seed Shop" or "Gear Shop") .. " • Learned estimates are not guaranteed",
		},
		timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ"),
	}
end

function buildStockPredictionEmbed(shopName)
	local _, nextRestock = getShopRestockTimes(shopName)
	nextRestock = tonumber(nextRestock)
	if not nextRestock or nextRestock <= 0 then
		return nil
	end

	local predictions = {}
	local learning = {}
	local items = getStockItemsFolder and getStockItemsFolder(shopName)
	if items then
		for _, item in ipairs(items:GetChildren()) do
			if not string.find(string.lower(item.Name), "template", 1, true) then
				local emoji = getStockItemEmoji(shopName, item.Name)
				local likelyUnix, probability, hits, observations, cycles, status = getStockPredictionEstimate(shopName, item.Name, nextRestock)
				local confidence = getStockPredictionConfidenceText(probability, hits, observations, cycles, status)
				if likelyUnix and status == "learned" then
					table.insert(predictions, {
						name = item.Name,
						time = likelyUnix,
						line = ("- %s **%s**: <t:%d:F> (<t:%d:R>) `%s`"):format(
							emoji,
							item.Name,
							likelyUnix,
							likelyUnix,
							confidence
						),
					})
				else
					table.insert(learning, {
						name = item.Name,
						hits = hits,
						observations = observations,
						line = ("- %s **%s**: `%s`"):format(emoji, item.Name, confidence),
					})
				end
			end
		end
	end

	table.sort(predictions, function(left, right)
		if left.time ~= right.time then
			return left.time < right.time
		end
		return left.name < right.name
	end)
	table.sort(learning, function(left, right)
		if left.hits ~= right.hits then
			return left.hits > right.hits
		end
		if left.observations ~= right.observations then
			return left.observations > right.observations
		end
		return left.name < right.name
	end)

	local predictionLines = {}
	for index, entry in ipairs(predictions) do
		if index > 45 then
			break
		end
		table.insert(predictionLines, entry.line)
	end
	local learningLines = {}
	for index, entry in ipairs(learning) do
		if index > 12 then
			break
		end
		table.insert(learningLines, entry.line)
	end

	local isSeed = shopName == "SeedShop"
	local description = table.concat({
		"Exact shop timer. Forecasts only show after an item has enough observed appearances to learn a repeat gap.",
		("Next shop refresh: <t:%d:F> (<t:%d:R>)"):format(nextRestock, nextRestock),
		"",
		"**Forecasts**",
		#predictionLines > 0 and table.concat(predictionLines, "\n") or "- No learned forecasts yet",
		"",
		"**Learning / No Forecast**",
		#learningLines > 0 and table.concat(learningLines, "\n") or "- All listed items have learned forecasts",
	}, "\n")

	return {
		title = isSeed and "Seed Shop Stock Forecast" or "Gear Shop Stock Forecast",
		description = description,
		color = isSeed and 5763719 or 3447003,
		footer = {
			text = (isSeed and "Seed Shop" or "Gear Shop") .. " - learned estimates are not guaranteed",
		},
		timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ"),
	}
end

function buildStockPredictionEmbeds()
	local embeds = {}
	for _, shopName in ipairs({ "SeedShop", "GearShop" }) do
		local embed = buildStockPredictionEmbed(shopName)
		if embed then
			table.insert(embeds, embed)
		end
	end
	return embeds
end

function sendStockPrediction()
	if not canSendPredictorWebhook() then
		return false
	end
	local embeds = buildStockPredictionEmbeds()
	if #embeds == 0 then
		return false
	end
	return requestPredictorWebhookMessage(embeds)
end

function queueStockPredictionUpdate()
	if predictorWebhookUpdateScheduled then
		return
	end
	predictorWebhookUpdateScheduled = true
	task.delay(1.5, function()
		predictorWebhookUpdateScheduled = false
		sendStockPrediction()
	end)
end

function shouldNotifySelected(map, name)
	return name and name ~= "" and map[name] == true
end

function listHasName(list, name)
	for _, value in ipairs(list) do
		if value == name then
			return true
		end
	end
	return false
end

function compactName(value)
	return string.gsub(string.lower(tostring(value or "")), "[^%w]", "")
end

function getStockFolderName(shopName)
	if shopName == "Seed shop" then
		return "SeedShop"
	elseif shopName == "Gear shop" then
		return "GearShop"
	end
	return shopName
end

function getShopGuiRoot(shopName)
	local guiName = getStockFolderName(shopName)
	return playerGui:FindFirstChild(guiName) or StarterGui:FindFirstChild(guiName)
end

function shopGuiShowsItem(shopName, itemName)
	local shopGui = getShopGuiRoot(shopName)
	if not shopGui then
		return false
	end

	for _, descendant in ipairs(shopGui:GetDescendants()) do
		if descendant.Name == itemName and descendant.Name ~= "ItemTemplate" then
			if descendant:FindFirstChild("Main_Frame", true) or descendant:FindFirstChildWhichIsA("GuiButton", true) then
				return true
			end
		end
	end

	return false
end

function itemIsInStock(shopName, itemName)
	local stockFolderName = getStockFolderName(shopName)
	local stockAmount = getShopStockAmount and getShopStockAmount(stockFolderName, itemName) or 0
	return stockAmount > 0
end

function flushStockWebhookQueue()
	stockWebhookScheduled = false
	local queued = stockWebhookQueue
	stockWebhookQueue = {}

	local byShop = {}
	local keys = {}
	for _, entry in pairs(queued) do
		if entry.amount and entry.amount > 0 then
			byShop[entry.shopName] = byShop[entry.shopName] or {}
			table.insert(byShop[entry.shopName], ("- %s (%d available)"):format(entry.itemName, entry.amount))
			table.insert(keys, entry.key)
		end
	end

	if #keys == 0 then
		return
	end

	local sections = {}
	for shopName, lines in pairs(byShop) do
		table.sort(lines)
		table.insert(sections, ("**%s**\n%s"):format(shopName, table.concat(lines, "\n")))
	end
	table.sort(sections)

	if #sections == 0 then
		return
	end

	local description = table.concat(sections, "\n\n")
	local sent = sendWebhook("Stock update", description, nil, CONFIG.webhookUrl)
	local officialSent = false
	if canSendOfficialStockWebhook() then
		officialSent = sendWebhook("Stock update", description, nil, CONFIG.officialStockWebhookUrl)
	end
	local now = os.clock()
	if sent then
		for _, key in ipairs(keys) do
			webhookSentAt[key] = now
		end
	end
	if officialSent then
		for _, key in ipairs(keys) do
			webhookSentAt[key .. ":official"] = now
		end
	end
end

function queueStockWebhook(shopName, itemName, stockAmount, key)
	stockWebhookQueue[key] = {
		shopName = shopName,
		itemName = itemName,
		amount = stockAmount,
		key = key,
	}

	if stockWebhookScheduled then
		return
	end
	stockWebhookScheduled = true
	task.delay(1.25, flushStockWebhookQueue)
end

function flushActivityWebhookQueue()
	activityWebhookScheduled = false
	local queued = activityWebhookQueue
	activityWebhookQueue = {}

	if #queued == 0 then
		return
	end

	sendWebhook("Activity update", table.concat(queued, "\n"), nil)
end

function queueActivityWebhook(line)
	if CONFIG.webhookUrl == "" or not line or line == "" then
		return false
	end

	table.insert(activityWebhookQueue, "- " .. tostring(line))
	if activityWebhookScheduled then
		return true
	end

	activityWebhookScheduled = true
	task.delay(1.5, flushActivityWebhookQueue)
	return true
end

function notifyStock(shopName, itemName, force)
	local stockFolderName = getStockFolderName(shopName)
	local stockAmount = getShopStockAmount(stockFolderName, itemName)
	local key = "stock:" .. shopName .. ":" .. itemName
	local previousAmount = stockLastAmounts[key]
	stockLastAmounts[key] = stockAmount

	if stockAmount <= 0 then
		webhookSentAt[key] = nil
		return
	end

	local lastRestock = getShopRestockTimes(stockFolderName)
	if lastRestock and lastRestock > 0 then
		stockPredictionSeenAt[getStockPredictionKey(stockFolderName, itemName)] = lastRestock
	end

	if force or previousAmount == nil or previousAmount ~= stockAmount then
		if not webhookSentAt[key] or os.clock() - webhookSentAt[key] >= CONFIG.stockWebhookCooldown then
			queueStockWebhook(shopName, itemName, stockAmount, key)
		end
	end
end

local watchedStockItems = {}

function watchStockItem(shopName, item)
	if not item then
		return
	end

	local key = shopName .. ":" .. item:GetFullName()
	if watchedStockItems[key] then
		return
	end
	watchedStockItems[key] = true

	local function changed()
		task.defer(function()
			notifyStock(shopName == "SeedShop" and "Seed shop" or shopName == "GearShop" and "Gear shop" or shopName, item.Name)
		end)
	end

	for _, attributeName in ipairs({
		"Stock",
		"StockAmount",
		"CurrentStock",
		"Amount",
		"Quantity",
		"Count",
		"Available",
	}) do
		item:GetAttributeChangedSignal(attributeName):Connect(changed)
	end

	if item:IsA("ValueBase") then
		item.Changed:Connect(changed)
	end

	for _, descendant in ipairs(item:GetDescendants()) do
		for _, attributeName in ipairs({
			"Stock",
			"StockAmount",
			"CurrentStock",
			"Amount",
			"Quantity",
			"Count",
			"Available",
		}) do
			descendant:GetAttributeChangedSignal(attributeName):Connect(changed)
		end
		if descendant:IsA("ValueBase") then
			descendant.Changed:Connect(changed)
		end
	end

	item.DescendantAdded:Connect(function(descendant)
		for _, attributeName in ipairs({
			"Stock",
			"StockAmount",
			"CurrentStock",
			"Amount",
			"Quantity",
			"Count",
			"Available",
		}) do
			descendant:GetAttributeChangedSignal(attributeName):Connect(changed)
		end
		if descendant:IsA("ValueBase") then
			descendant.Changed:Connect(changed)
			changed()
		end
	end)
	item.ChildAdded:Connect(changed)
	item.ChildRemoved:Connect(changed)
end

function notifyPetSpawn(petName)
	if shouldNotifySelected(selectedPets, petName) then
		queueActivityWebhook(("Pet spawned: `%s`"):format(petName))
	end
end

local petVariantWords = {
	"Big",
	"Huge",
	"Giant",
	"Rainbow",
	"Super",
	"Gold",
	"Golden",
	"Shiny",
}

local statusValue
local statsLabels = {}
local sessionStartedAt = os.clock()
local lastStatusSetAt = 0
local pendingStatusMessage
local lastStatsUIUpdateAt = 0
local schedulerAccumulator = 0
local lastStatsWebhookAt = 0

local stats = {
	fruitTargetsChecked = 0,
	fruitCollected = 0,
	collectSkippedFull = 0,
	seedsBought = 0,
	gearBought = 0,
	petsBought = 0,
	petsSold = 0,
	mailClaimed = 0,
	mailChecks = 0,
	sheckles = 0,
	startSheckles = nil,
	shecklesFarmed = 0,
	inventoryItems = 0,
	inventoryCapacity = CONFIG.maxInventoryItems,
	inventoryFull = false,
}

local running = {}
local stopTokens = {}
local lastAutoSellAttemptAt = 0

function bumpStopToken(key)
	stopTokens[key] = (stopTokens[key] or 0) + 1
end

function getStopToken(key)
	return stopTokens[key] or 0
end

function runStopped(key, token)
	return key and (not isEnabled(key) or getStopToken(key) ~= token)
end

setStatus = function(message)
	local text = tostring(message)
	local now = os.clock()
	state.lastStatus = text
	local lowered = string.lower(text)
	local remoteIssue = string.find(lowered, "remote", 1, true)
		or string.find(lowered, "failed", 1, true)
		or string.find(lowered, "error", 1, true)
		or string.find(lowered, "made no change", 1, true)
	local noisyEmptyStatus = string.find(lowered, "no matching", 1, true)
		or string.find(lowered, "no pets selected", 1, true)
		or string.find(lowered, "no verified", 1, true)
		or string.find(lowered, "no harvest targets found", 1, true)
		or string.find(lowered, "no owned garden found", 1, true)
		or string.find(lowered, "no valid harvest attempt", 1, true)
		or string.find(lowered, "not found", 1, true)
		or string.match(lowered, "no .- found") ~= nil
	if noisyEmptyStatus and not remoteIssue then
		return
	end
	if statusValue then
		if now - lastStatusSetAt >= 0.8 then
			lastStatusSetAt = now
			statusValue.Value = text
			pendingStatusMessage = nil
		else
			pendingStatusMessage = text
		end
	end
end

function countEnabledToggles()
	local count = 0
	for _, key in ipairs({
		"fruitCollector",
		"autoSell",
		"sellWhenFull",
		"autoBuySeeds",
		"autoBuyGear",
		"autoMovePlants",
		"autoBuyPets",
		"autoSellPets",
		"performanceMode",
	}) do
		if state[key] then
			count += 1
		end
	end
	return count
end

function formatNumber(value)
	value = tonumber(value) or 0
	local sign = value < 0 and "-" or ""
	value = math.abs(math.floor(value + 0.5))
	local text = tostring(value)
	while true do
		local replaced
		text, replaced = string.gsub(text, "^(%d+)(%d%d%d)", "%1,%2")
		if replaced == 0 then
			break
		end
	end
	return sign .. text
end

function parseAmountText(text)
	text = tostring(text or "")
	local lowered = string.lower(text)
	local multiplier = 1
	if string.find(lowered, "b", 1, true) then
		multiplier = 1000000000
	elseif string.find(lowered, "m", 1, true) then
		multiplier = 1000000
	elseif string.find(lowered, "k", 1, true) then
		multiplier = 1000
	end

	local raw = string.match(text, "[-]?[%d,]+%.?%d*")
	if not raw then
		return nil
	end

	raw = string.gsub(raw, ",", "")
	local amount = tonumber(raw)
	if not amount then
		return nil
	end
	return math.floor(amount * multiplier + 0.5)
end

function isEnabled(key)
	return state[key] == true
end

function addUniqueName(list, name)
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

function trimText(value)
	return string.gsub(tostring(value or ""), "^%s*(.-)%s*$", "%1")
end

function stripVariantWords(name)
	local result = tostring(name or "")
	for _, word in ipairs(petVariantWords) do
		result = string.gsub(result, "^" .. word .. "%s+", "")
		result = string.gsub(result, "%s+" .. word .. "$", "")
	end
	return trimText(result)
end

function getWildPetBaseName(name)
	local text = tostring(name or "")
	local fromSpawn = string.match(text, "^WildPet[_%s%-]+(.+)[_%s%-]+WildPet[_%s%-]+[%w%-]+$")
		or string.match(text, "^WildPet[_%s%-]+(.+)$")
	if fromSpawn and fromSpawn ~= "" then
		text = fromSpawn
	end
	text = string.gsub(text, "[_%s%-]+WildPet[_%s%-]*[%w%-]*$", "")
	text = string.gsub(text, "^WildPet[_%s%-]+", "")
	text = string.gsub(text, "_", " ")
	text = string.gsub(text, "%s+", " ")
	return stripVariantWords(text)
end

function getGearImagesFolder()
	local sharedModules = ReplicatedStorage:FindFirstChild("SharedModules")
	return sharedModules and sharedModules:FindFirstChild("GearImages")
end

getStockItemsFolder = function(shopName)
	local stockValues = ReplicatedStorage:FindFirstChild("StockValues")
	local shop = stockValues and stockValues:FindFirstChild(shopName)
	return shop and shop:FindFirstChild("Items")
end

function getSeedShopGui()
	return StarterGui:FindFirstChild("SeedShop") or playerGui:FindFirstChild("SeedShop")
end

function getRuntimeSeedShopGui()
	return playerGui:FindFirstChild("SeedShop") or StarterGui:FindFirstChild("SeedShop")
end

function getNumericFromInstance(instance, keys)
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

function stockKeyLooksValid(name)
	local lowered = string.lower(tostring(name or ""))
	return lowered == "stock"
		or lowered == "stockamount"
		or lowered == "currentstock"
		or lowered == "amount"
		or lowered == "quantity"
		or lowered == "count"
		or lowered == "available"
		or string.find(lowered, "stock", 1, true) ~= nil
end

getShopStockAmount = function(shopName, itemName)
	local items = getStockItemsFolder and getStockItemsFolder(shopName)
	local stockItem = items and items:FindFirstChild(itemName)
	if not stockItem then
		return 0
	end

	if stockItem:IsA("NumberValue") or stockItem:IsA("IntValue") then
		return math.max(0, math.floor(tonumber(stockItem.Value) or 0))
	end

	if stockItem:IsA("BoolValue") then
		return stockItem.Value and 1 or 0
	end

	local value = getNumericFromInstance(stockItem, {
		"Stock",
		"StockAmount",
		"CurrentStock",
		"Amount",
		"Quantity",
		"Count",
		"Available",
	})
	if value then
		return math.max(0, math.floor(value))
	end

	for _, descendant in ipairs(stockItem:GetDescendants()) do
		if stockKeyLooksValid(descendant.Name) and (descendant:IsA("NumberValue") or descendant:IsA("IntValue")) then
			local number = tonumber(descendant.Value)
			if number and number > 0 then
				return math.floor(number)
			end
		elseif stockKeyLooksValid(descendant.Name) and descendant:IsA("BoolValue") and descendant.Value == true then
			return 1
		end
	end

	return 0
end

getShopPriceAmount = function(shopName, itemName)
	local items = getStockItemsFolder and getStockItemsFolder(shopName)
	local stockItem = items and items:FindFirstChild(itemName)
	if not stockItem then
		return nil
	end

	return getNumericFromInstance(stockItem, {
		"Price",
		"Cost",
		"Value",
		"Sheckles",
		"Coins",
		"BuyPrice",
		"CurrentPrice",
	})
end

function getSeedMetadataValue(seedName)
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

function refreshNamesFromStock(shopName, targetList)
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

function refreshSeedNamesFromStockValues()
	refreshNamesFromStock("SeedShop", seedNames)
end

function refreshGearNamesFromStockValues()
	refreshNamesFromStock("GearShop", gearNames)
end

function refreshPetNamesFromAssets()
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local pets = assets and assets:FindFirstChild("Pets")
	if not pets then
		return
	end

	for _, pet in ipairs(pets:GetChildren()) do
		addUniqueName(petNames, stripVariantWords(pet.Name))
	end

	table.sort(petNames)
end

function watchStockPredictionShop(shopName)
	local stockValues = ReplicatedStorage:FindFirstChild("StockValues")
	local shop = stockValues and stockValues:FindFirstChild(shopName)
	local lastValue = shop and shop:FindFirstChild("UnixLastRestock")
	local nextValue = shop and shop:FindFirstChild("UnixNextRestock")
	if not lastValue or not nextValue then
		return
	end

	local function updateCycle()
		local lastRestock = tonumber(lastValue.Value)
		local nextRestock = tonumber(nextValue.Value)
		local history = stockPredictionShops[shopName]
		if type(history) ~= "table" then
			history = {}
			stockPredictionShops[shopName] = history
		end
		if lastRestock and nextRestock and nextRestock > lastRestock then
			history.cycleSeconds = nextRestock - lastRestock
		end
	end

	local function observeRestock()
		updateCycle()
		task.delay(0.75, function()
			recordStockPredictionCycle(shopName, tonumber(lastValue.Value))
		end)
	end

	lastValue.Changed:Connect(observeRestock)
	nextValue.Changed:Connect(updateCycle)
	updateCycle()
	task.delay(1, observeRestock)
end

refreshSeedNamesFromStockValues()
refreshGearNamesFromStockValues()
refreshPetNamesFromAssets()
watchStockPredictionShop("SeedShop")
watchStockPredictionShop("GearShop")

task.spawn(function()
	while task.wait(1) do
		if canSendPredictorWebhook() then
			local now = os.time()
			local predictionDue = false
			for _, shopName in ipairs({ "SeedShop", "GearShop" }) do
				local _, nextRestock = getShopRestockTimes(shopName)
				nextRestock = tonumber(nextRestock)
				if nextRestock and nextRestock > 0 then
					local history = stockPredictionShops[shopName]
					if type(history) ~= "table" then
						history = {}
						stockPredictionShops[shopName] = history
					end
					local leadSeconds = math.max(5, tonumber(CONFIG.stockPredictorLeadSeconds) or 30)
					if now >= nextRestock - leadSeconds
						and now <= nextRestock + 2
						and tonumber(history.predictedFor) ~= nextRestock
					then
						predictionDue = true
					end
				end
			end
			if predictionDue and sendStockPrediction() then
				for _, shopName in ipairs({ "SeedShop", "GearShop" }) do
					local _, nextRestock = getShopRestockTimes(shopName)
					local history = stockPredictionShops[shopName]
					if type(history) == "table" then
						history.predictedFor = nextRestock
					end
				end
				saveConfig()
			end
		end
	end
end)

function getCharacter()
	return localPlayer.Character or localPlayer.CharacterAdded:Wait()
end

function getRoot()
	local character = getCharacter()
	return character:FindFirstChild("HumanoidRootPart")
end

function getHumanoid()
	local character = getCharacter()
	return character:FindFirstChildOfClass("Humanoid")
end

function getObjectPath(instance)
	local parts = {}
	local current = instance
	while current and current ~= game do
		table.insert(parts, 1, current.Name)
		current = current.Parent
	end
	return table.concat(parts, ".")
end

function safeText(value)
	if value == nil then
		return ""
	end

	return tostring(value)
end

local packetIdKeys = {
	"Id",
	"ID",
	"UUID",
	"Guid",
	"UID",
	"UniqueId",
	"UniqueID",
	"InstanceId",
	"InstanceID",
	"FruitId",
	"FruitID",
	"ItemId",
	"ItemID",
	"PetId",
	"PetID",
}

function getInstancePacketId(instance)
	if typeof(instance) ~= "Instance" then
		return nil
	end

	for _, key in ipairs(packetIdKeys) do
		local ok, value = pcall(function()
			return instance:GetAttribute(key)
		end)
		if ok and value ~= nil and tostring(value) ~= "" then
			return value
		end

		local child = instance:FindFirstChild(key)
		if child and child:IsA("ValueBase") and child.Value ~= nil and tostring(child.Value) ~= "" then
			return child.Value
		end
	end

	local nameId = string.match(instance.Name, "[%w]+_[%w%-]+_([%w%-]+)$")
		or string.match(instance.Name, "([0-9a-fA-F]+%-[0-9a-fA-F]+%-[0-9a-fA-F]+%-[0-9a-fA-F]+%-[0-9a-fA-F]+)")
	if nameId and nameId ~= "" then
		return nameId
	end

	return nil
end

local packetModule

function getPacketModule()
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
local packetEntryCache = {}
local packetObjectCache = {}
local runtimePacketEntryCache = {}
local packetRegistryTables
local unpackArgs = table.unpack or unpack
local packetRequiresArguments = {
	CollectFruit = true,
	MovePlant = true,
	PurchaseGear = true,
	PurchaseSeed = true,
	SellFruit = true,
	SellItem = true,
	SellPet = true,
	WildPetCollected = true,
	WildPetTame = true,
}
local packetSendMethodNames = {
	"Fire",
	"fire",
	"FireServer",
	"fireServer",
	"Send",
	"send",
	"SendToServer",
	"sendToServer",
	"SendServer",
	"sendServer",
	"Invoke",
	"invoke",
	"InvokeServer",
	"invokeServer",
	"Call",
	"call",
}

function tryPacketMethod(target, methodName, ...)
	if type(target) ~= "table" and typeof(target) ~= "Instance" then
		return false
	end
	if select("#", ...) > 0 and type(target) == "table" then
		local writes
		pcall(function()
			writes = target.Writes
		end)
		if type(writes) == "table" and #writes == 0 then
			return false
		end
	end
	local method = target[methodName]
	if type(method) ~= "function" then
		return false
	end
	return pcall(method, target, ...) or pcall(method, ...)
end

function getPacketRemote()
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

function packetNameExists(packetName)
	local remote = getPacketRemote()
	if not remote then
		return true
	end
	return remote:GetAttribute(packetName) ~= nil
end

function getPacketId(packetName)
	local remote = getPacketRemote()
	if not remote then
		return nil
	end
	local id = remote:GetAttribute(packetName)
	if type(id) == "number" and id >= 0 and id <= 255 then
		return id
	end
	return nil
end

function fireRawPacketBuffer(packetName, writePayload, instances)
	local remote = getPacketRemote()
	local packetId = getPacketId(packetName)
	if not remote or packetId == nil or typeof(buffer) ~= "table" then
		return false
	end

	local ok, payloadBuffer = pcall(writePayload, packetId)
	if not ok or typeof(payloadBuffer) ~= "buffer" then
		return false
	end

	if instances and #instances > 0 then
		return pcall(remote.FireServer, remote, payloadBuffer, instances)
	end
	return pcall(remote.FireServer, remote, payloadBuffer)
end

function sendRawStringPacket(packetName, value)
	local text = tostring(value or "")
	if text == "" or #text > 255 then
		return false
	end

	return fireRawPacketBuffer(packetName, function(packetId)
		local payloadBuffer = buffer.create(2 + #text)
		buffer.writeu8(payloadBuffer, 0, packetId)
		buffer.writeu8(payloadBuffer, 1, #text)
		buffer.writestring(payloadBuffer, 2, text)
		return payloadBuffer
	end)
end

function sendRawAnyStringPacket(packetName, value)
	local text = tostring(value or "")
	if text == "" or #text > 255 then
		return false
	end

	return fireRawPacketBuffer(packetName, function(packetId)
		local payloadBuffer = buffer.create(3 + #text)
		buffer.writeu8(payloadBuffer, 0, packetId)
		buffer.writeu8(payloadBuffer, 1, 11)
		buffer.writeu8(payloadBuffer, 2, #text)
		buffer.writestring(payloadBuffer, 3, text)
		return payloadBuffer
	end)
end

function sendRawStringNumberPacket(packetName, value, amount)
	local text = tostring(value or "")
	amount = tonumber(amount) or 1
	if text == "" or #text > 255 or amount < 0 or amount > 255 then
		return false
	end

	return fireRawPacketBuffer(packetName, function(packetId)
		local payloadBuffer = buffer.create(3 + #text)
		buffer.writeu8(payloadBuffer, 0, packetId)
		buffer.writeu8(payloadBuffer, 1, #text)
		buffer.writestring(payloadBuffer, 2, text)
		buffer.writeu8(payloadBuffer, 2 + #text, amount)
		return payloadBuffer
	end)
end

function sendRawAnyStringNumberPacket(packetName, value, amount)
	local text = tostring(value or "")
	amount = tonumber(amount) or 1
	if text == "" or #text > 255 or amount < 0 or amount > 255 then
		return false
	end

	return fireRawPacketBuffer(packetName, function(packetId)
		local payloadBuffer = buffer.create(5 + #text)
		buffer.writeu8(payloadBuffer, 0, packetId)
		buffer.writeu8(payloadBuffer, 1, 11)
		buffer.writeu8(payloadBuffer, 2, #text)
		buffer.writestring(payloadBuffer, 3, text)
		buffer.writeu8(payloadBuffer, 3 + #text, 5)
		buffer.writeu8(payloadBuffer, 4 + #text, amount)
		return payloadBuffer
	end)
end

function sendRawStringVariants(packetName, values)
	local actions = 0
	local seen = {}
	for _, value in ipairs(values or {}) do
		local text = tostring(value or "")
		if text ~= "" and not seen[text] then
			seen[text] = true
			if sendRawStringPacket(packetName, text) then
				actions += 1
			end
			if sendRawAnyStringPacket(packetName, text) then
				actions += 1
			end
		end
	end
	return actions > 0, actions
end

function sendRawStringNumberVariants(packetName, values, amount)
	local actions = 0
	local seen = {}
	for _, value in ipairs(values or {}) do
		local text = tostring(value or "")
		if text ~= "" and not seen[text] then
			seen[text] = true
			if sendRawStringNumberPacket(packetName, text, amount) then
				actions += 1
			end
			if sendRawAnyStringNumberPacket(packetName, text, amount) then
				actions += 1
			end
		end
	end
	return actions > 0, actions
end

function sendRawInstancePacket(packetName, instance)
	if typeof(instance) ~= "Instance" then
		return false
	end

	return fireRawPacketBuffer(packetName, function(packetId)
		local payloadBuffer = buffer.create(1)
		buffer.writeu8(payloadBuffer, 0, packetId)
		return payloadBuffer
	end, { instance })
end

function sendRawAnyInstancePacket(packetName, instance)
	if typeof(instance) ~= "Instance" then
		return false
	end

	return fireRawPacketBuffer(packetName, function(packetId)
		local payloadBuffer = buffer.create(2)
		buffer.writeu8(payloadBuffer, 0, packetId)
		buffer.writeu8(payloadBuffer, 1, 13)
		return payloadBuffer
	end, { instance })
end

function sendRawInstanceVariants(packetName, instances)
	local actions = 0
	local seen = {}
	for _, instance in ipairs(instances or {}) do
		if typeof(instance) == "Instance" and not seen[instance] then
			seen[instance] = true
			if sendRawInstancePacket(packetName, instance) then
				actions += 1
			end
			if sendRawAnyInstancePacket(packetName, instance) then
				actions += 1
			end
		end
	end
	return actions > 0, actions
end

function writeVector3Payload(payloadBuffer, offset, value)
	if typeof(value) ~= "Vector3" then
		return false
	end
	buffer.writef32(payloadBuffer, offset, value.X)
	buffer.writef32(payloadBuffer, offset + 4, value.Y)
	buffer.writef32(payloadBuffer, offset + 8, value.Z)
	return true
end

function sendRawInstanceVector3Packet(packetName, instance, position)
	if typeof(instance) ~= "Instance" or typeof(position) ~= "Vector3" then
		return false
	end

	return fireRawPacketBuffer(packetName, function(packetId)
		local payloadBuffer = buffer.create(13)
		buffer.writeu8(payloadBuffer, 0, packetId)
		writeVector3Payload(payloadBuffer, 1, position)
		return payloadBuffer
	end, { instance })
end

function sendRawStringVector3Packet(packetName, value, position)
	local text = tostring(value or "")
	if text == "" or #text > 255 or typeof(position) ~= "Vector3" then
		return false
	end

	return fireRawPacketBuffer(packetName, function(packetId)
		local payloadBuffer = buffer.create(14 + #text)
		buffer.writeu8(payloadBuffer, 0, packetId)
		buffer.writeu8(payloadBuffer, 1, #text)
		buffer.writestring(payloadBuffer, 2, text)
		writeVector3Payload(payloadBuffer, 2 + #text, position)
		return payloadBuffer
	end)
end

function firePacketRemote(packetName, ...)
	return false
end

function tryPacketEntry(entry, ...)
	if type(entry) == "table" then
		for _, methodName in ipairs(packetSendMethodNames) do
			if tryPacketMethod(entry, methodName, ...) then
				return true
			end
		end
	elseif type(entry) == "function" then
		if pcall(entry, ...) then
			return true
		end
	end

	return false
end

function addPacketRegistryTable(registries, seen, value)
	if type(value) ~= "table" or seen[value] then
		return
	end
	seen[value] = true
	table.insert(registries, value)
end

function getPacketRegistryTables()
	if packetRegistryTables then
		return packetRegistryTables
	end

	packetRegistryTables = {}
	local seen = {}
	local packet = getPacketModule()
	local meta = type(packet) == "table" and getmetatable(packet) or nil
	local constructor = type(meta) == "table" and rawget(meta, "__call") or nil

	if type(constructor) == "function" then
		if typeof(debug) == "table" and type(debug.getupvalue) == "function" then
			for index = 1, 40 do
				local ok, _, value = pcall(debug.getupvalue, constructor, index)
				if not ok or value == nil then
					break
				end
				addPacketRegistryTable(packetRegistryTables, seen, value)
			end
		elseif typeof(getupvalues) == "function" then
			local ok, upvalues = pcall(getupvalues, constructor)
			if ok and type(upvalues) == "table" then
				for _, value in pairs(upvalues) do
					addPacketRegistryTable(packetRegistryTables, seen, value)
				end
			end
		end
	end

	return packetRegistryTables
end

function findDefinedPacketObject(packetName)
	local remote = getPacketRemote()
	local packetId = remote and remote:GetAttribute(packetName) or nil

	for _, registry in ipairs(getPacketRegistryTables()) do
		local candidates = {}
		local namedCandidate
		pcall(function()
			namedCandidate = registry[packetName]
		end)
		if namedCandidate ~= nil then
			table.insert(candidates, namedCandidate)
		end
		if packetId ~= nil then
			local idCandidate
			pcall(function()
				idCandidate = registry[packetId]
			end)
			if idCandidate ~= nil then
				table.insert(candidates, idCandidate)
			end
		end

		for _, candidate in ipairs(candidates) do
			if type(candidate) == "table" then
				local nameMatches = false
				pcall(function()
					nameMatches = candidate.Name == packetName
				end)
				if nameMatches then
					return candidate
				end
			end
		end
	end

	return nil
end

function packetObjectHasNoWrites(object)
	if type(object) ~= "table" then
		return false
	end
	local writes
	pcall(function()
		writes = object.Writes
	end)
	return type(writes) == "table" and #writes == 0
end

function clearEmptyPacketObject(packetName, object)
	local remote = getPacketRemote()
	local packetId = remote and remote:GetAttribute(packetName) or nil
	for _, registry in ipairs(getPacketRegistryTables()) do
		pcall(function()
			if registry[packetName] == object then
				registry[packetName] = nil
			end
		end)
		if packetId ~= nil then
			pcall(function()
				if registry[packetId] == object then
					registry[packetId] = nil
				end
			end)
		end
	end
end

function getPacketTypeValue(typeName)
	local packet = getPacketModule()
	if type(packet) ~= "table" then
		return nil
	end
	local ok, value = pcall(function()
		return packet[typeName]
	end)
	return ok and value or nil
end

function buildTypedPacketObject(packetName, typeNames)
	local packet = getPacketModule()
	if type(packet) ~= "table" and type(packet) ~= "function" then
		return nil
	end

	local defined = findDefinedPacketObject(packetName)
	if defined and not packetObjectHasNoWrites(defined) then
		return defined
	end
	if defined and packetObjectHasNoWrites(defined) then
		clearEmptyPacketObject(packetName, defined)
		packetObjectCache[packetName] = nil
	end

	local packetTypes = {}
	for _, typeName in ipairs(typeNames or {}) do
		local packetType = getPacketTypeValue(typeName)
		if packetType == nil then
			return nil
		end
		table.insert(packetTypes, packetType)
	end

	local ok, object
	if type(packet) == "function" then
		ok, object = pcall(packet, packetName, unpackArgs(packetTypes))
	else
		ok, object = pcall(function()
			return packet(packetName, unpackArgs(packetTypes))
		end)
	end
	if ok and type(object) == "table" and (#packetTypes == 0 or not packetObjectHasNoWrites(object)) then
		packetObjectCache[packetName] = object
		return object
	end

	return nil
end

function sendTypedPacketExact(packetName, typeNames, ...)
	if not packetNameExists(packetName) then
		return false
	end
	local object = buildTypedPacketObject(packetName, typeNames)
	if not object then
		return false
	end
	for _, methodName in ipairs(packetSendMethodNames) do
		if tryPacketMethod(object, methodName, ...) then
			return true
		end
	end
	return false
end

function sendTypedPacketArgVariants(packetName, typeNames, variants)
	local actions = 0
	for _, args in ipairs(variants or {}) do
		if sendTypedPacketExact(packetName, typeNames, unpackArgs(args)) then
			actions += 1
		end
	end
	return actions > 0, actions
end

function buildPacketObject(packetName)
	local packet = getPacketModule()
	if not packet then
		return nil
	end

	local defined = findDefinedPacketObject(packetName)
	if defined then
		return defined
	end

	local constructors = {}
	if type(packet) == "function" then
		table.insert(constructors, packet)
	elseif type(packet) == "table" then
		table.insert(constructors, function(name)
			return packet(name)
		end)
		for _, key in ipairs({
			"new",
			"New",
			"create",
			"Create",
			"get",
			"Get",
			"packet",
			"Packet",
			"fromName",
			"FromName",
			"define",
			"Define",
			"event",
			"Event",
			"remote",
			"Remote",
			"getPacket",
			"GetPacket",
		}) do
			if type(packet[key]) == "function" then
				table.insert(constructors, function(name)
					return packet[key](packet, name)
				end)
				table.insert(constructors, packet[key])
			end
		end
	end

	for _, constructor in ipairs(constructors) do
		local ok, object = pcall(constructor, packetName)
		if ok and (type(object) == "table" or typeof(object) == "Instance") then
			if packetRequiresArguments[packetName] and packetObjectHasNoWrites(object) then
				clearEmptyPacketObject(packetName, object)
				continue
			end
			return object
		end
	end

	return nil
end

function getPacketObject(packetName)
	local cached = packetObjectCache[packetName]
	if cached ~= nil then
		return cached ~= false and cached or nil
	end

	local object = buildPacketObject(packetName)
	if object then
		packetObjectCache[packetName] = object
		return object
	end

	packetObjectCache[packetName] = false
	return nil
end

function firePacketObject(packetName, ...)
	local object = getPacketObject(packetName)
	if not object then
		return false, 0
	end

	local actions = 0
	for _, methodName in ipairs(packetSendMethodNames) do
		if tryPacketMethod(object, methodName, ...) then
			actions += 1
		end
	end

	return actions > 0, actions
end

function findPacketEntry(root, packetName, seen)
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

function packetFieldMatchesPacket(value, packetName, packetId)
	if value == nil then
		return false
	end
	if value == packetName then
		return true
	end
	if packetId ~= nil and value == packetId then
		return true
	end
	local text = tostring(value)
	return text == packetName or (packetId ~= nil and text == tostring(packetId))
end

function tableLooksLikePacketEntry(value, packetName, packetId)
	if type(value) ~= "table" then
		return false
	end

	for _, key in ipairs({ "Name", "name", "_name", "PacketName", "packetName", "Id", "ID", "_id", "Identifier", "identifier" }) do
		local ok, field = pcall(function()
			return value[key]
		end)
		if ok and packetFieldMatchesPacket(field, packetName, packetId) then
			return true
		end
	end

	local matched = false
	pcall(function()
		local checked = 0
		for key, field in pairs(value) do
			checked += 1
			if packetFieldMatchesPacket(key, packetName, packetId) or packetFieldMatchesPacket(field, packetName, packetId) then
				matched = true
				break
			end
			if checked >= 40 then
				break
			end
		end
	end)

	return matched
end

function functionMentionsPacket(fn, packetName, packetId)
	if type(fn) ~= "function" then
		return false
	end

	if typeof(debug) == "table" and type(debug.getconstants) == "function" then
		local ok, constants = pcall(debug.getconstants, fn)
		if ok and type(constants) == "table" then
			for _, constant in ipairs(constants) do
				if packetFieldMatchesPacket(constant, packetName, packetId) then
					return true
				end
			end
		end
	elseif typeof(getconstants) == "function" then
		local ok, constants = pcall(getconstants, fn)
		if ok and type(constants) == "table" then
			for _, constant in ipairs(constants) do
				if packetFieldMatchesPacket(constant, packetName, packetId) then
					return true
				end
			end
		end
	end

	return false
end

function scanFunctionUpvaluesForPacket(results, seen, fn, packetName, packetId)
	if type(fn) ~= "function" then
		return
	end

	local mentionsPacket = functionMentionsPacket(fn, packetName, packetId)
	local function visitValue(value)
		if type(value) == "table" then
			local entry
			pcall(function()
				entry = value[packetName]
			end)
			addRuntimePacketCandidate(results, seen, entry)
			if mentionsPacket or tableLooksLikePacketEntry(value, packetName, packetId) then
				addRuntimePacketCandidate(results, seen, value)
			end
		end
	end

	if typeof(debug) == "table" and type(debug.getupvalue) == "function" then
		for index = 1, 80 do
			local ok, _, value = pcall(debug.getupvalue, fn, index)
			if not ok or value == nil then
				break
			end
			visitValue(value)
		end
	elseif typeof(getupvalues) == "function" then
		local ok, upvalues = pcall(getupvalues, fn)
		if ok and type(upvalues) == "table" then
			for _, value in pairs(upvalues) do
				visitValue(value)
			end
		end
	end
end

function addRuntimePacketCandidate(results, seen, candidate)
	if candidate == nil or seen[candidate] then
		return
	end
	local candidateType = type(candidate)
	if candidateType ~= "table" and candidateType ~= "function" then
		return
	end
	seen[candidate] = true
	table.insert(results, candidate)
end

function findRuntimePacketEntries(packetName)
	local now = os.clock()
	local cached = runtimePacketEntryCache[packetName]
	local cooldown = CONFIG.deepPacketDiscovery and CONFIG.packetDiscoveryCooldown or 999999
	if cached and now - cached.checkedAt < cooldown then
		return cached.entries
	end

	local results = {}
	local seen = {}
	local remote = getPacketRemote()
	local packetId = remote and remote:GetAttribute(packetName) or nil

	local packet = getPacketModule()
	if type(packet) == "table" then
		addRuntimePacketCandidate(results, seen, findPacketEntry(packet, packetName))
	end

	if CONFIG.deepPacketDiscovery == true and typeof(getgc) == "function" then
		local ok, objects = pcall(getgc, true)
		if ok and type(objects) == "table" then
			local scanned = 0
			for _, object in ipairs(objects) do
				scanned += 1
				if type(object) == "table" then
					local entry
					pcall(function()
						entry = object[packetName]
					end)
					addRuntimePacketCandidate(results, seen, entry)
					if tableLooksLikePacketEntry(object, packetName, packetId) then
						addRuntimePacketCandidate(results, seen, object)
					end
				elseif type(object) == "function" then
					scanFunctionUpvaluesForPacket(results, seen, object, packetName, packetId)
				end
				if scanned >= CONFIG.packetDiscoveryLimit then
					break
				end
			end
		end
	end

	runtimePacketEntryCache[packetName] = {
		checkedAt = now,
		entries = results,
	}
	return results
end

function fireRuntimePacketEntries(packetName, ...)
	local actions = 0
	for _, entry in ipairs(findRuntimePacketEntries(packetName)) do
		if tryPacketEntry(entry, ...) then
			actions += 1
		end
	end
	return actions > 0, actions
end

function sendPacket(packetName, ...)
	if not packetNameExists(packetName) then
		return false
	end

	local packet = getPacketModule()
	if type(packet) == "table" then
		local entry = packetEntryCache[packetName]
		if entry == nil then
			entry = findPacketEntry(packet, packetName)
			if entry == nil then
				entry = false
			end
			packetEntryCache[packetName] = entry
		end
		if entry == false then
			entry = nil
		end
		if tryPacketEntry(entry, ...) then
			return true
		end
		if fireRuntimePacketEntries(packetName, ...) then
			return true
		end

		for _, methodName in ipairs(packetSendMethodNames) do
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

	if fireRuntimePacketEntries(packetName, ...) then
		return true
	end

	return firePacketRemote(packetName, ...)
end

function sendExactPacket(packetName, ...)
	if not packetNameExists(packetName) then
		return false, 0
	end

	local actions = 0
	local runtimeTried = false
	local ok, count = firePacketObject(packetName, ...)
	if ok then
		actions += count or 1
	end

	local packet = getPacketModule()
	if type(packet) == "table" then
		local entry = packetEntryCache[packetName]
		if entry == nil then
			entry = findPacketEntry(packet, packetName)
			if entry == nil then
				entry = false
			end
			packetEntryCache[packetName] = entry
		end
		if entry ~= false and tryPacketEntry(entry, ...) then
			actions += 1
		end
		local runtimeOk, runtimeCount = fireRuntimePacketEntries(packetName, ...)
		runtimeTried = true
		if runtimeOk then
			actions += runtimeCount or 1
		end

		for _, methodName in ipairs(packetSendMethodNames) do
			if type(packet[methodName]) == "function" then
				if pcall(packet[methodName], packet, packetName, ...) then
					actions += 1
				end
				if pcall(packet[methodName], packetName, ...) then
					actions += 1
				end
			end
		end
	elseif type(packet) == "function" then
		if pcall(packet, packetName, ...) then
			actions += 1
		end
	end

	if not runtimeTried then
		local runtimeOk, runtimeCount = fireRuntimePacketEntries(packetName, ...)
		if runtimeOk then
			actions += runtimeCount or 1
		end
	end

	if firePacketRemote(packetName, ...) then
		actions += 1
	end

	return actions > 0, actions
end

function sendPacketArgVariants(packetName, variants)
	local actions = 0
	for _, args in ipairs(variants or {}) do
		local exactOk, count = sendExactPacket(packetName, unpackArgs(args))
		if exactOk then
			actions += count or 1
		elseif sendPacket(packetName, unpackArgs(args)) then
			actions += 1
		end
	end
	return actions > 0, actions
end

local cache = {
	seedFrames = {},
	gearFrames = {},
}
local nextDescendantRefreshAt = 0

function getCachedDescendants(key, root, maxAge)
	local now = os.clock()
	local atKey = key .. "At"
	local listKey = key .. "Descendants"
	maxAge = maxAge or CONFIG.cacheRefreshInterval

	if not root then
		cache[atKey] = now
		cache[listKey] = {}
		return cache[listKey]
	end

	if not cache[atKey] or now - cache[atKey] > maxAge then
		if cache[listKey] and now < nextDescendantRefreshAt then
			return cache[listKey]
		end
		nextDescendantRefreshAt = now + 0.35
		cache[atKey] = now
		cache[listKey] = root:GetDescendants()
	end

	return cache[listKey]
end

function maybeYieldScan(startedAt, budgetSeconds)
	if os.clock() - startedAt >= (budgetSeconds or 0.012) then
		task.wait()
		return os.clock()
	end
	return startedAt
end

function getMap()
	return workspace:FindFirstChild("Map")
end

function getGardens()
	return workspace:FindFirstChild("Gardens")
end

function getWildPetSpawns()
	local map = getMap()
	local direct = map and map:FindFirstChild("WildPetSpawns")
	if direct then
		return direct
	end

	for _, root in ipairs({ map, workspace }) do
		if root then
			local found = root:FindFirstChild("WildPetSpawns", true)
			if found then
				return found
			end
		end
	end

	return nil
end

function refreshBuyPetNamesFromWildSpawns()
	local wildPetSpawns = getWildPetSpawns()
	if not wildPetSpawns then
		return
	end

	for _, descendant in ipairs(wildPetSpawns:GetDescendants()) do
		local model
		if descendant:IsA("ProximityPrompt") and descendant.Parent and descendant:IsDescendantOf(workspace) then
			model = descendant:FindFirstAncestorWhichIsA("Model")
		elseif descendant:IsA("Model") and descendant:FindFirstChildWhichIsA("ProximityPrompt", true) then
			model = descendant
		end

		if model then
			local petName = getWildPetBaseName(model.Name)
			addUniqueName(buyPetNames, petName)
			addUniqueName(petNames, petName)
			notifyPetSpawn(petName)
		end
	end

	table.sort(buyPetNames)
	table.sort(petNames)
end

function valueMatchesLocalPlayer(value)
	if value == localPlayer then
		return true
	end

	if typeof(value) == "Instance" and value:IsA("Player") then
		return value == localPlayer
	end

	local text = tostring(value or "")
	return text == tostring(localPlayer.UserId) or string.lower(text) == string.lower(localPlayer.Name)
end

function plotBelongsToLocalPlayer(plot)
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

		local child = plot:FindFirstChild(key, true)
		if child and child:IsA("ValueBase") and valueMatchesLocalPlayer(child.Value) then
			return true
		end
	end

	return false
end

local ownGardenCache = {
	plots = {},
	roots = {},
	checkedAt = 0,
}

local fruitTargetCache = {
	targets = {},
	refreshedAt = 0,
	cursor = 1,
	rootCount = 0,
	noGainStreak = 0,
}

function invalidateOwnGardenCache()
	ownGardenCache.checkedAt = 0
	ownGardenCache.plots = {}
	cache.ownGardenDescendants = nil
	cache.ownGardenAt = nil
	fruitTargetCache.refreshedAt = 0
	fruitTargetCache.targets = {}
	fruitTargetCache.cursor = 1
	fruitTargetCache.noGainStreak = 0
end

function addUniqueInstance(list, instance)
	if not instance then
		return false
	end

	for _, existing in ipairs(list) do
		if existing == instance then
			return false
		end
	end

	table.insert(list, instance)
	return true
end

function plotHasLocalPlayerPlants(plot)
	local plants = plot and plot:FindFirstChild("Plants")
	if not plants then
		return false
	end

	local userPrefix = tostring(localPlayer.UserId) .. "_"
	for _, plant in ipairs(plants:GetChildren()) do
		if string.sub(plant.Name, 1, #userPrefix) == userPrefix then
			return true
		end
	end

	return false
end

function getPlotDistanceFromPlayer(plot)
	local root = getRoot()
	if not root or not plot then
		return math.huge
	end

	local part
	if plot:IsA("BasePart") then
		part = plot
	elseif plot:IsA("Model") or plot:IsA("Folder") then
		part = plot:FindFirstChildWhichIsA("BasePart", true)
	end
	if not part then
		return math.huge
	end

	return (root.Position - part.Position).Magnitude
end

function getOwnGardenPlots()
	local now = os.clock()
	if now - ownGardenCache.checkedAt < 5 and #ownGardenCache.plots > 0 then
		return ownGardenCache.plots
	end

	local gardens = getGardens()
	local plots = {}
	if not gardens then
		ownGardenCache.plots = plots
		ownGardenCache.checkedAt = now
		return plots
	end

	for _, plot in ipairs(gardens:GetChildren()) do
		if plotBelongsToLocalPlayer(plot) or plotHasLocalPlayerPlants(plot) then
			addUniqueInstance(plots, plot)
		end
	end

	if #plots == 0 then
		local closestPlot
		local closestDistance = math.huge
		for _, plot in ipairs(gardens:GetChildren()) do
			if plot:FindFirstChild("Plants") then
				local distance = getPlotDistanceFromPlayer(plot)
				if distance < closestDistance then
					closestPlot = plot
					closestDistance = distance
				end
			end
		end
		addUniqueInstance(plots, closestPlot)
	end

	ownGardenCache.plots = plots
	ownGardenCache.checkedAt = now
	return plots
end

function collectNamedDescendantRoots(root, names, results, limit)
	if not root then
		return
	end

	local wanted = {}
	for _, name in ipairs(names) do
		wanted[string.lower(name)] = true
	end

	for _, descendant in ipairs(root:GetDescendants()) do
		if wanted[string.lower(descendant.Name)] then
			addUniqueInstance(results, descendant)
			if #results >= (limit or 8) then
				return
			end
		end
	end
end

function getOwnGardenRoots()
	local now = os.clock()
	if now - ownGardenCache.checkedAt < 5 and #ownGardenCache.roots > 0 then
		return ownGardenCache.roots
	end

	local roots = {}

	local function addOwnPlot(plot)
		if not plot then
			return
		end

		local added = false
		local rootNames = { "Plants", "Fruits", "Fruit", "Crops", "Harvest", "Harvests", "Drops" }
		for _, name in ipairs(rootNames) do
			local child = plot:FindFirstChild(name)
			if child then
				added = addUniqueInstance(roots, child) or added
			end
		end

		if not added then
			local before = #roots
			collectNamedDescendantRoots(plot, rootNames, roots, 10)
			added = #roots > before
		end

		if not added then
			addUniqueInstance(roots, plot)
		end
	end

	for _, plot in ipairs(getOwnGardenPlots()) do
		addOwnPlot(plot)
	end

	if #roots == 0 then
		local gardens = getGardens()
		if not gardens then
			return roots
		end
		for _, plot in ipairs(gardens:GetChildren()) do
			if plot:FindFirstChild("Plants") or plot:FindFirstChild("Fruits") then
				addOwnPlot(plot)
			end
			if #roots >= 8 then
				break
			end
		end
	end

	ownGardenCache.roots = roots
	ownGardenCache.checkedAt = now
	return roots
end

local gardensForCache = getGardens()
if gardensForCache then
	gardensForCache.ChildAdded:Connect(invalidateOwnGardenCache)
	gardensForCache.ChildRemoved:Connect(invalidateOwnGardenCache)
end

local performanceRefreshQueued = false
function queuePerformanceRefresh(delaySeconds)
	if performanceRefreshQueued or not state.performanceMode then
		return
	end
	performanceRefreshQueued = true
	task.delay(delaySeconds or 1, function()
		performanceRefreshQueued = false
		if state.performanceMode and enablePerformanceMode then
			enablePerformanceMode()
		end
	end)
end

workspace.ChildAdded:Connect(function(child)
	if child.Name == "Gardens" then
		invalidateOwnGardenCache()
		child.ChildAdded:Connect(invalidateOwnGardenCache)
		child.ChildRemoved:Connect(invalidateOwnGardenCache)
		queuePerformanceRefresh(1)
	elseif child.Name == "Map" and state.performanceMode then
		queuePerformanceRefresh(1)
	end
end)

function textMatches(instance, terms)
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

function treeTextMatches(instance, terms, maxAncestors)
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

function getToolContainers()
	return {
		getCharacter(),
		localPlayer:FindFirstChildOfClass("Backpack"),
	}
end

function countInventoryTools()
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

function isHarvestInventoryItem(item)
	if not item then
		return false
	end
	if item:IsA("Tool") then
		return true
	end
	if item:IsA("Configuration") then
		return item:GetAttribute("HarvestedFruit") == true
			or item:GetAttribute("FruitProxy") == true
			or item:GetAttribute("Fruit") ~= nil
			or item:GetAttribute("FruitName") ~= nil
	end
	return false
end

function countHarvestInventoryItems()
	local count = 0
	for _, container in ipairs(getToolContainers()) do
		if container then
			for _, item in ipairs(container:GetChildren()) do
				if isHarvestInventoryItem(item) then
					count += 1
				end
			end
		end
	end
	return count
end

function guiShowsInventoryFull()
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

local inventoryCache = {
	items = 0,
	capacity = CONFIG.maxInventoryItems,
	full = false,
	guiFull = false,
	checkedAt = 0,
	guiCheckedAt = 0,
}

local currencyCache = {
	value = 0,
	checkedAt = 0,
}

function nameLooksLikeCurrency(name)
	local lowered = string.lower(tostring(name or ""))
	return string.find(lowered, "sheck", 1, true)
		or string.find(lowered, "money", 1, true)
		or string.find(lowered, "cash", 1, true)
		or string.find(lowered, "coin", 1, true)
		or string.find(lowered, "currency", 1, true)
end

function readCurrencyValueObject(root)
	if not root then
		return nil
	end

	for _, child in ipairs(root:GetChildren()) do
		if child:IsA("ValueBase") and nameLooksLikeCurrency(child.Name) then
			local amount = tonumber(child.Value)
			if amount then
				return amount
			end
		end
	end

	return nil
end

function readCurrencyFromGui()
	for _, descendant in ipairs(playerGui:GetDescendants()) do
		if descendant:IsA("TextLabel") or descendant:IsA("TextButton") or descendant:IsA("TextBox") then
			local ok, visible = pcall(function()
				return descendant.Visible
			end)
			if ok and visible then
				local text = tostring(descendant.Text or "")
				local lowered = string.lower(text .. " " .. descendant.Name)
				if string.find(lowered, "sheck", 1, true)
					or string.find(lowered, "$", 1, true)
					or string.find(lowered, "cash", 1, true)
					or string.find(lowered, "money", 1, true)
				then
					local amount = parseAmountText(text)
					if amount then
						return amount
					end
				end
			end
		end
	end
	return nil
end

function refreshCurrencyStats(force)
	local now = os.clock()
	if not force and now - currencyCache.checkedAt < 5 then
		return stats.sheckles
	end

	local amount = readCurrencyValueObject(localPlayer:FindFirstChild("leaderstats"))
		or readCurrencyValueObject(localPlayer)
		or readCurrencyFromGui()

	if amount then
		stats.sheckles = amount
		if stats.startSheckles == nil then
			stats.startSheckles = amount
		end
		stats.shecklesFarmed = math.max(stats.shecklesFarmed or 0, amount - (stats.startSheckles or amount), 0)
		currencyCache.value = amount
	end

	currencyCache.checkedAt = now
	return stats.sheckles
end

function getRuntimeText()
	local elapsed = math.floor(os.clock() - sessionStartedAt)
	local hours = math.floor(elapsed / 3600)
	local minutes = math.floor((elapsed % 3600) / 60)
	local seconds = elapsed % 60
	if hours > 0 then
		return ("%dh %dm %ds"):format(hours, minutes, seconds)
	end
	return ("%dm %ds"):format(minutes, seconds)
end

function buildStatsSnapshot()
	refreshCurrencyStats()
	local elapsedMinutes = math.max((os.clock() - sessionStartedAt) / 60, 0.01)
	local fruitRate = math.floor((stats.fruitCollected / elapsedMinutes) + 0.5)
	local freeSlots = math.max((stats.inventoryCapacity or CONFIG.maxInventoryItems) - (stats.inventoryItems or 0), 0)

	return {
		runtime = getRuntimeText(),
		enabled = countEnabledToggles(),
		sheckles = stats.sheckles or 0,
		shecklesFarmed = stats.shecklesFarmed or 0,
		fruitCollected = stats.fruitCollected,
		fruitRate = fruitRate,
		seedsBought = stats.seedsBought,
		gearBought = stats.gearBought,
		petsBought = stats.petsBought,
		petsSold = stats.petsSold,
		mailClaimed = stats.mailClaimed,
		mailChecks = stats.mailChecks,
		inventoryItems = stats.inventoryItems,
		inventoryCapacity = stats.inventoryCapacity,
		freeSlots = freeSlots,
		inventoryFull = stats.inventoryFull,
	}
end

function buildStatsWebhookDescription(snapshot)
	return table.concat({
		("Runtime: `%s`"):format(snapshot.runtime),
		("Sheckles: `%s`"):format(formatNumber(snapshot.sheckles)),
		("Sheckles farmed since start: `+%s`"):format(formatNumber(snapshot.shecklesFarmed)),
		("Fruit collected: `%s` (`%s/min`)"):format(formatNumber(snapshot.fruitCollected), formatNumber(snapshot.fruitRate)),
		("Bought: `%s` seeds | `%s` gear | `%s` pets"):format(formatNumber(snapshot.seedsBought), formatNumber(snapshot.gearBought), formatNumber(snapshot.petsBought)),
		("Mail: `%s` claimed across `%s` check(s)"):format(formatNumber(snapshot.mailClaimed), formatNumber(snapshot.mailChecks)),
		("Pets sold: `%s`"):format(formatNumber(snapshot.petsSold)),
		("Inventory: `%s/%s` (`%s` free)%s"):format(formatNumber(snapshot.inventoryItems), formatNumber(snapshot.inventoryCapacity), formatNumber(snapshot.freeSlots), snapshot.inventoryFull and " FULL" or ""),
		("Enabled systems: `%d`"):format(snapshot.enabled),
	}, "\n")
end

function sendStatsWebhook(force)
	if CONFIG.webhookUrl == "" then
		return false
	end

	local now = os.clock()
	if not force and now - lastStatsWebhookAt < CONFIG.statsWebhookInterval then
		return false
	end

	local snapshot = buildStatsSnapshot()
	local sent = sendWebhook("Garden Tools Stats", buildStatsWebhookDescription(snapshot), force and "stats:manual" or "stats:auto")
	if sent then
		lastStatsWebhookAt = now
	end
	return sent
end

function refreshInventoryStats(force)
	local now = os.clock()
	if not force and now - inventoryCache.checkedAt < CONFIG.inventoryRefreshInterval then
		stats.inventoryItems = inventoryCache.items
		stats.inventoryCapacity = inventoryCache.capacity
		stats.inventoryFull = inventoryCache.full
		return stats.inventoryFull, stats.inventoryItems, stats.inventoryCapacity
	end

	local count = countInventoryTools()
	if type(getSellableFruitTools) == "function" then
		count = #getSellableFruitTools(force == true)
	end
	local capacity = CONFIG.maxInventoryItems
	local nearCapacity = count >= math.max(capacity - 15, 1)
	if count < math.max(capacity - 20, 1) then
		inventoryCache.guiFull = false
	elseif (force or nearCapacity or inventoryCache.guiFull) and (force or now - inventoryCache.guiCheckedAt >= CONFIG.guiInventoryRefreshInterval) then
		inventoryCache.guiCheckedAt = now
		inventoryCache.guiFull = guiShowsInventoryFull()
	end
	local full = count >= capacity or inventoryCache.guiFull

	inventoryCache.items = count
	inventoryCache.capacity = capacity
	inventoryCache.full = full
	inventoryCache.checkedAt = now
	stats.inventoryItems = count
	stats.inventoryCapacity = capacity
	stats.inventoryFull = full

	return full, count, capacity
end

function purchaseChanged(beforeInventoryCount, beforeSheckles)
	task.wait(0.25)
	local afterInventoryCount = countInventoryTools()
	local afterSheckles = refreshCurrencyStats(true)
	return (afterInventoryCount and beforeInventoryCount and afterInventoryCount > beforeInventoryCount)
		or (afterSheckles and beforeSheckles and afterSheckles < beforeSheckles),
		afterInventoryCount,
		afterSheckles
end

function waitForPurchaseChanged(beforeInventoryCount, beforeSheckles, timeoutSeconds)
	local deadline = os.clock() + (timeoutSeconds or 2.5)
	local changed, afterInventoryCount, afterSheckles = purchaseChanged(beforeInventoryCount, beforeSheckles)
	while not changed and os.clock() < deadline do
		task.wait(0.25)
		afterInventoryCount = countInventoryTools()
		afterSheckles = refreshCurrencyStats(true)
		changed = (afterInventoryCount and beforeInventoryCount and afterInventoryCount > beforeInventoryCount)
			or (afterSheckles and beforeSheckles and afterSheckles < beforeSheckles)
	end
	return changed, afterInventoryCount, afterSheckles
end

function shouldPauseFruitCollection()
	if not (state.sellWhenFull or state.autoSell) then
		return false
	end

	local full = refreshInventoryStats(false)
	if full ~= true then
		return false
	end

	invalidateSellableInventoryCache()
	return #getSellableFruitTools(true) > 0
end

function updateStatsUI()
	local now = os.clock()
	if now - lastStatsUIUpdateAt < 1.5 then
		return
	end
	lastStatsUIUpdateAt = now
	if pendingStatusMessage and statusValue then
		statusValue.Value = pendingStatusMessage
		pendingStatusMessage = nil
		lastStatusSetAt = now
	end

	local snapshot = buildStatsSnapshot()

	for key, label in pairs(statsLabels) do
		if label and label.Parent then
			if key == "status" then
				label.Text = ("Run: %s | Enabled: %d"):format(snapshot.runtime, snapshot.enabled)
			elseif key == "systems" then
				label.Text = ("Sheckles: %s"):format(formatNumber(snapshot.sheckles))
			elseif key == "inventory" then
				label.Text = ("Farmed this run: +%s sheckles"):format(formatNumber(snapshot.shecklesFarmed))
			elseif key == "collect" then
				label.Text = ("Fruit: %s total | %s/min"):format(formatNumber(snapshot.fruitCollected), formatNumber(snapshot.fruitRate))
			elseif key == "mail" then
				label.Text = ("Mail: %s claimed | %s checks"):format(formatNumber(snapshot.mailClaimed), formatNumber(snapshot.mailChecks))
			elseif key == "shops" then
				label.Text = ("Bought: %s seeds | %s gear | %s pets | Sold pets: %s"):format(formatNumber(snapshot.seedsBought), formatNumber(snapshot.gearBought), formatNumber(snapshot.petsBought), formatNumber(snapshot.petsSold))
			elseif key == "limits" then
				label.Text = ("Inv: %s/%s (%s free)%s | Mail: %s/%s"):format(formatNumber(snapshot.inventoryItems), formatNumber(snapshot.inventoryCapacity), formatNumber(snapshot.freeSlots), snapshot.inventoryFull and " FULL" or "", formatNumber(snapshot.mailClaimed), formatNumber(snapshot.mailChecks))
			end
		end
	end
end

function getSeedRarity(seedName)
	return seedPriority[seedName] or 0
end

function readNumericMetadata(instance, keys, maxAncestors)
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

function getSortedSeedList(list)
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

function getInstanceTextBlob(instance, maxAncestors)
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

function getFruitWeight(instance)
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

function getFruitRarity(instance)
	return readNumericMetadata(instance, { "Rarity", "RarityValue", "Tier", "TierValue", "Priority", "Value" }, 5)
end

function getFruitMutationValue(instance)
	return readNumericMetadata(instance, { "MutationValue", "MutationMultiplier", "MutationPrice", "MutationWorth", "VariantValue", "VariantMultiplier" }, 5)
end

function getPromptDistance(prompt)
	local root = getRoot()
	local part = getPromptPart and getPromptPart(prompt)
	if not root or not part then
		return math.huge
	end
	return (root.Position - part.Position).Magnitude
end

function isHarvestPrompt(prompt)
	if not prompt or not prompt:IsA("ProximityPrompt") then
		return false
	end

	if prompt.Name == "StealPrompt" or prompt.ActionText == "Steal" then
		return false
	end

	return prompt.Name == "HarvestPrompt"
		or treeTextMatches(prompt, { "harvestprompt", "collect", "harvest", "pick", "fruit" }, 3)
end

function isUsableHarvestPrompt(prompt)
	if not isHarvestPrompt(prompt) then
		return false
	end

	local ok, enabled = pcall(function()
		return prompt.Enabled
	end)

	return not ok or enabled
end

function getCollectFruitTarget(prompt)
	local current = prompt and prompt.Parent

	while current and current ~= workspace do
		if current.Parent and current.Parent.Name == "Fruits" then
			return current
		end
		if current.Parent and current.Parent.Name == "Plants" then
			return current
		end
		current = current.Parent
	end

	return prompt and prompt.Parent
end

function getFruitPlantTarget(fruit)
	local current = fruit
	while current and current ~= workspace do
		if current.Parent and current.Parent.Name == "Fruits" then
			return current.Parent.Parent
		end
		current = current.Parent
	end
	return nil
end

function collectFruitPacket(target, heavy, prompt)
	if not target then
		return false
	end

	local fruit = target
	local current = target
	while current and current ~= workspace do
		if current.Parent and current.Parent.Name == "Fruits" then
			fruit = current
			break
		end
		current = current.Parent
	end

	local plant = getFruitPlantTarget(fruit)
	local fruitId = getInstancePacketId(fruit)
	local plantId = getInstancePacketId(plant)
	local instanceVariants = {
		{ fruit },
	}
	if sendRawInstancePacket("CollectFruit", fruit) then
		return true
	end
	if prompt and sendRawInstancePacket("CollectFruit", prompt) then
		return true
	end
	if target ~= fruit and sendRawInstancePacket("CollectFruit", target) then
		return true
	end
	if plant and sendRawInstancePacket("CollectFruit", plant) then
		return true
	end

	if target ~= fruit then
		table.insert(instanceVariants, { target })
	end
	if prompt then
		table.insert(instanceVariants, { prompt })
	end
	if plant then
		table.insert(instanceVariants, { plant })
	end
	local typedOk = sendTypedPacketArgVariants("CollectFruit", { "Instance" }, instanceVariants)
	if typedOk then
		return true
	end

	local variants = {
		{ fruit },
		{ fruit.Name },
	}
	if fruitId ~= nil then
		table.insert(variants, { fruitId })
		table.insert(variants, { { Id = fruitId } })
		table.insert(variants, { { FruitId = fruitId } })
		table.insert(variants, { { UID = fruitId } })
	end
	if target ~= fruit then
		table.insert(variants, { target })
		table.insert(variants, { target.Name })
	end
	if plant then
		table.insert(variants, { plant, fruit })
		table.insert(variants, { plant.Name, fruit.Name })
		table.insert(variants, { plant.Name, fruit })
		table.insert(variants, { plant, fruit.Name })
		if plantId ~= nil then
			table.insert(variants, { plantId, fruitId or fruit.Name })
			table.insert(variants, { { PlantId = plantId, FruitId = fruitId or fruit.Name } })
		end
	end

	local ok = sendPacketArgVariants("CollectFruit", variants)
	if ok then
		return true
	end

	if not heavy then
		return false
	end

	if plant and sendExactPacket("CollectFruit", plant, fruit) then
		return true
	end

	if plant and sendExactPacket("CollectFruit", plant.Name, fruit and fruit.Name) then
		return true
	end

	if plant and sendExactPacket("CollectFruit", plant.Name, fruit) then
		return true
	end

	if fruit and sendPacket("CollectFruit", fruit.Name) then
		return true
	end

	if target ~= fruit and sendPacket("CollectFruit", target) then
		return true
	end

	if target ~= fruit and target and sendPacket("CollectFruit", target.Name) then
		return true
	end

	if plant and sendPacket("CollectFruit", plant, fruit) then
		return true
	end

	if plant and sendPacket("CollectFruit", plant.Name, fruit and fruit.Name) then
		return true
	end

	if plant and sendPacket("CollectFruit", plant.Name, fruit) then
		return true
	end

	return false
end

function collectionTookEffect(target, beforeInventoryCount)
	task.wait(0.25)

	if target and not target.Parent then
		return true
	end

	if target and target.Parent and not target:IsDescendantOf(workspace) then
		return true
	end

	local afterInventoryCount = countHarvestInventoryItems()
	return beforeInventoryCount ~= nil and afterInventoryCount > beforeInventoryCount
end

function triggerHarvestPrompt(prompt)
	if not isUsableHarvestPrompt(prompt) then
		return false
	end

	if typeof(fireproximityprompt) == "function" then
		local ok = pcall(fireproximityprompt, prompt)
			or pcall(fireproximityprompt, prompt, 0)
			or pcall(fireproximityprompt, prompt, 1, true)
		if ok then
			return true
		end
	end

	local began = pcall(function()
		prompt:InputHoldBegin()
	end)
	task.wait(0.03)
	local ended = pcall(function()
		prompt:InputHoldEnd()
	end)
	return began or ended
end

function triggerAnyPrompt(prompt)
	if not prompt or not prompt:IsA("ProximityPrompt") then
		return false
	end

	local ok, enabled = pcall(function()
		return prompt.Enabled
	end)
	if ok and enabled == false then
		return false
	end

	local holdSeconds = 0.05
	pcall(function()
		holdSeconds = math.clamp(tonumber(prompt.HoldDuration) or 0, 0, 2) + 0.05
	end)
	local fired = false
	if typeof(fireproximityprompt) == "function" then
		for _, args in ipairs({
			{ prompt, holdSeconds, true },
			{ prompt, math.max(1, holdSeconds), true },
			{ prompt, 1, true },
			{ prompt, 0, true },
			{ prompt },
		}) do
			local ok = pcall(fireproximityprompt, unpackArgs(args))
			fired = fired or ok
			task.wait(0.04)
		end
	end

	local began = pcall(function()
		prompt:InputHoldBegin()
	end)
	task.wait(holdSeconds)
	local ended = pcall(function()
		prompt:InputHoldEnd()
	end)
	return fired or began or ended
end

function getTargetPart(target)
	if not target then
		return nil
	end
	if target:IsA("BasePart") then
		return target
	end
	if target:IsA("Model") then
		return target.PrimaryPart
			or target:FindFirstChild("HumanoidRootPart", true)
			or target:FindFirstChildWhichIsA("BasePart", true)
	end
	if target:IsA("Folder") then
		return target:FindFirstChildWhichIsA("BasePart", true)
	end
	return nil
end

function collectPrompt(prompt)
	local target = getCollectFruitTarget(prompt)
	local beforeInventoryCount = countHarvestInventoryItems()
	local fired = false
	if prompt then
		fired = triggerHarvestPrompt(prompt) or fired
		if collectionTookEffect(target or prompt, beforeInventoryCount) then
			return true
		end
	end
	if target ~= nil then
		fired = collectFruitPacket(target, true, prompt) or fired
		if collectionTookEffect(target or prompt, beforeInventoryCount) then
			return true
		end
	end

	return false
end

function getHarvestPromptInTarget(target)
	if not target then
		return nil
	end

	local cached = harvestPromptCache[target]
	if cached ~= nil then
		if cached == false or (cached.Parent and cached:IsDescendantOf(workspace)) then
			return cached ~= false and cached or nil
		end
		harvestPromptCache[target] = nil
	end

	if target:IsA("ProximityPrompt") and isUsableHarvestPrompt(target) then
		harvestPromptCache[target] = target
		return target
	end

	if target:IsA("Model") or target:IsA("BasePart") or target:IsA("Folder") then
		for _, descendant in ipairs(target:GetDescendants()) do
			if isUsableHarvestPrompt(descendant) then
				harvestPromptCache[target] = descendant
				return descendant
			end
		end
	end

	harvestPromptCache[target] = false
	return nil
end

function getTargetDistance(target)
	local root = getRoot()
	local part = target and getTargetPart(target)
	if not root or not part then
		return math.huge
	end
	return (root.Position - part.Position).Magnitude
end

function getFruitPriority(instance)
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

	return priority
end

function isLiveFruitEntry(entry)
	if not entry then
		return false
	end

	local target = entry.target or entry.prompt
	if not target or not target.Parent then
		return false
	end

	if not target:IsDescendantOf(workspace) then
		return false
	end

	if entry.prompt and (not entry.prompt.Parent or not isUsableHarvestPrompt(entry.prompt)) then
		return false
	end

	return true
end

function addFruitTarget(targets, seenTargets, prompt, target)
	if prompt and not isUsableHarvestPrompt(prompt) then
		return
	end

	target = target or getCollectFruitTarget(prompt)
	if not target then
		return
	end

	local key = target or prompt
	if seenTargets[key] then
		return
	end

	seenTargets[key] = true
	table.insert(targets, {
		prompt = prompt,
		target = target,
		priority = getFruitPriority(target),
	})
end

function addPromptFromHarvestPart(targets, seenTargets, container)
	if not container then
		return
	end

	local harvestPart = container:FindFirstChild("HarvestPart")
	local prompt = harvestPart and harvestPart:FindFirstChild("HarvestPrompt")
	if prompt and isUsableHarvestPrompt(prompt) then
		addFruitTarget(targets, seenTargets, prompt, container)
	end
end

function addGardenPlantHarvestTargets(targets, seenTargets, plot)
	local plants = plot and plot:FindFirstChild("Plants")
	if not plants then
		return
	end

	local scanStartedAt = os.clock()
	for _, plant in ipairs(plants:GetChildren()) do
		scanStartedAt = maybeYieldScan(scanStartedAt, 0.012)
		if #targets >= CONFIG.maxFruitTargetsCached then
			return
		end

		addPromptFromHarvestPart(targets, seenTargets, plant)

		local fruits = plant:FindFirstChild("Fruits")
		if fruits then
			for _, fruit in ipairs(fruits:GetChildren()) do
				if #targets >= CONFIG.maxFruitTargetsCached then
					return
				end
				addPromptFromHarvestPart(targets, seenTargets, fruit)
			end
		end
	end
end

function isFruitModelCandidate(instance)
	if not instance or not instance.Parent then
		return false
	end
	if not (instance:IsA("Model") or instance:IsA("Folder") or instance:IsA("BasePart")) then
		return false
	end
	local parent = instance.Parent
	if parent and parent.Name == "Fruits" then
		return true
	end
	local pathText = string.lower(getObjectPath(instance))
	return string.find(pathText, ".fruits.", 1, true) ~= nil
		or string.find(pathText, ".fruit.", 1, true) ~= nil
end

function rebuildFruitTargetCache(roots, forceDescendantRefresh)
	local targets = {}
	local seenTargets = {}

	for _, plot in ipairs(getOwnGardenPlots()) do
		addGardenPlantHarvestTargets(targets, seenTargets, plot)
	end

	for index, root in ipairs(roots) do
		if not root then
			continue
		end

		local scanned = 0
		local scanStartedAt = os.clock()
		if forceDescendantRefresh then
			cache["fruitFast" .. index .. "At"] = nil
		end
		local descendants = getCachedDescendants("fruitFast" .. index, root, CONFIG.fruitCacheRefreshInterval)
		for _, descendant in ipairs(descendants) do
			scanStartedAt = maybeYieldScan(scanStartedAt, 0.01)
			if #targets >= CONFIG.maxFruitTargetsCached then
				break
			end

			scanned += 1
			if scanned > CONFIG.maxFruitScanPerRoot then
				break
			end

			if isUsableHarvestPrompt(descendant) then
				addFruitTarget(targets, seenTargets, descendant, getCollectFruitTarget(descendant))
			elseif isFruitModelCandidate(descendant) then
				addFruitTarget(targets, seenTargets, nil, descendant)
			end
		end
	end

	table.sort(targets, function(left, right)
		if left.priority ~= right.priority then
			return left.priority > right.priority
		end
		return getTargetDistance(left.target) < getTargetDistance(right.target)
	end)

	fruitTargetCache.targets = targets
	fruitTargetCache.refreshedAt = os.clock()
	fruitTargetCache.cursor = 1
	fruitTargetCache.rootCount = #roots
	return targets
end

function getFruitTargetBatch(roots)
	local now = os.clock()
	local targets = fruitTargetCache.targets
	if #targets == 0
		or now - fruitTargetCache.refreshedAt > CONFIG.fruitCacheRefreshInterval
		or fruitTargetCache.rootCount ~= #roots
	then
		targets = rebuildFruitTargetCache(roots)
	end

	local batch = {}
	local checked = 0
	while #batch < CONFIG.maxFruitCollectPerTick and checked < #targets do
		if fruitTargetCache.cursor > #targets then
			fruitTargetCache.cursor = 1
		end

		local entry = targets[fruitTargetCache.cursor]
		fruitTargetCache.cursor += 1
		checked += 1

		if isLiveFruitEntry(entry) then
			table.insert(batch, entry)
		end
	end

	if #batch == 0 and #targets > 0 then
		targets = rebuildFruitTargetCache(roots, true)
		for index, entry in ipairs(targets) do
			if index > CONFIG.maxFruitCollectPerTick then
				break
			end
			if isLiveFruitEntry(entry) then
				table.insert(batch, entry)
			end
		end
	end

	return batch, #targets
end

function pruneFruitTargetCache()
	local live = {}
	for _, entry in ipairs(fruitTargetCache.targets) do
		if isLiveFruitEntry(entry) then
			table.insert(live, entry)
		end
	end

	fruitTargetCache.targets = live
	if fruitTargetCache.cursor > #live then
		fruitTargetCache.cursor = 1
	end
end

function collectFruitEntryFast(entry, heavy, verifyEach)
	if not isLiveFruitEntry(entry) then
		return false, false
	end
	if verifyEach == nil then
		verifyEach = true
	end

	local target = entry.target
	local prompt = entry.prompt

	local beforeInventoryCount = countHarvestInventoryItems()
	local fired = false
	if prompt then
		fired = triggerHarvestPrompt(prompt) or fired
		if verifyEach and collectionTookEffect(target or prompt, beforeInventoryCount) then
			return true, true
		end
	end
	if target then
		fired = collectFruitPacket(target, true, prompt) or fired
		if verifyEach and collectionTookEffect(target or prompt, beforeInventoryCount) then
			return true, true
		end
	end

	if not verifyEach then
		return false, fired
	end

	return false, fired
end

function sellSucceeded(beforeInventoryCount, beforeSheckles)
	local currentInventoryCount = type(getSellableFruitTools) == "function" and #getSellableFruitTools(true) or countInventoryTools()
	local currentSheckles = refreshCurrencyStats(true)
	return currentInventoryCount < beforeInventoryCount
		or (currentSheckles and beforeSheckles and currentSheckles > beforeSheckles),
		currentInventoryCount,
		currentSheckles
end

function getToolPacketId(tool)
	return getInstancePacketId(tool)
end

function sellToolByRemote(tool)
	if not tool then
		return false
	end

	local id = getToolPacketId(tool)
	local variants = {
		{ tool },
		{ tool.Name },
	}
	if id ~= nil then
		table.insert(variants, 1, { id })
		table.insert(variants, { { Id = id } })
		table.insert(variants, { { ItemId = id } })
		table.insert(variants, { { FruitId = id } })
		table.insert(variants, { { UID = id } })
		table.insert(variants, { id, tool.Name })
		table.insert(variants, { tool.Name, id })
	end

	local soldItem = sendPacketArgVariants("SellItem", variants)
	local soldFruit = sendPacketArgVariants("SellFruit", variants)
	return soldItem or soldFruit
end

function sellInventoryByRemote(sellableTools, individualFallback)
	if not individualFallback then
		if sendExactPacket("SellAll") then
			return 1
		end
		local ok, count = sendPacketArgVariants("SellAll", {
			{ "Fruit" },
			{ { Type = "Fruit" } },
		})
		return ok and (count or 1) or 0
	end

	local actions = 0
	for index, tool in ipairs(sellableTools or {}) do
		if index > 12 then
			break
		end
		if sellToolByRemote(tool) then
			actions += 1
		end
	end
	return actions
end

function collectFruit()
	if not isEnabled("fruitCollector") then
		return
	end

	if state.sellWhenFull or state.autoSell then
		invalidateSellableInventoryCache()
		refreshInventoryStats(true)
	end
	if state.performanceMode then
		restoreOwnGardenAutomationPrompts()
	end

	if shouldPauseFruitCollection() then
		stats.collectSkippedFull += 1
		updateStatsUI()
		setStatus(("Fruit collector: inventory full (%d/%d), still scanning"):format(stats.inventoryItems, stats.inventoryCapacity))
	end

	local roots = getOwnGardenRoots()

	if #roots == 0 then
		setStatus("Fruit collector: no owned garden found")
		return
	end

	local targets, totalCached = getFruitTargetBatch(roots)

	if #targets == 0 then
		fruitTargetCache.refreshedAt = 0
		targets = rebuildFruitTargetCache(roots, true)
		totalCached = #targets
	end

	if #targets == 0 then
		updateStatsUI()
		setStatus(("Fruit collector: no harvest targets found (%d root(s))"):format(#roots))
		return
	end

	local beforeInventoryCount = countHarvestInventoryItems()
	local fired = 0
	local fallback = 0
	local fallbackLimit = CONFIG.maxFruitPromptFallbackPerTick
	if fruitTargetCache.noGainStreak >= 1 then
		fallbackLimit = math.min(math.ceil(CONFIG.maxFruitCollectPerTick / 2), fallbackLimit + 10)
	end
	if fruitTargetCache.noGainStreak >= 2 then
		fallbackLimit = CONFIG.maxFruitCollectPerTick
	end

	local heavyFallback = fruitTargetCache.noGainStreak >= 1
	local verifyEachHarvest = fruitTargetCache.noGainStreak >= 2
	local failedRemoteHarvests = 0
	local attemptedHarvests = 0
	for index, entry in ipairs(targets) do
		if not isEnabled("fruitCollector") then
			return
		end
		if shouldPauseFruitCollection() then
			stats.collectSkippedFull += 1
			if index % 15 == 0 then
				setStatus(("Fruit collector: sell needed (%d/%d), still running"):format(stats.inventoryItems, stats.inventoryCapacity))
			end
		end

		if fallback < fallbackLimit and isLiveFruitEntry(entry) and entry.target then
			local harvested, attempted = collectFruitEntryFast(entry, heavyFallback, verifyEachHarvest)
			if attempted then
				attemptedHarvests += 1
			end
			if harvested or (attempted and not verifyEachHarvest) then
				fallback += 1
				fired += 1
				failedRemoteHarvests = 0
			elseif attempted then
				fruitTargetCache.refreshedAt = 0
			else
				failedRemoteHarvests += 1
				fruitTargetCache.refreshedAt = 0
			end
		end

		if index % 15 == 0 then
			task.wait()
		end
	end

	task.wait(0.04)
	local afterInventoryCount = countHarvestInventoryItems()
	local gained = math.max((afterInventoryCount or 0) - (beforeInventoryCount or 0), 0)
	stats.fruitCollected += gained
	stats.fruitTargetsChecked += totalCached
	if gained > 0 then
		invalidateSellableInventoryCache()
		fruitTargetCache.noGainStreak = 0
	else
		fruitTargetCache.noGainStreak = math.min(fruitTargetCache.noGainStreak + 1, 3)
	end
	if failedRemoteHarvests > 0 then
		fruitTargetCache.refreshedAt = 0
	end
	pruneFruitTargetCache()
	refreshInventoryStats()
	updateStatsUI()
	if fired == 0 and fallback == 0 and attemptedHarvests == 0 then
		fruitTargetCache.refreshedAt = 0
		setStatus(("Fruit collector: found %d target(s), no valid harvest attempt"):format(totalCached))
	elseif gained == 0 and attemptedHarvests > 0 then
		setStatus(("Fruit collector: attempted %d/%d target(s), waiting for inventory update"):format(attemptedHarvests, totalCached))
	else
		setStatus(("Fruit collector: harvested %d/%d, inventory +%d"):format(math.max(fallback, gained), #targets, gained))
	end
end

function getSelectedSeedList()
	local selected = {}
	local seen = {}

	for _, seedName in ipairs(seedNames) do
		if selectedSeeds[seedName] then
			seen[seedName] = true
			table.insert(selected, seedName)
		end
	end

	for seedName, enabled in pairs(selectedSeeds) do
		if enabled and not seen[seedName] then
			addUniqueName(seedNames, seedName)
			seedPriority[seedName] = seedPriority[seedName] or getSeedMetadataValue(seedName)
			table.insert(selected, seedName)
		end
	end

	return getSortedSeedList(selected)
end

isInventorySeedTool = function(item)
	if not item or not item:IsA("Tool") then
		return false
	end

	local name = string.lower(item.Name)
	local compact = compactName(item.Name)
	for _, word in ipairs({ "kg", " lb", "fruit", "harvest", "picked", "mutation", "rainbow", "golden" }) do
		if string.find(name, word, 1, true) then
			return false
		end
	end

	if string.find(name, "seed", 1, true) then
		return true
	end

	for _, key in ipairs({ "Seed", "SeedName", "ItemName", "Name" }) do
		local ok, attribute = pcall(function()
			return item:GetAttribute(key)
		end)
		if ok and attribute ~= nil and tostring(attribute) ~= "" then
			local value = tostring(attribute)
			if string.find(string.lower(value), "seed", 1, true) then
				return true
			end
			for _, seedName in ipairs(seedNames) do
				local seedCompact = compactName(seedName)
				if seedCompact ~= "" and string.find(compactName(value), seedCompact, 1, true) then
					return true
				end
			end
		end

		local child = item:FindFirstChild(key)
		if child and child:IsA("ValueBase") and child.Value ~= nil then
			local value = tostring(child.Value)
			if string.find(string.lower(value), "seed", 1, true) then
				return true
			end
		end
	end

	for _, seedName in ipairs(seedNames) do
		local seedCompact = compactName(seedName)
		if string.find(name, string.lower(seedName), 1, true)
			or (seedCompact ~= "" and string.find(compact, seedCompact, 1, true))
			or (seedCompact ~= "" and string.find(compact, seedCompact .. "seed", 1, true))
		then
			return true
		end
	end

	return false
end

function toolHasValue(item, keys)
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

function toolNameMatchesList(item, list)
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

function isKnownGearTool(item)
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

function isKnownPetTool(item)
	if not item or not item:IsA("Tool") then
		return false
	end

	if item:GetAttribute("Pet") or item:GetAttribute("PetName") then
		return true
	end

	if toolNameMatchesList(item, petNames) or toolNameMatchesList(item, buyPetNames) then
		return true
	end

	local name = string.lower(item.Name)
	return string.find(name, "pet", 1, true) ~= nil
		or string.find(name, "egg", 1, true) ~= nil
end

function isLikelyFruitTool(item)
	if not item
		or not (item:IsA("Tool") or item:IsA("Configuration"))
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
		or toolNameMatchesList(item, seedNames)
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

local sellableInventoryCache = {
	tools = {},
	count = 0,
	checkedAt = 0,
	dirty = true,
}

function invalidateSellableInventoryCache()
	sellableInventoryCache.dirty = true
end

function scanSellableFruitTools()
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

function getSellableFruitTools(force)
	local now = os.clock()
	if not force
		and not sellableInventoryCache.dirty
		and now - sellableInventoryCache.checkedAt < 1.0
	then
		return sellableInventoryCache.tools
	end

	local tools = scanSellableFruitTools()
	sellableInventoryCache.tools = tools
	sellableInventoryCache.count = #tools
	sellableInventoryCache.checkedAt = now
	sellableInventoryCache.dirty = false
	return tools
end

function hasSellableFruitTools()
	return #getSellableFruitTools(false) > 0
end

function getSelectedGearList()
	local selected = {}
	local seen = {}

	for _, gearName in ipairs(gearNames) do
		if selectedGears[gearName] then
			seen[gearName] = true
			table.insert(selected, gearName)
		end
	end

	for gearName, enabled in pairs(selectedGears) do
		if enabled and not seen[gearName] then
			addUniqueName(gearNames, gearName)
			table.insert(selected, gearName)
		end
	end

	table.sort(gearNames)
	table.sort(selected)
	return selected
end

function getSeedFrame(seedName)
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

function getGearFrame(gearName)
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

function getSelectedPetList()
	local selected = {}
	local seen = {}

	for _, petName in ipairs(petNames) do
		if selectedPets[petName] then
			seen[petName] = true
			table.insert(selected, petName)
		end
	end
	for petName, enabled in pairs(selectedPets) do
		if enabled and petName and petName ~= "" and not seen[petName] then
			seen[petName] = true
			table.insert(selected, petName)
		end
	end

	return selected
end

function getAvailableBuyPetMap()
	local available = {}
	local wildPetSpawns = getWildPetSpawns()
	if not wildPetSpawns then
		return available
	end

	for _, descendant in ipairs(getCachedDescendants("wildPets", wildPetSpawns, 0.5)) do
		if descendant:IsA("ProximityPrompt") and descendant.Parent and descendant:IsDescendantOf(workspace) then
			local model = descendant:FindFirstAncestorWhichIsA("Model")
			if model and not petSpawnHandled(model, descendant) and isPetBuyPrompt(descendant) then
				local baseName = getWildPetBaseName(model.Name)
				if baseName ~= "" then
					available[baseName] = true
				end
			end
		end
	end

	return available
end

function petIsAvailableForBuy(petName, available)
	if type(available) ~= "table" then
		return false
	end
	for availableName in pairs(available) do
		if petNameMatchesSelection(availableName, petName, nil, nil) then
			return true
		end
	end
	return false
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

function purchaseSeedRemote(seedName)
	local variants = {
		seedName,
		string.gsub(seedName, "%s+", "_"),
		string.gsub(seedName, "%s+", ""),
	}
	local bought = 0

	for repeatIndex = 1, CONFIG.seedBuyRemoteRepeats do
		for _, variant in ipairs(variants) do
			if sendTypedPacketExact("PurchaseSeed", { "String" }, variant) then
				bought += 1
			end

			if sendPacket("PurchaseSeed", variant) then
				bought += 1
			end

			if sendPacket("PurchaseSeed", variant, 1) then
				bought += 1
			end
		end

		task.wait()
	end

	return bought > 0, bought
end

performanceState = {
	optimized = setmetatable({}, { __mode = "k" }),
	hidden = setmetatable({}, { __mode = "k" }),
	watcherConnected = false,
	queue = {},
	queueHead = 1,
	queueRunning = false,
	fullScanDone = false,
	lastTreeScanAt = 0,
	lastGardenHideAt = 0,
}

function isLaggyEffectInstance(instance)
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

function disableLaggyEffect(instance)
	local changed = 0
	if not instance or performanceState.optimized[instance] then
		return changed
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
		changed = 1
	elseif instance:IsA("PostEffect")
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
		changed = 1
	end

	return changed
end

function getGardenPlotForInstance(instance)
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

function gardenPlotIsOwn(plot)
	if not plot then
		return false
	end

	if plotBelongsToLocalPlayer(plot) then
		return true
	end

	local plants = plot:FindFirstChild("Plants")
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

function isOwnPlantVisual(instance, plot)
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

function hidePerformanceTree(instance, hidePrompts)
	return hidePerformanceVisual(instance, hidePrompts)
end

function hasAutomationPrompt(instance)
	if not instance then
		return false
	end

	if instance:IsA("ProximityPrompt") then
		return true
	end

	return instance:FindFirstChildWhichIsA("ProximityPrompt", true) ~= nil
end

function hidePerformanceVisual(instance, hidePrompts)
	if not instance or performanceState.hidden[instance] then
		return 0
	end

	local changed = 0
	changed += disableLaggyEffect(instance)
	if instance:IsA("ProximityPrompt") then
		return changed
	end

	if instance:IsA("BasePart") then
		performanceState.hidden[instance] = true
		pcall(function()
			instance.LocalTransparencyModifier = 1
			instance.CastShadow = false
		end)
		changed = 1
	elseif instance:IsA("Decal") or instance:IsA("Texture") then
		performanceState.hidden[instance] = true
		pcall(function()
			instance.Transparency = 1
		end)
		changed = 1
	elseif instance:IsA("BillboardGui")
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
		changed = 1
	end

	return changed
end

function applyPerformanceGardenHiding(instance)
	local plot = getGardenPlotForInstance(instance)
	if not plot then
		return 0
	end

	if gardenPlotIsOwn(plot) then
		if isOwnPlantVisual(instance, plot) then
			return hidePerformanceTree(instance, false)
		end
		return 0
	end

	return hidePerformanceTree(instance, true)
end

function hidePerformanceGardenPlot(plot)
	if not plot then
		return 0
	end

	local changed = 0
	local ownPlot = gardenPlotIsOwn(plot)
	if ownPlot then
		for _, name in ipairs({ "Plants", "Fruits", "Fruit", "Crops", "Harvest", "Harvests" }) do
			local folder = plot:FindFirstChild(name, true)
			if folder then
				changed += hidePerformanceTree(folder, false)
				local processed = 0
				for _, descendant in ipairs(folder:GetDescendants()) do
					changed += hidePerformanceTree(descendant, false)
					processed += 1
					if processed % 120 == 0 then
						task.wait()
					end
				end
			end
		end
		return changed
	end

	changed += hidePerformanceTree(plot, true)
	local processed = 0
	for _, descendant in ipairs(plot:GetDescendants()) do
		changed += hidePerformanceTree(descendant, true)
		processed += 1
		if processed % 120 == 0 then
			task.wait()
		end
	end

	return changed
end

function hidePerformanceGardens()
	local gardens = getGardens()
	if not gardens then
		return 0
	end

	local changed = 0
	for _, plot in ipairs(gardens:GetChildren()) do
		changed += hidePerformanceGardenPlot(plot)
		task.wait()
	end
	return changed
end

function restoreOwnGardenAutomationPrompts()
	local restored = 0
	for _, root in ipairs(getOwnGardenRoots()) do
		for _, descendant in ipairs(root:GetDescendants()) do
			if descendant:IsA("ProximityPrompt")
				and descendant.Name ~= "StealPrompt"
				and isHarvestPrompt(descendant)
			then
				local ok = pcall(function()
					if descendant.Enabled == false then
						descendant.Enabled = true
						restored += 1
					end
				end)
				if not ok then
					continue
				end
			end
		end
	end
	return restored
end

function optimizePerformanceInstance(instance)
	if not instance then
		return 0
	end

	local changed = 0
	if state.performanceMode then
		changed = applyPerformanceGardenHiding(instance)
	end
	if not state.performanceMode then
		return changed
	end

	if performanceState.optimized[instance] then
		return changed
	end

	changed += disableLaggyEffect(instance)
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
		changed = 1
	elseif instance:IsA("Decal") or instance:IsA("Texture") then
		performanceState.optimized[instance] = true
		pcall(function()
			instance.Transparency = 1
		end)
		changed = 1
	elseif instance:IsA("BillboardGui")
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
		changed = 1
	elseif instance:IsA("Animator") then
		performanceState.optimized[instance] = true
		pcall(function()
			for _, track in ipairs(instance:GetPlayingAnimationTracks()) do
				track:Stop(0)
			end
		end)
		changed = 1
	end

	return changed
end

function optimizePerformanceTree(root, budget)
	local changed = 0
	local processed = 0
	for _, descendant in ipairs(root:GetDescendants()) do
		changed += optimizePerformanceInstance(descendant)
		processed += 1
		if budget and processed % budget == 0 then
			task.wait()
		end
	end
	return changed
end

function connectPerformanceWatcher()
	if performanceState.watcherConnected then
		return
	end

	performanceState.watcherConnected = true
	workspace.DescendantAdded:Connect(function(descendant)
		if state.performanceMode then
			if #performanceState.queue - performanceState.queueHead < 800 then
				performanceState.queue[#performanceState.queue + 1] = descendant
			end
			if not performanceState.queueRunning then
				performanceState.queueRunning = true
				task.spawn(function()
					while state.performanceMode and performanceState.queueHead <= #performanceState.queue do
						for _ = 1, 18 do
							local item = performanceState.queue[performanceState.queueHead]
							performanceState.queue[performanceState.queueHead] = nil
							performanceState.queueHead += 1
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
					if performanceState.queueHead > #performanceState.queue then
						performanceState.queue = {}
						performanceState.queueHead = 1
					end
					performanceState.queueRunning = false
				end)
			end
		end
	end)
end

enablePerformanceMode = function()
	local changed = 0
	local now = os.clock()

	connectPerformanceWatcher()

	pcall(function()
		settings().Rendering.QualityLevel = Enum.QualityLevel.Level01
	end)

	pcall(function()
		local lighting = game:GetService("Lighting")
		lighting.GlobalShadows = false
		lighting.EnvironmentDiffuseScale = 0
		lighting.EnvironmentSpecularScale = 0
		lighting.Brightness = math.min(lighting.Brightness, 1)
		for _, descendant in ipairs(lighting:GetDescendants()) do
			changed += optimizePerformanceInstance(descendant)
		end
	end)

	pcall(function()
		local soundService = game:GetService("SoundService")
		for _, descendant in ipairs(soundService:GetDescendants()) do
			changed += optimizePerformanceInstance(descendant)
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
		changed += hidePerformanceGardens()
		changed += restoreOwnGardenAutomationPrompts()
	end

	if not performanceState.fullScanDone and now - performanceState.lastTreeScanAt > 10 then
		performanceState.lastTreeScanAt = now
		performanceState.fullScanDone = true
		changed += optimizePerformanceTree(workspace, 220)
	end

	setStatus(("Performance mode: simplified %d object(s)"):format(changed))
end

function schedulePerformanceModeRestore()
	if not state.performanceMode then
		return
	end

	task.spawn(function()
		for _, delaySeconds in ipairs({ 0, 1.5, 4, 8 }) do
			if delaySeconds > 0 then
				task.wait(delaySeconds)
			end
			if state.performanceMode then
				enablePerformanceMode()
			end
		end
	end)
end

function getSelectedMoveSeedList()
	local selected = {}
	local seen = {}

	for _, seedName in ipairs(seedNames) do
		if selectedMoveSeeds[seedName] then
			seen[seedName] = true
			table.insert(selected, seedName)
		end
	end

	for seedName, enabled in pairs(selectedMoveSeeds) do
		if enabled and not seen[seedName] then
			addUniqueName(seedNames, seedName)
			seedPriority[seedName] = seedPriority[seedName] or getSeedMetadataValue(seedName)
			table.insert(selected, seedName)
		end
	end

	return getSortedSeedList(selected)
end

function getTrowelTool()
	return getToolByWords({ "trowel" })
end

function movePlantTarget(plant, targetPosition)
	if not plant or not plant.Parent or not targetPosition then
		return false, "invalid plant target"
	end

	plant = getPlantModel(plant)
	if not plant or not plant.Parent then
		return false, "plant model unavailable"
	end

	local tool = getTrowelTool()
	if not tool then
		return false, "no trowel found in inventory"
	end

	local plantId = getInstancePacketId(plant)
	if plantId == nil then
		return false, "plant UUID unavailable"
	end
	plantId = tostring(plantId)
	local plantKey = tostring(plant.Name)

	local character = getCharacter()
	local humanoid = getHumanoid()
	if tool.Parent ~= character and humanoid then
		humanoid:EquipTool(tool)
		task.wait(0.08)
	end

	local actions = 0
	local typedStringOk, typedStringCount = sendTypedPacketArgVariants("MovePlant", { "String", "Vector3" }, {
		{ plantKey, targetPosition },
		{ plantId, targetPosition },
	})
	if typedStringOk then
		actions += typedStringCount or 1
	end
	local typedInstanceOk, typedInstanceCount = sendTypedPacketArgVariants("MovePlant", { "Instance", "Vector3" }, {
		{ plant, targetPosition },
	})
	if typedInstanceOk then
		actions += typedInstanceCount or 1
	end
	if sendPacket("MovePlant", plantKey, targetPosition) then
		actions += 1
	end
	if sendPacket("MovePlant", plantId, targetPosition) then
		actions += 1
	end
	if sendPacket("MovePlant", plant, targetPosition) then
		actions += 1
	end
	if actions == 0 and sendRawStringVector3Packet("MovePlant", plantKey, targetPosition) then
		actions += 1
	end
	if actions == 0 and sendRawStringVector3Packet("MovePlant", plantId, targetPosition) then
		actions += 1
	end
	return actions > 0, actions > 0 and ("%d MovePlant request(s)"):format(actions) or "MovePlant packet unavailable"
end

function plantReachedTargetOrMoved(plant, beforePosition, targetPosition)
	local part = getTargetPart(plant)
	if not part then
		return false
	end

	local afterPosition = part.Position
	if beforePosition and (afterPosition - beforePosition).Magnitude >= 1.5 then
		return true
	end
	return targetPosition and (afterPosition - targetPosition).Magnitude <= 6
end

function getTrowelSlotPosition(center, index)
	local slot = math.max(0, (index or 1) - 1)
	local column = (slot % 3) - 1
	local row = math.floor(slot / 3)
	return center + Vector3.new(column * 4, 0, row * 4)
end

function autoMovePlants()
	if not isEnabled("autoMovePlants") then
		return
	end

	local targetPosition = vectorFromConfigPosition(CONFIG.movePlantPosition)
	if not targetPosition then
		setStatus("Move plants: save a move position first")
		return
	end
	targetPosition = getGroundPositionBelow(targetPosition)

	local selected = getSelectedMoveSeedList()
	if #selected == 0 then
		setStatus("Move plants: select planted seed types first")
		return
	end

	local moved = 0
	local checked = 0
	local seen = {}
	local requested = 0
	local lastFailure = "no matching plants found"
	for _, root in ipairs(getOwnGardenRoots()) do
		for _, descendant in ipairs(getCachedDescendants("movePlants", root, CONFIG.cacheRefreshInterval)) do
			if not isEnabled("autoMovePlants") then
				return
			end
			if moved >= 2 or checked >= 60 then
				break
			end

			local plant = getPlantModel(descendant)
			if plant and not seen[plant] and plantMatchesSelection(plant, selected) then
				seen[plant] = true
				checked += 1
				local plantTargetPosition = getTrowelSlotPosition(targetPosition, checked)
				local part = getTargetPart(plant)
				local beforePosition = part and part.Position or nil
				if beforePosition and (beforePosition - plantTargetPosition).Magnitude <= 2.5 then
					continue
				end
				local sent, detail = movePlantTarget(plant, plantTargetPosition)
				if sent then
					requested += 1
					task.wait(0.7)
				else
					lastFailure = detail or lastFailure
				end
				if plantReachedTargetOrMoved(plant, beforePosition, plantTargetPosition) then
					moved += 1
					task.wait(0.25)
				end
			end
		end
		if moved >= 2 or checked >= 60 then
			break
		end
	end

	if moved > 0 then
		setStatus(("Move plants: moved %d matching plant(s)"):format(moved))
	elseif requested > 0 then
		setStatus(("Move plants: sent %d request(s), server made no move"):format(requested))
	elseif checked > 0 then
		setStatus("Move plants: " .. lastFailure)
	else
		setStatus("Move plants: no matching plants found")
	end
end

function getPlantName(instance)
	local current = instance
	local best = instance
	while current and current ~= workspace do
		local parent = current.Parent
		local parentName = parent and string.lower(parent.Name) or ""
		if (current:IsA("Model") or current:IsA("Folder") or current:IsA("BasePart"))
			and (parentName == "plants" or parentName == "crops" or parentName == "plant")
		then
			best = current
			break
		end
		current = parent
	end
	return best and best.Name or ""
end

function getPlantModel(instance)
	local current = instance
	while current and current ~= workspace do
		local parent = current.Parent
		local parentName = parent and string.lower(parent.Name) or ""
		if (current:IsA("Model") or current:IsA("Folder") or current:IsA("BasePart"))
			and (parentName == "plants" or parentName == "crops" or parentName == "plant")
		then
			return current
		end
		current = parent
	end
	return nil
end

function plantHasPromptText(plant, seedName)
	if not plant or not seedName then
		return false
	end

	local seedCache = plantPromptTextCache[plant]
	if not seedCache then
		seedCache = {}
		plantPromptTextCache[plant] = seedCache
	elseif seedCache[seedName] ~= nil then
		return seedCache[seedName]
	end

	local lowered = string.lower(seedName)
	local compactSeed = string.gsub(lowered, "[%s_%-]", "")
	for _, descendant in ipairs(plant:GetDescendants()) do
		if descendant:IsA("ProximityPrompt") and descendant.Name ~= "StealPrompt" then
			local text = string.lower((descendant.ObjectText or "") .. " " .. (descendant.ActionText or "") .. " " .. descendant.Name)
			local compactText = string.gsub(text, "[%s_%-]", "")
			if string.find(text, lowered, 1, true) or string.find(compactText, compactSeed, 1, true) then
				seedCache[seedName] = true
				return true
			end
		end
	end

	seedCache[seedName] = false
	return false
end

function plantMatchesSelection(plant, selected)
	local plantName = string.lower(getPlantName(plant))
	local pathText = string.lower(getObjectPath(plant))
	local compactPlantName = string.gsub(plantName, "[%s_%-]", "")
	local compactPath = string.gsub(pathText, "[%s_%-]", "")
	if plantName == "" and pathText == "" then
		return false
	end

	for _, seedName in ipairs(selected) do
		local lowered = string.lower(seedName)
		local compactSeed = string.gsub(lowered, "[%s_%-]", "")
		local baseSeed = string.gsub(lowered, "%s+fruit$", "")
		baseSeed = string.gsub(baseSeed, "%s+seed$", "")
		local compactBaseSeed = string.gsub(baseSeed, "[%s_%-]", "")
		if string.find(plantName, lowered, 1, true)
			or string.find(compactPlantName, compactSeed, 1, true)
			or (compactBaseSeed ~= "" and string.find(compactPlantName, compactBaseSeed, 1, true))
			or string.find(pathText, lowered, 1, true)
			or string.find(compactPath, compactSeed, 1, true)
			or (compactBaseSeed ~= "" and string.find(compactPath, compactBaseSeed, 1, true))
			or plantHasPromptText(plant, seedName)
			or treeTextMatches(plant, { seedName }, 3)
			or (baseSeed ~= lowered and treeTextMatches(plant, { baseSeed }, 3))
		then
			return true
		end
	end

	return false
end

function activateToolOnly(tool)
	if tool and tool.Parent then
		return pcall(function()
			tool:Activate()
		end)
	end

	return false
end

function vectorFromConfigPosition(value)
	if type(value) ~= "table" then
		return nil
	end
	local x, y, z = tonumber(value.x), tonumber(value.y), tonumber(value.z)
	if x and y and z then
		return Vector3.new(x, y, z)
	end
	return nil
end

function getGroundPositionBelow(position)
	if not position then
		return nil
	end
	local parameters = RaycastParams.new()
	parameters.FilterType = Enum.RaycastFilterType.Exclude
	parameters.FilterDescendantsInstances = { getCharacter() }
	local result = workspace:Raycast(position + Vector3.new(0, 8, 0), Vector3.new(0, -80, 0), parameters)
	return result and result.Position or position
end

function getToolByWords(words)
	local character = getCharacter()
	local humanoid = getHumanoid()
	for _, container in ipairs(getToolContainers()) do
		if container then
			for _, item in ipairs(container:GetChildren()) do
				if item:IsA("Tool") then
					local lowered = string.lower(item.Name)
					for _, word in ipairs(words) do
						if string.find(lowered, string.lower(word), 1, true) then
							if item.Parent ~= character and humanoid then
								humanoid:EquipTool(item)
								task.wait(0.05)
							end
							return item
						end
					end
				end
			end
		end
	end
	return nil
end

function useToolAtPosition(tool, position, holdSeconds)
	if not tool or not position then
		return false
	end

	return activateToolOnly(tool)
end

function autoAcceptMail()
	if not isEnabled("autoAcceptMail") then
		return
	end
	stats.mailChecks += 1
	local actions = 0
	local beforeInventoryCount = countInventoryTools()

	if sendExactPacket("MailboxList") then
		actions += 1
	end
	if sendExactPacket("MailboxOpenInbox") then
		actions += 1
	end
	local openOk, openCount = sendPacketArgVariants("MailboxOpenInbox", {
		{},
		{ true },
		{ "Inbox" },
		{ localPlayer },
		{ { Player = localPlayer } },
	})
	if openOk then
		actions += openCount or 1
	end
	if sendExactPacket("MailboxClaim") then
		actions += 1
	end
	local claimAllOk, claimAllCount = sendPacketArgVariants("MailboxClaim", {
		{},
		{ true },
		{ "All" },
		{ "Inbox" },
		{ localPlayer },
		{ { ClaimAll = true } },
		{ { All = true } },
		{ { Player = localPlayer } },
	})
	if claimAllOk then
		actions += claimAllCount or 1
	end
	for index = 1, 50 do
		if sendTypedPacketExact("MailboxClaim", { "NumberU8" }, index) then
			actions += 1
		end
		if sendTypedPacketExact("MailboxClaim", { "NumberU16" }, index) then
			actions += 1
		end
		if sendTypedPacketExact("MailboxClaim", { "NumberU32" }, index) then
			actions += 1
		end
		if sendTypedPacketExact("MailboxClaim", { "String" }, tostring(index)) then
			actions += 1
		end
		if sendExactPacket("MailboxClaim", index) then
			actions += 1
		end
		if sendExactPacket("MailboxClaim", tostring(index)) then
			actions += 1
		end
		local indexOk, indexCount = sendPacketArgVariants("MailboxClaim", {
			{ index },
			{ tostring(index) },
			{ { Index = index } },
			{ { Id = index } },
			{ { ID = index } },
			{ { MailId = index } },
			{ { MailID = index } },
			{ { InboxIndex = index } },
		})
		if indexOk then
			actions += indexCount or 1
		end
	end
	task.wait(0.25)

	local afterInventoryCount = countInventoryTools()
	local claimed = math.max((afterInventoryCount or 0) - (beforeInventoryCount or 0), 0)
	if claimed > 0 then
		stats.mailClaimed += claimed
		refreshInventoryStats(true)
		updateStatsUI()
	end
	setStatus(("Mail: remote checked (%d action(s)), inventory +%d"):format(actions, claimed))
end

function applyPlayerVisualSettings()
	local changed = 0
	local ownGui = playerGui:FindFirstChild("GardenAutomationGui")
	for _, guiObject in ipairs(playerGui:GetDescendants()) do
		if guiObject:IsA("GuiObject") and (not ownGui or not guiObject:IsDescendantOf(ownGui)) then
			local text = string.lower(safeText(guiObject.Name))
			pcall(function()
				text = text .. " " .. string.lower(safeText(guiObject.Text))
			end)
			if state.hideGameButtons and (string.find(text, "button", 1, true) or string.find(text, "shop", 1, true) or string.find(text, "gift", 1, true)) then
				guiObject.Visible = false
				changed += 1
			elseif state.hidePlotIcons and (string.find(text, "plot", 1, true) or string.find(text, "icon", 1, true)) then
				guiObject.Visible = false
				changed += 1
			end
		end
	end
	if state.hideOwnPlants then
		for _, root in ipairs(getOwnGardenRoots()) do
			for _, descendant in ipairs(root:GetDescendants()) do
				if isOwnPlantVisual(descendant, getGardenPlotForInstance(descendant)) then
					changed += hidePerformanceVisual(descendant, false)
				end
			end
		end
	end
	setStatus(("Player settings: hidden %d object(s)"):format(changed))
end

function autoSell(force)
	local stopKey = force and "sellWhenFull" or "autoSell"
	local token = getStopToken(stopKey)
	if runStopped(stopKey, token) then
		return
	end
	local now = os.clock()
	if now - lastAutoSellAttemptAt < CONFIG.sellCooldown then
		return
	end
	lastAutoSellAttemptAt = now

	local inventoryFull = refreshInventoryStats(true)
	local sellableTools = getSellableFruitTools(true)
	if #sellableTools <= 0 then
		refreshInventoryStats(true)
		if not force then
			setStatus("Sell: nothing to sell")
		else
			setStatus(("Sell: inventory empty (%d/%d)"):format(stats.inventoryItems, stats.inventoryCapacity))
		end
		return
	end
	local beforeInventoryCount = #sellableTools

	local beforeSheckles = refreshCurrencyStats(true)
	local farmedBeforeSell = stats.shecklesFarmed or 0

	for attempt = 1, CONFIG.maxSellAttempts do
		if runStopped(stopKey, token) then
			return
		end
		if #getSellableFruitTools(true) <= 0 then
			setStatus("Sell: no sellable fruit in inventory")
			return
		end

		local remoteActions = sellInventoryByRemote(getSellableFruitTools(true), attempt > 1)
		if remoteActions > 0 then
			task.wait(attempt == 1 and 0.18 or 0.25)
			local sold = sellSucceeded(beforeInventoryCount, beforeSheckles)
			if sold then
				setStatus(("Sell: remote sold inventory (%d action(s))"):format(remoteActions))
				break
			end
		end

		if #getSellableFruitTools(true) == 0 then
			break
		end
	end

	task.wait(0.05)
	local afterSheckles = refreshCurrencyStats(true)
	if afterSheckles and beforeSheckles and afterSheckles > beforeSheckles then
		stats.shecklesFarmed = math.max(stats.shecklesFarmed or 0, farmedBeforeSell + (afterSheckles - beforeSheckles))
	end

	refreshInventoryStats(true)
	invalidateSellableInventoryCache()
	local afterInventoryCount = #getSellableFruitTools(true)
	local sold = afterInventoryCount < beforeInventoryCount
		or (afterSheckles and beforeSheckles and afterSheckles > beforeSheckles)
	if sold then
		fruitTargetCache.refreshedAt = 0
		if timers then
			timers.sellWhenFull = 0
			timers.autoSell = 0
			timers.fruitCollector = CONFIG.collectInterval
		end
	end
	updateStatsUI()
	if not sold then
		setStatus(("Sell failed: remote made no change (%d/%d)"):format(stats.inventoryItems, stats.inventoryCapacity))
	else
		setStatus(("Sell: inventory %d -> %d"):format(beforeInventoryCount, afterInventoryCount))
	end
end

function buyOneSeed(seedName)
	local remoteOk, remoteCount = purchaseSeedRemote(seedName)
	if remoteOk then
		return true, "Seed: " .. seedName, remoteCount or 1
	end

	return false, "Seed: remote failed " .. seedName, 0
end

function buySeed()
	if not isEnabled("autoBuySeeds") then
		return
	end

	local bought = 0
	local attempts = 0
	local lastMessage = "Auto buy: no seeds selected"

	for _, seedName in ipairs(getSelectedSeedList()) do
		if not isEnabled("autoBuySeeds") then
			return
		end

		if attempts >= CONFIG.maxSeedBuyPerTick then
			break
		end

		local beforeInventoryCount = countInventoryTools()
		local beforeSheckles = refreshCurrencyStats(true)
		local ok, message = buyOneSeed(seedName)
		lastMessage = message
		if ok then
			local changed = purchaseChanged(beforeInventoryCount, beforeSheckles)
			if changed then
				bought += 1
			else
				lastMessage = "Auto buy: no verified seed purchase for " .. seedName
			end
		end
		attempts += 1
		task.wait()
	end

	if bought > 0 then
		stats.seedsBought += bought
		refreshInventoryStats()
		updateStatsUI()
		setStatus(("Auto buy: verified %d seed purchase(s) across %d attempt(s)"):format(bought, attempts))
	else
		setStatus(lastMessage)
	end
end

function addBuyAlias(list, seen, value)
	local text = tostring(value or "")
	if text ~= "" and not seen[text] then
		seen[text] = true
		table.insert(list, text)
	end
end

function getGearBuyAliases(gearName)
	local aliases = {}
	local seen = {}
	local text = tostring(gearName or "")
	addBuyAlias(aliases, seen, text)
	addBuyAlias(aliases, seen, string.gsub(text, "%s+", "_"))
	addBuyAlias(aliases, seen, string.gsub(text, "%s+", ""))

	local frame = getGearFrame(text)
	if frame then
		addBuyAlias(aliases, seen, frame.Name)
		addBuyAlias(aliases, seen, string.gsub(frame.Name, "%s+", "_"))
		addBuyAlias(aliases, seen, string.gsub(frame.Name, "%s+", ""))
	end

	local stockFolder = getStockItemsFolder and getStockItemsFolder("GearShop")
	local stockItem = stockFolder and stockFolder:FindFirstChild(text)
	if stockItem then
		addBuyAlias(aliases, seen, stockItem.Name)
	end

	return aliases
end

function buyOneGear(gearName)
	local aliases = getGearBuyAliases(gearName)
	local primary = aliases[1] or tostring(gearName or "")
	local typedVariants = {}
	local typedQuantityVariants = {}
	local packetVariants = {}
	for _, alias in ipairs(aliases) do
		table.insert(typedVariants, { alias })
		table.insert(typedQuantityVariants, { alias, 1 })
		table.insert(packetVariants, { alias })
		table.insert(packetVariants, { alias, 1 })
	end
	table.insert(packetVariants, { { Name = primary } })
	table.insert(packetVariants, { { Gear = primary } })
	table.insert(packetVariants, { { Item = primary } })
	table.insert(packetVariants, { { ItemName = primary } })
	table.insert(packetVariants, { { Name = primary, Quantity = 1 } })

	local actions = 0
	for repeatIndex = 1, CONFIG.gearBuyRemoteRepeats do
		local rawNameOk, rawNameCount = sendRawStringVariants("PurchaseGear", aliases)
		if rawNameOk then
			actions += rawNameCount or 1
		end

		local rawQuantityOk, rawQuantityCount = sendRawStringNumberVariants("PurchaseGear", aliases, 1)
		if rawQuantityOk then
			actions += rawQuantityCount or 1
		end

		local typedOk, typedCount = sendTypedPacketArgVariants("PurchaseGear", { "String" }, typedVariants)
		if typedOk then
			actions += typedCount or 1
		end

		local typedQuantityOk, typedQuantityCount = sendTypedPacketArgVariants("PurchaseGear", { "String", "NumberU8" }, typedQuantityVariants)
		if typedQuantityOk then
			actions += typedQuantityCount or 1
		end

		local ok, count = sendPacketArgVariants("PurchaseGear", packetVariants)
		if ok then
			actions += count or 1
		end

		task.wait()
	end

	if actions > 0 then
		return true, "Gear: " .. primary, actions
	end

	return false, "Gear: remote failed " .. primary, 0
end

function buyGear()
	if not isEnabled("autoBuyGear") then
		return
	end

	local bought = 0
	local attempts = 0
	local lastMessage = "Auto gear: no gear selected"

	for _, gearName in ipairs(getSelectedGearList()) do
		if not isEnabled("autoBuyGear") then
			return
		end
		if attempts >= CONFIG.maxGearBuyPerTick then
			break
		end

		local beforeInventoryCount = countInventoryTools()
		local beforeSheckles = refreshCurrencyStats(true)
		local ok, message, actions = buyOneGear(gearName)
		lastMessage = message
		if ok then
			local changed = purchaseChanged(beforeInventoryCount, beforeSheckles)
			if changed then
				bought += 1
			else
				lastMessage = ("Auto gear: requested %s (%d action(s)), no verified purchase yet"):format(gearName, actions or 0)
			end
			task.wait(0.12)
		end
		attempts += 1
	end

	if bought > 0 then
		stats.gearBought += bought
		refreshInventoryStats()
		updateStatsUI()
		setStatus(("Auto gear: verified %d purchase(s) across %d attempt(s)"):format(bought, attempts))
	else
		setStatus(lastMessage)
	end
end

function petSpawnHandled(model, prompt)
	local now = os.clock()
	local handledUntil = handledPetSpawns[model] or handledPetSpawns[prompt]
	if handledUntil and now < handledUntil then
		return true
	end
	if prompt and (not prompt.Parent or not prompt:IsDescendantOf(workspace)) then
		return true
	end
	if model and (not model.Parent or not model:IsDescendantOf(workspace)) then
		return true
	end
	local ok, enabled = pcall(function()
		return prompt.Enabled
	end)
	return ok and enabled == false
end

function markPetSpawnHandled(model, prompt, seconds)
	local untilTime = os.clock() + (seconds or 20)
	if model then
		handledPetSpawns[model] = untilTime
	end
	if prompt then
		handledPetSpawns[prompt] = untilTime
	end
	cache.wildPetsAt = 0
end

function getPetSpawnId(model, prompt)
	return getInstancePacketId(model)
		or getInstancePacketId(prompt)
		or (model and string.match(model.Name, "([%w%-]+)$"))
		or (model and model.Name)
end

function getPetRemoteInstances(model, prompt)
	local instances = {}
	local seen = {}
	local function add(instance)
		if typeof(instance) == "Instance" and not seen[instance] then
			seen[instance] = true
			table.insert(instances, instance)
		end
	end

	add(prompt)
	add(prompt and prompt.Parent)
	add(model)
	local rootPart = model and model:FindFirstChild("RootPart")
	add(rootPart)
	local primaryPart = model and model.PrimaryPart
	add(primaryPart)
	return instances
end

function buildSingleArgVariants(values)
	local variants = {}
	for _, value in ipairs(values or {}) do
		table.insert(variants, { value })
	end
	return variants
end

function getPetBuyAliases(petName, model, prompt)
	local aliases = {}
	local seen = {}
	addBuyAlias(aliases, seen, petName)
	if model then
		addBuyAlias(aliases, seen, model.Name)
		addBuyAlias(aliases, seen, getWildPetBaseName(model.Name))
	end
	if prompt then
		addBuyAlias(aliases, seen, prompt.Name)
	end
	local spawnId = getPetSpawnId(model, prompt)
	if spawnId ~= nil then
		addBuyAlias(aliases, seen, spawnId)
	end
	return aliases, spawnId
end

function getPetVariantText(model, prompt)
	for _, instance in ipairs({ model, prompt, prompt and prompt.Parent }) do
		if instance then
			for _, key in ipairs({ "Variant", "Mutation", "Mutations", "Rarity", "Tier" }) do
				local ok, value = pcall(function()
					return instance:GetAttribute(key)
				end)
				if ok and value ~= nil and tostring(value) ~= "" then
					return tostring(value)
				end

				local child = instance:FindFirstChild(key)
				if child and child:IsA("ValueBase") and child.Value ~= nil and tostring(child.Value) ~= "" then
					return tostring(child.Value)
				end
			end
		end
	end

	local haystack = string.lower(tostring(model and model.Name or ""))
	for _, variant in ipairs(petVariantWords) do
		if string.find(haystack, string.lower(variant), 1, true) then
			return variant
		end
	end

	return "Normal"
end

function getPetPurchaseInfo(petName, model, prompt)
	return {
		name = model and getWildPetBaseName(model.Name) or petName,
		variant = getPetVariantText(model, prompt),
		spawn = model and model.Name or "",
	}
end

function getPetPromptPosition(model, prompt)
	local part = getPromptPart(prompt) or getTargetPart(model)
	return part and part.Position or nil
end

function walkToDynamicPosition(getPosition, stopDistance, timeoutSeconds)
	local humanoid = getHumanoid()
	local root = getRoot()
	local position = type(getPosition) == "function" and getPosition() or nil
	if not humanoid or not root or not position then
		return false
	end

	stopDistance = stopDistance or CONFIG.petWalkDistance
	timeoutSeconds = timeoutSeconds or CONFIG.petWalkTimeout
	local startedAt = os.clock()
	local lastProgressPosition = root.Position
	local lastProgressAt = os.clock()

	while os.clock() - startedAt < timeoutSeconds do
		root = getRoot()
		position = getPosition()
		if not root or not position then
			return false
		end
		if (root.Position - position).Magnitude <= stopDistance then
			return true
		end

		humanoid:MoveTo(position)
		local directStartedAt = os.clock()
		while os.clock() - directStartedAt < 0.45 do
			task.wait(0.06)
			root = getRoot()
			position = getPosition()
			if not root or not position then
				return false
			end
			if (root.Position - position).Magnitude <= stopDistance then
				return true
			end
			if (root.Position - lastProgressPosition).Magnitude >= 2 then
				lastProgressPosition = root.Position
				lastProgressAt = os.clock()
			end
		end

		local path = PathfindingService:CreatePath({
			AgentRadius = 2.25,
			AgentHeight = 5,
			AgentCanJump = true,
			WaypointSpacing = 4,
		})
		local computed = pcall(function()
			path:ComputeAsync(root.Position, position)
		end)
		local waypoints = computed and path.Status == Enum.PathStatus.Success and path:GetWaypoints() or {}
		if #waypoints < 2 then
			waypoints = {
				{ Position = root.Position },
				{ Position = position },
			}
		end

		local plannedTarget = position
		local recompute = false
		for index = 2, #waypoints do
			local waypoint = waypoints[index]
			if waypoint.Action == Enum.PathWaypointAction.Jump then
				humanoid.Jump = true
			end
			humanoid:MoveTo(waypoint.Position)

			local waypointStartedAt = os.clock()
			while os.clock() - waypointStartedAt < CONFIG.petPathRefreshInterval do
				task.wait(0.06)
				root = getRoot()
				position = getPosition()
				if not root or not position then
					return false
				end
				if (root.Position - position).Magnitude <= stopDistance then
					return true
				end
				if (position - plannedTarget).Magnitude >= CONFIG.petPathTargetMoveThreshold then
					recompute = true
					break
				end
				if (root.Position - waypoint.Position).Magnitude <= 2.5 then
					break
				end
				if (root.Position - lastProgressPosition).Magnitude >= 1.5 then
					lastProgressPosition = root.Position
					lastProgressAt = os.clock()
				elseif os.clock() - lastProgressAt >= 0.45 then
					humanoid.Jump = true
					recompute = true
					lastProgressAt = os.clock()
					break
				end
			end
			if recompute then
				break
			end
		end
	end

	root = getRoot()
	position = getPosition()
	return root and position and (root.Position - position).Magnitude <= stopDistance or false
end

function walkToPosition(position, stopDistance, timeoutSeconds)
	return walkToDynamicPosition(function()
		return position
	end, stopDistance, timeoutSeconds)
end

function walkToPetPrompt(model, prompt)
	if not model or not prompt then
		return false
	end

	local stopDistance = math.min(CONFIG.petWalkDistance, 5.5)
	pcall(function()
		stopDistance = math.max(3, math.min(stopDistance, (tonumber(prompt.MaxActivationDistance) or stopDistance) - 2))
	end)
	local reached = walkToDynamicPosition(function()
		if not model.Parent or not prompt.Parent or not model:IsDescendantOf(workspace) then
			return nil
		end
		return getPetPromptPosition(model, prompt)
	end, stopDistance, CONFIG.petWalkTimeout)
	if reached then
		task.wait(0.15)
	end
	return reached
end

function isPetBuyPrompt(prompt)
	if not prompt or not prompt:IsA("ProximityPrompt") then
		return false
	end
	if prompt.Name == "BuyPrompt" then
		return true
	end
	return textMatches(prompt, { "buy", "purchase", "adopt", "tame" })
end

function petNameMatchesSelection(baseName, selectedName, model, prompt)
	local selectedTerm = compactName(selectedName)
	if selectedTerm == "" then
		return false
	end

	local terms = {
		baseName,
		model and model.Name or "",
		prompt and prompt.Name or "",
		prompt and prompt.ObjectText or "",
		prompt and prompt.ActionText or "",
	}
	for _, value in ipairs(terms) do
		local term = compactName(value)
		if term ~= "" and (term == selectedTerm or string.find(term, selectedTerm, 1, true) or string.find(selectedTerm, term, 1, true)) then
			return true
		end
	end

	return false
end

function buyPetRemote(petName, model, prompt)
	if not model or not model:IsDescendantOf(workspace) then
		return false
	end

	local spawnId = getPetSpawnId(model, prompt)
	local sent = false
	local instances = getPetRemoteInstances(model, prompt)
	local instanceVariants = buildSingleArgVariants(instances)
	local typedOk = sendTypedPacketArgVariants("WildPetTame", { "Instance" }, instanceVariants)
	sent = sent or typedOk
	local instanceOk = sendPacketArgVariants("WildPetTame", instanceVariants)
	sent = sent or instanceOk
	if spawnId ~= nil then
		local idSent = sendPacketArgVariants("WildPetTame", {
			{ spawnId },
			{ { SpawnId = spawnId } },
			{ { Id = spawnId } },
		})
		sent = sent or idSent
	end
	if not sent then
		local rawOk = sendRawInstanceVariants("WildPetTame", instances)
		sent = sent or rawOk
	end
	return sent
end

function tryVerifiedPetRemote(model, prompt)
	local spawnId = getPetSpawnId(model, prompt)
	local attempts = {}
	for _, instance in ipairs(getPetRemoteInstances(model, prompt)) do
		table.insert(attempts, function()
			return sendTypedPacketArgVariants("WildPetTame", { "Instance" }, { { instance } })
				or sendExactPacket("WildPetTame", instance)
				or sendPacket("WildPetTame", instance)
				or sendRawInstancePacket("WildPetTame", instance)
				or sendRawAnyInstancePacket("WildPetTame", instance)
		end)
	end
	if spawnId ~= nil then
		table.insert(attempts, function()
			return sendPacket("WildPetTame", spawnId)
		end)
		table.insert(attempts, function()
			return sendPacket("WildPetTame", { SpawnId = spawnId })
		end)
	end

	for _, attempt in ipairs(attempts) do
		local beforeInventoryCount = countInventoryTools()
		local beforeSheckles = refreshCurrencyStats(true)
		if attempt() then
			local changed = waitForPurchaseChanged(beforeInventoryCount, beforeSheckles, 0.8)
			if changed then
				return true
			end
		end
	end
	return false
end

function buyOnePet(petName)
	if not isEnabled("autoBuyPets") then
		return false, "Auto pets: disabled"
	end

	local wildPetSpawns = getWildPetSpawns()
	if not wildPetSpawns then
		return false, "Auto pets: WildPetSpawns not found"
	end

	local candidates = {}
	cache.wildPetsAt = 0

	for _, descendant in ipairs(getCachedDescendants("wildPets", wildPetSpawns, 0.5)) do
		if not isEnabled("autoBuyPets") then
			return false, "Auto pets: disabled"
		end

		if descendant:IsA("ProximityPrompt") and descendant.Parent and descendant:IsDescendantOf(workspace) then
			local model = descendant:FindFirstAncestorWhichIsA("Model")
			if petSpawnHandled(model, descendant) then
				continue
			end

			local baseName = model and getWildPetBaseName(model.Name) or ""

			if isPetBuyPrompt(descendant) and petNameMatchesSelection(baseName, petName, model, descendant) then
				table.insert(candidates, {
					model = model,
					prompt = descendant,
					distance = getPromptDistance(descendant),
				})
			end
		end
	end

	table.sort(candidates, function(left, right)
		return left.distance < right.distance
	end)

	for _, candidate in ipairs(candidates) do
		local model = candidate.model
		local prompt = candidate.prompt
		if tryVerifiedPetRemote(model, prompt) then
			markPetSpawnHandled(model, prompt, 20)
			return true, ("Auto pets: bought %s by remote"):format(petName), getPetPurchaseInfo(petName, model, prompt)
		end

		local walked = walkToPetPrompt(model, prompt)
		if walked then
			local beforeInventoryCount = countInventoryTools()
			local beforeSheckles = refreshCurrencyStats(true)
			if triggerAnyPrompt(prompt) then
				local changed = waitForPurchaseChanged(beforeInventoryCount, beforeSheckles, 3.0)
				if changed then
					markPetSpawnHandled(model, prompt, 20)
					return true, ("Auto pets: bought %s by prompt"):format(petName), getPetPurchaseInfo(petName, model, prompt)
				end
			end
		else
			setStatus(("Auto pets: pathing to %s failed, trying remote"):format(petName))
		end
	end

	if #candidates == 0 then
		return false, ("Auto pets: no exact available spawn for %s"):format(petName)
	end
	return false, ("Auto pets: matched %d %s spawn(s), purchase made no change"):format(#candidates, petName)
end

function buyPets()
	if not isEnabled("autoBuyPets") then
		return
	end

	local bought = 0
	local attempted = 0
	local lastMessage = "Auto pets: no pets selected"
	local boughtLines = {}
	local skippedUnavailable = {}
	local selectedList = getSelectedPetList()
	local availablePets = getAvailableBuyPetMap()

	for _, petName in ipairs(selectedList) do
		if not isEnabled("autoBuyPets") then
			return
		end
		if petIsAvailableForBuy(petName, availablePets) then
			if bought >= CONFIG.maxPetBuyPerTick then
				break
			end

			local ok, message, petInfo = buyOnePet(petName)
			attempted += 1
			lastMessage = message
			if ok then
				bought += 1
				if petInfo then
					table.insert(boughtLines, ("Bought pet: `%s` | Variant: `%s`"):format(petInfo.name or petName, petInfo.variant or "Normal"))
				end
				task.wait(0.12)
			end
		else
			table.insert(skippedUnavailable, petName)
			lastMessage = ("Auto pets: %s is selected but not currently spawned"):format(petName)
		end
	end

	if bought > 0 then
		stats.petsBought += bought
		refreshInventoryStats()
		updateStatsUI()
		for _, line in ipairs(boughtLines) do
			queueActivityWebhook(line)
		end
		setStatus(("Auto pets: verified %d purchase(s)"):format(bought))
	elseif #selectedList == 0 then
		setStatus("Auto pets: no pets selected")
	elseif attempted == 0 and #skippedUnavailable > 0 then
		setStatus(("Auto pets: selected pet(s) not spawned: %s"):format(table.concat(skippedUnavailable, ", ")))
	else
		setStatus(lastMessage)
	end
end

function splitFilterTerms(value)
	local terms = {}
	for term in string.gmatch(tostring(value or ""), "([^,]+)") do
		term = trimText(term)
		if term ~= "" then
			table.insert(terms, string.lower(term))
		end
	end
	return terms
end

function filterAllowsValue(filterText, value)
	local terms = splitFilterTerms(filterText)
	if #terms == 0 then
		return true
	end
	local lowered = string.lower(tostring(value or ""))
	for _, term in ipairs(terms) do
		if term == "any" or term == "*" or string.find(lowered, term, 1, true) then
			return true
		end
	end
	return false
end

function filterRejectsValue(filterText, value)
	local terms = splitFilterTerms(filterText)
	if #terms == 0 then
		return false
	end
	local lowered = string.lower(tostring(value or ""))
	for _, term in ipairs(terms) do
		if term ~= "any" and term ~= "*" and string.find(lowered, term, 1, true) then
			return true
		end
	end
	return false
end

function petInfoHasVariant(info)
	if not info then
		return false
	end
	local haystack = string.lower(table.concat({
		tostring(info.variant or ""),
		tostring(info.mutation or ""),
		info.tool and tostring(info.tool.Name) or "",
	}, " "))
	for _, variant in ipairs(petVariantWords) do
		if string.find(haystack, string.lower(variant), 1, true) then
			return true
		end
	end
	return false
end

function getPetToolInfo(tool)
	if not tool or not tool:IsA("Tool") then
		return nil
	end

	local name = tool:GetAttribute("PetName")
		or tool:GetAttribute("Pet")
		or tool:GetAttribute("Type")
		or tool:GetAttribute("Name")
		or stripVariantWords(tool.Name)
	local variant = tool:GetAttribute("Variant")
		or tool:GetAttribute("Size")
		or tool:GetAttribute("Rarity")
		or ""
	local mutation = tool:GetAttribute("Mutation")
		or tool:GetAttribute("Mutations")
		or ""
	local id = getToolPacketId(tool)

	for _, childName in ipairs({ "PetName", "Pet", "Type", "Variant", "Mutation", "Mutations", "Id", "ID", "UUID", "Guid", "UID", "UniqueId", "UniqueID", "PetId", "PetID" }) do
		local child = tool:FindFirstChild(childName)
		if child and child:IsA("ValueBase") then
			if childName == "PetName" or childName == "Pet" or childName == "Type" then
				name = name or child.Value
			elseif childName == "Variant" then
				variant = child.Value
			elseif childName == "Mutation" or childName == "Mutations" then
				mutation = child.Value
			elseif id == nil then
				id = child.Value
			end
		end
	end

	local baseName = stripVariantWords(name or tool.Name)
	if not isKnownPetTool(tool) and not hasKnownPetBase(baseName) then
		return nil
	end

	return {
		tool = tool,
		name = baseName,
		variant = tostring(variant or ""),
		mutation = tostring(mutation or ""),
		id = id,
	}
end

function selectedSellPetList()
	local selected = {}
	local seen = {}
	for _, petName in ipairs(petNames) do
		if selectedSellPets[petName] then
			seen[petName] = true
			table.insert(selected, petName)
		end
	end
	for petName, enabled in pairs(selectedSellPets) do
		if enabled and petName and petName ~= "" and not seen[petName] then
			seen[petName] = true
			table.insert(selected, petName)
		end
	end
	return selected
end

function petSellInfoMatches(info)
	if not info then
		return false
	end
	local selected = selectedSellPetList()
	if #selected == 0 then
		return false
	end
	local matchedName = false
	local wanted = compactName(info.name)
	for _, petName in ipairs(selected) do
		if compactName(petName) == wanted then
			matchedName = true
			break
		end
	end
	if not matchedName then
		return false
	end
	if CONFIG.keepAllPetVariants and petInfoHasVariant(info) then
		return false
	end
	return true
end

function getSellablePetTools()
	local tools = {}
	for _, container in ipairs(getToolContainers()) do
		if container then
			for _, item in ipairs(container:GetChildren()) do
				local info = getPetToolInfo(item)
				if petSellInfoMatches(info) then
					table.insert(tools, info)
				end
			end
		end
	end
	return tools
end

function sellPetTool(info)
	if not info then
		return false
	end

	local variants = {
		{ info.tool },
		{ info.name },
		{ info.tool and info.tool.Name or info.name },
		{ { Name = info.name } },
		{ { PetName = info.name } },
	}
	if info.id ~= nil then
		table.insert(variants, 1, { info.id })
		table.insert(variants, { { Id = info.id } })
		table.insert(variants, { { PetId = info.id } })
		table.insert(variants, { { ItemId = info.id } })
		table.insert(variants, { { UID = info.id } })
		table.insert(variants, { info.id, info.name })
		table.insert(variants, { info.name, info.id })
	end

	local actions = 0
	local rawInstances = {}
	if info.tool then
		table.insert(rawInstances, info.tool)
	end
	local rawInstanceOk, rawInstanceCount = sendRawInstanceVariants("SellPet", rawInstances)
	if rawInstanceOk then
		actions += rawInstanceCount or 1
	end
	local rawSellItemInstanceOk, rawSellItemInstanceCount = sendRawInstanceVariants("SellItem", rawInstances)
	if rawSellItemInstanceOk then
		actions += rawSellItemInstanceCount or 1
	end

	local rawStrings = {}
	local function addRawString(value)
		if value ~= nil and tostring(value) ~= "" then
			table.insert(rawStrings, tostring(value))
		end
	end
	addRawString(info.id)
	addRawString(info.name)
	addRawString(info.tool and info.tool.Name or nil)
	local rawStringOk, rawStringCount = sendRawStringVariants("SellPet", rawStrings)
	if rawStringOk then
		actions += rawStringCount or 1
	end
	local rawSellItemStringOk, rawSellItemStringCount = sendRawStringVariants("SellItem", rawStrings)
	if rawSellItemStringOk then
		actions += rawSellItemStringCount or 1
	end

	if info.tool then
		local typedInstanceOk, typedInstanceCount = sendTypedPacketArgVariants("SellPet", { "Instance" }, {
			{ info.tool },
		})
		if typedInstanceOk then
			actions += typedInstanceCount or 1
		end
	end
	local typedStringVariants = {}
	for _, value in ipairs(rawStrings) do
		if value ~= nil and tostring(value) ~= "" then
			table.insert(typedStringVariants, { tostring(value) })
		end
	end
	local typedStringOk, typedStringCount = sendTypedPacketArgVariants("SellPet", { "String" }, typedStringVariants)
	if typedStringOk then
		actions += typedStringCount or 1
	end

	local ok = sendPacketArgVariants("SellPet", variants)
	if ok then
		actions += 1
	end
	local itemOk = sendPacketArgVariants("SellItem", variants)
	if itemOk then
		actions += 1
	end
	return actions > 0
end

function autoSellPets()
	if not isEnabled("autoSellPets") then
		return
	end

	local sold = 0
	local petTools = getSellablePetTools()
	for _, info in ipairs(petTools) do
		if not isEnabled("autoSellPets") then
			return
		end
		local before = countInventoryTools()
		if sellPetTool(info) then
			task.wait(0.2)
			if not info.tool.Parent or countInventoryTools() < before then
				sold += 1
			end
		end
	end

	if sold > 0 then
		stats.petsSold += sold
		refreshInventoryStats(true)
		updateStatsUI()
		setStatus(("Pet sell: sold %d selected pet(s)"):format(sold))
	else
		setStatus(#petTools == 0 and "Pet sell: no matching pets" or "Pet sell: sell packet made no change")
	end
end

function getPetsFolder()
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	return assets and assets:FindFirstChild("Pets")
end

function getPetModulesFolder()
	local sharedModules = ReplicatedStorage:FindFirstChild("SharedModules")
	return sharedModules and sharedModules:FindFirstChild("PetModules")
end

function hasKnownPetBase(baseName)
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

function refreshPetNamesFromGearImages()
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
function make(className, properties, parent)
	local instance = Instance.new(className)
	for key, value in pairs(properties or {}) do
		instance[key] = value
	end
	instance.Parent = parent
	return instance
end

function matchesSelectorFilter(name, query)
	query = string.lower(tostring(query or ""))
	if query == "" then
		return true
	end

	local haystack = string.lower(tostring(name or ""))
	local compactHaystack = string.gsub(haystack, "[%s_%-']", "")
	local compactQuery = string.gsub(query, "[%s_%-']", "")
	return string.find(haystack, query, 1, true) ~= nil
		or string.find(compactHaystack, compactQuery, 1, true) ~= nil
end

function makeSelectorSearch(parent, order, placeholder, onChanged)
	local box = make("TextBox", {
		Name = string.gsub(placeholder, "%s+", "") .. "Search",
		BackgroundColor3 = Color3.fromRGB(18, 23, 24),
		BorderSizePixel = 0,
		ClearTextOnFocus = false,
		Font = Enum.Font.Gotham,
		PlaceholderText = placeholder,
		Text = "",
		TextColor3 = Color3.fromRGB(242, 247, 239),
		TextSize = 9,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Size = UDim2.new(1, 0, 0, 18),
		LayoutOrder = order,
	}, parent)
	make("UICorner", { CornerRadius = UDim.new(0, 6) }, box)
	make("UIPadding", {
		PaddingLeft = UDim.new(0, 7),
		PaddingRight = UDim.new(0, 7),
	}, box)

	box:GetPropertyChangedSignal("Text"):Connect(function()
		onChanged(box.Text)
	end)

	return box
end

function refreshSelectorFilter(buttons, names, query, row, columns)
	local visible = 0
	for _, name in ipairs(names) do
		local button = buttons[name]
		if button then
			local show = matchesSelectorFilter(name, query)
			button.Visible = show
			if show then
				visible += 1
			end
		end
	end

	row.CanvasSize = UDim2.fromOffset(0, math.max(1, math.ceil(visible / (columns or 2))) * 20)
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
	Position = UDim2.fromOffset(18, 250),
	Size = UDim2.fromOffset(238, 350),
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
	TextSize = 12,
	Size = UDim2.new(1, 0, 0, 22),
}, panel)
make("UICorner", { CornerRadius = UDim.new(0, 8) }, header)

local content = make("ScrollingFrame", {
	Name = "Content",
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	CanvasSize = UDim2.fromOffset(0, 0),
	Position = UDim2.fromOffset(5, 27),
	ScrollBarThickness = 3,
	Size = UDim2.new(1, -10, 1, -32),
}, panel)
local contentLayout = make("UIListLayout", {
	Padding = UDim.new(0, 2),
	SortOrder = Enum.SortOrder.LayoutOrder,
}, content)

contentLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
	content.CanvasSize = UDim2.fromOffset(0, contentLayout.AbsoluteContentSize.Y + 8)
end)

local tabButtons = {}
local tabPages = {}
local currentTabParent
local activeTabName = "Farm"

local tabBar = make("Frame", {
	Name = "Tabs",
	BackgroundTransparency = 1,
	Size = UDim2.new(1, 0, 0, 22),
	LayoutOrder = 1,
}, content)
make("UIListLayout", {
	FillDirection = Enum.FillDirection.Horizontal,
	Padding = UDim.new(0, 3),
	SortOrder = Enum.SortOrder.LayoutOrder,
}, tabBar)

local function refreshTabButtons()
	for name, button in pairs(tabButtons) do
		local active = name == activeTabName
		button.BackgroundColor3 = active and Color3.fromRGB(58, 111, 67) or Color3.fromRGB(34, 41, 42)
		button.TextColor3 = active and Color3.fromRGB(246, 255, 242) or Color3.fromRGB(201, 219, 202)
	end
	for name, page in pairs(tabPages) do
		local active = name == activeTabName
		page.Visible = active
		local layout = page:FindFirstChildOfClass("UIListLayout")
		if layout then
			page.Size = active and UDim2.new(1, 0, 0, layout.AbsoluteContentSize.Y + 4) or UDim2.new(1, 0, 0, 0)
		end
	end
end

local function makeTab(name, order)
	local button = make("TextButton", {
		Name = name .. "Tab",
		AutoButtonColor = false,
		BackgroundColor3 = Color3.fromRGB(34, 41, 42),
		BorderSizePixel = 0,
		Font = Enum.Font.GothamSemibold,
		Text = name,
		TextColor3 = Color3.fromRGB(201, 219, 202),
		TextSize = 9,
		Size = UDim2.new(0.25, -3, 1, 0),
		LayoutOrder = order,
	}, tabBar)
	make("UICorner", { CornerRadius = UDim.new(0, 6) }, button)
	tabButtons[name] = button
	button.Activated:Connect(function()
		activeTabName = name
		refreshTabButtons()
		content.CanvasPosition = Vector2.new(0, 0)
	end)

	local page = make("Frame", {
		Name = name .. "Page",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 1),
		LayoutOrder = 10,
		Visible = name == activeTabName,
	}, content)
	local pageLayout = make("UIListLayout", {
		Padding = UDim.new(0, 2),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, page)
	pageLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
		if page.Visible then
			page.Size = UDim2.new(1, 0, 0, pageLayout.AbsoluteContentSize.Y + 4)
		end
	end)
	tabPages[name] = page
	return page
end

makeTab("Farm", 1)
makeTab("Shops", 2)
makeTab("Pets", 3)
makeTab("Settings", 4)
currentTabParent = tabPages.Farm
refreshTabButtons()

local function setBuildTab(name)
	currentTabParent = tabPages[name] or tabPages.Farm
end

local statusLabel = make("TextLabel", {
	Name = "Status",
	BackgroundColor3 = Color3.fromRGB(14, 18, 19),
	BorderSizePixel = 0,
	Font = Enum.Font.Gotham,
	Text = state.lastStatus,
	TextColor3 = Color3.fromRGB(201, 219, 202),
	TextSize = 9,
	TextWrapped = true,
	TextXAlignment = Enum.TextXAlignment.Left,
	Size = UDim2.new(1, 0, 0, 20),
	LayoutOrder = 2,
}, content)
make("UICorner", { CornerRadius = UDim.new(0, 6) }, statusLabel)
make("UIPadding", {
	PaddingLeft = UDim.new(0, 7),
	PaddingRight = UDim.new(0, 7),
}, statusLabel)

statusValue.Changed:Connect(function(value)
	statusLabel.Text = value
end)

function makeToggle(label, key, order)
	local enabled = state[key] == true
	local button = make("TextButton", {
		Name = key,
		AutoButtonColor = false,
		BackgroundColor3 = enabled and Color3.fromRGB(58, 111, 67) or Color3.fromRGB(34, 41, 42),
		BorderSizePixel = 0,
		Font = Enum.Font.GothamSemibold,
		Text = ("%s: %s"):format(label, enabled and "ON" or "OFF"),
		TextColor3 = Color3.fromRGB(235, 244, 233),
		TextSize = 9,
		TextWrapped = true,
		Size = UDim2.new(1, 0, 0, 18),
		LayoutOrder = order,
	}, currentTabParent or content)
	make("UICorner", { CornerRadius = UDim.new(0, 6) }, button)

	button.Activated:Connect(function()
		state[key] = not state[key]
		if not state[key] then
			bumpStopToken(key)
			running[key] = false
			if timers and timers[key] ~= nil then
				timers[key] = 0
			end
			if key == "autoSell" then
				bumpStopToken("sellWhenFull")
				running.sellWhenFull = false
				if timers then
					timers.sellWhenFull = 0
				end
			elseif key == "sellWhenFull" then
				bumpStopToken("autoSell")
				running.autoSell = false
				if timers then
					timers.autoSell = 0
				end
			elseif key == "fruitCollector" then
				fruitTargetCache.refreshedAt = 0
			end
		else
			bumpStopToken(key)
		end
		button.Text = ("%s: %s"):format(label, state[key] and "ON" or "OFF")
		button.BackgroundColor3 = state[key] and Color3.fromRGB(58, 111, 67) or Color3.fromRGB(34, 41, 42)
		saveConfig()
		setStatus(("%s %s"):format(label, state[key] and "enabled" or "disabled"))

		if key == "performanceMode" and state[key] then
			task.spawn(enablePerformanceMode)
		elseif (key == "hideGameButtons" or key == "hidePlotIcons" or key == "hideOwnPlants") and state[key] then
			task.spawn(applyPlayerVisualSettings)
		end
	end)
end

function makeSectionLabel(text, order)
	return make("TextLabel", {
		Name = string.gsub(text, "%s+", "") .. "Section",
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamSemibold,
		Text = text,
		TextColor3 = Color3.fromRGB(174, 211, 178),
		TextSize = 9,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, 0, 0, 10),
		LayoutOrder = order,
	}, currentTabParent or content)
end

function makeCommandButton(label, order, onClick)
	local button = make("TextButton", {
		Name = string.gsub(label, "%s+", "") .. "Button",
		AutoButtonColor = false,
		BackgroundColor3 = Color3.fromRGB(34, 41, 42),
		BorderSizePixel = 0,
		Font = Enum.Font.GothamSemibold,
		Text = label,
		TextColor3 = Color3.fromRGB(235, 244, 233),
		TextSize = 9,
		TextWrapped = true,
		Size = UDim2.new(1, 0, 0, 18),
		LayoutOrder = order,
	}, currentTabParent or content)
	make("UICorner", { CornerRadius = UDim.new(0, 6) }, button)
	button.Activated:Connect(onClick)
	return button
end

setBuildTab("Pets")
makeSectionLabel("Priority", 1)
makeToggle("Auto Buy Pets", "autoBuyPets", 2)
makeToggle("Auto Sell Pets", "autoSellPets", 3)
setBuildTab("Farm")
makeSectionLabel("Farm", 1)
makeToggle("Fruit Collector", "fruitCollector", 2)
makeToggle("Trowel Plants", "autoMovePlants", 3)
makeCommandButton("Set Trowel Position", 4, function()
	local root = getRoot()
	if root then
		local position = getGroundPositionBelow(root.Position)
		CONFIG.movePlantPosition = { x = position.X, y = position.Y, z = position.Z }
		saveConfig()
		setStatus("Saved current ground position for trowel")
	end
end)
makeToggle("Auto Sell Inventory", "autoSell", 5)
setBuildTab("Shops")
makeSectionLabel("Shops", 1)
makeToggle("Auto Buy Seeds", "autoBuySeeds", 2)
makeToggle("Auto Buy Gear", "autoBuyGear", 3)
makeToggle("Auto Accept Mail", "autoAcceptMail", 4)
setBuildTab("Settings")
makeSectionLabel("Settings", 1)
makeToggle("Performance Mode", "performanceMode", 2)

local webhookBox = make("TextBox", {
	Name = "WebhookUrl",
	BackgroundColor3 = Color3.fromRGB(34, 41, 42),
	BorderSizePixel = 0,
	ClearTextOnFocus = false,
	Font = Enum.Font.GothamSemibold,
	PlaceholderText = "Webhook URL for selected stock/pets",
	Text = CONFIG.webhookUrl,
	TextColor3 = Color3.fromRGB(242, 247, 239),
	TextSize = 9,
	TextTruncate = Enum.TextTruncate.AtEnd,
	Size = UDim2.new(1, 0, 0, 20),
	LayoutOrder = 34,
}, currentTabParent or content)
make("UICorner", { CornerRadius = UDim.new(0, 6) }, webhookBox)
make("UIPadding", {
	PaddingLeft = UDim.new(0, 7),
	PaddingRight = UDim.new(0, 7),
}, webhookBox)
webhookBox.FocusLost:Connect(function()
	CONFIG.webhookUrl = string.gsub(tostring(webhookBox.Text or ""), "^%s*(.-)%s*$", "%1")
	webhookBox.Text = CONFIG.webhookUrl
	saveConfig()
	setStatus(CONFIG.webhookUrl ~= "" and "Webhook URL saved" or "Webhook URL cleared")
	if CONFIG.webhookUrl ~= "" then
		sendStatsWebhook(true)
	end
end)

if string.lower(localPlayer.Name or "") == "saraoliver6" then
	local officialStockWebhookBox = make("TextBox", {
		Name = "OfficialStockWebhookUrl",
		BackgroundColor3 = Color3.fromRGB(34, 41, 42),
		BorderSizePixel = 0,
		ClearTextOnFocus = false,
		Font = Enum.Font.GothamSemibold,
		PlaceholderText = "Exclusive live-stock webhook URL",
		Text = CONFIG.officialStockWebhookUrl,
		TextColor3 = Color3.fromRGB(242, 247, 239),
		TextSize = 9,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Size = UDim2.new(1, 0, 0, 20),
		LayoutOrder = 35,
	}, currentTabParent or content)
	make("UICorner", { CornerRadius = UDim.new(0, 6) }, officialStockWebhookBox)
	make("UIPadding", {
		PaddingLeft = UDim.new(0, 7),
		PaddingRight = UDim.new(0, 7),
	}, officialStockWebhookBox)
	officialStockWebhookBox.FocusLost:Connect(function()
		CONFIG.officialStockWebhookUrl = string.gsub(tostring(officialStockWebhookBox.Text or ""), "^%s*(.-)%s*$", "%1")
		officialStockWebhookBox.Text = CONFIG.officialStockWebhookUrl
		saveConfig()
		setStatus(CONFIG.officialStockWebhookUrl ~= "" and "Official stock webhook saved" or "Official stock webhook cleared")
	end)

	local predictorWebhookBox = make("TextBox", {
		Name = "PredictorWebhookUrl",
		BackgroundColor3 = Color3.fromRGB(34, 41, 42),
		BorderSizePixel = 0,
		ClearTextOnFocus = false,
		Font = Enum.Font.GothamSemibold,
		PlaceholderText = "Exclusive predictor webhook URL",
		Text = CONFIG.predictorWebhookUrl,
		TextColor3 = Color3.fromRGB(242, 247, 239),
		TextSize = 9,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Size = UDim2.new(1, 0, 0, 20),
		LayoutOrder = 36,
	}, currentTabParent or content)
	make("UICorner", { CornerRadius = UDim.new(0, 6) }, predictorWebhookBox)
	make("UIPadding", {
		PaddingLeft = UDim.new(0, 7),
		PaddingRight = UDim.new(0, 7),
	}, predictorWebhookBox)
	predictorWebhookBox.FocusLost:Connect(function()
		local previousUrl = CONFIG.predictorWebhookUrl
		CONFIG.predictorWebhookUrl = string.gsub(tostring(predictorWebhookBox.Text or ""), "^%s*(.-)%s*$", "%1")
		if CONFIG.predictorWebhookUrl ~= previousUrl then
			stockPredictionShops.webhookMessageId = nil
		end
		predictorWebhookBox.Text = CONFIG.predictorWebhookUrl
		saveConfig()
		setStatus(CONFIG.predictorWebhookUrl ~= "" and "Exclusive predictor webhook saved" or "Exclusive predictor webhook cleared")
		if CONFIG.predictorWebhookUrl ~= "" then
			sendStockPrediction()
		end
	end)
end

local statsTitle = make("TextLabel", {
	Name = "StatsTitle",
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamSemibold,
	Text = "Session Stats",
	TextColor3 = Color3.fromRGB(221, 236, 216),
	TextSize = 9,
	TextXAlignment = Enum.TextXAlignment.Left,
	Size = UDim2.new(1, 0, 0, 10),
	LayoutOrder = 37,
}, currentTabParent or content)

local statsFrame = make("Frame", {
	Name = "Stats",
	BackgroundColor3 = Color3.fromRGB(14, 18, 19),
	BorderSizePixel = 0,
	Size = UDim2.new(1, 0, 0, 74),
	LayoutOrder = 37,
}, currentTabParent or content)
make("UICorner", { CornerRadius = UDim.new(0, 6) }, statsFrame)
make("UIPadding", {
	PaddingTop = UDim.new(0, 3),
	PaddingBottom = UDim.new(0, 3),
	PaddingLeft = UDim.new(0, 6),
	PaddingRight = UDim.new(0, 6),
}, statsFrame)
make("UIListLayout", {
	Padding = UDim.new(0, 1),
	SortOrder = Enum.SortOrder.LayoutOrder,
}, statsFrame)

function makeStatsLabel(key, order)
	local label = make("TextLabel", {
		Name = key,
		BackgroundTransparency = 1,
		Font = Enum.Font.Gotham,
		Text = "",
		TextColor3 = Color3.fromRGB(201, 219, 202),
		TextSize = 9,
		TextTruncate = Enum.TextTruncate.AtEnd,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, 0, 0, 9),
		LayoutOrder = order,
	}, statsFrame)
	statsLabels[key] = label
	return label
end

makeStatsLabel("status", 1)
makeStatsLabel("systems", 2)
makeStatsLabel("inventory", 3)
makeStatsLabel("collect", 4)
makeStatsLabel("mail", 5)
makeStatsLabel("shops", 6)
makeStatsLabel("limits", 7)
refreshInventoryStats()
updateStatsUI()

function buildSeedSelector()
local parent = currentTabParent or content
local selectedSeedLabel = make("TextLabel", {
	Name = "SelectedSeedLabel",
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamSemibold,
	Text = "Seeds to buy",
	TextColor3 = Color3.fromRGB(221, 236, 216),
	TextSize = 9,
	TextXAlignment = Enum.TextXAlignment.Left,
	Size = UDim2.new(1, 0, 0, 10),
	LayoutOrder = 24,
}, parent)

local seedRow = make("ScrollingFrame", {
	Name = "SeedSelector",
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	CanvasSize = UDim2.fromOffset(0, 0),
	ScrollBarThickness = 3,
	ScrollingDirection = Enum.ScrollingDirection.Y,
	Size = UDim2.new(1, 0, 0, 42),
	LayoutOrder = 26,
}, parent)
make("UIGridLayout", {
	CellPadding = UDim2.fromOffset(3, 3),
	CellSize = UDim2.fromOffset(108, 16),
	SortOrder = Enum.SortOrder.LayoutOrder,
}, seedRow)

local seedLayout = seedRow:FindFirstChildOfClass("UIGridLayout")
local seedButtons = {}
local seedButtonCount = 0
local seedFilterText = ""

makeSelectorSearch(parent, 25, "Search seeds to buy", function(text)
	seedFilterText = text
	refreshSelectorFilter(seedButtons, seedNames, seedFilterText, seedRow, 2)
end)

function refreshSeedButton(seedName)
	local button = seedButtons[seedName]
	if not button then
		return
	end

	local enabled = selectedSeeds[seedName] == true
	button.Text = (enabled and "[x] " or "[ ] ") .. seedName
	button.BackgroundColor3 = enabled and Color3.fromRGB(58, 111, 67) or Color3.fromRGB(52, 60, 54)
end

function refreshSeedCanvas()
	refreshSelectorFilter(seedButtons, seedNames, seedFilterText, seedRow, 2)
end

function makeSeedButton(seedName)
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
		TextSize = 9,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Size = UDim2.fromOffset(108, 16),
		LayoutOrder = seedButtonCount,
	}, seedRow)
	make("UICorner", { CornerRadius = UDim.new(0, 6) }, button)

	seedButtons[seedName] = button
	refreshSeedButton(seedName)
	button.Visible = matchesSelectorFilter(seedName, seedFilterText)

	button.Activated:Connect(function()
		selectedSeeds[seedName] = not selectedSeeds[seedName]
		refreshSeedButton(seedName)
		saveConfig()
		setStatus((selectedSeeds[seedName] and "Selected " or "Unselected ") .. seedName)
		if selectedSeeds[seedName] then
			notifyStock("Seed shop", seedName, true)
		end
	end)

	refreshSeedCanvas()
end

function scanSeedShopNames()
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
refreshSeedCanvas()
scanSeedShopNames()

local seedStockItems = getStockItemsFolder("SeedShop")
if seedStockItems then
	for _, item in ipairs(seedStockItems:GetChildren()) do
		addUniqueName(seedNames, item.Name)
		seedPriority[item.Name] = seedPriority[item.Name] or getSeedMetadataValue(item.Name)
		makeSeedButton(item.Name)
		watchStockItem("SeedShop", item)
		notifyStock("Seed shop", item.Name)
	end

	seedStockItems.ChildAdded:Connect(function(item)
		addUniqueName(seedNames, item.Name)
		seedPriority[item.Name] = getSeedMetadataValue(item.Name)
		table.sort(seedNames)
		makeSeedButton(item.Name)
		watchStockItem("SeedShop", item)
		notifyStock("Seed shop", item.Name)
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
setBuildTab("Shops")
buildSeedSelector()

function buildMoveSeedSelector()
local parent = currentTabParent or content
local moveSeedLabel = make("TextLabel", {
	Name = "MoveSeedLabel",
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamSemibold,
	Text = "Plants to move",
	TextColor3 = Color3.fromRGB(221, 236, 216),
	TextSize = 9,
	TextXAlignment = Enum.TextXAlignment.Left,
	Size = UDim2.new(1, 0, 0, 10),
	LayoutOrder = 30,
}, parent)

local moveSeedRow = make("ScrollingFrame", {
	Name = "MoveSeedSelector",
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	CanvasSize = UDim2.fromOffset(0, 0),
	ScrollBarThickness = 3,
	ScrollingDirection = Enum.ScrollingDirection.Y,
	Size = UDim2.new(1, 0, 0, 42),
	LayoutOrder = 32,
}, parent)
make("UIGridLayout", {
	CellPadding = UDim2.fromOffset(3, 3),
	CellSize = UDim2.fromOffset(108, 16),
	SortOrder = Enum.SortOrder.LayoutOrder,
}, moveSeedRow)

local moveSeedLayout = moveSeedRow:FindFirstChildOfClass("UIGridLayout")
local moveSeedButtons = {}
local moveSeedButtonCount = 0
local moveSeedFilterText = ""

makeSelectorSearch(parent, 31, "Search plants to move", function(text)
	moveSeedFilterText = text
	refreshSelectorFilter(moveSeedButtons, seedNames, moveSeedFilterText, moveSeedRow, 2)
end)

function refreshMoveSeedButton(seedName)
	local button = moveSeedButtons[seedName]
	if not button then
		return
	end

	local enabled = selectedMoveSeeds[seedName] == true
	button.Text = (enabled and "[x] " or "[ ] ") .. seedName
	button.BackgroundColor3 = enabled and Color3.fromRGB(58, 89, 121) or Color3.fromRGB(52, 60, 54)
end

function refreshMoveSeedCanvas()
	refreshSelectorFilter(moveSeedButtons, seedNames, moveSeedFilterText, moveSeedRow, 2)
end

function makeMoveSeedButton(seedName)
	if moveSeedButtons[seedName] then
		return
	end

	moveSeedButtonCount += 1
	local button = make("TextButton", {
		Name = "Move" .. seedName,
		AutoButtonColor = false,
		BackgroundColor3 = Color3.fromRGB(52, 60, 54),
		BorderSizePixel = 0,
		Font = Enum.Font.GothamSemibold,
		Text = seedName,
		TextColor3 = Color3.fromRGB(242, 247, 239),
		TextSize = 9,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Size = UDim2.fromOffset(108, 16),
		LayoutOrder = moveSeedButtonCount,
	}, moveSeedRow)
	make("UICorner", { CornerRadius = UDim.new(0, 6) }, button)

	moveSeedButtons[seedName] = button
	refreshMoveSeedButton(seedName)
	button.Visible = matchesSelectorFilter(seedName, moveSeedFilterText)

	button.Activated:Connect(function()
		selectedMoveSeeds[seedName] = not selectedMoveSeeds[seedName]
		refreshMoveSeedButton(seedName)
		saveConfig()
		setStatus((selectedMoveSeeds[seedName] and "Will move " or "Stopped moving ") .. seedName)
	end)

	refreshMoveSeedCanvas()
end

for _, seedName in ipairs(seedNames) do
	makeMoveSeedButton(seedName)
end

if moveSeedLayout then
	moveSeedLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(refreshMoveSeedCanvas)
end
refreshMoveSeedCanvas()

local moveSeedStockItems = getStockItemsFolder("SeedShop")
if moveSeedStockItems then
	for _, item in ipairs(moveSeedStockItems:GetChildren()) do
		makeMoveSeedButton(item.Name)
	end

	moveSeedStockItems.ChildAdded:Connect(function(item)
		task.wait()
		makeMoveSeedButton(item.Name)
	end)
end
end
setBuildTab("Farm")
buildMoveSeedSelector()

function buildGearSelector()
local parent = currentTabParent or content
local selectedGearLabel = make("TextLabel", {
	Name = "SelectedGearLabel",
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamSemibold,
	Text = "Gear to buy",
	TextColor3 = Color3.fromRGB(221, 236, 216),
	TextSize = 9,
	TextXAlignment = Enum.TextXAlignment.Left,
	Size = UDim2.new(1, 0, 0, 10),
	LayoutOrder = 30,
}, parent)

local gearRow = make("ScrollingFrame", {
	Name = "GearSelector",
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	CanvasSize = UDim2.fromOffset(0, 0),
	ScrollBarThickness = 3,
	ScrollingDirection = Enum.ScrollingDirection.Y,
	Size = UDim2.new(1, 0, 0, 42),
	LayoutOrder = 32,
}, parent)
make("UIGridLayout", {
	CellPadding = UDim2.fromOffset(3, 3),
	CellSize = UDim2.fromOffset(108, 16),
	SortOrder = Enum.SortOrder.LayoutOrder,
}, gearRow)

local gearLayout = gearRow:FindFirstChildOfClass("UIGridLayout")
local gearButtons = {}
local gearButtonCount = 0
local gearFilterText = ""

makeSelectorSearch(parent, 31, "Search gear to buy", function(text)
	gearFilterText = text
	refreshSelectorFilter(gearButtons, gearNames, gearFilterText, gearRow, 2)
end)

function refreshGearButton(gearName)
	local button = gearButtons[gearName]
	if not button then
		return
	end

	local enabled = selectedGears[gearName] == true
	local price = getShopPriceAmount and getShopPriceAmount("GearShop", gearName)
	local stock = getShopStockAmount and getShopStockAmount("GearShop", gearName) or 0
	local suffix = ""
	if price and price > 0 then
		suffix = (" - $%s"):format(tostring(math.floor(price)))
	end
	if stock > 0 then
		suffix = suffix .. (" [%d]"):format(stock)
	end
	button.Text = (enabled and "[x] " or "[ ] ") .. gearName .. suffix
	button.BackgroundColor3 = enabled and Color3.fromRGB(58, 111, 67) or Color3.fromRGB(52, 60, 54)
end

function refreshGearCanvas()
	refreshSelectorFilter(gearButtons, gearNames, gearFilterText, gearRow, 2)
end

function makeGearButton(gearName)
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
		TextSize = 9,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Size = UDim2.fromOffset(108, 16),
		LayoutOrder = gearButtonCount,
	}, gearRow)
	make("UICorner", { CornerRadius = UDim.new(0, 6) }, button)

	gearButtons[gearName] = button
	refreshGearButton(gearName)
	button.Visible = matchesSelectorFilter(gearName, gearFilterText)

	button.Activated:Connect(function()
		selectedGears[gearName] = not selectedGears[gearName]
		refreshGearButton(gearName)
		saveConfig()
		setStatus((selectedGears[gearName] and "Selected " or "Unselected ") .. gearName)
		if selectedGears[gearName] then
			notifyStock("Gear shop", gearName, true)
		end
	end)

	refreshGearCanvas()
end

function scanGearShopNames()
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
	for _, item in ipairs(gearStockItems:GetChildren()) do
		addUniqueName(gearNames, item.Name)
		makeGearButton(item.Name)
		watchStockItem("GearShop", item)
		notifyStock("Gear shop", item.Name)
	end

	gearStockItems.ChildAdded:Connect(function(item)
		addUniqueName(gearNames, item.Name)
		table.sort(gearNames)
		makeGearButton(item.Name)
		watchStockItem("GearShop", item)
		notifyStock("Gear shop", item.Name)
	end)
end

playerGui.ChildAdded:Connect(function(child)
	if child.Name == "GearShop" then
		task.wait(0.25)
		scanGearShopNames()
	end
end)
end
setBuildTab("Shops")
buildGearSelector()

function buildPetSelector()
local parent = currentTabParent or content
local selectedPetLabel = make("TextLabel", {
	Name = "SelectedPetLabel",
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamSemibold,
	Text = "Pets to buy",
	TextColor3 = Color3.fromRGB(221, 236, 216),
	TextSize = 9,
	TextXAlignment = Enum.TextXAlignment.Left,
	Size = UDim2.new(1, 0, 0, 10),
	LayoutOrder = 33,
}, parent)

local petRow = make("ScrollingFrame", {
	Name = "PetSelector",
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	CanvasSize = UDim2.fromOffset(0, 0),
	ScrollBarThickness = 3,
	ScrollingDirection = Enum.ScrollingDirection.Y,
	Size = UDim2.new(1, 0, 0, 42),
	LayoutOrder = 35,
}, parent)
make("UIGridLayout", {
	CellPadding = UDim2.fromOffset(3, 3),
	CellSize = UDim2.fromOffset(108, 16),
	SortOrder = Enum.SortOrder.LayoutOrder,
}, petRow)

local petLayout = petRow:FindFirstChildOfClass("UIGridLayout")
local petButtons = {}
local petButtonCount = 0
local petFilterText = ""

makeSelectorSearch(parent, 34, "Search pets to buy", function(text)
	petFilterText = text
	refreshSelectorFilter(petButtons, petNames, petFilterText, petRow, 2)
end)

function refreshPetButton(petName)
	local button = petButtons[petName]
	if not button then
		return
	end

	local enabled = selectedPets[petName] == true
	button.Text = (enabled and "[x] " or "[ ] ") .. petName
	button.BackgroundColor3 = enabled and Color3.fromRGB(58, 111, 67) or Color3.fromRGB(52, 60, 54)
end

function refreshPetCanvas()
	refreshSelectorFilter(petButtons, petNames, petFilterText, petRow, 2)
end

function makePetButton(petName)
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
		TextSize = 9,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Size = UDim2.fromOffset(108, 16),
		LayoutOrder = petButtonCount,
	}, petRow)
	make("UICorner", { CornerRadius = UDim.new(0, 6) }, button)

	petButtons[petName] = button
	refreshPetButton(petName)
	button.Visible = matchesSelectorFilter(petName, petFilterText)

	button.Activated:Connect(function()
		selectedPets[petName] = not selectedPets[petName]
		refreshPetButton(petName)
		saveConfig()
		setStatus((selectedPets[petName] and "Selected " or "Unselected ") .. petName)
		if selectedPets[petName] and listHasName(buyPetNames, petName) then
			notifyPetSpawn(petName)
		end
	end)

	refreshPetCanvas()
end

function scanPetBuyNames()
	refreshPetNamesFromAssets()
	refreshBuyPetNamesFromWildSpawns()

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
		table.sort(petNames)
		makePetButton(baseName)
	end)
end

local wildPetSpawnsForBuy = getWildPetSpawns()
if wildPetSpawnsForBuy then
	wildPetSpawnsForBuy.DescendantAdded:Connect(function(descendant)
		cache.wildPetsAt = 0
		local model
		if descendant:IsA("ProximityPrompt") then
			model = descendant:FindFirstAncestorWhichIsA("Model")
		elseif descendant:IsA("Model") and descendant:FindFirstChildWhichIsA("ProximityPrompt", true) then
			model = descendant
		end
		if model then
			local baseName = getWildPetBaseName(model.Name)
			addUniqueName(buyPetNames, baseName)
			addUniqueName(petNames, baseName)
			table.sort(buyPetNames)
			table.sort(petNames)
			makePetButton(baseName)
			notifyPetSpawn(baseName)
		end
	end)
end
local mapForPetBuy = getMap()
if mapForPetBuy then
	mapForPetBuy.ChildAdded:Connect(function(child)
		if child.Name == "WildPetSpawns" then
			task.wait(0.25)
			cache.wildPetsAt = 0
			scanPetBuyNames()
			child.DescendantAdded:Connect(function(descendant)
				cache.wildPetsAt = 0
				local model
				if descendant:IsA("ProximityPrompt") then
					model = descendant:FindFirstAncestorWhichIsA("Model")
				elseif descendant:IsA("Model") and descendant:FindFirstChildWhichIsA("ProximityPrompt", true) then
					model = descendant
				end
				if model then
					local baseName = getWildPetBaseName(model.Name)
					addUniqueName(buyPetNames, baseName)
					addUniqueName(petNames, baseName)
					table.sort(buyPetNames)
					table.sort(petNames)
					makePetButton(baseName)
					notifyPetSpawn(baseName)
				end
			end)
		end
	end)
end
end
setBuildTab("Pets")
buildPetSelector()

function buildPetSellSelector()
local parent = currentTabParent or content
local petSellLabel = make("TextLabel", {
	Name = "SellPetLabel",
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamSemibold,
	Text = "Pets to sell",
	TextColor3 = Color3.fromRGB(221, 236, 216),
	TextSize = 9,
	TextXAlignment = Enum.TextXAlignment.Left,
	Size = UDim2.new(1, 0, 0, 10),
	LayoutOrder = 36,
}, parent)

local keepVariantsButton
keepVariantsButton = make("TextButton", {
	Name = "KeepAllPetVariants",
	AutoButtonColor = false,
	BackgroundColor3 = CONFIG.keepAllPetVariants and Color3.fromRGB(58, 111, 67) or Color3.fromRGB(34, 41, 42),
	BorderSizePixel = 0,
	Font = Enum.Font.GothamSemibold,
	Text = "Keep All Variants: " .. (CONFIG.keepAllPetVariants and "ON" or "OFF"),
	TextColor3 = Color3.fromRGB(235, 244, 233),
	TextSize = 9,
	TextWrapped = true,
	Size = UDim2.new(1, 0, 0, 18),
	LayoutOrder = 37,
}, parent)
make("UICorner", { CornerRadius = UDim.new(0, 6) }, keepVariantsButton)
keepVariantsButton.Activated:Connect(function()
	CONFIG.keepAllPetVariants = not CONFIG.keepAllPetVariants
	keepVariantsButton.Text = "Keep All Variants: " .. (CONFIG.keepAllPetVariants and "ON" or "OFF")
	keepVariantsButton.BackgroundColor3 = CONFIG.keepAllPetVariants and Color3.fromRGB(58, 111, 67) or Color3.fromRGB(34, 41, 42)
	saveConfig()
	setStatus("Pet sell keep all variants " .. (CONFIG.keepAllPetVariants and "enabled" or "disabled"))
end)

local petSellRow = make("ScrollingFrame", {
	Name = "PetSellSelector",
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	CanvasSize = UDim2.fromOffset(0, 0),
	ScrollBarThickness = 3,
	ScrollingDirection = Enum.ScrollingDirection.Y,
	Size = UDim2.new(1, 0, 0, 38),
	LayoutOrder = 39,
}, parent)
make("UIGridLayout", {
	CellPadding = UDim2.fromOffset(3, 3),
	CellSize = UDim2.fromOffset(108, 16),
	SortOrder = Enum.SortOrder.LayoutOrder,
}, petSellRow)

local petSellLayout = petSellRow:FindFirstChildOfClass("UIGridLayout")
local petSellButtons = {}
local petSellButtonCount = 0
local petSellFilterText = ""

makeSelectorSearch(parent, 38, "Search pets to sell", function(text)
	petSellFilterText = text
	refreshSelectorFilter(petSellButtons, petNames, petSellFilterText, petSellRow, 2)
end)

function refreshPetSellButton(petName)
	local button = petSellButtons[petName]
	if not button then
		return
	end
	local enabled = selectedSellPets[petName] == true
	button.Text = (enabled and "[x] " or "[ ] ") .. petName
	button.BackgroundColor3 = enabled and Color3.fromRGB(122, 65, 50) or Color3.fromRGB(52, 60, 54)
end

function refreshPetSellCanvas()
	refreshSelectorFilter(petSellButtons, petNames, petSellFilterText, petSellRow, 2)
end

function makePetSellButton(petName)
	if petSellButtons[petName] then
		return
	end
	petSellButtonCount += 1
	local button = make("TextButton", {
		Name = "Sell" .. petName,
		AutoButtonColor = false,
		BackgroundColor3 = Color3.fromRGB(52, 60, 54),
		BorderSizePixel = 0,
		Font = Enum.Font.GothamSemibold,
		Text = petName,
		TextColor3 = Color3.fromRGB(242, 247, 239),
		TextSize = 9,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Size = UDim2.fromOffset(108, 16),
		LayoutOrder = petSellButtonCount,
	}, petSellRow)
	make("UICorner", { CornerRadius = UDim.new(0, 6) }, button)
	petSellButtons[petName] = button
	refreshPetSellButton(petName)
	button.Visible = matchesSelectorFilter(petName, petSellFilterText)
	button.Activated:Connect(function()
		selectedSellPets[petName] = not selectedSellPets[petName]
		refreshPetSellButton(petName)
		saveConfig()
		setStatus((selectedSellPets[petName] and "Sell selected " or "Sell unselected ") .. petName)
	end)
	refreshPetSellCanvas()
end

for _, petName in ipairs(petNames) do
	makePetSellButton(petName)
end
if petSellLayout then
	petSellLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(refreshPetSellCanvas)
end
refreshPetSellCanvas()

local assetsForPetSell = ReplicatedStorage:FindFirstChild("Assets")
local petsFolderForSell = assetsForPetSell and assetsForPetSell:FindFirstChild("Pets")
if petsFolderForSell then
	petsFolderForSell.ChildAdded:Connect(function(pet)
		local baseName = stripVariantWords(pet.Name)
		addUniqueName(petNames, baseName)
		table.sort(petNames)
		makePetSellButton(baseName)
	end)
end
end
setBuildTab("Pets")
buildPetSellSelector()

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

schedulePerformanceModeRestore()

timers = {
	fruitCollector = 0,
	autoSell = 0,
	sellWhenFull = 0,
	autoMovePlants = 0,
	autoAcceptMail = 0,
	autoBuySeeds = 0,
	autoBuyGear = 0,
	autoBuyPets = 0,
	autoSellPets = 0,
	stats = 0,
	statsWebhook = 0,
	guiInventoryFull = false,
	lastInventoryRefresh = 0,
	lastGuiInventoryRefresh = 0,
}

function runGuarded(key, callback)
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

function watchToolContainer(container)
	if not container then
		return
	end
	container.ChildAdded:Connect(invalidateSellableInventoryCache)
	container.ChildRemoved:Connect(invalidateSellableInventoryCache)
end

watchToolContainer(localPlayer:FindFirstChildOfClass("Backpack"))
localPlayer.ChildAdded:Connect(function(child)
	if child:IsA("Backpack") then
		watchToolContainer(child)
		invalidateSellableInventoryCache()
	end
end)
if localPlayer.Character then
	watchToolContainer(localPlayer.Character)
end
localPlayer.CharacterAdded:Connect(function(character)
	watchToolContainer(character)
	invalidateSellableInventoryCache()
end)

RunService.Heartbeat:Connect(function(deltaTime)
	schedulerAccumulator += deltaTime
	if schedulerAccumulator < CONFIG.schedulerInterval then
		return
	end
	deltaTime = schedulerAccumulator
	schedulerAccumulator = 0

	local jobsStarted = 0
	local maxJobsThisFrame = 8
	local function tryRun(key, callback)
		if jobsStarted >= maxJobsThisFrame or running[key] then
			return false
		end

		jobsStarted += 1
		runGuarded(key, callback)
		return true
	end

	timers.fruitCollector = state.fruitCollector and (timers.fruitCollector + deltaTime) or 0
	timers.autoSell = state.autoSell and (timers.autoSell + deltaTime) or 0
	timers.sellWhenFull = state.sellWhenFull and (timers.sellWhenFull + deltaTime) or 0
	timers.autoMovePlants = state.autoMovePlants and (timers.autoMovePlants + deltaTime) or 0
	timers.autoAcceptMail = state.autoAcceptMail and (timers.autoAcceptMail + deltaTime) or 0
	timers.autoBuySeeds = state.autoBuySeeds and (timers.autoBuySeeds + deltaTime) or 0
	timers.autoBuyGear = state.autoBuyGear and (timers.autoBuyGear + deltaTime) or 0
	timers.autoBuyPets = state.autoBuyPets and (timers.autoBuyPets + deltaTime) or 0
	timers.autoSellPets = state.autoSellPets and (timers.autoSellPets + deltaTime) or 0
	timers.stats += deltaTime
	timers.statsWebhook += deltaTime

	if timers.stats >= 5.0 then
		timers.stats = 0
		refreshInventoryStats()
		updateStatsUI()
	end

	if timers.statsWebhook >= CONFIG.statsWebhookInterval then
		timers.statsWebhook = 0
		sendStatsWebhook(false)
	end

	local inventoryFull = false
	local sellNeeded = false
	local hasSellableInventory = false
	if state.sellWhenFull or state.autoSell then
		inventoryFull = refreshInventoryStats(false)
		if inventoryFull then
			invalidateSellableInventoryCache()
			inventoryFull = refreshInventoryStats(true)
		end
		hasSellableInventory = hasSellableFruitTools()
		sellNeeded = inventoryFull and hasSellableInventory
	end
	local urgentSellDue = hasSellableInventory and inventoryFull and (state.sellWhenFull or state.autoSell)
	local sellDue = hasSellableInventory and (urgentSellDue
		or (state.autoSell and timers.autoSell >= CONFIG.sellInterval))

	if sellDue and not running.autoSell and not running.sellWhenFull then
		if state.sellWhenFull and sellNeeded then
			if tryRun("sellWhenFull", function()
				autoSell(true)
			end) then
				timers.sellWhenFull = 0
				timers.autoSell = 0
			end
		elseif state.autoSell then
			if tryRun("autoSell", autoSell) then
				timers.autoSell = 0
			end
		end
	elseif not hasSellableInventory then
		timers.autoSell = 0
		timers.sellWhenFull = 0
	end

	if state.autoMovePlants and timers.autoMovePlants >= 1.0 then
		if tryRun("autoMovePlants", autoMovePlants) then
			timers.autoMovePlants = 0
		end
	end

	if state.autoAcceptMail and timers.autoAcceptMail >= CONFIG.mailInterval then
		if tryRun("autoAcceptMail", autoAcceptMail) then
			timers.autoAcceptMail = 0
		end
	end

	if state.autoBuyPets and timers.autoBuyPets >= CONFIG.petBuyInterval then
		if tryRun("autoBuyPets", buyPets) then
			timers.autoBuyPets = 0
		end
	end

	if state.autoSellPets and timers.autoSellPets >= CONFIG.petSellInterval then
		if tryRun("autoSellPets", autoSellPets) then
			timers.autoSellPets = 0
		end
	end

	if state.fruitCollector and timers.fruitCollector >= CONFIG.collectInterval then
		if tryRun("fruitCollector", collectFruit) then
			timers.fruitCollector = 0
		end
	end

	if state.autoBuySeeds and timers.autoBuySeeds >= CONFIG.buyInterval then
		if tryRun("autoBuySeeds", buySeed) then
			timers.autoBuySeeds = 0
		end
	end

	if state.autoBuyGear and timers.autoBuyGear >= CONFIG.buyInterval then
		if tryRun("autoBuyGear", buyGear) then
			timers.autoBuyGear = 0
		end
	end

end)

if configLoaded then
	setStatus("Garden Tools loaded - config restored")
elseif canUseFileConfig() then
	setStatus("Garden Tools loaded - config ready")
else
	setStatus("Garden Tools loaded - config files unsupported")
end

