--!strict
local Runner = require(script.Parent.Parent.Parent.testing.Runner)
local Config = require(script.Parent.Parent.Parent.Config)
local Profile = require(script.Parent.Parent.Profile)

local describe = Runner.describe
local it = Runner.it
local expect = Runner.expect

-- A profile that owns `count` pets with uids "u1" to "uN", all of the first
-- configured pet, and nothing equipped.
local function withPets(count: number): Profile.Profile
	local profile = Profile.new()
	for i = 1, count do
		table.insert(profile.pets, { uid = "u" .. i, petId = Config.pets[1].id, variant = nil })
	end
	return profile
end

local function kindsOf(problems: { Profile.Problem }): { string }
	local kinds = {}
	for _, problem in problems do
		table.insert(kinds, problem.kind)
	end
	return kinds
end

local function hasKind(problems: { Profile.Problem }, kind: string): boolean
	return table.find(kindsOf(problems), kind) ~= nil
end

-- A save as version 1 wrote it: no gymsBeaten or feesPaid yet.
local function v1Save(): any
	return {
		version = 1,
		coins = 12345,
		pets = {
			{ uid = "u1", petId = Config.pets[1].id },
			{ uid = "u2", petId = Config.pets[2].id, variant = Config.variants[1].id },
		},
		team = { "u1", "u2" },
		index = { [Config.pets[1].id] = { normal = true } },
		badges = {},
		rebirths = 2,
	}
end

return function()
	describe("Profile", function()
		it("starts empty at the current version", function()
			local profile = Profile.new()
			expect(profile.version).toEqual(Profile.version)
			expect(profile.coins).toEqual(0)
			expect(profile.rebirths).toEqual(0)
			expect(profile.pets).toEqual({})
			expect(profile.team).toEqual({})
			expect(profile.index).toEqual({})
			expect(profile.badges).toEqual({})
			expect(profile.gymsBeaten).toEqual({})
			expect(profile.feesPaid).toEqual({})
		end)

		it("passes validate when new", function()
			expect(Profile.validate(Profile.new())).toEqual({})
		end)

		it("migrates a v1 profile with its coins and pets intact", function()
			local save = v1Save()
			local migrated = Profile.migrate(save)
			expect(migrated.version).toEqual(Profile.version)
			expect(migrated.coins).toEqual(12345)
			expect(migrated.pets).toEqual(v1Save().pets)
			expect(migrated.team).toEqual({ "u1", "u2" })
			expect(migrated.rebirths).toEqual(2)
			expect(migrated.gymsBeaten).toEqual({})
			expect(migrated.feesPaid).toEqual({})
			expect(Profile.validate(migrated)).toEqual({})
			expect(save.version).toEqual(1)
		end)

		it("leaves a current profile as it is", function()
			local profile = withPets(2)
			profile.coins = 50
			expect(Profile.migrate(profile)).toEqual(profile)
		end)

		it("refuses a newer version rather than resetting it", function()
			local save = v1Save()
			save.version = Profile.version + 1
			expect(function()
				Profile.migrate(save)
			end).toThrow("newer")
		end)

		it("refuses an unknown or missing version", function()
			for _, version in { 0, -1, 1.5, "1" } :: { any } do
				local save = v1Save()
				save.version = version
				expect(function()
					Profile.migrate(save)
				end).toThrow("unknown profile version")
			end
			local missing = v1Save()
			missing.version = nil
			expect(function()
				Profile.migrate(missing)
			end).toThrow("unknown profile version")
			expect(function()
				Profile.migrate("not a table")
			end).toThrow("not a table")
		end)

		it("reports a team uid the player does not own", function()
			local profile = withPets(1)
			profile.team = { "u1", "stolen" }
			local problems = Profile.validate(profile)
			expect(kindsOf(problems)).toEqual({ Profile.problems.teamNotOwned })
			expect(problems[1].repairable).toBeTrue()
		end)

		it("reports a team longer than team_size", function()
			local size = Config.constants.team_size
			local profile = withPets(size + 1)
			for i = 1, size + 1 do
				table.insert(profile.team, "u" .. i)
			end
			expect(hasKind(Profile.validate(profile), Profile.problems.teamTooLong)).toBeTrue()
		end)

		it("reports a petId that is not in config", function()
			local profile = withPets(1)
			profile.pets[1].petId = "no_such_pet"
			local problems = Profile.validate(profile)
			expect(kindsOf(problems)).toEqual({ Profile.problems.unknownPet })
			expect(problems[1].repairable).toBeFalse()
		end)

		it("reports negative coins", function()
			local profile = Profile.new()
			profile.coins = -1
			expect(kindsOf(Profile.validate(profile))).toEqual({ Profile.problems.negativeCoins })
		end)

		it("repairs a bad team and keeps every owned pet", function()
			local size = Config.constants.team_size
			local profile = withPets(size + 1)
			table.insert(profile.team, "stolen")
			for i = 1, size + 1 do
				table.insert(profile.team, "u" .. i)
			end
			local repaired, remaining = Profile.repair(profile)
			expect(remaining).toEqual({})
			expect(#repaired.team).toEqual(size)
			expect(repaired.team[1]).toEqual("u1")
			expect(#repaired.pets).toEqual(size + 1)
			expect(#profile.team).toEqual(size + 2)
		end)

		it("does not repair what it cannot fix", function()
			local profile = withPets(1)
			profile.coins = -5
			local _, remaining = Profile.repair(profile)
			expect(kindsOf(remaining)).toEqual({ Profile.problems.negativeCoins })
		end)
	end)
end
