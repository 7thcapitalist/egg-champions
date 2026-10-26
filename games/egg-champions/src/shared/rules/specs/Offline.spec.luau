--!strict
local Runner = require(script.Parent.Parent.Parent.testing.Runner)
local Offline = require(script.Parent.Parent.Offline)
local expect = Runner.expect
return function()
	Runner.describe("offline training", function()
		Runner.it("requires equipped pets and uses the configured fraction", function()
			expect(Offline.rate(400, true)).toEqual(100)
			expect(Offline.rate(400, false)).toEqual(0)
		end)
		Runner.it("rounds down and caps absence at two hours", function()
			local coins, seconds = Offline.reward({ at = 10, rate = 1.25 }, 10000)
			expect(coins).toEqual(9000)
			expect(seconds).toEqual(7200)
			local fractional = Offline.reward({ at = 10, rate = 1.25 }, 13)
			expect(fractional).toEqual(3)
		end)
		Runner.it("refuses future malformed negative and non-finite snapshots", function()
			for _, data in
				{
					false,
					{ at = 100, rate = 2 },
					{ at = -1, rate = 2 },
					{ at = 0, rate = -1 },
					{ at = 0, rate = math.huge },
					{ at = 0, rate = 0 / 0 },
					{ at = "0", rate = 2 },
				}
			do
				local coins = Offline.reward(data, 10)
				expect(coins).toEqual(0)
			end
			expect(Offline.reward(nil, 10)).toEqual(0)
		end)
	end)
end
