--!strict
local Runner = require(script.Parent.Parent.Parent.testing.Runner)
local Config = require(script.Parent.Parent.Parent.Config)
local Battle = require(script.Parent.Parent.Battle)
local Coins = require(script.Parent.Parent.Coins)
local Gym = require(script.Parent.Parent.Gym)
local Hatch = require(script.Parent.Parent.Hatch)
local PassEffects = require(script.Parent.Parent.PassEffects)

local describe = Runner.describe
local it = Runner.it
local expect = Runner.expect

local EPSILON = 1e-9
local BATTLE_SEED = 18018
local MAX_TURNS = 500

local function sorted(list: { string }): { string }
	local copy = table.clone(list)
	table.sort(copy)
	return copy
end

local function chanceOf(odds: { Hatch.OddsEntry }, rarity: string): number
	for _, entry in odds do
		if entry.rarity == rarity then
			return entry.chance
		end
	end
	error("no odds entry for " .. rarity)
end

-- A team of the first team_size pets of world 1, one with a variant, so the
-- battle uses the rebirth and variant multipliers.
local function sampleTeam(): { Gym.OwnedPet }
	local team: { Gym.OwnedPet } = {}
	local worldId = Config.worlds[1].id
	for _, pet in Config.pets do
		if pet.world == worldId and #team < Config.constants.team_size then
			table.insert(team, { petId = pet.id, variant = nil })
		end
	end
	team[1].variant = Config.variants[#Config.variants].id
	return team
end

-- Plays a whole seeded gym battle and returns every turn's events and the
-- final state. Uses the special whenever it is ready.
local function playBattle(passes: PassEffects.Owned, rebirths: number): any
	local state = Gym.startBattle({
		worldId = Config.worlds[1].id,
		pets = sampleTeam(),
		rebirths = rebirths,
		passes = passes,
	}, Hatch.seededRng(BATTLE_SEED))
	local start = state
	local turns = {}
	local count = 0
	while Battle.isOver(state) == nil and count < MAX_TURNS do
		local move = if Battle.canUseSpecial(state) then Battle.SPECIAL else Battle.BASIC
		local nextState, events = Battle.takeTurn(state, move)
		table.insert(turns, events)
		state = nextState
		count += 1
	end
	return {
		start = { player = start.player, leader = start.leader },
		turns = turns,
		winner = Battle.isOver(state),
		player = state.player,
		leader = state.leader,
	}
end

return function()
	describe("PassEffects", function()
		it("handles exactly the pass ids in config/passes.json", function()
			local configIds: { string } = {}
			for _, pass in Config.passes do
				table.insert(configIds, pass.id)
			end
			expect(sorted(PassEffects.HANDLED :: any)).toEqual(sorted(configIds))
			local all = PassEffects.all()
			for _, id in configIds do
				expect(all[id]).toBeTrue()
			end
		end)

		it("2x_coins exactly doubles coins per click at 0 and 3 rebirths", function()
			local team = sampleTeam()
			local with = { ["2x_coins"] = true }
			for _, rebirths in { 0, 3 } do
				local plain = Coins.perClick({
					team = team,
					rebirths = rebirths,
					completedEggs = 0,
					passMultiplier = PassEffects.coinMultiplier({}),
				})
				local doubled = Coins.perClick({
					team = team,
					rebirths = rebirths,
					completedEggs = 0,
					passMultiplier = PassEffects.coinMultiplier(with),
				})
				expect(plain > 0).toBeTrue()
				expect(doubled).toBeCloseTo(2 * plain, EPSILON)
			end
		end)

		it("no other pass changes coins per click", function()
			local owned = PassEffects.all()
			owned["2x_coins"] = nil
			expect(PassEffects.coinMultiplier(owned)).toEqual(1)
		end)

		it("lucky_eggs doubles Epic and Legendary odds and the table sums to 1", function()
			local plain = Hatch.odds(PassEffects.hatchOptions({}))
			local lucky = Hatch.odds(PassEffects.hatchOptions({ lucky_eggs = true }))
			for _, rarity in { "epic", "legendary" } do
				expect(chanceOf(lucky, rarity)).toBeCloseTo(2 * chanceOf(plain, rarity), EPSILON)
			end
			local total = 0
			for _, entry in lucky do
				total += entry.chance
			end
			expect(total).toBeCloseTo(1, EPSILON)
		end)

		it("triple_hatch allows a count of three and nothing else extra", function()
			expect(PassEffects.hatchCountAllowed({}, 1)).toBeTrue()
			expect(PassEffects.hatchCountAllowed({}, Hatch.TRIPLE_COUNT)).toBeFalse()
			local owned = { triple_hatch = true }
			expect(PassEffects.hatchCountAllowed(owned, Hatch.TRIPLE_COUNT)).toBeTrue()
			expect(PassEffects.hatchCountAllowed(owned, 2)).toBeFalse()
			expect(PassEffects.hatchCountAllowed(PassEffects.all(), 10)).toBeFalse()
		end)

		it("auto_click is on only with the pass", function()
			expect(PassEffects.autoClick({})).toBeFalse()
			expect(PassEffects.autoClick({ auto_click = true })).toBeTrue()
		end)

		it("no pass changes any value on the battle path", function()
			for _, rebirths in { 0, 3 } do
				local without = playBattle({}, rebirths)
				expect(#without.turns > 0).toBeTrue()
				expect(playBattle(PassEffects.all(), rebirths)).toEqual(without)
				for _, id in PassEffects.HANDLED do
					expect(playBattle({ [id] = true }, rebirths)).toEqual(without)
				end
			end
		end)
	end)
end
