--!strict
--[[
	WorldPalette: the one palette table of world colors, shared by the server
	and the client.

	The world builder (server/World/Builder) paints every island, prop and
	portal from it, and the progression effects (client/Effects/Progress) take
	each world's unlock swirl color from the same row, so a world's ground and
	its portal swirl can never drift apart.

	Rows are keyed by world id. A world with no row gets one picked from
	keywords in its environment string, so a new world in the spec still builds
	and still has an unlock color with no code change.

	Colors are plain { r, g, b } tables and materials are Enum.Material names,
	so this module needs no engine global and the headless tests can check that
	every world in config resolves. These are presentation values, not game
	numbers.
]]

local Config = require(script.Parent.Parent.Config)

export type RGB = { r: number, g: number, b: number }

export type Palette = {
	ground: RGB,
	-- An Enum.Material name, turned into the enum by the builder.
	groundMaterial: string,
	cliff: RGB,
	water: RGB,
	trunk: RGB,
	leaf: RGB,
	rock: RGB,
	accent: RGB,
	trim: RGB,
	glow: RGB,
	text: RGB,
	-- The world's own color: the portal swirl when the world opens.
	swirl: RGB,
}

local function rgb(r: number, g: number, b: number): RGB
	return table.freeze({ r = r, g = g, b = b })
end

local WorldPalette = {}

WorldPalette.ROWS = table.freeze({
	green_meadow = table.freeze({
		ground = rgb(106, 170, 78),
		groundMaterial = "Grass",
		cliff = rgb(122, 96, 70),
		water = rgb(80, 150, 210),
		trunk = rgb(110, 76, 48),
		leaf = rgb(62, 140, 64),
		rock = rgb(140, 140, 132),
		accent = rgb(250, 214, 92),
		trim = rgb(236, 230, 214),
		glow = rgb(255, 240, 170),
		text = rgb(255, 255, 255),
		swirl = rgb(110, 220, 110),
	}),
	coral_coast = table.freeze({
		ground = rgb(236, 214, 158),
		groundMaterial = "Sand",
		cliff = rgb(196, 160, 118),
		water = rgb(40, 170, 200),
		trunk = rgb(150, 112, 70),
		leaf = rgb(70, 170, 120),
		rock = rgb(232, 128, 120),
		accent = rgb(90, 120, 200),
		trim = rgb(248, 244, 232),
		glow = rgb(150, 220, 255),
		text = rgb(255, 255, 255),
		swirl = rgb(60, 190, 230),
	}),
	ember_volcano = table.freeze({
		ground = rgb(70, 62, 62),
		groundMaterial = "Basalt",
		cliff = rgb(48, 42, 42),
		water = rgb(240, 100, 30),
		trunk = rgb(60, 50, 46),
		leaf = rgb(110, 90, 80),
		rock = rgb(90, 80, 78),
		accent = rgb(230, 90, 40),
		trim = rgb(150, 140, 136),
		glow = rgb(255, 150, 60),
		text = rgb(255, 255, 255),
		swirl = rgb(255, 110, 40),
	}),
} :: { [string]: Palette })

-- For a world with no row: keywords in its environment string pick a row.
WorldPalette.KEYWORDS = table.freeze({
	table.freeze({ words = { "lava", "volcano", "ash", "ember", "fire" }, row = "ember_volcano" }),
	table.freeze({
		words = { "beach", "reef", "sea", "ocean", "coast", "storm" },
		row = "coral_coast",
	}),
	table.freeze({ words = { "grass", "forest", "meadow", "field" }, row = "green_meadow" }),
} :: { { words: { string }, row: string } })

WorldPalette.DEFAULT_ROW = "green_meadow"

-- The row for a world: its own, else one picked by environment keywords,
-- else the default.
function WorldPalette.forWorld(worldId: string, environment: string): Palette
	local own = WorldPalette.ROWS[worldId]
	if own ~= nil then
		return own
	end
	local text = string.lower(environment)
	for _, entry in WorldPalette.KEYWORDS do
		for _, word in entry.words do
			if string.find(text, word, 1, true) ~= nil then
				return WorldPalette.ROWS[entry.row]
			end
		end
	end
	return WorldPalette.ROWS[WorldPalette.DEFAULT_ROW]
end

-- The swirl color a world's portal shows when the world opens.
function WorldPalette.unlockColor(worldId: string): RGB
	local environment = ""
	for _, world in Config.worlds do
		if world.id == worldId then
			environment = world.environment
		end
	end
	return WorldPalette.forWorld(worldId, environment).swirl
end

return WorldPalette
