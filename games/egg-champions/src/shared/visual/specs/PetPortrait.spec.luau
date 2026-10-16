--!strict
local Runner = require(script.Parent.Parent.Parent.testing.Runner)
local PetPortrait = require(script.Parent.Parent.PetPortrait)

local describe = Runner.describe
local it = Runner.it
local expect = Runner.expect

return function()
	describe("PetPortrait", function()
		it("views a pet from its front at a slight three-quarter angle", function()
			local x, y, z = PetPortrait.direction()
			expect(x > 0 and x < 0.4).toBeTrue()
			expect(y > 0 and y < 0.3).toBeTrue()
			expect(z < -0.9).toBeTrue()
			expect(math.abs(x * x + y * y + z * z - 1) < 0.0001).toBeTrue()
		end)

		it("fits tall, wide and deep models with margin", function()
			local sizes = { { 2, 8, 2 }, { 8, 2, 2 }, { 2, 2, 8 } }
			for _, size in sizes do
				local distance = PetPortrait.distance(size[1], size[2], size[3], 1)
				expect(distance > math.max(size[1], size[2], size[3]) / 2).toBeTrue()
				expect(PetPortrait.distance(size[1] * 2, size[2] * 2, size[3] * 2, 1)).toEqual(
					distance * 2
				)
			end
		end)

		it("moves back for narrow portrait cards", function()
			local square = PetPortrait.distance(4, 6, 3, 1)
			expect(PetPortrait.distance(4, 6, 3, 0.5) > square).toBeTrue()
			expect(PetPortrait.distance(4, 6, 3, 2) <= square).toBeTrue()
		end)

		it("rejects unusable bounds or aspect ratios", function()
			expect(PetPortrait.distance(0, 1, 1, 1)).toEqual(0)
			expect(PetPortrait.distance(1, 1, 1, 0)).toEqual(0)
			expect(PetPortrait.distance(1, 1, 1, 0 / 0)).toEqual(0)
			expect(PetPortrait.distance(math.huge, 1, 1, 1)).toEqual(0)
		end)
	end)
end
