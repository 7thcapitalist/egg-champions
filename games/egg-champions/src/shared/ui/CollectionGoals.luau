--!strict
-- A read-only collection trail over the existing server-owned index. No new
-- currency, reward claim or save field: egg bonuses already come from Coins.
local Config = require(script.Parent.Parent.Config)
local Progression = require(script.Parent.Parent.rules.Progression)

export type Goal = {
	eggId: string,
	name: string,
	have: number,
	need: number,
	complete: boolean,
	unlocked: boolean,
	missing: { string },
	bonusPercent: number,
}

local CollectionGoals = {}

function CollectionGoals.build(profile: any): ({ Goal }, Goal?)
	local safe = if type(profile) == "table" then profile else {}
	local index = if type(safe.index) == "table" then safe.index else {}
	local progression =
		{ gymsBeaten = if type(safe.gymsBeaten) == "table" then safe.gymsBeaten else {} }
	local goals: { Goal } = {}
	local target: Goal? = nil
	for _, egg in Config.eggs do
		local missing = {}
		local have = 0
		for _, pet in Config.pets do
			if pet.egg == egg.id then
				local entry = index[pet.id]
				if type(entry) == "table" and entry.normal == true then
					have += 1
				else
					table.insert(missing, pet.name)
				end
			end
		end
		local goal: Goal = {
			eggId = egg.id,
			name = egg.name,
			have = have,
			need = Config.constants.pets_per_egg,
			complete = have == Config.constants.pets_per_egg,
			unlocked = Progression.eggUnlocked(progression :: any, egg.id),
			missing = missing,
			bonusPercent = Config.constants.index_egg_bonus * 100,
		}
		table.insert(goals, goal)
		if goal.unlocked and not goal.complete then
			-- Prefer finishing an almost-complete set; config order breaks ties.
			if target == nil or goal.have > target.have then
				target = goal
			end
		end
	end
	return goals, target
end

return CollectionGoals
