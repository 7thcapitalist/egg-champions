--!strict
--[[
	Terrain: builds each island's ground with the Terrain API, from the
	scenery plan (shared/world/Scenery) and the world's look
	(shared/world/WorldLook). Nothing here decides where anything goes.

	Per island: a sea floor and water around it, a cliff body, a top layer
	of the world's surface material, sloping shores on every side, hills
	(FillBall), a pond and a flower field where the plan has them, lava
	streams, and the paths, painted with ReplaceMaterial so they stay flat.

	Terrain voxels are 4 studs, so every layer here sits on that grid. The
	ground top is y = 0, where the game props stand.
]]

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Scenery = require(Shared:WaitForChild("world"):WaitForChild("Scenery"))
local WorldLook = require(Shared:WaitForChild("world"):WaitForChild("WorldLook"))

local VOXEL = 4
local TOP_LAYER = 4
local SEA_LEVEL = -4
local SEA_FLOOR = -16
-- How far the sea reaches past the island edge.
local SEA_MARGIN = 60

local WorldTerrain = {}

local function material(name: string): Enum.Material
	return (Enum.Material :: any)[name] :: Enum.Material
end

local function terrain(): Terrain
	return Workspace.Terrain
end

-- Sets each terrain material's color, once for the whole place.
function WorldTerrain.paint()
	for name, c in WorldLook.MATERIAL_COLORS do
		local ok = pcall(function()
			terrain():SetMaterialColor(material(name), Color3.fromRGB(c.r, c.g, c.b))
		end)
		if not ok then
			warn("[World] could not color terrain material " .. name)
		end
	end
end

function WorldTerrain.clear()
	terrain():Clear()
end

-- Repaints the top layer from `from` to `to` in a box around (x, z), snapped
-- to the voxel grid so the ground stays level.
local function repaint(
	x: number,
	z: number,
	halfWidth: number,
	from: Enum.Material,
	to: Enum.Material
)
	local region = Region3.new(
		Vector3.new(x - halfWidth, -TOP_LAYER, z - halfWidth),
		Vector3.new(x + halfWidth, 0, z + halfWidth)
	):ExpandToGrid(VOXEL)
	terrain():ReplaceMaterial(region, VOXEL, from, to)
end

-- Repaints a strip along the segment from a to b.
local function repaintStrip(
	a: Scenery.P,
	b: Scenery.P,
	width: number,
	from: Enum.Material,
	to: Enum.Material
)
	local length = math.sqrt((b.x - a.x) ^ 2 + (b.z - a.z) ^ 2)
	local steps = math.max(1, math.ceil(length / (VOXEL / 2)))
	for i = 0, steps do
		local t = i / steps
		repaint(a.x + (b.x - a.x) * t, a.z + (b.z - a.z) * t, width / 2, from, to)
	end
end

-- Builds one island's terrain.
function WorldTerrain.build(scenery: Scenery.WorldScenery)
	local t = terrain()
	local look = WorldLook.LOOKS[scenery.theme]
	local tl = look.terrain
	local o = scenery.origin
	local size = scenery.half * 2
	local sea = size + SEA_MARGIN * 2

	-- Sea floor, then water over it.
	t:FillBlock(
		CFrame.new(o.x, SEA_FLOOR - VOXEL, o.z),
		Vector3.new(sea, VOXEL * 2, sea),
		material(tl.seabed)
	)
	t:FillBlock(
		CFrame.new(o.x, (SEA_FLOOR + SEA_LEVEL) / 2, o.z),
		Vector3.new(sea, SEA_LEVEL - SEA_FLOOR, sea),
		Enum.Material.Water
	)
	-- The island: a cliff body, then the surface layer on top.
	t:FillBlock(
		CFrame.new(o.x, (SEA_FLOOR - TOP_LAYER) / 2, o.z),
		Vector3.new(size, -TOP_LAYER - SEA_FLOOR, size),
		material(tl.cliff)
	)
	t:FillBlock(
		CFrame.new(o.x, -TOP_LAYER / 2, o.z),
		Vector3.new(size, TOP_LAYER, size),
		material(tl.surface)
	)

	-- Shores: a wedge down each side, its high edge on the island's edge.
	local width = tl.shoreWidth
	local drop = -SEA_FLOOR
	for side = 0, 3 do
		local angle = side * math.pi / 2
		local out = Vector3.new(math.sin(angle), 0, -math.cos(angle))
		local center = Vector3.new(o.x, -drop / 2, o.z) + out * (scenery.half + width / 2)
		-- A wedge's low edge is its front (-Z), so face it outward.
		local frame = CFrame.lookAt(center, center + out)
		t:FillWedge(frame, Vector3.new(size, drop, width), material(tl.shore))
	end
	for cx = -1, 1, 2 do
		for cz = -1, 1, 2 do
			t:FillBall(
				Vector3.new(o.x + cx * scenery.half, -width * 0.6, o.z + cz * scenery.half),
				width * 0.6,
				material(tl.shore)
			)
		end
	end

	local surface = material(tl.surface)
	for _, hill in scenery.hills do
		t:FillBall(
			Vector3.new(hill.x, hill.height - hill.radius, hill.z),
			hill.radius,
			material(tl.hill)
		)
	end
	for _, field in scenery.fields do
		local cells = math.ceil(field.r / VOXEL)
		for i = -cells, cells do
			for j = -cells, cells do
				local x, z = field.x + i * VOXEL, field.z + j * VOXEL
				if (x - field.x) ^ 2 + (z - field.z) ^ 2 <= field.r ^ 2 then
					repaint(x, z, VOXEL / 2, surface, material(tl.field))
				end
			end
		end
	end
	for _, pond in scenery.ponds do
		t:FillCylinder(
			CFrame.new(pond.x, -TOP_LAYER / 2, pond.z),
			TOP_LAYER,
			pond.r + 2,
			material(tl.pondRim)
		)
		t:FillCylinder(CFrame.new(pond.x, -VOXEL, pond.z), VOXEL * 2, pond.r, Enum.Material.Water)
	end
	for _, stream in scenery.streams do
		for i = 2, #stream.points do
			repaintStrip(
				stream.points[i - 1],
				stream.points[i],
				stream.width,
				surface,
				material(tl.stream)
			)
		end
	end
	for _, path in scenery.paths do
		repaintStrip(path.a, path.b, path.width, surface, material(tl.path))
	end
end

return WorldTerrain
