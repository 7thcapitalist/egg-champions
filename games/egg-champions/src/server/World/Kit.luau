--!strict
--[[
	Kit: the prop builders the world builder places.

	Each builder returns a Model made from plain parts, anchored, with a
	PrimaryPart, placed at the CFrame it is given (the CFrame is the prop's
	base, resting on the ground). No meshes, no uploaded assets: final art is
	the world stage's job, and it replaces this kit.

	Builders that a player interacts with (egg stand, portal) carry a part named
	"Trigger" that the builder wires up. Every Model gets a "Prop" attribute
	naming its builder, so what was built can be counted.

	Sizes here are prop geometry, not game numbers.
]]

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

-- A floating text label above a part.
local function label(adornee: BasePart, text: string, height: number, color: Color3)
	local gui = Instance.new("BillboardGui")
	gui.Name = "Label"
	gui.Size = UDim2.fromOffset(220, 90)
	gui.StudsOffsetWorldSpace = Vector3.new(0, height, 0)
	gui.AlwaysOnTop = false
	gui.MaxDistance = 120
	gui.Adornee = adornee
	local textLabel = Instance.new("TextLabel")
	textLabel.Size = UDim2.fromScale(1, 1)
	textLabel.BackgroundTransparency = 1
	textLabel.Text = text
	textLabel.TextColor3 = color
	textLabel.TextStrokeTransparency = 0.3
	textLabel.TextScaled = true
	textLabel.Font = Enum.Font.FredokaOne
	textLabel.Parent = gui
	gui.Parent = adornee
end

-- Egg stand signs: sized in studs, so they shrink with distance, and hidden
-- past SIGN_MAX_DISTANCE so only the stands near the player show a sign.
local SIGN_SIZE = UDim2.fromScale(9, 3.2)
local SIGN_MAX_DISTANCE = 60
local SIGN_HEIGHT = 3.5
local PRICE_GOLD = Color3.fromRGB(232, 179, 58)
local EGG_HOVER = 0.5

Kit.EGG_SPIN_TAG = "SpinningEgg"

local function line(gui: BillboardGui, text: string, top: number, color: Color3, name: string)
	local textLabel = Instance.new("TextLabel")
	textLabel.Name = name
	textLabel.Size = UDim2.fromScale(1, 0.5)
	textLabel.Position = UDim2.fromScale(0, top)
	textLabel.BackgroundTransparency = 1
	textLabel.Text = text
	textLabel.TextColor3 = color
	textLabel.TextStrokeTransparency = 0.3
	textLabel.TextScaled = true
	textLabel.TextWrapped = false
	textLabel.Font = Enum.Font.FredokaOne
	textLabel.Parent = gui
end

-- An egg stand's sign: the name on one line, the price below it in gold.
local function standSign(adornee: BasePart, name: string, price: string, color: Color3)
	local gui = Instance.new("BillboardGui")
	gui.Name = "Label"
	gui.Size = SIGN_SIZE
	gui.StudsOffsetWorldSpace = Vector3.new(0, SIGN_HEIGHT, 0)
	gui.AlwaysOnTop = false
	gui.MaxDistance = SIGN_MAX_DISTANCE
	gui.LightInfluence = 0
	gui.Adornee = adornee
	line(gui, name, 0, color, "Name")
	line(gui, price, 0.5, PRICE_GOLD, "Price")
	gui.Parent = adornee
end

-- 1. Ground: the flat top of an island. The base CFrame is the top center.
function Kit.ground(size: number, base: CFrame, palette: Palette): Model
	local model = newModel("Ground")
	local depth = 20
	local top = part(
		model,
		"Top",
		Vector3.new(size, depth, size),
		base * CFrame.new(0, -depth / 2, 0),
		palette.ground,
		palette.groundMaterial
	)
	model.PrimaryPart = top
	return model
end

-- 2. Cliff: the island's sides, a skirt that tapers below the ground.
function Kit.cliff(size: number, base: CFrame, palette: Palette): Model
	local model = newModel("Cliff")
	local layers = 3
	local layerHeight = 8
	local first: Part? = nil
	for i = 1, layers do
		local width = size - i * 12
		local p = part(
			model,
			"Layer" .. i,
			Vector3.new(width, layerHeight, width),
			base * CFrame.new(0, -20 - (i - 0.5) * layerHeight, 0),
			palette.cliff,
			Enum.Material.Slate
		)
		first = first or p
	end
	model.PrimaryPart = first
	return model
end

-- 3. Tree: a trunk and two blocky leaf layers.
function Kit.tree(base: CFrame, palette: Palette, scale: number): Model
	local model = newModel("Tree")
	local trunk = part(
		model,
		"Trunk",
		Vector3.new(2, 8, 2) * scale,
		base * CFrame.new(0, 4 * scale, 0),
		palette.trunk,
		Enum.Material.Wood
	)
	part(
		model,
		"Leaves",
		Vector3.new(8, 5, 8) * scale,
		base * CFrame.new(0, 9.5 * scale, 0),
		palette.leaf,
		Enum.Material.Grass
	)
	part(
		model,
		"LeavesTop",
		Vector3.new(5, 3, 5) * scale,
		base * CFrame.new(0, 13.5 * scale, 0) * CFrame.Angles(0, math.rad(45), 0),
		palette.leaf,
		Enum.Material.Grass
	)
	model.PrimaryPart = trunk
	return model
end

-- 4. Rock: two tilted blocks.
function Kit.rock(base: CFrame, palette: Palette, scale: number): Model
	local model = newModel("Rock")
	local big = part(
		model,
		"Big",
		Vector3.new(6, 4, 5) * scale,
		base * CFrame.new(0, 1.5 * scale, 0) * CFrame.Angles(0.1, 0.4, 0.05),
		palette.rock,
		Enum.Material.Rock
	)
	part(
		model,
		"Small",
		Vector3.new(3, 2.5, 3) * scale,
		base * CFrame.new(3 * scale, 1 * scale, 2 * scale) * CFrame.Angles(0, 1.1, 0.15),
		palette.rock,
		Enum.Material.Rock
	)
	model.PrimaryPart = big
	return model
end

-- 5. Water plane: a wide flat sheet around the island, just under the ground top.
function Kit.water(size: number, base: CFrame, palette: Palette): Model
	local model = newModel("Water")
	local sheet = part(
		model,
		"Sheet",
		Vector3.new(size, 1, size),
		base * CFrame.new(0, -6, 0),
		palette.water,
		Enum.Material.Glass
	)
	sheet.Transparency = 0.35
	sheet.CanCollide = false
	sheet.CanQuery = false
	model.PrimaryPart = sheet
	return model
end

-- 6. Egg stand: a plinth, a blocky placeholder egg on top (in a Model named
-- "Egg" that Kit.setEgg swaps for the real one), a sign, and a Trigger pad.
function Kit.eggStand(base: CFrame, palette: Palette, name: string, price: string): Model
	local model = newModel("EggStand")
	local plinth = part(
		model,
		"Plinth",
		Vector3.new(8, 3, 8),
		base * CFrame.new(0, 1.5, 0),
		palette.trim,
		Enum.Material.Marble
	)
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
	trigger.Transparency = 0.4
	trigger.CanCollide = false
	-- The sign floats above the egg: plinth top, egg, then the sign.
	local signPart = part(
		model,
		"SignAnchor",
		Vector3.new(1, 1, 1),
		base * CFrame.new(0, 3 + 4 + 2 * EGG_HOVER + 1, 0),
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

-- 7. Gym building: walls, a roof, a door gap, and a label.
function Kit.gymBuilding(base: CFrame, palette: Palette, text: string): Model
	local model = newModel("Gym")
	local width, depth, height = 24, 18, 14
	local floor = part(
		model,
		"Floor",
		Vector3.new(width, 1, depth),
		base * CFrame.new(0, 0.5, 0),
		palette.trim,
		Enum.Material.Concrete
	)
	part(
		model,
		"Back",
		Vector3.new(width, height, 1),
		base * CFrame.new(0, height / 2, depth / 2),
		palette.accent
	)
	part(
		model,
		"Left",
		Vector3.new(1, height, depth),
		base * CFrame.new(-width / 2, height / 2, 0),
		palette.accent
	)
	part(
		model,
		"Right",
		Vector3.new(1, height, depth),
		base * CFrame.new(width / 2, height / 2, 0),
		palette.accent
	)
	-- The front wall has a door gap in the middle.
	local side = (width - 8) / 2
	part(
		model,
		"FrontLeft",
		Vector3.new(side, height, 1),
		base * CFrame.new(-(4 + side / 2), height / 2, -depth / 2),
		palette.accent
	)
	part(
		model,
		"FrontRight",
		Vector3.new(side, height, 1),
		base * CFrame.new(4 + side / 2, height / 2, -depth / 2),
		palette.accent
	)
	part(
		model,
		"Lintel",
		Vector3.new(8, 4, 1),
		base * CFrame.new(0, height - 2, -depth / 2),
		palette.accent
	)
	local roof = part(
		model,
		"Roof",
		Vector3.new(width + 4, 2, depth + 4),
		base * CFrame.new(0, height + 1, 0),
		palette.trim,
		Enum.Material.Slate
	)
	label(roof, text, 8, palette.text)
	model.PrimaryPart = floor
	return model
end

-- 8. Portal frame: two posts, a top bar, and a glowing Trigger in the middle.
function Kit.portalFrame(base: CFrame, palette: Palette, text: string): Model
	local model = newModel("Portal")
	local width, height = 10, 14
	local floor = part(
		model,
		"Step",
		Vector3.new(width + 4, 1, 6),
		base * CFrame.new(0, 0.5, 0),
		palette.trim,
		Enum.Material.Marble
	)
	part(
		model,
		"PostLeft",
		Vector3.new(2, height, 2),
		base * CFrame.new(-width / 2, height / 2, 0),
		palette.trim
	)
	part(
		model,
		"PostRight",
		Vector3.new(2, height, 2),
		base * CFrame.new(width / 2, height / 2, 0),
		palette.trim
	)
	local bar = part(
		model,
		"Bar",
		Vector3.new(width + 2, 2, 2),
		base * CFrame.new(0, height + 1, 0),
		palette.trim
	)
	local trigger = part(
		model,
		"Trigger",
		Vector3.new(width - 2, height - 1, 1),
		base * CFrame.new(0, height / 2 + 0.5, 0),
		palette.glow,
		Enum.Material.Neon
	)
	trigger.Transparency = 0.3
	trigger.CanCollide = false
	label(bar, text, 5, palette.text)
	model.PrimaryPart = floor
	return model
end

-- 9. Sign: a post and a board with text.
function Kit.sign(base: CFrame, palette: Palette, text: string): Model
	local model = newModel("Sign")
	local post = part(
		model,
		"Post",
		Vector3.new(1, 6, 1),
		base * CFrame.new(0, 3, 0),
		palette.trunk,
		Enum.Material.Wood
	)
	local board = part(
		model,
		"Board",
		Vector3.new(10, 4, 0.5),
		base * CFrame.new(0, 7, 0),
		palette.trim,
		Enum.Material.Wood
	)
	label(board, text, 4, palette.text)
	model.PrimaryPart = post
	return model
end

-- 10. Light: a lamp post with a point light.
function Kit.light(base: CFrame, palette: Palette): Model
	local model = newModel("Light")
	local post =
		part(model, "Post", Vector3.new(1, 10, 1), base * CFrame.new(0, 5, 0), palette.trim)
	local lamp = part(
		model,
		"Lamp",
		Vector3.new(2, 2, 2),
		base * CFrame.new(0, 11, 0),
		palette.glow,
		Enum.Material.Neon
	)
	local glow = Instance.new("PointLight")
	glow.Color = palette.glow
	glow.Range = 24
	glow.Brightness = 1.5
	glow.Parent = lamp
	model.PrimaryPart = post
	return model
end

-- 11. Filler: a low bush or flower patch for scenery.
function Kit.filler(base: CFrame, palette: Palette, scale: number): Model
	local model = newModel("Filler")
	local bush = part(
		model,
		"Bush",
		Vector3.new(4, 2, 4) * scale,
		base * CFrame.new(0, 1 * scale, 0),
		palette.leaf,
		Enum.Material.Grass
	)
	part(
		model,
		"Bloom",
		Vector3.new(1, 1, 1) * scale,
		base * CFrame.new(0.8 * scale, 2.3 * scale, 0.5 * scale),
		palette.accent,
		Enum.Material.Neon
	)
	model.PrimaryPart = bush
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
		Enum.Material.Marble
	)
	model.PrimaryPart = pad
	return model
end

return Kit
