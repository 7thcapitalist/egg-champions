--!strict
local Runner = require(script.Parent.Parent.Parent.testing.Runner)
local Config = require(script.Parent.Parent.Parent.Config)
local Motion = require(script.Parent.Parent.BattleMotion)

return function()
	Runner.describe("Creature battle motion", function()
		Runner.it("assigns every configured species a motion family", function()
			for _, pet in Config.pets do
				Runner.expect(type(Motion.families[pet.id]) == "string").toBeTrue()
			end
		end)
		Runner.it(
			"restores the exact resting pose at both ends and outside the interval",
			function()
				for pet in Motion.families do
					for _, kind in { "attack", "hit" } do
						for _, t in { -1, 0, 1, 2 } do
							for _, value in Motion.sample(pet, kind, t) do
								Runner.expect(value).toEqual(0)
							end
						end
					end
				end
			end
		)
		Runner.it("keeps displacement and rotation within portrait-safe bounds", function()
			for pet in Motion.families do
				for _, kind in { "attack", "hit" } do
					for i = 0, 100 do
						local p = Motion.sample(pet, kind, i / 100)
						Runner.expect(math.abs(p.y) <= 0.17 and math.abs(p.z) <= 0.14).toBeTrue()
						Runner.expect(
							math.abs(p.pitch) <= 0.31
								and math.abs(p.yaw) <= 0.31
								and math.abs(p.roll) <= 0.19
						).toBeTrue()
					end
				end
			end
		end)
		Runner.it(
			"anticipates backward before the strike and gives heroes distinct poses",
			function()
				Runner.expect(Motion.sample("leafpup", "attack", 0.24).z > 0).toBeTrue()
				Runner.expect(Motion.sample("leafpup", "attack", 0.52).z < 0).toBeTrue()
				local whale = Motion.sample("tidewhale", "attack", 0.52)
				local dragon = Motion.sample("thundrake", "attack", 0.52)
				local bird = Motion.sample("magmaroc", "attack", 0.52)
				Runner.expect(whale.pitch < 0 and bird.pitch > 0 and dragon.yaw > 0).toBeTrue()
				Runner.expect(whale.y > dragon.y and dragon.y > bird.y).toBeTrue()
			end
		)
		Runner.it("does not animate an unknown event", function()
			for _, value in Motion.sample("leafpup", "unknown", 0.5) do
				Runner.expect(value).toEqual(0)
			end
		end)
	end)
end
