--!strict
local Runner = require(script.Parent.Parent.Parent.testing.Runner)
local Config = require(script.Parent.Parent.Parent.Config)
local NextGoal = require(script.Parent.Parent.NextGoal)
local Format = require(script.Parent.Parent.Format)

local describe = Runner.describe
local it = Runner.it
local expect = Runner.expect

local EPSILON = 1e-9

local function newState(coins: number): NextGoal.State
	return { coins = coins, rebirths = 0, index = {}, gymsBeaten = {}, feesPaid = {} }
end

local function worldsInOrder(): { Config.World }
	local list = table.clone(Config.worlds)
	table.sort(list, function(a, b)
		return a.index < b.index
	end)
	return list
end

-- The eggs of a world that the rule may pick, cheapest first.
local function goalEggs(world: Config.World): { Config.Egg }
	local list = {}
	for _, eggId in world.eggs do
		local egg = Config.eggById[eggId]
		if egg.price < world.gym.fee then
			table.insert(list, egg)
		end
	end
	table.sort(list, function(a, b)
		return a.price < b.price
	end)
	return list
end

-- Marks one pet of the egg as seen in the index.
local function hatch(state: NextGoal.State, eggId: string)
	for _, pet in Config.pets do
		if pet.egg == eggId then
			state.index[pet.id] = { normal = true }
			return
		end
	end
	error("no pet hatches from " .. eggId)
end

local worlds = worldsInOrder()
local first = worlds[1]
local last = worlds[#worlds]

return function()
	describe("NextGoal.currentWorld", function()
		it("starts in the first world", function()
			expect(NextGoal.currentWorld(newState(0)).id).toEqual(first.id)
		end)

		it("moves on when the gym of the current world is beaten", function()
			if #worlds < 2 then
				return
			end
			local state = newState(0)
			state.gymsBeaten[first.id] = true
			expect(NextGoal.currentWorld(state).id).toEqual(worlds[2].id)
		end)
	end)

	describe("NextGoal.pick", function()
		it("points a new player at the cheapest egg of the first world", function()
			local eggs = goalEggs(first)
			expect(#eggs > 0).toBeTrue()
			local goal = NextGoal.pick(newState(0), 0)
			expect(goal.kind).toEqual(NextGoal.kinds.egg)
			expect(goal.id).toEqual(eggs[1].id)
			expect(goal.need).toEqual(eggs[1].price)
			expect(goal.have).toEqual(0)
			expect(goal.progress).toEqual(0)
			expect(goal.ready).toBeFalse()
		end)

		it("moves to the next egg once the first has been hatched", function()
			local eggs = goalEggs(first)
			if #eggs < 2 then
				return
			end
			local state = newState(0)
			hatch(state, eggs[1].id)
			local goal = NextGoal.pick(state, 0)
			expect(goal.kind).toEqual(NextGoal.kinds.egg)
			expect(goal.id).toEqual(eggs[2].id)
		end)

		it("points at the gym fee once every egg of the world was hatched", function()
			local state = newState(0)
			for _, egg in goalEggs(first) do
				hatch(state, egg.id)
			end
			local goal = NextGoal.pick(state, 0)
			expect(goal.kind).toEqual(NextGoal.kinds.gym)
			expect(goal.id).toEqual(first.id)
			expect(goal.need).toEqual(first.gym.fee)
		end)

		it("fills the bar with the coins held and caps it at the target", function()
			local state = newState(0)
			for _, egg in goalEggs(first) do
				hatch(state, egg.id)
			end
			local fee = first.gym.fee
			state.coins = fee / 4
			local quarter = NextGoal.pick(state, 0)
			expect(quarter.progress).toBeCloseTo(0.25, EPSILON)
			expect(quarter.have).toEqual(fee / 4)
			expect(quarter.ready).toBeFalse()

			state.coins = fee * 3
			local over = NextGoal.pick(state, 0)
			expect(over.progress).toEqual(1)
			expect(over.have).toEqual(fee)
			expect(over.ready).toBeTrue()
		end)

		it("names the leader type and its counter for a gym goal", function()
			local state = newState(0)
			for _, egg in goalEggs(first) do
				hatch(state, egg.id)
			end
			local goal = NextGoal.pick(state, 0)
			local leader = Config.typeById[first.gym.leader_type].name
			local counter = Config.typeById[first.gym.counter_type].name
			expect(string.find(goal.detail, leader, 1, true) ~= nil).toBeTrue()
			expect(string.find(goal.detail, counter, 1, true) ~= nil).toBeTrue()
		end)

		it("shows a paid gym as ready even with no coins", function()
			local state = newState(0)
			state.feesPaid[first.id] = true
			local goal = NextGoal.pick(state, 0)
			expect(goal.kind).toEqual(NextGoal.kinds.gym)
			expect(goal.ready).toBeTrue()
			expect(goal.progress).toEqual(1)
		end)

		it("points at the rebirth cost the server sent once the last gym is beaten", function()
			local state = newState(0)
			for _, world in worlds do
				state.gymsBeaten[world.id] = true
			end
			local cost = Config.constants.rebirth_first_cost
			state.coins = cost / 2
			local goal = NextGoal.pick(state, cost)
			expect(goal.kind).toEqual(NextGoal.kinds.rebirth)
			expect(goal.id).toEqual(last.id)
			expect(goal.need).toEqual(cost)
			expect(goal.progress).toBeCloseTo(0.5, EPSILON)
		end)

		it(
			"runs the first minutes as small goals: more pets, a full team, the next egg, the gym",
			function()
				local teamSize = Config.constants.team_size
				local cheapest = NextGoal.cheapestEgg(first)
				local eggs = goalEggs(first)

				-- Right after the tutorial: one pet hatched and equipped.
				local state = newState(0)
				hatch(state, cheapest.id)
				state.petCount = 1
				state.teamCount = 1

				local goal = NextGoal.pick(state, 0)
				expect(goal.kind).toEqual(NextGoal.kinds.pets)
				expect(goal.title).toEqual(string.format("Hatch %d more pets", teamSize - 1))
				expect(goal.have).toEqual(1)
				expect(goal.need).toEqual(teamSize)
				expect(goal.progress).toBeCloseTo(1 / teamSize, EPSILON)
				expect(goal.ready).toBeFalse()
				expect(NextGoal.beforeGym(goal)).toBeTrue()
				state.coins = cheapest.price
				expect(NextGoal.pick(state, 0).ready).toBeTrue()

				-- Enough pets, but only one on the team.
				state.petCount = teamSize
				goal = NextGoal.pick(state, 0)
				expect(goal.kind).toEqual(NextGoal.kinds.team)
				expect(goal.title).toEqual(string.format("Fill your team of %d", teamSize))
				expect(goal.have).toEqual(1)
				expect(goal.need).toEqual(teamSize)
				expect(goal.ready).toBeTrue()
				expect(NextGoal.beforeGym(goal)).toBeTrue()

				-- A full team: save for the next egg of the world, by its price.
				state.teamCount = teamSize
				goal = NextGoal.pick(state, 0)
				if #eggs >= 2 then
					expect(goal.kind).toEqual(NextGoal.kinds.egg)
					expect(goal.id).toEqual(eggs[2].id)
					expect(goal.title).toEqual("Save for the " .. eggs[2].name)
					expect(goal.need).toEqual(eggs[2].price)
					expect(NextGoal.beforeGym(goal)).toBeTrue()
					hatch(state, eggs[2].id)
					goal = NextGoal.pick(state, 0)
				end

				-- Then the gym, which the tutorial's gym step waits for.
				expect(goal.kind).toEqual(NextGoal.kinds.gym)
				expect(goal.need).toEqual(first.gym.fee)
				expect(NextGoal.beforeGym(goal)).toBeFalse()
			end
		)

		it("says one more pet in the singular", function()
			local teamSize = Config.constants.team_size
			if teamSize < 2 then
				return
			end
			local state = newState(0)
			state.petCount = teamSize - 1
			state.teamCount = teamSize - 1
			expect(NextGoal.pick(state, 0).title).toEqual("Hatch 1 more pet")
		end)

		it("only asks to fill the team with pets the player owns", function()
			local teamSize = Config.constants.team_size
			local state = newState(0)
			state.petCount = teamSize + 2
			state.teamCount = teamSize
			expect(NextGoal.pick(state, 0).kind ~= NextGoal.kinds.team).toBeTrue()
			state.teamCount = 0
			expect(NextGoal.pick(state, 0).kind).toEqual(NextGoal.kinds.team)
		end)

		it("skips the pet and team goals once the fee is paid", function()
			local state = newState(0)
			state.feesPaid[first.id] = true
			state.petCount = 0
			state.teamCount = 0
			expect(NextGoal.pick(state, 0).kind).toEqual(NextGoal.kinds.gym)
		end)

		it("picks the cheapest egg of a world", function()
			for _, world in worlds do
				local egg = NextGoal.cheapestEgg(world)
				for _, eggId in world.eggs do
					expect(Config.eggById[eggId].price >= egg.price).toBeTrue()
				end
			end
		end)

		it("leaves the state it is given untouched", function()
			local state = newState(10)
			state.feesPaid[first.id] = true
			NextGoal.pick(state, 0)
			expect(state).toEqual({
				coins = 10,
				rebirths = 0,
				index = {},
				gymsBeaten = {},
				feesPaid = { [first.id] = true },
			})
		end)
	end)

	describe("NextGoal.nextLine", function()
		local teamSize = Config.constants.team_size

		it("names the gym and its fee from config under a small goal", function()
			local state = newState(0)
			state.petCount = 1
			state.teamCount = 1
			local goal = NextGoal.pick(state, 0)
			expect(NextGoal.beforeGym(goal)).toBeTrue()
			local expected =
				string.format("Next: %s Gym (%s)", first.name, Format.abbreviate(first.gym.fee))
			expect(NextGoal.nextLine(state, goal)).toEqual(expected)
		end)

		it("reads Next: Green Meadow Gym (50K) for the first world as configured", function()
			local state = newState(0)
			state.petCount = 0
			state.teamCount = 0
			local line = NextGoal.nextLine(state, NextGoal.pick(state, 0))
			if first.name == "Green Meadow" and first.gym.fee == 50000 then
				expect(line).toEqual("Next: Green Meadow Gym (50K)")
			end
		end)

		it("shows no second line when the goal is the gym itself or a rebirth", function()
			local state = newState(0)
			state.petCount = teamSize
			state.teamCount = teamSize
			for _, egg in goalEggs(first) do
				hatch(state, egg.id)
			end
			local goal = NextGoal.pick(state, 0)
			expect(goal.kind).toEqual("gym")
			expect(NextGoal.nextLine(state, goal)).toEqual(nil)
			state.feesPaid[first.id] = true
			expect(NextGoal.nextLine(state, NextGoal.pick(state, 0))).toEqual(nil)
		end)
	end)

	describe("NextGoal.gymBeam", function()
		local teamSize = Config.constants.team_size

		it("stays off with an open team slot and no tap", function()
			local state = newState(0)
			state.petCount = 1
			state.teamCount = 1
			expect(NextGoal.gymBeam(state, nil)).toEqual(nil)
		end)

		it("turns on when the next line was tapped in this world", function()
			local state = newState(0)
			state.petCount = 1
			state.teamCount = 1
			expect(NextGoal.gymBeam(state, first.id)).toEqual(first.id)
			-- A tap from another world does not count here.
			expect(NextGoal.gymBeam(state, last.id == first.id and "elsewhere" or last.id)).toEqual(
				nil
			)
		end)

		it("turns on by itself once the team is full", function()
			local state = newState(0)
			state.petCount = teamSize
			state.teamCount = teamSize
			expect(NextGoal.teamFull(state)).toBeTrue()
			expect(NextGoal.gymBeam(state, nil)).toEqual(first.id)
		end)

		it("turns off once the gym is beaten", function()
			local state = newState(0)
			state.petCount = teamSize
			state.teamCount = teamSize
			state.gymsBeaten[last.id] = true
			for _, world in worlds do
				state.gymsBeaten[world.id] = true
			end
			expect(NextGoal.gymBeam(state, NextGoal.currentWorld(state).id)).toEqual(nil)
		end)
	end)
end
