--!strict
-- Currency is awarded only by a server clock and server-observed location.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Training = require(Shared.rules.Training)
local TrainingSites = require(Shared.world.TrainingSites)
local PassEffects = require(Shared.rules.PassEffects)
local server = script.Parent.Parent
local Profiles = require(server.Profiles)
local Passes = require(server.Passes)
local ClickService = require(script.Parent.ClickService)
local GymService = require(script.Parent.GymService)

local WildService = require(script.Parent.WildService)
local TrainingService = {}
local clocks: { [Player]: Training.Clock } = {}
local started = false

local function siteFor(player: Player, profile: any): (string?, Vector3?)
	local character = player.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
	if root == nil or not root:IsA("BasePart") or humanoid == nil or humanoid.Health <= 0 then
		return nil, nil
	end
	if GymService.isBattling(player) then
		return nil, nil
	end
	local point = { x = root.Position.X, y = root.Position.Y, z = root.Position.Z }
	for _, site in CollectionService:GetTagged(TrainingSites.TAG) do
		if not site:IsDescendantOf(Workspace) then
			continue
		end
		local position = site:GetAttribute("TrainingPosition")
		local worldId, index = site:GetAttribute("WorldId"), site:GetAttribute("WorldIndex")
		if
			typeof(position) == "Vector3"
			and type(worldId) == "string"
			and type(index) == "number"
			and Training.allowed(profile, index, true, false)
			and Training.inRange(point, { x = position.X, y = position.Y, z = position.Z })
		then
			return worldId, position
		end
	end
	return nil, nil
end

-- Exposed for deterministic server tests; clients have no remote for this.
function TrainingService.step(player: Player, now: number)
	local profile = Profiles.get(player)
	local worldId: string? = nil
	local position: Vector3? = nil
	if profile ~= nil and player.Parent ~= nil then
		worldId, position = siteFor(player, profile)
	end
	WildService.observe(player, worldId, now)
	local clock = clocks[player]
	if clock == nil then
		clock = {}
		clocks[player] = clock
	end
	local previous = clock.target
	local reward = Training.step(clock, worldId, now)
	if previous ~= worldId then
		player:SetAttribute(TrainingSites.WORLD_ATTRIBUTE, worldId)
		player:SetAttribute(TrainingSites.TARGET_ATTRIBUTE, position)
		player:SetAttribute(TrainingSites.START_ATTRIBUTE, if worldId then now else nil)
	end
	if reward and profile ~= nil and position ~= nil then
		ClickService.train(
			player,
			profile,
			Training.hits(PassEffects.autoClick(Passes.owned(player)))
				* WildService.multiplier(player, now),
			position
		)
		player:SetAttribute(TrainingSites.PULSE_ATTRIBUTE, now)
	end
end

function TrainingService.start()
	if started then
		return
	end
	started = true
	WildService.start(function(player, profile)
		local worldId = siteFor(player, profile)
		return worldId
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		clocks[player] = nil
	end)
	task.spawn(function()
		while true do
			local now = Workspace:GetServerTimeNow()
			for _, player in Players:GetPlayers() do
				TrainingService.step(player, now)
			end
			task.wait(0.05)
		end
	end)
end

return TrainingService
