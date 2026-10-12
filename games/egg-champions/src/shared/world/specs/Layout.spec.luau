--!strict
--[[
	The world builder places one prop per entry of Layout.plan, and checks its
	built counts against the plan when it runs. So these tests count what it
	builds: egg stands, gyms and portals, against the counts in config.
]]

local Runner = require(script.Parent.Parent.Parent.testing.Runner)
local Config = require(script.Parent.Parent.Parent.Config)
local Layout = require(script.Parent.Parent.Layout)

local describe = Runner.describe
local it = Runner.it
local expect = Runner.expect

local function eggCountInConfig(worlds: { Config.World }): number
	local count = 0
	for _, world in worlds do
		count += #world.eggs
	end
	return count
end

local function countBy<T>(list: { T }, keyOf: (T) -> string): { [string]: number }
	local counts: { [string]: number } = {}
	for _, item in list do
		local key = keyOf(item)
		counts[key] = (counts[key] or 0) + 1
	end
	return counts
end

-- A copy of the world table with one more world, reusing ids that resolve.
local function withFourthWorld(): { Config.World }
	local worlds = table.clone(Config.worlds)
	local last = worlds[#worlds]
	local first = worlds[1]
	table.insert(worlds, {
		index = last.index + 1,
		id = "test_extra_world",
		name = "Test Extra World",
		environment = "Grass fields",
		eggs = { first.eggs[1], last.eggs[1], last.eggs[#last.eggs] },
		gym = last.gym,
	})
	return worlds
end

return function()
	describe("World layout", function()
		it("plans one egg stand per egg in config, in its own world", function()
			local plan = Layout.plan()
			expect(#plan.eggStands).toEqual(eggCountInConfig(Config.worlds))
			local perWorld = countBy(plan.eggStands, function(stand: Layout.EggStand): string
				return stand.worldId
			end)
			for _, world in Config.worlds do
				expect(perWorld[world.id]).toEqual(#world.eggs)
			end
			for _, stand in plan.eggStands do
				local egg = Config.eggById[stand.eggId]
				expect(egg.world).toEqual(stand.worldId)
			end
		end)

		it("plans one gym, one island and one portal per world", function()
			local plan = Layout.plan()
			expect(#plan.gyms).toEqual(#Config.worlds)
			expect(#plan.islands).toEqual(#Config.worlds)
			expect(#plan.portals).toEqual(#Config.worlds)
			local gyms = countBy(plan.gyms, function(gym: Layout.GymSite): string
				return gym.worldId
			end)
			for _, world in Config.worlds do
				expect(gyms[world.id]).toEqual(1)
			end
		end)

		it("builds a fourth world with no code change", function()
			local worlds = withFourthWorld()
			local plan = Layout.plan(worlds)
			expect(#plan.islands).toEqual(#Config.worlds + 1)
			expect(#plan.gyms).toEqual(#worlds)
			expect(#plan.eggStands).toEqual(eggCountInConfig(worlds))
			expect(plan.arrivals["test_extra_world"] ~= nil).toBeTrue()
		end)

		it("labels stands and gyms with the numbers from config", function()
			local plan = Layout.plan()
			for _, stand in plan.eggStands do
				local egg = Config.eggById[stand.eggId]
				expect(string.find(stand.label, egg.name, 1, true) ~= nil).toBeTrue()
				local price = Layout.formatCount(egg.price)
				expect(string.find(stand.label, price, 1, true) ~= nil).toBeTrue()
			end
			for _, gym in plan.gyms do
				local world = Config.worldById[gym.worldId]
				local fee = Layout.formatCount(world.gym.fee)
				local leaderType = Config.typeById[world.gym.leader_type].name
				expect(string.find(gym.label, fee, 1, true) ~= nil).toBeTrue()
				expect(string.find(gym.label, leaderType, 1, true) ~= nil).toBeTrue()
			end
		end)

		it("points each portal at the next world, and the last at nothing", function()
			local plan = Layout.plan()
			local sorted = table.clone(Config.worlds)
			table.sort(sorted, function(a: Config.World, b: Config.World): boolean
				return a.index < b.index
			end)
			for i, portal in plan.portals do
				expect(portal.fromIndex).toEqual(sorted[i].index)
				if i < #sorted then
					expect(portal.toIndex).toEqual(sorted[i + 1].index)
					expect(portal.toWorldId).toEqual(sorted[i + 1].id)
				else
					expect(portal.toIndex).toEqual(nil)
				end
			end
		end)

		it("puts the spawn on the first world and spaces the islands apart", function()
			local plan = Layout.plan()
			local first = plan.islands[1]
			expect(plan.spawn.x).toEqual(first.origin.x)
			expect(plan.spawn.z).toEqual(first.origin.z)
			for i = 1, #plan.islands do
				for j = i + 1, #plan.islands do
					local a = plan.islands[i].origin
					local b = plan.islands[j].origin
					local apart = math.max(math.abs(a.x - b.x), math.abs(a.z - b.z))
					expect(apart >= Layout.ISLAND_SIZE).toBeTrue()
				end
			end
		end)

		it("formats counts with thousands separators", function()
			expect(Layout.formatCount(50)).toEqual("50")
			expect(Layout.formatCount(5000)).toEqual("5,000")
			expect(Layout.formatCount(10000000000)).toEqual("10,000,000,000")
		end)
	end)
end
