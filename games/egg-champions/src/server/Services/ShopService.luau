--!strict
--[[
	ShopService: buying and hatching eggs.

	BuyEgg takes the egg id and, optionally, true for a Triple Hatch. The server
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
local Hatch = require(rules:WaitForChild("Hatch"))
local PetIndex = require(rules:WaitForChild("PetIndex"))
local Profile = require(rules:WaitForChild("Profile"))
local Progression = require(rules:WaitForChild("Progression"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Requests = require(Shared:WaitForChild("net"):WaitForChild("Requests"))

local server = script.Parent.Parent
local Guard = require(server:WaitForChild("Guard"))
local Passes = require(server:WaitForChild("Passes"))

type Profile = Profile.Profile

-- Pass ids from config, checked at load so a renamed pass fails loudly.
local TRIPLE_HATCH = Config.passById["triple_hatch"].id
local LUCKY_EGGS = Config.passById["lucky_eggs"].id
-- How many eggs Triple Hatch opens. Names the pass's effect, like its name.
local TRIPLE_COUNT = 3

local ShopService = {}

local eggIds: { string } = {}
for _, egg in Config.eggs do
	table.insert(eggIds, egg.id)
end
local knownEggs = Requests.setOf(eggIds)

local rng = Random.new()

local function onBuyEgg(player: Player, profile: Profile, eggId: any, triple: any): (boolean, any)
	local valid, reason = Requests.checkChoice(eggId, knownEggs)
	if not valid then
		return false, reason
	end
	if triple ~= nil and type(triple) ~= "boolean" then
		return false, Requests.reasons.badChoice
	end
	local count = 1
	if triple == true then
		if not Passes.owns(player, TRIPLE_HATCH) then
			return false, "no_triple_hatch_pass"
		end
		count = TRIPLE_COUNT
	end
	if not Progression.eggUnlocked(profile :: any, eggId) then
		return false, "egg_locked"
	end
	local price = Config.eggById[eggId].price * count
	if profile.coins < price then
		return false, "cannot_afford"
	end

	local results =
		Hatch.rollMany(eggId, rng :: any, { luckyEggs = Passes.owns(player, LUCKY_EGGS) }, count)
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
		})
	end
	return true, { eggId = eggId, pets = hatched, price = price }
end

function ShopService.start()
	Guard.onInvoke(Remotes.names.BuyEgg, onBuyEgg)
end

return ShopService
