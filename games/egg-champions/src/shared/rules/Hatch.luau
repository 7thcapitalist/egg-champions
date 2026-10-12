--!strict
--[[
	Hatch: which pet comes out of an egg, and which variant it rolls.

	Each egg holds exactly one pet of each rarity. A hatch makes two
	independent draws from the injected rng:

	1. Rarity, from rarities[].hatch_chance. The pet is the one pet of that
	   rarity in that egg.
	2. Variant, from variants[].hatch_chance. Variants are checked rarest
	   first (golden before shiny), so the rarer result wins and a hatch is
	   never both.

	The rng is anything with the Random:NextNumber() shape, returning a number
	in [0, 1). Hatch.seededRng gives a pure Luau one for headless tests.

	Every number comes from Config. The module refuses to load if the rarity
	chances do not sum to 1, if the variant chances sum past 1, or if an egg
	does not hold exactly one pet of each rarity.
]]

local Config = require(script.Parent.Parent.Config)

export type Rng = {
	NextNumber: (self: any, ...any) -> number,
}

export type Options = {
	-- The Lucky Eggs pass: doubles Epic and Legendary, paid for out of Common.
	luckyEggs: boolean?,
}

export type Result = {
	petId: string,
	variant: string?,
}

export type OddsEntry = {
	rarity: string,
	chance: number,
}

-- How far a probability sum may drift from 1 before the config is rejected.
local SUM_TOLERANCE = 1e-9

-- The rarities Lucky Eggs doubles, and the one that pays for them. These name
-- the pass's effect in the spec ("Doubles Epic and Legendary odds"), not a number.
local LUCKY_BOOSTED = { "epic", "legendary" }
local LUCKY_SOURCE = "common"
local LUCKY_FACTOR = 2

local Hatch = {}

-- Load time checks

local function sumOf(entries: { OddsEntry }): number
	local total = 0
	for _, entry in entries do
		total += entry.chance
	end
	return total
end

-- The base odds table, in config rarity order.
local baseOdds: { OddsEntry } = {}
do
	local ordered = table.clone(Config.rarities)
	table.sort(ordered, function(a: Config.Rarity, b: Config.Rarity): boolean
		return a.order < b.order
	end)
	for _, rarity in ordered do
		if rarity.hatch_chance < 0 then
			error(string.format("Hatch: rarity %s has a negative hatch_chance", rarity.id))
		end
		table.insert(baseOdds, { rarity = rarity.id, chance = rarity.hatch_chance })
	end
	local total = sumOf(baseOdds)
	if math.abs(total - 1) > SUM_TOLERANCE then
		error(string.format("Hatch: rarity hatch_chance values sum to %.12f, not 1", total))
	end
end

-- Variants, rarest first, so the rarer result wins.
local variantOrder: { Config.Variant } = table.clone(Config.variants)
do
	table.sort(variantOrder, function(a: Config.Variant, b: Config.Variant): boolean
		return a.hatch_chance < b.hatch_chance
	end)
	local total = 0
	for _, variant in variantOrder do
		if variant.hatch_chance < 0 then
			error(string.format("Hatch: variant %s has a negative hatch_chance", variant.id))
		end
		total += variant.hatch_chance
	end
	if total > 1 + SUM_TOLERANCE then
		error(string.format("Hatch: variant hatch_chance values sum to %.12f, past 1", total))
	end
end

-- petByEggAndRarity[eggId][rarityId] = petId, exactly one per pair.
local petByEggAndRarity: { [string]: { [string]: string } } = {}
do
	for _, egg in Config.eggs do
		petByEggAndRarity[egg.id] = {}
	end
	for _, pet in Config.pets do
		local slots = petByEggAndRarity[pet.egg]
		if slots[pet.rarity] ~= nil then
			error(
				string.format(
					"Hatch: egg %s has two %s pets (%s and %s)",
					pet.egg,
					pet.rarity,
					slots[pet.rarity],
					pet.id
				)
			)
		end
		slots[pet.rarity] = pet.id
	end
	for eggId, slots in petByEggAndRarity do
		for _, entry in baseOdds do
			if slots[entry.rarity] == nil then
				error(string.format("Hatch: egg %s has no %s pet", eggId, entry.rarity))
			end
		end
	end
end

-- Odds

-- The rarity odds table for these options, in config rarity order. The result
-- is a fresh table that always sums to 1.
function Hatch.odds(options: Options?): { OddsEntry }
	local odds: { OddsEntry } = {}
	for _, entry in baseOdds do
		table.insert(odds, { rarity = entry.rarity, chance = entry.chance })
	end
	if options ~= nil and options.luckyEggs == true then
		local byId: { [string]: OddsEntry } = {}
		for _, entry in odds do
			byId[entry.rarity] = entry
		end
		local source = byId[LUCKY_SOURCE]
		local added = 0
		for _, rarityId in LUCKY_BOOSTED do
			local entry = byId[rarityId]
			added += entry.chance * (LUCKY_FACTOR - 1)
			entry.chance *= LUCKY_FACTOR
		end
		source.chance = math.max(0, source.chance - added)
		local total = sumOf(odds)
		for _, entry in odds do
			entry.chance /= total
		end
	end
	return odds
end

-- Rolling

local function draw(rng: Rng): number
	local value = rng:NextNumber()
	if type(value) ~= "number" or value < 0 or value >= 1 then
		error("Hatch: rng:NextNumber() must return a number in [0, 1), got " .. tostring(value))
	end
	return value
end

local function pickRarity(odds: { OddsEntry }, value: number): string
	local cumulative = 0
	for _, entry in odds do
		cumulative += entry.chance
		if value < cumulative then
			return entry.rarity
		end
	end
	-- Float rounding can leave the last edge a hair under 1.
	for position = #odds, 1, -1 do
		if odds[position].chance > 0 then
			return odds[position].rarity
		end
	end
	error("Hatch: the odds table is empty")
end

local function pickVariant(value: number): string?
	local cumulative = 0
	for _, variant in variantOrder do
		cumulative += variant.hatch_chance
		if value < cumulative then
			return variant.id
		end
	end
	return nil
end

-- One hatch from eggId: { petId, variant } with variant nil, "shiny" or "golden".
function Hatch.roll(eggId: string, rng: Rng, options: Options?): Result
	local slots = petByEggAndRarity[eggId]
	if slots == nil then
		error(string.format("Hatch.roll: unknown egg %s", tostring(eggId)), 2)
	end
	local rarity = pickRarity(Hatch.odds(options), draw(rng))
	local variant = pickVariant(draw(rng))
	return { petId = slots[rarity], variant = variant }
end

-- count independent hatches, for Triple Hatch.
function Hatch.rollMany(eggId: string, rng: Rng, options: Options?, count: number): { Result }
	if count < 0 or count % 1 ~= 0 then
		error(
			string.format("Hatch.rollMany: count must be a whole number, got %s", tostring(count)),
			2
		)
	end
	local results: { Result } = {}
	for _ = 1, count do
		table.insert(results, Hatch.roll(eggId, rng, options))
	end
	return results
end

-- Pure Luau fallback rng

-- Park and Miller's minimal standard generator. Every product stays below
-- 2^53, so it is exact in Luau numbers and repeats on every platform.
local MODULUS = 2147483647
local MULTIPLIER = 48271

type SeededRng = {
	state: number,
	NextNumber: (self: SeededRng) -> number,
}

local function nextNumber(self: SeededRng): number
	self.state = (self.state * MULTIPLIER) % MODULUS
	return (self.state - 1) / (MODULUS - 1)
end

-- A deterministic rng with the Random:NextNumber() shape, for headless tests.
function Hatch.seededRng(seed: number): Rng
	local state = math.floor(math.abs(seed)) % MODULUS
	if state == 0 then
		state = 1
	end
	local rng: SeededRng = { state = state, NextNumber = nextNumber }
	return (rng :: any) :: Rng
end

return Hatch
