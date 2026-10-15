--!strict
local Runner = require(script.Parent.Parent.Parent.testing.Runner)
local PetsLayout = require(script.Parent.Parent.PetsLayout)
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

-- Where the screen starts: below the Roblox top bar and the HUD top bar, the
-- same sum the client uses.
local function topOf(width: number, height: number, inset: number): number
	return inset + HudLayout.compute(width, height - inset, 0).topBar.h
end

local function each(check: (
	layout: PetsLayout.Layout,
	where: string,
	width: number,
	height: number
) -> ())
	for _, screen in SCREENS do
		for _, inset in INSETS do
			for _, guide in { false, true } do
				local layout = PetsLayout.compute(
					screen.width,
					screen.height,
					topOf(screen.width, screen.height, inset),
					guide
				)
				local where = string.format(
					"%dx%d inset %d guide %s",
					screen.width,
					screen.height,
					inset,
					tostring(guide)
				)
				check(layout, where, screen.width, screen.height)
			end
		end
	end
end

local function describeRect(r: PetsLayout.Rect): string
	return string.format("%s(%d,%d %dx%d)", r.name, r.x, r.y, r.w, r.h)
end

-- Fails with the rectangles in the message, so a failure says where.
local function expectInside(where: string, inner: PetsLayout.Rect, outer: PetsLayout.Rect)
	local text = string.format("%s: %s in %s", where, describeRect(inner), describeRect(outer))
	expect(text .. " " .. tostring(PetsLayout.inside(inner, outer))).toEqual(text .. " true")
end

local function expectApart(where: string, a: PetsLayout.Rect, b: PetsLayout.Rect)
	local text = string.format("%s: %s and %s", where, describeRect(a), describeRect(b))
	expect(text .. " " .. tostring(PetsLayout.overlap(a, b))).toEqual(text .. " false")
end

return function()
	describe("PetsLayout", function()
		it("keeps EQUIP right under the pet name, inside the panel and on screen", function()
			each(function(layout, where, width, height)
				local screen: PetsLayout.Rect =
					{ name = "screen", x = 0, y = 0, w = width, h = height }
				local s = layout.sizes
				expectInside(where, layout.detailTop, layout.detail)
				expectInside(where, layout.equip, layout.detail)
				expectInside(where, layout.detail, layout.panel)
				expectInside(where, layout.equip, screen)
				expect(layout.equip.y).toEqual(
					layout.detailTop.y + layout.detailTop.h + s.detailGap
				)
				expect(layout.equip.w >= 44 and layout.equip.h >= 44).toBeTrue()
				expectApart(where, layout.equip, layout.detailTop)
			end)
		end)

		it("scrolls the rest of the detail panel below EQUIP", function()
			each(function(layout, where)
				expectInside(where, layout.detailScroll, layout.detail)
				expectApart(where, layout.detailScroll, layout.equip)
				expect(layout.detailScroll.y >= layout.equip.y + layout.equip.h).toBeTrue()
				expect(layout.detailScroll.h > 0).toBeTrue()
			end)
		end)

		it("keeps the filter row out from under the detail panel", function()
			each(function(layout, where)
				expect(#layout.controls).toEqual(#PetsLayout.CONTROLS)
				for position, control in layout.controls do
					expectInside(where, control, layout.content)
					expectApart(where, control, layout.detail)
					expectApart(where, control, layout.grid)
					expectApart(where, control, layout.hint)
					expect(control.w >= layout.sizes.controlMin).toBeTrue()
					expect(control.h >= 30).toBeTrue()
					for other = position + 1, #layout.controls do
						expectApart(where, control, layout.controls[other])
					end
				end
				expectApart(where, layout.content, layout.detail)
			end)
		end)

		it("wraps the filter row when four buttons do not fit", function()
			local s = PetsLayout.SIZES.compact
			local four = 4 * s.controlMin + 3 * s.controlGap
			expect(PetsLayout.controlsPerRow(s, four)).toEqual(4)
			expect(PetsLayout.controlsPerRow(s, four - 1)).toEqual(2)
			expect(PetsLayout.controlsPerRow(s, s.controlMin)).toEqual(1)
		end)

		it("uses 3 columns under 500 px of content and fits the tiles", function()
			expect(PetsLayout.columnsFor(499)).toEqual(3)
			expect(PetsLayout.columnsFor(500) > 3).toBeTrue()
			expect(PetsLayout.columnsFor(2000)).toEqual(PetsLayout.MAX_COLUMNS)
			each(function(layout, where)
				expect(layout.columns).toEqual(PetsLayout.columnsFor(layout.content.w))
				local used = layout.columns * layout.tileWidth
					+ (layout.columns - 1) * layout.sizes.tileGap
				local free = layout.grid.w - layout.sizes.scrollBar - 2 * layout.sizes.gridPad
				expect(used <= free).toBeTrue()
				-- Wide enough for a marker line such as "Click +12.5".
				expect(where .. " " .. tostring(layout.tileWidth >= 90)).toEqual(where .. " true")
				expectInside(where, layout.grid, layout.content)
				expect(layout.grid.h > 0).toBeTrue()
			end)
			local phone = PetsLayout.compute(808, 432, topOf(808, 432, 58), true)
			expect(phone.content.w < 500).toBeTrue()
			expect(phone.columns).toEqual(3)
		end)

		it("gives every tile marker its own line", function()
			for _, s in { PetsLayout.SIZES.normal, PetsLayout.SIZES.compact } do
				local lines = PetsLayout.MARKER_LINES
				local needed = 2 * s.tilePad
					+ s.tileBlock
					+ s.tileName
					+ lines * s.marker
					+ (lines + 1) * s.markerGap
				expect(PetsLayout.tileHeight(s) >= needed).toBeTrue()
			end
		end)

		it("puts the guide strip in the header, above the body", function()
			each(function(layout, where)
				local guide = layout.guide
				if guide == nil then
					expect(layout.content.y).toEqual(
						layout.header.y + layout.header.h + layout.sizes.gap
					)
					return
				end
				expectInside(where, guide, layout.panel)
				expectApart(where, guide, layout.header)
				expectApart(where, guide, layout.content)
				expectApart(where, guide, layout.detail)
				expect(guide.y >= layout.header.y + layout.header.h).toBeTrue()
				expect(guide.y + guide.h <= layout.content.y).toBeTrue()
			end)
		end)
	end)
end
