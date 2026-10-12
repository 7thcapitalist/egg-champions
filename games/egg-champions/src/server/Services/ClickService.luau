--!strict
--[[
	ClickService: coins for clicks.

	The client fires Click with nothing else; it never sends an amount. Each
	accepted click adds Coins.perClick for the player's equipped team, rebirths,
	completed eggs and pass multiplier, all worked out here on the server.

	Clicks past MAX_CLICKS_PER_SECOND in any one second are dropped, not
	credited. The first drop in each window is logged; logging every dropped
	click from a spamming client would flood the Output.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local rules = Shared:WaitForChild("rules")
local Coins = require(rules:WaitForChild("Coins"))
local PetIndex = require(rules:WaitForChild("PetIndex"))
local Profile = require(rules:WaitForChild("Profile"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Requests = require(Shared:WaitForChild("net"):WaitForChild("Requests"))

local server = script.Parent.Parent
local Guard = require(server:WaitForChild("Guard"))
local Passes = require(server:WaitForChild("Passes"))

type Profile = Profile.Profile

-- A plausible human maximum. Anti cheat, not a game number.
local MAX_CLICKS_PER_SECOND = 20
local WINDOW_SECONDS = 1

local ClickService = {}

ClickService.MAX_CLICKS_PER_SECOND = MAX_CLICKS_PER_SECOND

local limiter = Requests.newRateLimiter(MAX_CLICKS_PER_SECOND, WINDOW_SECONDS)

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
	return Coins.perClick({
		team = equippedPets(profile),
		rebirths = profile.rebirths,
		completedEggs = PetIndex.completedEggs(profile.index),
		passMultiplier = Passes.coinMultiplier(player),
	})
end

local function onClick(player: Player, profile: Profile)
	local allowed, dropped = Requests.allow(limiter, player, os.clock())
	if not allowed then
		if dropped == 1 then
			Guard.reject(player, Remotes.names.Click, Requests.reasons.rateLimited)
		end
		return
	end
	profile.coins += ClickService.coinsPerClick(player, profile)
	Guard.push(player)
end

function ClickService.start()
	Guard.addDerived("coinsPerClick", ClickService.coinsPerClick)
	Guard.onEvent(Remotes.names.Click, onClick)
	Players.PlayerRemoving:Connect(function(player: Player)
		Requests.forget(limiter, player)
	end)
end

return ClickService
