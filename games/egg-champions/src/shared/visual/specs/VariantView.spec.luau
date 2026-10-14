--!strict
local Runner = require(script.Parent.Parent.Parent.testing.Runner)
local Config = require(script.Parent.Parent.Parent.Config)
local EffectsBudget = require(script.Parent.Parent.EffectsBudget)
local VariantFx = require(script.Parent.Parent.VariantFx)

local describe = Runner.describe
local it = Runner.it
local expect = Runner.expect

-- Classes Roblox does not render inside a ViewportFrame. Highlight is here
-- too: it is not drawn in a ViewportFrame either.
local UNSAFE = {
	"ParticleEmitter",
	"PointLight",
	"SpotLight",
	"SurfaceLight",
	"Light",
	"Fire",
	"Smoke",
	"Sparkles",
	"Trail",
	"Beam",
	"Highlight",
}

local SAFE = { "UIStroke", "UIGradient", "Frame", "ImageLabel", "UICorner" }

local MATERIALS = { "Neon", "Foil", "SmoothPlastic", "Metal", "Glass", "Plastic" }

local function variants(): { string? }
	local list: { string? } = { nil }
	for _, variant in Config.variants do
		table.insert(list, variant.id)
	end
	return list
end

local function isFraction(value: any): boolean
	return type(value) == "number" and value >= 0 and value <= 1
end

local function positive(value: any): boolean
	return type(value) == "number" and value > 0 and value == value and value < math.huge
end

-- Fake instances for building a variant view with no engine. Each records
-- its class, properties, children and ZIndex listeners.
type FakeInfo = {
	className: string,
	props: { [string]: any },
	children: { any },
	listeners: { () -> () },
}
local fakeInfo: { [any]: FakeInfo } = {}
local FakeMeta: any = {}
FakeMeta.__index = function(self: any, key: string): any
	local info = fakeInfo[self]
	if key == "ClassName" then
		return info.className
	elseif key == "FindFirstChildWhichIsA" then
		return function(_: any, className: string): any
			for _, child in info.children do
				if fakeInfo[child].className == className then
					return child
				end
			end
			return nil
		end
	elseif key == "GetPropertyChangedSignal" then
		return function(_: any, _property: string): any
			return {
				Connect = function(_: any, fn: () -> ())
					table.insert(info.listeners, fn)
				end,
			}
		end
	end
	return info.props[key]
end
FakeMeta.__newindex = function(self: any, key: string, value: any)
	local info = fakeInfo[self]
	if key == "Parent" then
		local old = info.props.Parent
		if old ~= nil then
			local siblings = fakeInfo[old].children
			table.remove(siblings, table.find(siblings, self) :: number)
		end
		table.insert(fakeInfo[value].children, self)
	end
	info.props[key] = value
end

local function fake(className: string): any
	local self = setmetatable({}, FakeMeta)
	fakeInfo[self] = { className = className, props = {}, children = {}, listeners = {} }
	return self
end

-- Every instance under `root`, not counting root.
local function descendants(root: any): { any }
	local found = {}
	local function walk(node: any)
		for _, child in fakeInfo[node].children do
			table.insert(found, child)
			walk(child)
		end
	end
	walk(root)
	return found
end

-- A card with a rounded corner, a view inside it, and a kit that records
-- every instance and every looping tween it makes.
local function scene(animate: boolean): (any, any, VariantFx.Kit, { any }, { any })
	local card = fake("Frame")
	local round = fake("UICorner")
	round.CornerRadius = "radius-12"
	round.Parent = card
	local view = fake("ViewportFrame")
	view.ZIndex = 5
	view.Parent = card
	local made: { any } = {}
	local loops: { any } = {}
	local kit: VariantFx.Kit = {
		new = function(className: string): any
			local instance = fake(className)
			table.insert(made, instance)
			return instance
		end,
		color = function(c: EffectsBudget.RGB): any
			return c
		end,
		scale = function(x: number, y: number): any
			return { x = x, y = y }
		end,
		vector2 = function(x: number, y: number): any
			return { x = x, y = y }
		end,
		sequence = function(points: { { number } }): any
			return points
		end,
		strokeBorder = "Border",
		loop = if animate
			then function(target: any, _info: VariantFx.LoopInfo, _goal: { [string]: any })
				table.insert(loops, target)
			end
			else nil,
	}
	return card, view, kit, made, loops
end

local function allViewClasses(): { string }
	local list = {}
	for _, classes in EffectsBudget.VIEW_CLASSES do
		for _, class in classes do
			table.insert(list, class)
		end
	end
	return list
end

return function()
	describe("EffectsBudget.variantView", function()
		it("gives every variant in config, and normal, a viewport look", function()
			expect(#Config.variants > 0).toBeTrue()
			for _, variant in Config.variants do
				expect(EffectsBudget.VARIANT_VIEW[variant.id] ~= nil).toBeTrue()
			end
			for i = 1, #Config.variants + 1 do
				local variant = variants()[i]
				expect(type(EffectsBudget.variantView(variant)) == "table").toBeTrue()
			end
		end)

		it(
			"never depends on a ParticleEmitter, a Light or anything else a viewport skips",
			function()
				for i = 1, #Config.variants + 1 do
					local variant = variants()[i]
					for _, class in EffectsBudget.variantClasses(variant) do
						expect(table.find(UNSAFE, class)).toEqual(nil)
						expect(table.find(SAFE, class) ~= nil).toBeTrue()
					end
				end
				for piece, classes in EffectsBudget.VIEW_CLASSES do
					for _, class in classes do
						expect(table.find(UNSAFE, class)).toEqual(nil)
					end
					expect(type(piece) == "string").toBeTrue()
				end
			end
		)

		it("leaves normal plain and gives every other variant a stroke and a material", function()
			local normal = EffectsBudget.variantView(nil)
			expect(normal.material).toEqual(nil)
			expect(#EffectsBudget.variantClasses(nil)).toEqual(0)
			for _, variant in Config.variants do
				local view = EffectsBudget.variantView(variant.id)
				expect(view.stroke ~= nil).toBeTrue()
				expect(table.find(MATERIALS, view.material :: string) ~= nil).toBeTrue()
			end
		end)

		it("makes shiny and golden different from each other at a glance", function()
			local shiny = EffectsBudget.variantView("shiny")
			local golden = EffectsBudget.variantView("golden")
			expect(shiny.material ~= golden.material).toBeTrue()
			local a = (shiny.stroke :: EffectsBudget.VariantStroke).color
			local b = (golden.stroke :: EffectsBudget.VariantStroke).color
			expect(a.r == b.r and a.g == b.g and a.b == b.b).toBeFalse()
			-- Shiny twinkles; golden pulses a glow.
			expect(shiny.twinkles ~= nil).toBeTrue()
			expect(golden.pulse ~= nil).toBeTrue()
		end)

		it("keeps every look number in range", function()
			for _, variant in Config.variants do
				local view = EffectsBudget.variantView(variant.id)
				if view.stroke ~= nil then
					local s = view.stroke :: EffectsBudget.VariantStroke
					expect(positive(s.thickness)).toBeTrue()
					expect(isFraction(s.transparency)).toBeTrue()
				end
				if view.shimmer ~= nil then
					local sh = view.shimmer :: EffectsBudget.VariantShimmer
					expect(isFraction(sh.transparency)).toBeTrue()
					expect(sh.width > 0 and sh.width < 1).toBeTrue()
					expect(positive(sh.seconds)).toBeTrue()
				end
				if view.pulse ~= nil then
					local p = view.pulse :: EffectsBudget.VariantPulse
					expect(isFraction(p.low) and isFraction(p.high)).toBeTrue()
					expect(p.low < p.high).toBeTrue()
					expect(positive(p.seconds)).toBeTrue()
				end
				if view.twinkles ~= nil then
					local t = view.twinkles :: EffectsBudget.VariantTwinkles
					expect(#t.spots > 0).toBeTrue()
					expect(positive(t.size) and t.size < 1).toBeTrue()
					expect(positive(t.seconds)).toBeTrue()
					expect(type(t.image) == "string" and #t.image > 0).toBeTrue()
					-- An ImageLabel needs a plain image; .dds particle textures
					-- may not load in one.
					expect(string.match(string.lower(t.image), "%.dds$")).toEqual(nil)
					for _, spot in t.spots do
						expect(isFraction(spot.x) and isFraction(spot.y)).toBeTrue()
					end
				end
			end
		end)

		it("rejects a variant that is not in config", function()
			expect(function()
				EffectsBudget.variantView("sparkly")
			end).toThrow()
		end)
	end)
	describe("VariantFx.build", function()
		it(
			"only creates classes listed in EffectsBudget.VIEW_CLASSES, all inside the view",
			function()
				local listed = allViewClasses()
				for _, animate in { false, true } do
					for i = 1, #Config.variants + 1 do
						local variant = variants()[i]
						local card, view, kit, made, loops = scene(animate)
						VariantFx.build(view, card, variant, kit)
						local own = EffectsBudget.variantClasses(variant)
						local under = descendants(view)
						-- Everything the builder made hangs off the view.
						expect(#under).toEqual(#made)
						for _, instance in under do
							local class = instance.ClassName
							expect(table.find(listed, class) ~= nil).toBeTrue()
							expect(table.find(own, class) ~= nil).toBeTrue()
							expect(table.find(UNSAFE, class)).toEqual(nil)
						end
						for _, target in loops do
							expect(table.find(made, target) ~= nil).toBeTrue()
						end
					end
				end
			end
		)

		it("makes nothing for a normal pet", function()
			local card, view, kit, made = scene(true)
			local layers = VariantFx.build(view, card, nil, kit)
			expect(#made).toEqual(0)
			expect(#layers).toEqual(0)
		end)

		it("rounds the overlay like the card, so the stroke follows its corners", function()
			for _, variant in Config.variants do
				local card, view, kit = scene(false)
				VariantFx.build(view, card, variant.id, kit)
				local fx = view:FindFirstChildWhichIsA("Frame")
				expect(fx ~= nil).toBeTrue()
				expect(fx.Name).toEqual(VariantFx.FRAME)
				local corner = fx:FindFirstChildWhichIsA("UICorner")
				expect(corner ~= nil).toBeTrue()
				expect(corner.CornerRadius).toEqual("radius-12")
				expect(fx:FindFirstChildWhichIsA("UIStroke") ~= nil).toBeTrue()
			end
		end)

		it("hands back layers that fade to nothing with the model", function()
			for _, variant in Config.variants do
				local card, view, kit, made = scene(true)
				local layers = VariantFx.build(view, card, variant.id, kit)
				expect(#layers > 0).toBeTrue()
				for _, layer in layers do
					expect(table.find(made, layer.target) ~= nil).toBeTrue()
					expect(isFraction(layer.base)).toBeTrue()
					expect(layer.target[layer.property]).toEqual(layer.base)
					expect(VariantFx.faded(layer.base, 0)).toEqual(layer.base)
					expect(VariantFx.faded(layer.base, 1)).toEqual(1)
				end
			end
		end)

		it("keeps its layers above the view when the view's ZIndex rises", function()
			local card, view, kit, made = scene(false)
			VariantFx.build(view, card, "shiny", kit)
			view.ZIndex = 40
			for _, listener in fakeInfo[view].listeners do
				listener()
			end
			for _, instance in made do
				if instance.ClassName == "Frame" then
					expect(instance.ZIndex).toEqual(40)
				elseif instance.ClassName == "ImageLabel" then
					expect(instance.ZIndex).toEqual(41)
				end
			end
		end)
	end)
end
