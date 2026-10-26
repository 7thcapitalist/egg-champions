--!strict
-- Private encounters use injected server time and RNG. Clients choose only an action.
local Config = require(script.Parent.Parent.Config)
local C = Config.constants
local Prisms = require(script.Parent.Prisms)
local Wild = {}
export type Encounter = {
	id: string,
	worldId: string,
	petId: string,
	startedAt: number,
	expiresAt: number,
	hp: number,
	maxHp: number,
	strength: number,
	rewardCoins: number?,
	misses: number,
	lastStrike: number,
	phase: string,
}
function Wild.new(id: string, worldId: string, petId: string, now: number): Encounter
	local strength = Prisms.strength(petId)
	return {
		id = id,
		worldId = worldId,
		petId = petId,
		startedAt = now,
		expiresAt = now + C.wild_encounter_seconds,
		hp = math.ceil(C.wild_hp * strength),
		maxHp = math.ceil(C.wild_hp * strength),
		strength = strength,
		misses = 0,
		lastStrike = now - C.wild_strike_cooldown,
		phase = "fighting",
	}
end
function Wild.focus(startedAt: number, now: number): number
	return ((now - startedAt) % C.wild_focus_period) / C.wild_focus_period
end
function Wild.strike(e: Encounter, now: number): (boolean, string)
	if now >= e.expiresAt or e.phase ~= "fighting" then
		return false, "encounter_ended"
	end
	if now - e.lastStrike < C.wild_strike_cooldown then
		return false, "strike_cooldown"
	end
	e.lastStrike = now
	local perfect = math.abs(Wild.focus(e.startedAt, now) - 0.5) <= C.wild_focus_window
	e.hp = math.max(0, e.hp - (if perfect then C.wild_focus_damage else C.wild_damage))
	if not perfect then
		e.misses += 1
	end
	if e.hp <= 0 then
		e.phase = "defeated"
	elseif e.misses >= C.wild_max_misses then
		e.phase = "escaped"
	end
	return true, if perfect then "perfect" else "counter"
end
function Wild.reward(activePerSecond: number, strength: number): number
	return math.floor(activePerSecond * C.wild_reward_seconds * strength)
end
function Wild.capture(e: Encounter, now: number, roll: number, chance: number?): (boolean, string)
	if now >= e.expiresAt or e.phase ~= "defeated" then
		return false, "capture_unavailable"
	end
	-- The service spends inventory before this roll. End the encounter before returning.
	e.phase = if roll < (chance or 0) then "captured" else "escaped"
	return true, e.phase
end
function Wild.pool(worldId: string): { string }
	local list = {}
	for _, pet in Config.pets do
		if pet.world == worldId then
			table.insert(list, pet.id)
		end
	end
	return list
end
return Wild
