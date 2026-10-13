--!strict
local Runner = require(script.Parent.Parent.Parent.testing.Runner)
local Config = require(script.Parent.Parent.Parent.Config)
local Battle = require(script.Parent.Parent.Parent.rules.Battle)
local Hatch = require(script.Parent.Parent.Parent.rules.Hatch)
local EffectsBudget = require(script.Parent.Parent.EffectsBudget)
local BattleEffects = require(script.Parent.Parent.BattleEffects)

local describe = Runner.describe
local it = Runner.it
local expect = Runner.expect

local C = Config.constants
local B = EffectsBudget.BATTLE

-- A type other than `typeId`, for an Off-type pet.
local function otherType(typeId: string): string
	for _, row in Config.types do
		if row.id ~= typeId then
			return row.id
		end
	end
	error("config needs at least two types")
end

-- A team member for each special in config, cycling through the types, the
-- same FighterSpec shape the task 05 specs build battles from.
local function fighters(
	stats: { hp: number, attack: number, speed: number }
): { Battle.FighterSpec }
	local list = {}
	for index, row in Config.specials do
		local typeId = Config.types[(index - 1) % #Config.types + 1].id
		table.insert(list, {
			pet = nil,
			variant = nil,
			type = typeId,
			hp = stats.hp,
			attack = stats.attack,
			speed = stats.speed + index,
			special = row.id,
			offType = if row.kind == "offtype" then otherType(typeId) else nil,
		})
	end
	return list
end

-- Splits all specials into teams of team_size, so every special fights.
local function teams(
	stats: { hp: number, attack: number, speed: number }
): { { Battle.FighterSpec } }
	local all = fighters(stats)
	local out = {}
	local size = C.team_size
	for start = 1, #all, size do
		local team = {}
		for i = start, math.min(start + size - 1, #all) do
			table.insert(team, all[i])
		end
		table.insert(out, team)
	end
	return out
end

-- Records the full event list of a battle played by the rules, the player
-- using its special whenever it is ready.
local function record(
	playerTeam: { Battle.FighterSpec },
	leaderTeam: { Battle.FighterSpec },
	seed: number
): { Battle.Event }
	local state = Battle.start(playerTeam, leaderTeam, 0, Hatch.seededRng(seed))
	local all: { Battle.Event } = {}
	while Battle.isOver(state) == nil do
		assert(state.turn < 500, "recorded battle did not finish")
		local move = if Battle.canUseSpecial(state) then Battle.SPECIAL else Battle.BASIC
		local events
		state, events = Battle.takeTurn(state, move)
		for _, event in events do
			table.insert(all, event)
		end
	end
	return all
end

-- Battles that between them use every special and end in both a win and a
-- loss, so every event kind the rules emit shows up.
local function recordedBattles(): { { Battle.Event } }
	local battles = {}
	local strong = teams({ hp = 400, attack = 60, speed = 20 })
	local weak = teams({ hp = 120, attack = 12, speed = 2 })
	for i, team in strong do
		local opponent = weak[(i % #weak) + 1]
		table.insert(battles, record(team, opponent, 10 + i))
		table.insert(battles, record(opponent, team, 20 + i))
	end
	return battles
end

-- A short battle written out by hand in the event shape Battle.takeTurn
-- returns: a guard, a strong Smash, a drain, a rush, a faint and a win.
local HAND_RECORDED: { { [string]: any } } = {
	{ kind = "guard", side = "player", pet = 1, special = "guard", value = 0.5 },
	{
		kind = "attack",
		side = "leader",
		pet = 1,
		move = 2,
		special = "smash",
		moveType = "fire",
		power = 80,
	},
	{
		kind = "damage",
		side = "player",
		pet = 1,
		amount = 30,
		hp = 70,
		maxHp = 100,
		typeBonus = 1,
		guarded = true,
	},
	{
		kind = "attack",
		side = "player",
		pet = 1,
		move = 2,
		special = "drain",
		moveType = "grass",
		power = 50,
	},
	{
		kind = "damage",
		side = "leader",
		pet = 1,
		amount = 40,
		hp = 60,
		maxHp = 100,
		typeBonus = C.type_bonus_strong,
		guarded = false,
	},
	{
		kind = "heal",
		side = "player",
		pet = 1,
		special = "drain",
		amount = 20,
		hp = 90,
		maxHp = 100,
	},
	{ kind = "rush", side = "leader", pet = 1, special = "rush", value = 0.5, speed = 15 },
	{ kind = "faint", side = "leader", pet = 1 },
	{ kind = "switch", side = "leader", pet = 2 },
	{ kind = "win", side = "player" },
}

return function()
	describe("BattleEffects registry", function()
		it("registers a visual for every special id in config", function()
			expect(#Config.specials > 0).toBeTrue()
			for _, row in Config.specials do
				local visual = BattleEffects.specialVisual(row.id)
				if visual == nil then
					error("special " .. row.id .. " has no battle visual")
				end
				expect(visual.burstScale > 0).toBeTrue()
			end
		end)

		it("gives every type id in config a burst color", function()
			expect(#Config.types > 0).toBeTrue()
			for _, row in Config.types do
				if BattleEffects.BURST_COLORS[row.id] == nil then
					error("type " .. row.id .. " has no burst color")
				end
			end
		end)

		it("keeps all six specials visually distinct", function()
			local seen: { [string]: string } = {}
			for _, row in Config.specials do
				local visual = BattleEffects.specialVisual(row.id) :: BattleEffects.SpecialVisual
				local key = visual.visual .. ":" .. tostring(visual.burstScale)
				expect(seen[key]).toEqual(nil)
				seen[key] = row.id
			end
		end)

		it("has a handler and a duration for every event kind the rules emit", function()
			expect(BattleEffects.unhandledKinds()).toEqual({})
			for _, kind in Battle.EVENT_KINDS do
				expect(EffectsBudget.BATTLE_SECONDS[kind] ~= nil).toBeTrue()
			end
		end)
	end)

	describe("BattleEffects dispatcher", function()
		it("handles every event in battles recorded from the rules", function()
			local seenKinds: { [string]: boolean } = {}
			for _, events in recordedBattles() do
				local dispatcher = BattleEffects.newDispatcher()
				for _, event in events do
					local cue = BattleEffects.cue(dispatcher, event)
					if cue == nil then
						error("no effect for event kind " .. tostring(event.kind))
					end
					expect(cue.seconds).toEqual(EffectsBudget.BATTLE_SECONDS[event.kind])
					seenKinds[event.kind] = true
				end
			end
			-- The recording is wide enough to prove the point: every kind
			-- the rules can emit appeared at least once.
			for _, kind in Battle.EVENT_KINDS do
				if not seenKinds[kind] then
					error("the recorded battles never produced a " .. kind .. " event")
				end
			end
		end)

		it("handles every event in the hand recorded battle", function()
			local dispatcher = BattleEffects.newDispatcher()
			local cues = {}
			for _, event in HAND_RECORDED do
				local cue = BattleEffects.cue(dispatcher, event)
				expect(cue ~= nil).toBeTrue()
				table.insert(cues, cue :: BattleEffects.Cue)
			end
			expect(cues[1].shieldUp).toBeTrue()
			expect(cues[2].hop).toBeTrue()
			expect(cues[3].shieldBreak).toBeTrue()
			expect(cues[3].burst ~= nil).toBeTrue()
			expect(cues[5].number ~= nil and cues[5].number.strong).toBeTrue()
			expect(cues[6].streamFrom).toEqual("leader")
			expect(cues[7].speedLines).toBeTrue()
			expect(cues[8].faint).toBeTrue()
			expect(cues[9].enter).toBeTrue()
			expect(cues[10].kind).toEqual("win")
		end)

		it("returns nil for an event kind it does not know", function()
			local dispatcher = BattleEffects.newDispatcher()
			expect(BattleEffects.cue(dispatcher, { kind = "dance", side = "player" })).toEqual(nil)
			expect(BattleEffects.cue(dispatcher, "not an event")).toEqual(nil)
		end)

		it("reads a strong hit from the event, never from the matchup", function()
			local dispatcher = BattleEffects.newDispatcher()
			BattleEffects.cue(dispatcher, { kind = "attack", side = "player", moveType = "fire" })
			local plain = BattleEffects.cue(
				dispatcher,
				{ kind = "damage", side = "leader", amount = 10, typeBonus = 1 }
			) :: BattleEffects.Cue
			expect((plain.number :: BattleEffects.Number).strong).toBeFalse()
			BattleEffects.cue(dispatcher, { kind = "attack", side = "player", moveType = "fire" })
			local strong = BattleEffects.cue(
				dispatcher,
				{ kind = "damage", side = "leader", amount = 10, typeBonus = C.type_bonus_strong }
			) :: BattleEffects.Cue
			expect((strong.number :: BattleEffects.Number).strong).toBeTrue()
		end)

		it("colors the burst by the move type and scales it for Smash and Off-type", function()
			for _, row in Config.types do
				local dispatcher = BattleEffects.newDispatcher()
				BattleEffects.cue(
					dispatcher,
					{ kind = "attack", side = "player", moveType = row.id }
				)
				local cue = BattleEffects.cue(
					dispatcher,
					{ kind = "damage", side = "leader", amount = 1, typeBonus = 1 }
				) :: BattleEffects.Cue
				local burst = cue.burst :: BattleEffects.Burst
				expect(burst.color).toEqual(BattleEffects.BURST_COLORS[row.id])
				expect(burst.scale).toEqual(1)
			end
			local dispatcher = BattleEffects.newDispatcher()
			BattleEffects.cue(
				dispatcher,
				{ kind = "attack", side = "player", special = "off_type", moveType = "water" }
			)
			local off = BattleEffects.cue(
				dispatcher,
				{ kind = "damage", side = "leader", amount = 1, typeBonus = 1 }
			) :: BattleEffects.Cue
			local offBurst = off.burst :: BattleEffects.Burst
			expect(offBurst.color).toEqual(BattleEffects.BURST_COLORS.water)
			expect(offBurst.scale > 1).toBeTrue()
			BattleEffects.cue(
				dispatcher,
				{ kind = "attack", side = "player", special = "smash", moveType = "fire" }
			)
			local smash = BattleEffects.cue(
				dispatcher,
				{ kind = "damage", side = "leader", amount = 1, typeBonus = 1 }
			) :: BattleEffects.Cue
			expect((smash.burst :: BattleEffects.Burst).scale > 1).toBeTrue()
		end)

		it("holds the guard shield until the hit it absorbs", function()
			local dispatcher = BattleEffects.newDispatcher()
			BattleEffects.cue(dispatcher, { kind = "guard", side = "player", special = "guard" })
			BattleEffects.cue(dispatcher, { kind = "attack", side = "player", moveType = "fire" })
			local other = BattleEffects.cue(
				dispatcher,
				{ kind = "damage", side = "leader", amount = 1, typeBonus = 1, guarded = false }
			) :: BattleEffects.Cue
			expect(other.shieldBreak).toBeFalse()
			BattleEffects.cue(dispatcher, { kind = "attack", side = "leader", moveType = "fire" })
			local absorbed = BattleEffects.cue(
				dispatcher,
				{ kind = "damage", side = "player", amount = 1, typeBonus = 1, guarded = true }
			) :: BattleEffects.Cue
			expect(absorbed.shieldBreak).toBeTrue()
		end)

		it("shows crosses for Heal and a stream from the target for Drain", function()
			local dispatcher = BattleEffects.newDispatcher()
			local healCue = BattleEffects.cue(
				dispatcher,
				{ kind = "heal", side = "leader", special = "heal", amount = 5 }
			) :: BattleEffects.Cue
			expect(healCue.crosses).toBeTrue()
			expect(healCue.streamFrom).toEqual(nil)
			local drainCue = BattleEffects.cue(
				dispatcher,
				{ kind = "heal", side = "leader", special = "drain", amount = 5 }
			) :: BattleEffects.Cue
			expect(drainCue.crosses).toBeFalse()
			expect(drainCue.streamFrom).toEqual("player")
		end)
	end)

	describe("Battle effect timing", function()
		local S = EffectsBudget.BATTLE_SECONDS

		it("fits every animation inside its event's row, so nothing overlaps", function()
			expect(B.hopSeconds * 2 <= S.attack).toBeTrue()
			expect(B.flashSeconds <= S.damage).toBeTrue()
			expect(B.shakeSeconds * 2 * B.shakes <= S.damage).toBeTrue()
			expect(B.burstLifetime <= S.damage).toBeTrue()
			expect(B.numberSeconds <= S.damage).toBeTrue()
			expect(B.shieldBreakSeconds <= S.damage).toBeTrue()
			expect(B.numberSeconds <= S.heal).toBeTrue()
			expect(B.crossSeconds <= S.heal).toBeTrue()
			expect(B.streamSeconds + B.streamStagger * (B.streamDots - 1) <= S.heal).toBeTrue()
			expect(B.shieldInSeconds <= S.guard).toBeTrue()
			expect(B.speedLineSeconds <= S.rush).toBeTrue()
			expect(B.faintSeconds <= S.faint).toBeTrue()
			expect(B.enterSeconds <= S.switch).toBeTrue()
		end)

		it("keeps a typical turn at the 2.8 seconds task 13 paced battles at", function()
			expect(EffectsBudget.typicalTurnSeconds()).toBeCloseTo(2.8)
		end)

		it("gives an unknown event kind the shortest duration", function()
			local shortest = math.huge
			for _, seconds in S do
				shortest = math.min(shortest, seconds)
			end
			expect(EffectsBudget.battleSeconds("dance")).toEqual(shortest)
		end)

		it("keeps piece counts within their pools", function()
			expect(B.burstParticles <= B.dotPool).toBeTrue()
			expect(B.streamDots <= B.dotPool).toBeTrue()
			expect(B.speedLines <= B.barPool).toBeTrue()
			expect(B.crosses + 1 <= B.labelPool).toBeTrue()
		end)
	end)
end
