--!strict
local Runner = require(script.Parent.Parent.Parent.testing.Runner)
local Config = require(script.Parent.Parent.Parent.Config)
local PetLook = require(script.Parent.Parent.PetLook)
local EffectsBudget = require(script.Parent.Parent.EffectsBudget)
local Pool = require(script.Parent.Parent.Pool)

local describe = Runner.describe
local it = Runner.it
local expect = Runner.expect

local function isChannel(value: any): boolean
	return type(value) == "number" and value >= 0 and value <= 255
end

local function ordered(): { Config.Rarity }
	local list = table.clone(Config.rarities)
	table.sort(list, function(a, b)
		return a.order < b.order
	end)
	return list
end

return function()
	describe("EffectsBudget", function()
		it("gives every rarity id in config a reveal duration and a color", function()
			expect(#Config.rarities > 0).toBeTrue()
			for _, rarity in Config.rarities do
				local timing = EffectsBudget.hatch[rarity.id]
				expect(timing ~= nil).toBeTrue()
				expect(type(timing.total) == "number" and timing.total > 0).toBeTrue()
				expect(timing.rays > 0).toBeTrue()
				local color = EffectsBudget.rarityColor(rarity.id)
				expect(isChannel(color.r) and isChannel(color.g) and isChannel(color.b)).toBeTrue()
			end
		end)

		it("uses the same rarity colors as the UI stripe", function()
			for _, rarity in Config.rarities do
				local reveal = EffectsBudget.rarityColor(rarity.id)
				local stripe = PetLook.rarityColor(rarity.id)
				expect({ reveal.r, reveal.g, reveal.b }).toEqual({ stripe.r, stripe.g, stripe.b })
			end
		end)

		it("makes higher rarities longer and brighter", function()
			local list = ordered()
			for i = 2, #list do
				local lower = EffectsBudget.hatch[list[i - 1].id]
				local higher = EffectsBudget.hatch[list[i].id]
				expect(higher.total > lower.total).toBeTrue()
				expect(higher.flashStrength >= lower.flashStrength).toBeTrue()
				expect(higher.rays >= lower.rays).toBeTrue()
			end
		end)

		it("shakes the egg three times", function()
			expect(EffectsBudget.HATCH.shakes).toEqual(3)
		end)

		it("plays a triple hatch in sequence, never overlapping", function()
			expect(EffectsBudget.HATCH.tripleMode).toEqual("sequence")
			local ids = { "common", "common", "common" }
			local one = EffectsBudget.hatchTiming("common").total
			expect(EffectsBudget.sequenceSeconds(ids)).toBeCloseTo(one * 3)
		end)

		it("gives an unknown rarity the lowest reveal instead of nil", function()
			local lowest = ordered()[1]
			expect(EffectsBudget.hatchTiming("not_a_rarity").total).toBeCloseTo(
				EffectsBudget.hatch[lowest.id].total
			)
		end)
	end)

	describe("Pool", function()
		it("never holds more click pops than its cap, however fast the clicks", function()
			local cap = EffectsBudget.CLICK.maxLive
			local made = 0
			local pool = Pool.new(cap, function(): { id: number }
				made += 1
				return { id = made }
			end)
			local recycled = 0
			for _ = 1, cap * 20 do
				local _, wasLive = Pool.acquire(pool)
				if wasLive then
					recycled += 1
				end
				expect(Pool.liveCount(pool) <= cap).toBeTrue()
				expect(Pool.size(pool) <= cap).toBeTrue()
			end
			expect(made).toEqual(cap)
			expect(recycled).toEqual(cap * 19)
		end)

		it("reuses released items instead of creating new ones", function()
			local made = 0
			local pool = Pool.new(4, function(): { id: number }
				made += 1
				return { id = made }
			end)
			for _ = 1, 100 do
				local item = Pool.acquire(pool)
				Pool.release(pool, item)
			end
			expect(made).toEqual(1)
			expect(Pool.liveCount(pool)).toEqual(0)
		end)

		it("ignores releasing an item twice", function()
			local pool = Pool.new(2, function(): { id: number }
				return { id = 1 }
			end)
			local item = Pool.acquire(pool)
			Pool.release(pool, item)
			Pool.release(pool, item)
			expect(#pool.free).toEqual(1)
		end)

		it("keeps at most max pending clicks and forgets stale ones", function()
			local queue = Pool.newQueue(3)
			for i = 1, 10 do
				Pool.push(queue, i, i)
			end
			expect(Pool.queued(queue)).toEqual(3)
			expect(Pool.take(queue, 10, 5)).toEqual(8)
			expect(Pool.take(queue, 100, 5)).toEqual(nil)
			expect(Pool.queued(queue)).toEqual(0)
		end)
	end)
end
