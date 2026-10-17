--!strict
local Runner = require(script.Parent.Parent.Parent.testing.Runner)
local Scenes = require(script.Parent.Parent.SceneLayout)
local Scenery = require(script.Parent.Parent.Scenery)
local Layout = require(script.Parent.Parent.Layout)
return function()
	Runner.describe("Raised scenic areas", function()
		Runner.it("uses continuous low-angle approaches and elevated destinations", function()
			for _, theme in { "green_meadow", "coral_coast", "ember_volcano" } do
				for _, s in Scenes.forTheme(theme) do
					local length = math.sqrt((s.endX - s.startX) ^ 2 + (s.endZ - s.startZ) ^ 2)
					Runner.expect(math.deg(math.atan(s.endY / length)) < 30).toBeTrue()
					Runner.expect(s.height > 0 and s.endY >= s.height).toBeTrue()
					Runner.expect(
						math.sqrt((s.endX - s.x) ^ 2 + (s.endZ - s.z) ^ 2) < s.radius - 1.5
					)
						.toBeTrue()
				end
			end
		end)
		Runner.it("reserves every constructed scene in the procedural planner", function()
			local plan = Layout.plan()
			for _, island in plan.islands do
				local scenery = Scenery.forIsland(plan, island)
				for _, s in Scenes.forTheme(scenery.theme) do
					local found = false
					for _, zone in scenery.clear do
						if
							zone.x == island.origin.x + s.x
							and zone.z == island.origin.z + s.z
							and zone.r == s.radius
						then
							found = true
						end
					end
					Runner.expect(found).toBeTrue()
				end
			end
		end)
	end)
end
