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
	local island = block(
		"Island",
		Vector3.new(12, size + 30, size + 30),
		CFrame.new(o.x, -7, o.z) * CFrame.Angles(0, 0, math.pi / 2),
		rock
	)
	island.Shape = Enum.PartType.Cylinder
	local surface = block(
		"Ground",
		Vector3.new(1, size + 26, size + 26),
		CFrame.new(o.x, -0.5, o.z) * CFrame.Angles(0, 0, math.pi / 2),
		ground
	)
	surface.Shape = Enum.PartType.Cylinder
	local water = block(
		"Sea",
		Vector3.new(size + 110, 1, size + 110),
		CFrame.new(o.x, -8, o.z),
		rgb(palette.water)
	)
	water.Material = Enum.Material.Glass
	water.Transparency = 0.18
	water.CanCollide = false
	-- Irregular perimeter rocks frame the horizon without a repeated fortress wall.
	-- They sit beyond every interaction route and the landmark footprints.
	for i = 0, 17 do
		local angle = i * math.pi / 9
		local rear = math.sin(angle) < -0.35
		local h = if rear then 11 + (i * 7 % 4) * 4 else 3 + i % 3
		if scenery.theme == "coral_coast" then
			h *= 0.55
		end
		local radius = 116 + (i % 3) * 2
		local p = block(
			"ShoreRock",
			Vector3.new(13 + i % 4 * 2, h, 14),
			CFrame.new(o.x + math.cos(angle) * radius, h / 2 - 4, o.z + math.sin(angle) * radius)
				* CFrame.Angles(0.08 * (i % 2), angle + 0.3, -0.12),
			rock:Lerp(ground, 0.12 + i % 3 * 0.06)
		)
		p.Shape = Enum.PartType.Ball
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
