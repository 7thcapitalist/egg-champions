--!strict
--[[
	PetVisual: the single source of a pet's look in the world and in the UI.

	PetVisual.create(petId, variant) returns a Model. Until the asset stage,
	that is a colored block: body color from the pet's type, a band in the
	rarity color, and a size that grows with rarity. The battle arena, the
	egg shop result, the pets screen, the team bar and the hatch reveal all
	show pets through PetVisual.view, which puts this same model in a
	ViewportFrame. No caller builds its own pet.

	Roblox does not render particles or lights inside a ViewportFrame, and
	every pet is shown in one, so nothing here uses them. Variant looks
	(design/eggs-and-effects.md) come from EffectsBudget.VARIANT_VIEW and use
	only what renders there. A pet is never both:
	- Shiny: brighter colors in Neon, a pale stroke, a sweeping pale shimmer
	  and a few twinkling sparkle images.
	- Golden: gold Foil body, a warm gold stroke, a slow glow pulse and a
	  broad warm shimmer.
	The material goes on the model; the stroke, shimmer, pulse and twinkles
	are UI layered on the ViewportFrame itself, so they show at any size.

	Every model carries an attachment named for its elemental feature (Flame,
	Sparks, Droplets, Leaves). Fire, electric and water pets get a small solid
	accent there in the feature color.

	The asset stage's seam is PetLook.MODEL_IDS: when a pet has an entry,
	PetVisual clones ReplicatedStorage.PetModels[<model id>] instead of the
	block, adds the feature attachment if the model lacks it, and applies
	the variant material to its parts. Callers do not change.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local EffectsBudget = require(script.Parent.visual.EffectsBudget)
local PetLook = require(script.Parent.visual.PetLook)

local PetVisual = {}

-- The block's depth and the band's thickness, as shares of its edge.
local DEPTH_SHARE = 0.8
local BAND_SHARE = 0.18
local BAND_OVERHANG = 0.08

local function color(c: PetLook.RGB): Color3
	return Color3.fromRGB(c.r, c.g, c.b)
end

local function material(name: string): Enum.Material
	return (Enum.Material :: any)[name] :: Enum.Material
end

-- Building

local function accent(look: PetLook.Look, base: BasePart, attachment: Attachment)
	local edge = look.size * EffectsBudget.ACCENT.share
	local piece = Instance.new("Part")
	piece.Name = "Accent"
	piece.Anchored = true
	piece.CanCollide = false
	piece.CanQuery = false
	piece.CanTouch = false
	piece.CastShadow = false
	piece.Material = material(EffectsBudget.ACCENT.material)
	piece.Color = color(look.feature.color)
	piece.Size = Vector3.new(edge, edge, edge)
	piece.CFrame = attachment.WorldCFrame
	piece.Parent = base.Parent
end

-- Paints the variant material onto the model. Golden leaves the rarity band
-- alone so rarity still reads; shiny brightens every part.
local function applyVariant(model: Model, look: PetLook.Look)
	local view = EffectsBudget.variantView(look.variant)
	if view.material == nil then
		return
	end
	local mat = material(view.material :: string)
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			if look.golden and part.Name == "Band" then
				continue
			end
			if look.golden then
				part.Color = color(look.body)
			end
			part.Material = mat
		end
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
	if look.feature.accent then
		accent(look, base, attachment :: Attachment)
	end
	applyVariant(pet, look)
	return pet
end

-- Variant UI on the frame

-- A looping tween, cancelled when the view goes away.
local function loop(view: ViewportFrame, target: Instance, info: TweenInfo, goal: { [string]: any })
	local tween = TweenService:Create(target, info, goal)
	tween:Play()
	view.Destroying:Connect(function()
		tween:Cancel()
	end)
end

-- Layers the variant's stroke, shimmer, pulse and twinkles on the view.
-- Only UI objects, which render over a ViewportFrame at any size.
local function variantFx(view: ViewportFrame, variant: string?)
	local look = EffectsBudget.variantView(variant)
	if look.stroke == nil and look.shimmer == nil and look.twinkles == nil then
		return
	end
	local animate = RunService:IsClient()

	local fx = Instance.new("Frame")
	fx.Name = "VariantFx"
	fx.BackgroundTransparency = 1
	fx.BorderSizePixel = 0
	fx.Size = UDim2.fromScale(1, 1)
	fx.ZIndex = view.ZIndex
	fx.Parent = view

	local stroke: UIStroke? = nil
	if look.stroke ~= nil then
		local s = look.stroke :: EffectsBudget.VariantStroke
		local made = Instance.new("UIStroke")
		made.Name = "VariantStroke"
		made.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		made.Color = color(s.color)
		made.Thickness = s.thickness
		made.Transparency = s.transparency
		made.Parent = fx
		stroke = made
	end

	if look.shimmer ~= nil then
		local sh = look.shimmer :: EffectsBudget.VariantShimmer
		fx.BackgroundColor3 = color(sh.color)
		fx.BackgroundTransparency = sh.transparency
		local half = sh.width / 2
		local gradient = Instance.new("UIGradient")
		gradient.Name = "Shimmer"
		gradient.Rotation = 30
		gradient.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(math.max(0.5 - half, 0.001), 1),
			NumberSequenceKeypoint.new(0.5, 0),
			NumberSequenceKeypoint.new(math.min(0.5 + half, 0.999), 1),
			NumberSequenceKeypoint.new(1, 1),
		})
		gradient.Offset = Vector2.new(-1, 0)
		gradient.Parent = fx
		if animate then
			loop(
				view,
				gradient,
				TweenInfo.new(sh.seconds, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1),
				{ Offset = Vector2.new(1, 0) }
			)
		end
	end

	if look.pulse ~= nil and animate then
		local p = look.pulse :: EffectsBudget.VariantPulse
		local info =
			TweenInfo.new(p.seconds, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
		if stroke ~= nil then
			stroke.Transparency = p.low
			loop(view, stroke, info, { Transparency = p.high })
		end
		if look.shimmer ~= nil then
			local base = fx.BackgroundTransparency
			loop(view, fx, info, { BackgroundTransparency = base + (1 - base) * p.high })
		end
	end

	if look.twinkles ~= nil then
		local t = look.twinkles :: EffectsBudget.VariantTwinkles
		for i, spot in t.spots do
			local star = Instance.new("ImageLabel")
			star.Name = "Twinkle" .. i
			star.BackgroundTransparency = 1
			star.Image = t.image
			star.ImageColor3 = color(t.color)
			star.AnchorPoint = Vector2.new(0.5, 0.5)
			star.Position = UDim2.fromScale(spot.x, spot.y)
			star.Size = UDim2.fromScale(t.size, t.size)
			star.ZIndex = view.ZIndex + 1
			star.Parent = view
			if animate then
				star.Size = UDim2.fromScale(0, 0)
				loop(
					view,
					star,
					TweenInfo.new(
						t.seconds / 2,
						Enum.EasingStyle.Quad,
						Enum.EasingDirection.Out,
						-1,
						true,
						t.stagger * (i - 1)
					),
					{ Size = UDim2.fromScale(t.size, t.size) }
				)
			end
		end
	end

	-- Callers may raise the view's ZIndex after building it (the hatch
	-- reveal does); keep the layers on top of it either way.
	local function follow()
		fx.ZIndex = view.ZIndex
		for _, child in view:GetChildren() do
			if child:IsA("ImageLabel") then
				child.ZIndex = view.ZIndex + 1
			end
		end
	end
	view:GetPropertyChangedSignal("ZIndex"):Connect(follow)
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
	variantFx(viewport, look.variant)
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
