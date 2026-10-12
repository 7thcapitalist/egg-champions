--!strict
local Runner = require(script.Parent.Parent.Parent.testing.Runner)
local Config = require(script.Parent.Parent.Parent.Config)
local Progression = require(script.Parent.Parent.Progression)
local Rebirth = require(script.Parent.Parent.Rebirth)

local describe = Runner.describe
local it = Runner.it
local expect = Runner.expect

-- A state deep into a run: coins, pets, an index, a team, every gym beaten and
-- every fee paid.
local function fullState(): Progression.State
	local state = Progression.newState()
	state.coins = Rebirth.cost(0) * 3
	state.rebirths = 0
	local pet = Config.pets[1]
	state.pets = {
		{ uid = "pet1", petId = pet.id, variant = nil },
		{ uid = "pet2", petId = pet.id, variant = Config.variants[1].id },
	}
	state.team = { "pet1", "pet2" }
	state.index = { [pet.id] = { normal = true, shiny = true } }
	for _, world in Config.worlds do
		state.feesPaid[world.id] = true
		Progression.beatGym(state, world.index)
	end
	return state
end

local function sortedKeys(t: { [string]: any }): { string }
	local keys = {}
	for key in t do
		table.insert(keys, key)
	end
	table.sort(keys)
	return keys
end

return function()
	describe("Rebirth", function()
		it("costs rebirth_first_cost x rebirth_cost_growth ^ n for rebirths 0 to 5", function()
			local first = Config.constants.rebirth_first_cost
			local growth = Config.constants.rebirth_cost_growth
			-- Hand-computed by repeated multiplication, not by the module's power.
			local expected = first
			for rebirths = 0, 5 do
				expect(Rebirth.cost(rebirths)).toEqual(expected)
				expected *= growth
			end
			expect(Rebirth.cost(0)).toEqual(first)
			expect(Rebirth.cost(1)).toEqual(first * growth)
			expect(Rebirth.cost(5)).toEqual(first * growth * growth * growth * growth * growth)
		end)

		it("allows a rebirth only when coins reach the cost", function()
			local state = Progression.newState()
			state.coins = Rebirth.cost(0) - 1
			expect(Rebirth.canRebirth(state)).toBeFalse()
			state.coins = Rebirth.cost(0)
			expect(Rebirth.canRebirth(state)).toBeTrue()
			state.rebirths = 2
			expect(Rebirth.canRebirth(state)).toBeFalse()
			state.coins = Rebirth.cost(2)
			expect(Rebirth.canRebirth(state)).toBeTrue()
		end)

		it("clears exactly coins, gym wins and fees, and keeps every other field", function()
			-- The exact split. A new state field must be added to one list or the
			-- other here, so a change to the state shape cannot silently wipe pets.
			expect(Rebirth.CLEARED).toEqual({ "coins", "feesPaid", "gymsBeaten" })
			local kept = { "badges", "index", "pets", "team" }

			local before = fullState()
			local after = Rebirth.apply(before)
			local afterAny: any = after
			local beforeAny: any = before

			local allFields =
				{ "badges", "coins", "feesPaid", "gymsBeaten", "index", "pets", "rebirths", "team" }
			expect(sortedKeys(beforeAny)).toEqual(allFields)
			expect(sortedKeys(afterAny)).toEqual(allFields)

			-- Cleared.
			expect(after.coins).toEqual(0)
			expect(after.gymsBeaten).toEqual({})
			expect(after.feesPaid).toEqual({})
			-- Counted up.
			expect(after.rebirths).toEqual(before.rebirths + 1)
			-- Kept, field by field.
			for _, field in kept do
				expect(afterAny[field]).toEqual(beforeAny[field])
			end
			expect(#after.pets).toEqual(2)
			expect(next(after.index) ~= nil).toBeTrue()
			for _, world in Config.worlds do
				expect(after.badges[world.id]).toEqual(true)
			end
		end)

		it("keeps a field it does not know about", function()
			local before: any = fullState()
			before.futureField = { kept = true }
			local after: any = Rebirth.apply(before)
			expect(after.futureField).toEqual({ kept = true })
		end)

		it("leaves the input state untouched", function()
			local before = fullState()
			local snapshot = Rebirth.apply(Rebirth.apply(before))
			local _ = snapshot
			expect(before.coins).toEqual(Rebirth.cost(0) * 3)
			expect(before.rebirths).toEqual(0)
			for _, world in Config.worlds do
				expect(before.gymsBeaten[world.id]).toEqual(true)
				expect(before.feesPaid[world.id]).toEqual(true)
			end
			local after = Rebirth.apply(before)
			table.insert(after.pets, { uid = "pet3", petId = Config.pets[1].id })
			expect(#before.pets).toEqual(2)
		end)

		it("rejects a negative rebirth count", function()
			expect(function()
				Rebirth.cost(-1)
			end).toThrow("negative")
		end)
	end)
end
