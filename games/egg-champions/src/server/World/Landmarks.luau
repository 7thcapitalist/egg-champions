--!strict
-- Original constructed landmarks. Geometry is presentation, all routes stay clear.
local CollectionService = game:GetService("CollectionService")
local Landmarks = {}

function Landmarks.build(theme: string, origin: Vector3, parent: Folder)
	local folder = Instance.new("Folder")
	folder.Name = "Landmarks"
	local cream = Color3.fromRGB(248, 237, 204)
	local wood = Color3.fromRGB(119, 76, 51)
	local teal = Color3.fromRGB(47, 147, 155)
	local function part(
		name: string,
		size: Vector3,
		cf: CFrame,
		color: Color3,
		material: Enum.Material?
	): Part
		local p = Instance.new("Part")
		p.Name, p.Size, p.CFrame = name, size, CFrame.new(origin) * cf
		p.Color, p.Material = color, material or Enum.Material.SmoothPlastic
		p.Anchored, p.CanTouch = true, false
		p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
		p.Parent = folder
		return p
	end
	local function ball(name: string, size: Vector3, pos: Vector3, color: Color3): Part
		local p = part(name, size, CFrame.new(pos), color)
		p.Shape = Enum.PartType.Ball
		return p
	end
	local function cylinder(
		name: string,
		radius: number,
		height: number,
		pos: Vector3,
		color: Color3
	): Part
		local p = part(
			name,
			Vector3.new(height, radius * 2, radius * 2),
			CFrame.new(pos) * CFrame.Angles(0, 0, math.pi / 2),
			color
		)
		p.Shape = Enum.PartType.Cylinder
		return p
	end
	local function beam(name: string, a: Vector3, b: Vector3, width: number, color: Color3)
		part(
			name,
			Vector3.new(width, width, (b - a).Magnitude),
			CFrame.lookAt((a + b) / 2, b),
			color
		)
	end
	local function emitter(p: BasePart, color: Color3, texture: string, rate: number, speed: number)
		local fx = Instance.new("ParticleEmitter")
		fx.Name = "AmbientParticles"
		fx.Texture = texture
		fx.Color = ColorSequence.new(color)
		fx.Rate, fx.Lifetime, fx.Speed =
			rate, NumberRange.new(1.5, 3), NumberRange.new(speed * 0.5, speed)
		fx.SpreadAngle = Vector2.new(40, 40)
		fx.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.15),
			NumberSequenceKeypoint.new(0.5, 0.7),
			NumberSequenceKeypoint.new(1, 0),
		})
		fx.Transparency = NumberSequence.new(0.3, 1)
		fx.LightEmission = 0.5
		fx.Parent = p
		CollectionService:AddTag(fx, "WorldAmbient")
	end
	local function rotor(name: string, center: Vector3, color: Color3, radius: number)
		local model = Instance.new("Model")
		model.Name = name
		model.WorldPivot = CFrame.new(origin + center)
		for i = 0, 3 do
			local angle = i * math.pi / 2
			local p = part(
				"Sail",
				Vector3.new(2.6, radius, 0.5),
				CFrame.new(center) * CFrame.Angles(0, 0, angle) * CFrame.new(0, radius / 2, 0),
				color
			)
			p.CanCollide = false
			p.Parent = model
		end
		model.Parent = folder
		model:SetAttribute("SpinAxis", "Z")
		CollectionService:AddTag(model, "WorldRotor")
	end
	if theme == "green_meadow" then
		-- Ancient tree sanctuary, with a broad asymmetrical crown and crystal fruit.
		local center = Vector3.new(-64, 0, -58)
		cylinder("RootTerrace", 24, 1, center + Vector3.new(0, 0.5, 0), Color3.fromRGB(74, 147, 75))
		cylinder("AncientTrunk", 5.5, 29, center + Vector3.new(0, 15, 0), wood)
		for i = 0, 5 do
			local a = i * math.pi / 3
			local reach = Vector3.new(math.cos(a) * 13, 0, math.sin(a) * 13)
			beam("TreeRoot", center + Vector3.new(0, 5, 0), center + reach, 3.3, wood)
			beam(
				"Branch",
				center + Vector3.new(0, 21, 0),
				center + reach + Vector3.new(0, 30 + i % 2 * 5, 0),
				3,
				wood
			)
			ball(
				"Crown",
				Vector3.new(24, 15, 22),
				center + reach + Vector3.new(0, 32 + i % 2 * 5, 0),
				Color3.fromRGB(63 + i * 7, 155 + i * 7, 88)
			)
			local fruit = ball(
				"SpiritFruit",
				Vector3.one * 1.2,
				center + reach + Vector3.new(0, 24, 0),
				Color3.fromRGB(160, 255, 202)
			)
			fruit.Material, fruit.CanCollide = Enum.Material.Neon, false
			emitter(fruit, fruit.Color, "rbxasset://textures/particles/sparkles_main.dds", 1, 1)
		end
		-- Walkable picnic boardwalk and windmill behind the arrival camera.
		part("MillHouse", Vector3.new(16, 17, 13), CFrame.new(-58, 8.5, 48), cream)
		for side = -1, 1, 2 do
			part(
				"MillRoof",
				Vector3.new(12, 1.5, 17),
				CFrame.new(-58 + side * 4.2, 19, 48) * CFrame.Angles(0, 0, side * math.rad(33)),
				teal
			)
		end
		part("MillDoor", Vector3.new(4, 7, 0.3), CFrame.new(-58, 3.5, 54.7), wood)
		rotor("WindmillSails", Vector3.new(-58, 16, 55.5), cream, 11)
		for i = 0, 15 do
			part(
				"GardenWalk",
				Vector3.new(9, 0.3, 3),
				CFrame.new(-58, 0.18, i * 3),
				wood:Lerp(cream, 0.25)
			)
		end
		for i = 0, 4 do
			local x = -38 + i * 9
			ball(
				"GardenHedge",
				Vector3.new(7, 3, 5),
				Vector3.new(x, 1, 56),
				Color3.fromRGB(70, 166, 92)
			)
		end
	elseif theme == "coral_coast" then
		-- Landmark lighthouse, open ocean horizon and harbor.
		local center = Vector3.new(-66, 0, -55)
		cylinder("LighthouseIsland", 22, 2, center + Vector3.new(0, 1, 0), cream)
		for i = 0, 5 do
			cylinder(
				"LighthouseTower",
				7 - i * 0.45,
				5,
				center + Vector3.new(0, 4 + i * 5, 0),
				if i % 2 == 0 then cream else Color3.fromRGB(228, 102, 92)
			)
		end
		cylinder("LanternDeck", 8, 1.5, center + Vector3.new(0, 33, 0), teal)
		for i = 0, 7 do
			local a = i * math.pi / 4
			part(
				"LanternPost",
				Vector3.new(0.6, 7, 0.6),
				CFrame.new(center + Vector3.new(math.cos(a) * 6, 37, math.sin(a) * 6)),
				cream
			)
		end
		local lamp = ball(
			"Lantern",
			Vector3.one * 5,
			center + Vector3.new(0, 37, 0),
			Color3.fromRGB(255, 226, 131)
		)
		lamp.Material = Enum.Material.Neon
		cylinder("LanternRoof", 8, 2, center + Vector3.new(0, 41, 0), teal)
		local light = Instance.new("PointLight")
		light.Color, light.Range, light.Brightness = lamp.Color, 28, 1.4
		light.Parent = lamp
		for i = 0, 34 do
			part(
				"HarborPlank",
				Vector3.new(16, 0.35, 3.5),
				CFrame.new(-58, 0.25, 12 + i * 3.5),
				wood:Lerp(cream, (i % 3) * 0.09)
			)
			if i % 4 == 0 then
				for side = -1, 1, 2 do
					cylinder(
						"MooringPost",
						0.7,
						5,
						Vector3.new(-58 + side * 8, 1, 12 + i * 3.5),
						wood
					)
				end
			end
		end
		part(
			"BoatHull",
			Vector3.new(8, 2, 16),
			CFrame.new(-76, -6, 105) * CFrame.Angles(0, 0.2, 0),
			teal
		)
		beam("Mast", Vector3.new(-76, -5, 105), Vector3.new(-76, 12, 105), 0.6, wood)
		local sail = part("Sail", Vector3.new(0.2, 12, 10), CFrame.new(-76, 5, 108), cream)
		sail.CanCollide = false
		for i = 0, 3 do
			local wave = part(
				"Foam",
				Vector3.new(44, 0.1, 0.8),
				CFrame.new(-70, -6.9, 126 + i * 7),
				Color3.fromRGB(199, 254, 249)
			)
			wave.CanCollide = false
			CollectionService:AddTag(wave, "WorldWave")
		end
	else
		-- Broken caldera skyline behind the gym; lava falls leave the route open.
		local center = Vector3.new(-42, 0, -103)
		for i = 0, 11 do
			local a = i * math.pi / 6
			local h = 26 + (i % 3) * 8
			local position = center + Vector3.new(math.cos(a) * 24, h / 2, math.sin(a) * 20)
			local direction = Vector3.new(position.X - center.X, 0, position.Z - center.Z).Unit
			local slope = Instance.new("WedgePart")
			slope.Name, slope.Size = "CalderaSpire", Vector3.new(18, h, 38)
			slope.CFrame = CFrame.new(origin) * CFrame.lookAt(position, position + direction)
			slope.Color, slope.Material =
				Color3.fromRGB(51 + i % 3 * 7, 43, 65), Enum.Material.SmoothPlastic
			slope.Anchored, slope.CanTouch = true, false
			slope.Parent = folder
		end
		local lava = cylinder(
			"CraterHeart",
			19,
			1,
			center + Vector3.new(0, 27, 0),
			Color3.fromRGB(255, 117, 45)
		)
		lava.Material = Enum.Material.Neon
		emitter(
			lava,
			Color3.fromRGB(255, 185, 81),
			"rbxasset://textures/particles/fire_main.dds",
			5,
			8
		)
		for i = 0, 2 do
			local from = Vector3.new(-59 + i * 8, 27, -90)
			local to = Vector3.new(-67 + i * 8, 1, -67)
			local fall = part(
				"LavaFall",
				Vector3.new(2.2, 0.5, (to - from).Magnitude),
				CFrame.lookAt((from + to) / 2, to),
				Color3.fromRGB(255, 141, 48),
				Enum.Material.Neon
			)
			fall.CanCollide = false
		end
		-- Monumental forge pavilion with a bright central energy crystal.
		part(
			"ForgeFloor",
			Vector3.new(34, 0.4, 28),
			CFrame.new(-59, 0.2, 47),
			Color3.fromRGB(69, 64, 83)
		)
		for x = -1, 1, 2 do
			for z = -1, 1, 2 do
				part(
					"ForgeColumn",
					Vector3.new(4, 18, 4),
					CFrame.new(-59 + x * 14, 9, 47 + z * 10),
					Color3.fromRGB(51, 47, 67)
				)
			end
		end
		part(
			"ForgeLintel",
			Vector3.new(36, 4, 26),
			CFrame.new(-59, 20, 47),
			Color3.fromRGB(74, 65, 90)
		)
		cylinder("AnvilBase", 5, 4, Vector3.new(-59, 2, 47), wood)
		local crystal = part(
			"ForgeCrystal",
			Vector3.new(4, 8, 4),
			CFrame.new(-59, 9, 47) * CFrame.Angles(0, math.pi / 4, 0.25),
			Color3.fromRGB(255, 177, 70),
			Enum.Material.Neon
		)
		crystal.CanCollide = false
		emitter(crystal, crystal.Color, "rbxasset://textures/particles/sparkles_main.dds", 3, 3)
		for i = 0, 14 do
			part(
				"BasaltWalk",
				Vector3.new(10, 0.25, 3),
				CFrame.new(-59, 0.15, i * 3),
				Color3.fromRGB(130, 113, 140)
			)
		end
	end
	folder.Parent = parent
end
return Landmarks
