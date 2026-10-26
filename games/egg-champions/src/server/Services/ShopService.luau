--!strict
--[[
	ShopService: buying and hatching eggs.

	BuyEgg takes the egg id and a count: 1 (or nothing) for one egg, or
	Hatch.TRIPLE_COUNT for a Triple Hatch. Any other count is refused. The server
	checks the egg's world is open (Progression.eggUnlocked), charges the price
	from config, rolls with Hatch, adds each pet with a fresh uid, and records
	it in the pet index. Triple Hatch needs the pass, charges three prices and
	rolls three times. Nothing is charged unless the whole purchase can go
	through.
]]

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local rules = Shared:WaitForChild("rules")
local Config = require(Shared:WaitForChild("Config"))
local Coins = require(rules:WaitForChild("Coins"))
local Hatch = require(rules:WaitForChild("Hatch"))
local PassEffects = require(rules:WaitForChild("PassEffects"))
local PetIndex = require(rules:WaitForChild("PetIndex"))
local Profile = require(rules:WaitForChild("Profile"))
local Progression = require(rules:WaitForChild("Progression"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Requests = require(Shared:WaitForChild("net"):WaitForChild("Requests"))

local server = script.Parent.Parent
local Guard = require(server:WaitForChild("Guard"))
local Passes = require(server:WaitForChild("Passes"))
local Analytics = require(server:WaitForChild("Analytics"))
local TutorialService = require(script.Parent:WaitForChild("TutorialService"))

type Profile = Profile.Profile

local TRIPLE_COUNT = Hatch.TRIPLE_COUNT

local ShopService = {}

local eggIds: { string } = {}
for _, egg in Config.eggs do
	table.insert(eggIds, egg.id)
end
local knownEggs = Requests.setOf(eggIds)

local rng = Random.new()

local function onBuyEgg(
	player: Player,
	profile: Profile,
	eggId: any,
	requested: any
): (boolean, any)
	local valid, reason = Requests.checkChoice(eggId, knownEggs)
	if not valid then
		return false, reason
	end
	if requested ~= nil and requested ~= 1 and requested ~= TRIPLE_COUNT then
		return false, Requests.reasons.badChoice
	end
	local owned = Passes.owned(player)
	local count = if requested == TRIPLE_COUNT then TRIPLE_COUNT else 1
	if not PassEffects.hatchCountAllowed(owned, count) then
		return false, "no_triple_hatch_pass"
	end
	if not Progression.eggUnlocked(profile :: any, eggId) then
		return false, "egg_locked"
	end
	local price = Config.eggById[eggId].price * count
	if profile.coins < price then
		return false, "cannot_afford"
	end

	-- A first hatch ever: the pet index is empty until something hatches.
	local firstEver = next(profile.index) == nil
	local results = Hatch.rollMany(eggId, rng :: any, PassEffects.hatchOptions(owned), count)
	profile.coins -= price
	local hatched = {}
	for _, result in results do
		local pet: Profile.OwnedPet = {
			uid = HttpService:GenerateGUID(false),
			petId = result.petId,
			variant = result.variant,
		}
		table.insert(profile.pets, pet)
		local newInIndex = PetIndex.record(profile.index, result.petId, result.variant)
		table.insert(hatched, {
			uid = pet.uid,
			petId = pet.petId,
			variant = pet.variant,
			newInIndex = newInIndex,
			-- For the hatch reveal's "Click +N"; the client only shows it.
			clickPower = Coins.clickPowerOf({ petId = pet.petId, variant = pet.variant }),
		})
	end
	Analytics.track(player, "egg_bought", {
		eggId = eggId,
		count = count,
		price = price,
		coinsAfter = profile.coins,
	})
	for _, result in results do
		Analytics.track(player, "pet_hatched", {
			petId = result.petId,
			rarity = Config.petById[result.petId].rarity,
			variant = result.variant or Analytics.NORMAL_VARIANT,
		})
	end
	TutorialService.note(profile, "hatched")
	if firstEver then
		Analytics.track(player, "first_hatch", Analytics.withPlaytime(player, {}))
	end
	return true, { eggId = eggId, pets = hatched, price = price }
end

function ShopService.start()
	-- Which hatch passes the player owns, so the egg shop offers Hatch x3 and
	-- shows the odds the server will roll. The client only displays these.
	Guard.addDerived("hatchPasses", function(player: Player, _profile: Profile): any
		local owned = Passes.owned(player)
		return {
			tripleHatch = PassEffects.hatchCountAllowed(owned, TRIPLE_COUNT),
			luckyEggs = PassEffects.hatchOptions(owned).luckyEggs == true,
		}
	end)
	Guard.onInvoke(Remotes.names.BuyEgg, onBuyEgg)
end

return ShopService
