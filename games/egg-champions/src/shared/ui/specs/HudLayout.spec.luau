--!strict
local Runner = require(script.Parent.Parent.Parent.testing.Runner)
local Config = require(script.Parent.Parent.Parent.Config)
local HudLayout = require(script.Parent.Parent.HudLayout)

local describe = Runner.describe
local it = Runner.it
local expect = Runner.expect

-- The three screens from the brief, and the heights left below the Roblox
-- top bar: none (inset ignored) and the tallest inset Roblox uses.
local SCREENS = {
	{ width = 1280, height = 720 },
	{ width = 1920, height = 1080 },
	{ width = 844, height = 390 },
	{ width = 808, height = 432 },
}
local INSETS = { 0, 36, 58 }

local function joined(list: { string }): string
	return table.concat(list, ", ")
end

return function()
	describe("HudLayout.overlaps", function()
		it("finds a pair that shares area", function()
			local a = { name = "a", x = 0, y = 0, w = 10, h = 10 }
			local b = { name = "b", x = 5, y = 5, w = 10, h = 10 }
			local c = { name = "c", x = 100, y = 100, w = 10, h = 10 }
			expect(joined(HudLayout.overlaps({ a, b, c }))).toEqual("a/b")
		end)

		it("does not count touching edges", function()
			local a = { name = "a", x = 0, y = 0, w = 10, h = 10 }
			local b = { name = "b", x = 10, y = 0, w = 10, h = 10 }
			expect(#HudLayout.overlaps({ a, b })).toEqual(0)
		end)

		it("names parts past the screen edge", function()
			local a = { name = "a", x = 90, y = 0, w = 20, h = 10 }
			expect(joined(HudLayout.outside({ a }, 100, 100))).toEqual("a")
		end)
	end)

	describe("HudLayout.compute", function()
		local teamSize = Config.constants.team_size
		for _, screen in SCREENS do
			for _, inset in INSETS do
				local width = screen.width
				local height = screen.height - inset
				local label = string.format("%d x %d, inset %d", screen.width, screen.height, inset)
				for slots = 0, teamSize do
					it(
						string.format("has no overlaps at %s with %d team slots", label, slots),
						function()
							local layout = HudLayout.compute(width, height, slots)
							expect(joined(HudLayout.overlaps(layout.parts))).toEqual("")
							expect(joined(HudLayout.outside(layout.parts, width, height))).toEqual(
								""
							)
						end
					)
				end
				it(
					string.format("keeps the goal card to a quarter of the screen at %s", label),
					function()
						local layout = HudLayout.compute(width, height, teamSize)
						expect(layout.goal.h <= screen.height / 4).toBeTrue()
					end
				)
				it(
					string.format("keeps the team bar low and off the character at %s", label),
					function()
						local layout = HudLayout.compute(width, height, teamSize)
						local team = layout.team :: HudLayout.Rect
						-- The bottom quarter of the screen.
						expect(team.y >= height * 0.75).toBeTrue()
						if layout.compact then
							-- Bottom left, ending before the middle of the screen.
							expect(team.x).toEqual(layout.sizes.gutter)
							expect(team.x + team.w <= width / 2).toBeTrue()
						else
							local centre = team.x + team.w / 2
							expect(math.abs(centre - width / 2) <= 1).toBeTrue()
						end
					end
				)
				it(string.format("centres the world name at %s", label), function()
					local layout = HudLayout.compute(width, height, teamSize)
					local centre = layout.world.x + layout.world.w / 2
					expect(math.abs(centre - width / 2) <= 1).toBeTrue()
				end)
			end
		end

		it("gives the goal line two lines of at least 18 px text", function()
			expect(HudLayout.GOAL_TEXT >= 18).toBeTrue()
			for _, kind in { "normal", "compact" } do
				local s = (HudLayout.SIZES :: any)[kind] :: HudLayout.Sizes
				expect(s.goalLines).toEqual(2)
				expect(s.goalLine >= HudLayout.GOAL_TEXT).toBeTrue()
			end
		end)

		it("uses compact sizes on the phone only", function()
			expect(HudLayout.compute(844, 390, 0).compact).toBeTrue()
			expect(HudLayout.compute(808, 432, 0).compact).toBeTrue()
			expect(HudLayout.compute(1280, 720, 0).compact).toBeFalse()
			expect(HudLayout.compute(1920, 1080, 0).compact).toBeFalse()
		end)

		it("leaves the team out when no slot shows", function()
			local layout = HudLayout.compute(1280, 720, 0)
			expect(layout.team == nil).toBeTrue()
			expect(#layout.parts).toEqual(5)
		end)

		it("has four menu entries and no Index", function()
			expect(joined(HudLayout.MENU)).toEqual("Eggs, Pets, Rebirth, Shop")
		end)
	end)

	describe("HudLayout.teamSlots", function()
		it("shows nothing before the first pet is equipped", function()
			expect(HudLayout.teamSlots(0, 3)).toEqual(0)
		end)

		it("shows one slot per equipped pet up to the team size", function()
			expect(HudLayout.teamSlots(1, 3)).toEqual(1)
			expect(HudLayout.teamSlots(2, 3)).toEqual(2)
			expect(HudLayout.teamSlots(3, 3)).toEqual(3)
			expect(HudLayout.teamSlots(40, 3)).toEqual(3)
		end)
	end)
end
