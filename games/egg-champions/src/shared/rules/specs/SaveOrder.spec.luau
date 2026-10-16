--!strict
local Runner = require(script.Parent.Parent.Parent.testing.Runner)
local SaveOrder = require(script.Parent.Parent.SaveOrder)

local describe = Runner.describe
local it = Runner.it
local expect = Runner.expect

return function()
	describe("save ordering", function()
		it(
			"waits for an in-flight autosave before release and rejects a delayed autosave",
			function()
				local state = SaveOrder.new()
				local stored = { coins = 10, jobId = "server-a" :: string? }
				-- The first autosave has acquired the key but has not finished.
				expect(SaveOrder.begin(state, false)).toEqual("run")
				expect(SaveOrder.begin(state, true)).toEqual("wait")
				expect(SaveOrder.begin(state, false)).toEqual("skip")
				stored.coins = 10
				SaveOrder.finish(state)
				-- The final save runs next and releases the key.
				expect(SaveOrder.begin(state, true)).toEqual("run")
				if SaveOrder.ownsSession(stored.jobId, "server-a") then
					stored.coins = 25
					stored.jobId = nil
				end
				SaveOrder.finish(state)
				-- An autosave scheduled before leave must not restore old coins or a lock.
				expect(SaveOrder.begin(state, false)).toEqual("skip")
				expect(stored.coins).toEqual(25)
				expect(stored.jobId).toEqual(nil)
			end
		)
		it("rejects a missing or foreign session lock before writing", function()
			expect(SaveOrder.ownsSession(nil, "server-a")).toBeFalse()
			expect(SaveOrder.ownsSession("server-b", "server-a")).toBeFalse()
			expect(SaveOrder.ownsSession("server-a", "server-a")).toBeTrue()
		end)
	end)
end
