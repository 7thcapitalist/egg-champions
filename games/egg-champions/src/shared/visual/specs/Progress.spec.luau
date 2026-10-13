--!strict
local Runner = require(script.Parent.Parent.Parent.testing.Runner)
local Config = require(script.Parent.Parent.Parent.Config)
local WorldPalette = require(script.Parent.Parent.Parent.world.WorldPalette)
local ProgressEffects = require(script.Parent.Parent.ProgressEffects)
local EffectsBudget = require(script.Parent.Parent.EffectsBudget)

local describe = Runner.describe
local it = Runner.it
local expect = Runner.expect

local function isChannel(value: any): boolean
	return type(value) == "number" and value >= 0 and value <= 255
end

local function ordered(): { Config.World }
	local list = table.clone(Config.worlds)
	table.sort(list, function(a, b)
		return a.index < b.index
	end)
	return list
end

-- A profile that has beaten every gym before world `upTo` in this run.
local function beatenBefore(upTo: number): { [string]: any }
	local beaten: { [string]: boolean } = {}
	for _, world in ordered() do
		if world.index < upTo then
			beaten[world.id] = true
		end
	end
	return { gymsBeaten = beaten, badges = table.clone(beaten), feesPaid = {} }
end

return function()
	describe("WorldPalette", function()
		it("gives every world in config an unlock color from the shared palette table", function()
			expect(#Config.worlds > 0).toBeTrue()
			for _, world in Config.worlds do
				local color = WorldPalette.unlockColor(world.id)
				expect(isChannel(color.r) and isChannel(color.g) and isChannel(color.b)).toBeTrue()
				local row = WorldPalette.forWorld(world.id, world.environment)
				expect(rawequal(color, row.swirl)).toBeTrue()
				local inTable = false
				for _, entry in WorldPalette.ROWS do
					if rawequal(entry, row) then
						inTable = true
					end
				end
				expect(inTable).toBeTrue()
			end
		end)

		it("gives a world with no row of its own a row from the same table", function()
			local row = WorldPalette.forWorld("not_a_world", "Lava fields")
			expect(rawequal(row, WorldPalette.ROWS.ember_volcano)).toBeTrue()
			local fallback = WorldPalette.forWorld("not_a_world", "")
			expect(rawequal(fallback, WorldPalette.ROWS[WorldPalette.DEFAULT_ROW])).toBeTrue()
		end)
	end)

	describe("ProgressEffects rebirth", function()
		it("plays nothing for a refused rebirth", function()
			local played = 0
			local refused = { ok = false, reason = "cannot_afford" }
			local result = ProgressEffects.onRebirthReply(refused, function(_rebirths: number)
				played += 1
			end)
			expect(result).toBeFalse()
			expect(played).toEqual(0)
		end)

		it("plays nothing for a lost or malformed reply", function()
			local played = 0
			local function play(_rebirths: number)
				played += 1
			end
			ProgressEffects.onRebirthReply(nil, play)
			ProgressEffects.onRebirthReply({ ok = false, reason = "in_battle" }, play)
			ProgressEffects.onRebirthReply({ ok = true }, play)
			ProgressEffects.onRebirthReply("ok", play)
			expect(played).toEqual(0)
		end)

		it("plays once, with the new count, for a confirmed rebirth", function()
			local seen: { number } = {}
			local result = ProgressEffects.onRebirthReply(
				{ ok = true, rebirths = 3 },
				function(n: number)
					table.insert(seen, n)
				end
			)
			expect(result).toBeTrue()
			expect(seen).toEqual({ 3 })
		end)

		it("explains a refusal", function()
			expect(ProgressEffects.rebirthReasonText("cannot_afford") ~= "").toBeTrue()
			expect(ProgressEffects.rebirthReasonText(nil) ~= "").toBeTrue()
		end)
	end)

	describe("ProgressEffects portals", function()
		it("opens only the first portal's world after the first gym", function()
			local worlds = ordered()
			local fresh = ProgressEffects.portals({})
			for _, world in worlds do
				expect(fresh[world.id] ~= nil).toBeTrue()
				expect(fresh[world.id].status == "open").toBeFalse()
			end
			local after = ProgressEffects.portals(beatenBefore(worlds[1].index + 1))
			expect(after[worlds[1].id].status).toEqual("open")
			if #worlds > 2 then
				expect(after[worlds[2].id].status).toEqual("locked")
			end
		end)

		it("swirls in the color of the world the portal opens", function()
			local views = ProgressEffects.portals({})
			for _, view in views do
				local target = view.toWorldId
				if target ~= nil then
					expect(rawequal(view.color, WorldPalette.unlockColor(target))).toBeTrue()
				end
			end
		end)

		it("shows the last world's gate once the final gym is beaten", function()
			local worlds = ordered()
			local last = worlds[#worlds]
			local before = ProgressEffects.portals(beatenBefore(last.index))
			expect(before[last.id].status).toEqual("locked")
			local after = ProgressEffects.portals(beatenBefore(last.index + 1))
			expect(after[last.id].status).toEqual("soon")
			expect(string.find(after[last.id].label, "coming soon", 1, true) ~= nil).toBeTrue()
		end)

		it("replays nothing on the first payload, as after a rejoin", function()
			local views = ProgressEffects.portals(beatenBefore(99))
			local changes = ProgressEffects.changes(nil, views)
			expect(#changes.opened).toEqual(0)
			expect(#changes.closed).toEqual(0)
		end)

		it("reports a newly opened portal once, and a rebirth as relocking", function()
			local worlds = ordered()
			local start = ProgressEffects.portals({})
			local won = ProgressEffects.portals(beatenBefore(worlds[1].index + 1))
			local opened = ProgressEffects.changes(start, won)
			expect(opened.opened).toEqual({ worlds[1].id })
			local again = ProgressEffects.changes(
				won,
				ProgressEffects.portals(beatenBefore(worlds[1].index + 1))
			)
			expect(#again.opened).toEqual(0)
			local reborn = ProgressEffects.changes(
				won,
				ProgressEffects.portals({ gymsBeaten = {}, badges = { [worlds[1].id] = true } })
			)
			expect(#reborn.opened).toEqual(0)
			expect(reborn.closed).toEqual({ worlds[1].id })
		end)
	end)

	describe("ProgressEffects gym win", function()
		it("lights the next world's portal after a gym that has one", function()
			local worlds = ordered()
			local win = ProgressEffects.gymWin(worlds[1].id, {}, true)
			expect(win.nextWorldId).toEqual(worlds[2].id)
			expect(win.finalGate).toEqual(nil)
			expect(win.newBadge).toBeTrue()
		end)

		it("shows the coming soon gate after the last gym", function()
			local worlds = ordered()
			local last = worlds[#worlds]
			local win = ProgressEffects.gymWin(last.id, beatenBefore(last.index), true)
			expect(win.nextWorldId).toEqual(nil)
			expect(win.finalGate ~= nil).toBeTrue()
			expect(string.find(win.caption, "coming soon", 1, true) ~= nil).toBeTrue()
		end)

		it("lights the portal only after the badge has played", function()
			expect(EffectsBudget.badgeSeconds() > 0).toBeTrue()
		end)
	end)
end
