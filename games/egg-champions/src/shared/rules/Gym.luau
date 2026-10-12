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

function Gym.leaderTeam(worldId: string, rebirths: number): { Battle.FighterSpec }
	if rebirths < 0 then
		error("Gym.leaderTeam: rebirths cannot be negative")
	end
	local gym = Config.gymByWorld[worldId]
	local team: { Battle.FighterSpec } = {}
	for _, leader in gym.leader_team do
		table.insert(team, {
			pet = nil,
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

function Gym.fee(worldId: string): number
	return Config.worldById[worldId].gym.fee
end

function Gym.retrySeconds(): number
	return Config.constants.gym_retry_seconds
end

return Gym
