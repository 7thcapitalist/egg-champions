--!strict
--[[
	PassEffects: what each game pass does, as plain rules.

	The four passes are read from config/passes.json. This module names the
	effect of each one and nothing else; it never asks who owns what. The
	server (PassService) works out the owned set and hands it in here.

	- 2x_coins: a factor of COIN_FACTOR in the pass multiplier that
	  Coins.perClick takes as an input.
	- lucky_eggs: sets luckyEggs on the options Hatch.roll takes.
	- triple_hatch: allows a hatch count of Hatch.TRIPLE_COUNT.
	- auto_click: the server clicks for the player on an interval.

	COIN_FACTOR names the pass's own effect ("Doubles coins per click"), like
	Hatch.LUCKY_FACTOR and Hatch.TRIPLE_COUNT do for theirs.

	No pass touches battle HP or Attack. That is a spec rule, and it is tested.

	At load, every pass in config must have an entry in HANDLED and every
	entry in HANDLED must be in config, so a new pass cannot be half built.
]]

local Config = require(script.Parent.Parent.Config)
local Hatch = require(script.Parent.Hatch)

-- The owned passes, keyed by config pass id.
export type Owned = { [string]: boolean }

local COIN_FACTOR = 2

local PassEffects = {}

PassEffects.COIN_FACTOR = COIN_FACTOR

PassEffects.ids = table.freeze({
	coins = "2x_coins",
	autoClick = "auto_click",
	luckyEggs = "lucky_eggs",
	tripleHatch = "triple_hatch",
})

-- Every pass id this module gives an effect to.
PassEffects.HANDLED = table.freeze({
	PassEffects.ids.coins,
	PassEffects.ids.autoClick,
	PassEffects.ids.luckyEggs,
	PassEffects.ids.tripleHatch,
})

-- Load time check: the handled ids and the config ids are the same set.
do
	local inConfig: { [string]: boolean } = {}
	for _, pass in Config.passes do
		inConfig[pass.id] = true
	end
	local handled: { [string]: boolean } = {}
	for _, id in PassEffects.HANDLED do
		handled[id] = true
		if inConfig[id] ~= true then
			error(string.format("PassEffects handles %q, which config/passes.json lacks", id))
		end
	end
	for _, pass in Config.passes do
		if handled[pass.id] ~= true then
			error(string.format("PassEffects has no effect for the config pass %q", pass.id))
		end
	end
end

local function has(owned: Owned?, id: string): boolean
	return owned ~= nil and owned[id] == true
end

-- The product of every owned pass's coin factor, for Coins.perClick.
function PassEffects.coinMultiplier(owned: Owned?): number
	local multiplier = 1
	if has(owned, PassEffects.ids.coins) then
		multiplier *= COIN_FACTOR
	end
	return multiplier
end

-- The options Hatch.roll and Hatch.odds take for this owned set.
function PassEffects.hatchOptions(owned: Owned?): Hatch.Options
	return { luckyEggs = has(owned, PassEffects.ids.luckyEggs) }
end

-- True when a hatch of this many eggs at once is allowed.
function PassEffects.hatchCountAllowed(owned: Owned?, count: number): boolean
	if count == 1 then
		return true
	end
	return count == Hatch.TRIPLE_COUNT and has(owned, PassEffects.ids.tripleHatch)
end

-- True when the server should click for the player on its interval.
function PassEffects.autoClick(owned: Owned?): boolean
	return has(owned, PassEffects.ids.autoClick)
end

-- An owned set with every handled pass on, for tests and tools.
function PassEffects.all(): Owned
	local owned: Owned = {}
	for _, id in PassEffects.HANDLED do
		owned[id] = true
	end
	return owned
end

return PassEffects
