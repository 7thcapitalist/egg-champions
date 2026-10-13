--!strict
local Runner = require(script.Parent.Runner)

local describe = Runner.describe
local it = Runner.it
local expect = Runner.expect

local nan = 0 / 0
local inf = math.huge

return function()
	describe("Runner.expect.toBeCloseTo", function()
		it("passes for finite numbers within the margin", function()
			expect(0.1 + 0.2).toBeCloseTo(0.3)
			expect(10).toBeCloseTo(10.5, 1)
		end)

		it("fails for finite numbers outside the margin", function()
			expect(function()
				expect(1).toBeCloseTo(2, 0.5)
			end).toThrow("toBeCloseTo failed")
		end)

		it("fails when the value is NaN", function()
			expect(function()
				expect(nan).toBeCloseTo(0, 1)
			end).toThrow("NaN and infinity are never close")
		end)

		it("fails when the expected value is NaN", function()
			expect(function()
				expect(0).toBeCloseTo(nan, 1)
			end).toThrow("NaN and infinity are never close")
		end)

		it("fails when either value is infinite", function()
			expect(function()
				expect(inf).toBeCloseTo(inf, 1)
			end).toThrow("NaN and infinity are never close")
			expect(function()
				expect(-inf).toBeCloseTo(0, 1)
			end).toThrow("NaN and infinity are never close")
			expect(function()
				expect(0).toBeCloseTo(inf, 1)
			end).toThrow("NaN and infinity are never close")
		end)

		it("fails when the margin is NaN or infinite", function()
			expect(function()
				expect(1).toBeCloseTo(2, inf)
			end).toThrow("NaN and infinity are never close")
			expect(function()
				expect(1).toBeCloseTo(2, nan)
			end).toThrow("NaN and infinity are never close")
		end)

		it("fails when the value is not a number", function()
			expect(function()
				expect("1").toBeCloseTo(1, 1)
			end).toThrow("toBeCloseTo failed")
		end)
	end)
end
