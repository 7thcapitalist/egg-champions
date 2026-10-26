--!strict
--[[
	ThemeColors: the approved colors of the game, from design/ui (Main.dc.html
	and its README). The client's Theme serves them to every screen as
	Theme.colors, and the server's world signs read the same table, so a
	color is spelled out in exactly one place.

	Pure Luau: no Roblox service, so the test runner checks it headless.
]]

local ThemeColors = table.freeze({
	panel = Color3.fromRGB(38, 54, 120),
	raised = Color3.fromRGB(60, 84, 168),
	border = Color3.fromRGB(110, 146, 230),
	-- The thick dark outline around every panel, button and heading.
	outline = Color3.fromRGB(14, 16, 40),
	-- Menu button faces, one color per entry.
	eggs = Color3.fromRGB(255, 176, 46),
	pets = Color3.fromRGB(150, 92, 240),
	rebirth = Color3.fromRGB(64, 196, 120),
	shop = Color3.fromRGB(240, 82, 120),
	-- The red face of every Close button.
	close = Color3.fromRGB(232, 72, 72),
	text = Color3.fromRGB(242, 244, 248),
	muted = Color3.fromRGB(155, 166, 186),
	gold = Color3.fromRGB(255, 210, 73),
	badgeEmpty = Color3.fromRGB(90, 100, 120),
	-- The egg shop's Hatch button and the dim behind a full screen panel.
	hatch = Color3.fromRGB(42, 170, 86),
	white = Color3.fromRGB(255, 255, 255),
	backdrop = Color3.fromRGB(0, 0, 0),
	-- The gym battle (Battle.dc.html): arena ground, healthy HP and team
	-- markers, and a fainted team marker. Low HP uses gold.
	arena = Color3.fromRGB(51, 80, 62),
	arenaFloor = Color3.fromRGB(38, 61, 47),
	healthy = Color3.fromRGB(76, 191, 115),
	fainted = Color3.fromRGB(74, 84, 104),
})

return ThemeColors
