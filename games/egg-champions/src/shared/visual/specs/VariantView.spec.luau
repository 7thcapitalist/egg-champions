--!strict
local Runner = require(script.Parent.Parent.Parent.testing.Runner)
local Config = require(script.Parent.Parent.Parent.Config)
local EffectsBudget = require(script.Parent.Parent.EffectsBudget)

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

local SAFE = { "UIStroke", "UIGradient", "Frame", "ImageLabel" }

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
end
