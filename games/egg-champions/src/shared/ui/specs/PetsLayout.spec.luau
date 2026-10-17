--!strict
local Runner = require(script.Parent.Parent.Parent.testing.Runner)
local PetsLayout = require(script.Parent.Parent.PetsLayout)
local HudLayout = require(script.Parent.Parent.HudLayout)
local PetsView = require(script.Parent.Parent.PetsView)
local Config = require(script.Parent.Parent.Parent.Config)

local describe = Runner.describe
local it = Runner.it
local expect = Runner.expect

-- The playtest phone, the design size and the playtest laptop, with the Roblox top bar insets the
-- engine uses (none, the old bar and the current one).
local SCREENS = {
	{ width = 808, height = 432 },
	{ width = 1280, height = 720 },
	{ width = 1348, height = 672 },
}
local INSETS = { 0, 36, 58 }

-- Where the screen starts: below the Roblox top bar and the HUD top bar, the
-- same sum the client uses.
local function topOf(width: number, height: number, inset: number): number
	return inset + HudLayout.compute(width, height - inset, 0).topBar.h
end

-- The HUD's left menu, the same rect the client passes in.
local function menuOf(width: number, height: number, inset: number): PetsLayout.Rect
	local insets: HudLayout.Insets = { top = inset, left = 0, right = 0 }
	local menu = HudLayout.compute(width, height, 0, insets).menu
	return { name = "menu", x = menu.x, y = menu.y, w = menu.w, h = menu.h }
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
					guide,
					true,
					{ menu = menuOf(screen.width, screen.height, inset) }
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
	describe("Inventory action toolbar", function()
		it("keeps team actions, search, equip and a usable grid on phone and desktop", function()
			for _, screen in { { 808, 432 }, { 844, 390 }, { 1280, 720 }, { 1920, 1080 } } do
				for _, filters in { false, true } do
					local width, height = screen[1], screen[2]
					local l = PetsLayout.compute(
						width,
						height,
						58,
						height >= 560,
						filters,
						{ tools = true }
					)
					local actions, search = l.actions, l.search
					expect(actions ~= nil and search ~= nil).toBeTrue()
					if actions ~= nil and search ~= nil then
						expectInside("toolbar", actions, l.panel)
						expectInside("search", search, l.content)
						expectApart("toolbar", actions, l.content)
						expectApart("search", search, l.grid)
						expect(actions.h >= 44).toBeTrue()
					end
					expect(
						string.format(
							"%dx%d filters=%s grid=%d",
							width,
							height,
							tostring(filters),
							l.grid.h
						)
							.. " "
							.. tostring(l.grid.h >= 70)
					).toEqual(
						string.format(
							"%dx%d filters=%s grid=%d",
							width,
							height,
							tostring(filters),
							l.grid.h
						) .. " true"
					)
					expect(l.sizes.tileBlock >= (if height < 420 then 64 else 72)).toBeTrue()
					expect(l.tileWidth >= l.sizes.tileBlock + 2 * l.sizes.tilePad).toBeTrue()
					expectInside("detail", l.equip, l.detail)
					expect(l.detailScroll.h > 0).toBeTrue()
				end
			end
		end)
		it("shows a complete pet card inside the phone safe area", function()
			local l = PetsLayout.compute(706, 281, 0, false, false, { tools = true })
			expect(l.tileHeight + 2 * l.sizes.gridPad <= l.grid.h).toBeTrue()
			expect(l.tileWidth >= l.sizes.tileBlock + 100).toBeTrue()
			expectInside("phone equip", l.equip, l.detail)
		end)
	end)
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
	describe("PetsLayout with few pets", function()
		it("drops the filter row and starts the grid under the hint", function()
			for _, screen in SCREENS do
				local top = topOf(screen.width, screen.height, 58)
				local full = PetsLayout.compute(screen.width, screen.height, top, false)
				local simple = PetsLayout.compute(screen.width, screen.height, top, false, false)
				expect(#full.controls).toEqual(#PetsLayout.CONTROLS)
				expect(#simple.controls).toEqual(0)
				expect(simple.controlRows).toEqual(0)
				expect(simple.grid.y < full.grid.y).toBeTrue()
				expect(simple.grid.y >= simple.hint.y + simple.hint.h).toBeTrue()
				expect(simple.grid.y + simple.grid.h).toEqual(full.grid.y + full.grid.h)
			end
		end)
	end)

	describe("PetsLayout EQUIP button", function()
		it("sits inside its slot with room for its outline on every side", function()
			each(function(layout)
				local slot = layout.equip
				local b = layout.equipButton
				local inset = PetsLayout.EQUIP_INSET
				expect(inset >= 2).toBeTrue()
				expect(b.x - slot.x >= inset).toBeTrue()
				expect(b.y - slot.y >= inset).toBeTrue()
				expect(slot.x + slot.w - (b.x + b.w) >= inset).toBeTrue()
				expect(slot.y + slot.h - (b.y + b.h) >= inset).toBeTrue()
				expect(b.w > 0 and b.h > 0).toBeTrue()
				-- Clear of the pet picture above, outline included.
				local top = layout.detailTop
				expect(b.y - inset >= top.y + top.h).toBeTrue()
			end)
		end)
	end)
	describe("PetsLayout and the menu", function()
		it("keeps the panel's left edge right of the menu, with any number of pets", function()
			for _, screen in SCREENS do
				for _, inset in INSETS do
					for _, few in { false, true } do
						local menu = menuOf(screen.width, screen.height, inset)
						local layout = PetsLayout.compute(
							screen.width,
							screen.height,
							topOf(screen.width, screen.height, inset),
							false,
							not few,
							{ few = few, menu = menu }
						)
						local where = string.format(
							"%dx%d inset %d few %s",
							screen.width,
							screen.height,
							inset,
							tostring(few)
						)
						expectApart(where, layout.panel, menu)
						local clear = layout.panel.x >= menu.x + menu.w
						expect(where .. " " .. tostring(clear)).toEqual(where .. " true")
						local screenRect: PetsLayout.Rect =
							{ name = "screen", x = 0, y = 0, w = screen.width, h = screen.height }
						expectInside(where, layout.panel, screenRect)
					end
				end
			end
		end)

		it("checks the playtest sizes 1280 x 720 and 1348 x 672", function()
			for _, size in { { 1280, 720 }, { 1348, 672 } } do
				local menu = menuOf(size[1], size[2], 58)
				local layout = PetsLayout.compute(
					size[1],
					size[2],
					topOf(size[1], size[2], 58),
					true,
					true,
					{ menu = menu }
				)
				expect(layout.panel.x >= menu.x + menu.w + layout.sizes.margin).toBeTrue()
				expect(layout.panel.x + layout.panel.w <= size[1] - layout.sizes.margin).toBeTrue()
			end
		end)
	end)

	describe("PetsLayout with fewer than 4 pets", function()
		it("uses bigger tiles with a pet view of at least 100 px that fit the grid", function()
			for _, screen in SCREENS do
				for _, inset in INSETS do
					local layout = PetsLayout.compute(
						screen.width,
						screen.height,
						topOf(screen.width, screen.height, inset),
						true,
						false,
						{ few = true, menu = menuOf(screen.width, screen.height, inset) }
					)
					local s = layout.sizes
					local where =
						string.format("%dx%d inset %d", screen.width, screen.height, inset)
					expect(layout.few).toBeTrue()
					expect(where .. " " .. tostring(s.tileBlock >= 100)).toEqual(where .. " true")
					local roomy = layout.tileWidth - 2 * s.tilePad >= s.tileBlock
					expect(where .. " " .. tostring(roomy)).toEqual(where .. " true")
					local used = layout.columns * layout.tileWidth
						+ (layout.columns - 1) * s.tileGap
					expect(used <= layout.grid.w - s.scrollBar - 2 * s.gridPad).toBeTrue()
					expect(layout.columns >= 1 and layout.columns <= PetsLayout.FEW.maxColumns).toBeTrue()
					expect(layout.tileHeight).toEqual(PetsLayout.tileHeight(s))
					expect(layout.grid.h > 0).toBeTrue()
					expectInside(where, layout.equip, layout.detail)
				end
			end
		end)

		it("narrows the panel and centers it on the playtest sizes", function()
			for _, size in { { 1280, 720 }, { 1348, 672 } } do
				local top = topOf(size[1], size[2], 58)
				local menu = menuOf(size[1], size[2], 58)
				local full = PetsLayout.compute(size[1], size[2], top, false, true, { menu = menu })
				local few = PetsLayout.compute(
					size[1],
					size[2],
					top,
					false,
					false,
					{ few = true, menu = menu }
				)
				expect(few.panel.w < full.panel.w).toBeTrue()
				local left = few.panel.x
				local right = size[1] - (few.panel.x + few.panel.w)
				expect(math.abs(left - right) <= 1).toBeTrue()
				expect(few.tileWidth > full.tileWidth).toBeTrue()
			end
		end)
	end)

	describe("PetsLayout stat rows", function()
		it("sizes a row from its text size plus padding", function()
			for _, s in { PetsLayout.SIZES.normal, PetsLayout.SIZES.compact } do
				expect(PetsLayout.statRow(s)).toEqual(s.text + 2 * s.statPad)
				expect(s.statPad >= 4).toBeTrue()
			end
		end)

		it("fits every stat label and value on its row", function()
			local widest = 0
			for _, pet in Config.pets do
				for _, stat in PetsView.detail(pet.id, nil).stats do
					widest = math.max(widest, #stat.label + #stat.value)
				end
				for _, variant in Config.variants do
					for _, stat in PetsView.detail(pet.id, variant.id).stats do
						widest = math.max(widest, #stat.label + #stat.value)
					end
				end
			end
			for _, screen in SCREENS do
				local layout = PetsLayout.compute(
					screen.width,
					screen.height,
					topOf(screen.width, screen.height, 58),
					false,
					true,
					{ menu = menuOf(screen.width, screen.height, 58) }
				)
				local s = layout.sizes
				for _, pet in Config.pets do
					for _, stat in PetsView.detail(pet.id, nil).stats do
						local need = HudLayout.textWidth(stat.label, s.text)
							+ HudLayout.textWidth(stat.value, s.text)
							+ 2 * s.statPad
						expect(need <= layout.detailScroll.w - 8).toBeTrue()
					end
				end
				-- Room for the longest label and value pair at upper case width.
				local worst = widest * HudLayout.GLYPH.upper * s.text + 2 * s.statPad
				expect(worst <= layout.detailScroll.w - 8).toBeTrue()
			end
		end)
	end)
end
