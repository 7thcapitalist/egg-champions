--!strict
-- Server-only training rewards. Historical names preserve saved-stat compatibility.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local rules = Shared:WaitForChild("rules")
local Coins = require(rules:WaitForChild("Coins"))
local PetIndex = require(rules:WaitForChild("PetIndex"))
local Profile = require(rules:WaitForChild("Profile"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Offline = require(rules:WaitForChild("Offline"))
local Config = require(Shared:WaitForChild("Config"))
local Profiles = require(script.Parent.Parent:WaitForChild("Profiles"))
local Training = require(rules:WaitForChild("Training"))
local PassEffects = require(rules:WaitForChild("PassEffects"))

local server = script.Parent.Parent
local Guard = require(server:WaitForChild("Guard"))
local Passes = require(server:WaitForChild("Passes"))
local TutorialService = require(script.Parent:WaitForChild("TutorialService"))

type Profile = Profile.Profile

local CollectionRewards = require(rules.CollectionRewards)
local ClickService = {}

-- The equipped team as Coins reads it: each uid resolved to its pet.
local function equippedPets(profile: Profile): { Coins.OwnedPet }
	local byUid: { [string]: Profile.OwnedPet } = {}
	for _, pet in profile.pets do
		byUid[pet.uid] = pet
	end
	local team: { Coins.OwnedPet } = {}
	for _, uid in profile.team do
		local pet = byUid[uid]
		if pet ~= nil then
			table.insert(team, { petId = pet.petId, variant = pet.variant })
		end
	end
	return team
end

function ClickService.coinsPerClick(player: Player, profile: Profile): number
	return CollectionRewards.summary(profile.index).extraMultiplier
		* Coins.perClick({
			team = equippedPets(profile),
			rebirths = profile.rebirths,
			completedEggs = PetIndex.completedEggs(profile.index),
			passMultiplier = Passes.coinMultiplier(player),
			legacyAnchor = Coins.legacyAnchor(profile.pets),
		})
end

-- Only TrainingService can call this; legacy Click remotes have no handler.
function ClickService.train(player: Player, profile: Profile, hits: number, target: Vector3)
	local credited = ClickService.coinsPerClick(player, profile) * hits
	profile.coins += credited
	TutorialService.note(profile, "coins")
	Guard.push(player)
	Guard.fire(player, Remotes.names.ClickCredited, credited, target)
end

-- Each equipped pet's own Click Power, keyed by uid, for the team bar. The
-- client shows these numbers and never works them out itself.
function ClickService.teamClickPower(_player: Player, profile: Profile): { [string]: number }
	local byUid: { [string]: Profile.OwnedPet } = {}
	for _, pet in profile.pets do
		byUid[pet.uid] = pet
	end
	local powers: { [string]: number } = {}
	local anchor = Coins.legacyAnchor(profile.pets)
	for _, uid in profile.team do
		local pet = byUid[uid]
		if pet ~= nil then
			powers[uid] = Coins.clickPowerOf({ petId = pet.petId, variant = pet.variant }, anchor)
		end
	end
	return powers
end

function ClickService.start()
	Guard.addDerived("collectionRewards", function(_player, profile)
		return CollectionRewards.summary(profile.index)
	end)
	Profiles.setOfflineRate(function(player: Player, profile: Profile): number
		local active = ClickService.coinsPerClick(player, profile)
			* Training.hits(PassEffects.autoClick(Passes.owned(player)))
			/ Config.constants.training_tick_seconds
		return Offline.rate(active, #profile.team > 0)
	end)
	Guard.addDerived("offlineReward", function(player: Player)
		return Profiles.offlineReward(player)
	end)
	Guard.addDerived("coinsPerClick", ClickService.coinsPerClick)
	Guard.addDerived("teamClickPower", ClickService.teamClickPower)
	Guard.addDerived("coinsPerTrainingTick", function(player: Player, profile: Profile): number
		return ClickService.coinsPerClick(player, profile)
			* Training.hits(PassEffects.autoClick(Passes.owned(player)))
	end)
end

return ClickService
