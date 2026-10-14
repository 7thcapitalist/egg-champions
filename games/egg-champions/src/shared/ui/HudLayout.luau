--!strict
--[[
	HudLayout: where every part of the main screen HUD sits, as plain
	rectangles, for a given screen size.

	The main screen (client/UI/Main) places its panels from compute(), and the
	specs run overlaps() on the same rectangles at 1280 x 720, 1920 x 1080 and
	a 844 x 390 phone, so a layout that collides is caught before a playtest.

	The parts:
	- coins: coins and coins per click, top left;
	- world: the world name, centred in the top bar on its own;
	- rebirths: the rebirth count, small, top right;
	- menu: the four menu buttons on the left;
	- goal: the next-goal card on the right, at most a quarter of the screen
	  height;
	- team: the team bar at the bottom, only when it shows at least one slot.

	The top bar itself spans the screen and holds coins, world and rebirths,
	so it is returned apart (topBar) and not counted as an overlap.

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
	topBar: number,
	gutter: number,
	coinsWidth: number,
	worldWidth: number,
	rebirthsWidth: number,
	menuWidth: number,
	menuButton: number,
	menuGap: number,
	menuTop: number,
	goalWidth: number,
	goalPad: number,
	goalLine: number,
	goalGap: number,
	goalButton: number,
	slotWidth: number,
	slotHeight: number,
	slotGap: number,
	teamPad: number,
	teamBottom: number,
}

export type Layout = {
	compact: boolean,
	sizes: Sizes,
	topBar: Rect,
	coins: Rect,
	world: Rect,
	rebirths: Rect,
	menu: Rect,
	goal: Rect,
	team: Rect?,
	-- Every HUD part that must not overlap another, team included when shown.
	parts: { Rect },
}

local HudLayout = {}

-- The menu entries, in order. The Index is a tab inside the Pets screen.
HudLayout.MENU = table.freeze({ "Eggs", "Pets", "Rebirth", "Shop" })

-- Below either of these the HUD switches to its compact sizes (phones).
HudLayout.COMPACT_BELOW = table.freeze({ width = 1000, height = 600 })

HudLayout.SIZES = table.freeze({
	normal = table.freeze({
		topBar = 64,
		gutter = 24,
		coinsWidth = 240,
		worldWidth = 280,
		rebirthsWidth = 140,
		menuWidth = 132,
		menuButton = 46,
		menuGap = 6,
		menuTop = 24,
		goalWidth = 260,
		goalPad = 12,
		goalLine = 22,
		goalGap = 8,
		goalButton = 44,
		slotWidth = 168,
		slotHeight = 56,
		slotGap = 8,
		teamPad = 8,
		teamBottom = 20,
	} :: Sizes),
	compact = table.freeze({
		topBar = 48,
		gutter = 12,
		coinsWidth = 170,
		worldWidth = 200,
		rebirthsWidth = 100,
		menuWidth = 104,
		menuButton = 44,
		menuGap = 6,
		menuTop = 10,
		goalWidth = 200,
		goalPad = 8,
		goalLine = 18,
		goalGap = 6,
		goalButton = 44,
		slotWidth = 132,
		slotHeight = 44,
		slotGap = 6,
		teamPad = 6,
		teamBottom = 10,
	} :: Sizes),
})

local function rect(name: string, x: number, y: number, w: number, h: number): Rect
	return { name = name, x = x, y = y, w = w, h = h }
end

function HudLayout.isCompact(width: number, height: number): boolean
	return width < HudLayout.COMPACT_BELOW.width or height < HudLayout.COMPACT_BELOW.height
end

-- How many team slots the bar shows: none until the player owns a pet, then
-- one per owned pet, up to the team size.
function HudLayout.teamSlots(ownedPets: number, teamSize: number): number
	if ownedPets <= 0 or teamSize <= 0 then
		return 0
	end
	return math.min(math.floor(ownedPets), math.floor(teamSize))
end

-- The HUD rectangles for a screen of width x height pixels (the area below
-- the Roblox top bar), with slots team slots showing.
function HudLayout.compute(width: number, height: number, slots: number): Layout
	local compact = HudLayout.isCompact(width, height)
	local s: Sizes = if compact then HudLayout.SIZES.compact else HudLayout.SIZES.normal

	local topBar = rect("topBar", 0, 0, width, s.topBar)
	local coins = rect("coins", s.gutter, 0, s.coinsWidth, s.topBar)
	local world = rect("world", math.floor((width - s.worldWidth) / 2), 0, s.worldWidth, s.topBar)
	local rebirths =
		rect("rebirths", width - s.gutter - s.rebirthsWidth, 0, s.rebirthsWidth, s.topBar)

	local below = s.topBar + s.menuTop
	local count = #HudLayout.MENU
	local menu =
		rect("menu", s.gutter, below, s.menuWidth, count * s.menuButton + (count - 1) * s.menuGap)

	local goalHeight = s.goalPad * 2 + s.goalLine + s.goalGap + s.goalButton
	local goal = rect("goal", width - s.gutter - s.goalWidth, below, s.goalWidth, goalHeight)

	local parts = { coins, world, rebirths, menu, goal }
	local team: Rect? = nil
	if slots > 0 then
		local teamWidth = slots * s.slotWidth + (slots - 1) * s.slotGap + s.teamPad * 2
		local teamHeight = s.slotHeight + s.teamPad * 2
		local t = rect(
			"team",
			math.floor((width - teamWidth) / 2),
			height - s.teamBottom - teamHeight,
			teamWidth,
			teamHeight
		)
		team = t
		table.insert(parts, t)
	end

	return {
		compact = compact,
		sizes = s,
		topBar = topBar,
		coins = coins,
		world = world,
		rebirths = rebirths,
		menu = menu,
		goal = goal,
		team = team,
		parts = parts,
	}
end

-- True when the two rectangles share any area. Touching edges do not count.
function HudLayout.intersects(a: Rect, b: Rect): boolean
	return a.x < b.x + b.w and b.x < a.x + a.w and a.y < b.y + b.h and b.y < a.y + a.h
end

-- Every pair of rectangles that overlap, as "a/b" in input order.
function HudLayout.overlaps(rects: { Rect }): { string }
	local found = {}
	for i = 1, #rects do
		for j = i + 1, #rects do
			if HudLayout.intersects(rects[i], rects[j]) then
				table.insert(found, rects[i].name .. "/" .. rects[j].name)
			end
		end
	end
	return found
end

-- The names of the rectangles that reach past a width x height screen.
function HudLayout.outside(rects: { Rect }, width: number, height: number): { string }
	local found = {}
	for _, r in rects do
		if r.x < 0 or r.y < 0 or r.x + r.w > width or r.y + r.h > height then
			table.insert(found, r.name)
		end
	end
	return found
end

return HudLayout
