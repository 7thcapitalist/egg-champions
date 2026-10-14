--!strict
local Runner = require(script.Parent.Parent.Parent.testing.Runner)
local Config = require(script.Parent.Parent.Parent.Config)
local PetLook = require(script.Parent.Parent.PetLook)

local describe = Runner.describe
local it = Runner.it
local expect = Runner.expect

local function isChannel(value: any): boolean
	return type(value) == "number" and value >= 0 and value <= 255
end

local function isColor(color: any): boolean
	return type(color) == "table"
		and isChannel(color.r)
		and isChannel(color.g)
		and isChannel(color.b)
end

local function same(a: PetLook.RGB, b: PetLook.RGB): boolean
	return a.r == b.r and a.g == b.g and a.b == b.b
end

return function()
	describe("PetLook.resolve", function()
		it("gives every pet in config a color, a band and a size", function()
			expect(#Config.pets > 0).toBeTrue()
			for _, pet in Config.pets do
				local look = PetLook.resolve(pet.id, nil)
				expect(isColor(look.body)).toBeTrue()
				expect(isColor(look.band)).toBeTrue()
				expect(type(look.size) == "number" and look.size > 0).toBeTrue()
				expect(type(look.feature.attachment) == "string").toBeTrue()
			end
		end)

		it("has a body color for every type in config", function()
			for _, petType in Config.types do
				expect(PetLook.TYPE_COLORS[petType.id] ~= nil).toBeTrue()
				expect(PetLook.FEATURES[petType.id] ~= nil).toBeTrue()
			end
		end)

		it("makes higher rarities larger", function()
			local ordered = table.clone(Config.rarities)
			table.sort(ordered, function(a, b)
				return a.order < b.order
			end)
			for i = 2, #ordered do
				expect(PetLook.size(ordered[i].id) > PetLook.size(ordered[i - 1].id)).toBeTrue()
			end
		end)

		it("gives each rarity its own band color", function()
			local seen: { string } = {}
			for _, rarity in Config.rarities do
				local c = PetLook.rarityColor(rarity.id)
				local key = string.format("%d,%d,%d", c.r, c.g, c.b)
				expect(table.find(seen, key)).toEqual(nil)
				table.insert(seen, key)
			end
		end)

		it("gives fire, electric and water an accent and grass none", function()
			expect(PetLook.feature("fire").accent).toBeTrue()
			expect(PetLook.feature("electric").accent).toBeTrue()
			expect(PetLook.feature("water").accent).toBeTrue()
			expect(PetLook.feature("grass").accent).toBeFalse()
		end)

		it("keeps normal, shiny and golden looks apart", function()
			local petId = Config.pets[1].id
			local normal = PetLook.resolve(petId, nil)
			local shiny = PetLook.resolve(petId, "shiny")
			local golden = PetLook.resolve(petId, "golden")
			expect(normal.shiny or normal.golden).toBeFalse()
			expect(shiny.shiny).toBeTrue()
			expect(shiny.golden).toBeFalse()
			expect(golden.golden).toBeTrue()
			expect(golden.shiny).toBeFalse()
			expect(same(normal.body, shiny.body)).toBeFalse()
			expect(same(normal.body, golden.body)).toBeFalse()
			expect(same(shiny.body, golden.body)).toBeFalse()
			expect(PetLook.key(normal) ~= PetLook.key(shiny)).toBeTrue()
		end)

		it("only knows the variants in config", function()
			for _, variant in Config.variants do
				expect(PetLook.resolve(Config.pets[1].id, variant.id).variant).toEqual(variant.id)
			end
			expect(function()
				PetLook.resolve(Config.pets[1].id, "sparkly")
			end).toThrow()
		end)

		it("uses the placeholder block until the asset stage fills MODEL_IDS", function()
			for _, pet in Config.pets do
				expect(PetLook.resolve(pet.id, nil).modelId).toEqual(PetLook.MODEL_IDS[pet.id])
			end
		end)
	end)

	describe("PetLook.resolveType", function()
		it("gives a gym leader pet a look from its type alone", function()
			for _, petType in Config.types do
				local look = PetLook.resolveType(petType.id, nil)
				expect(look.petId).toEqual(nil)
				expect(isColor(look.body)).toBeTrue()
				expect(look.size > 0).toBeTrue()
			end
		end)
	end)
end
