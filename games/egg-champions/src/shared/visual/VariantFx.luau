--!strict
--[[
	VariantFx: the shiny and golden layers drawn over a pet's ViewportFrame.

	PetVisual.view calls VariantFx.build with the view, the card it sits in,
	the variant and a Kit. The Kit is every engine call the builder needs
	(making instances, colors, sizes, tweens), so this module touches no
	engine global and the headless tests can build a view against fakes and
	check every instance it makes against EffectsBudget.VIEW_CLASSES.

	The layers (design/eggs-and-effects.md):
	- a VariantFx frame filling the view, with the card's UICorner copied in,
	  so the stroke follows the card's rounded corners;
	- a UIStroke on that frame, a UIGradient shimmer sweeping across it, and
	  a pulse that breathes the stroke and the tint;
	- twinkle ImageLabels on the view, growing in and out.

	build returns the layers that can fade, each with the transparency it
	rests at, so PetVisual.fade can dim them with the model when a battle
	pet faints.
]]

local EffectsBudget = require(script.Parent.EffectsBudget)

export type RGB = EffectsBudget.RGB

-- How a looping tween runs. PetVisual turns this into a TweenInfo.
export type LoopInfo = {
	seconds: number,
	style: "Linear" | "Sine" | "Quad",
	direction: "InOut" | "Out",
	reverses: boolean,
	delay: number,
}

export type Kit = {
	new: (className: string) -> any,
	color: (c: RGB) -> any,
	scale: (x: number, y: number) -> any,
	vector2: (x: number, y: number) -> any,
	-- A NumberSequence from { time, value } pairs.
	sequence: (points: { { number } }) -> any,
	-- Enum.ApplyStrokeMode.Border.
	strokeBorder: any,
	-- Starts a looping tween on target. nil when nothing animates (the
	-- server, and the tests).
	loop: ((target: any, info: LoopInfo, goal: { [string]: any }) -> ())?,
}

-- One layer that fades with the model: `target[property]` rests at `base`.
export type Layer = { target: any, property: string, base: number }

local VariantFx = {}

-- The name of the overlay frame inside the view.
VariantFx.FRAME = "VariantFx"

-- Builds the variant's layers on `view`. `card` is the GuiObject the view
-- fills; its UICorner, if any, is copied onto the overlay. Returns the
-- layers that fade with the model (empty for a normal pet).
function VariantFx.build(view: any, card: any, variant: string?, kit: Kit): { Layer }
	local look = EffectsBudget.variantView(variant)
	local layers: { Layer } = {}
	if look.stroke == nil and look.shimmer == nil and look.twinkles == nil then
		return layers
	end
	local loop = kit.loop

	local fx = kit.new("Frame")
	fx.Name = VariantFx.FRAME
	fx.BackgroundTransparency = 1
	fx.BorderSizePixel = 0
	fx.Size = kit.scale(1, 1)
	fx.ZIndex = view.ZIndex
	fx.Parent = view

	local round = if card ~= nil then card:FindFirstChildWhichIsA("UICorner") else nil
	if round ~= nil then
		local corner = kit.new("UICorner")
		corner.Name = "VariantCorner"
		corner.CornerRadius = round.CornerRadius
		corner.Parent = fx
	end

	local stroke: any = nil
	if look.stroke ~= nil then
		local s = look.stroke :: EffectsBudget.VariantStroke
		stroke = kit.new("UIStroke")
		stroke.Name = "VariantStroke"
		stroke.ApplyStrokeMode = kit.strokeBorder
		stroke.Color = kit.color(s.color)
		stroke.Thickness = s.thickness
		stroke.Transparency = s.transparency
		stroke.Parent = fx
	end

	if look.shimmer ~= nil then
		local sh = look.shimmer :: EffectsBudget.VariantShimmer
		fx.BackgroundColor3 = kit.color(sh.color)
		fx.BackgroundTransparency = sh.transparency
		local half = sh.width / 2
		local gradient = kit.new("UIGradient")
		gradient.Name = "Shimmer"
		gradient.Rotation = 30
		gradient.Transparency = kit.sequence({
			{ 0, 1 },
			{ math.max(0.5 - half, 0.001), 1 },
			{ 0.5, 0 },
			{ math.min(0.5 + half, 0.999), 1 },
			{ 1, 1 },
		})
		gradient.Offset = kit.vector2(-1, 0)
		gradient.Parent = fx
		if loop ~= nil then
			loop(gradient, {
				seconds = sh.seconds,
				style = "Linear",
				direction = "InOut",
				reverses = false,
				delay = 0,
			}, { Offset = kit.vector2(1, 0) })
		end
	end

	if look.pulse ~= nil and loop ~= nil then
		local p = look.pulse :: EffectsBudget.VariantPulse
		local info: LoopInfo = {
			seconds = p.seconds,
			style = "Sine",
			direction = "InOut",
			reverses = true,
			delay = 0,
		}
		if stroke ~= nil then
			stroke.Transparency = p.low
			loop(stroke, info, { Transparency = p.high })
		end
		if look.shimmer ~= nil then
			local base = fx.BackgroundTransparency
			loop(fx, info, { BackgroundTransparency = base + (1 - base) * p.high })
		end
	end

	if stroke ~= nil then
		table.insert(
			layers,
			{ target = stroke, property = "Transparency", base = stroke.Transparency }
		)
	end
	if look.shimmer ~= nil then
		table.insert(
			layers,
			{ target = fx, property = "BackgroundTransparency", base = fx.BackgroundTransparency }
		)
	end

	local stars: { any } = {}
	if look.twinkles ~= nil then
		local t = look.twinkles :: EffectsBudget.VariantTwinkles
		for i, spot in t.spots do
			local star = kit.new("ImageLabel")
			star.Name = "Twinkle" .. i
			star.BackgroundTransparency = 1
			star.Image = t.image
			star.ImageColor3 = kit.color(t.color)
			star.ImageTransparency = 0
			star.AnchorPoint = kit.vector2(0.5, 0.5)
			star.Position = kit.scale(spot.x, spot.y)
			star.Size = kit.scale(t.size, t.size)
			star.ZIndex = view.ZIndex + 1
			star.Parent = view
			table.insert(stars, star)
			table.insert(layers, { target = star, property = "ImageTransparency", base = 0 })
			if loop ~= nil then
				star.Size = kit.scale(0, 0)
				loop(star, {
					seconds = t.seconds / 2,
					style = "Quad",
					direction = "Out",
					reverses = true,
					delay = t.stagger * (i - 1),
				}, { Size = kit.scale(t.size, t.size) })
			end
		end
	end

	-- Callers may raise the view's ZIndex after building it (the hatch
	-- reveal does); keep the layers on top of it either way.
	view:GetPropertyChangedSignal("ZIndex"):Connect(function()
		fx.ZIndex = view.ZIndex
		for _, star in stars do
			star.ZIndex = view.ZIndex + 1
		end
	end)
	return layers
end

-- The transparency a layer resting at `base` shows at fade `amount`
-- (0 is as built, 1 is gone).
function VariantFx.faded(base: number, amount: number): number
	return base + (1 - base) * math.clamp(amount, 0, 1)
end

return VariantFx
