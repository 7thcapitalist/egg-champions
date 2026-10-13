--!strict
--[[
	PetVisual: the single source of a pet's look in the world and in the UI.

	PetVisual.create(petId, variant) returns a Model. Until the asset stage,
	that is a colored block: body color from the pet's type, a band in the
	rarity color, and a size that grows with rarity. The battle arena, the
	egg shop result, the pets screen and the team bar all show pets through
	PetVisual.view, which puts this same model in a ViewportFrame. No caller
	builds its own pet.

	Variant looks (design/eggs-and-effects.md), driven by the variant the
	server sent. A pet is never both:
	- Shiny: brighter colors and a sparkle emitter.
	- Golden: gold material and a soft glow.

	Every model carries an attachment named for its elemental feature (Flame,
	Sparks, Droplets, Leaves). Fire, electric and water pets get a small idle
	emitter there. Emitters start disabled; on the client one throttled loop
	enables them only while the pet is in the workspace, on screen and within
	IDLE.maxDistance of the camera. Particles do not render inside a
	ViewportFrame, so UI views never run them.

	The asset stage's seam is PetLook.MODEL_IDS: when a pet has an entry,
	PetVisual clones ReplicatedStorage.PetModels[<model id>] instead of the
	block, adds the feature attachment if the model lacks it, and applies
	the variant look to its parts. Callers do not change.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local PetLook = require(script.Parent.visual.PetLook)

local PetVisual = {}

-- Every idle and variant particle number, in one table.
local IDLE = table.freeze({
	-- Studs from the camera past which emitters switch off.
	maxDistance = 60,
	-- Seconds between visibility checks.
	checkInterval = 0.25,
	-- Elemental idle emitter.
	rate = 4,
	lifetimeMin = 0.4,
	lifetimeMax = 0.7,
	speed = 1.5,
	sizeStart = 0.35,
	-- Shiny sparkle emitter.
	sparkleRate = 3,
	sparkleLifetime = 0.6,
	sparkleSize = 0.3,
	-- Golden glow.
	glowBrightness = 1,
	glowRange = 6,
})
PetVisual.IDLE = IDLE

local TEXTURES = table.freeze({
	Flame = "rbxasset://textures/particles/fire_main.dds",
	Sparks = "rbxasset://textures/particles/sparkles_main.dds",
	Droplets = "rbxasset://textures/particles/smoke_main.dds",
	Sparkle = "rbxasset://textures/particles/sparkles_main.dds",
})

-- The block's depth and the band's thickness, as shares of its edge.
local DEPTH_SHARE = 0.8
local BAND_SHARE = 0.18
local BAND_OVERHANG = 0.08

local function color(c: PetLook.RGB): Color3
	return Color3.fromRGB(c.r, c.g, c.b)
end

-- Culling

local tracked: { [ParticleEmitter]: Attachment } = {}
local loopStarted = false

local function startCulling()
	if loopStarted or not RunService:IsClient() then
		return
	end
	loopStarted = true
	local elapsed = 0
	RunService.Heartbeat:Connect(function(dt: number)
		elapsed += dt
		if elapsed < IDLE.checkInterval then
			return
		end
		elapsed = 0
		local camera = workspace.CurrentCamera
		for emitter, attachment in tracked do
			if emitter.Parent == nil then
				tracked[emitter] = nil
				continue
			end
			local visible = false
			if camera ~= nil and emitter:IsDescendantOf(workspace) then
				local position = attachment.WorldPosition
				if (position - camera.CFrame.Position).Magnitude <= IDLE.maxDistance then
					local _, onScreen = camera:WorldToViewportPoint(position)
					visible = onScreen
				end
			end
			if emitter.Enabled ~= visible then
				emitter.Enabled = visible
			end
		end
	end)
end

local function track(emitter: ParticleEmitter, attachment: Attachment)
	emitter.Enabled = false
	tracked[emitter] = attachment
	startCulling()
end

-- Building

local function idleEmitter(look: PetLook.Look, attachment: Attachment)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "Idle"
	emitter.Texture = TEXTURES[look.feature.attachment] or TEXTURES.Sparkle
	emitter.Color = ColorSequence.new(color(look.feature.color))
	emitter.LightEmission = 0.6
	emitter.Rate = IDLE.rate
	emitter.Lifetime = NumberRange.new(IDLE.lifetimeMin, IDLE.lifetimeMax)
	emitter.Speed = NumberRange.new(IDLE.speed)
	emitter.SpreadAngle = Vector2.new(15, 15)
	emitter.Size = NumberSequence.new(IDLE.sizeStart, 0)
	emitter.Transparency = NumberSequence.new(0.2, 1)
	emitter.Parent = attachment
	track(emitter, attachment)
end

local function sparkle(root: BasePart)
	local attachment = Instance.new("Attachment")
	attachment.Name = "Sparkle"
	attachment.Parent = root
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "Sparkle"
	emitter.Texture = TEXTURES.Sparkle
	emitter.LightEmission = 1
	emitter.Rate = IDLE.sparkleRate
	emitter.Lifetime = NumberRange.new(IDLE.sparkleLifetime)
	emitter.Speed = NumberRange.new(0.5)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Size = NumberSequence.new(IDLE.sparkleSize, 0)
	emitter.Shape = Enum.ParticleEmitterShape.Box
	emitter.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	emitter.Parent = attachment
	track(emitter, attachment)
end

-- Paints the variant look onto every part of a model.
local function applyVariant(model: Model, root: BasePart, look: PetLook.Look)
	if look.golden then
		for _, part in model:GetDescendants() do
			if part:IsA("BasePart") and part.Name ~= "Band" then
				part.Color = color(look.body)
				part.Material = Enum.Material.Foil
				part.Reflectance = 0.2
			end
		end
		local glow = Instance.new("PointLight")
		glow.Name = "Glow"
		glow.Color = color(look.body)
		glow.Brightness = IDLE.glowBrightness
		glow.Range = IDLE.glowRange
		glow.Shadows = false
		glow.Parent = root
	elseif look.shiny then
		for _, part in model:GetDescendants() do
			if part:IsA("BasePart") then
				part.Material = Enum.Material.Neon
			end
		end
		sparkle(root)
	end
end

local function block(look: PetLook.Look): (Model, BasePart)
	local model = Instance.new("Model")
	local edge = look.size

	local body = Instance.new("Part")
	body.Name = "Body"
	body.Anchored = true
	body.CanCollide = false
	body.CanQuery = false
	body.CanTouch = false
	body.CastShadow = false
	body.Material = Enum.Material.SmoothPlastic
	body.Size = Vector3.new(edge, edge, edge * DEPTH_SHARE)
	body.Color = color(look.body)
	body.TopSurface = Enum.SurfaceType.Smooth
	body.BottomSurface = Enum.SurfaceType.Smooth
	body.Parent = model

	local band = Instance.new("Part")
	band.Name = "Band"
	band.Anchored = true
	band.CanCollide = false
	band.CanQuery = false
	band.CanTouch = false
	band.CastShadow = false
	band.Material = Enum.Material.SmoothPlastic
	band.Size = Vector3.new(
		edge + edge * BAND_OVERHANG,
		edge * BAND_SHARE,
		edge * DEPTH_SHARE + edge * BAND_OVERHANG
	)
	band.Color = color(look.band)
	band.CFrame = body.CFrame
	band.Parent = model

	model.PrimaryPart = body
	return model, body
end

local function fromAsset(look: PetLook.Look): (Model?, BasePart?)
	local folder = ReplicatedStorage:FindFirstChild("PetModels")
	local source = if folder ~= nil and look.modelId ~= nil
		then folder:FindFirstChild(look.modelId :: string)
		else nil
	if source == nil or not source:IsA("Model") then
		warn(
			string.format(
				"PetVisual: no model %q for %s; using the block",
				look.modelId or "",
				look.petId or "?"
			)
		)
		return nil, nil
	end
	local model = source:Clone()
	local root = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
	if root == nil then
		return nil, nil
	end
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = true
			part.CanCollide = false
		end
	end
	model.PrimaryPart = root
	return model, root
end

local function build(look: PetLook.Look): Model
	local model: Model?, root: BasePart? = nil, nil
	if look.modelId ~= nil then
		model, root = fromAsset(look)
	end
	if model == nil or root == nil then
		model, root = block(look)
	end
	local pet = model :: Model
	local base = root :: BasePart
	pet.Name = "Pet_" .. (look.petId or look.typeId)
	pet:SetAttribute("PetId", look.petId)
	pet:SetAttribute("Type", look.typeId)
	pet:SetAttribute("Rarity", look.rarityId)
	pet:SetAttribute("Variant", look.variant)

	-- The feature attachment: a real model may bring its own, placed by the
	-- artist; otherwise it goes on the top back of the root part.
	local attachment = pet:FindFirstChild(look.feature.attachment, true)
	if attachment == nil or not attachment:IsA("Attachment") then
		local made = Instance.new("Attachment")
		made.Name = look.feature.attachment
		made.Position = Vector3.new(0, base.Size.Y / 2, base.Size.Z / 2)
		made.Parent = base
		attachment = made
	end
	if look.feature.emits then
		idleEmitter(look, attachment :: Attachment)
	end
	applyVariant(pet, base, look)
	return pet
end

-- One pet, with the variant the server sent (nil for a normal pet).
function PetVisual.create(petId: string, variant: string?): Model
	return build(PetLook.resolve(petId, variant))
end

-- A gym leader's pet, which has only a type.
function PetVisual.createLeader(typeId: string): Model
	return build(PetLook.resolveType(typeId, nil))
end

-- The UI view of a pet: a transparent ViewportFrame filling `parent`, with
-- the same model PetVisual.create builds and a camera framed on it.
-- Pass petId for a player's pet, or typeId alone for a gym leader's.
function PetVisual.view(
	parent: GuiObject,
	petId: string?,
	variant: string?,
	typeId: string?
): ViewportFrame
	local look = if petId ~= nil
		then PetLook.resolve(petId, variant)
		else PetLook.resolveType(typeId :: string, nil)
	local old = parent:FindFirstChild("PetView")
	if old ~= nil then
		old:Destroy()
	end
	local viewport = Instance.new("ViewportFrame")
	viewport.Name = "PetView"
	viewport.BackgroundTransparency = 1
	viewport.BorderSizePixel = 0
	viewport.Size = UDim2.fromScale(1, 1)
	viewport.Ambient = Color3.fromRGB(200, 200, 200)
	viewport.LightColor = Color3.fromRGB(255, 255, 255)
	viewport.LightDirection = Vector3.new(-1, -1, -1)
	viewport:SetAttribute("PetKey", PetLook.key(look))

	local model = build(look)
	model:PivotTo(CFrame.new())
	model.Parent = viewport

	-- Frame the largest rarity the same way, so size still reads in the UI.
	local camera = Instance.new("Camera")
	camera.FieldOfView = 30
	local largest = PetLook.SIZE.base + PetLook.SIZE.step * (#PetLook.RARITY_PALETTE - 1)
	local distance = largest * 3.2
	local eye = Vector3.new(distance * 0.45, distance * 0.35, distance)
	camera.CFrame = CFrame.lookAt(eye, Vector3.zero)
	camera.Parent = viewport
	viewport.CurrentCamera = camera
	viewport.Parent = parent
	return viewport
end

-- The key of what a view shows, so callers rebuild only on change.
function PetVisual.key(petId: string?, variant: string?, typeId: string?): string
	local look = if petId ~= nil
		then PetLook.resolve(petId, variant)
		else PetLook.resolveType(typeId :: string, nil)
	return PetLook.key(look)
end

return PetVisual
