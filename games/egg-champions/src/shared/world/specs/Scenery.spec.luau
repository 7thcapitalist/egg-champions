--!strict
--[[
	The scenery plan decides where every tree, rock, hill, pond and lava
	stream goes. These tests check its promises: nothing crowds the spawn,
	stands, gym, portal or sign, nothing sits on a path, everything is on its
	island, the same seed gives the same island, and each world stays under
	its part budget. They also check every world resolves to a whole look.
]]

local Runner = require(script.Parent.Parent.Parent.testing.Runner)
local Config = require(script.Parent.Parent.Parent.Config)
local Layout = require(script.Parent.Parent.Layout)
local Scenery = require(script.Parent.Parent.Scenery)
local WorldLook = require(script.Parent.Parent.WorldLook)

local describe = Runner.describe
local it = Runner.it
local expect = Runner.expect

local function flat(ax: number, az: number, bx: number, bz: number): number
	return math.sqrt((ax - bx) ^ 2 + (az - bz) ^ 2)
end

local function withFourthWorld(): { Config.World }
	local worlds = table.clone(Config.worlds)
	local last = worlds[#worlds]
	table.insert(worlds, {
		index = last.index + 1,
		id = "test_extra_world",
		name = "Test Extra World",
		environment = "Lava rivers",
		eggs = { last.eggs[1] },
		gym = last.gym,
	})
	return worlds
end

local function allSceneries(): { Scenery.WorldScenery }
	local list = {}
	for _, plan in { Layout.plan(), Layout.plan(withFourthWorld()) } do
		for _, island in plan.islands do
			table.insert(list, Scenery.forIsland(plan, island))
		end
	end
	return list
end

local function inZone(s: Scenery.WorldScenery, x: number, z: number, r: number): boolean
	for _, zone in s.clear do
		if flat(x, z, zone.x, zone.z) < zone.r + r then
			return true
		end
	end
	return false
end

local function onPath(s: Scenery.WorldScenery, x: number, z: number, r: number): boolean
	for _, path in s.paths do
		if Scenery.toSegment(x, z, path.a, path.b) < path.width / 2 + r then
			return true
		end
	end
	return false
end

local function inside(s: Scenery.WorldScenery, x: number, z: number, r: number): boolean
	return math.abs(x - s.origin.x) + r <= s.half and math.abs(z - s.origin.z) + r <= s.half
end

local function serialize(value: any): string
	if type(value) ~= "table" then
		if type(value) == "number" then
			return string.format("%.6f", value)
		end
		return tostring(value)
	end
	local keys = {}
	for key in value do
		table.insert(keys, tostring(key))
	end
	table.sort(keys)
	local out = {}
	for _, key in keys do
		local item = value[key]
		if item == nil then
			item = value[tonumber(key)]
		end
		table.insert(out, key .. "=" .. serialize(item))
	end
	return "{" .. table.concat(out, ",") .. "}"
end

return function()
	describe("World scenery", function()
		it("gives every world in config a whole look", function()
			for _, world in Config.worlds do
				local look = WorldLook.forWorld(world.id, world.environment)
				expect(look ~= nil).toBeTrue()
				expect(#look.props > 0).toBeTrue()
				expect(#look.greens >= 2).toBeTrue()
				local l = look.lighting
				expect(l.clockTime >= 0 and l.clockTime < 24).toBeTrue()
				expect(l.atmosphere.density >= 0 and l.atmosphere.density <= 1).toBeTrue()
				-- Bloom stays subtle.
				expect(l.bloom.intensity <= 0.6).toBeTrue()
				for _, material in
					{
						look.terrain.surface,
						look.terrain.path,
						look.terrain.cliff,
						look.terrain.shore,
						look.terrain.hill,
						look.terrain.stream,
					}
				do
					expect(WorldLook.MATERIAL_COLORS[material] ~= nil).toBeTrue()
				end
				for _, entry in look.props do
					expect(Scenery.PROPS[entry.kind] ~= nil).toBeTrue()
				end
			end
		end)

		it("matches each world to its theme: meadow, coast, volcano", function()
			local plan = Layout.plan()
			local themes = {}
			for _, island in plan.islands do
				themes[island.worldId] = Scenery.forIsland(plan, island).theme
			end
			expect(themes.green_meadow).toEqual("green_meadow")
			expect(themes.coral_coast).toEqual("coral_coast")
			expect(themes.ember_volcano).toEqual("ember_volcano")
			-- A new world picks a look from its environment words.
			local four = Layout.plan(withFourthWorld())
			local extra = four.islands[#four.islands]
			expect(Scenery.forIsland(four, extra).theme).toEqual("ember_volcano")
		end)

		it("keeps clear zones around the spawn, stands, gym, portal and sign", function()
			local plan = Layout.plan()
			for _, island in plan.islands do
				local s = Scenery.forIsland(plan, island)
				local function covered(x: number, z: number): boolean
					for _, zone in s.clear do
						if flat(x, z, zone.x, zone.z) < 0.001 then
							return true
						end
					end
					return false
				end
				local arrival = plan.arrivals[island.worldId]
				expect(covered(arrival.x, arrival.z)).toBeTrue()
				expect(covered(s.signSpot.x, s.signSpot.z)).toBeTrue()
				for _, stand in plan.eggStands do
					if stand.worldId == island.worldId then
						expect(covered(stand.position.x, stand.position.z)).toBeTrue()
					end
				end
				for _, gym in plan.gyms do
					if gym.worldId == island.worldId then
						expect(covered(gym.position.x, gym.position.z)).toBeTrue()
					end
				end
				for _, portal in plan.portals do
					if portal.worldId == island.worldId then
						expect(covered(portal.position.x, portal.position.z)).toBeTrue()
					end
				end
				-- A path from the spawn to the gym, and one to the portal.
				expect(#s.paths).toEqual(2)
			end
		end)

		it("never puts a prop in a clear zone, on a path, or off the island", function()
			for _, s in allSceneries() do
				expect(#s.props > 0).toBeTrue()
				for _, prop in s.props do
					expect(inZone(s, prop.x, prop.z, prop.radius)).toBeFalse()
					expect(onPath(s, prop.x, prop.z, prop.radius)).toBeFalse()
					expect(inside(s, prop.x, prop.z, prop.radius)).toBeTrue()
				end
			end
		end)

		it("keeps props apart, off fences and out of ponds and lava", function()
			for _, s in allSceneries() do
				for i = 1, #s.props do
					local a = s.props[i]
					for j = i + 1, #s.props do
						local b = s.props[j]
						expect(flat(a.x, a.z, b.x, b.z) >= a.radius + b.radius).toBeTrue()
					end
					for _, pond in s.ponds do
						expect(flat(a.x, a.z, pond.x, pond.z) >= pond.r + a.radius).toBeTrue()
					end
					for _, fence in s.fences do
						expect(Scenery.toSegment(a.x, a.z, fence.a, fence.b) >= a.radius).toBeTrue()
					end
					for _, stream in s.streams do
						for k = 2, #stream.points do
							local d =
								Scenery.toSegment(a.x, a.z, stream.points[k - 1], stream.points[k])
							expect(d >= stream.width / 2 + a.radius).toBeTrue()
						end
					end
				end
			end
		end)

		it(
			"puts every hill, pond, field, stream and fence on the island and off the sites",
			function()
				for _, s in allSceneries() do
					for _, hill in s.hills do
						local reach = Scenery.hillFootprint(hill)
						expect(inside(s, hill.x, hill.z, reach)).toBeTrue()
						expect(inZone(s, hill.x, hill.z, reach)).toBeFalse()
						expect(onPath(s, hill.x, hill.z, reach)).toBeFalse()
					end
					for _, list in { s.ponds, s.fields } do
						for _, c in list do
							expect(inside(s, c.x, c.z, c.r)).toBeTrue()
							expect(inZone(s, c.x, c.z, c.r)).toBeFalse()
							expect(onPath(s, c.x, c.z, c.r)).toBeFalse()
						end
					end
					for _, stream in s.streams do
						expect(#stream.points >= 3).toBeTrue()
						for k = 2, #stream.points do
							local a, b = stream.points[k - 1], stream.points[k]
							for step = 0, 10 do
								local t = step / 10
								local x, z = a.x + (b.x - a.x) * t, a.z + (b.z - a.z) * t
								expect(inside(s, x, z, stream.width / 2)).toBeTrue()
								expect(inZone(s, x, z, stream.width / 2)).toBeFalse()
								expect(onPath(s, x, z, stream.width / 2)).toBeFalse()
							end
						end
					end
					for _, fence in s.fences do
						for _, p in { fence.a, fence.b } do
							expect(inside(s, p.x, p.z, 0)).toBeTrue()
							expect(inZone(s, p.x, p.z, 0)).toBeFalse()
							expect(onPath(s, p.x, p.z, 0)).toBeFalse()
						end
					end
					for _, light in s.lights do
						expect(inside(s, light.x, light.z, 0)).toBeTrue()
					end
				end
			end
		)

		it("gives each theme its features", function()
			local plan = Layout.plan()
			local byTheme: { [string]: Scenery.WorldScenery } = {}
			for _, island in plan.islands do
				local s = Scenery.forIsland(plan, island)
				byTheme[s.theme] = s
			end
			local meadow = byTheme.green_meadow
			expect(#meadow.hills > 0).toBeTrue()
			expect(#meadow.ponds).toEqual(1)
			expect(#meadow.fields).toEqual(1)
			expect(#meadow.fences > 0).toBeTrue()
			local volcano = byTheme.ember_volcano
			expect(#volcano.streams > 0).toBeTrue()
			expect(#volcano.lights > 0).toBeTrue()
			local kinds: { [string]: boolean } = {}
			for _, prop in byTheme.coral_coast.props do
				kinds[prop.kind] = true
			end
			expect(kinds.palm).toBeTrue()
		end)

		it("rests props on the ground, or on top of a hill", function()
			for _, s in allSceneries() do
				for _, prop in s.props do
					expect(math.abs(prop.y - Scenery.heightAt(s, prop.x, prop.z)) < 0.001).toBeTrue()
					expect(prop.y >= 0).toBeTrue()
				end
			end
		end)

		it("places the same island for the same seed", function()
			local a = Layout.plan()
			local b = Layout.plan()
			for i, island in a.islands do
				local first = serialize(Scenery.forIsland(a, island))
				local second = serialize(Scenery.forIsland(b, b.islands[i]))
				expect(first).toEqual(second)
			end
			-- Different worlds get different seeds, so islands differ.
			local one = Scenery.forIsland(a, a.islands[1])
			local two = Scenery.forIsland(a, a.islands[2])
			expect(one.seed ~= two.seed).toBeTrue()
		end)

		it("keeps every world under its part budget", function()
			for _, s in allSceneries() do
				expect(s.parts <= Scenery.PART_BUDGET).toBeTrue()
				expect(s.parts > Scenery.FIXED_PARTS).toBeTrue()
			end
		end)

		it("finds which world a point is on", function()
			local plan = Layout.plan()
			for _, island in plan.islands do
				local o = island.origin
				expect(Scenery.islandAt(plan, o.x, o.z)).toEqual(island.worldId)
				expect(Scenery.islandAt(plan, o.x + island.size / 2 - 1, o.z - 10)).toEqual(
					island.worldId
				)
			end
			expect(Scenery.islandAt(plan, -100000, -100000)).toEqual(nil)
		end)
	end)
end
