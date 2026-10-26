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
	local sidePanels = not portrait and height < 450
	local pad = if sidePanels then 8 else 12
	local gap = if sidePanels then 6 else 8
	local headerHeight = if sidePanels then 28 else 44
	local headerY = if short then 0 else topInset
	local top = math.max(topInset, headerY + headerHeight) + gap
	local panelHeight = if short then 48 else if portrait then 80 else 92
	local panelWidth = (width - pad * 2 - gap) / 2
	local buttonHeight = if short then 44 else if width < 1000 then 48 else 58
	local giveHeight = if portrait then 44 else buttonHeight
	local rowHeight = if portrait then buttonHeight + gap + giveHeight else buttonHeight
	local rowY = height - pad - rowHeight
	-- A second horizontal HP row consumes most of a short screen. Keep status
	-- at the outer edges, leaving the full middle height for both creatures.
	if sidePanels then
		local statusWidth = math.min(148, panelWidth * 0.42)
		local stageWidth = panelWidth - statusWidth - gap
		local logHeight = if short then 0 else 48
		local logY = rowY - gap - logHeight
		local stageHeight = math.max(1, (if short then rowY else logY) - gap - top)
		local petSize = math.max(1, math.min(stageWidth, stageHeight, 320))
		local statusHeight = math.min(if short then 64 else 92, stageHeight)
		local statusY = top + (stageHeight - statusHeight) / 2
		local petY = top + (stageHeight - petSize) / 2
		local petX = pad + statusWidth + gap + (stageWidth - petSize) / 2
		local giveWidth = 80
		local moveWidth = math.min(190, (width - pad * 2 - giveWidth - gap * 2) / 2)
		local actionsX = (width - (moveWidth * 2 + giveWidth + gap * 2)) / 2
		return {
			short = short,
			portrait = portrait,
			sidePanels = true,
			pad = pad,
			gap = gap,
			headerY = headerY,
			headerHeight = headerHeight,
			playerPanel = rect(pad, statusY, statusWidth, statusHeight),
			leaderPanel = rect(width - pad - statusWidth, statusY, statusWidth, statusHeight),
			playerPet = rect(petX, petY, petSize, petSize),
			leaderPet = rect(width - petX - petSize, petY, petSize, petSize),
			log = rect(pad, logY, width - pad * 2, math.max(1, logHeight)),
			move1 = rect(actionsX, rowY, moveWidth, buttonHeight),
			move2 = rect(actionsX + moveWidth + gap, rowY, moveWidth, buttonHeight),
			giveUp = rect(actionsX + (moveWidth + gap) * 2, rowY, giveWidth, buttonHeight),
		}
	end
	-- Leave room for a full wrapped message plus padding on narrow phones.
	local logHeight = if short then 0 else if portrait then 72 else 60
	local logY = rowY - gap - logHeight
	local artTop = top + panelHeight + gap
	local artBottom = if short then rowY - gap else logY - gap
	local diameter = math.max(1, math.min(panelWidth, artBottom - artTop, 320))
	local artY = artTop + math.max(0, (artBottom - artTop - diameter) / 2)
	local giveWidth = if short then 80 else 100
	local moveWidth = if portrait
		then panelWidth
		else math.min(240, (width - pad * 2 - giveWidth - gap * 2) / 2)
	local actionsX = if portrait then pad else (width - (moveWidth * 2 + giveWidth + gap * 2)) / 2
	return {
		short = short,
		portrait = portrait,
		sidePanels = false,
		pad = pad,
		gap = gap,
		headerY = headerY,
		headerHeight = headerHeight,
		playerPanel = rect(pad, top, panelWidth, panelHeight),
		leaderPanel = rect(width - pad - panelWidth, top, panelWidth, panelHeight),
		playerPet = rect(width * 0.25 - diameter / 2, artY, diameter, diameter),
		leaderPet = rect(width * 0.75 - diameter / 2, artY, diameter, diameter),
		log = rect(pad, logY, width - pad * 2, logHeight),
		move1 = rect(actionsX, rowY, moveWidth, buttonHeight),
		move2 = rect(actionsX + moveWidth + gap, rowY, moveWidth, buttonHeight),
		giveUp = if portrait
			then rect((width - giveWidth) / 2, rowY + buttonHeight + gap, giveWidth, giveHeight)
			else rect(actionsX + (moveWidth + gap) * 2, rowY, giveWidth, giveHeight),
	}
end
return BattleLayout
