--!strict
local Runner = require(script.Parent.Parent.Parent.testing.Runner)
local Config = require(script.Parent.Parent.Parent.Config)
local Progression = require(script.Parent.Parent.Progression)
local Rebirth = require(script.Parent.Parent.Rebirth)

local describe = Runner.describe
local it = Runner.it
local expect = Runner.expect

-- World indexes in ascending order, read from config.
local function worldIndexes(): { number }
	local indexes = {}
	for _, world in Config.worlds do
		table.insert(indexes, world.index)
	end
	table.sort(indexes)
	return indexes
end

return function()
	describe("Progression", function()
		it("opens world 1 from the start and locks every later world", function()
			local state = Progression.newState()
			local indexes = worldIndexes()
			expect(indexes[1]).toEqual(1)
			expect(Progression.worldUnlocked(state, 1)).toBeTrue()
			for i = 2, #indexes do
				expect(Progression.worldUnlocked(state, indexes[i])).toBeFalse()
			end
		end)

		it("opens a world only once the previous gym is beaten", function()
			local state = Progression.newState()
			local indexes = worldIndexes()
			for i = 2, #indexes do
				expect(Progression.worldUnlocked(state, indexes[i])).toBeFalse()
				Progression.beatGym(state, indexes[i - 1])
				expect(Progression.worldUnlocked(state, indexes[i])).toBeTrue()
				if i < #indexes then
					expect(Progression.worldUnlocked(state, indexes[i + 1])).toBeFalse()
				end
			end
		end)

		it("relocks worlds after a rebirth", function()
			local state = Progression.newState()
			for _, index in worldIndexes() do
				Progression.beatGym(state, index)
			end
			local reborn = Rebirth.apply(state)
			local indexes = worldIndexes()
			expect(Progression.worldUnlocked(reborn, 1)).toBeTrue()
			for i = 2, #indexes do
				expect(Progression.worldUnlocked(reborn, indexes[i])).toBeFalse()
				expect(Progression.isGymBeaten(reborn, indexes[i - 1])).toBeFalse()
			end
		end)

		it("lets an egg be bought only when its world is open", function()
			local state = Progression.newState()
			for _, egg in Config.eggs do
				local world = Config.worldById[egg.world]
				expect(Progression.eggUnlocked(state, egg.id)).toEqual(world.index == 1)
			end
			for _, index in worldIndexes() do
				Progression.beatGym(state, index)
			end
			for _, egg in Config.eggs do
				expect(Progression.eggUnlocked(state, egg.id)).toBeTrue()
			end
			local reborn = Rebirth.apply(state)
			for _, egg in Config.eggs do
				local world = Config.worldById[egg.world]
				expect(Progression.eggUnlocked(reborn, egg.id)).toEqual(world.index == 1)
			end
		end)

		it("awards a badge on the first win and keeps it through rebirth", function()
			local state = Progression.newState()
			expect(Progression.hasBadge(state, 1)).toBeFalse()
			expect(Progression.beatGym(state, 1)).toBeTrue()
			expect(Progression.hasBadge(state, 1)).toBeTrue()

			local reborn = Rebirth.apply(state)
			expect(Progression.hasBadge(reborn, 1)).toBeTrue()
			expect(Progression.isGymBeaten(reborn, 1)).toBeFalse()

			-- Beating the gym again neither loses nor duplicates the badge.
			expect(Progression.beatGym(reborn, 1)).toBeFalse()
			expect(Progression.hasBadge(reborn, 1)).toBeTrue()
			expect(Progression.isGymBeaten(reborn, 1)).toBeTrue()
			local count = 0
			for _ in reborn.badges do
				count += 1
			end
			expect(count).toEqual(1)
			expect(reborn.badges).toEqual({ [Config.worldByIndex[1].id] = true })
		end)

		it("reports the final gym beaten only in the current run", function()
			local state = Progression.newState()
			local indexes = worldIndexes()
			for i = 1, #indexes - 1 do
				Progression.beatGym(state, indexes[i])
				expect(Progression.isFinalGymBeaten(state)).toBeFalse()
			end
			Progression.beatGym(state, indexes[#indexes])
			expect(Progression.isFinalGymBeaten(state)).toBeTrue()
			expect(Progression.isFinalGymBeaten(Rebirth.apply(state))).toBeFalse()
		end)

		it("rejects an unknown world or egg", function()
			local state = Progression.newState()
			expect(function()
				Progression.worldUnlocked(state, 99)
			end).toThrow("99")
			expect(function()
				Progression.beatGym(state, 99)
			end).toThrow("99")
			expect(function()
				Progression.eggUnlocked(state, "no_such_egg")
			end).toThrow("no_such_egg")
		end)
	end)
end
