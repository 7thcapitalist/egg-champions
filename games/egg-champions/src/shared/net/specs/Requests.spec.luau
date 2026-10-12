--!strict
local Runner = require(script.Parent.Parent.Parent.testing.Runner)
local Requests = require(script.Parent.Parent.Requests)
local Remotes = require(script.Parent.Parent.Parent.Remotes)

local describe = Runner.describe
local it = Runner.it
local expect = Runner.expect

local reasons = Requests.reasons

local function session(ownerId: number, ended: boolean, specialReady: boolean): Requests.SessionView
	return { ownerId = ownerId, ended = ended, specialReady = specialReady }
end

return function()
	describe("Remotes", function()
		it("names every remote the server and client share", function()
			local expected = {
				"Click",
				"BuyEgg",
				"Equip",
				"Unequip",
				"PayGymFee",
				"StartBattle",
				"BattleMove",
				"GiveUp",
				"Rebirth",
				"ProfileChanged",
			}
			local names = {}
			for _, entry in Remotes.list do
				table.insert(names, entry.name)
			end
			expect(names).toEqual(expected)
			for _, name in expected do
				expect((Remotes.names :: any)[name]).toEqual(name)
			end
		end)

		it("makes the pushes events and the requests with answers functions", function()
			expect(Remotes.kindOf("Click")).toEqual("event")
			expect(Remotes.kindOf("ProfileChanged")).toEqual("event")
			expect(Remotes.kindOf("BuyEgg")).toEqual("function")
			expect(Remotes.kindOf("BattleMove")).toEqual("function")
			expect(Remotes.kindOf("NotARemote")).toEqual(nil)
		end)
	end)

	describe("Requests choices", function()
		local allowed = Requests.setOf({ "egg_a", "egg_b" })

		it("accepts a known choice", function()
			local ok, reason = Requests.checkChoice("egg_a", allowed)
			expect(ok).toBeTrue()
			expect(reason).toEqual(nil)
		end)

		it("rejects numbers, tables, nil and empty strings as choices", function()
			for _, value in { 5, {}, true, "" } do
				local ok, reason = Requests.checkChoice(value, allowed)
				expect(ok).toBeFalse()
				expect(reason).toEqual(reasons.badChoice)
			end
			local ok, reason = Requests.checkChoice(nil, allowed)
			expect(ok).toBeFalse()
			expect(reason).toEqual(reasons.badChoice)
		end)

		it("rejects an overlong string before looking it up", function()
			local long = string.rep("x", Requests.MAX_CHOICE_LENGTH + 1)
			local ok, reason = Requests.checkChoice(long, Requests.setOf({ long }))
			expect(ok).toBeFalse()
			expect(reason).toEqual(reasons.badChoice)
		end)

		it("rejects an unknown choice", function()
			local ok, reason = Requests.checkChoice("egg_z", allowed)
			expect(ok).toBeFalse()
			expect(reason).toEqual(reasons.unknownChoice)
		end)
	end)

	describe("Requests battle moves", function()
		it("accepts move 1 and a ready move 2 from the owner", function()
			expect((Requests.checkMove(session(7, false, true), 7, 1))).toBeTrue()
			expect((Requests.checkMove(session(7, false, true), 7, 2))).toBeTrue()
		end)

		it("rejects a missing session", function()
			local ok, reason = Requests.checkMove(nil, 7, 1)
			expect(ok).toBeFalse()
			expect(reason).toEqual(reasons.noSession)
		end)

		it("rejects a session another player owns", function()
			local ok, reason = Requests.checkMove(session(8, false, true), 7, 1)
			expect(ok).toBeFalse()
			expect(reason).toEqual(reasons.notOwner)
		end)

		it("rejects a session that has ended", function()
			local ok, reason = Requests.checkMove(session(7, true, true), 7, 1)
			expect(ok).toBeFalse()
			expect(reason).toEqual(reasons.sessionEnded)
		end)

		it("checks a session on its own for giving up", function()
			expect((Requests.checkSession(session(7, false, false), 7))).toBeTrue()
			local ok, reason = Requests.checkSession(session(7, true, false), 7)
			expect(ok).toBeFalse()
			expect(reason).toEqual(reasons.sessionEnded)
			ok, reason = Requests.checkSession(session(8, false, false), 7)
			expect(ok).toBeFalse()
			expect(reason).toEqual(reasons.notOwner)
		end)

		it("rejects any move but 1 or 2", function()
			for _, move in { 0, 3, 1.5, -1, "1", nil, {} } do
				local ok, reason = Requests.checkMove(session(7, false, true), 7, move)
				expect(ok).toBeFalse()
				expect(reason).toEqual(reasons.badMove)
			end
		end)

		it("rejects move 2 on cooldown but still allows move 1", function()
			local ok, reason = Requests.checkMove(session(7, false, false), 7, 2)
			expect(ok).toBeFalse()
			expect(reason).toEqual(reasons.onCooldown)
			expect((Requests.checkMove(session(7, false, false), 7, 1))).toBeTrue()
		end)
	end)

	describe("Requests rate limiter", function()
		it("allows up to the limit in one window and drops the rest", function()
			local limiter = Requests.newRateLimiter(3, 1)
			for _ = 1, 3 do
				expect((Requests.allow(limiter, "a", 10))).toBeTrue()
			end
			local ok, dropped = Requests.allow(limiter, "a", 10.5)
			expect(ok).toBeFalse()
			expect(dropped).toEqual(1)
			ok, dropped = Requests.allow(limiter, "a", 10.9)
			expect(ok).toBeFalse()
			expect(dropped).toEqual(2)
		end)

		it("starts a fresh window once the old one passes", function()
			local limiter = Requests.newRateLimiter(1, 1)
			expect((Requests.allow(limiter, "a", 10))).toBeTrue()
			expect((Requests.allow(limiter, "a", 10.5))).toBeFalse()
			expect((Requests.allow(limiter, "a", 11))).toBeTrue()
		end)

		it("counts each key on its own", function()
			local limiter = Requests.newRateLimiter(1, 1)
			expect((Requests.allow(limiter, "a", 10))).toBeTrue()
			expect((Requests.allow(limiter, "b", 10))).toBeTrue()
			expect((Requests.allow(limiter, "a", 10))).toBeFalse()
			Requests.forget(limiter, "a")
			expect((Requests.allow(limiter, "a", 10))).toBeTrue()
		end)

		it("refuses a limiter that could never allow anything", function()
			expect(function()
				Requests.newRateLimiter(0, 1)
			end).toThrow("limit")
		end)
	end)
end
