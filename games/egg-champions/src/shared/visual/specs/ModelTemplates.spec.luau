--!strict
local Runner = require(script.Parent.Parent.Parent.testing.Runner)
local Config = require(script.Parent.Parent.Parent.Config)
local PetLook = require(script.Parent.Parent.PetLook)
local ModelTemplates = require(script.Parent.Parent.ModelTemplates)

local describe = Runner.describe
local it = Runner.it
local expect = Runner.expect

local ReplicatedStorage = (script.Parent.Parent.Parent :: Instance).Parent :: Instance
local models: ModelTemplates.Table = require(
	(ReplicatedStorage:WaitForChild("GameConfig") :: Instance):WaitForChild("models") :: any
)

type Fake = {
	kit: ModelTemplates.Kit,
	calls: { [string]: number },
	waits: { number },
	warnings: { string },
	dressed: { [string]: { texture: string, scale: number, attachment: string? } },
}

-- A Kit whose parts are plain tables. failures[uri] is how many tries fail
-- before one works; heights[uri] overrides the mesh height.
local function fake(failures: { [string]: number }, heights: { [string]: number }): Fake
	local state: Fake = nil :: any
	state = {
		calls = {},
		waits = {},
		warnings = {},
		dressed = {},
		kit = {
			createMeshPart = function(uri: string): any
				state.calls[uri] = (state.calls[uri] or 0) + 1
				if state.calls[uri] <= (failures[uri] or 0) then
					error("HTTP 429 (Too Many Requests)")
				end
				return { uri = uri, height = heights[uri] or 2 }
			end,
			height = function(part: any): number
				return part.height
			end,
			dress = function(_part: any, entry, textureUri, scale, attachment)
				state.dressed[entry.id] =
					{ texture = textureUri, scale = scale, attachment = attachment }
			end,
			wait = function(seconds: number)
				table.insert(state.waits, seconds)
			end,
			warn = function(message: string)
				table.insert(state.warnings, message)
			end,
		},
	}
	return state
end

local function entry(id: string, kind: string, mesh: number, height: number): ModelTemplates.Entry
	return { id = id, kind = kind, mesh_id = mesh, texture_id = mesh + 1, height = height }
end

local function has(list: { string }, text: string): boolean
	for _, line in list do
		if string.find(line, text, 1, true) then
			return true
		end
	end
	return false
end

return function()
	describe("the model table", function()
		it("has one entry for every pet and every egg in config", function()
			local byId: { [string]: ModelTemplates.Entry } = {}
			for _, item in models.entries do
				byId[item.id] = item
			end
			for _, pet in Config.pets do
				expect(byId[pet.id] ~= nil and byId[pet.id].kind == "pet").toBeTrue()
			end
			for _, egg in Config.eggs do
				expect(byId[egg.id] ~= nil and byId[egg.id].kind == "egg").toBeTrue()
			end
			expect(#models.entries).toEqual(#Config.pets + #Config.eggs)
		end)

		it("gives every entry positive integer ids and a positive height", function()
			for _, item in models.entries do
				expect(item.mesh_id > 0 and item.mesh_id == math.floor(item.mesh_id)).toBeTrue()
				expect(item.texture_id > 0 and item.texture_id == math.floor(item.texture_id)).toBeTrue()
				expect(ModelTemplates.scale(1, item.height) ~= nil).toBeTrue()
			end
		end)
	end)

	describe("ModelTemplates helpers", function()
		it("writes large asset ids in full", function()
			expect(ModelTemplates.assetUri(136103984711129)).toEqual("rbxassetid://136103984711129")
		end)

		it("refuses a zero, negative or NaN height", function()
			expect(ModelTemplates.scale(0, 5) == nil).toBeTrue()
			expect(ModelTemplates.scale(2, -1) == nil).toBeTrue()
			expect(ModelTemplates.scale(0 / 0, 5) == nil).toBeTrue()
			expect(ModelTemplates.scale(2, 5) :: number).toBeCloseTo(2.5)
		end)

		it("gives pets their type's feature attachment and eggs none", function()
			local pet = Config.pets[1]
			local expected = PetLook.resolve(pet.id, nil).feature.attachment
			expect(ModelTemplates.attachmentFor(entry(pet.id, "pet", 1, 1))).toEqual(expected)
			expect(ModelTemplates.attachmentFor(entry(Config.eggs[1].id, "egg", 1, 1)) == nil).toBeTrue()
		end)

		it("builds the seam only from pet ids", function()
			local pet = Config.pets[1].id
			local seam = ModelTemplates.seamFrom({ pet, Config.eggs[1].id, "not_a_pet" })
			expect(seam).toEqual({ [pet] = pet })
		end)
	end)

	describe("ModelTemplates.load", function()
		it("scales each model to its entry's height and fills the seam for pets", function()
			local pet = Config.pets[1].id
			local egg = Config.eggs[1].id
			local f = fake({}, { ["rbxassetid://10"] = 4 })
			local report =
				ModelTemplates.load({ entry(pet, "pet", 10, 5), entry(egg, "egg", 20, 3) }, f.kit)
			expect(report.loaded).toEqual({ pet, egg })
			expect(#report.failed).toEqual(0)
			expect(report.modelIds).toEqual({ [pet] = pet })
			expect(f.dressed[pet].scale).toBeCloseTo(1.25)
			expect(f.dressed[pet].texture).toEqual("rbxassetid://11")
			expect(f.dressed[egg].scale).toBeCloseTo(1.5)
			expect(f.dressed[egg].attachment == nil).toBeTrue()
		end)

		it("retries a failing mesh and waits between tries", function()
			local pet = Config.pets[1].id
			local f = fake({ ["rbxassetid://10"] = ModelTemplates.TRIES - 1 }, {})
			local report = ModelTemplates.load({ entry(pet, "pet", 10, 5) }, f.kit)
			expect(report.loaded).toEqual({ pet })
			expect(f.calls["rbxassetid://10"]).toEqual(ModelTemplates.TRIES)
			expect(#f.waits).toEqual(ModelTemplates.TRIES - 1)
		end)

		it("gives up after TRIES, logs the id and keeps going", function()
			local first = Config.pets[1].id
			local second = Config.pets[2].id
			local f = fake({ ["rbxassetid://10"] = ModelTemplates.TRIES }, {})
			local report = ModelTemplates.load(
				{ entry(first, "pet", 10, 5), entry(second, "pet", 30, 5) },
				f.kit
			)
			expect(f.calls["rbxassetid://10"]).toEqual(ModelTemplates.TRIES)
			expect(#f.waits).toEqual(ModelTemplates.TRIES - 1)
			expect(report.loaded).toEqual({ second })
			expect(#report.failed).toEqual(1)
			expect(report.failed[1].id).toEqual(first)
			expect(report.modelIds[first] == nil).toBeTrue()
			expect(has(f.warnings, first .. " stays a placeholder")).toBeTrue()
		end)

		it(
			"fails an entry whose mesh has no height or whose dressing errors, without raising",
			function()
				local first = Config.pets[1].id
				local second = Config.pets[2].id
				local f = fake({}, { ["rbxassetid://10"] = 0 })
				f.kit.dress = function(_part, item, _texture, _scale, _attachment)
					if item.id == second then
						error("cannot parent")
					end
				end
				local report = ModelTemplates.load(
					{ entry(first, "pet", 10, 5), entry(second, "pet", 30, 5) },
					f.kit
				)
				expect(#report.loaded).toEqual(0)
				expect(#report.failed).toEqual(2)
				expect(has(f.warnings, first)).toBeTrue()
				expect(has(f.warnings, second)).toBeTrue()
			end
		)

		it("puts loaded pets into PetLook.MODEL_IDS", function()
			local pet = Config.pets[1].id
			local before = PetLook.MODEL_IDS[pet]
			ModelTemplates.applySeam({ [pet] = pet })
			expect(PetLook.resolve(pet, nil).modelId).toEqual(pet)
			PetLook.MODEL_IDS[pet] = before
		end)
	end)
end
