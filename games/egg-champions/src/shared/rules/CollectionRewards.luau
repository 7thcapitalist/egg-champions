--!strict
-- Recompute permanent rewards from the saved index: no claim duplication or new schema.
local Config = require(script.Parent.Parent.Config)
local Coins = require(script.Parent.Coins)
local CollectionRewards = {}
function CollectionRewards.summary(index: Coins.PetIndex): any
	local worlds, eggs = 0, Coins.completedEggs(index)
	for _, world in Config.worlds do
		local complete = true
		for _, eggId in world.eggs do
			if not Coins.isEggComplete(index, eggId) then
				complete = false
			end
		end
		if complete then
			worlds += 1
		end
	end
	local full = eggs == #Config.eggs
	local extra = worlds * Config.constants.index_world_bonus
		+ (if full then Config.constants.index_full_bonus else 0)
	return {
		eggs = eggs,
		worlds = worlds,
		full = full,
		extraMultiplier = 1 + extra,
		bonusPercent = ((1 + eggs * Config.constants.index_egg_bonus) * (1 + extra) - 1) * 100,
	}
end
return CollectionRewards
