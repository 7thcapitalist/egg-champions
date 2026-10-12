--!strict
local Runner = require(script.Parent.Parent.testing.Runner)
local Example = require(script.Parent.Example)

local describe = Runner.describe
local it = Runner.it
local expect = Runner.expect

return function()
	describe("Example", function()
		it("adds two numbers", function()
			expect(Example.add(2, 3)).toEqual(5)
		end)

		it("scales a list without changing the input", function()
			local input = { 1, 2, 3 }
			expect(Example.scale(input, 2)).toEqual({ 2, 4, 6 })
			expect(input).toEqual({ 1, 2, 3 })
		end)

		it("compares fractions with a margin", function()
			expect(Example.add(0.1, 0.2)).toBeCloseTo(0.3, 1e-9)
		end)

		it("throws on a bad argument", function()
			expect(function()
				Example.add(1, (nil :: any) :: number)
			end).toThrow()
		end)

		it("checks booleans", function()
			expect(Example.add(1, 1) == 2).toBeTrue()
			expect(Example.add(1, 1) == 3).toBeFalse()
		end)
	end)
end
