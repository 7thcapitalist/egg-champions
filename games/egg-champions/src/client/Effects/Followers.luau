--!strict
--[[
	Followers: equipped pets walk or fly after their player in the world.

	The server only writes each player's team onto the Player as the
	FollowerTeam attribute (shared/visual/Followers) when the team changes.
	Everything else happens here, on each client, for every player whose
	character is within Followers.LOOK.viewDistance of the camera: the pets
	are built with PetVisual.create (the PetModels asset when there is one,
	with the shiny or golden look), kept in a local folder in the Workspace,
	scaled so their largest side is Followers.LOOK.size studs, and moved
	each frame beside the player (left and right, a little behind) with a
	gentle bob, never on the camera line straight behind.
	The server does no work per frame, and the models never replicate.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local PetVisual = require(Shared:WaitForChild("PetVisual"))
local FollowerMath = require(Shared:WaitForChild("visual"):WaitForChild("Followers"))
local PetLook = require(Shared:WaitForChild("visual"):WaitForChild("PetLook"))
local TrainingSites = require(Shared:WaitForChild("world"):WaitForChild("TrainingSites"))
local PetMotion = require(Shared:WaitForChild("visual"):WaitForChild("PetMotion"))

local FOLDER_NAME = "PetFollowers"

type Entry = {
	key: string,
	models: { Model },
	floors: { number },
	clearance: { number },
	motion: { number },
	positions: { Vector3 },
	phases: { number },
	facing: { CFrame },
}

local Followers = {}

local entries: { [Player]: Entry } = {}
local folder: Folder? = nil

local function clear(player: Player)
	local entry = entries[player]
	if entry == nil then
		return
	end
	for _, model in entry.models do
		model:Destroy()
	end
	entries[player] = nil
end

local function build(player: Player, key: string): Entry
	local models = {}
	local clearance = {}
	for _, member in FollowerMath.decode(key) do
		local ok, model = pcall(PetVisual.create, member.petId, member.variant)
		if ok and model ~= nil then
			local extents = model:GetExtentsSize()
			local largest = math.max(extents.X, extents.Y, extents.Z)
			local factor = FollowerMath.scaleFor(largest)
			if factor ~= 1 then
				pcall(function()
					model:ScaleTo(model:GetScale() * factor)
				end)
			end
			model.Name = string.format("%s_%s", player.Name, model.Name)
			model.Parent = folder
			table.insert(models, model)
			local box, size = model:GetBoundingBox()
			table.insert(clearance, model:GetPivot().Position.Y - box.Position.Y + size.Y / 2)
		end
	end
	local entry = {
		key = key,
		models = models,
		floors = {},
		clearance = clearance,
		motion = {},
		positions = {},
		phases = {},
		facing = {},
	}
	entries[player] = entry
	return entry
end

local function rootOf(player: Player): BasePart?
	local character = player.Character
	if character == nil then
		return nil
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	if root ~= nil and root:IsA("BasePart") then
		return root
	end
	return nil
end

local function step(dt: number)
	local camera = Workspace.CurrentCamera
	if camera == nil then
		return
	end
	local eye = camera.CFrame.Position
	local seconds = os.clock()
	local blend = FollowerMath.blend(dt)
	local range = FollowerMath.LOOK.viewDistance

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local excluded: { Instance } = { folder :: Folder }
	for _, other in Players:GetPlayers() do
		if other.Character ~= nil then
			table.insert(excluded, other.Character :: Model)
		end
	end
	params.FilterDescendantsInstances = excluded

	for _, player in Players:GetPlayers() do
		local root = rootOf(player)
		local key = player:GetAttribute(FollowerMath.ATTRIBUTE)
		local wanted = if type(key) == "string" then key else ""
		if root == nil or wanted == "" or (root.Position - eye).Magnitude > range then
			clear(player)
			continue
		end
		local entry = entries[player]
		local fresh = false
		if entry == nil or entry.key ~= wanted then
			clear(player)
			entry = build(player, wanted)
			fresh = true
		end
		local current = entry :: Entry
		local count = #current.models
		local base = root.CFrame
		local trainingTarget = player:GetAttribute(TrainingSites.TARGET_ATTRIBUTE)
		local trainingStart = player:GetAttribute(TrainingSites.START_ATTRIBUTE)
		local training = typeof(trainingTarget) == "Vector3" and type(trainingStart) == "number"
		for index, model in current.models do
			local phase = seconds + index * 0.71
			local o = FollowerMath.offset(index, count, seconds)
			local spot = base * CFrame.new(o.x, o.y, o.z)
			local effort = 0
			if training then
				local angle = (index - (count + 1) / 2) * 0.65
				effort = math.max(
					0,
					math.sin((Workspace:GetServerTimeNow() - trainingStart) * 7 + index * 1.4)
				)
				local radius = 5.5 - effort * 1.4
				spot = CFrame.new(
					trainingTarget
						+ Vector3.new(math.sin(angle) * radius, 1, math.cos(angle) * radius)
				)
			end
			local hit = Workspace:Raycast(
				spot.Position + Vector3.new(0, 12, 0),
				Vector3.new(0, -40, 0),
				params
			)
			local ground = if hit ~= nil then hit.Position.Y else root.Position.Y - 3
			local floor = current.floors[index]
			floor = if floor == nil then ground else floor + (ground - floor) * blend
			current.floors[index] = floor
			local flying = model:GetAttribute("Flying") == true
			local previous = current.positions[index] or spot.Position
			local destination = Vector3.new(spot.Position.X, 0, spot.Position.Z)
			local previousFlat = Vector3.new(previous.X, 0, previous.Z)
			local teleport = (destination - previousFlat).Magnitude > 80
			local position = if fresh or teleport
				then destination
				else previousFlat:Lerp(destination, blend)
			local delta = position - previousFlat
			local distance = if fresh or teleport then 0 else delta.Magnitude
			current.positions[index] = position
			local speed = if dt > 0 then distance / dt else 0
			local gait = (current.motion[index] or 0)
				+ (math.clamp(speed / 12, 0, 1) - (current.motion[index] or 0)) * blend
			current.motion[index] = gait
			local stride = FollowerMath.stride(current.phases[index] or index * 0.9, distance)
			current.phases[index] = stride
			local face = current.facing[index] or base.Rotation
			if distance > 0.004 then
				face = face:Lerp(CFrame.lookAt(Vector3.zero, delta), 1 - math.exp(-8 * dt))
			elseif fresh or teleport then
				face = base.Rotation
			end
			if training then
				local aim = Vector3.new(trainingTarget.X, 0, trainingTarget.Z) - position
				if aim.Magnitude > 0.01 then
					face = CFrame.lookAt(Vector3.zero, aim)
				end
			end
			current.facing[index] = face
			local lift = if training
				then effort * 0.65
				elseif flying then 1 + math.sin(phase * 2.6) * 0.18
				else (1 - math.cos(stride * 2)) * gait * 0.045
			local target = CFrame.new(
				position.X,
				floor + current.clearance[index] + lift,
				position.Z
			) * face * CFrame.Angles(
				if flying then -gait * 0.08 else math.sin(stride * 2) * gait * 0.018,
				math.sin(phase * 0.9) * 0.035 * (1 - gait),
				if flying then math.sin(phase * 2.6) * 0.035 else math.sin(stride) * gait * 0.025
			)
			model:PivotTo(target)
			PetMotion.pose(model, phase, gait, stride, effort)
		end
	end
end

function Followers.mount()
	local made = Instance.new("Folder")
	made.Name = FOLDER_NAME
	made.Parent = Workspace
	folder = made
	-- An equipped team can arrive before its templates. Invalidate only
	-- teams waiting for this asset; the next frame rebuilds their followers.
	local function watchTemplates(templates: Instance)
		if templates.Name ~= "PetModels" or not templates:IsA("Folder") then
			return
		end
		local function ready(descendant: Instance)
			local source = descendant
			while source.Parent ~= nil and source.Parent ~= templates do
				source = source.Parent
			end
			if source.Parent ~= templates or not source:IsA("Model") then
				return
			end
			if source:FindFirstChildWhichIsA("BasePart", true) == nil then
				return
			end
			PetLook.MODEL_IDS[source.Name] = source.Name
			for player, entry in entries do
				for _, model in entry.models do
					if
						model:GetAttribute("PetId") == source.Name
						and model:GetAttribute("UsesAsset") ~= true
						and model:GetAttribute("Procedural") ~= true
					then
						clear(player)
						break
					end
				end
			end
		end
		templates.DescendantAdded:Connect(ready)
		for _, source in templates:GetChildren() do
			ready(source)
		end
	end
	ReplicatedStorage.ChildAdded:Connect(watchTemplates)
	local templates = ReplicatedStorage:FindFirstChild("PetModels")
	if templates ~= nil then
		watchTemplates(templates)
	end
	Players.PlayerRemoving:Connect(clear)
	RunService.RenderStepped:Connect(step)
end

return Followers
