--!strict
--[[
	PetsLayout: where every part of the pets screen sits, as plain rectangles
	in screen pixels, for a given screen size.

	The pets screen (client/UI/Pets) places its panel, filter row, grid and
	detail panel from compute(), and the specs check the same rectangles at a
	808 x 432 phone and at 1280 x 720.

	- The panel starts below `top`: the Roblox top bar plus the HUD top bar.
	- The header holds the tabs and Close. While the tutorial has a line for
	  this screen, a one-line guide strip sits right under it.
	- Detail panel: the pet view and name at the top, EQUIP right under them
	  at a fixed place, and the rest (stats, moves, messages) in a scrolling
	  area below EQUIP. So EQUIP is never pushed off the panel.
	- Filter row: the four sort and filter buttons share the content width.
	  When four do not fit at their minimum width they wrap to two rows of
	  two (or one per row), so they never run under the detail panel. With
	  few pets (PetsView.screenParts) there is no filter row and the grid
	  starts right under the hint.
	- EQUIP: the button (equipButton) sits EQUIP_INSET pixels inside its
	  slot, so its outline, drawn on its border, is never clipped and never
	  touches the pet picture above.
	- Grid: 3 columns when the content is under 500 px wide, 4 under 640,
	  else 5. A tile holds the pet view, the name and up to three marker
	  lines (Click Power, variant, Equipped), each on its own line. The grid
	  keeps gridPad free around the tiles so the tutorial outline around a
	  tile is not cut off.
	- Few pets (fewer than PetsView.FULL_SCREEN_PETS, options.few): a
	  narrower panel centered on the screen and bigger tiles, whose pet view
	  is FEW.tileBlock (at least 100 px). Columns are as many as fit that
	  view, up to FEW.maxColumns.
	- Menu: given the HUD's left menu rect (options.menu), the panel's left
	  edge stays right of it by the margin, so the EGGS and PETS buttons are
	  never covered.
	- Stat rows: a row is its text size plus statPad above and below
	  (statRow), so every label fits its row.

	These are pixel sizes of the interface, not game numbers. Nothing here
	touches the engine.
]]

export type Rect = {
	name: string,
	x: number,
	y: number,
	w: number,
	h: number,
}

export type Sizes = {
	margin: number,
	maxWidth: number,
	padding: number,
	header: number,
	guide: number,
	gap: number,
	detailWidth: number,
	detailPad: number,
	detailBlock: number,
	detailGap: number,
	statPad: number,
	equip: number,
	hint: number,
	control: number,
	controlGap: number,
	controlMin: number,
	scrollBar: number,
	gridPad: number,
	tileGap: number,
	tilePad: number,
	tileBlock: number,
	tileHorizontal: boolean?,
	tileName: number,
	marker: number,
	markerGap: number,
	title: number,
	text: number,
	small: number,
}

-- few: the player has few pets (bigger tiles, narrower panel). menu: the
-- HUD's left menu rect, which the panel keeps clear of.
export type Options = {
	few: boolean?,
	menu: Rect?,
	tools: boolean?,
	actions: boolean?,
}

export type Layout = {
	compact: boolean,
	bodyViewport: Rect?,
	bodyCanvasHeight: number,
	few: boolean,
	sizes: Sizes,
	panel: Rect,
	header: Rect,
	guide: Rect?,
	actions: Rect?,
	search: Rect?,
	content: Rect,
	detail: Rect,
	detailTop: Rect,
	equip: Rect,
	equipButton: Rect,
	detailScroll: Rect,
	hint: Rect,
	controls: { Rect },
	controlRows: number,
	grid: Rect,
	columns: number,
	tileWidth: number,
	tileHeight: number,
}

local PetsLayout = {}

-- Below either of these the screen uses its compact sizes (phones).
PetsLayout.COMPACT_BELOW = table.freeze({ width = 1000, height = 600 })

-- The sort and filter buttons, in order.
PetsLayout.CONTROLS = table.freeze({ "Sort", "Rarity", "Type", "Egg" })

-- Most marker lines a tile shows: Click Power, variant, Equipped.
PetsLayout.MARKER_LINES = 3

-- Grid columns by content width: under 500 px 3, under 640 px 4, else 5.
PetsLayout.COLUMNS = table.freeze({
	{ below = 500, columns = 3 },
	{ below = 640, columns = 4 },
})
PetsLayout.MAX_COLUMNS = 5

PetsLayout.SIZES = table.freeze({
	normal = table.freeze({
		margin = 16,
		maxWidth = 1140,
		padding = 20,
		header = 48,
		guide = 30,
		gap = 14,
		detailWidth = 340,
		detailPad = 16,
		detailBlock = 88,
		detailGap = 10,
		statPad = 8,
		equip = 48,
		hint = 20,
		control = 36,
		controlGap = 8,
		controlMin = 150,
		scrollBar = 8,
		gridPad = 10,
		tileGap = 10,
		tilePad = 8,
		tileBlock = 44,
		tileName = 18,
		marker = 14,
		markerGap = 2,
		title = 24,
		text = 15,
		small = 12,
	} :: Sizes),
	compact = table.freeze({
		margin = 8,
		maxWidth = 1140,
		padding = 10,
		header = 40,
		guide = 24,
		gap = 8,
		detailWidth = 280,
		detailPad = 10,
		detailBlock = 56,
		detailGap = 6,
		statPad = 6,
		equip = 44,
		hint = 16,
		control = 30,
		controlGap = 6,
		controlMin = 130,
		scrollBar = 6,
		gridPad = 10,
		tileGap = 8,
		tilePad = 6,
		tileBlock = 36,
		tileName = 14,
		marker = 12,
		markerGap = 2,
		title = 18,
		text = 13,
		small = 11,
	} :: Sizes),
})

-- With few pets: the panel's widest width and the tile pet view size, by
-- screen class, and the most grid columns.
PetsLayout.FEW = table.freeze({
	normal = table.freeze({ maxWidth = 860, tileBlock = 120 }),
	compact = table.freeze({ maxWidth = 760, tileBlock = 100 }),
	maxColumns = 3,
})

local function rect(name: string, x: number, y: number, w: number, h: number): Rect
	return { name = name, x = x, y = y, w = math.max(0, w), h = math.max(0, h) }
end

function PetsLayout.isCompact(width: number, height: number): boolean
	return width < PetsLayout.COMPACT_BELOW.width or height < PetsLayout.COMPACT_BELOW.height
end

-- Grid columns for a content width.
function PetsLayout.columnsFor(contentWidth: number): number
	for _, row in PetsLayout.COLUMNS do
		if contentWidth < row.below then
			return row.columns
		end
	end
	return PetsLayout.MAX_COLUMNS
end

-- Buttons per filter row: all four when they fit at their minimum width,
-- else two, else one.
function PetsLayout.controlsPerRow(s: Sizes, width: number): number
	local count = #PetsLayout.CONTROLS
	for _, perRow in { count, 2, 1 } do
		if perRow * s.controlMin + (perRow - 1) * s.controlGap <= width then
			return perRow
		end
	end
	return 1
end

-- A tile's height: padding, pet view, name and every marker line.
function PetsLayout.tileHeight(s: Sizes): number
	local lines = PetsLayout.MARKER_LINES
	if s.tileHorizontal then
		return 2 * s.tilePad + math.max(s.tileBlock, s.tileName + lines * (s.marker + s.markerGap))
	end
	return 2 * s.tilePad
		+ s.tileBlock
		+ s.markerGap
		+ s.tileName
		+ s.markerGap
		+ lines * s.marker
		+ (lines - 1) * s.markerGap
end

-- A stat row's height: its text size plus statPad above and below.
function PetsLayout.statRow(s: Sizes): number
	return s.text + 2 * s.statPad
end

-- How far the EQUIP button sits inside its slot on every side: room for
-- its outline plus padding.
PetsLayout.EQUIP_INSET = 4

-- The screen for a screen of width x height pixels (inset included),
-- starting below `top` pixels, with or without the tutorial guide strip.
-- filters false leaves out the sort and filter row (default true).
-- options: few pets and the HUD menu rect to keep clear of (Options).
function PetsLayout.compute(
	width: number,
	height: number,
	top: number,
	guide: boolean,
	filters: boolean?,
	options: Options?
): Layout
	local screenHeight = height
	local scrollBody = width >= 600 and height < 360
	if scrollBody then
		-- Keep readable controls and scroll the body under a fixed header.
		height = math.max(height, top + 420)
	end
	local withFilters = filters ~= false
	local few = options ~= nil and options.few == true
	local tools = options ~= nil and options.tools == true
	local menu = if options ~= nil then options.menu else nil
	local compact = PetsLayout.isCompact(width, height)
	local portrait = width < 500
	local s: Sizes = if compact then PetsLayout.SIZES.compact else PetsLayout.SIZES.normal
	if few then
		local fewSizes = if compact then PetsLayout.FEW.compact else PetsLayout.FEW.normal
		local copy = table.clone(s)
		copy.maxWidth = fewSizes.maxWidth
		copy.tileBlock = fewSizes.tileBlock
		s = copy
	end
	if tools then
		local copy = table.clone(s)
		copy.maxWidth = 1140
		copy.detailWidth = if compact then 230 else 300
		copy.tileBlock = if compact then 80 else 104
		copy.controlMin = if compact then 76 else 120
		if screenHeight < 420 then
			copy.tileHorizontal = true
			copy.tileBlock = 64
			copy.gridPad = 4
		end
		s = copy
	end
	if portrait then
		s = table.clone(s)
		s.header = 78
		s.detailBlock = 48
		menu = nil
	end

	local panelWidth = math.min(s.maxWidth, width - 2 * s.margin)
	local panelX = math.floor((width - panelWidth) / 2)
	if menu ~= nil then
		local leftLimit = math.max(s.margin, menu.x + menu.w + s.margin)
		if panelX < leftLimit then
			panelX = leftLimit
			panelWidth = math.min(panelWidth, width - s.margin - leftLimit)
		end
	end
	local panelY = top + s.margin
	local panel = rect("panel", panelX, panelY, panelWidth, height - panelY - s.margin)

	local innerX = panel.x + s.padding
	local innerW = panel.w - 2 * s.padding
	local header = rect("header", innerX, panel.y + s.padding, innerW, s.header)
	local below = header.y + header.h
	local guideRect: Rect? = nil
	if guide then
		guideRect = rect("guide", innerX, below + s.controlGap, innerW, s.guide)
		below = below + s.controlGap + s.guide
	end
	local actions: Rect? = nil
	if tools and (options == nil or options.actions ~= false) then
		actions = rect("actions", innerX, below + s.controlGap, innerW, 44)
		below = actions.y + actions.h
	end
	local bodyY = below + s.gap
	local bodyH = panel.y + panel.h - s.padding - bodyY

	local detail = rect("detail", innerX + innerW - s.detailWidth, bodyY, s.detailWidth, bodyH)
	if portrait then
		local detailHeight = math.min(190, bodyH * 0.45)
		detail = rect("detail", innerX, bodyY + bodyH - detailHeight, innerW, detailHeight)
	end
	local detailInnerX = detail.x + s.detailPad
	local detailInnerW = detail.w - 2 * s.detailPad
	local detailTop =
		rect("detailTop", detailInnerX, detail.y + s.detailPad, detailInnerW, s.detailBlock)
	local equip =
		rect("equip", detailInnerX, detailTop.y + detailTop.h + s.detailGap, detailInnerW, s.equip)
	local inset = PetsLayout.EQUIP_INSET
	local equipButton = rect(
		"equipButton",
		equip.x + inset,
		equip.y + inset,
		equip.w - 2 * inset,
		equip.h - 2 * inset
	)
	local scrollY = equip.y + equip.h + s.detailGap
	local detailScroll = rect(
		"detailScroll",
		detailInnerX,
		scrollY,
		detailInnerW,
		detail.y + detail.h - s.detailPad - scrollY
	)

	local content = rect("content", innerX, bodyY, innerW - s.detailWidth - s.gap, bodyH)
	if portrait then
		content = rect("content", innerX, bodyY, innerW, detail.y - bodyY - s.gap)
	end
	local hint = rect("hint", content.x, content.y, content.w, s.hint)
	local search: Rect? = nil
	if tools then
		search = rect("search", content.x, content.y + hint.h + s.controlGap, content.w, 32)
	end
	local perRow = PetsLayout.controlsPerRow(s, content.w)
	local controlW = math.floor((content.w - (perRow - 1) * s.controlGap) / perRow)
	local controlsY = if search ~= nil
		then search.y + search.h + s.controlGap
		else hint.y + hint.h + s.controlGap
	local controls: { Rect } = {}
	for position, name in if withFilters then PetsLayout.CONTROLS else {} do
		local index = position - 1
		local column = index % perRow
		local row = index // perRow
		table.insert(
			controls,
			rect(
				name,
				content.x + column * (controlW + s.controlGap),
				controlsY + row * (s.control + s.controlGap),
				controlW,
				s.control
			)
		)
	end
	local controlRows = if withFilters then math.ceil(#PetsLayout.CONTROLS / perRow) else 0
	local gridY = if withFilters
		then controlsY + controlRows * s.control + (controlRows - 1) * s.controlGap + s.gap
		else (if search ~= nil then search.y + search.h else hint.y + hint.h) + s.gap
	local grid = rect("grid", content.x, gridY, content.w, content.y + content.h - gridY)

	local free = grid.w - s.scrollBar - 2 * s.gridPad
	local function widthFor(count: number): number
		return math.floor((free - (count - 1) * s.tileGap) / count)
	end
	local columns = PetsLayout.columnsFor(content.w)
	if tools then
		local minTile = if s.tileHorizontal then 200 elseif compact then 104 else 128
		columns = math.clamp(
			math.floor((free + s.tileGap) / (minTile + s.tileGap)),
			1,
			PetsLayout.MAX_COLUMNS
		)
	elseif few then
		columns = 1
		for count = PetsLayout.FEW.maxColumns, 1, -1 do
			if widthFor(count) - 2 * s.tilePad >= s.tileBlock then
				columns = count
				break
			end
		end
	end
	local tileWidth = widthFor(columns)
	if tools then
		local copy = table.clone(s)
		copy.tileBlock = math.min(s.tileBlock, tileWidth - 2 * s.tilePad)
		s = copy
	end
	local bodyViewport: Rect? = nil
	local bodyCanvasHeight = 0
	if scrollBody then
		local bodyTop = header.y + header.h + s.controlGap
		bodyCanvasHeight = panel.y + panel.h - s.padding - bodyTop
		panel.h = math.max(0, screenHeight - panel.y - s.margin)
		bodyViewport =
			rect("bodyViewport", panel.x, bodyTop, panel.w, panel.y + panel.h - s.padding - bodyTop)
	end
	return {
		compact = compact,
		bodyViewport = bodyViewport,
		bodyCanvasHeight = bodyCanvasHeight,
		few = few,
		sizes = s,
		panel = panel,
		header = header,
		guide = guideRect,
		actions = actions,
		search = search,
		content = content,
		detail = detail,
		detailTop = detailTop,
		equip = equip,
		equipButton = equipButton,
		detailScroll = detailScroll,
		hint = hint,
		controls = controls,
		controlRows = controlRows,
		grid = grid,
		columns = columns,
		tileWidth = tileWidth,
		tileHeight = PetsLayout.tileHeight(s),
	}
end

-- Scroll just enough to center an action inside the short body viewport.
function PetsLayout.revealScroll(layout: Layout, target: Rect): number
	local viewport = layout.bodyViewport
	if viewport == nil then
		return 0
	end
	return math.clamp(
		target.y - viewport.y - (viewport.h - target.h) / 2,
		0,
		math.max(0, layout.bodyCanvasHeight - viewport.h)
	)
end

-- True when inner lies wholly inside outer.
function PetsLayout.inside(inner: Rect, outer: Rect): boolean
	return inner.x >= outer.x
		and inner.y >= outer.y
		and inner.x + inner.w <= outer.x + outer.w
		and inner.y + inner.h <= outer.y + outer.h
end

-- True when a and b share area (touching edges do not count).
function PetsLayout.overlap(a: Rect, b: Rect): boolean
	return a.x < b.x + b.w and b.x < a.x + a.w and a.y < b.y + b.h and b.y < a.y + a.h
end

return PetsLayout
