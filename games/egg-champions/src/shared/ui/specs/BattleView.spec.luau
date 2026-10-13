--!strict
local Runner = require(script.Parent.Parent.Parent.testing.Runner)
local Config = require(script.Parent.Parent.Parent.Config)
local Battle = require(script.Parent.Parent.Parent.rules.Battle)
local Gym = require(script.Parent.Parent.Parent.rules.Gym)
local Hatch = require(script.Parent.Parent.Parent.rules.Hatch)
local BattleView = require(script.Parent.Parent.BattleView)

local describe = Runner.describe
local it = Runner.it
local expect = Runner.expect

local MAX_TURNS = 500

type Turn = {
	before: BattleView.Snapshot,
	after: BattleView.Snapshot,
	events: { Battle.Event },
}

-- Plays a battle out the way the task 05 specs do: the special when ready,
-- otherwise the basic attack. Returns every turn with the view before and
-- after it, as the server would send them.
local function playOut(state: Battle.State): { Turn }
	local played: { Turn } = {}
	local current = state
	for _ = 1, MAX_TURNS do
		if Battle.isOver(current) ~= nil then
			break
		end
		local move = if Battle.canUseSpecial(current) then Battle.SPECIAL else Battle.BASIC
		local nextState, events = Battle.takeTurn(current, move)
		table.insert(played, {
			before = BattleView.snapshot(current),
			after = BattleView.snapshot(nextState),
			events = events,
		})
		current = nextState
	end
	return played
end

-- The task 05 seeded run: gym 1's tuner reference team against its leaders.
local function recordedBattle(): { Turn }
	local gym = Config.gyms[1]
	local state = Battle.start(
		Gym.referenceTeam(gym.world),
		Gym.leaderTeam(gym.world, 0),
		gym.target_rebirths,
		Hatch.seededRng(42)
	)
	return playOut(state)
end

-- Every pet in config alone against gym 1, so every special, a win and a loss
-- all show up in the recorded events.
local function everyPetBattles(): { Turn }
	local gym = Config.gyms[1]
	local all: { Turn } = {}
	for position, pet in Config.pets do
		local state = Battle.start(
			{ Battle.fighterFromPet(pet.id, nil) },
			Gym.leaderTeam(gym.world, 0),
			gym.target_rebirths,
			Hatch.seededRng(position)
		)
		for _, turn in playOut(state) do
			table.insert(all, turn)
		end
	end
	return all
end

local function checkLines(turns: { Turn }): { [string]: boolean }
	local seen: { [string]: boolean } = {}
	for _, turn in turns do
		local lines = BattleView.lines(turn.events, turn.before)
		expect(#lines).toEqual(#turn.events)
		for position, line in lines do
			local event = turn.events[position]
			seen[event.kind] = true
			expect(type(line)).toEqual("string")
			expect(#line > 0).toBeTrue()
			expect(string.find(line, "nil", 1, true) == nil).toBeTrue()
			expect(string.sub(line, -1)).toEqual(".")
		end
	end
	return seen
end

return function()
	describe("BattleView log", function()
		it("writes one readable line per event of the recorded task 05 battle", function()
			local turns = recordedBattle()
			expect(#turns > 0).toBeTrue()
			checkLines(turns)
		end)

		it("covers every event kind across battles with every pet", function()
			local seen = checkLines(everyPetBattles())
			for _, kind in Battle.EVENT_KINDS do
				expect(seen[kind] == true).toBeTrue()
			end
		end)

		it("has a log line for every event kind in Battle.EVENT_KINDS and no other", function()
			for _, kind in Battle.EVENT_KINDS do
				expect(BattleView.handles(kind)).toBeTrue()
			end
			local expected = table.clone(Battle.EVENT_KINDS)
			table.sort(expected)
			expect(BattleView.handledKinds()).toEqual(expected)
		end)

		it("refuses an unknown event kind instead of skipping it", function()
			local snapshot = recordedBattle()[1].before
			expect(function()
				BattleView.lineFor({ kind = "teleport", side = "player" } :: any, snapshot)
			end).toThrow("no log line")
		end)

		it("says who acted, what it did and how much damage it dealt", function()
			local turn = recordedBattle()[1]
			local attack: Battle.Event? = nil
			local damage: Battle.Event? = nil
			for _, event in turn.events do
				if attack == nil and event.kind == "attack" then
					attack = event
				elseif attack ~= nil and damage == nil and event.kind == "damage" then
					damage = event
				end
			end
			assert(attack ~= nil and damage ~= nil, "the first turn has an attack and its damage")
			local attacker = BattleView.fighterName(turn.before, attack.side, attack.pet :: number)
			expect(string.find(BattleView.lineFor(attack, turn.before), attacker, 1, true) ~= nil).toBeTrue()
			local target = BattleView.fighterName(turn.before, damage.side, damage.pet :: number)
			local line = BattleView.lineFor(damage, turn.before)
			expect(string.find(line, target, 1, true) ~= nil).toBeTrue()
			local amount = tostring(math.ceil(damage.amount :: number))
			expect(string.find(line, amount .. " damage", 1, true) ~= nil).toBeTrue()
		end)
	end)

	describe("BattleView playback", function()
		it("ends each turn on the server's HP and active pets by applying its events", function()
			for _, turn in everyPetBattles() do
				local display = BattleView.copy(turn.before)
				for _, event in turn.events do
					BattleView.apply(display, event)
				end
				for _, side in { "player", "leader" } do
					local shown = if side == "player" then display.player else display.leader
					local sent = if side == "player" then turn.after.player else turn.after.leader
					for position, fighter in sent.fighters do
						expect(shown.fighters[position].hp).toBeCloseTo(fighter.hp, 1e-9)
					end
					if sent.active <= #sent.fighters then
						expect(shown.active).toEqual(sent.active)
					end
				end
			end
		end)

		it("leaves the snapshot it copied untouched", function()
			local turn = recordedBattle()[1]
			local before = BattleView.copy(turn.before)
			local display = BattleView.copy(turn.before)
			for _, event in turn.events do
				BattleView.apply(display, event)
			end
			expect(turn.before).toEqual(before)
		end)
	end)

	describe("BattleView moves and panels", function()
		it("names move 1 after the type and move 2 from config", function()
			for _, row in Config.types do
				expect(BattleView.basicMoveName(row.id)).toEqual(row.name .. " Strike")
			end
			for _, row in Config.specials do
				expect(BattleView.specialName(row.id)).toEqual(row.name)
			end
		end)

		it("shows the cooldown the server sent", function()
			expect(BattleView.cooldownText(0)).toEqual("Ready")
			expect(BattleView.cooldownText(1)).toEqual("Ready in 1 turn")
			local turns = Config.constants.special_cooldown_turns
			expect(BattleView.cooldownText(turns)).toEqual(
				string.format("Ready in %d turns", turns)
			)
		end)

		it("rounds HP up so a standing pet never shows 0", function()
			expect(BattleView.hpText(0.4, 98)).toEqual("1 / 98 HP")
			expect(BattleView.hpShare(49, 98)).toBeCloseTo(0.5, 1e-9)
			expect(BattleView.hpShare(5, 0)).toEqual(0)
		end)

		it("counts the pets each side has left", function()
			local turn = recordedBattle()[1]
			expect(BattleView.petsLeft(turn.before.leader)).toEqual(#turn.before.leader.fighters)
		end)
	end)

	describe("BattleView entering and leaving", function()
		local empty = { badges = {}, gymsBeaten = {}, feesPaid = {} }

		it("shows the fee from config and that attempts are free until rebirth", function()
			local world = Config.worlds[1]
			local prompt = BattleView.feePrompt(world.id, empty)
			expect(prompt.fee).toEqual(world.gym.fee)
			expect(prompt.paid).toBeFalse()
			expect(string.find(prompt.body, "free until your next rebirth", 1, true) ~= nil).toBeTrue()
			local paid = BattleView.feePrompt(world.id, {
				badges = {},
				gymsBeaten = {},
				feesPaid = { [world.id] = true },
			})
			expect(paid.paid).toBeTrue()
			expect(string.find(paid.body, "free until your next rebirth", 1, true) ~= nil).toBeTrue()
		end)

		it("picks the first open gym not yet beaten", function()
			expect(BattleView.pickGym(empty)).toEqual(Config.worlds[1].id)
			local first = Config.worlds[1].id
			expect(BattleView.pickGym({
				badges = { [first] = true },
				gymsBeaten = { [first] = true },
				feesPaid = {},
			})).toEqual(Config.worlds[2].id)
		end)

		it("counts the retry wait down and names the badge and next world on a win", function()
			local wait = Config.constants.gym_retry_seconds
			expect(BattleView.countdownText(wait)).toEqual(
				string.format("You can try again in %ds.", wait)
			)
			expect(BattleView.countdownText(0)).toEqual("The gym is open again.")
			local text = BattleView.winText(Config.worlds[1].id, true)
			expect(string.find(text, Config.worlds[1].name, 1, true) ~= nil).toBeTrue()
			expect(string.find(text, Config.worlds[2].name, 1, true) ~= nil).toBeTrue()
			local last = Config.worlds[#Config.worlds]
			expect(string.find(BattleView.winText(last.id, true), "final gym", 1, true) ~= nil).toBeTrue()
		end)

		it("turns every gym refusal into words", function()
			for _, reason in { "fee_not_paid", "retry_wait", "cannot_afford", "team_empty" } do
				expect(string.find(BattleView.reasonText(reason), "refused", 1, true) == nil).toBeTrue()
			end
		end)
	end)
end
