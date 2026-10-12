--!strict
local Runner = require(script.Parent.Parent.Parent.testing.Runner)
local Config = require(script.Parent.Parent.Parent.Config)
local Coins = require(script.Parent.Parent.Coins)

local describe = Runner.describe
local it = Runner.it
local expect = Runner.expect

local EPSILON = 1e-9

local constants = Config.constants

local function emptyState(rebirths: number, completedEggs: number): Coins.ClickState
	return { team = {}, rebirths = rebirths, completedEggs = completedEggs }
end

-- The normal pets of an egg, in config order.
local function petsOf(eggId: string): { Config.Pet }
	local list = {}
	for _, pet in Config.pets do
		if pet.egg == eggId then
			table.insert(list, pet)
		end
	end
	return list
end

-- An index holding every pet of every egg in the given variant slot.
local function fullIndex(slot: string): Coins.PetIndex
	local index: Coins.PetIndex = {}
	for _, pet in Config.pets do
		local entry: any = {}
		entry[slot] = true
		index[pet.id] = entry
	end
	return index
end

return function()
	describe("Coins.perClick", function()
		it("earns 1 coin per click with an empty team", function()
			expect(Coins.perClick(emptyState(0, 0))).toEqual(1)
		end)

		it("adds exactly rebirth_coin_bonus per rebirth", function()
			for _, rebirths in { 0, 1, 5 } do
				local expected = 1 + constants.rebirth_coin_bonus * rebirths
				expect(Coins.perClick(emptyState(rebirths, 0))).toBeCloseTo(expected, EPSILON)
			end
			local step = Coins.perClick(emptyState(1, 0)) - Coins.perClick(emptyState(0, 0))
			expect(step).toBeCloseTo(constants.rebirth_coin_bonus, EPSILON)
		end)

		it("adds exactly index_egg_bonus per completed egg", function()
			expect(Coins.perClick(emptyState(0, 0))).toEqual(1)
			local eggs = #Config.eggs
			expect(Coins.perClick(emptyState(0, eggs))).toBeCloseTo(
				1 + constants.index_egg_bonus * eggs,
				EPSILON
			)
			expect(Coins.perClick(emptyState(0, 6))).toBeCloseTo(
				1 + constants.index_egg_bonus * 6,
				EPSILON
			)
		end)

		it("adds the team's Click Power to the base of 1", function()
			local team: { Coins.OwnedPet } = {}
			local sum = 0
			for i = 1, constants.team_size do
				local pet = Config.pets[i]
				table.insert(team, { petId = pet.id })
				sum += pet.click_power
			end
			expect(Coins.perClick({ team = team, rebirths = 0, completedEggs = 0 })).toBeCloseTo(
				1 + sum,
				EPSILON
			)
		end)

		it("multiplies every factor together", function()
			local pet = Config.pets[1]
			local team = { { petId = pet.id, variant = "golden" } }
			local state: Coins.ClickState =
				{ team = team, rebirths = 2, completedEggs = 3, passMultiplier = 2 }
			local expected = (1 + pet.click_power * Config.variantById.golden.click_mult)
				* (1 + constants.rebirth_coin_bonus * 2)
				* (1 + constants.index_egg_bonus * 3)
				* 2
			expect(Coins.perClick(state)).toBeCloseTo(expected, EPSILON)
		end)

		it("takes the pass multiplier as an input, defaulting to 1", function()
			local base = Coins.perClick(emptyState(1, 1))
			local state = emptyState(1, 1)
			state.passMultiplier = 2
			expect(Coins.perClick(state)).toBeCloseTo(base * 2, EPSILON)
		end)
	end)

	describe("Coins.clickPowerOf", function()
		it("is the config Click Power for a normal pet", function()
			for _, pet in Config.pets do
				expect(Coins.clickPowerOf({ petId = pet.id })).toEqual(pet.click_power)
			end
		end)

		it("multiplies by the shiny and golden config values", function()
			for _, variant in Config.variants do
				expect(variant.click_mult ~= 1).toBeTrue()
				for _, pet in Config.pets do
					local power = Coins.clickPowerOf({ petId = pet.id, variant = variant.id })
					expect(power).toBeCloseTo(pet.click_power * variant.click_mult, EPSILON)
				end
			end
			local pet = Config.pets[1]
			expect(Coins.clickPowerOf({ petId = pet.id, variant = "shiny" })).toBeCloseTo(
				pet.click_power * Config.variantById.shiny.click_mult,
				EPSILON
			)
			expect(Coins.clickPowerOf({ petId = pet.id, variant = "golden" })).toBeCloseTo(
				pet.click_power * Config.variantById.golden.click_mult,
				EPSILON
			)
		end)

		it("errors on an unknown pet or variant", function()
			expect(function()
				Coins.clickPowerOf({ petId = "no_such_pet" })
			end).toThrow()
			expect(function()
				Coins.clickPowerOf({ petId = Config.pets[1].id, variant = "no_such_variant" })
			end).toThrow()
		end)
	end)

	describe("Coins.completedEggs", function()
		it("is 0 for an empty index", function()
			expect(Coins.completedEggs({})).toEqual(0)
		end)

		it("counts every egg once all its normal pets are seen", function()
			expect(Coins.completedEggs(fullIndex("normal"))).toEqual(#Config.eggs)
		end)

		it("does not count shiny or golden hatches toward completion", function()
			expect(Coins.completedEggs(fullIndex("shiny"))).toEqual(0)
			expect(Coins.completedEggs(fullIndex("golden"))).toEqual(0)
		end)

		it("completes an egg only on its last normal pet", function()
			local egg = Config.eggs[1]
			local pets = petsOf(egg.id)
			expect(#pets).toEqual(constants.pets_per_egg)
			local index: Coins.PetIndex = {}
			for i, pet in pets do
				expect(Coins.isEggComplete(index, egg.id)).toBeFalse()
				index[pet.id] = { normal = true }
				expect(Coins.completedEggs(index)).toEqual(if i == #pets then 1 else 0)
			end
			expect(Coins.isEggComplete(index, egg.id)).toBeTrue()
		end)

		it("does not complete an egg when the last pet is only shiny", function()
			local egg = Config.eggs[1]
			local pets = petsOf(egg.id)
			local index: Coins.PetIndex = {}
			for i, pet in pets do
				index[pet.id] = if i == #pets
					then { shiny = true, golden = true }
					else { normal = true }
			end
			expect(Coins.isEggComplete(index, egg.id)).toBeFalse()
			expect(Coins.completedEggs(index)).toEqual(0)
		end)
	end)
end
