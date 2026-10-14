--!strict
--[[
	PassService: who owns which game pass, checked on the server.

	The pass ids come from config/passes.json through PassEffects. The Roblox
	game pass ids live in PRODUCT_IDS below, since they are platform ids, not
	game design. An id of 0 means the owner has not created that pass yet: it
	counts as not owned and the client offers no purchase for it.

	Ownership:
	- Checked with MarketplaceService:UserOwnsGamePassAsync when the player
	  joins, cached for the session, and checked again when the player
	  finishes a purchase prompt.
	- Every check runs in pcall. A check that errors grants nothing and is
	  retried every RETRY_SECONDS. A failure never overwrites an owned pass
	  with false, so a flaky service cannot take a pass away mid session.

	Auto Click: the server clicks for every player who owns it, once every
	AUTO_CLICK_SECONDS, through the callback start() is given. The client
	has no say in the rate.

	Nothing here touches battle. PassEffects says what each pass does.
]]

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local PassEffects = require(Shared:WaitForChild("rules"):WaitForChild("PassEffects"))
local Profile = require(Shared:WaitForChild("rules"):WaitForChild("Profile"))

local server = script.Parent.Parent
local Guard = require(server:WaitForChild("Guard"))
local Profiles = require(server:WaitForChild("Profiles"))
local Analytics = require(server:WaitForChild("Analytics"))

type Profile = Profile.Profile

-- Roblox game pass ids, by config pass id. The owner fills these in after
-- creating the passes; 0 means not created yet.
local PRODUCT_IDS: { [string]: number } = {
	["2x_coins"] = 2036822460,
	["auto_click"] = 2036948474,
	["lucky_eggs"] = 2037398470,
	["triple_hatch"] = 2039582279,
}

-- How often a failed ownership check is tried again.
local RETRY_SECONDS = 15

-- How often the server clicks for an Auto Click owner. Not a spec number:
-- the spec only says the pass clicks automatically.
local AUTO_CLICK_SECONDS = 1

-- Load time check: one product id entry per handled pass, no more.
do
	local handled: { [string]: boolean } = {}
	for _, id in PassEffects.HANDLED do
		handled[id] = true
		if PRODUCT_IDS[id] == nil then
			error(string.format("PassService has no product id entry for %q", id))
		end
	end
	for id in PRODUCT_IDS do
		if handled[id] ~= true then
			error(string.format("PassService has a product id for unknown pass %q", id))
		end
	end
end

type PlayerPasses = {
	owned: PassEffects.Owned,
	-- Pass ids whose last check errored, to try again.
	retry: { [string]: boolean },
}

local PassService = {}

PassService.AUTO_CLICK_SECONDS = AUTO_CLICK_SECONDS
PassService.RETRY_SECONDS = RETRY_SECONDS

local byPlayer: { [Player]: PlayerPasses } = {}

local function entryFor(player: Player): PlayerPasses
	local entry = byPlayer[player]
	if entry == nil then
		entry = { owned = {}, retry = {} }
		byPlayer[player] = entry
	end
	return entry
end

local function passIdOfProduct(productId: number): string?
	for id, product in PRODUCT_IDS do
		if product ~= 0 and product == productId then
			return id
		end
	end
	return nil
end

-- Checks one pass. Returns true when the owned set changed.
local function check(player: Player, passId: string): boolean
	local productId = PRODUCT_IDS[passId]
	if productId == nil or productId == 0 then
		return false
	end
	local entry = entryFor(player)
	local ok, result = pcall(function()
		return MarketplaceService:UserOwnsGamePassAsync(player.UserId, productId)
	end)
	if not ok then
		entry.retry[passId] = true
		warn(
			string.format(
				"[Passes] ownership check for %s failed for %s, will retry: %s",
				passId,
				player.Name,
				tostring(result)
			)
		)
		return false
	end
	entry.retry[passId] = nil
	if result == true and entry.owned[passId] ~= true then
		entry.owned[passId] = true
		return true
	end
	return false
end

local function checkAll(player: Player)
	local changed = false
	for _, passId in PassEffects.HANDLED do
		if player.Parent == nil then
			return
		end
		if check(player, passId) then
			changed = true
		end
	end
	if changed then
		Guard.push(player)
	end
end

-- True when the player owns the pass with this config id.
function PassService.owns(player: Player, passId: string): boolean
	local entry = byPlayer[player]
	return entry ~= nil and entry.owned[passId] == true
end

-- A copy of the player's owned set, keyed by config pass id.
function PassService.owned(player: Player): PassEffects.Owned
	local entry = byPlayer[player]
	return if entry ~= nil then table.clone(entry.owned) else {}
end

-- What the main screen shows: each pass, whether it is owned, and the
-- Roblox id to prompt with (0 when it cannot be bought yet).
local function passesView(player: Player, _profile: Profile): any
	local list = {}
	for _, pass in Config.passes do
		table.insert(list, {
			id = pass.id,
			name = pass.name,
			effect = pass.effect,
			owned = PassService.owns(player, pass.id),
			productId = PRODUCT_IDS[pass.id] or 0,
		})
	end
	return list
end

local started = false

-- Hooks joins, purchases, the retry loop and the Auto Click loop. onAutoClick
-- is called once per interval for each Auto Click owner with a loaded profile.
function PassService.start(onAutoClick: (Player, Profile) -> ())
	if started then
		return
	end
	started = true

	Guard.addDerived("passes", passesView)

	Players.PlayerAdded:Connect(function(player: Player)
		entryFor(player)
		checkAll(player)
	end)
	for _, player in Players:GetPlayers() do
		entryFor(player)
		task.spawn(checkAll, player)
	end
	Players.PlayerRemoving:Connect(function(player: Player)
		byPlayer[player] = nil
	end)

	MarketplaceService.PromptGamePassPurchaseFinished:Connect(
		function(player: Player, productId: number, purchased: boolean)
			local passId = passIdOfProduct(productId)
			if passId == nil or player.Parent == nil then
				return
			end
			if purchased then
				entryFor(player).owned[passId] = true
				Analytics.track(player, "pass_purchased", { passId = passId })
			end
			check(player, passId)
			Guard.push(player)
		end
	)

	task.spawn(function()
		while true do
			task.wait(RETRY_SECONDS)
			for player, entry in byPlayer do
				if next(entry.retry) ~= nil then
					local changed = false
					for passId in table.clone(entry.retry) do
						if check(player, passId) then
							changed = true
						end
					end
					if changed then
						Guard.push(player)
					end
				end
			end
		end
	end)

	task.spawn(function()
		while true do
			task.wait(AUTO_CLICK_SECONDS)
			for player, entry in byPlayer do
				if PassEffects.autoClick(entry.owned) then
					local profile = Profiles.get(player)
					if profile ~= nil and player.Parent ~= nil then
						task.spawn(onAutoClick, player, profile)
					end
				end
			end
		end
	end)
end

return PassService
