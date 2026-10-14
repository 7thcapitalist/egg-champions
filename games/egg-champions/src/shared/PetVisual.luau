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
	are UI layered on the ViewportFrame itself by VariantFx, so they show at
	any size. PetVisual.fade dims the model and those layers together.

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
local VariantFx = require(script.Parent.visual.VariantFx)

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

-- What each live view's variant layers need to fade: its looping tweens and
-- the layers VariantFx built. Cleared when the view goes away.
type Live = { tweens: { Tween }, layers: { VariantFx.Layer } }
local live: { [ViewportFrame]: Live } = setmetatable({}, { __mode = "k" }) :: any

-- The engine side of VariantFx: real instances, colors and tweens.
local function kitFor(state: Live): VariantFx.Kit
	local animate = RunService:IsClient()
	local function loopTween(target: any, info: VariantFx.LoopInfo, goal: { [string]: any })
		local tween = TweenService:Create(
			target,
			TweenInfo.new(
				info.seconds,
				(Enum.EasingStyle :: any)[info.style],
				(Enum.EasingDirection :: any)[info.direction],
				-1,
				info.reverses,
				info.delay
			),
			goal
		)
		tween:Play()
		table.insert(state.tweens, tween)
	end
	return {
		new = function(className: string): any
			return Instance.new(className :: any)
		end,
		color = color,
		scale = UDim2.fromScale,
		vector2 = Vector2.new,
		sequence = function(points: { { number } }): any
			local keys = {}
			for _, point in points do
				table.insert(keys, NumberSequenceKeypoint.new(point[1], point[2]))
			end
			return NumberSequence.new(keys)
		end,
		strokeBorder = Enum.ApplyStrokeMode.Border,
		loop = if animate then loopTween else nil,
	}
end

-- Layers the variant's stroke, shimmer, pulse and twinkles on the view.
local function variantFx(view: ViewportFrame, card: GuiObject, variant: string?)
	local state: Live = { tweens = {}, layers = {} }
	state.layers = VariantFx.build(view, card, variant, kitFor(state))
	live[view] = state
	view.Destroying:Connect(function()
		for _, tween in state.tweens do
			tween:Cancel()
		end
		live[view] = nil
	end)
end

-- Fades a view's model and its variant layers together: `amount` 0 is as
-- built, 1 is gone. With `seconds` it tweens; without, it sets at once.
-- The variant's looping tweens stop, so a fainted pet stops shimmering.
function PetVisual.fade(view: ViewportFrame, amount: number, seconds: number?)
	local function set(target: Instance, goal: { [string]: any })
		if seconds ~= nil and seconds > 0 then
			TweenService:Create(target, TweenInfo.new(seconds), goal):Play()
		else
			for property, value in goal do
				(target :: any)[property] = value
			end
		end
	end
	set(view, { ImageTransparency = math.clamp(amount, 0, 1) })
	local state = live[view]
	if state == nil then
		return
	end
	for _, tween in state.tweens do
		tween:Cancel()
	end
	table.clear(state.tweens)
	for _, layer in state.layers do
		set(layer.target, { [layer.property] = VariantFx.faded(layer.base, amount) })
	end
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
	variantFx(viewport, parent, look.variant)
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
