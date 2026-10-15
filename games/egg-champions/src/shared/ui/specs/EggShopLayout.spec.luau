--!strict
local Runner = require(script.Parent.Parent.Parent.testing.Runner)
local EggShopLayout = require(script.Parent.Parent.EggShopLayout)
local HudLayout = require(script.Parent.Parent.HudLayout)

local describe = Runner.describe
local it = Runner.it
local expect = Runner.expect

-- The playtest phone and the design size, with the Roblox top bar insets the
-- engine uses (none, the old bar and the current one).
local SCREENS = {
	{ width = 808, height = 432 },
	{ width = 1280, height = 720 },
}
local INSETS = { 0, 36, 58 }

-- Where the shop starts: below the Roblox top bar and the HUD top bar, the
-- same sum the client uses.
local function topOf(width: number, height: number, inset: number): number
	return inset + HudLayout.compute(width, height - inset, 0).topBar.h
end

local function each(check: (width: number, height: number, inset: number) -> ())
	for _, screen in SCREENS do
		for _, inset in INSETS do
			check(screen.width, screen.height, inset)
		end
	end
end

local function describeRect(r: EggShopLayout.Rect): string
	return string.format("%s(%d,%d %dx%d)", r.name, r.x, r.y, r.w, r.h)
end

return function()
	describe("EggShopLayout", function()
		it("puts the first card's HATCH inside the visible list at scroll 0", function()
			each(function(width, height, inset)
				local layout = EggShopLayout.compute(width, height, topOf(width, height, inset))
				local card = EggShopLayout.cardRect(layout, 1, 0)
				local hatch = EggShopLayout.onScreen(card, layout.parts.hatch)
				local triple = EggShopLayout.onScreen(card, layout.parts.triple)
				local where = string.format(
					"%dx%d inset %d: %s in %s",
					width,
					height,
					inset,
					describeRect(hatch),
					describeRect(layout.list)
				)
				expect(where .. " " .. tostring(EggShopLayout.inside(hatch, layout.list))).toEqual(
					where .. " true"
				)
				expect(EggShopLayout.inside(triple, layout.list)).toBeTrue()
				expect(hatch.w >= 44 and hatch.h >= 44).toBeTrue()
			end)
		end)

		it("keeps HATCH visible and uncovered after a hatch", function()
			each(function(width, height, inset)
				local top = topOf(width, height, inset)
				local before = EggShopLayout.compute(width, height, top)
				-- A hatch shows the result over the card; the layout, and so the
				-- list and scroll, do not change.
				local after = EggShopLayout.compute(width, height, top)
				expect(describeRect(after.list)).toEqual(describeRect(before.list))
				local card = EggShopLayout.cardRect(after, 1, 0)
				local hatch = EggShopLayout.onScreen(card, after.parts.hatch)
				local result = EggShopLayout.onScreen(card, after.parts.result)
				expect(EggShopLayout.inside(hatch, after.list)).toBeTrue()
				expect(EggShopLayout.overlap(result, hatch)).toBeFalse()
				expect(EggShopLayout.inside(result, card)).toBeTrue()
			end)
		end)

		it("starts below the Roblox and HUD top bars and stays on screen", function()
			each(function(width, height, inset)
				local top = topOf(width, height, inset)
				local layout = EggShopLayout.compute(width, height, top)
				expect(layout.panel.y >= top).toBeTrue()
				local screen = { name = "screen", x = 0, y = 0, w = width, h = height }
				expect(EggShopLayout.inside(layout.panel, screen)).toBeTrue()
				expect(EggShopLayout.inside(layout.header, layout.panel)).toBeTrue()
				expect(EggShopLayout.inside(layout.list, layout.panel)).toBeTrue()
				expect(EggShopLayout.inside(layout.footer, layout.panel)).toBeTrue()
				expect(EggShopLayout.overlap(layout.header, layout.list)).toBeFalse()
				expect(EggShopLayout.overlap(layout.footer, layout.list)).toBeFalse()
			end)
		end)

		it("keeps every card part inside its card without overlaps", function()
			each(function(width, height, inset)
				local layout = EggShopLayout.compute(width, height, topOf(width, height, inset))
				local card =
					{ name = "card", x = 0, y = 0, w = layout.cardWidth, h = layout.cardHeight }
				local p = layout.parts
				local solid = { p.egg, p.words, p.hatch, p.triple, p.toggle }
				for i, a in solid do
					expect(EggShopLayout.inside(a, card)).toBeTrue()
					for j = i + 1, #solid do
						expect(EggShopLayout.overlap(a, solid[j])).toBeFalse()
					end
				end
				-- The odds overlay leaves the toggle free, so it can be hidden again.
				expect(EggShopLayout.overlap(p.odds, p.toggle)).toBeFalse()
			end)
		end)

		it("uses two columns on both screens", function()
			each(function(width, height, inset)
				local layout = EggShopLayout.compute(width, height, topOf(width, height, inset))
				expect(layout.columns).toEqual(2)
				local second = EggShopLayout.cardRect(layout, 2, 0)
				expect(second.x + second.w <= layout.list.x + layout.list.w).toBeTrue()
			end)
		end)

		it("goes compact on the phone only", function()
			expect(EggShopLayout.compute(808, 432, 0).compact).toBeTrue()
			expect(EggShopLayout.compute(1280, 720, 0).compact).toBeFalse()
		end)
	end)
end
