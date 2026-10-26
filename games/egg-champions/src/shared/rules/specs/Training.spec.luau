--!strict
local Runner = require(script.Parent.Parent.Parent.testing.Runner)
local Training = require(script.Parent.Parent.Training)
local expect = Runner.expect
return function()
	Runner.describe("training eligibility and rewards", function()
		Runner.it("pays four times per second without accumulating scheduler drift", function()
			local clock: Training.Clock = {}
			Training.step(clock, "meadow", 0)
			local payments = 0
			for _, now in { 0.27, 0.51, 0.76, 1.02 } do
				if Training.step(clock, "meadow", now) then
					payments += 1
				end
			end
			expect(payments).toEqual(4)
			expect(clock.nextAt).toEqual(1.25)
			expect(payments * Training.hits(false)).toEqual(16)
		end)
		Runner.it("requires a full dwell and discards lag backlog and partial exits", function()
			local clock: Training.Clock = {}
			expect(Training.step(clock, "meadow", 0)).toBeFalse()
			expect(Training.step(clock, "meadow", 0.249)).toBeFalse()
			expect(Training.step(clock, "meadow", 0.25)).toBeTrue()
			expect(Training.step(clock, "meadow", 100)).toBeTrue()
			expect(Training.step(clock, "meadow", 100)).toBeFalse()
			expect(Training.step(clock, nil, 100.5)).toBeFalse()
			expect(Training.step(clock, "meadow", 100.6)).toBeFalse()
			expect(Training.step(clock, "coast", 101.6)).toBeFalse()
		end)
		Runner.it("checks height horizontal boundary alive battle and unlock", function()
			local center = { x = 0, y = 0, z = 0 }
			expect(Training.inRange({ x = 12, y = 8, z = 0 }, center)).toBeTrue()
			expect(Training.inRange({ x = 12.01, y = 0, z = 0 }, center)).toBeFalse()
			expect(Training.inRange({ x = 0, y = 8.01, z = 0 }, center)).toBeFalse()
			local state = { gymsBeaten = {} }
			expect(Training.allowed(state, 1, true, false)).toBeTrue()
			expect(Training.allowed(state, 2, true, false)).toBeFalse()
			expect(Training.allowed(state, 1, false, false)).toBeFalse()
			expect(Training.allowed(state, 1, true, true)).toBeFalse()
			expect(Training.hits(false)).toEqual(4)
			expect(Training.hits(true)).toEqual(5)
		end)
	end)
end
