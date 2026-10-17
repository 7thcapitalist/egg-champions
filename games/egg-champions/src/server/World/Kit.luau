--!strict
--[[
	Kit: the prop builders the world builder places.

	Each builder returns a Model made from plain parts, anchored, with a
	PrimaryPart, placed at the CFrame it is given (the CFrame is the prop's
	base, resting on the ground). No meshes, no uploaded assets.

	Builders that a player interacts with (egg stand, portal) carry a part named
	"Trigger" that the builder wires up. Every Model gets a "Prop" attribute
	naming its builder, so what was built can be counted.

	Scenery props (trees, palms, rocks, bushes, flowers, fences) are built
	from Ball, Cylinder and Wedge parts. The constructed ground is built by server/World/Landscape.

	Sizes here are prop geometry, not game numbers.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ThemeColors = require(Shared:WaitForChild("ui"):WaitForChild("ThemeColors"))
local WorldNames = require(Shared:WaitForChild("world"):WaitForChild("Names"))
local Scenery = require(Shared:WaitForChild("world"):WaitForChild("Scenery"))

local Kit = {}

export type Palette = {
	ground: Color3,
	groundMaterial: Enum.Material,
	cliff: Color3,
	water: Color3,
	trunk: Color3,
	leaf: Color3,
	rock: Color3,
	accent: Color3,
	trim: Color3,
	glow: Color3,
	text: Color3,
	-- Foliage greens and flower colors, picked per prop by its variant.
	greens: { Color3 },
	flowers: { Color3 },
}

local function part(
	model: Model,
	name: string,
	size: Vector3,
	cframe: CFrame,
	color: Color3,
	material: Enum.Material?
): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = model
	return p
end

local function newModel(prop: string, name: string?): Model
	local model = Instance.new("Model")
	model.Name = name or prop
	model:SetAttribute("Prop", prop)
	return model
end

-- The font of every world sign: a heavy face whose letters keep together at
-- any size, so a word never reads as split ("E gg").
local SIGN_FONT = Enum.Font.FredokaOne

-- A floating text label above a part, sized in studs (so it scales with
-- distance like the part does). `height` is how far the label's center sits
-- above the part's center.
local function label(adornee: BasePart, text: string, size: Vector2, height: number, color: Color3)
	local gui = Instance.new("BillboardGui")
	gui.Name = "Label"
	gui.Size = UDim2.fromScale(size.X, size.Y)
	gui.StudsOffsetWorldSpace = Vector3.new(0, height, 0)
	gui.AlwaysOnTop = false
	gui.MaxDistance = 120
	gui.LightInfluence = 0
	gui.Adornee = adornee
	local textLabel = Instance.new("TextLabel")
	textLabel.Size = UDim2.fromScale(1, 1)
	textLabel.BackgroundTransparency = 1
	textLabel.Text = text
	textLabel.TextColor3 = color
	textLabel.TextStrokeTransparency = 0.3
	textLabel.TextScaled = true
	textLabel.Font = SIGN_FONT
	textLabel.Parent = gui
	gui.Parent = adornee
end

-- Text printed on both faces of a flat board, filling it with a small margin,
-- so it always fits the board it is on. Lines break only where the text says
-- (at its newlines), never inside a word.
local BOARD_MARGIN = 0.08
local function boardText(board: BasePart, text: string, color: Color3)
	board.Color = ThemeColors.panel
	board.Material = Enum.Material.SmoothPlastic
	for _, face in { Enum.NormalId.Front, Enum.NormalId.Back } do
		local gui = Instance.new("SurfaceGui")
		gui.Name = "Label" .. face.Name
		gui.Face = face
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 50
		gui.LightInfluence = 0
		gui.Adornee = board
		local textLabel = Instance.new("TextLabel")
		textLabel.AnchorPoint = Vector2.new(0.5, 0.5)
		textLabel.Position = UDim2.fromScale(0.5, 0.5)
		textLabel.Size = UDim2.fromScale(1 - 2 * BOARD_MARGIN, 1 - 2 * BOARD_MARGIN)
		textLabel.BackgroundTransparency = 1
		textLabel.Text = text
		textLabel.TextColor3 = color
		textLabel.TextStrokeTransparency = 0.3
		textLabel.TextScaled = true
		textLabel.TextWrapped = true
		textLabel.Font = SIGN_FONT
		textLabel.Parent = gui
		gui.Parent = board
	end
end

-- Egg stand signs: a dark plate sized in studs (Scenery.STAND_LABEL), just
-- above the egg, so it shrinks with distance but stays readable from the
-- spawn point, and hidden past SIGN_MAX_DISTANCE.
local STAND_LABEL = Scenery.STAND_LABEL
local SIGN_SIZE = UDim2.fromScale(STAND_LABEL.width, STAND_LABEL.height)
local SIGN_MAX_DISTANCE = 90
local SIGN_PLATE_TRANSPARENCY = 0.2
local PRICE_GOLD = ThemeColors.gold
local EGG_HOVER = STAND_LABEL.hover

Kit.EGG_SPIN_TAG = WorldNames.SPINNING_EGG_TAG

local function line(
	gui: BillboardGui,
	text: string,
	top: number,
	height: number,
	color: Color3,
	name: string
)
	local textLabel = Instance.new("TextLabel")
	textLabel.Name = name
	textLabel.Size = UDim2.fromScale(0.92, height)
	textLabel.Position = UDim2.fromScale(0.04, top)
	textLabel.BackgroundTransparency = 1
	textLabel.Text = text
	textLabel.TextColor3 = color
	textLabel.TextStrokeTransparency = 0.3
	textLabel.TextScaled = true
	textLabel.TextWrapped = true
	textLabel.Font = SIGN_FONT
	textLabel.Parent = gui
end

-- An egg stand's sign: the name on one line, the price below it in gold.
local function standSign(adornee: BasePart, name: string, price: string, color: Color3)
	local gui = Instance.new("BillboardGui")
	gui.Name = "Label"
	gui.Size = SIGN_SIZE
	gui.AlwaysOnTop = false
	gui.MaxDistance = SIGN_MAX_DISTANCE
	gui.LightInfluence = 0
	gui.Adornee = adornee
	local plate = Instance.new("Frame")
	plate.Name = "Plate"
	plate.Size = UDim2.fromScale(1, 1)
	plate.BackgroundColor3 = ThemeColors.panel
	plate.BackgroundTransparency = SIGN_PLATE_TRANSPARENCY
	plate.BorderSizePixel = 0
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.2, 0)
	corner.Parent = plate
	local stroke = Instance.new("UIStroke")
	stroke.Color = ThemeColors.border
	stroke.Thickness = 2
	stroke.Parent = plate
	plate.Parent = gui
	line(gui, name, 0.05, 0.5, color, "Name")
	line(gui, price, 0.56, 0.39, PRICE_GOLD, "Price")
	gui.Parent = adornee
end

-- 6. Egg stand: a plinth, a blocky placeholder egg on top (in a Model named
-- "Egg" that Kit.setEgg swaps for the real one), a sign, and a Trigger pad.
-- eggHeight is the egg model's configured height in studs (nil for the
-- placeholder), so the sign clears the real egg.
function Kit.eggStand(
	base: CFrame,
	palette: Palette,
	name: string,
	price: string,
	eggHeight: number?
): Model
	local model = newModel("EggStand")
	part(model, "BaseTrim", Vector3.new(9, 0.5, 9), base * CFrame.new(0, 0.25, 0), palette.accent)
	local plinth = part(
		model,
		"Plinth",
		Vector3.new(8, STAND_LABEL.plinth, 8),
		base * CFrame.new(0, STAND_LABEL.plinth / 2, 0),
		palette.trim,
		Enum.Material.SmoothPlastic
	)
	for _, side in { -1, 1 } do
		part(
			model,
			"StandTrim",
			Vector3.new(0.3, 2, 8.2),
			base * CFrame.new(side * 4.05, 1.5, 0),
			palette.accent
		)
		part(
			model,
			"StandTrim",
			Vector3.new(8.2, 2, 0.3),
			base * CFrame.new(0, 1.5, side * 4.05),
			palette.accent
		)
	end
	local egg = Instance.new("Model")
	egg.Name = "Egg"
	local low =
		part(egg, "EggLow", Vector3.new(4, 3, 4), base * CFrame.new(0, 4.5, 0), palette.accent)
	part(egg, "EggHigh", Vector3.new(3, 2, 3), base * CFrame.new(0, 7, 0), palette.accent)
	egg.PrimaryPart = low
	egg:AddTag(Kit.EGG_SPIN_TAG)
	egg.Parent = model
	local trigger = part(
		model,
		"Trigger",
		Vector3.new(10, 1, 6),
		base * CFrame.new(0, 0.5, -7),
		palette.glow,
		Enum.Material.Neon
	)
	trigger.Material = Enum.Material.SmoothPlastic
	trigger.Transparency = 0.55
	trigger.CanCollide = false
	-- The sign sits just above the egg: plinth top, egg, then the sign.
	local signPart = part(
		model,
		"SignAnchor",
		Vector3.new(1, 1, 1),
		base * CFrame.new(0, Scenery.standLabelY(eggHeight), 0),
		palette.trim
	)
	signPart.Transparency = 1
	signPart.CanCollide = false
	signPart.CanQuery = false
	signPart.CanTouch = false
	standSign(signPart, name, price, palette.text)
	model.PrimaryPart = plinth
	return model
end

-- Replaces an egg stand's egg with a clone of `template` (a Model from
-- ReplicatedStorage.PetModels, already scaled to its configured height),
-- resting just above the plinth and tagged to spin on clients.
function Kit.setEgg(stand: Model, template: Model)
	local plinth = stand.PrimaryPart
	if plinth == nil then
		return
	end
	local egg = template:Clone()
	egg.Name = "Egg"
	for _, item in egg:GetDescendants() do
		if item:IsA("BasePart") then
			item.Anchored = true
			item.CanCollide = false
			item.CanQuery = false
			item.CanTouch = false
		end
	end
	local _, size = egg:GetBoundingBox()
	local top = plinth.CFrame * CFrame.new(0, plinth.Size.Y / 2, 0)
	egg:PivotTo(top * CFrame.new(0, size.Y / 2 + EGG_HOVER, 0))
	egg:AddTag(Kit.EGG_SPIN_TAG)
	local old = stand:FindFirstChild("Egg")
	if old ~= nil then
		old:Destroy()
	end
	egg.Parent = stand
end

-- Turns a Cylinder part's length (its X axis) to point up.
local UPRIGHT = CFrame.Angles(0, 0, math.pi / 2)

local function ball(
	model: Instance,
	name: string,
	diameter: number,
	cframe: CFrame,
	color: Color3,
	material: Enum.Material?
): Part
	local p = Instance.new("Part")
	p.Shape = Enum.PartType.Ball
	p.Name = name
	p.Anchored = true
	p.Size = Vector3.new(diameter, diameter, diameter)
	p.CFrame = cframe
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.Parent = model
	return p
end

-- A cylinder whose length runs along the CFrame's X axis.
local function cylinder(
	model: Instance,
	name: string,
	length: number,
	diameter: number,
	cframe: CFrame,
	color: Color3,
	material: Enum.Material?
): Part
	local p = Instance.new("Part")
	p.Shape = Enum.PartType.Cylinder
	p.Name = name
	p.Anchored = true
	p.Size = Vector3.new(length, diameter, diameter)
	p.CFrame = cframe
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.Parent = model
	return p
end

local function wedge(
	model: Instance,
	name: string,
	size: Vector3,
	cframe: CFrame,
	color: Color3,
	material: Enum.Material
): WedgePart
	local p = Instance.new("WedgePart")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = material
	p.Parent = model
	return p
end

-- Picks one color of a list by a prop's variant number.
local function pick(colors: { Color3 }, variant: number): Color3
	return colors[(variant - 1) % #colors + 1]
end

-- Scenery props. Each takes its base CFrame (on the ground, turned), the
-- palette, a scale and a variant number that picks its colors, and has the
-- part count Scenery.PROPS lists for it.

-- Tree: a round trunk and layered rounded foliage in two or three greens.
function Kit.tree(base: CFrame, palette: Palette, scale: number, variant: number): Model
	local model = newModel("Tree")
	local height = 7 * scale
	local trunk = cylinder(
		model,
		"Trunk",
		height,
		1.6 * scale,
		base * CFrame.new(0, height / 2, 0) * UPRIGHT,
		palette.trunk,
		Enum.Material.SmoothPlastic
	)
	local g = palette.greens
	part(
		model,
		"Crown",
		Vector3.new(7, 4, 7) * scale,
		base * CFrame.new(0, height + 1.5 * scale, 0) * CFrame.Angles(0, 0.2, 0),
		pick(g, variant)
	)
	part(
		model,
		"CrownLeft",
		Vector3.new(5.5, 3, 5.5) * scale,
		base * CFrame.new(1.9 * scale, height + 0.2 * scale, 0.8 * scale),
		pick(g, variant + 1)
	)
	part(
		model,
		"CrownRight",
		Vector3.new(5, 3.5, 5) * scale,
		base * CFrame.new(-1.7 * scale, height + 0.6 * scale, -1.2 * scale),
		pick(g, variant + 2)
	)
	part(
		model,
		"CrownTop",
		Vector3.new(4, 3, 4) * scale,
		base * CFrame.new(0.3 * scale, height + 4.4 * scale, 0.2 * scale),
		pick(g, variant + 1)
	)
	model.PrimaryPart = trunk
	return model
end

-- Palm: a leaning trunk in three pieces, a coconut cluster and four fronds.
function Kit.palm(base: CFrame, palette: Palette, scale: number, variant: number): Model
	local model = newModel("Palm")
	local piece = 3.4 * scale
	local at = base
	local first: Part? = nil
	for i = 1, 3 do
		at = at * CFrame.Angles(0, 0, 0.12)
		local p = cylinder(
			model,
			"Trunk" .. i,
			piece,
			(1.5 - 0.15 * i) * scale,
			at * CFrame.new(0, piece / 2, 0) * UPRIGHT,
			palette.trunk,
			Enum.Material.SmoothPlastic
		)
		first = first or p
		at = at * CFrame.new(0, piece * 0.95, 0)
	end
	ball(model, "Coconuts", 1.6 * scale, at, Color3.fromRGB(110, 80, 50))
	for i = 1, 4 do
		local frond = part(
			model,
			"Frond" .. i,
			Vector3.new(1.8, 0.3, 5.5) * scale,
			at
				* CFrame.Angles(0, i * math.pi / 2 + variant * 0.3, 0)
				* CFrame.Angles(-0.35, 0, 0)
				* CFrame.new(0, 0, -2.6 * scale),
			pick(palette.greens, variant + i)
		)
		frond.CanCollide = false
	end
	model.PrimaryPart = first
	return model
end

-- Dead tree: a bare trunk with three crooked branches.
function Kit.deadTree(base: CFrame, palette: Palette, scale: number, variant: number): Model
	local model = newModel("DeadTree")
	local height = 6 * scale
	local trunk = cylinder(
		model,
		"Trunk",
		height,
		1.2 * scale,
		base * CFrame.new(0, height / 2, 0) * UPRIGHT,
		palette.trunk,
		Enum.Material.SmoothPlastic
	)
	for i = 1, 3 do
		local length = (2.4 + (i + variant) % 3 * 0.5) * scale
		cylinder(
			model,
			"Branch" .. i,
			length,
			0.5 * scale,
			base
				* CFrame.new(0, height * (0.55 + 0.15 * i), 0)
				* CFrame.Angles(0, i * 2.1 + variant, 0)
				* CFrame.Angles(0, 0, 0.7)
				* CFrame.new(length / 2, 0, 0),
			palette.trunk,
			Enum.Material.SmoothPlastic
		)
	end
	model.PrimaryPart = trunk
	return model
end

-- Rock: a few balls and wedges, turned against each other.
function Kit.rock(base: CFrame, palette: Palette, scale: number, _variant: number): Model
	local model = newModel("Rock")
	local material = Enum.Material.SmoothPlastic
	local big = ball(
		model,
		"Big",
		3.6 * scale,
		base * CFrame.new(0, 1.1 * scale, 0),
		palette.rock,
		material
	)
	ball(
		model,
		"Small",
		2.6 * scale,
		base * CFrame.new(1.6 * scale, 0.7 * scale, 0.8 * scale),
		palette.rock,
		material
	)
	wedge(
		model,
		"WedgeA",
		Vector3.new(3, 2.4, 3.2) * scale,
		base * CFrame.new(-1.2 * scale, 1.1 * scale, -0.4 * scale) * CFrame.Angles(0, 0.8, 0),
		palette.rock,
		material
	)
	wedge(
		model,
		"WedgeB",
		Vector3.new(2.4, 1.8, 2.6) * scale,
		base * CFrame.new(0.4 * scale, 1.2 * scale, -1.5 * scale) * CFrame.Angles(0.1, 2.4, 0),
		palette.rock,
		material
	)
	model.PrimaryPart = big
	return model
end

-- Boulder: one big round stone, a wedge and a smaller stone.
function Kit.boulder(base: CFrame, palette: Palette, scale: number, _variant: number): Model
	local model = newModel("Boulder")
	local material = Enum.Material.SmoothPlastic
	local big =
		ball(model, "Big", 5 * scale, base * CFrame.new(0, 1.8 * scale, 0), palette.rock, material)
	wedge(
		model,
		"Wedge",
		Vector3.new(4, 3, 4) * scale,
		base * CFrame.new(1.6 * scale, 1.4 * scale, 0) * CFrame.Angles(0, 1.2, 0),
		palette.rock,
		material
	)
	ball(
		model,
		"Small",
		3 * scale,
		base * CFrame.new(-2 * scale, 1 * scale, 1 * scale),
		palette.rock,
		material
	)
	model.PrimaryPart = big
	return model
end

-- Bush: three rounded clumps.
function Kit.bush(base: CFrame, palette: Palette, scale: number, variant: number): Model
	local model = newModel("Bush")
	local g = palette.greens
	local main =
		ball(model, "Main", 3.4 * scale, base * CFrame.new(0, 1.2 * scale, 0), pick(g, variant))
	ball(
		model,
		"Left",
		2.8 * scale,
		base * CFrame.new(1.4 * scale, 0.9 * scale, 0.4 * scale),
		pick(g, variant + 1)
	)
	ball(
		model,
		"Right",
		2.4 * scale,
		base * CFrame.new(-1.2 * scale, 0.8 * scale, -0.6 * scale),
		pick(g, variant + 2)
	)
	model.PrimaryPart = main
	return model
end

-- Flower: a stem and a bloom.
function Kit.flower(base: CFrame, palette: Palette, scale: number, variant: number): Model
	local model = newModel("Flower")
	local stem = cylinder(
		model,
		"Stem",
		1.6 * scale,
		0.25 * scale,
		base * CFrame.new(0, 0.8 * scale, 0) * UPRIGHT,
		pick(palette.greens, variant)
	)
	stem.CanCollide = false
	local bloom = ball(
		model,
		"Bloom",
		0.9 * scale,
		base * CFrame.new(0, 1.7 * scale, 0),
		pick(palette.flowers, variant)
	)
	bloom.CanCollide = false
	model.PrimaryPart = stem
	return model
end

-- Fence piece from a to b on the ground: a post at a and two rails.
function Kit.fence(a: Vector3, b: Vector3, palette: Palette): Model
	local model = newModel("Fence")
	local post = part(
		model,
		"Post",
		Vector3.new(0.8, 3, 0.8),
		CFrame.new(a + Vector3.new(0, 1.5, 0)),
		palette.trunk,
		Enum.Material.SmoothPlastic
	)
	local length = (b - a).Magnitude
	for i, height in { 1.2, 2.3 } do
		local from = a + Vector3.new(0, height, 0)
		local to = b + Vector3.new(0, height, 0)
		part(
			model,
			"Rail" .. i,
			Vector3.new(0.3, 0.4, length),
			CFrame.lookAt((from + to) / 2, to),
			palette.trunk,
			Enum.Material.SmoothPlastic
		)
	end
	model.PrimaryPart = post
	return model
end

-- A soft glow over a lava stream: an invisible part holding a PointLight.
function Kit.glow(position: Vector3, color: Color3): Model
	local model = newModel("Glow")
	local holder = part(model, "Light", Vector3.new(1, 1, 1), CFrame.new(position), color)
	holder.Transparency = 1
	holder.CanCollide = false
	holder.CanQuery = false
	holder.CanTouch = false
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = 16
	light.Brightness = 1.4
	light.Parent = holder
	model.PrimaryPart = holder
	return model
end

-- The gym arena's sizes, in studs. Its footprint, a circle ARENA_STEP_DIAMETER
-- across, fits inside Layout.GYM_SIZE.
local ARENA_STEP_DIAMETER = 28
local ARENA_FLOOR_DIAMETER = 24
local ARENA_STEP = 1
local ARENA_PILLAR_RADIUS = 10.5
local ARENA_PILLAR_HEIGHT = 11
-- The gate and its sign stand toward the arrival point (local -z).
local ARENA_GATE_Z = -Scenery.GYM_SIGN.forward
local ARENA_PILLAR_ANGLES = { 55, 105, 155, 205, 255, 305 }

-- The leader's type icon: a round badge in the type color with its name.
local function typeBadge(board: BasePart, typeColor: Color3, typeName: string, text: Color3)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "TypeIcon"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 50
	gui.LightInfluence = 0
	gui.Adornee = board
	local disc = Instance.new("Frame")
	disc.AnchorPoint = Vector2.new(0.5, 0.5)
	disc.Position = UDim2.fromScale(0.5, 0.5)
	disc.Size = UDim2.fromScale(0.9, 0.9)
	disc.BackgroundColor3 = typeColor
	disc.BorderSizePixel = 0
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = disc
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.new(1, 1, 1)
	stroke.Thickness = 10
	stroke.Parent = disc
	local name = Instance.new("TextLabel")
	name.AnchorPoint = Vector2.new(0.5, 0.5)
	name.Position = UDim2.fromScale(0.5, 0.5)
	name.Size = UDim2.fromScale(0.75, 0.4)
	name.BackgroundTransparency = 1
	name.Text = string.upper(typeName)
	name.TextColor3 = text
	name.TextStrokeTransparency = 0.2
	name.TextScaled = true
	name.Font = Enum.Font.FredokaOne
	name.Parent = disc
	disc.Parent = gui
	gui.Parent = board
end

-- 7. Gym arena: a raised round platform with steps, a ring of pillars open to
-- the front, a banner in the leader's type color with the type icon, and an
-- entrance gate whose board carries the gym's sign. The top floor is the
-- PrimaryPart: the builder tags it, and stepping on it opens the battle.
function Kit.gymBuilding(
	base: CFrame,
	palette: Palette,
	text: string,
	typeColor: Color3,
	typeName: string
): Model
	local model = newModel("Gym")
	cylinder(
		model,
		"StepLow",
		ARENA_STEP,
		ARENA_STEP_DIAMETER,
		base * CFrame.new(0, ARENA_STEP / 2, 0) * UPRIGHT,
		palette.trim,
		Enum.Material.SmoothPlastic
	)
	cylinder(
		model,
		"StepHigh",
		ARENA_STEP,
		ARENA_STEP_DIAMETER - 2,
		base * CFrame.new(0, ARENA_STEP * 1.5, 0) * UPRIGHT,
		palette.trim,
		Enum.Material.SmoothPlastic
	)
	-- A rim in the type color, just under the floor's edge.
	cylinder(
		model,
		"Rim",
		0.8,
		ARENA_FLOOR_DIAMETER + 1,
		base * CFrame.new(0, ARENA_STEP * 2.5, 0) * UPRIGHT,
		typeColor
	)
	local floorTop = ARENA_STEP * 3
	local floor = cylinder(
		model,
		"Floor",
		ARENA_STEP,
		ARENA_FLOOR_DIAMETER,
		base * CFrame.new(0, floorTop - ARENA_STEP / 2, 0) * UPRIGHT,
		palette.trim,
		Enum.Material.SmoothPlastic
	)
	for i, degrees in ARENA_PILLAR_ANGLES do
		local angle = math.rad(degrees)
		local x = ARENA_PILLAR_RADIUS * math.sin(angle)
		local z = -ARENA_PILLAR_RADIUS * math.cos(angle)
		cylinder(
			model,
			"Pillar" .. i,
			ARENA_PILLAR_HEIGHT,
			1.8,
			base * CFrame.new(x, floorTop + ARENA_PILLAR_HEIGHT / 2, z) * UPRIGHT,
			palette.trim,
			Enum.Material.SmoothPlastic
		)
		part(
			model,
			"Cap" .. i,
			Vector3.new(2.6, 0.8, 2.6),
			base * CFrame.new(x, floorTop + ARENA_PILLAR_HEIGHT + 0.4, z),
			palette.accent
		)
	end
	-- The banner hangs at the back, between the two back pillars.
	local backZ = ARENA_PILLAR_RADIUS - 0.6
	cylinder(
		model,
		"BannerRod",
		8,
		0.5,
		base * CFrame.new(0, floorTop + ARENA_PILLAR_HEIGHT - 0.4, backZ),
		palette.trim,
		Enum.Material.Metal
	)
	part(
		model,
		"Banner",
		Vector3.new(6, 9, 0.3),
		base * CFrame.new(0, floorTop + ARENA_PILLAR_HEIGHT - 5, backZ),
		typeColor,
		Enum.Material.SmoothPlastic
	)
	local badge = part(
		model,
		"TypeIconBoard",
		Vector3.new(4.4, 4.4, 0.2),
		base * CFrame.new(0, floorTop + ARENA_PILLAR_HEIGHT - 4.5, backZ - 0.3),
		typeColor
	)
	badge.Transparency = 1
	badge.CanCollide = false
	typeBadge(badge, typeColor, typeName, palette.text)
	-- The entrance gate, on the bottom step, facing the arrival point.
	for side = -1, 1, 2 do
		part(
			model,
			if side < 0 then "GateLeft" else "GateRight",
			Vector3.new(1.4, 10, 1.4),
			base * CFrame.new(side * 7, ARENA_STEP + 5, ARENA_GATE_Z),
			palette.accent
		)
	end
	local board = part(
		model,
		"SignBoard",
		Vector3.new(Scenery.GYM_SIGN.width, Scenery.GYM_SIGN.height, 0.6),
		base * CFrame.new(0, Scenery.GYM_SIGN.y, ARENA_GATE_Z),
		palette.accent,
		Enum.Material.SmoothPlastic
	)
	boardText(board, text, palette.text)
	model.PrimaryPart = floor
	return model
end

-- Portal sizes, in studs. Its footprint stays inside Layout.PORTAL_EXTENT.
local PORTAL_POST_X = 5.2
local PORTAL_POST_HEIGHT = 12
local PORTAL_STONE = 2.4
local PORTAL_SWIRL_DIAMETER = 8.4
local PORTAL_LABEL_SIZE = Vector2.new(12, 4)

-- 8. Portal: a stone arch on a step, with a glowing swirl in the middle that
-- is the Trigger.
function Kit.portalFrame(base: CFrame, palette: Palette, text: string): Model
	local model = newModel("Portal")
	local step = part(
		model,
		"Step",
		Vector3.new(14, 1, 6),
		base * CFrame.new(0, 0.5, 0),
		palette.rock,
		Enum.Material.SmoothPlastic
	)
	local stoneHeight = PORTAL_POST_HEIGHT / 3
	for side = -1, 1, 2 do
		for i = 1, 3 do
			part(
				model,
				string.format("Stone%s%d", if side < 0 then "Left" else "Right", i),
				Vector3.new(PORTAL_STONE, stoneHeight, PORTAL_STONE),
				base
					* CFrame.new(side * PORTAL_POST_X, 1 + stoneHeight * (i - 0.5), 0)
					* CFrame.Angles(0, side * i * 0.12, 0),
				palette.rock,
				Enum.Material.SmoothPlastic
			)
		end
	end
	-- The arch: stones on a half circle over the posts.
	local archY = 1 + PORTAL_POST_HEIGHT
	local keystone: Part? = nil
	for k = 1, 5 do
		local angle = math.pi * k / 6
		local stone = part(
			model,
			if k == 3 then "Keystone" else "Arch" .. k,
			Vector3.new(PORTAL_STONE, PORTAL_STONE, PORTAL_STONE + 0.2),
			base
				* CFrame.new(
					PORTAL_POST_X * math.cos(angle),
					archY + PORTAL_POST_X * math.sin(angle),
					0
				)
				* CFrame.Angles(0, 0, angle),
			palette.rock,
			Enum.Material.SmoothPlastic
		)
		if k == 3 then
			keystone = stone
		end
	end
	local trigger = cylinder(
		model,
		"Trigger",
		0.6,
		PORTAL_SWIRL_DIAMETER,
		base
			* CFrame.new(0, 1 + PORTAL_SWIRL_DIAMETER / 2 + 0.8, 0)
			* CFrame.Angles(0, math.pi / 2, 0),
		palette.glow,
		Enum.Material.Neon
	)
	trigger.Transparency = 0.3
	trigger.CanCollide = false
	local swirl = Instance.new("ParticleEmitter")
	swirl.Name = "Swirl"
	swirl.Color = ColorSequence.new(palette.glow)
	swirl.LightEmission = 1
	swirl.Rate = 14
	swirl.Lifetime = NumberRange.new(1.2, 1.8)
	swirl.Speed = NumberRange.new(0.5, 1)
	swirl.RotSpeed = NumberRange.new(90, 180)
	swirl.Rotation = NumberRange.new(0, 360)
	swirl.Size = NumberSequence.new(1.6, 0)
	swirl.Transparency = NumberSequence.new(0.2, 1)
	swirl.Parent = trigger
	local top = keystone :: Part
	label(
		top,
		text,
		PORTAL_LABEL_SIZE,
		top.Size.Y / 2 + PORTAL_LABEL_SIZE.Y / 2 + 0.5,
		palette.text
	)
	model.PrimaryPart = step
	return model
end

-- 9. Sign: a board with text on two posts. The posts stand just outside the
-- board's edges, so neither crosses the lettering.
function Kit.sign(base: CFrame, palette: Palette, text: string): Model
	local model = newModel("Sign")
	local b = Scenery.SIGN_BOARD
	local top = b.y + b.height / 2
	local first: Part? = nil
	for side = -1, 1, 2 do
		local post = part(
			model,
			if side < 0 then "PostLeft" else "PostRight",
			Vector3.new(b.post, top, b.post),
			base * CFrame.new(side * (b.width + b.post) / 2, top / 2, 0),
			palette.trunk,
			Enum.Material.SmoothPlastic
		)
		first = first or post
	end
	local board = part(
		model,
		"Board",
		Vector3.new(b.width, b.height, 0.5),
		base * CFrame.new(0, b.y, 0),
		palette.trim,
		Enum.Material.SmoothPlastic
	)
	boardText(board, text, palette.text)
	model.PrimaryPart = first
	return model
end

-- An arrival pad: where a portal drops a player on a world.
function Kit.arrivalPad(base: CFrame, palette: Palette): Model
	local model = newModel("ArrivalPad")
	local pad = part(
		model,
		"Pad",
		Vector3.new(12, 1, 12),
		base * CFrame.new(0, 0.5, 0),
		palette.trim,
		Enum.Material.SmoothPlastic
	)
	model.PrimaryPart = pad
	return model
end

return Kit
