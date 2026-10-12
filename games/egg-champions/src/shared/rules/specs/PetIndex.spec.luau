--!strict
local Runner = require(script.Parent.Parent.Parent.testing.Runner)
local Config = require(script.Parent.Parent.Parent.Config)
local PetIndex = require(script.Parent.Parent.PetIndex)

local describe = Runner.describe
local it = Runner.it
local expect = Runner.expect

local function petsOf(eggId: string): { Config.Pet }
	local list = {}
	for _, pet in Config.pets do
		if pet.egg == eggId then
			table.insert(list, pet)
		end
	end
	return list
end

return function()
	describe("PetIndex.record", function()
		it("tracks normal, shiny and golden separately", function()
			local index = PetIndex.new()
			local petId = Config.pets[1].id
			expect(PetIndex.record(index, petId, "shiny")).toBeTrue()
			expect(PetIndex.hasSeen(index, petId, "shiny")).toBeTrue()
			expect(PetIndex.hasSeen(index, petId, nil)).toBeFalse()
			expect(PetIndex.hasSeen(index, petId, "golden")).toBeFalse()
			expect(PetIndex.record(index, petId, nil)).toBeTrue()
			expect(PetIndex.record(index, petId, "golden")).toBeTrue()
			expect(index[petId]).toEqual({ normal = true, shiny = true, golden = true })
		end)

		it("returns false when the slot was already seen", function()
			local index = PetIndex.new()
			local petId = Config.pets[1].id
			expect(PetIndex.record(index, petId, nil)).toBeTrue()
			expect(PetIndex.record(index, petId, nil)).toBeFalse()
		end)

		it("errors on an unknown pet or variant", function()
			expect(function()
				PetIndex.record(PetIndex.new(), "no_such_pet", nil)
			end).toThrow()
			expect(function()
				PetIndex.record(PetIndex.new(), Config.pets[1].id, "no_such_variant")
			end).toThrow()
		end)
	end)

	describe("PetIndex.isEggComplete", function()
		it("completes only after all pets_per_egg normal pets", function()
			for _, egg in Config.eggs do
				local pets = petsOf(egg.id)
				expect(#pets).toEqual(Config.constants.pets_per_egg)
				local index = PetIndex.new()
				for _, pet in pets do
					expect(PetIndex.isEggComplete(index, egg.id)).toBeFalse()
					PetIndex.record(index, pet.id, nil)
				end
				expect(PetIndex.isEggComplete(index, egg.id)).toBeTrue()
				expect(PetIndex.completedEggs(index)).toEqual(1)
			end
		end)

		it("is not completed by a shiny pet alone", function()
			local egg = Config.eggs[1]
			local pets = petsOf(egg.id)
			local index = PetIndex.new()
			for i, pet in pets do
				PetIndex.record(index, pet.id, if i == #pets then "shiny" else nil)
			end
			expect(PetIndex.isEggComplete(index, egg.id)).toBeFalse()
			PetIndex.record(index, pets[#pets].id, "golden")
			expect(PetIndex.isEggComplete(index, egg.id)).toBeFalse()
			PetIndex.record(index, pets[#pets].id, nil)
			expect(PetIndex.isEggComplete(index, egg.id)).toBeTrue()
		end)

		it("is not completed by every pet seen only as shiny or golden", function()
			local egg = Config.eggs[1]
			local index = PetIndex.new()
			for _, pet in petsOf(egg.id) do
				PetIndex.record(index, pet.id, "shiny")
				PetIndex.record(index, pet.id, "golden")
			end
			expect(PetIndex.isEggComplete(index, egg.id)).toBeFalse()
		end)
	end)

	describe("PetIndex.fruitEdition", function()
		it("lists only seen pets whose config edition is set, in config order", function()
			local fruit: { string } = {}
			for _, pet in Config.pets do
				if pet.edition ~= nil then
					table.insert(fruit, pet.id)
				end
			end
			expect(#fruit > 0).toBeTrue()

			local index = PetIndex.new()
			expect(PetIndex.fruitEdition(index)).toEqual({})
			for _, pet in Config.pets do
				if pet.edition == nil then
					PetIndex.record(index, pet.id, nil)
				end
			end
			expect(PetIndex.fruitEdition(index)).toEqual({})

			PetIndex.record(index, fruit[#fruit], "golden")
			expect(PetIndex.fruitEdition(index)).toEqual({ fruit[#fruit] })
			for _, petId in fruit do
				PetIndex.record(index, petId, nil)
			end
			expect(PetIndex.fruitEdition(index)).toEqual(fruit)
		end)
	end)
end
