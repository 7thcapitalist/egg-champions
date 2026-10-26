--!strict
local Runner = require(script.Parent.Parent.Parent.testing.Runner)
local Config = require(script.Parent.Parent.Parent.Config)
local Goals = require(script.Parent.Parent.CollectionGoals)
local Progression = require(script.Parent.Parent.Parent.rules.Progression)

return function()
	Runner.describe("Collection trail", function()
		Runner.it("starts with an unlocked set and uses the existing configured bonus", function()
			local rows, target = Goals.build(Progression.newState())
			Runner.expect(#rows).toEqual(#Config.eggs)
			assert(target ~= nil, "fresh profile needs an unlocked collection target")
			Runner.expect(target.unlocked).toBeTrue()
			Runner.expect(target.have).toEqual(0)
			Runner.expect(target.need).toEqual(Config.constants.pets_per_egg)
			Runner.expect(target.bonusPercent).toEqual(Config.constants.index_egg_bonus * 100)
		end)
		Runner.it(
			"does not mistake shiny/golden hatches or malformed entries for normal collection",
			function()
				local state = Progression.newState()
				state.index[Config.pets[1].id] = { shiny = true, golden = true }
				local rows = Goals.build(state)
				Runner.expect(rows[1].have).toEqual(0)
				local bad = { index = { [Config.pets[1].id] = true } }
				local repaired = Goals.build(bad)
				Runner.expect(repaired[1].have).toEqual(0)
			end
		)
		Runner.it(
			"prefers a partially collected unlocked set without changing the profile",
			function()
				local state = Progression.newState()
				local pet = Config.pets[1]
				-- Select from config instead of relying on a species id.
				for _, candidate in Config.pets do
					if candidate.egg == Config.eggs[2].id then
						pet = candidate
						break
					end
				end
				state.index[pet.id] = { normal = true }
				local _, target = Goals.build(state)
				assert(target ~= nil, "partial collection needs an available target")
				Runner.expect(target.eggId).toEqual(pet.egg)
				Runner.expect(target.have).toEqual(1)
				Runner.expect(state.coins).toEqual(0)
				Runner.expect(#state.pets).toEqual(0)
			end
		)
		Runner.it(
			"keeps completed sets through rebirth but excludes locked incomplete targets",
			function()
				local state = Progression.newState()
				for _, pet in Config.pets do
					state.index[pet.id] = { normal = true }
				end
				local rows, target = Goals.build(state)
				Runner.expect(target == nil).toBeTrue()
				for _, row in rows do
					Runner.expect(row.complete and #row.missing == 0).toBeTrue()
				end
				state.index[Config.pets[#Config.pets].id] = nil
				local _, lockedTarget = Goals.build(state)
				Runner.expect(lockedTarget == nil).toBeTrue()
			end
		)
	end)
end
