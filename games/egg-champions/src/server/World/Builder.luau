--!strict
--[[
	Builder: generates every world from the world table. Nothing is placed by hand.

	Builder.buildAll reads the plan from shared/world/Layout (which reads
	Config.worlds) and the scenery plan from shared/world/Scenery, and builds,
	for each world, one island: terrain (ground, shores, water, hills, ponds,
	lava, paths, from server/World/Terrain), scenery props (trees, rocks,
	fences, lights), a name sign, one egg stand per egg, one gym arena and one
	portal. Each world's instances go under one folder in Workspace,
	"World_<id>", tagged with the Generated attribute, so a rebuild clears and
	regenerates those folders and the terrain, and touches nothing else.

	Every part is anchored. Each world's part count is checked against
	Scenery.PART_BUDGET after the build and stored on its folder.

	It also removes the placeholder Baseplate from the Rojo project (the
	generated ground replaces it) and moves the SpawnLocation onto world 1.

	Colors come from shared/world/WorldPalette, the one palette table, keyed
	by world id. A world with no row gets one picked from keywords in its
	environment string, so a new world in the spec still builds with no code
	change. The client reads the same table for each world's unlock swirl.

	Returns what it built, counted from the instances themselves, and errors if
	that differs from the plan.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Layout = require(Shared:WaitForChild("world"):WaitForChild("Layout"))
local Scenery = require(Shared:WaitForChild("world"):WaitForChild("Scenery"))
local WorldLook = require(Shared:WaitForChild("world"):WaitForChild("WorldLook"))
local PetLook = require(Shared:WaitForChild("visual"):WaitForChild("PetLook"))
local WorldPalette = require(Shared:WaitForChild("world"):WaitForChild("WorldPalette"))
local WorldNames = require(Shared:WaitForChild("world"):WaitForChild("Names"))
local Kit = require(script.Parent:WaitForChild("Kit"))
local WorldTerrain = require(script.Parent:WaitForChild("Terrain"))

-- Each egg's configured model height in studs (GameConfig.models, built from
-- assets/models.json), so a stand's sign clears its real egg. An egg with no
-- entry is left out and its stand uses the placeholder height.
local function eggHeights(): { [string]: number }
	local heights: { [string]: number } = {}
	local source = ReplicatedStorage:WaitForChild("GameConfig"):FindFirstChild("models")
	if source == nil or not source:IsA("ModuleScript") then
		return heights
	end
	local ok, data = pcall(require, source)
	if not ok or type(data) ~= "table" or type(data.entries) ~= "table" then
		return heights
	end
	for _, entry in data.entries do
		if
			entry.kind == "egg"
			and type(entry.id) == "string"
			and type(entry.height) == "number"
		then
			heights[entry.id] = entry.height
		end
	end
	return heights
end

type Palette = Kit.Palette
type Vec = Layout.Vec

export type PortalSite = {
	trigger: BasePart,
	portal: Layout.Portal,
}

export type StandSite = {
	trigger: BasePart,
	stand: Layout.EggStand,
	model: Model,
}

export type Built = {
	plan: Layout.Plan,
	folders: { [string]: Folder },
	eggStands: { StandSite },
	gyms: { Model },
	portals: { PortalSite },
	counts: { eggStands: number, gyms: number, portals: number },
}

local GENERATED_ATTRIBUTE = "GeneratedWorld"
local PORTAL_TAG = "Portal"
-- How far a prop sinks into the ground, so it never floats on the voxel
-- terrain of a hill.
local PROP_SINK = 0.4

local function color(c: WorldPalette.RGB): Color3
	return Color3.fromRGB(c.r, c.g, c.b)
end

-- Turns a shared WorldPalette row into the Color3 and Enum form Kit takes.
local converted: { [WorldPalette.Palette]: Palette } = {}
local function paletteFor(worldId: string, environment: string): Palette
	local row = WorldPalette.forWorld(worldId, environment)
	local look = WorldLook.forWorld(worldId, environment)
	local done = converted[row]
	if done ~= nil then
		return done
	end
	local material = (Enum.Material :: any)[row.groundMaterial] :: Enum.Material
	local made: Palette = {
		ground = color(row.ground),
		groundMaterial = material,
		cliff = color(row.cliff),
		water = color(row.water),
		trunk = color(row.trunk),
		leaf = color(row.leaf),
		rock = color(row.rock),
		accent = color(row.accent),
		trim = color(row.trim),
		glow = color(row.glow),
		text = color(row.text),
		greens = {},
		flowers = {},
	}
	for _, c in look.greens do
		table.insert(made.greens, color(c))
	end
	for _, c in look.flowers do
		table.insert(made.flowers, color(c))
	end
	converted[row] = made
	return made
end

local Builder = {}

Builder.paletteFor = paletteFor

local function at(v: Vec): CFrame
	return CFrame.new(v.x, v.y, v.z)
end

-- Faces a prop at `position` toward `target` on the ground plane.
local function facing(position: Vec, target: Vec): CFrame
	local from = Vector3.new(position.x, position.y, position.z)
	local to = Vector3.new(target.x, position.y, target.z)
	if (to - from).Magnitude < 0.01 then
		return CFrame.new(from)
	end
	return CFrame.lookAt(from, to)
end

local function triggerOf(model: Model): BasePart
	local trigger = model:FindFirstChild("Trigger")
	if trigger == nil or not trigger:IsA("BasePart") then
		error("Builder: prop " .. model.Name .. " has no Trigger part")
	end
	return trigger
end

-- Removes every folder a previous build made, and the terrain, and nothing
-- else.
function Builder.clear()
	for _, child in Workspace:GetChildren() do
		if child:IsA("Folder") and child:GetAttribute(GENERATED_ATTRIBUTE) == true then
			child:Destroy()
		end
	end
	WorldTerrain.clear()
end

type PropBuilder = (CFrame, Palette, number, number) -> Model

local PROP_BUILDERS: { [string]: PropBuilder } = {
	tree = Kit.tree,
	palm = Kit.palm,
	deadTree = Kit.deadTree,
	rock = Kit.rock,
	boulder = Kit.boulder,
	bush = Kit.bush,
	flower = Kit.flower,
}

local function buildScenery(folder: Folder, scenery: Scenery.WorldScenery, palette: Palette)
	local holder = Instance.new("Folder")
	holder.Name = "Scenery"
	holder.Parent = folder
	for _, prop in scenery.props do
		local make = PROP_BUILDERS[prop.kind]
		if make == nil then
			error("Builder: no Kit builder for prop kind " .. prop.kind)
		end
		local base = CFrame.new(prop.x, prop.y - PROP_SINK, prop.z) * CFrame.Angles(0, prop.turn, 0)
		make(base, palette, prop.scale, prop.variant).Parent = holder
	end
	for _, fence in scenery.fences do
		Kit.fence(
			Vector3.new(fence.a.x, 0, fence.a.z),
			Vector3.new(fence.b.x, 0, fence.b.z),
			palette
		).Parent =
			holder
	end
	local look = WorldLook.LOOKS[scenery.theme]
	local glow = color(look.streamGlow)
	for _, light in scenery.lights do
		Kit.glow(Vector3.new(light.x, light.y, light.z), glow).Parent = holder
	end
end

-- Anchors every part in a world and returns how many there are.
local function settle(folder: Folder): number
	local count = 0
	for _, item in folder:GetDescendants() do
		if item:IsA("BasePart") then
			item.Anchored = true
			count += 1
		end
	end
	return count
end

local function countProps(folders: { [string]: Folder }, prop: string): number
	local count = 0
	for _, folder in folders do
		for _, item in folder:GetDescendants() do
			if item:IsA("Model") and item:GetAttribute("Prop") == prop then
				count += 1
			end
		end
	end
	return count
end

-- Builds every world from config. Safe to call again: it clears its own
-- folders first.
function Builder.buildAll(): Built
	local plan = Layout.plan()
	local sceneries = Scenery.planAll(plan)
	Builder.clear()
	WorldTerrain.paint()

	local baseplate = Workspace:FindFirstChild("Baseplate")
	if baseplate ~= nil and baseplate:IsA("BasePart") then
		baseplate:Destroy()
	end

	local built: Built = {
		plan = plan,
		folders = {},
		eggStands = {},
		gyms = {},
		portals = {},
		counts = { eggStands = 0, gyms = 0, portals = 0 },
	}

	local byWorld: { [string]: Palette } = {}
	for _, island in plan.islands do
		local palette = paletteFor(island.worldId, island.environment)
		byWorld[island.worldId] = palette

		local folder = Instance.new("Folder")
		folder.Name = "World_" .. island.worldId
		folder:SetAttribute(GENERATED_ATTRIBUTE, true)
		folder:SetAttribute("WorldId", island.worldId)
		folder:SetAttribute("WorldIndex", island.worldIndex)
		built.folders[island.worldId] = folder

		local scenery = sceneries[island.worldId]
		WorldTerrain.build(scenery)
		local o = island.origin
		Kit.sign(facing(scenery.signSpot, o), palette, island.name).Parent = folder
		if island.worldIndex ~= plan.islands[1].worldIndex then
			Kit.arrivalPad(at(plan.arrivals[island.worldId]), palette).Parent = folder
		end
		buildScenery(folder, scenery, palette)
	end

	local heights = eggHeights()
	for _, stand in plan.eggStands do
		local folder = built.folders[stand.worldId]
		local center = plan.arrivals[stand.worldId]
		-- Stands face the island center, so the Trigger pad is on the near side.
		local model = Kit.eggStand(
			facing(stand.position, center),
			byWorld[stand.worldId],
			stand.name,
			stand.price,
			heights[stand.eggId]
		)
		model.Name = "EggStand_" .. stand.eggId
		model:SetAttribute("EggId", stand.eggId)
		local trigger = triggerOf(model)
		trigger:SetAttribute("EggId", stand.eggId)
		trigger:AddTag("EggStand")
		model.Parent = folder
		table.insert(built.eggStands, { trigger = trigger, stand = stand, model = model })
	end

	for _, gym in plan.gyms do
		local folder = built.folders[gym.worldId]
		local leaderType = Config.worldById[gym.worldId].gym.leader_type
		local model = Kit.gymBuilding(
			facing(gym.position, plan.arrivals[gym.worldId]),
			byWorld[gym.worldId],
			gym.label,
			color(PetLook.typeColor(leaderType)),
			Config.typeById[leaderType].name
		)
		model.Name = WorldNames.gymModel(gym.worldId)
		model:SetAttribute("WorldId", gym.worldId)
		-- Stepping on the gym floor opens the battle screen's fee prompt.
		local floor = model.PrimaryPart :: BasePart
		floor:SetAttribute("WorldId", gym.worldId)
		floor:AddTag("GymFloor")
		model.Parent = folder
		table.insert(built.gyms, model)
	end

	for _, portal in plan.portals do
		local folder = built.folders[portal.worldId]
		local model = Kit.portalFrame(
			facing(portal.position, plan.arrivals[portal.worldId]),
			byWorld[portal.worldId],
			portal.label
		)
		model.Name = "Portal_" .. portal.worldId
		model:SetAttribute("FromIndex", portal.fromIndex)
		-- The client finds portals by this tag and shows each one open or
		-- locked from its own ProfileChanged state.
		model:SetAttribute("WorldId", portal.worldId)
		model:AddTag(PORTAL_TAG)
		if portal.toIndex ~= nil then
			model:SetAttribute("ToIndex", portal.toIndex)
		end
		local trigger = triggerOf(model)
		model.Parent = folder
		table.insert(built.portals, { trigger = trigger, portal = portal })
	end

	-- Parent the folders last, so each world appears whole.
	for worldId, folder in built.folders do
		local parts = settle(folder)
		folder:SetAttribute("PartCount", parts)
		if parts > Scenery.PART_BUDGET then
			warn(
				string.format(
					"[World] %s has %d parts, over the budget of %d",
					worldId,
					parts,
					Scenery.PART_BUDGET
				)
			)
		end
		folder.Parent = Workspace
	end

	local spawn = Workspace:FindFirstChildOfClass("SpawnLocation")
	if spawn ~= nil then
		spawn.CFrame = at(plan.spawn) * CFrame.new(0, spawn.Size.Y / 2, 0)
	else
		warn("[World] no SpawnLocation in Workspace; players spawn at the origin")
	end

	built.counts = {
		eggStands = countProps(built.folders, "EggStand"),
		gyms = countProps(built.folders, "Gym"),
		portals = countProps(built.folders, "Portal"),
	}
	if
		built.counts.eggStands ~= #plan.eggStands
		or built.counts.gyms ~= #plan.gyms
		or built.counts.portals ~= #plan.portals
	then
		error(
			string.format(
				"Builder: built %d stands, %d gyms, %d portals; the plan has %d, %d, %d",
				built.counts.eggStands,
				built.counts.gyms,
				built.counts.portals,
				#plan.eggStands,
				#plan.gyms,
				#plan.portals
			)
		)
	end
	return built
end

-- Puts each egg's real model on its stand once the asset stage has loaded it
-- into ReplicatedStorage.PetModels (named by egg id), and again whenever it is
-- reloaded. A stand whose model never loads keeps its placeholder. Call it in
-- its own thread: it waits for the PetModels folder.
function Builder.dressEggStands(built: Built, folderName: string)
	local models = ReplicatedStorage:WaitForChild(folderName)
	local byEgg: { [string]: { Model } } = {}
	for _, site in built.eggStands do
		local list = byEgg[site.stand.eggId] or {}
		table.insert(list, site.model)
		byEgg[site.stand.eggId] = list
	end
	local function use(child: Instance)
		local stands = byEgg[child.Name]
		if stands == nil or not child:IsA("Model") then
			return
		end
		for _, stand in stands do
			if stand.Parent ~= nil then
				Kit.setEgg(stand, child)
			end
		end
	end
	models.ChildAdded:Connect(use)
	for _, child in models:GetChildren() do
		use(child)
	end
end

return Builder
