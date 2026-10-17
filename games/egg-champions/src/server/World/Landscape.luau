--!strict
-- Constructed biomes share the existing collision, arrival and interaction plan.
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Scenery = require(Shared:WaitForChild("world"):WaitForChild("Scenery"))
local WorldPalette = require(Shared:WaitForChild("world"):WaitForChild("WorldPalette"))
local Landscape = {}

function Landscape.paint() end

function Landscape.clear()
	Workspace.Terrain:Clear()
end

function Landscape.build(scenery: Scenery.WorldScenery, parent: Folder)
	local palette = WorldPalette.ROWS[scenery.theme]
	local function rgb(c: WorldPalette.RGB): Color3
		return Color3.fromRGB(c.r, c.g, c.b)
	end
	local ground = rgb(palette.ground)
	local rock = rgb(palette.cliff)
	local folder = Instance.new("Folder")
	folder.Name = "Landscape"
	local function block(
		name: string,
		size: Vector3,
		cf: CFrame,
		tint: Color3,
		studs: boolean?
	): Part
		local p = Instance.new("Part")
		p.Name = name
		p.Size = size
		p.CFrame = cf
		p.Color = tint
		p.Anchored = true
		p.Material = Enum.Material.SmoothPlastic
		p.TopSurface = if studs then Enum.SurfaceType.Studs else Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		if studs then
			local texture = Instance.new("Texture")
			texture.Name = "StudPattern"
			texture.Texture = "rbxasset://textures/Studs.dds"
			texture.Face = Enum.NormalId.Top
			texture.StudsPerTileU = 2
			texture.StudsPerTileV = 2
			texture.Transparency = 0.78
			texture.Parent = p
		end
		p.Parent = folder
		return p
	end
	local o = scenery.origin
	local size = scenery.half * 2
	block("Island", Vector3.new(size, 12, size), CFrame.new(o.x, -7, o.z), rock)
	local water = block(
		"Sea",
		Vector3.new(size + 110, 1, size + 110),
		CFrame.new(o.x, -8, o.z),
		rgb(palette.water)
	)
	water.Material = Enum.Material.Glass
	water.Transparency = 0.18
	water.CanCollide = false
	local tile = 20
	local count = math.ceil(size / tile)
	for x = 0, count - 1 do
		for z = 0, count - 1 do
			local tint = ground:Lerp(Color3.new(1, 1, 1), if (x + z) % 2 == 0 then 0.075 else 0)
			block(
				"GroundTile",
				Vector3.new(tile, 1, tile),
				CFrame.new(
					o.x - scenery.half + (x + 0.5) * tile,
					-0.5,
					o.z - scenery.half + (z + 0.5) * tile
				),
				tint,
				true
			)
		end
	end
	for side = 0, 3 do
		for column = 0, 12 do
			local height = 18 + ((column * 7 + side * 3 + scenery.worldIndex) % 4) * 4
			local along = -96 + column * 16
			local cf = CFrame.new(o.x, 0, o.z)
				* CFrame.Angles(0, side * math.pi / 2, 0)
				* CFrame.new(along, height / 2 - 3, -scenery.half - 7)
			block(
				"Cliff",
				Vector3.new(16, height, 14),
				cf,
				rock:Lerp(ground, 0.16 + (column % 3) * 0.07),
				true
			)
			block(
				"CliffCap",
				Vector3.new(16.5, 1.5, 14.5),
				cf * CFrame.new(0, height / 2, 0),
				ground,
				true
			)
		end
	end
	-- Spheres match Scenery.heightAt exactly, so trees stay grounded.
	for _, hill in scenery.hills do
		local p = block(
			"Hill",
			Vector3.one * (hill.radius * 2),
			CFrame.new(hill.x, hill.height - hill.radius, hill.z),
			ground
		)
		p.Shape = Enum.PartType.Ball
	end
	for _, pond in scenery.ponds do
		block(
			"PondRim",
			Vector3.new(pond.r * 2 + 2, 0.12, pond.r * 2 + 2),
			CFrame.new(pond.x, 0.06, pond.z),
			rgb(palette.trim)
		)
		local p = block(
			"Pond",
			Vector3.new(pond.r * 2, 0.15, pond.r * 2),
			CFrame.new(pond.x, 0.15, pond.z),
			rgb(palette.water)
		)
		p.Material = Enum.Material.Glass
		p.Transparency = 0.12
	end
	local function strip(
		name: string,
		a: Scenery.P,
		b: Scenery.P,
		width: number,
		tint: Color3,
		neon: boolean?,
		y: number?
	)
		local level = y or 0.12
		local from = Vector3.new(a.x, level, a.z)
		local to = Vector3.new(b.x, level, b.z)
		local length = (to - from).Magnitude
		if length < 0.01 then
			return
		end
		local p = block(
			name,
			Vector3.new(width, 0.16, length + 0.1),
			CFrame.lookAt((from + to) / 2, to),
			tint
		)
		if neon then
			p.Material = Enum.Material.Neon
		end
		p.CanCollide = false
	end
	for _, path in scenery.paths do
		strip(
			"PathBorder",
			path.a,
			path.b,
			path.width + 1,
			rock:Lerp(rgb(palette.trim), 0.45),
			false,
			0.09
		)
		strip("Path", path.a, path.b, path.width, rgb(palette.trim), false, 0.13)
	end
	for _, stream in scenery.streams do
		for i = 2, #stream.points do
			strip(
				"Lava",
				stream.points[i - 1],
				stream.points[i],
				stream.width,
				rgb(palette.glow),
				true
			)
		end
	end
	local pad = block(
		"ArrivalPlaza",
		Vector3.new(22, 0.16, 22),
		CFrame.new(o.x, 0.09, o.z),
		rgb(palette.trim)
	)
	pad.CanCollide = false
	for _, side in { -1, 1 } do
		local rim = block(
			"PlazaTrim",
			Vector3.new(22, 0.18, 0.5),
			CFrame.new(o.x, 0.2, o.z + side * 10.5),
			rgb(palette.accent)
		)
		rim.CanCollide = false
	end
	folder.Parent = parent
end

return Landscape
