--!strict
--[[
	EggShopLayout: where every part of the egg shop sits, as plain rectangles
	in screen pixels, for a given screen size.

	The egg shop (client/UI/EggShop) places its panel, list and card parts
	from compute(), and the specs check the same rectangles at a 808 x 432
	phone and at 1280 x 720, so a shop whose HATCH button sits below the
	visible list is caught before a playtest.

	- The panel starts below `top`: the Roblox top bar (GuiService inset)
	  plus the HUD top bar, so the shop never hides either.
	- Each card has a fixed height. Its top part holds the egg view, the name
	  and price, then HATCH and HATCH X3, then the "Show odds" toggle. The
	  odds open as an overlay over the card above the toggle.
	- The hatch result overlays the card's egg and name area only, never the
	  buttons, and never changes the list area, so the scroll position and
	  the HATCH rectangle stay where they were.

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
	gap: number,
	footer: number,
	cardPadding: number,
	egg: number,
	button: number,
	tripleWidth: number,
	toggle: number,
	innerGap: number,
	title: number,
	cardTitle: number,
	price: number,
	odds: number,
	resultBlock: number,
	-- Room kept for the list's scroll bar at its right edge.
	scrollBar: number,
	-- Empty space under the last card, so it is never cut off.
	listBottom: number,
	-- Below this list width the cards go one per row.
	twoColumnsFrom: number,
}

-- Rectangles inside one card, relative to the card's top left corner.
export type CardParts = {
	egg: Rect,
	words: Rect,
	hatch: Rect,
	-- HATCH across the whole row, for a card that does not show HATCH X3.
	hatchWide: Rect,
	triple: Rect,
	toggle: Rect,
	odds: Rect,
	result: Rect,
}

export type Layout = {
	compact: boolean,
	sizes: Sizes,
	panel: Rect,
	header: Rect,
	list: Rect,
	footer: Rect,
	columns: number,
	cardWidth: number,
	cardHeight: number,
	parts: CardParts,
}

local EggShopLayout = {}

-- Below either of these the shop uses its compact sizes (phones).
EggShopLayout.COMPACT_BELOW = table.freeze({ width = 1000, height = 600 })

EggShopLayout.SIZES = table.freeze({
	normal = table.freeze({
		margin = 16,
		maxWidth = 1080,
		padding = 20,
		header = 52,
		gap = 14,
		footer = 22,
		cardPadding = 14,
		egg = 84,
		button = 52,
		tripleWidth = 150,
		toggle = 30,
		innerGap = 10,
		title = 32,
		cardTitle = 26,
		price = 18,
		odds = 15,
		resultBlock = 44,
		scrollBar = 8,
		listBottom = 14,
		twoColumnsFrom = 560,
	} :: Sizes),
	compact = table.freeze({
		margin = 8,
		maxWidth = 1080,
		padding = 10,
		header = 40,
		gap = 8,
		footer = 18,
		cardPadding = 10,
		egg = 56,
		button = 44,
		tripleWidth = 110,
		toggle = 26,
		innerGap = 6,
		title = 24,
		cardTitle = 20,
		price = 15,
		odds = 12,
		resultBlock = 36,
		scrollBar = 8,
		listBottom = 10,
		twoColumnsFrom = 560,
	} :: Sizes),
})

local function rect(name: string, x: number, y: number, w: number, h: number): Rect
	return { name = name, x = x, y = y, w = w, h = h }
end

function EggShopLayout.isCompact(width: number, height: number): boolean
	return width < EggShopLayout.COMPACT_BELOW.width or height < EggShopLayout.COMPACT_BELOW.height
end

-- The parts of a card of the given width.
function EggShopLayout.cardParts(s: Sizes, cardWidth: number): CardParts
	local inner = cardWidth - 2 * s.cardPadding
	local buttonsY = s.cardPadding + s.egg + s.innerGap
	local toggleY = buttonsY + s.button + s.innerGap
	local hatchWidth = inner - s.tripleWidth - s.innerGap
	local wordsX = s.cardPadding + s.egg + s.innerGap
	return {
		egg = rect("egg", s.cardPadding, s.cardPadding, s.egg, s.egg),
		words = rect("words", wordsX, s.cardPadding, cardWidth - s.cardPadding - wordsX, s.egg),
		hatch = rect("hatch", s.cardPadding, buttonsY, hatchWidth, s.button),
		hatchWide = rect("hatchWide", s.cardPadding, buttonsY, inner, s.button),
		triple = rect(
			"triple",
			s.cardPadding + hatchWidth + s.innerGap,
			buttonsY,
			s.tripleWidth,
			s.button
		),
		toggle = rect("toggle", s.cardPadding, toggleY, inner, s.toggle),
		odds = rect("odds", 0, 0, cardWidth, toggleY - math.floor(s.innerGap / 2)),
		result = rect("result", 0, 0, cardWidth, buttonsY - math.floor(s.innerGap / 2)),
	}
end

-- The card height of a size set: padding, egg row, buttons, toggle.
function EggShopLayout.cardHeight(s: Sizes): number
	return 2 * s.cardPadding + s.egg + s.innerGap + s.button + s.innerGap + s.toggle
end

-- The shop for a screen of width x height pixels (the whole screen, inset
-- included), starting below `top` pixels.
function EggShopLayout.compute(width: number, height: number, top: number): Layout
	local compact = EggShopLayout.isCompact(width, height)
	local s: Sizes = if compact then EggShopLayout.SIZES.compact else EggShopLayout.SIZES.normal

	local panelWidth = math.min(s.maxWidth, width - 2 * s.margin)
	local panelX = math.floor((width - panelWidth) / 2)
	local panelY = top + s.margin
	local panel = rect("panel", panelX, panelY, panelWidth, math.max(0, height - panelY - s.margin))

	local innerX = panel.x + s.padding
	local innerW = panel.w - 2 * s.padding
	local header = rect("header", innerX, panel.y + s.padding, innerW, s.header)
	local footer =
		rect("footer", innerX, panel.y + panel.h - s.padding - s.footer, innerW, s.footer)
	local listY = header.y + header.h + s.gap
	local list = rect("list", innerX, listY, innerW, math.max(0, footer.y - s.gap - listY))

	local columns = if list.w >= s.twoColumnsFrom then 2 else 1
	local cardWidth = math.floor((list.w - s.scrollBar - s.gap * (columns - 1)) / columns)
	return {
		compact = compact,
		sizes = s,
		panel = panel,
		header = header,
		list = list,
		footer = footer,
		columns = columns,
		cardWidth = cardWidth,
		cardHeight = EggShopLayout.cardHeight(s),
		parts = EggShopLayout.cardParts(s, cardWidth),
	}
end

-- How a heading line is measured: its height is the text size times this.
EggShopLayout.LINE_HEIGHT = 1.25

-- The title's text size: the size set's title, made smaller when the line
-- above it (the world name, at smallSize) and the title would not both fit
-- in the header's height.
function EggShopLayout.titleSize(s: Sizes, smallSize: number): number
	local room = s.header - smallSize * EggShopLayout.LINE_HEIGHT
	local fits = math.floor(room / EggShopLayout.LINE_HEIGHT)
	return math.max(1, math.min(s.title, fits))
end

-- The height of the list's scrolling content holding `count` cards: every
-- row, the gaps between them, and the empty space under the last card.
function EggShopLayout.canvasHeight(layout: Layout, count: number): number
	if count <= 0 then
		return 0
	end
	local rows = math.ceil(count / layout.columns)
	return rows * layout.cardHeight + (rows - 1) * layout.sizes.gap + layout.sizes.listBottom
end

-- The screen rectangle of the card at `position` (1 based) with the list
-- scrolled down by `scroll` pixels.
function EggShopLayout.cardRect(layout: Layout, position: number, scroll: number): Rect
	local index = position - 1
	local column = index % layout.columns
	local row = index // layout.columns
	return rect(
		"card" .. position,
		layout.list.x + column * (layout.cardWidth + layout.sizes.gap),
		layout.list.y + row * (layout.cardHeight + layout.sizes.gap) - scroll,
		layout.cardWidth,
		layout.cardHeight
	)
end

-- A card part moved onto the screen, given its card's screen rectangle.
function EggShopLayout.onScreen(card: Rect, part: Rect): Rect
	return rect(part.name, card.x + part.x, card.y + part.y, part.w, part.h)
end

-- True when inner lies wholly inside outer.
function EggShopLayout.inside(inner: Rect, outer: Rect): boolean
	return inner.x >= outer.x
		and inner.y >= outer.y
		and inner.x + inner.w <= outer.x + outer.w
		and inner.y + inner.h <= outer.y + outer.h
end

-- True when a and b share area (touching edges do not count).
function EggShopLayout.overlap(a: Rect, b: Rect): boolean
	return a.x < b.x + b.w and b.x < a.x + a.w and a.y < b.y + b.h and b.y < a.y + a.h
end

return EggShopLayout
