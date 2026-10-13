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

	Palettes live in PALETTES below, keyed by world id. A world with no entry
	gets a palette picked from keywords in its environment string, so a new
	world in the spec still builds with no code change.

	Returns what it built, counted from the instances themselves, and errors if
	that differs from the plan.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Layout = require(Shared:WaitForChild("world"):WaitForChild("Layout"))
local Kit = require(script.Parent:WaitForChild("Kit"))

type Palette = Kit.Palette
type Vec = Layout.Vec

export type PortalSite = {
	trigger: BasePart,
	portal: Layout.Portal,
}

export type StandSite = {
	trigger: BasePart,
	stand: Layout.EggStand,
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
local WATER_SIZE = Layout.ISLAND_SIZE + 140
local SCENERY_RADIUS = 68
local SCENERY_SLOTS = 12
local LIGHT_RADIUS = 52
local SIGN_OFFSET: Vec = { x = -22, y = 0, z = 14 }

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local PALETTES: { [string]: Palette } = {
	green_meadow = {
		ground = rgb(106, 170, 78),
		groundMaterial = Enum.Material.Grass,
		cliff = rgb(122, 96, 70),
		water = rgb(80, 150, 210),
		trunk = rgb(110, 76, 48),
		leaf = rgb(62, 140, 64),
		rock = rgb(140, 140, 132),
		accent = rgb(250, 214, 92),
		trim = rgb(236, 230, 214),
		glow = rgb(255, 240, 170),
		text = rgb(255, 255, 255),
	},
	coral_coast = {
		ground = rgb(236, 214, 158),
		groundMaterial = Enum.Material.Sand,
		cliff = rgb(196, 160, 118),
		water = rgb(40, 170, 200),
		trunk = rgb(150, 112, 70),
		leaf = rgb(70, 170, 120),
		rock = rgb(232, 128, 120),
		accent = rgb(90, 120, 200),
		trim = rgb(248, 244, 232),
		glow = rgb(150, 220, 255),
		text = rgb(255, 255, 255),
	},
	ember_volcano = {
		ground = rgb(70, 62, 62),
		groundMaterial = Enum.Material.Basalt,
		cliff = rgb(48, 42, 42),
		water = rgb(240, 100, 30),
		trunk = rgb(60, 50, 46),
		leaf = rgb(110, 90, 80),
		rock = rgb(90, 80, 78),
		accent = rgb(230, 90, 40),
		trim = rgb(150, 140, 136),
		glow = rgb(255, 150, 60),
		text = rgb(255, 255, 255),
	},
}

-- For a world with no palette entry: keywords in its environment string pick
-- one of the palettes above.
local KEYWORD_PALETTES: { { words: { string }, palette: string } } = {
	{ words = { "lava", "volcano", "ash", "ember", "fire" }, palette = "ember_volcano" },
	{ words = { "beach", "reef", "sea", "ocean", "coast", "storm" }, palette = "coral_coast" },
	{ words = { "grass", "forest", "meadow", "field" }, palette = "green_meadow" },
}
local DEFAULT_PALETTE = "green_meadow"

local function paletteFor(worldId: string, environment: string): Palette
	local own = PALETTES[worldId]
	if own ~= nil then
		return own
	end
	local text = string.lower(environment)
	for _, entry in KEYWORD_PALETTES do
		for _, word in entry.words do
			if string.find(text, word, 1, true) ~= nil then
				return PALETTES[entry.palette]
			end
		end
	end
	return PALETTES[DEFAULT_PALETTE]
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

local function buildScenery(folder: Folder, island: Layout.Island, palette: Palette)
	local scenery = Instance.new("Folder")
	scenery.Name = "Scenery"
	scenery.Parent = folder
	local rng = Random.new(island.worldIndex)
	local o = island.origin
	for slot = 1, SCENERY_SLOTS do
		-- Slot 1 points along +x, where the portal stands; leave it clear.
		if slot ~= 1 then
			local angle = (slot - 1) / SCENERY_SLOTS * math.pi * 2
			local radius = SCENERY_RADIUS - rng:NextNumber(0, 6)
			local base = CFrame.new(
				o.x + math.cos(angle) * radius,
				o.y,
				o.z + math.sin(angle) * radius
			) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0)
			local scale = rng:NextNumber(0.9, 1.3)
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

	local palettes: { [string]: Palette } = {}
	for _, island in plan.islands do
		local palette = paletteFor(island.worldId, island.environment)
		palettes[island.worldId] = palette

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
		buildScenery(folder, island, palette)
	end

	for _, stand in plan.eggStands do
		local folder = built.folders[stand.worldId]
		local center = plan.arrivals[stand.worldId]
		-- Stands face the island center, so the Trigger pad is on the near side.
		local model =
			Kit.eggStand(facing(stand.position, center), palettes[stand.worldId], stand.label)
		model.Name = "EggStand_" .. stand.eggId
		model:SetAttribute("EggId", stand.eggId)
		local trigger = triggerOf(model)
		trigger:SetAttribute("EggId", stand.eggId)
		trigger:AddTag("EggStand")
		model.Parent = folder
		table.insert(built.eggStands, { trigger = trigger, stand = stand })
	end

	for _, gym in plan.gyms do
		local folder = built.folders[gym.worldId]
		local model = Kit.gymBuilding(
			facing(gym.position, plan.arrivals[gym.worldId]),
			palettes[gym.worldId],
			gym.label
		)
		model.Name = "Gym_" .. gym.worldId
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
			palettes[portal.worldId],
			portal.label
		)
		model.Name = "Portal_" .. portal.worldId
		model:SetAttribute("FromIndex", portal.fromIndex)
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

return Builder
