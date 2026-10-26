--!strict
local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Wild = require(Shared.rules.WildEncounter)
local Prisms = require(Shared.rules.Prisms)
local PrismService = require(script.Parent.PrismService)
local ClickService = require(script.Parent.ClickService)
local Passes = require(script.Parent.Parent.Passes)
local PassEffects = require(Shared.rules.PassEffects)
local Training = require(Shared.rules.Training)
local TutorialService = require(script.Parent.TutorialService)
local PetIndex = require(Shared.rules.PetIndex)
local Remotes = require(Shared.Remotes)
local Guard = require(script.Parent.Parent.Guard)
local C = Config.constants
local WildService = {}
local rng = Random.new()
type Entry = { worldId: string?, nextAt: number, encounter: Wild.Encounter?, boostUntil: number }
local entries: { [Player]: Entry } = {}
local eligible: (Player, any) -> string? = function(_player: Player, _profile: any)
	return nil
end
local function entry(player: Player): Entry
	if not entries[player] then
		entries[player] = { nextAt = 0, boostUntil = 0 }
	end
	return entries[player]
end
function WildService.multiplier(player: Player, now: number): number
	local e = entries[player]
	return if e and now < e.boostUntil then 1 + C.wild_training_bonus else 1
end
function WildService.observe(player: Player, worldId: string?, now: number)
	local e = entry(player)
	if e.worldId ~= worldId then
		e.worldId, e.encounter, e.nextAt = worldId, nil, now + C.wild_spawn_seconds
	elseif e.encounter and now >= e.encounter.expiresAt then
		e.encounter = nil
		e.nextAt = now + C.wild_spawn_seconds
	elseif worldId and not e.encounter and now >= e.nextAt then
		local petId = Prisms.spawn(
			worldId,
			rng:NextNumber(),
			rng:NextNumber(),
			rng:NextNumber(),
			rng:NextNumber()
		)
		e.encounter = Wild.new(HttpService:GenerateGUID(false), worldId, petId, now)
	end
end
function WildService.start(check: (Player, any) -> string?)
	eligible = check
	Guard.addDerived("wild", function(player: Player, profile: any)
		local e = entry(player)
		if e.encounter then
			e.encounter.rewardCoins = Wild.reward(
				ClickService.coinsPerClick(player, profile)
					* Training.hits(PassEffects.autoClick(Passes.owned(player)))
					/ C.training_tick_seconds,
				e.encounter.strength
			)
		end
		return {
			encounter = e.encounter,
			boostUntil = e.boostUntil,
			bonus = C.wild_training_bonus,
			nextAt = e.nextAt,
		}
	end)
	Guard.onInvoke(
		Remotes.names.WildAction,
		function(player: Player, profile: any, id: any, action: any, prismId: any)
			if
				type(id) ~= "string"
				or (action ~= "strike" and action ~= "capture" and action ~= "skip")
			then
				return false, "bad_choice"
			end
			local now = workspace:GetServerTimeNow()
			local e = entry(player)
			local encounter = e.encounter
			if not encounter or encounter.id ~= id then
				return false, "encounter_ended"
			end
			-- Recheck position/unlock/health/gym synchronously; replicated attributes are not authority.
			if eligible(player, profile) ~= encounter.worldId or now >= encounter.expiresAt then
				e.encounter = nil
				e.nextAt = now + C.wild_spawn_seconds
				return false, "leave_training"
			end
			if action == "skip" then
				e.encounter, e.nextAt = nil, now + C.wild_spawn_seconds
				return true, {}
			end
			local rewardCoins = 0
			local dropId: string? = nil
			local ok, result
			if action == "strike" then
				ok, result = Wild.strike(encounter, now)
				if ok and encounter.phase == "defeated" then
					-- Refresh, never stack or bank time. This boost is active-only and never saved offline.
					e.boostUntil = now + C.wild_boost_seconds
					rewardCoins = Wild.reward(
						ClickService.coinsPerClick(player, profile)
							* Training.hits(PassEffects.autoClick(Passes.owned(player)))
							/ C.training_tick_seconds,
						encounter.strength
					)
					profile.coins += rewardCoins
					dropId = Prisms.drop(
						Config.petById[encounter.petId].world,
						rng:NextNumber(),
						rng:NextNumber()
					)
					if dropId then
						profile.prisms[dropId] += 1
					end
				end
			else
				if encounter.phase ~= "defeated" then
					return false, "capture_unavailable"
				end
				if not Prisms.spend(profile, prismId, PrismService.paidAllowed(player)) then
					return false, "no_prisms"
				end
				ok, result = Wild.capture(
					encounter,
					now,
					rng:NextNumber(),
					Prisms.chance(encounter.petId, prismId)
				)
				if ok and result == "captured" then
					local pet = { uid = HttpService:GenerateGUID(false), petId = encounter.petId }
					table.insert(profile.pets, pet)
					PetIndex.record(profile.index, pet.petId, nil)
					TutorialService.note(profile, "hatched")
				end
			end
			if not ok then
				return false, result
			end
			return true,
				{
					result = result,
					petId = encounter.petId,
					phase = encounter.phase,
					rewardCoins = rewardCoins,
					dropId = dropId,
				}
		end
	)
	Players.PlayerRemoving:Connect(function(player)
		entries[player] = nil
	end)
end
return WildService
