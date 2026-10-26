--!strict
-- Bounded elemental motion complements the sculpted mesh without obscuring its face.
local PetFinishing = {}
function PetFinishing.apply(model: Model, rarity: string, element: string)
	if rarity ~= "epic" and rarity ~= "legendary" then
		return
	end
	local palette = {
		fire = Color3.fromRGB(255, 165, 65),
		water = Color3.fromRGB(94, 235, 238),
		grass = Color3.fromRGB(147, 237, 106),
		electric = Color3.fromRGB(255, 230, 107),
	}
	local tint = palette[element] or Color3.new(1, 1, 1)
	local root = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
	if root then
		local attachment = Instance.new("Attachment")
		attachment.Name = "ElementAura"
		attachment.Parent = root
		local fx = Instance.new("ParticleEmitter")
		fx.Name = "ElementMotes"
		fx.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		fx.Color = ColorSequence.new(tint)
		fx.Rate = if rarity == "legendary" then 3 else 1
		fx.Lifetime = NumberRange.new(0.5, 1)
		fx.Speed = NumberRange.new(0.4, 1.3)
		fx.SpreadAngle = Vector2.new(180, 180)
		fx.Size = NumberSequence.new(0.15, 0)
		fx.LightEmission = 0.8
		fx.Parent = attachment
	end
end
return PetFinishing
