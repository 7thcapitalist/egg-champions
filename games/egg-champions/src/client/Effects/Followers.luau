--!strict
--[[
	Followers: every player's equipped pets hover after them in the world.

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

local FOLDER_NAME = "PetFollowers"

type Entry = {
	key: string,
	models: { Model },
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
		end
	end
	local entry = { key = key, models = models }
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
		for index, model in current.models do
			local o = FollowerMath.offset(index, count, seconds)
			local spot = base * CFrame.new(o.x, o.y, o.z)
			local target = CFrame.new(spot.Position) * base.Rotation
			if fresh then
				model:PivotTo(target)
			else
				model:PivotTo(model:GetPivot():Lerp(target, blend))
			end
		end
	end
end

function Followers.mount()
	local made = Instance.new("Folder")
	made.Name = FOLDER_NAME
	made.Parent = Workspace
	folder = made
	Players.PlayerRemoving:Connect(clear)
	RunService.RenderStepped:Connect(step)
end

return Followers
