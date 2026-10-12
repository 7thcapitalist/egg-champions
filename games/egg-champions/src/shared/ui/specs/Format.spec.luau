--!strict
local Runner = require(script.Parent.Parent.Parent.testing.Runner)
local Format = require(script.Parent.Parent.Format)

local describe = Runner.describe
local it = Runner.it
local expect = Runner.expect

return function()
	describe("Format.abbreviate", function()
		it("keeps numbers under a thousand whole", function()
			expect(Format.abbreviate(0)).toEqual("0")
			expect(Format.abbreviate(7)).toEqual("7")
			expect(Format.abbreviate(950)).toEqual("950")
			expect(Format.abbreviate(999)).toEqual("999")
		end)

		it("rounds fractions down", function()
			expect(Format.abbreviate(1.5)).toEqual("1")
			expect(Format.abbreviate(999.99)).toEqual("999")
		end)

		it("shortens thousands, millions and billions to one decimal", function()
			expect(Format.abbreviate(1200)).toEqual("1.2K")
			expect(Format.abbreviate(3400000)).toEqual("3.4M")
			expect(Format.abbreviate(5600000000)).toEqual("5.6B")
			expect(Format.abbreviate(7.8e12)).toEqual("7.8T")
		end)

		it("drops a trailing .0", function()
			expect(Format.abbreviate(1000)).toEqual("1K")
			expect(Format.abbreviate(50000)).toEqual("50K")
			expect(Format.abbreviate(2000000)).toEqual("2M")
		end)

		it("rounds down so it never shows more than there is", function()
			expect(Format.abbreviate(1250)).toEqual("1.2K")
			expect(Format.abbreviate(1999)).toEqual("1.9K")
			expect(Format.abbreviate(999999)).toEqual("999.9K")
			expect(Format.abbreviate(999999999)).toEqual("999.9M")
		end)

		it("moves to the next suffix at exactly a thousand of the last", function()
			expect(Format.abbreviate(1000000)).toEqual("1M")
			expect(Format.abbreviate(1000000000)).toEqual("1B")
		end)

		it("handles negatives and numbers past the last suffix", function()
			expect(Format.abbreviate(-1200)).toEqual("-1.2K")
			expect(Format.abbreviate(1e40)).toEqual("1.0e+40")
		end)
	end)

	describe("Format.commas", function()
		it("groups thousands", function()
			expect(Format.commas(0)).toEqual("0")
			expect(Format.commas(999)).toEqual("999")
			expect(Format.commas(1250)).toEqual("1,250")
			expect(Format.commas(50000)).toEqual("50,000")
			expect(Format.commas(1234567)).toEqual("1,234,567")
			expect(Format.commas(-1250.7)).toEqual("-1,250")
		end)
	end)
end
