--!strict
--[[
	Builder: generates every world from the world table. Nothing is placed by hand.

	Builder.buildAll reads the plan from shared/world/Layout (which reads
	Config.worlds) and builds, for each world, one island: ground, cliffs,
	water, scenery, lights, a name sign, one egg stand per egg, one gym building
	and one portal. Each world's instances go under one folder in Workspace,
	"World_<id>", tagged with the Generated attribute, so a rebuild clears and
	regenerates those folders and touches nothing else.

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
local Layout = require(Shared:WaitForChild("world"):WaitForChild("Layout"))
local WorldPalette = require(Shared:WaitForChild("world"):WaitForChild("WorldPalette"))
local WorldNames = require(Shared:WaitForChild("world"):WaitForChild("Names"))
local Kit = require(script.Parent:WaitForChild("Kit"))

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
local WATER_SIZE = Layout.ISLAND_SIZE + 140
local SCENERY_RADIUS = 68
local SCENERY_SLOTS = 12
-- Open ground kept between a scenery prop and the gym's corners, in studs.
local GYM_SCENERY_GAP = 6
local LIGHT_RADIUS = 52
local SIGN_OFFSET: Vec = { x = -22, y = 0, z = 14 }

local function color(c: WorldPalette.RGB): Color3
	return Color3.fromRGB(c.r, c.g, c.b)
end

-- Turns a shared WorldPalette row into the Color3 and Enum form Kit takes.
local converted: { [WorldPalette.Palette]: Palette } = {}
local function paletteFor(worldId: string, environment: string): Palette
	local row = WorldPalette.forWorld(worldId, environment)
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
	}
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

-- Removes every folder a previous build made, and nothing else.
function Builder.clear()
	for _, child in Workspace:GetChildren() do
		if child:IsA("Folder") and child:GetAttribute(GENERATED_ATTRIBUTE) == true then
			child:Destroy()
		end
	end
end

-- True when a scenery prop at (x, z) would stand on or crowd the gym.
local function nearGym(gym: Layout.GymSite?, x: number, z: number): boolean
	if gym == nil then
		return false
	end
	local half = Layout.GYM_SIZE
	local reach = math.sqrt((half.width / 2) ^ 2 + (half.depth / 2) ^ 2) + GYM_SCENERY_GAP
	return (x - gym.position.x) ^ 2 + (z - gym.position.z) ^ 2 < reach * reach
end

local function buildScenery(
	folder: Folder,
	island: Layout.Island,
	palette: Palette,
	gym: Layout.GymSite?
)
	local scenery = Instance.new("Folder")
	scenery.Name = "Scenery"
	scenery.Parent = folder
	local rng = Random.new(island.worldIndex)
	local o = island.origin
	for slot = 1, SCENERY_SLOTS do
		-- Slot 1 points along +x, where the portal stands; leave it clear.
		-- Slots that would crowd the gym are left clear too. The random numbers
		-- are drawn either way, so the other props keep their places.
		local angle = (slot - 1) / SCENERY_SLOTS * math.pi * 2
		local radius = SCENERY_RADIUS - rng:NextNumber(0, 6)
		local x = o.x + math.cos(angle) * radius
		local z = o.z + math.sin(angle) * radius
		local turn = rng:NextNumber(0, math.pi * 2)
		local scale = rng:NextNumber(0.9, 1.3)
		if slot ~= 1 and not nearGym(gym, x, z) then
			local base = CFrame.new(x, o.y, z) * CFrame.Angles(0, turn, 0)
			local kind = slot % 3
			local prop = if kind == 0
				then Kit.rock(base, palette, scale)
				elseif kind == 1 then Kit.filler(base, palette, scale)
				else Kit.tree(base, palette, scale)
			prop.Parent = scenery
		end
	end
	for corner = 0, 3 do
		local angle = math.pi / 4 + corner * math.pi / 2
		local light = Kit.light(
			CFrame.new(
				o.x + math.cos(angle) * LIGHT_RADIUS,
				o.y,
				o.z + math.sin(angle) * LIGHT_RADIUS
			),
			palette
		)
		light.Parent = scenery
	end
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
	Builder.clear()

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

		local base = at(island.origin)
		Kit.ground(island.size, base, palette).Parent = folder
		Kit.cliff(island.size, base, palette).Parent = folder
		Kit.water(WATER_SIZE, base, palette).Parent = folder
		local o = island.origin
		local signSpot = { x = o.x + SIGN_OFFSET.x, y = o.y, z = o.z + SIGN_OFFSET.z }
		Kit.sign(facing(signSpot, o), palette, island.name).Parent = folder
		if island.worldIndex ~= plan.islands[1].worldIndex then
			Kit.arrivalPad(at(plan.arrivals[island.worldId]), palette).Parent = folder
		end
		local gymSite: Layout.GymSite? = nil
		for _, gym in plan.gyms do
			if gym.worldId == island.worldId then
				gymSite = gym
			end
		end
		buildScenery(folder, island, palette, gymSite)
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
		local model = Kit.gymBuilding(
			facing(gym.position, plan.arrivals[gym.worldId]),
			byWorld[gym.worldId],
			gym.label
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
	for _, folder in built.folders do
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
