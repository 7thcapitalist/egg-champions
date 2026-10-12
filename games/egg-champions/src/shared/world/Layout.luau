--!strict
--[[
	Layout: where every generated world prop goes, and what its label says.

	The world builder (server/World/Builder) turns this plan into parts, one
	prop per entry, so this module is the single place that decides how many
	egg stands, gyms and portals exist. It reads only the world table and the
	egg and type lookups from config, so a new world or egg in the spec changes
	the plan with no code change.

	It needs no Roblox service: positions are plain { x, y, z } tables in
	studs, so the headless test runner can check the plan.

	The numbers below are geometry (island size, spacing), not game numbers.
	Every price, fee and type on a label comes from config.
]]

local Config = require(script.Parent.Parent.Config)

export type Vec = { x: number, y: number, z: number }

export type Island = {
	worldId: string,
	worldIndex: number,
	name: string,
	environment: string,
	origin: Vec,
	size: number,
}

export type EggStand = {
	worldId: string,
	eggId: string,
	label: string,
	position: Vec,
}

export type GymSite = {
	worldId: string,
	worldIndex: number,
	label: string,
	position: Vec,
}

export type Portal = {
	worldId: string,
	fromIndex: number,
	-- The world this portal leads to, or nil past the last world.
	toIndex: number?,
	toWorldId: string?,
	label: string,
	-- What a player is told when the portal refuses them.
	lockedMessage: string,
	position: Vec,
}

export type Plan = {
	islands: { Island },
	eggStands: { EggStand },
	gyms: { GymSite },
	portals: { Portal },
	-- Where a player lands on each world, keyed by world id.
	arrivals: { [string]: Vec },
	-- Where the SpawnLocation sits: on the first world.
	spawn: Vec,
}

-- Geometry, in studs. Ground tops sit at y = 0.
local ISLAND_SIZE = 160
local ISLAND_SPACING = 400
local GRID_COLUMNS = 3
local STAND_ROW_Z = -40
local STAND_GAP = 24
local GYM_OFFSET: Vec = { x = 0, y = 0, z = 50 }
local PORTAL_OFFSET: Vec = { x = 60, y = 0, z = 0 }
local ARRIVAL_OFFSET: Vec = { x = 0, y = 0, z = 0 }

local Layout = {}

Layout.ISLAND_SIZE = ISLAND_SIZE

local function add(a: Vec, b: Vec): Vec
	return { x = a.x + b.x, y = a.y + b.y, z = a.z + b.z }
end

-- A whole number with thousands separators: 10000000000 -> "10,000,000,000".
function Layout.formatCount(value: number): string
	local digits = string.format("%.0f", math.abs(value))
	local out = ""
	local count = 0
	for i = #digits, 1, -1 do
		if count > 0 and count % 3 == 0 then
			out = "," .. out
		end
		out = string.sub(digits, i, i) .. out
		count += 1
	end
	if value < 0 then
		out = "-" .. out
	end
	return out
end

-- Where the island of the nth world (1 based, in index order) sits.
function Layout.islandOrigin(slot: number): Vec
	local column = (slot - 1) % GRID_COLUMNS
	local row = (slot - 1) // GRID_COLUMNS
	return { x = column * ISLAND_SPACING, y = 0, z = row * ISLAND_SPACING }
end

function Layout.eggLabel(eggId: string): string
	local egg = Config.eggById[eggId]
	return string.format("%s\n%s coins", egg.name, Layout.formatCount(egg.price))
end

function Layout.gymLabel(world: Config.World): string
	local leaderType = Config.typeById[world.gym.leader_type]
	return string.format(
		"%s Gym\nFee: %s coins\nLeader type: %s",
		world.name,
		Layout.formatCount(world.gym.fee),
		leaderType.name
	)
end

-- Builds the plan from a world list. Defaults to Config.worlds; a test may pass
-- its own list to show a new world needs no code change.
function Layout.plan(worldList: { Config.World }?): Plan
	local worlds = table.clone(worldList or Config.worlds)
	table.sort(worlds, function(a: Config.World, b: Config.World): boolean
		return a.index < b.index
	end)

	local byIndex: { [number]: Config.World } = {}
	local lastIndex = -math.huge
	for _, world in worlds do
		byIndex[world.index] = world
		lastIndex = math.max(lastIndex, world.index)
	end

	local plan: Plan = {
		islands = {},
		eggStands = {},
		gyms = {},
		portals = {},
		arrivals = {},
		spawn = { x = 0, y = 0, z = 0 },
	}

	for slot, world in worlds do
		local origin = Layout.islandOrigin(slot)
		table.insert(plan.islands, {
			worldId = world.id,
			worldIndex = world.index,
			name = world.name,
			environment = world.environment,
			origin = origin,
			size = ISLAND_SIZE,
		})
		plan.arrivals[world.id] = add(origin, ARRIVAL_OFFSET)
		if slot == 1 then
			plan.spawn = add(origin, ARRIVAL_OFFSET)
		end

		local eggCount = #world.eggs
		for position, eggId in world.eggs do
			local x = (position - (eggCount + 1) / 2) * STAND_GAP
			table.insert(plan.eggStands, {
				worldId = world.id,
				eggId = eggId,
				label = Layout.eggLabel(eggId),
				position = add(origin, { x = x, y = 0, z = STAND_ROW_Z }),
			})
		end

		table.insert(plan.gyms, {
			worldId = world.id,
			worldIndex = world.index,
			label = Layout.gymLabel(world),
			position = add(origin, GYM_OFFSET),
		})

		local nextWorld = byIndex[world.index + 1]
		local portal: Portal
		if nextWorld ~= nil then
			portal = {
				worldId = world.id,
				fromIndex = world.index,
				toIndex = nextWorld.index,
				toWorldId = nextWorld.id,
				label = string.format("To %s\nBeat the %s Gym to open", nextWorld.name, world.name),
				lockedMessage = string.format(
					"Locked. Beat the %s Gym to open %s.",
					world.name,
					nextWorld.name
				),
				position = add(origin, PORTAL_OFFSET),
			}
		else
			local soon = string.format("World %d coming soon", lastIndex + 1)
			portal = {
				worldId = world.id,
				fromIndex = world.index,
				toIndex = nil,
				toWorldId = nil,
				label = soon,
				lockedMessage = soon .. ".",
				position = add(origin, PORTAL_OFFSET),
			}
		end
		table.insert(plan.portals, portal)
	end

	return plan
end

return Layout
