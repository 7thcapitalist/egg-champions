--!strict
--[[
	Gym: the leader team, fee and retry wait for each world's gym.

	Leader stats come from tuning/gyms.json, written by the economy tuner. They
	are already tuned, so they are read as they are and never recomputed here.
	Leader pets get no rebirth bonus and no variant, so the rebirth count a
	caller passes does not change the team.
]]

local Config = require(script.Parent.Parent.Config)
local Battle = require(script.Parent.Battle)

local Gym = {}

-- Match each tuned leader slot to an existing pet model from that world.
-- This identity is cosmetic: every combat field still comes from gyms.json.
local function leaderLooks(worldId: string, typeId: string): { string }
	local world = Config.worldById[worldId]
	local looks = {}
	for _, pet in Config.pets do
		if
			pet.world == worldId
			and pet.type == typeId
			and table.find(world.eggs, pet.egg) ~= nil
		then
			table.insert(looks, pet.id)
		end
	end
	if #looks == 0 then
		error(string.format("Gym.leaderTeam: no %s pet in %s eggs", typeId, worldId))
	end
	return looks
end

function Gym.leaderTeam(worldId: string, rebirths: number): { Battle.FighterSpec }
	if rebirths < 0 then
		error("Gym.leaderTeam: rebirths cannot be negative")
	end
	local gym = Config.gymByWorld[worldId]
	local team: { Battle.FighterSpec } = {}
	local looksByType: { [string]: { string } } = {}
	for slot, leader in gym.leader_team do
		local looks = looksByType[leader.type]
		if looks == nil then
			looks = leaderLooks(worldId, leader.type)
			looksByType[leader.type] = looks
		end
		table.insert(team, {
			pet = looks[(slot - 1) % #looks + 1],
			variant = nil,
			type = leader.type,
			hp = leader.hp,
			attack = leader.attack,
			speed = leader.speed,
			special = leader.special,
			offType = nil,
		})
	end
	return team
end

-- The tuner's reference team for this gym, as battle input. Used to check that
-- the rules and the tuner agree.
function Gym.referenceTeam(worldId: string): { Battle.FighterSpec }
	local gym = Config.gymByWorld[worldId]
	local team: { Battle.FighterSpec } = {}
	for _, reference in gym.reference_team do
		local pet = Config.petById[reference.pet]
		table.insert(team, {
			pet = reference.pet,
			variant = nil,
			type = reference.type,
			hp = reference.hp,
			attack = reference.attack,
			speed = reference.speed,
			special = reference.special,
			offType = pet.special_off_type,
		})
	end
	return team
end

export type OwnedPet = {
	petId: string,
	variant: string?,
}

-- Everything about the player that a gym battle could be started from.
export type BattleInput = {
	worldId: string,
	-- The equipped pets, in team order, already resolved from uids.
	pets: { OwnedPet },
	rebirths: number,
	-- The player's owned game passes. The spec says no pass changes HP or
	-- Attack, so nothing here reads it. It is part of the input so the one
	-- function GymService starts battles with is the one a test runs with
	-- every pass on and off, and a pass wired into battle would fail it.
	passes: { [string]: boolean }?,
}

-- Starts a gym battle: the player team from the equipped pets, the leader
-- team from Gym.leaderTeam. Errors on an empty team, like Battle.start.
function Gym.startBattle(input: BattleInput, rng: Battle.Rng): Battle.State
	local playerTeam: { Battle.FighterSpec } = {}
	for _, pet in input.pets do
		table.insert(playerTeam, Battle.fighterFromPet(pet.petId, pet.variant))
	end
	return Battle.start(
		playerTeam,
		Gym.leaderTeam(input.worldId, input.rebirths),
		input.rebirths,
		rng
	)
end

function Gym.fee(worldId: string): number
	return Config.worldById[worldId].gym.fee
end

function Gym.retrySeconds(): number
	return Config.constants.gym_retry_seconds
end

-- When the next attempt at each world's gym is allowed, by world id, in the
-- same clock as `now` below (the server's unix time in seconds). It lives in
-- the player's profile, so the wait survives leaving and rejoining.
export type RetryWaits = { [string]: number }

-- Starts the retry wait after a loss: the next attempt is allowed
-- gym_retry_seconds after `now`. Changes `waits` in place.
function Gym.recordLoss(waits: RetryWaits, worldId: string, now: number)
	waits[worldId] = now + Gym.retrySeconds()
end

-- A win ends any wait for that gym. Changes `waits` in place.
function Gym.clearWait(waits: RetryWaits, worldId: string)
	waits[worldId] = nil
end

-- Seconds left before the gym can be tried again, 0 when it can be now. Never
-- more than gym_retry_seconds, so a deadline saved by a server whose clock ran
-- ahead cannot lock a gym for longer than one wait.
function Gym.retryWaitLeft(waits: RetryWaits, worldId: string, now: number): number
	local readyAt = waits[worldId]
	if type(readyAt) ~= "number" or readyAt ~= readyAt then
		return 0
	end
	return math.clamp(readyAt - now, 0, Gym.retrySeconds())
end

-- True when a battle at this gym may start at `now`.
function Gym.canStart(waits: RetryWaits, worldId: string, now: number): boolean
	return Gym.retryWaitLeft(waits, worldId, now) <= 0
end

-- How a battle session ended, as gym_result reports it. Leaving the game with
-- a battle running counts as giving up.
Gym.endings = table.freeze({ win = "win", loss = "loss", gaveUp = "gave_up" })

-- The one rule for the retry wait when a session ends: a win clears the wait,
-- and anything else (a loss, giving up, leaving mid-battle) starts it, the
-- same way. Changes `waits` in place.
function Gym.recordEnd(waits: RetryWaits, worldId: string, ending: string, now: number)
	if ending == Gym.endings.win then
		Gym.clearWait(waits, worldId)
	else
		Gym.recordLoss(waits, worldId, now)
	end
end

-- Ends a session because the player left the game: the same path as giving up.
function Gym.recordLeave(waits: RetryWaits, worldId: string, now: number)
	Gym.recordEnd(waits, worldId, Gym.endings.gaveUp, now)
end

-- Why a start is refused for the wait, if it is: "retry_wait" and the whole
-- seconds left (rounded up, at least 1), so the client can count down after a
-- rejoin. Nil when the gym can be tried now.
function Gym.retryRefusal(waits: RetryWaits, worldId: string, now: number): (string?, number?)
	local left = Gym.retryWaitLeft(waits, worldId, now)
	if left <= 0 then
		return nil, nil
	end
	return "retry_wait", math.max(1, math.ceil(left))
end

return Gym
