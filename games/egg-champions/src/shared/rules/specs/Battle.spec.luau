--!strict
local Runner = require(script.Parent.Parent.Parent.testing.Runner)
local Config = require(script.Parent.Parent.Parent.Config)
local Battle = require(script.Parent.Parent.Battle)
local Gym = require(script.Parent.Parent.Gym)
local Hatch = require(script.Parent.Parent.Hatch)

local describe = Runner.describe
local it = Runner.it
local expect = Runner.expect

local EPSILON = 1e-9

-- Battles per gym in the win-rate check, and how far the measured rate may
-- sit from the tuner's recorded reference_win_rate_at_target. The tuner
-- measured 3000 battles, so its own standard error near 0.8 is about 0.007;
-- 2000 battles here add about 0.009. A tolerance of 0.05 is over 4 standard
-- errors of the difference, so only a real rules mismatch fails it.
local WIN_RATE_BATTLES = 2000
local WIN_RATE_TOLERANCE = 0.05

-- The tuner's player only uses Heal below this share of max HP. It is the
-- simulator's own setting (SIM heal_below_hp), copied for the policy below.
local POLICY_HEAL_BELOW = 0.6

local C = Config.constants

-- An rng that always returns the same draw in [0, 1).
local function fixedRng(u: number): Battle.Rng
	return {
		NextNumber = function(_self: any): number
			return u
		end,
	}
end

local function randomAt(u: number): number
	return C.damage_random_min + (C.damage_random_max - C.damage_random_min) * u
end

local function special(id: string): Config.Special
	return Config.specialById[id]
end

-- Two types with no bonus either way, so a test can isolate one effect.
local function neutralPair(): (string, string)
	for _, a in Config.types do
		for _, b in Config.types do
			if Battle.typeBonus(a.id, b.id) == 1 and Battle.typeBonus(b.id, a.id) == 1 then
				return a.id, b.id
			end
		end
	end
	error("no neutral type pair in config")
end

local function fighter(fields: {
	type: string,
	hp: number?,
	attack: number?,
	speed: number?,
	special: string?,
	offType: string?,
	variant: string?,
}): Battle.FighterSpec
	return {
		pet = nil,
		variant = fields.variant,
		type = fields.type,
		hp = fields.hp or 1000,
		attack = fields.attack or 20,
		speed = fields.speed or 10,
		special = fields.special or "smash",
		offType = fields.offType,
	}
end

local function firstOf(events: { Battle.Event }, kind: string, side: string?): Battle.Event?
	for _, event in events do
		if event.kind == kind and (side == nil or event.side == side) then
			return event
		end
	end
	return nil
end

local function mustFind(events: { Battle.Event }, kind: string, side: string?): Battle.Event
	local event = firstOf(events, kind, side)
	if event == nil then
		error(string.format("no %s event for %s", kind, tostring(side)))
	end
	return event
end

-- A one on one battle with neutral types, the player faster, and the leader
-- held on its basic attack, so only the player's special matters.
local function duel(playerSpecial: string, playerFields: { [string]: any }?): Battle.State
	local pType, lType = neutralPair()
	local fields: { [string]: any } = { type = pType, special = playerSpecial, speed = 12 }
	for key, value in playerFields or {} do
		fields[key] = value
	end
	local state = Battle.start(
		{ fighter(fields :: any) },
		{ fighter({ type = lType, speed = 10, attack = 30 }) },
		0,
		fixedRng(0.5)
	)
	state.leader.fighters[1].cooldown = math.huge
	return state
end

-- The tuner's player policy (simulate_economy.py player_wants_special).
local function policy(state: Battle.State): number
	local p = Battle.activeFighter(state, "player") :: Battle.Fighter
	local l = Battle.activeFighter(state, "leader") :: Battle.Fighter
	if p.cooldown > 0 then
		return Battle.BASIC
	end
	local row = special(p.special)
	local kind = row.kind
	local use = false
	if kind == "attack" or kind == "drain" then
		use = true
	elseif kind == "offtype" then
		use = row.power * Battle.typeBonus(p.offType :: string, l.type)
			> C.basic_move_power * Battle.typeBonus(p.type, l.type)
	elseif kind == "heal" then
		use = p.hp < POLICY_HEAL_BELOW * p.maxHp
	elseif kind == "guard" then
		if p.guard == nil then
			use = if p.speed >= l.speed then l.cooldown == 0 else l.cooldown == 1
		end
	elseif kind == "speed" then
		use = p.speed < l.speed
	end
	return if use then Battle.SPECIAL else Battle.BASIC
end

local function playOut(state: Battle.State, maxTurns: number): (Battle.State, { Battle.Event })
	local all: { Battle.Event } = {}
	local current = state
	while Battle.isOver(current) == nil do
		if current.turn >= maxTurns then
			error("battle did not finish in " .. maxTurns .. " turns")
		end
		local events
		current, events = Battle.takeTurn(current, policy(current))
		for _, event in events do
			table.insert(all, event)
		end
	end
	return current, all
end

-- One test per special, keyed by config id. The coverage test below checks
-- these keys against config/specials.json.
local SPECIAL_TESTS: { [string]: () -> () } = {
	smash = function()
		local row = special("smash")
		local state = duel("smash")
		local p = state.player.fighters[1]
		local l = state.leader.fighters[1]
		local _, events = Battle.takeTurn(state, Battle.SPECIAL)
		local attack = mustFind(events, "attack", "player")
		expect(attack.special).toEqual("smash")
		expect(attack.power).toEqual(row.power)
		local damage = mustFind(events, "damage", "leader")
		local expected = p.attack * (row.power / C.basic_move_power) * randomAt(0.5)
		expect(damage.amount).toBeCloseTo(expected, EPSILON)
		expect(damage.hp).toBeCloseTo(l.maxHp - expected, EPSILON)
	end,

	drain = function()
		local row = special("drain")
		local state = duel("drain")
		local p = state.player.fighters[1]
		p.hp = p.maxHp / 2
		local next, events = Battle.takeTurn(state, Battle.SPECIAL)
		local damage = mustFind(events, "damage", "leader")
		local expected = p.attack * (row.power / C.basic_move_power) * randomAt(0.5)
		expect(damage.amount).toBeCloseTo(expected, EPSILON)
		local healEvent = mustFind(events, "heal", "player")
		expect(healEvent.amount).toBeCloseTo(row.value * expected, EPSILON)
		-- The leader's basic hit lands after the drain.
		local hitBack = mustFind(events, "damage", "player")
		expect(next.player.fighters[1].hp).toBeCloseTo(
			p.maxHp / 2 + row.value * expected - (hitBack.amount :: number),
			EPSILON
		)
	end,

	heal = function()
		local row = special("heal")
		local state = duel("heal")
		local p = state.player.fighters[1]
		p.hp = p.maxHp / 4
		local _, events = Battle.takeTurn(state, Battle.SPECIAL)
		local healEvent = mustFind(events, "heal", "player")
		expect(healEvent.special).toEqual("heal")
		expect(healEvent.amount).toBeCloseTo(row.value * p.maxHp, EPSILON)
		expect(healEvent.hp).toBeCloseTo(p.maxHp / 4 + row.value * p.maxHp, EPSILON)
		expect(firstOf(events, "damage", "leader")).toEqual(nil)
	end,

	guard = function()
		local row = special("guard")
		local state = duel("guard")
		local l = state.leader.fighters[1]
		local p = state.player.fighters[1]
		local next, events = Battle.takeTurn(state, Battle.SPECIAL)
		local guardEvent = mustFind(events, "guard", "player")
		expect(guardEvent.value).toEqual(row.value)
		local damage = mustFind(events, "damage", "player")
		local normal = l.attack * Battle.typeBonus(l.type, p.type) * randomAt(0.5)
		expect(damage.guarded).toEqual(true)
		expect(damage.amount).toBeCloseTo(normal * row.value, EPSILON)
		expect(next.player.fighters[1].guard).toEqual(nil)
	end,

	rush = function()
		local row = special("rush")
		local state = duel("rush")
		local before = state.player.fighters[1].speed
		local next, events = Battle.takeTurn(state, Battle.SPECIAL)
		local rushEvent = mustFind(events, "rush", "player")
		expect(rushEvent.speed).toBeCloseTo(before * (1 + row.value), EPSILON)
		expect(next.player.fighters[1].speed).toBeCloseTo(before * (1 + row.value), EPSILON)
		-- It lasts: two more turns later the speed is still raised.
		local later = Battle.takeTurn(Battle.takeTurn(next, Battle.BASIC), Battle.BASIC)
		expect(later.player.fighters[1].speed).toBeCloseTo(before * (1 + row.value), EPSILON)
	end,

	off_type = function()
		local row = special("off_type")
		-- A pet whose own type is weak against the leader, with an off type
		-- that is strong against it.
		local leaderType = Config.types[1]
		local ownType: string? = nil
		local offType: string? = nil
		for _, t in Config.types do
			if t.weak_against == leaderType.id then
				ownType = t.id
			end
			if t.strong_against == leaderType.id then
				offType = t.id
			end
		end
		assert(
			ownType and offType,
			"config types need a weak and a strong type against " .. leaderType.id
		)
		local state = Battle.start(
			{ fighter({ type = ownType, special = "off_type", offType = offType, speed = 12 }) },
			{ fighter({ type = leaderType.id, speed = 10 }) },
			0,
			fixedRng(0.5)
		)
		local p = state.player.fighters[1]
		local _, events = Battle.takeTurn(state, Battle.SPECIAL)
		local attack = mustFind(events, "attack", "player")
		expect(attack.moveType).toEqual(offType)
		local damage = mustFind(events, "damage", "leader")
		expect(damage.typeBonus).toEqual(C.type_bonus_strong)
		local expected = p.attack
			* (row.power / C.basic_move_power)
			* C.type_bonus_strong
			* randomAt(0.5)
		expect(damage.amount).toBeCloseTo(expected, EPSILON)
	end,
}

return function()
	describe("Battle damage", function()
		it("matches the spec formula at fixed rng draws", function()
			local pType, lType = neutralPair()
			local attacker = { attack = 25 }
			local defender = { type = lType }
			for _, u in { 0, 0.25, 0.5, 0.999 } do
				local expected = 25 * (C.basic_move_power / C.basic_move_power) * 1 * randomAt(u)
				expect(Battle.damage(attacker, defender, C.basic_move_power, pType, fixedRng(u))).toBeCloseTo(
					expected,
					EPSILON
				)
			end
			-- Hand computed: Attack 20, power 80, neutral, mid draw.
			local mid = (C.damage_random_min + C.damage_random_max) / 2
			expect(Battle.damage({ attack = 20 }, defender, 80, pType, fixedRng(0.5))).toBeCloseTo(
				20 * (80 / C.basic_move_power) * mid,
				EPSILON
			)
		end)

		it("draws Random between damage_random_min and damage_random_max", function()
			local pType, lType = neutralPair()
			expect(
				Battle.damage(
					{ attack = 10 },
					{ type = lType },
					C.basic_move_power,
					pType,
					fixedRng(0)
				)
			).toBeCloseTo(10 * C.damage_random_min, EPSILON)
			local rng = Hatch.seededRng(7)
			for _ = 1, 500 do
				local d = Battle.damage(
					{ attack = 10 },
					{ type = lType },
					C.basic_move_power,
					pType,
					rng
				)
				expect(d >= 10 * C.damage_random_min - EPSILON).toBeTrue()
				expect(d <= 10 * C.damage_random_max + EPSILON).toBeTrue()
			end
		end)

		it("applies the strong, weak and neutral type bonus from config", function()
			for _, t in Config.types do
				expect(Battle.typeBonus(t.id, t.strong_against)).toEqual(C.type_bonus_strong)
				expect(Battle.typeBonus(t.id, t.weak_against)).toEqual(C.type_bonus_weak)
				local neutral = 0
				for _, other in Config.types do
					if other.id ~= t.strong_against and other.id ~= t.weak_against then
						expect(Battle.typeBonus(t.id, other.id)).toEqual(1)
						neutral += 1
					end
				end
				expect(neutral > 0).toBeTrue()
				local base = Battle.damage(
					{ attack = 30 },
					{ type = t.id },
					C.basic_move_power,
					t.id,
					fixedRng(0.5)
				)
				local strong = Battle.damage(
					{ attack = 30 },
					{ type = t.strong_against },
					C.basic_move_power,
					t.id,
					fixedRng(0.5)
				)
				local weak = Battle.damage(
					{ attack = 30 },
					{ type = t.weak_against },
					C.basic_move_power,
					t.id,
					fixedRng(0.5)
				)
				expect(strong).toBeCloseTo(base * C.type_bonus_strong, EPSILON)
				expect(weak).toBeCloseTo(base * C.type_bonus_weak, EPSILON)
			end
		end)
	end)

	describe("Battle start", function()
		it("scales player HP and Attack by rebirths and variant, and not the leader", function()
			local pet = Config.pets[1]
			local variant = Config.variants[#Config.variants]
			local spec = Battle.fighterFromPet(pet.id, variant.id)
			local leader = Gym.leaderTeam(Config.gyms[1].world, 3)
			local state = Battle.start({ spec }, leader, 3, fixedRng(0.5))
			local mult = (1 + C.rebirth_battle_bonus * 3) * variant.battle_mult
			local p = state.player.fighters[1]
			expect(p.maxHp).toBeCloseTo(pet.hp * mult, EPSILON)
			expect(p.hp).toBeCloseTo(pet.hp * mult, EPSILON)
			expect(p.attack).toBeCloseTo(pet.attack * mult, EPSILON)
			expect(p.speed).toEqual(pet.speed)
			expect(state.leader.fighters[1].maxHp).toEqual(leader[1].hp)
			expect(state.leader.fighters[1].attack).toEqual(leader[1].attack)
			expect(state.turn).toEqual(0)
			expect(state.player.active).toEqual(1)
			expect(state.leader.active).toEqual(1)
			expect(p.cooldown).toEqual(0)
		end)

		it("leaves the state passed to takeTurn untouched", function()
			local state = duel("smash")
			local hpBefore = state.leader.fighters[1].hp
			local next = Battle.takeTurn(state, Battle.SPECIAL)
			expect(state.leader.fighters[1].hp).toEqual(hpBefore)
			expect(state.turn).toEqual(0)
			expect(state.player.fighters[1].cooldown).toEqual(0)
			expect(next.turn).toEqual(1)
		end)

		it("rejects a bad move choice and a finished battle", function()
			local state = duel("smash")
			expect(function()
				Battle.takeTurn(state, 3)
			end).toThrow("moveChoice")
			local pType, lType = neutralPair()
			local quick = Battle.start(
				{ fighter({ type = pType, attack = 1000, speed = 12 }) },
				{ fighter({ type = lType, hp = 1 }) },
				0,
				fixedRng(0.5)
			)
			local over, events = Battle.takeTurn(quick, Battle.BASIC)
			expect(Battle.isOver(over)).toEqual("player")
			expect(events[#events].kind).toEqual("win")
			expect(function()
				Battle.takeTurn(over, Battle.BASIC)
			end).toThrow("already over")
		end)
	end)

	describe("Battle specials", function()
		for _, row in Config.specials do
			it("special " .. row.id .. " has its exact effect", function()
				local test = SPECIAL_TESTS[row.id]
				if test == nil then
					error("no test for special " .. row.id)
				end
				test()
			end)
		end

		it("covers exactly the specials in config/specials.json", function()
			local tested: { string } = {}
			for id in SPECIAL_TESTS do
				table.insert(tested, id)
			end
			local configured: { string } = {}
			for _, row in Config.specials do
				table.insert(configured, row.id)
			end
			table.sort(tested)
			table.sort(configured)
			expect(tested).toEqual(configured)
		end)

		it("makes the special unusable for exactly special_cooldown_turns turns", function()
			local state = duel("smash")
			expect(Battle.canUseSpecial(state)).toBeTrue()
			state = Battle.takeTurn(state, Battle.SPECIAL)
			for _ = 1, C.special_cooldown_turns do
				expect(Battle.canUseSpecial(state)).toBeFalse()
				local blocked = state
				expect(function()
					Battle.takeTurn(blocked, Battle.SPECIAL)
				end).toThrow("cooling down")
				state = Battle.takeTurn(state, Battle.BASIC)
			end
			expect(Battle.canUseSpecial(state)).toBeTrue()
			state = Battle.takeTurn(state, Battle.SPECIAL)
			expect(Battle.canUseSpecial(state)).toBeFalse()
		end)

		it("uses the leader special when ready, otherwise the basic attack", function()
			local pType, lType = neutralPair()
			local state = Battle.start(
				{ fighter({ type = pType, speed = 12 }) },
				{ fighter({ type = lType, speed = 10, special = "smash" }) },
				0,
				fixedRng(0.5)
			)
			local moves: { number } = {}
			for _ = 1, C.special_cooldown_turns + 2 do
				local events
				state, events = Battle.takeTurn(state, Battle.BASIC)
				table.insert(moves, mustFind(events, "attack", "leader").move :: number)
			end
			local expected: { number } = { Battle.SPECIAL }
			for _ = 1, C.special_cooldown_turns do
				table.insert(expected, Battle.BASIC)
			end
			table.insert(expected, Battle.SPECIAL)
			expect(moves).toEqual(expected)
		end)

		it("lets Guard absorb one hit, not two", function()
			local row = special("guard")
			local state = duel("guard")
			local p = state.player.fighters[1]
			local l = state.leader.fighters[1]
			local normal = l.attack * Battle.typeBonus(l.type, p.type) * randomAt(0.5)
			local events
			state, events = Battle.takeTurn(state, Battle.SPECIAL)
			local first = mustFind(events, "damage", "player")
			expect(first.guarded).toEqual(true)
			expect(first.amount).toBeCloseTo(normal * row.value, EPSILON)
			state, events = Battle.takeTurn(state, Battle.BASIC)
			local second = mustFind(events, "damage", "player")
			expect(second.guarded).toEqual(false)
			expect(second.amount).toBeCloseTo(normal, EPSILON)
		end)

		it("never lets Drain heal the user above max HP", function()
			local state = duel("drain", { attack = 200 })
			local p = state.player.fighters[1]
			p.hp = p.maxHp - 1
			local _, events = Battle.takeTurn(state, Battle.SPECIAL)
			local healEvent = mustFind(events, "heal", "player")
			expect(healEvent.amount).toBeCloseTo(1, EPSILON)
			expect(healEvent.hp).toBeCloseTo(p.maxHp, EPSILON)
		end)

		it("never lets Heal go above max HP", function()
			local state = duel("heal")
			local p = state.player.fighters[1]
			p.hp = p.maxHp - 1
			local _, events = Battle.takeTurn(state, Battle.SPECIAL)
			expect(mustFind(events, "heal", "player").hp).toBeCloseTo(p.maxHp, EPSILON)
		end)
	end)

	describe("Battle turn order", function()
		it("gives a Speed tie to the player", function()
			local pType, lType = neutralPair()
			local state = Battle.start(
				{ fighter({ type = pType, speed = 11 }) },
				{ fighter({ type = lType, speed = 11 }) },
				0,
				fixedRng(0.5)
			)
			local _, events = Battle.takeTurn(state, Battle.BASIC)
			expect(events[1].kind).toEqual("attack")
			expect(events[1].side).toEqual("player")
		end)

		it("lets the faster leader act first, and Rush flip the order", function()
			local row = special("rush")
			local pType, lType = neutralPair()
			local playerSpeed = 10
			local leaderSpeed = playerSpeed + 1
			assert(
				playerSpeed * (1 + row.value) >= leaderSpeed,
				"rush value too small for this test"
			)
			local state = Battle.start(
				{ fighter({ type = pType, speed = playerSpeed, special = "rush" }) },
				{ fighter({ type = lType, speed = leaderSpeed }) },
				0,
				fixedRng(0.5)
			)
			local events
			state, events = Battle.takeTurn(state, Battle.SPECIAL)
			expect(events[1].side).toEqual("leader")
			mustFind(events, "rush", "player")
			state, events = Battle.takeTurn(state, Battle.BASIC)
			expect(events[1].kind).toEqual("attack")
			expect(events[1].side).toEqual("player")
		end)

		it("skips the action of a pet that fainted first", function()
			local pType, lType = neutralPair()
			local state = Battle.start({ fighter({ type = pType, speed = 12, attack = 1000 }) }, {
				fighter({ type = lType, speed = 10, hp = 10 }),
				fighter({ type = lType, speed = 10 }),
			}, 0, fixedRng(0.5))
			local next, events = Battle.takeTurn(state, Battle.BASIC)
			expect(firstOf(events, "attack", "leader")).toEqual(nil)
			expect(mustFind(events, "faint", "leader").pet).toEqual(1)
			expect(mustFind(events, "switch", "leader").pet).toEqual(2)
			expect(next.leader.active).toEqual(2)
			expect(Battle.isOver(next)).toEqual(nil)
		end)
	end)

	describe("Battle full run", function()
		local function seededBattle(seed: number): (Battle.State, { Battle.Event })
			local gym = Config.gyms[1]
			local state = Battle.start(
				Gym.referenceTeam(gym.world),
				Gym.leaderTeam(gym.world, 0),
				gym.target_rebirths,
				Hatch.seededRng(seed)
			)
			return playOut(state, 500)
		end

		it("plays a seeded battle to a winner with a stable event list", function()
			local finalA, eventsA = seededBattle(42)
			local finalB, eventsB = seededBattle(42)
			expect(eventsA).toEqual(eventsB)
			expect(finalA.turn).toEqual(finalB.turn)
			local winner = Battle.isOver(finalA)
			expect(winner ~= nil).toBeTrue()
			local last = eventsA[#eventsA]
			expect(last.kind).toEqual(if winner == "player" then "win" else "lose")
			local endings = 0
			local faints = { player = 0, leader = 0 }
			for _, event in eventsA do
				if event.kind == "win" or event.kind == "lose" then
					endings += 1
				elseif event.kind == "faint" then
					faints[event.side] += 1
				end
			end
			expect(endings).toEqual(1)
			local loser = if winner == "player" then "leader" else "player"
			local loserSide = if loser == "player" then finalA.player else finalA.leader
			expect(faints[loser]).toEqual(#loserSide.fighters)
			-- Every damage event's hp is the target's HP after the hit.
			for _, event in eventsA do
				if event.kind == "damage" then
					expect((event.hp :: number) >= 0).toBeTrue()
					expect((event.amount :: number) > 0).toBeTrue()
				end
			end
		end)
	end)

	describe("Battle agrees with the tuner", function()
		for _, gym in Config.gyms do
			it(
				string.format(
					"reference team beats %s at %d rebirths within %.2f of the recorded win rate",
					gym.world,
					gym.target_rebirths,
					WIN_RATE_TOLERANCE
				),
				function()
					local rng = Hatch.seededRng(1000 + gym.target_rebirths)
					local wins = 0
					for _ = 1, WIN_RATE_BATTLES do
						local state = Battle.start(
							Gym.referenceTeam(gym.world),
							Gym.leaderTeam(gym.world, gym.target_rebirths),
							gym.target_rebirths,
							rng
						)
						local final = playOut(state, 1000)
						if Battle.isOver(final) == "player" then
							wins += 1
						end
					end
					local rate = wins / WIN_RATE_BATTLES
					local recorded = gym.reference_win_rate_at_target
					if math.abs(rate - recorded) > WIN_RATE_TOLERANCE then
						error(
							string.format(
								"%s: measured win rate %.3f, tuner recorded %.3f, tolerance %.2f",
								gym.world,
								rate,
								recorded,
								WIN_RATE_TOLERANCE
							)
						)
					end
				end
			)
		end
	end)
end
