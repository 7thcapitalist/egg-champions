--!strict
local Runner = require(script.Parent.Parent.Parent.testing.Runner)
local Config = require(script.Parent.Parent.Parent.Config)
local Hatch = require(script.Parent.Parent.Hatch)

local describe = Runner.describe
local it = Runner.it
local expect = Runner.expect

local EPSILON = 1e-9

-- An rng that walks the unit interval in even steps: (i - 0.5) / steps.
local function walkingRng(steps: number): Hatch.Rng
	local i = 0
	return {
		NextNumber = function(_self: any): number
			i = i % steps + 1
			return (i - 0.5) / steps
		end,
	}
end

-- An rng that returns a fixed list of values in order, then repeats.
local function scriptedRng(values: { number }): Hatch.Rng
	local i = 0
	return {
		NextNumber = function(_self: any): number
			i = i % #values + 1
			return values[i]
		end,
	}
end

local function chanceOf(odds: { Hatch.OddsEntry }, rarityId: string): number
	for _, entry in odds do
		if entry.rarity == rarityId then
			return entry.chance
		end
	end
	error("no odds entry for " .. rarityId)
end

local function sum(odds: { Hatch.OddsEntry }): number
	local total = 0
	for _, entry in odds do
		total += entry.chance
	end
	return total
end

return function()
	describe("Hatch odds", function()
		it("has config rarity chances that sum to 1", function()
			local total = 0
			for _, rarity in Config.rarities do
				total += rarity.hatch_chance
			end
			expect(total).toBeCloseTo(1, EPSILON)
			expect(sum(Hatch.odds())).toBeCloseTo(1, EPSILON)
		end)

		it("matches config exactly without options", function()
			local odds = Hatch.odds()
			expect(#odds).toEqual(#Config.rarities)
			for _, rarity in Config.rarities do
				expect(chanceOf(odds, rarity.id)).toBeCloseTo(rarity.hatch_chance, EPSILON)
			end
		end)

		it("Lucky Eggs doubles Epic and Legendary, takes it off Common, sums to 1", function()
			local odds = Hatch.odds({ luckyEggs = true })
			local r = Config.rarityById
			expect(sum(odds)).toBeCloseTo(1, EPSILON)
			expect(chanceOf(odds, "epic")).toBeCloseTo(2 * r.epic.hatch_chance, EPSILON)
			expect(chanceOf(odds, "legendary")).toBeCloseTo(2 * r.legendary.hatch_chance, EPSILON)
			local added = r.epic.hatch_chance + r.legendary.hatch_chance
			expect(chanceOf(odds, "common")).toBeCloseTo(r.common.hatch_chance - added, EPSILON)
			expect(chanceOf(odds, "uncommon")).toBeCloseTo(r.uncommon.hatch_chance, EPSILON)
			expect(chanceOf(odds, "rare")).toBeCloseTo(r.rare.hatch_chance, EPSILON)
		end)

		it("luckyEggs = false is the same as no options", function()
			local plain = Hatch.odds()
			local off = Hatch.odds({ luckyEggs = false })
			for position, entry in plain do
				expect(off[position].chance).toBeCloseTo(entry.chance, EPSILON)
			end
		end)
	end)

	describe("Hatch.roll", function()
		it("gives a repeatable sequence from a seeded rng", function()
			local egg = Config.eggs[1].id
			local first = Hatch.rollMany(egg, Hatch.seededRng(12345), nil, 50)
			local second = Hatch.rollMany(egg, Hatch.seededRng(12345), nil, 50)
			expect(first).toEqual(second)
			local other = Hatch.rollMany(egg, Hatch.seededRng(54321), nil, 50)
			local differs = false
			for i, result in first do
				if result.petId ~= other[i].petId or result.variant ~= other[i].variant then
					differs = true
				end
			end
			expect(differs).toBeTrue()
		end)

		it("hatches each rarity at its config rate", function()
			-- Two draws per hatch, so the rarity draws visit every other step of
			-- the walk and still cover the unit interval evenly.
			local hatches = 20000
			local tolerance = 0.001
			for _, egg in Config.eggs do
				local rng = walkingRng(hatches * 2)
				local counts: { [string]: number } = {}
				for _ = 1, hatches do
					local result = Hatch.roll(egg.id, rng)
					local pet = Config.petById[result.petId]
					expect(pet.egg).toEqual(egg.id)
					counts[pet.rarity] = (counts[pet.rarity] or 0) + 1
				end
				for _, rarity in Config.rarities do
					local rate = (counts[rarity.id] or 0) / hatches
					expect(math.abs(rate - rarity.hatch_chance) <= tolerance).toBeTrue()
				end
			end
		end)

		it("hatches each rarity at the Lucky Eggs rate with the flag", function()
			local hatches = 20000
			local tolerance = 0.001
			local odds = Hatch.odds({ luckyEggs = true })
			local rng = walkingRng(hatches * 2)
			local counts: { [string]: number } = {}
			for _ = 1, hatches do
				local result = Hatch.roll(Config.eggs[1].id, rng, { luckyEggs = true })
				local rarity = Config.petById[result.petId].rarity
				counts[rarity] = (counts[rarity] or 0) + 1
			end
			for _, entry in odds do
				local rate = (counts[entry.rarity] or 0) / hatches
				expect(math.abs(rate - entry.chance) <= tolerance).toBeTrue()
			end
		end)

		it("rolls variants at their config rates and never both", function()
			local hatches = 20000
			local tolerance = 0.001
			local rng = walkingRng(hatches * 2)
			local counts: { [string]: number } = {}
			for _ = 1, hatches do
				local result = Hatch.roll(Config.eggs[1].id, rng)
				local variant = result.variant
				if variant ~= nil then
					expect(variant == "shiny" or variant == "golden").toBeTrue()
					counts[variant] = (counts[variant] or 0) + 1
				end
			end
			for _, variant in Config.variants do
				local rate = (counts[variant.id] or 0) / hatches
				expect(math.abs(rate - variant.hatch_chance) <= tolerance).toBeTrue()
			end
		end)

		it("checks golden before shiny so the rarer result wins", function()
			local egg = Config.eggs[1].id
			local golden = Config.variantById.golden.hatch_chance
			local shiny = Config.variantById.shiny.hatch_chance
			-- Each pair is (rarity draw, variant draw).
			local rng = scriptedRng({ 0, 0, 0, golden, 0, golden + shiny })
			expect(Hatch.roll(egg, rng).variant).toEqual("golden")
			expect(Hatch.roll(egg, rng).variant).toEqual("shiny")
			expect(Hatch.roll(egg, rng).variant).toEqual(nil)
		end)

		it("never gives golden and shiny on one hatch over many seeded hatches", function()
			for _, result in Hatch.rollMany(Config.eggs[1].id, Hatch.seededRng(7), nil, 5000) do
				local variant = result.variant
				expect(variant == nil or variant == "shiny" or variant == "golden").toBeTrue()
			end
		end)

		it("gives the one pet of the rolled rarity in that egg", function()
			for _, egg in Config.eggs do
				local rng = scriptedRng({ 0.999999, 0.999999 })
				local pet = Config.petById[Hatch.roll(egg.id, rng).petId]
				expect(pet.egg).toEqual(egg.id)
				expect(pet.rarity).toEqual("legendary")
			end
		end)

		it("errors on an unknown egg and on a bad rng value", function()
			expect(function()
				Hatch.roll("no_such_egg", Hatch.seededRng(1))
			end).toThrow()
			expect(function()
				Hatch.roll(Config.eggs[1].id, scriptedRng({ 1 }))
			end).toThrow()
		end)
	end)

	describe("Hatch.rollMany", function()
		it("returns count independent hatches", function()
			local egg = Config.eggs[1].id
			local results = Hatch.rollMany(egg, Hatch.seededRng(99), nil, 3)
			expect(#results).toEqual(3)
			local rng = Hatch.seededRng(99)
			for _, result in results do
				expect(Hatch.roll(egg, rng)).toEqual(result)
			end
		end)

		it("rolls nothing for a count of 0", function()
			expect(#Hatch.rollMany(Config.eggs[1].id, Hatch.seededRng(1), nil, 0)).toEqual(0)
		end)
	end)

	describe("Hatch.seededRng", function()
		it("returns numbers in [0, 1)", function()
			local rng = Hatch.seededRng(0)
			for _ = 1, 1000 do
				local value = rng:NextNumber()
				expect(value >= 0 and value < 1).toBeTrue()
			end
		end)
	end)
end
