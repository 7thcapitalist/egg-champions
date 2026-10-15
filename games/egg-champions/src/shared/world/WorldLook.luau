--!strict
--[[
	WorldLook: how each world looks beyond its palette. Terrain materials, the
	natural features to scatter (hills, ponds, flower fields, lava streams), the
	prop mix, and the lighting a player sees on that world.

	Looks are keyed like WorldPalette rows (WorldPalette.rowKey), so a world
	with no row of its own still gets a whole look from its environment
	keywords, with no code change.

	Colors are plain { r, g, b } tables and materials are Enum.Material names,
	so this module needs no engine global and the headless tests can check it.
	The server builds terrain and props from it (server/World), and the client
	applies the lighting when a player enters a world (client/Effects/
	WorldLighting). These are presentation values, not game numbers.
]]

local WorldPalette = require(script.Parent.WorldPalette)

export type RGB = WorldPalette.RGB

export type Lighting = {
	clockTime: number,
	brightness: number,
	ambient: RGB,
	outdoorAmbient: RGB,
	atmosphere: {
		density: number,
		offset: number,
		haze: number,
		glare: number,
		color: RGB,
		decay: RGB,
	},
	colorCorrection: { brightness: number, contrast: number, saturation: number, tint: RGB },
	bloom: { intensity: number, size: number, threshold: number },
	sky: { starCount: number, sunSize: number, moonSize: number },
	water: { color: RGB, transparency: number, waveSize: number, reflectance: number },
}

export type TerrainLook = {
	-- Enum.Material names.
	surface: string,
	path: string,
	cliff: string,
	shore: string,
	hill: string,
	seabed: string,
	-- Flower fields, pond rims and lava streams, when the world has them.
	field: string,
	pondRim: string,
	stream: string,
	-- How far the shore slopes out from the island edge to the sea floor.
	shoreWidth: number,
}

export type Range = { min: number, max: number }

export type Features = {
	hills: number,
	hillRadius: Range,
	hillHeight: Range,
	ponds: number,
	pondRadius: Range,
	fields: number,
	fieldRadius: Range,
	streams: number,
	streamWidth: number,
	-- Fences along the path that leads to the portal.
	fences: boolean,
}

export type PropCount = { kind: string, count: number }

export type Look = {
	key: string,
	lighting: Lighting,
	terrain: TerrainLook,
	features: Features,
	props: { PropCount },
	-- Foliage greens, two or three, and flower colors.
	greens: { RGB },
	flowers: { RGB },
	-- The soft light that glows over a lava stream.
	streamGlow: RGB,
}

local function rgb(r: number, g: number, b: number): RGB
	return table.freeze({ r = r, g = g, b = b })
end

local function range(min: number, max: number): Range
	return table.freeze({ min = min, max = max })
end

local function deepFreeze<T>(value: T): T
	if type(value) == "table" and not table.isfrozen(value :: any) then
		for _, child in value :: any do
			deepFreeze(child)
		end
		table.freeze(value :: any)
	end
	return value
end

local WorldLook = {}

WorldLook.LOOKS = deepFreeze({
	green_meadow = {
		key = "green_meadow",
		lighting = {
			-- Bright morning.
			clockTime = 9.5,
			brightness = 2.6,
			ambient = rgb(110, 112, 122),
			outdoorAmbient = rgb(150, 152, 162),
			atmosphere = {
				density = 0.28,
				offset = 0.15,
				haze = 1.2,
				glare = 0.3,
				color = rgb(199, 215, 235),
				decay = rgb(106, 140, 180),
			},
			colorCorrection = {
				brightness = 0.03,
				contrast = 0.08,
				saturation = 0.15,
				tint = rgb(255, 252, 245),
			},
			bloom = { intensity = 0.35, size = 20, threshold = 1.6 },
			sky = { starCount = 0, sunSize = 14, moonSize = 11 },
			water = {
				color = rgb(64, 160, 190),
				transparency = 0.4,
				waveSize = 0.12,
				reflectance = 0.6,
			},
		},
		terrain = {
			surface = "Grass",
			path = "Ground",
			cliff = "Rock",
			shore = "Sand",
			hill = "Grass",
			seabed = "Sand",
			field = "LeafyGrass",
			pondRim = "Mud",
			stream = "Ground",
			shoreWidth = 16,
		},
		features = {
			hills = 7,
			hillRadius = range(14, 22),
			hillHeight = range(4, 8),
			ponds = 1,
			pondRadius = range(9, 12),
			fields = 1,
			fieldRadius = range(11, 14),
			streams = 0,
			streamWidth = 0,
			fences = true,
		},
		props = {
			{ kind = "tree", count = 28 },
			{ kind = "bush", count = 16 },
			{ kind = "rock", count = 8 },
			{ kind = "flower", count = 40 },
		},
		greens = { rgb(76, 153, 64), rgb(98, 176, 72), rgb(60, 128, 58) },
		flowers = { rgb(250, 140, 190), rgb(255, 220, 90), rgb(250, 250, 245), rgb(180, 140, 240) },
		streamGlow = rgb(255, 200, 120),
	},
	coral_coast = {
		key = "coral_coast",
		lighting = {
			-- Warm and sunny.
			clockTime = 13,
			brightness = 3,
			ambient = rgb(130, 122, 110),
			outdoorAmbient = rgb(170, 160, 145),
			atmosphere = {
				density = 0.25,
				offset = 0.1,
				haze = 0.8,
				glare = 0.5,
				color = rgb(255, 236, 205),
				decay = rgb(120, 170, 200),
			},
			colorCorrection = {
				brightness = 0.04,
				contrast = 0.1,
				saturation = 0.2,
				tint = rgb(255, 246, 230),
			},
			bloom = { intensity = 0.4, size = 24, threshold = 1.5 },
			sky = { starCount = 0, sunSize = 18, moonSize = 11 },
			water = {
				color = rgb(40, 200, 200),
				transparency = 0.6,
				waveSize = 0.15,
				reflectance = 0.5,
			},
		},
		terrain = {
			surface = "Sand",
			path = "Sandstone",
			cliff = "Limestone",
			shore = "Sand",
			hill = "Sand",
			seabed = "Sand",
			field = "Sand",
			pondRim = "Sand",
			stream = "Sand",
			shoreWidth = 28,
		},
		features = {
			hills = 5,
			hillRadius = range(16, 24),
			hillHeight = range(3, 5),
			ponds = 0,
			pondRadius = range(0, 0),
			fields = 0,
			fieldRadius = range(0, 0),
			streams = 0,
			streamWidth = 0,
			fences = true,
		},
		props = {
			{ kind = "palm", count = 18 },
			{ kind = "boulder", count = 8 },
			{ kind = "rock", count = 10 },
			{ kind = "bush", count = 8 },
		},
		greens = { rgb(66, 160, 96), rgb(88, 182, 110), rgb(52, 140, 90) },
		flowers = { rgb(255, 120, 110), rgb(255, 200, 80) },
		streamGlow = rgb(150, 220, 255),
	},
	ember_volcano = {
		key = "ember_volcano",
		lighting = {
			-- Dusk, with an orange haze.
			clockTime = 18.2,
			brightness = 1.6,
			ambient = rgb(110, 72, 60),
			outdoorAmbient = rgb(120, 80, 70),
			atmosphere = {
				density = 0.42,
				offset = 0.25,
				haze = 2.6,
				glare = 0.6,
				color = rgb(255, 150, 90),
				decay = rgb(120, 50, 40),
			},
			colorCorrection = {
				brightness = -0.02,
				contrast = 0.15,
				saturation = 0.05,
				tint = rgb(255, 225, 205),
			},
			bloom = { intensity = 0.5, size = 28, threshold = 1.2 },
			sky = { starCount = 1500, sunSize = 21, moonSize = 11 },
			water = {
				color = rgb(90, 40, 30),
				transparency = 0.2,
				waveSize = 0.05,
				reflectance = 0.3,
			},
		},
		terrain = {
			surface = "Basalt",
			path = "Slate",
			cliff = "Slate",
			shore = "Basalt",
			hill = "Slate",
			seabed = "Basalt",
			field = "Basalt",
			pondRim = "Basalt",
			stream = "CrackedLava",
			shoreWidth = 14,
		},
		features = {
			hills = 6,
			hillRadius = range(12, 20),
			hillHeight = range(4, 9),
			ponds = 0,
			pondRadius = range(0, 0),
			fields = 0,
			fieldRadius = range(0, 0),
			streams = 3,
			streamWidth = 4,
			fences = false,
		},
		props = {
			{ kind = "deadTree", count = 16 },
			{ kind = "boulder", count = 14 },
			{ kind = "rock", count = 12 },
		},
		greens = { rgb(92, 84, 80), rgb(70, 64, 62) },
		flowers = { rgb(255, 120, 40) },
		streamGlow = rgb(255, 130, 50),
	},
} :: { [string]: Look })

-- One color per terrain material, the same in every world (Roblox keeps one
-- color per material for the whole place).
WorldLook.MATERIAL_COLORS = deepFreeze({
	Grass = rgb(106, 170, 78),
	LeafyGrass = rgb(92, 160, 70),
	Ground = rgb(150, 116, 80),
	Mud = rgb(110, 86, 64),
	Rock = rgb(122, 110, 98),
	Sand = rgb(236, 214, 158),
	Sandstone = rgb(214, 180, 130),
	Limestone = rgb(220, 206, 180),
	Basalt = rgb(62, 56, 56),
	Slate = rgb(96, 90, 90),
	CrackedLava = rgb(255, 110, 40),
} :: { [string]: RGB })

-- The look for a world, keyed the same way as its palette row.
function WorldLook.forWorld(worldId: string, environment: string): Look
	return WorldLook.LOOKS[WorldPalette.rowKey(worldId, environment)]
		or WorldLook.LOOKS[WorldPalette.DEFAULT_ROW]
end

return WorldLook
