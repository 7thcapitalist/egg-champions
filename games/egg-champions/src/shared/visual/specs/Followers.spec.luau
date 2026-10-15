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
		it("puts a single pet straight behind the player", function()
			local o = Followers.offset(1, 1, 0)
			expect(o.x).toBeCloseTo(0)
			expect(o.z).toBeCloseTo(Followers.LOOK.behind)
		end)

		it("spreads a team on an arc behind, mirrored left and right", function()
			local left = Followers.offset(1, 3, 0)
			local middle = Followers.offset(2, 3, 0)
			local right = Followers.offset(3, 3, 0)
			expect(left.x < 0).toBeTrue()
			expect(right.x > 0).toBeTrue()
			expect(left.x).toBeCloseTo(-right.x)
			expect(middle.x).toBeCloseTo(0)
			for _, o in { left, middle, right } do
				expect(o.z > 0).toBeTrue()
			end
		end)

		it("bobs gently around the hover height", function()
			local look = Followers.LOOK
			for step = 0, 20 do
				local o = Followers.offset(1, 1, step * 0.1)
				expect(math.abs(o.y - look.hover) <= look.bob + 1e-6).toBeTrue()
			end
		end)
	end)

	describe("Followers.blend", function()
		it("closes none of the gap in no time and most of it in a second", function()
			expect(Followers.blend(0)).toEqual(0)
			expect(Followers.blend(1) > 0.9).toBeTrue()
			expect(Followers.blend(1) <= 1).toBeTrue()
		end)
	end)
end
