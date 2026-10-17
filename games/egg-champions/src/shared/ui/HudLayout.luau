--!strict
--[[
	HudLayout: where every part of the main screen HUD sits, as plain
	rectangles, for a given screen size and the space Roblox itself uses.

	All rectangles are in full screen pixels (ScreenGuis with IgnoreGuiInset),
	so they line up with the inputs, which come from the engine:
	- the top-bar inset (GuiService.TopbarInset): the free part of Roblox's
	  top bar, right of its logo, menu, chat and voice buttons and left of
	  its right-hand buttons;
	- the chat rect: where Roblox's chat window sits (top left, below the
	  Roblox top bar), or nil when chat is off. The client reads it from
	  TextChatService's ChatWindowConfiguration, or uses chatEstimate.

	The Roblox buttons and the chat window are reserved: no HUD part may
	overlap them. The main screen (client/UI/Main) places its panels from
	compute(), and the specs run overlaps() on parts plus reserved at
	808 x 432, 844 x 390, 1092 x 432, 1280 x 720 and 1920 x 1080 with
	several insets, so a layout that collides is caught before a playtest.

	The parts:
	- coins: coins and coins per click, starting 8 px right of the inset's
	  left edge, inside Roblox's top bar row;
	- world: the world name, centred on the screen when the row allows,
	  otherwise centred between coins and rebirths;
	- rebirths: the rebirth count, small, at the right of the row;
	- menu: the menu buttons on the left edge, below 45% of the screen
	  height and below the chat window, vertically centred in what is left.
	  Only the unlocked ones show (menuShown): EGGS and PETS always, REBIRTH
	  once the player can afford a rebirth or has beaten a gym, SHOP once
	  the tutorial is done;
	- goal: the next-goal card on the right, at most a quarter of the screen
	  height: a goal line of up to two lines at GOAL_TEXT pixels, then one
	  button (the tutorial's SKIP shares that row), or a labelled progress
	  bar in the button's place. Every card text must fit (fitsGoal);
	- team: the team bar, only when at least one pet is equipped. It sits
	  at the bottom centre, and on compact screens at the bottom left, short
	  and narrow, so it never covers the character in the middle.

	The top bar holds coins, world and rebirths, so it is returned apart
	(topBar) and not counted as an overlap. When Roblox shows no top bar row
	tall enough (or too narrow) the HUD bar spans the screen right below it.

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

-- The engine inputs. left and right are TopbarInset.Min.X and Max.X, top
-- is TopbarInset.Max.Y. chat is the chat window rect, nil when chat is off.
export type Insets = {
	left: number,
	right: number,
	top: number,
	chat: Rect?,
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
	goalLines: number,
	goalGap: number,
	goalButton: number,
	slotWidth: number,
	slotHeight: number,
	slotGap: number,
	teamPad: number,
	teamBottom: number,
	chatWidth: number,
	chatHeight: number,
}

export type Layout = {
	compact: boolean,
	horizontalMenu: boolean,
	sizes: Sizes,
	-- True when coins, world and rebirths sit inside Roblox's top bar row.
	inRow: boolean,
	topBar: Rect,
	-- The first y below every top bar: where screens like the egg shop start.
	contentTop: number,
	coins: Rect,
	world: Rect,
	rebirths: Rect,
	menu: Rect,
	goal: Rect,
	team: Rect?,
	chat: Rect?,
	-- Every HUD part that must not overlap another, team included when shown.
	parts: { Rect },
	-- Space Roblox uses: its top bar buttons and the chat window.
	reserved: { Rect },
}

local HudLayout = {}

-- Every menu entry, in order. The Index is a tab inside the Pets screen.
-- menuShown picks the ones a player sees.
HudLayout.MENU = table.freeze({ "Eggs", "Pets", "Rebirth", "Shop" })

-- The goal line's text size in pixels. It is never scaled down.
HudLayout.GOAL_TEXT = 18

-- Coins start this far right of the top-bar inset's left edge.
HudLayout.INSET_GAP = 8

-- The menu never starts above this share of the screen height, so the chat
-- window (top left) never covers it.
HudLayout.MENU_BELOW = 0.45

-- Below this, Roblox's top bar row is too short to hold the coins.
HudLayout.MIN_ROW = 30

-- The narrowest the world name may get before the bar leaves the row.
HudLayout.MIN_WORLD = 90

-- Average glyph widths, as a share of the text size, for the label font.
-- Generous on purpose, so a line that fits here fits on screen.
HudLayout.GLYPH = table.freeze({
	upper = 0.7,
	lower = 0.55,
	digit = 0.58,
	space = 0.28,
	other = 0.4,
})

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
		goalWidth = 280,
		goalPad = 12,
		goalLine = 22,
		goalLines = 2,
		goalGap = 8,
		goalButton = 44,
		slotWidth = 168,
		slotHeight = 56,
		slotGap = 8,
		teamPad = 8,
		teamBottom = 20,
		chatWidth = 400,
		chatHeight = 230,
	} :: Sizes),
	compact = table.freeze({
		topBar = 48,
		gutter = 12,
		coinsWidth = 170,
		worldWidth = 200,
		rebirthsWidth = 100,
		menuWidth = 104,
		menuButton = 34,
		menuGap = 4,
		menuTop = 10,
		goalWidth = 220,
		goalPad = 6,
		goalLine = 20,
		goalLines = 2,
		goalGap = 4,
		goalButton = 40,
		slotWidth = 116,
		slotHeight = 36,
		slotGap = 4,
		teamPad = 4,
		teamBottom = 10,
		chatWidth = 320,
		chatHeight = 100,
	} :: Sizes),
})

-- No Roblox top bar and no chat.
HudLayout.NO_INSETS = table.freeze({ left = 0, right = 0, top = 0, chat = nil }) :: Insets

local function rect(name: string, x: number, y: number, w: number, h: number): Rect
	return { name = name, x = x, y = y, w = w, h = h }
end

function HudLayout.isCompact(width: number, height: number): boolean
	return width < HudLayout.COMPACT_BELOW.width or height < HudLayout.COMPACT_BELOW.height
end

-- How many team slots the bar shows: none until the player equips a pet,
-- then one per equipped pet, up to the team size. An owned pet that is not
-- equipped never shows as an empty slot.
function HudLayout.teamSlots(equippedPets: number, teamSize: number): number
	if equippedPets <= 0 or teamSize <= 0 then
		return 0
	end
	return math.min(math.floor(equippedPets), math.floor(teamSize))
end

-- Where Roblox's chat window is expected when the engine has not reported
-- its size yet: top left, right below Roblox's top bar.
function HudLayout.chatEstimate(width: number, height: number, top: number): Rect
	local s: Sizes = if HudLayout.isCompact(width, height)
		then HudLayout.SIZES.compact
		else HudLayout.SIZES.normal
	local w = math.min(s.chatWidth, math.floor(width * 0.4))
	return rect("chat", HudLayout.INSET_GAP, top + HudLayout.INSET_GAP, w, s.chatHeight)
end

-- The estimated pixel width of one line of text at size.
function HudLayout.textWidth(text: string, size: number): number
	local g = HudLayout.GLYPH
	local total = 0
	for i = 1, #text do
		local c = string.sub(text, i, i)
		local share = g.other
		if string.match(c, "%u") then
			share = g.upper
		elseif string.match(c, "%l") then
			share = g.lower
		elseif string.match(c, "%d") then
			share = g.digit
		elseif c == " " then
			share = g.space
		end
		total += share * size
	end
	return total
end

-- How many lines text takes when word wrapped to width pixels at size. A
-- word wider than the line counts as the lines it would need on its own.
function HudLayout.lineCount(text: string, width: number, size: number): number
	local function span(line: string): number
		return math.max(1, math.ceil(HudLayout.textWidth(line, size) / width))
	end
	local lines = 0
	local current = ""
	for word in string.gmatch(text, "%S+") do
		local candidate = if current == "" then word else current .. " " .. word
		if current ~= "" and HudLayout.textWidth(candidate, size) > width then
			lines += span(current)
			current = word
		else
			current = candidate
		end
	end
	if current ~= "" then
		lines += span(current)
	end
	return lines
end

-- True when text fits the goal card's line area at GOAL_TEXT.
function HudLayout.fitsGoal(text: string, sizes: Sizes): boolean
	local width = sizes.goalWidth - 2 * sizes.goalPad
	return HudLayout.lineCount(text, width, HudLayout.GOAL_TEXT) <= sizes.goalLines
end

-- The HUD rectangles for a full screen of width x height pixels with slots
-- team slots showing. insets defaults to NO_INSETS. menuCount is how many
-- menu buttons show (menuShown), every entry of MENU when nil.
function HudLayout.compute(
	width: number,
	height: number,
	slots: number,
	insets: Insets?,
	menuCount: number?
): Layout
	local compact = HudLayout.isCompact(width, height)
	local s: Sizes = if compact then HudLayout.SIZES.compact else HudLayout.SIZES.normal
	-- A short landscape viewport cannot fit the vertical menu below chat.
	-- Keep the primary actions in one touch-sized row between the controls.
	local horizontalMenu = width >= 600 and height < 360
	if horizontalMenu then
		s = table.clone(s)
		s.menuButton = 40
	end
	local i: Insets = insets or HudLayout.NO_INSETS
	local gap = HudLayout.INSET_GAP
	local rowTop = math.max(0, i.top)
	local rowLeft = math.clamp(i.left, 0, width)
	local rowRight = if i.right > rowLeft then math.min(i.right, width) else width

	local reserved: { Rect } = {}

	-- Coins, world and rebirths inside Roblox's row when it is tall and wide
	-- enough; otherwise a bar of their own right below it.
	local inRow = false
	local topBar, coins, world, rebirths
	if rowTop >= HudLayout.MIN_ROW then
		local coinsX = rowLeft + gap
		local rebirthsX = rowRight - gap - s.rebirthsWidth
		local lo = coinsX + s.coinsWidth + gap
		local hi = rebirthsX - gap
		if hi - lo >= HudLayout.MIN_WORLD then
			inRow = true
			local ww = math.min(s.worldWidth, hi - lo)
			local wx = math.clamp(math.floor((width - ww) / 2), lo, hi - ww)
			topBar = rect("topBar", rowLeft, 0, rowRight - rowLeft, rowTop)
			coins = rect("coins", coinsX, 0, s.coinsWidth, rowTop)
			world = rect("world", wx, 0, ww, rowTop)
			rebirths = rect("rebirths", rebirthsX, 0, s.rebirthsWidth, rowTop)
			if rowLeft > 0 then
				table.insert(reserved, rect("robloxLeft", 0, 0, rowLeft, rowTop))
			end
			if rowRight < width then
				table.insert(reserved, rect("robloxRight", rowRight, 0, width - rowRight, rowTop))
			end
		end
	end
	if not inRow then
		-- A chat window reaching into the bar pushes coins right of it.
		local coinsX = s.gutter
		local barY = rowTop
		local c = i.chat
		if c ~= nil and HudLayout.intersects(c, rect("bar", 0, rowTop, width, s.topBar)) then
			coinsX = math.max(coinsX, c.x + c.w + gap)
		end
		local rebirthsX = width - s.gutter - s.rebirthsWidth
		if coinsX + s.coinsWidth + gap > rebirthsX and c ~= nil then
			barY = math.max(barY, c.y + c.h + gap)
			coinsX = s.gutter
		end
		local lo = coinsX + s.coinsWidth + gap
		local hi = rebirthsX - gap
		local ww = math.max(0, math.min(s.worldWidth, hi - lo))
		local wx = math.clamp(math.floor((width - ww) / 2), lo, math.max(lo, hi - ww))
		topBar = rect("topBar", 0, barY, width, s.topBar)
		coins = rect("coins", coinsX, barY, s.coinsWidth, s.topBar)
		world = rect("world", wx, barY, ww, s.topBar)
		rebirths = rect("rebirths", rebirthsX, barY, s.rebirthsWidth, s.topBar)
		if rowTop > 0 then
			table.insert(reserved, rect("robloxBar", 0, 0, width, rowTop))
		end
	end
	local contentTop = topBar.y + topBar.h

	local chat = i.chat
	if chat ~= nil then
		table.insert(reserved, chat)
	end

	-- The team bar's height, also used to keep the menu clear of it on
	-- compact screens whether or not it shows yet.
	local teamHeight = s.slotHeight + s.teamPad * 2
	local teamTop = height - (if width < 500 then 140 else s.teamBottom) - teamHeight

	local count = math.clamp(menuCount or #HudLayout.MENU, 1, #HudLayout.MENU)
	local menuHeight = count * s.menuButton + (count - 1) * s.menuGap
	local bandTop = math.ceil(height * HudLayout.MENU_BELOW)
	if chat ~= nil and chat.x < s.gutter + s.menuWidth then
		bandTop = math.max(bandTop, chat.y + chat.h + s.menuGap)
	end
	bandTop = math.max(bandTop, contentTop + s.menuTop)
	local bandBottom = if compact then teamTop - s.menuGap else height - s.gutter
	local menuY = bandTop + math.max(0, math.floor((bandBottom - bandTop - menuHeight) / 2))
	local menu = rect("menu", s.gutter, menuY, s.menuWidth, menuHeight)
	if horizontalMenu then
		local menuWidth = count * s.menuWidth + (count - 1) * s.menuGap
		menu = rect(
			"menu",
			math.floor((width - menuWidth) / 2),
			height - gap - s.menuButton,
			menuWidth,
			s.menuButton
		)
	end

	local goalHeight = s.goalPad * 2 + s.goalLine * s.goalLines + s.goalGap + s.goalButton
	local goal = rect(
		"goal",
		width - s.gutter - s.goalWidth,
		contentTop + s.menuTop,
		s.goalWidth,
		goalHeight
	)

	local parts = { coins, world, rebirths, menu, goal }
	local team: Rect? = nil
	if slots > 0 and not horizontalMenu then
		if width < 500 then
			s = table.clone(s)
			s.slotWidth = math.min(
				s.slotWidth,
				math.floor((width - 2 * s.gutter - 2 * s.teamPad - (slots - 1) * s.slotGap) / slots)
			)
		end
		local teamWidth = slots * s.slotWidth + (slots - 1) * s.slotGap + s.teamPad * 2
		local teamX = if compact then s.gutter else math.floor((width - teamWidth) / 2)
		local t = rect("team", teamX, teamTop, teamWidth, teamHeight)
		team = t
		table.insert(parts, t)
	end

	return {
		compact = compact,
		horizontalMenu = horizontalMenu,
		sizes = s,
		inRow = inRow,
		topBar = topBar,
		contentTop = contentTop,
		coins = coins,
		world = world,
		rebirths = rebirths,
		menu = menu,
		goal = goal,
		team = team,
		chat = chat,
		parts = parts,
		reserved = reserved,
	}
end

-- What decides which menu buttons show: the player's coins, the price of
-- their next rebirth, how many gyms they have beaten, and whether the
-- tutorial is done.
export type MenuState = {
	coins: number,
	rebirthCost: number,
	gymsBeaten: number,
	tutorialDone: boolean,
}

-- The menu entries a player sees, in HudLayout.MENU order. EGGS and PETS
-- always; REBIRTH once a rebirth is affordable or the first gym is beaten;
-- SHOP once the tutorial is done. A first-minute player sees two buttons.
function HudLayout.menuShown(state: MenuState): { string }
	local shown: { string } = {}
	for _, entry in HudLayout.MENU do
		local visible = true
		if entry == "Rebirth" then
			visible = state.gymsBeaten > 0
				or (state.rebirthCost > 0 and state.coins >= state.rebirthCost)
		elseif entry == "Shop" then
			visible = state.tutorialDone
		end
		if visible then
			table.insert(shown, entry)
		end
	end
	return shown
end

-- What decides which HUD parts are gold. Gold marks what to do next.
-- onboarding: the tutorial runs. pointer: the tutorial's pointer outlines
-- something on screen. goalBar: the goal card shows its progress bar.
-- goalReady: the goal card shows a ready button. menu: the menu entries
-- shown (menuShown). slots: team slots shown.
export type GoldState = {
	onboarding: boolean,
	pointer: boolean,
	goalBar: boolean,
	goalReady: boolean,
	menu: { string },
	slots: number,
}

-- The HUD parts drawn in gold, by name: "pointer", "goalBar" (the fill of
-- the goal card's bar), "goal" (its button), "menu:Shop", "perClick" and
-- "slotPowers". While the tutorial runs exactly one thing is gold: the
-- pointer when it outlines something, otherwise the goal card's bar. The
-- coin icon is the currency's picture, not a marker, and is not counted.
function HudLayout.goldParts(state: GoldState): { string }
	if state.onboarding then
		if state.pointer then
			return { "pointer" }
		end
		if state.goalBar then
			return { "goalBar" }
		end
		return {}
	end
	local gold: { string } = {}
	if state.goalReady then
		table.insert(gold, "goal")
	end
	if table.find(state.menu, "Shop") ~= nil then
		table.insert(gold, "menu:Shop")
	end
	table.insert(gold, "perClick")
	if state.slots > 0 then
		table.insert(gold, "slotPowers")
	end
	return gold
end

-- True when the two rectangles share any area. Touching edges do not count.
function HudLayout.intersects(a: Rect, b: Rect): boolean
	return a.x < b.x + b.w and b.x < a.x + a.w and a.y < b.y + b.h and b.y < a.y + a.h
end

-- Every pair of rectangles that overlap, as "a/b" in input order.
function HudLayout.overlaps(rects: { Rect }): { string }
	local found = {}
	for a = 1, #rects do
		for b = a + 1, #rects do
			if HudLayout.intersects(rects[a], rects[b]) then
				table.insert(found, rects[a].name .. "/" .. rects[b].name)
			end
		end
	end
	return found
end

-- Every HUD part that overlaps a reserved rect, as "part/reserved".
function HudLayout.blocked(layout: Layout): { string }
	local found = {}
	for _, part in layout.parts do
		for _, r in layout.reserved do
			if HudLayout.intersects(part, r) then
				table.insert(found, part.name .. "/" .. r.name)
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
