--!strict
-- Server-owned eligibility and full-tick timing. No engine objects or clocks.
local Config = require(script.Parent.Parent.Config)
local Progression = require(script.Parent.Progression)

local Training = {}
export type Point = { x: number, y: number, z: number }
export type Clock = { target: string?, nextAt: number? }

function Training.inRange(position: Point, target: Point): boolean
	local dx, dz = position.x - target.x, position.z - target.z
	return dx * dx + dz * dz <= Config.constants.training_radius ^ 2
		and math.abs(position.y - target.y) <= Config.constants.training_max_vertical
end

function Training.allowed(
	profile: any,
	worldIndex: number,
	alive: boolean,
	inBattle: boolean
): boolean
	return alive and not inBattle and Progression.worldUnlocked(profile, worldIndex)
end

function Training.hits(autoOwned: boolean): number
	return Config.constants.training_hits_per_tick
		+ (if autoOwned then Config.constants.training_auto_bonus_hits else 0)
end

-- At most one reward per evaluation. Re-entry, target changes and delayed
-- frames cannot bank partial ticks or collect a backlog of missed rewards.
function Training.step(clock: Clock, target: string?, now: number): boolean
	if target == nil then
		clock.target, clock.nextAt = nil, nil
		return false
	end
	if clock.target ~= target or clock.nextAt == nil then
		clock.target = target
		clock.nextAt = now + Config.constants.training_tick_seconds
		return false
	end
	if now < clock.nextAt then
		return false
	end
	-- Preserve cadence through small scheduler jitter. Missed whole ticks are
	-- discarded, never banked for a burst after a stall or re-entry.
	local interval = Config.constants.training_tick_seconds
	local skipped = math.floor((now - clock.nextAt) / interval)
	clock.nextAt += (skipped + 1) * interval
	return true
end

return Training
