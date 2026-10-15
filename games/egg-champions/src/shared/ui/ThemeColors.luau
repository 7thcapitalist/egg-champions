--!strict
--[[
	ThemeColors: the approved colors of the game, from design/ui (Main.dc.html
	and its README). The client's Theme serves them to every screen as
	Theme.colors, and the server's world signs read the same table, so a
	color is spelled out in exactly one place.

	Pure Luau: no Roblox service, so the test runner checks it headless.
]]

local ThemeColors = table.freeze({
	panel = Color3.fromRGB(18, 22, 31),
	raised = Color3.fromRGB(30, 37, 50),
	border = Color3.fromRGB(42, 50, 66),
	text = Color3.fromRGB(242, 244, 248),
	muted = Color3.fromRGB(155, 166, 186),
	gold = Color3.fromRGB(232, 179, 58),
	badgeEmpty = Color3.fromRGB(90, 100, 120),
	-- The egg shop's Hatch button and the dim behind a full screen panel.
	hatch = Color3.fromRGB(31, 122, 69),
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
