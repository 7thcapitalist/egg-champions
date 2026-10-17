--!strict
--[[
	Scenery: the plan for everything on an island that is not a game prop.
	Paths, the clear zones kept around the game props, hills, ponds, flower
	fields, lava streams, fences, and every tree, rock and bush.

	It works from Layout.plan (where the spawn, egg stands, gym and portal go)
	and WorldLook (what each world is made of), with a seeded random of its
	own, so the same seed always gives the same island. It needs no Roblox
	service: the server builds terrain and props from the plan
	(server/World), and the headless tests check it.

	Rules the plan keeps, and the specs check:
	- no prop, hill, pond, field or stream inside a clear zone or on a path;
	- every feature and prop inside its island;
	- the estimated part count of a world under PART_BUDGET.

	The numbers here are geometry and art, not game numbers.
]]

local Layout = require(script.Parent.Layout)
local WorldLook = require(script.Parent.WorldLook)
local SceneLayout = require(script.Parent.SceneLayout)

export type P = { x: number, z: number }
export type Circle = { x: number, z: number, r: number }
export type Segment = { a: P, b: P, width: number }
export type Hill = { x: number, z: number, radius: number, height: number }
export type Prop = {
	kind: string,
	x: number,
	y: number,
	z: number,
	turn: number,
	scale: number,
	radius: number,
	variant: number,
}
export type Stream = { points: { P }, width: number }
export type Light = { x: number, y: number, z: number }

export type WorldScenery = {
	worldId: string,
	worldIndex: number,
	theme: string,
	origin: Layout.Vec,
	half: number,
	seed: number,
	paths: { Segment },
	clear: { Circle },
	hills: { Hill },
	ponds: { Circle },
	fields: { Circle },
	streams: { Stream },
	lights: { Light },
	props: { Prop },
	fences: { Segment },
	signSpot: Layout.Vec,
	-- The point the sign faces: the arrival point, so its text reads toward
	-- the player who just landed.
	signLook: Layout.Vec,
	parts: number,
}

local Scenery = {}

-- Most parts a world may hold, props and game props together.
Scenery.PART_BUDGET = 1500
Scenery.SEED = 34001
Scenery.PATH_WIDTH = 6
-- Open ground kept between a feature and the island's edge.
Scenery.EDGE_MARGIN = 3
-- Where the world's name sign stands, from the island's center: in front of
-- the arrival point (players face -z on arrival), off to the left of the
-- path to the gym and wide of the left egg stands, so it is in view on
-- landing without hiding the gym or a stand label.
Scenery.SIGN_OFFSET = table.freeze({ x = -20, y = 0, z = -14 })
-- The name sign's board, in studs: its center height, and the two posts
-- that stand at its edges, outside the lettering.
Scenery.SIGN_BOARD = table.freeze({ width = 10, height = 4, y = 7, post = 1 })

-- An egg stand's label, in studs: a plate just above the egg. The stand's
-- plinth height and how far the egg floats above it place the egg; the
-- label's bottom sits `gap` above the egg's top.
Scenery.STAND_LABEL = table.freeze({
	width = 8,
	height = 3,
	gap = 0.5,
	plinth = 3,
	hover = 0.5,
	-- The placeholder egg's height, for an egg with no model height.
	placeholderEgg = 5,
})

-- The gym's entrance sign, in studs: its board, its center height, and how
-- far in front of the gym's center (toward the arrival point) it hangs.
Scenery.GYM_SIGN = table.freeze({ width = 16, height = 5, y = 13, forward = 12.5 })

-- The camera a player has on arrival: behind the character by `back`, at an
-- eye height between the two given, looking the way the player faces. A
-- point is in frame while its sideways offset over its depth is at most
-- halfWidth (a 16:9 screen at the default field of view, with a little
-- margin). The specs project the signs with several of these cameras.
Scenery.ARRIVAL_VIEW = table.freeze({
	backs = table.freeze({ 0, 12, 20 }),
	-- Roblox's default camera distance, which a player has on landing.
	defaultBack = 12.5,
	heights = table.freeze({ 5, 8, 12 }),
	halfWidth = math.tan(math.rad(55)),
})
Scenery.FENCE_PIECE = 8
-- A fence runs this far outside the path's edge.
Scenery.FENCE_OFFSET = 1.5
Scenery.FENCE_PARTS = 3
Scenery.LIGHT_PARTS = 1
-- An upper bound on the parts of the game props every world has (sign,
-- arrival pad, gym, portal), and of each egg stand, for the budget estimate.
Scenery.FIXED_PARTS = 440
Scenery.STAND_PARTS = 13

-- Clear zone radii around the game props, in studs.
Scenery.ARRIVAL_CLEAR = 14
Scenery.STAND_CLEAR = Layout.STAND_EXTENT + 5
Scenery.GYM_CLEAR = math.sqrt((Layout.GYM_SIZE.width / 2) ^ 2 + (Layout.GYM_SIZE.depth / 2) ^ 2) + 5
Scenery.PORTAL_CLEAR = Layout.PORTAL_EXTENT + 6
Scenery.SIGN_CLEAR = 7

-- Every prop kind: its footprint radius at scale 1 and how many parts the
-- server's Kit builds it from.
Scenery.PROPS = table.freeze({
	tree = table.freeze({ radius = 4.5, parts = 5 }),
	palm = table.freeze({ radius = 4, parts = 8 }),
	deadTree = table.freeze({ radius = 3, parts = 4 }),
	rock = table.freeze({ radius = 3, parts = 4 }),
	boulder = table.freeze({ radius = 3.5, parts = 3 }),
	bush = table.freeze({ radius = 2.5, parts = 3 }),
	flower = table.freeze({ radius = 0.8, parts = 2 }),
} :: { [string]: { radius: number, parts: number } })

local SCALE_MIN = 0.85
local SCALE_MAX = 1.25
local TRIES_PER_ITEM = 40
local STREAM_STEP = 7
local STREAM_POINTS = 6
local STREAM_MIN_POINTS = 3
local POND_RIM = 3
local LIGHT_HEIGHT = 1.5

-- A Park-Miller random: pure arithmetic, exact in doubles, so the same seed
-- gives the same island on every machine.
local MODULUS = 2147483647
local function newRandom(seed: number): () -> number
	local state = seed % (MODULUS - 1) + 1
	return function(): number
		state = (state * 16807) % MODULUS
		return (state - 1) / (MODULUS - 1)
	end
end

local function between(random: () -> number, low: number, high: number): number
	return low + (high - low) * random()
end

local function distance(ax: number, az: number, bx: number, bz: number): number
	return math.sqrt((ax - bx) ^ 2 + (az - bz) ^ 2)
end

-- The height of the center of an egg stand's label above the stand's base,
-- for an egg `eggHeight` studs tall (nil for the placeholder).
function Scenery.standLabelY(eggHeight: number?): number
	local l = Scenery.STAND_LABEL
	return l.plinth + l.hover + (eggHeight or l.placeholderEgg) + l.gap + l.height / 2
end

export type ScreenRect = { left: number, right: number, bottom: number, top: number }

-- Where a point lands on the arrival camera's screen: its sideways offset
-- and its height over its depth, and the depth. `back` and `eye` pick the
-- camera (see ARRIVAL_VIEW). Depth is 0 or less behind the camera.
function Scenery.project(
	arrival: Layout.Vec,
	back: number,
	eye: number,
	x: number,
	y: number,
	z: number
): (number, number, number)
	local f = Layout.FACING
	-- The camera's right, with the player facing f on the ground plane.
	local rx, rz = -f.z, f.x
	local ex, ez = arrival.x - f.x * back, arrival.z - f.z * back
	local depth = (x - ex) * f.x + (z - ez) * f.z
	local side = (x - ex) * rx + (z - ez) * rz
	if depth <= 0 then
		return 0, 0, depth
	end
	return side / depth, (y - (arrival.y + eye)) / depth, depth
end

-- The screen rectangle of a flat label `width` by `height` studs centered at
-- (x, y, z) and facing the camera, or nil when it is behind the camera.
function Scenery.screenRect(
	arrival: Layout.Vec,
	back: number,
	eye: number,
	center: Layout.Vec,
	width: number,
	height: number
): ScreenRect?
	local u, v, depth = Scenery.project(arrival, back, eye, center.x, center.y, center.z)
	if depth <= 0 then
		return nil
	end
	local hw, hh = width / 2 / depth, height / 2 / depth
	return { left = u - hw, right = u + hw, bottom = v - hh, top = v + hh }
end

function Scenery.rectsOverlap(a: ScreenRect, b: ScreenRect): boolean
	return a.left < b.right and b.left < a.right and a.bottom < b.top and b.bottom < a.top
end

-- True when the ground point (x, z) is in the frame of the default camera
-- a player has on landing.
function Scenery.inArrivalFrame(arrival: Layout.Vec, x: number, z: number): boolean
	local u, _, depth = Scenery.project(arrival, Scenery.ARRIVAL_VIEW.defaultBack, 0, x, 0, z)
	return depth > 0 and math.abs(u) <= Scenery.ARRIVAL_VIEW.halfWidth
end

-- The center of the gym's entrance sign, for a gym at `gym` facing `arrival`.
function Scenery.gymSignCenter(gym: Layout.Vec, arrival: Layout.Vec): Layout.Vec
	local dx, dz = arrival.x - gym.x, arrival.z - gym.z
	local length = math.sqrt(dx * dx + dz * dz)
	local forward = Scenery.GYM_SIGN.forward
	if length > 0 then
		dx, dz = dx / length * forward, dz / length * forward
	end
	return { x = gym.x + dx, y = gym.y + Scenery.GYM_SIGN.y, z = gym.z + dz }
end

-- The distance from (x, z) to the segment from a to b, on the ground plane.
function Scenery.toSegment(x: number, z: number, a: P, b: P): number
	local dx, dz = b.x - a.x, b.z - a.z
	local length2 = dx * dx + dz * dz
	local t = 0
	if length2 > 0 then
		t = math.clamp(((x - a.x) * dx + (z - a.z) * dz) / length2, 0, 1)
	end
	return distance(x, z, a.x + t * dx, a.z + t * dz)
end

-- The radius a hill covers on the ground: a ball of `radius` whose top stands
-- `height` above the ground.
function Scenery.hillFootprint(hill: Hill): number
	local h = math.min(hill.height, hill.radius)
	return math.sqrt(2 * hill.radius * h - h * h)
end

-- The ground height at (x, z): 0, or the top of a hill there.
function Scenery.heightAt(scenery: WorldScenery, x: number, z: number): number
	local top = 0
	for _, hill in scenery.hills do
		local d = distance(x, z, hill.x, hill.z)
		if d < hill.radius then
			local y = hill.height - hill.radius + math.sqrt(hill.radius ^ 2 - d ^ 2)
			top = math.max(top, y)
		end
	end
	return top
end

-- True when a circle at (x, z) of radius r lies inside the island, with the
-- edge margin to spare.
function Scenery.onIsland(scenery: WorldScenery, x: number, z: number, r: number): boolean
	local reach = scenery.half - Scenery.EDGE_MARGIN - r
	return math.abs(x - scenery.origin.x) <= reach and math.abs(z - scenery.origin.z) <= reach
end

-- True when a circle at (x, z) of radius r stays out of every clear zone and
-- off every path.
function Scenery.clearOfSites(scenery: WorldScenery, x: number, z: number, r: number): boolean
	for _, zone in scenery.clear do
		if distance(x, z, zone.x, zone.z) < zone.r + r then
			return false
		end
	end
	for _, path in scenery.paths do
		if Scenery.toSegment(x, z, path.a, path.b) < path.width / 2 + r + 1 then
			return false
		end
	end
	return true
end

local function nearStream(scenery: WorldScenery, x: number, z: number, r: number): boolean
	for _, stream in scenery.streams do
		for i = 2, #stream.points do
			local d = Scenery.toSegment(x, z, stream.points[i - 1], stream.points[i])
			if d < stream.width / 2 + r + 1 then
				return true
			end
		end
	end
	return false
end

local function inCircles(circles: { Circle }, x: number, z: number, r: number, pad: number): boolean
	for _, c in circles do
		if distance(x, z, c.x, c.z) < c.r + r + pad then
			return true
		end
	end
	return false
end

local function nearHills(hills: { Hill }, x: number, z: number, r: number): boolean
	for _, hill in hills do
		if distance(x, z, hill.x, hill.z) < Scenery.hillFootprint(hill) + r then
			return true
		end
	end
	return false
end

local function nearFence(scenery: WorldScenery, x: number, z: number, r: number): boolean
	for _, fence in scenery.fences do
		if Scenery.toSegment(x, z, fence.a, fence.b) < r + 0.5 then
			return true
		end
	end
	return false
end

local function nearProps(props: { Prop }, x: number, z: number, r: number): boolean
	for _, prop in props do
		if distance(x, z, prop.x, prop.z) < prop.radius + r + 0.5 then
			return true
		end
	end
	return false
end

-- A random point on the island, kept `r` inside it.
local function somewhere(scenery: WorldScenery, random: () -> number, r: number): (number, number)
	local reach = math.max(0, scenery.half - Scenery.EDGE_MARGIN - r)
	local o = scenery.origin
	return o.x + between(random, -reach, reach), o.z + between(random, -reach, reach)
end

-- Fences keep out of the arrival camera's frame: a piece cut short by a
-- clear zone would end there as a lone post and rail. `arrival` is where the
-- player lands.
local function addFences(scenery: WorldScenery, path: Segment, arrival: Layout.Vec)
	local dx, dz = path.b.x - path.a.x, path.b.z - path.a.z
	local length = math.sqrt(dx * dx + dz * dz)
	if length <= 0 then
		return
	end
	local ux, uz = dx / length, dz / length
	-- The sideways direction, to each side of the path.
	local sx, sz = -uz, ux
	local offset = path.width / 2 + Scenery.FENCE_OFFSET
	local pieces = math.floor(length / Scenery.FENCE_PIECE)
	for side = -1, 1, 2 do
		for i = 0, pieces - 1 do
			local t0, t1 = i * Scenery.FENCE_PIECE, (i + 1) * Scenery.FENCE_PIECE
			local a = {
				x = path.a.x + ux * t0 + sx * offset * side,
				z = path.a.z + uz * t0 + sz * offset * side,
			}
			local b = {
				x = path.a.x + ux * t1 + sx * offset * side,
				z = path.a.z + uz * t1 + sz * offset * side,
			}
			local keep = Scenery.onIsland(scenery, a.x, a.z, 0)
				and Scenery.onIsland(scenery, b.x, b.z, 0)
			if keep then
				-- Both ends and the middle stay out of every clear zone.
				for _, spot in { a, b, { x = (a.x + b.x) / 2, z = (a.z + b.z) / 2 } } do
					if inCircles(scenery.clear, spot.x, spot.z, 0, 1) then
						keep = false
					end
				end
			end
			if
				keep
				and (
					Scenery.inArrivalFrame(arrival, a.x, a.z)
					or Scenery.inArrivalFrame(arrival, b.x, b.z)
				)
			then
				keep = false
			end
			if keep then
				table.insert(scenery.fences, { a = a, b = b, width = 0 })
			end
		end
	end
end

local function addHills(scenery: WorldScenery, look: WorldLook.Look, random: () -> number)
	local f = look.features
	for _ = 1, f.hills do
		for _ = 1, TRIES_PER_ITEM do
			local hill: Hill = {
				x = 0,
				z = 0,
				radius = between(random, f.hillRadius.min, f.hillRadius.max),
				height = between(random, f.hillHeight.min, f.hillHeight.max),
			}
			local reach = Scenery.hillFootprint(hill)
			hill.x, hill.z = somewhere(scenery, random, reach)
			local ok = Scenery.clearOfSites(scenery, hill.x, hill.z, reach)
			if ok then
				for _, other in scenery.hills do
					local apart = distance(hill.x, hill.z, other.x, other.z)
					if apart < (reach + Scenery.hillFootprint(other)) * 0.6 then
						ok = false
					end
				end
			end
			if ok then
				table.insert(scenery.hills, hill)
				break
			end
		end
	end
end

local function addCircles(
	scenery: WorldScenery,
	random: () -> number,
	into: { Circle },
	count: number,
	radius: WorldLook.Range,
	pad: number
)
	for _ = 1, count do
		-- Large features need more candidates once authored footprints are reserved.
		for _ = 1, TRIES_PER_ITEM * 4 do
			local r = between(random, radius.min, radius.max)
			local x, z = somewhere(scenery, random, r + pad)
			local ok = Scenery.clearOfSites(scenery, x, z, r + pad)
				and not nearHills(scenery.hills, x, z, r + pad)
				and not inCircles(scenery.ponds, x, z, r + pad, POND_RIM)
				and not inCircles(scenery.fields, x, z, r + pad, 0)
				and not nearFence(scenery, x, z, r + pad)
			if ok then
				table.insert(into, { x = x, z = z, r = r })
				break
			end
		end
	end
end

local function streamPointOk(scenery: WorldScenery, x: number, z: number, half: number): boolean
	return Scenery.onIsland(scenery, x, z, half)
		and Scenery.clearOfSites(scenery, x, z, half + 1)
		and not inCircles(scenery.ponds, x, z, half, POND_RIM)
end

local function addStreams(scenery: WorldScenery, look: WorldLook.Look, random: () -> number)
	local f = look.features
	local half = f.streamWidth / 2
	for _ = 1, f.streams do
		for _ = 1, TRIES_PER_ITEM do
			local x, z = somewhere(scenery, random, half)
			local heading = between(random, 0, math.pi * 2)
			local points: { P } = {}
			if streamPointOk(scenery, x, z, half) then
				table.insert(points, { x = x, z = z })
				for _ = 2, STREAM_POINTS do
					heading += between(random, -0.6, 0.6)
					local nx = x + math.cos(heading) * STREAM_STEP
					local nz = z + math.sin(heading) * STREAM_STEP
					-- Check the whole step, a stud at a time.
					local ok = true
					for s = 1, STREAM_STEP do
						local t = s / STREAM_STEP
						if not streamPointOk(scenery, x + (nx - x) * t, z + (nz - z) * t, half) then
							ok = false
							break
						end
					end
					if not ok then
						break
					end
					x, z = nx, nz
					table.insert(points, { x = x, z = z })
				end
			end
			if #points >= STREAM_MIN_POINTS then
				table.insert(scenery.streams, { points = points, width = f.streamWidth })
				for i = 1, #points, 2 do
					table.insert(scenery.lights, {
						x = points[i].x,
						y = LIGHT_HEIGHT,
						z = points[i].z,
					})
				end
				break
			end
		end
	end
end

-- True when a prop of radius r may stand at (x, z).
function Scenery.propSpotOk(
	scenery: WorldScenery,
	kind: string,
	x: number,
	z: number,
	r: number
): boolean
	if not Scenery.onIsland(scenery, x, z, r) then
		return false
	end
	if not Scenery.clearOfSites(scenery, x, z, r) then
		return false
	end
	if inCircles(scenery.ponds, x, z, r, POND_RIM) then
		return false
	end
	if nearStream(scenery, x, z, r) or nearFence(scenery, x, z, r) then
		return false
	end
	-- Flower fields hold only flowers.
	if kind ~= "flower" and inCircles(scenery.fields, x, z, r, 0) then
		return false
	end
	return not nearProps(scenery.props, x, z, r)
end

local function addProps(scenery: WorldScenery, look: WorldLook.Look, random: () -> number)
	for _, entry in look.props do
		local kind = Scenery.PROPS[entry.kind]
		if kind == nil then
			error("Scenery: unknown prop kind " .. entry.kind)
		end
		local inField = entry.kind == "flower" and #scenery.fields > 0
		for _ = 1, entry.count do
			for _ = 1, TRIES_PER_ITEM do
				local scale = between(random, SCALE_MIN, SCALE_MAX)
				local r = kind.radius * scale
				local x, z
				if inField then
					local field =
						scenery.fields[1 + math.floor(random() * #scenery.fields) % #scenery.fields]
					local angle = between(random, 0, math.pi * 2)
					local reach = math.sqrt(random()) * math.max(0, field.r - r)
					x, z = field.x + math.cos(angle) * reach, field.z + math.sin(angle) * reach
				else
					x, z = somewhere(scenery, random, r)
				end
				local turn = between(random, 0, math.pi * 2)
				if Scenery.propSpotOk(scenery, entry.kind, x, z, r) then
					table.insert(scenery.props, {
						kind = entry.kind,
						x = x,
						y = Scenery.heightAt(scenery, x, z),
						z = z,
						turn = turn,
						scale = scale,
						radius = r,
						variant = #scenery.props + 1,
					})
					break
				end
			end
		end
	end
end

-- The estimated part count of a world.
function Scenery.partCount(scenery: WorldScenery, stands: number): number
	local count = Scenery.FIXED_PARTS + Scenery.STAND_PARTS * stands
	count += #scenery.fences * Scenery.FENCE_PARTS
	count += #scenery.lights * Scenery.LIGHT_PARTS
	for _, prop in scenery.props do
		count += Scenery.PROPS[prop.kind].parts
	end
	return count
end

-- The scenery of one island of a Layout plan.
function Scenery.forIsland(plan: Layout.Plan, island: Layout.Island): WorldScenery
	local look = WorldLook.forWorld(island.worldId, island.environment)
	local o = island.origin
	local seed = Scenery.SEED + island.worldIndex * 7919
	local random = newRandom(seed)
	local arrival = plan.arrivals[island.worldId]
	local signSpot = {
		x = o.x + Scenery.SIGN_OFFSET.x,
		y = o.y,
		z = o.z + Scenery.SIGN_OFFSET.z,
	}
	local scenery: WorldScenery = {
		worldId = island.worldId,
		worldIndex = island.worldIndex,
		theme = look.key,
		origin = o,
		half = island.size / 2,
		seed = seed,
		paths = {},
		clear = {},
		hills = {},
		ponds = {},
		fields = {},
		streams = {},
		lights = {},
		props = {},
		fences = {},
		signSpot = signSpot,
		signLook = { x = arrival.x, y = arrival.y, z = arrival.z },
		parts = 0,
	}

	local here: P = { x = arrival.x, z = arrival.z }
	-- Authored landmark footprints and their access lane, before random scenery.
	table.insert(scenery.clear, { x = o.x - 64, z = o.z - 57, r = 27 })
	table.insert(scenery.clear, { x = o.x - 58, z = o.z + 48, r = 25 })
	-- Secondary scenes have reserved footprints, so seeded props cannot grow
	-- through their structures. Their access paths join the existing loop.
	for _, scene in SceneLayout.forTheme(scenery.theme) do
		table.insert(scenery.clear, { x = o.x + scene.x, z = o.z + scene.z, r = scene.radius })
		table.insert(scenery.paths, {
			a = { x = o.x + scene.accessX, z = o.z + scene.accessZ },
			b = { x = o.x + scene.x, z = o.z + scene.z },
			width = 9,
		})
	end
	table.insert(
		scenery.paths,
		{ a = { x = o.x - 58, z = o.z }, b = { x = o.x - 58, z = o.z + 90 }, width = 18 }
	)
	table.insert(scenery.paths, { a = here, b = { x = o.x - 58, z = o.z }, width = 10 })
	-- A broad scenic return loop makes the southern half explorable; the path plan
	-- excludes random props before placement.
	local loop =
		{ { -58, 0 }, { -86, 15 }, { -86, 60 }, { -42, 80 }, { 4, 72 }, { 42, 40 }, { 60, 0 } }
	for i = 2, #loop do
		table.insert(scenery.paths, {
			a = { x = o.x + loop[i - 1][1], z = o.z + loop[i - 1][2] },
			b = { x = o.x + loop[i][1], z = o.z + loop[i][2] },
			width = 7,
		})
	end
	table.insert(scenery.clear, { x = arrival.x, z = arrival.z, r = Scenery.ARRIVAL_CLEAR })
	table.insert(scenery.clear, { x = signSpot.x, z = signSpot.z, r = Scenery.SIGN_CLEAR })
	local stands = 0
	for _, stand in plan.eggStands do
		if stand.worldId == island.worldId then
			stands += 1
			table.insert(scenery.clear, {
				x = stand.position.x,
				z = stand.position.z,
				r = Scenery.STAND_CLEAR,
			})
		end
	end
	for _, gym in plan.gyms do
		if gym.worldId == island.worldId then
			table.insert(scenery.clear, {
				x = gym.position.x,
				z = gym.position.z,
				r = Scenery.GYM_CLEAR,
			})
			table.insert(scenery.paths, {
				a = here,
				b = { x = gym.position.x, z = gym.position.z },
				width = Scenery.PATH_WIDTH,
			})
		end
	end
	local fenced: { Segment } = {}
	for _, portal in plan.portals do
		if portal.worldId == island.worldId then
			table.insert(scenery.clear, {
				x = portal.position.x,
				z = portal.position.z,
				r = Scenery.PORTAL_CLEAR,
			})
			local path = {
				a = here,
				b = { x = portal.position.x, z = portal.position.z },
				width = Scenery.PATH_WIDTH,
			}
			table.insert(scenery.paths, path)
			table.insert(fenced, path)
		end
	end

	if look.features.fences then
		for _, path in fenced do
			addFences(scenery, path, arrival)
		end
	end
	addHills(scenery, look, random)
	addCircles(
		scenery,
		random,
		scenery.ponds,
		look.features.ponds,
		look.features.pondRadius,
		POND_RIM
	)
	addCircles(scenery, random, scenery.fields, look.features.fields, look.features.fieldRadius, 0)
	addStreams(scenery, look, random)
	addProps(scenery, look, random)

	-- Keep the world under its part budget, dropping the last props first.
	while #scenery.props > 0 and Scenery.partCount(scenery, stands) > Scenery.PART_BUDGET do
		table.remove(scenery.props)
	end
	scenery.parts = Scenery.partCount(scenery, stands)
	return scenery
end

-- The scenery of every island in a Layout plan, keyed by world id.
function Scenery.planAll(plan: Layout.Plan): { [string]: WorldScenery }
	local all: { [string]: WorldScenery } = {}
	for _, island in plan.islands do
		all[island.worldId] = Scenery.forIsland(plan, island)
	end
	return all
end

-- The world whose island (or the sea around it) holds (x, z), or nil out in
-- the open between islands.
function Scenery.islandAt(plan: Layout.Plan, x: number, z: number): string?
	local best: string? = nil
	local bestReach = math.huge
	for _, island in plan.islands do
		local reach = math.max(math.abs(x - island.origin.x), math.abs(z - island.origin.z))
		if reach <= island.size and reach < bestReach then
			best = island.worldId
			bestReach = reach
		end
	end
	return best
end

return Scenery
