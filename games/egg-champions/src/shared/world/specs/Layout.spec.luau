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

		it("keeps every two egg stands at least the minimum distance apart", function()
			local function check(plan: Layout.Plan)
				for i = 1, #plan.eggStands do
					for j = i + 1, #plan.eggStands do
						local a = plan.eggStands[i].position
						local b = plan.eggStands[j].position
						local apart = math.sqrt((a.x - b.x) ^ 2 + (a.z - b.z) ^ 2)
						expect(apart >= Layout.STAND_MIN_GAP).toBeTrue()
					end
				end
			end
			check(Layout.plan())
			check(Layout.plan(withFourthWorld()))
			-- A crowded world still spaces its stands.
			local crowded = table.clone(Config.worlds)
			local first = table.clone(crowded[1])
			local many = {}
			for _, egg in Config.eggs do
				table.insert(many, egg.id)
			end
			first.eggs = many
			crowded[1] = first
			check(Layout.plan(crowded))
		end)

		it("lays each world's stands on an arc facing the arrival point", function()
			local plan = Layout.plan()
			for _, stand in plan.eggStands do
				local arrival = plan.arrivals[stand.worldId]
				local first: Layout.EggStand? = nil
				for _, other in plan.eggStands do
					if other.worldId == stand.worldId then
						first = first or other
					end
				end
				local f = (first :: Layout.EggStand).position
				local r0 = math.sqrt((f.x - arrival.x) ^ 2 + (f.z - arrival.z) ^ 2)
				local p = stand.position
				local r = math.sqrt((p.x - arrival.x) ^ 2 + (p.z - arrival.z) ^ 2)
				expect(math.abs(r - r0) < 0.001).toBeTrue()
				-- In front of the player: on the -z side of the arrival point.
				expect(p.z < arrival.z).toBeTrue()
			end
		end)

		it(
			"puts each gym in front of the arrival point, clear of stands, portal and edge",
			function()
				local function flat(a: Layout.Vec, b: Layout.Vec): number
					return math.sqrt((a.x - b.x) ^ 2 + (a.z - b.z) ^ 2)
				end
				local gymReach =
					math.sqrt((Layout.GYM_SIZE.width / 2) ^ 2 + (Layout.GYM_SIZE.depth / 2) ^ 2)
				local function check(plan: Layout.Plan)
					for _, gym in plan.gyms do
						local arrival = plan.arrivals[gym.worldId]
						local ahead = (gym.position.x - arrival.x) * Layout.FACING.x
							+ (gym.position.z - arrival.z) * Layout.FACING.z
						local away = flat(gym.position, arrival)
						-- Straight ahead of the way the player faces, so the
						-- default camera sees it.
						expect(ahead > 0).toBeTrue()
						expect(ahead / away > math.cos(math.rad(20))).toBeTrue()
						for _, stand in plan.eggStands do
							if stand.worldId == gym.worldId then
								-- Beyond the stands, and not touching any of them.
								local standAhead = (stand.position.x - arrival.x) * Layout.FACING.x
									+ (stand.position.z - arrival.z) * Layout.FACING.z
								expect(ahead > standAhead).toBeTrue()
								expect(
									ahead - Layout.GYM_SIZE.depth / 2
										> standAhead + Layout.STAND_EXTENT
								).toBeTrue()
							end
						end
						for _, portal in plan.portals do
							if portal.worldId == gym.worldId then
								expect(
									flat(gym.position, portal.position)
										> gymReach + Layout.PORTAL_EXTENT
								).toBeTrue()
							end
						end
						for _, island in plan.islands do
							if island.worldId == gym.worldId then
								-- The gym faces the arrival point straight ahead, so
								-- its footprint lines up with the island's sides.
								local half = island.size / 2
								local dx = math.abs(gym.position.x - island.origin.x)
								local dz = math.abs(gym.position.z - island.origin.z)
								expect(dx + Layout.GYM_SIZE.width / 2 < half).toBeTrue()
								expect(dz + Layout.GYM_SIZE.depth / 2 < half).toBeTrue()
							end
						end
					end
				end
				check(Layout.plan())
				check(Layout.plan(withFourthWorld()))
				local crowded = table.clone(Config.worlds)
				local first = table.clone(crowded[1])
				local many = {}
				for _, egg in Config.eggs do
					table.insert(many, egg.id)
				end
				first.eggs = many
				crowded[1] = first
				check(Layout.plan(crowded))
			end
		)

		it("gives every egg in every world a stand with its name and price", function()
			local plan = Layout.plan()
			local standFor: { [string]: Layout.EggStand } = {}
			for _, stand in plan.eggStands do
				standFor[stand.worldId .. "/" .. stand.eggId] = stand
			end
			for _, world in Config.worlds do
				for _, eggId in world.eggs do
					local stand = standFor[world.id .. "/" .. eggId]
					expect(stand ~= nil).toBeTrue()
					local egg = Config.eggById[eggId]
					expect((stand :: Layout.EggStand).name).toEqual(egg.name)
					expect((stand :: Layout.EggStand).price).toEqual(
						Layout.formatCount(egg.price) .. " coins"
					)
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
