--!strict
-- Pixel-space combat layout: controls keep their tap size instead of scaling
-- an entire desktop mockup into unreadable phone portraits.
local BattleLayout = {}
export type Rect = { x: number, y: number, w: number, h: number }
local function rect(x: number, y: number, w: number, h: number): Rect
	return { x = x, y = y, w = w, h = h }
end
function BattleLayout.compute(width: number, height: number, topInset: number)
	local short = height < 360
	local portrait = height > width
	local pad = if short then 8 else 12
	local gap = if short then 6 else 8
	local headerHeight = if short then 28 else 44
	local headerY = if short then 0 else topInset
	local top = math.max(topInset, headerY + headerHeight) + gap
	local panelHeight = if short then 48 else if portrait then 80 else 92
	local panelWidth = (width - pad * 2 - gap) / 2
	local buttonHeight = if short then 44 else 58
	local giveHeight = if portrait then 44 else buttonHeight
	local rowHeight = if portrait then buttonHeight + gap + giveHeight else buttonHeight
	local rowY = height - pad - rowHeight
	local logHeight = if short then 0 else 44
	local logY = rowY - gap - logHeight
	local artTop = top + panelHeight + gap
	local artBottom = if short then rowY - gap else logY - gap
	local diameter = math.max(1, math.min(panelWidth, artBottom - artTop, 320))
	local artY = artTop + math.max(0, (artBottom - artTop - diameter) / 2)
	local giveWidth = if short then 80 else 100
	local moveWidth = if portrait then panelWidth else (width - pad * 2 - giveWidth - gap * 2) / 2
	return {
		short = short,
		portrait = portrait,
		pad = pad,
		gap = gap,
		headerY = headerY,
		headerHeight = headerHeight,
		playerPanel = rect(pad, top, panelWidth, panelHeight),
		leaderPanel = rect(width - pad - panelWidth, top, panelWidth, panelHeight),
		playerPet = rect(width * 0.25 - diameter / 2, artY, diameter, diameter),
		leaderPet = rect(width * 0.75 - diameter / 2, artY, diameter, diameter),
		log = rect(pad, logY, width - pad * 2, logHeight),
		move1 = rect(pad, rowY, moveWidth, buttonHeight),
		move2 = rect(pad + moveWidth + gap, rowY, moveWidth, buttonHeight),
		giveUp = if portrait
			then rect(pad, rowY + buttonHeight + gap, width - pad * 2, giveHeight)
			else rect(width - pad - giveWidth, rowY, giveWidth, giveHeight),
	}
end
return BattleLayout
