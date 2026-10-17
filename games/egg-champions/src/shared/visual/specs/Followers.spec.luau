--!strict
local Runner = require(script.Parent.Parent.Parent.testing.Runner)
local Followers = require(script.Parent.Parent.Followers)

local describe = Runner.describe
local it = Runner.it
local expect = Runner.expect

return function()
	describe("Followers.encode and decode", function()
		local pets = {
			{ uid = "a", petId = "puddlet", variant = "normal" },
			{ uid = "b", petId = "sparkit", variant = "shiny" },
			{ uid = "c", petId = "emberpup" },
		}

		it("writes the team in team order with each variant", function()
			expect(Followers.encode(pets, { "b", "a" })).toEqual("sparkit:shiny,puddlet:normal")
		end)

		it("skips team uids the player does not own", function()
			expect(Followers.encode(pets, { "zz", "c" })).toEqual("emberpup:")
		end)

		it("is empty for no team or bad input", function()
			expect(Followers.encode(pets, {})).toEqual("")
			expect(Followers.encode(nil, nil)).toEqual("")
		end)

		it("reads back what it wrote", function()
			local members = Followers.decode(Followers.encode(pets, { "a", "b", "c" }))
			expect(#members).toEqual(3)
			expect(members[1].petId).toEqual("puddlet")
			expect(members[2].variant).toEqual("shiny")
			expect(members[3].variant == nil).toBeTrue()
		end)

		it("treats anything but a string as no team", function()
			expect(#Followers.decode(nil)).toEqual(0)
			expect(#Followers.decode(5)).toEqual(0)
			expect(#Followers.decode("")).toEqual(0)
		end)
	end)

	describe("Followers.offset", function()
		it("keeps every pet off the camera line, at least 2.5 studs to the side", function()
			for count = 1, 6 do
				for index = 1, count do
					local o = Followers.offset(index, count, 0)
					expect(math.abs(o.x) >= 2.5).toBeTrue()
				end
			end
		end)

		it("alternates left and right, a little behind the player", function()
			local first = Followers.offset(1, 3, 0)
			local second = Followers.offset(2, 3, 0)
			local third = Followers.offset(3, 3, 0)
			expect(first.x < 0).toBeTrue()
			expect(second.x > 0).toBeTrue()
			expect(third.x < 0).toBeTrue()
			expect(first.x).toBeCloseTo(-second.x)
			expect(first.z >= 1 and first.z <= 2).toBeTrue()
			expect(second.z).toBeCloseTo(first.z)
			expect(third.z > first.z).toBeTrue()
		end)

		it("puts a single pet beside the player, not straight behind", function()
			local o = Followers.offset(1, 1, 0)
			expect(math.abs(o.x) >= 3 and math.abs(o.x) <= 4).toBeTrue()
			expect(o.z >= 1 and o.z <= 2).toBeTrue()
		end)

		it("bobs gently around the hover height", function()
			local look = Followers.LOOK
			for step = 0, 20 do
				local o = Followers.offset(1, 1, step * 0.1)
				expect(math.abs(o.y - look.hover) <= look.bob + 1e-6).toBeTrue()
			end
		end)
	end)

	describe("Followers size", function()
		it("is at most half a standard character", function()
			local look = Followers.LOOK
			expect(look.size <= look.characterHeight / 2 + 1e-6).toBeTrue()
			expect(look.size).toBeCloseTo(2.5)
		end)

		it("scales any model to the follower size", function()
			for _, largest in { 1, 2.5, 6, 12 } do
				expect(largest * Followers.scaleFor(largest)).toBeCloseTo(Followers.LOOK.size)
			end
		end)

		it("leaves a model with no size alone", function()
			expect(Followers.scaleFor(0)).toEqual(1)
			expect(Followers.scaleFor(-1)).toEqual(1)
			expect(Followers.scaleFor(0 / 0)).toEqual(1)
			expect(Followers.scaleFor(math.huge)).toEqual(1)
		end)
	end)

	describe("Followers.blend", function()
		it("closes none of the gap in no time and most of it in a second", function()
			expect(Followers.blend(0)).toEqual(0)
			expect(Followers.blend(1) > 0.9).toBeTrue()
			expect(Followers.blend(1) <= 1).toBeTrue()
		end)
	end)
	describe("distance-driven stride", function()
		it("holds the pose at rest and ignores a teleport", function()
			expect(Followers.stride(1.2, 0)).toEqual(1.2)
			expect(Followers.stride(1.2, 100)).toEqual(1.2)
		end)
		it("covers the same gait at different frame rates", function()
			local a, b = 0, 0
			for _ = 1, 30 do
				a = Followers.stride(a, 10 / 30)
			end
			for _ = 1, 144 do
				b = Followers.stride(b, 10 / 144)
			end
			expect(a).toBeCloseTo(b)
		end)
	end)
end
