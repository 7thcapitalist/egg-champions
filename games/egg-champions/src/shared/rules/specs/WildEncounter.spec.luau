--!strict
local Runner = require(script.Parent.Parent.Parent.testing.Runner)
local Wild = require(script.Parent.Parent.WildEncounter)
local Config = require(script.Parent.Parent.Parent.Config)
local expect = Runner.expect
return function()
	Runner.describe("server timed wild encounters", function()
		Runner.it("requires good timing, rejects repeats and resolves victory once", function()
			local e = Wild.new("one", "green_meadow", "leafpup", 0)
			local ok, result = Wild.strike(e, 0.8)
			expect(ok).toBeTrue()
			expect(result).toEqual("perfect")
			expect(e.hp).toEqual(75)
			expect(Wild.strike(e, 0.8)).toBeFalse()
			for _, t in { 2.4, 4, 5.6 } do
				expect(Wild.strike(e, t)).toBeTrue()
			end
			expect(e.phase).toEqual("defeated")
			expect(Wild.strike(e, 7.2)).toBeFalse()
		end)
		Runner.it("expires and loses after three bad strikes", function()
			local e = Wild.new("one", "green_meadow", "leafpup", 0)
			for _, t in { 0, 1.6, 3.2 } do
				Wild.strike(e, t)
			end
			expect(e.phase).toEqual("escaped")
			expect(Wild.capture(e, 4, 0)).toBeFalse()
			local expired = Wild.new("two", "green_meadow", "leafpup", 0)
			expect(Wild.strike(expired, Config.constants.wild_encounter_seconds)).toBeFalse()
		end)
		Runner.it("allows only one capture after victory, success or failure", function()
			for _, roll in { 0, 1 } do
				local e = Wild.new("one", "green_meadow", "leafpup", 0)
				expect(Wild.capture(e, 0, roll)).toBeFalse()
				e.phase = "defeated"
				expect(Wild.capture(e, 1, roll, 0.75)).toBeTrue()
				expect(e.phase).toEqual(if roll == 0 then "captured" else "escaped")
				expect(Wild.capture(e, 2, 0)).toBeFalse()
			end
		end)
		Runner.it("scales health and coin reward by strength and actual income", function()
			local common = Wild.new("a", "green_meadow", "leafpup", 0)
			local rare = Wild.new("b", "green_meadow", "emberkit", 0)
			expect(rare.maxHp).toEqual(common.maxHp * 3)
			expect(Wild.reward(100, rare.strength)).toEqual(1500)
			expect(Wild.reward(100, common.strength)).toEqual(500)
		end)
		Runner.it("pools contain all ten species from each world", function()
			for _, world in Config.worlds do
				local pool = Wild.pool(world.id)
				expect(#pool).toEqual(10)
				for _, id in pool do
					expect(Config.petById[id].world).toEqual(world.id)
				end
			end
		end)
	end)
end
