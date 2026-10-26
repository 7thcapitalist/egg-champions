--!strict
-- Local joint and target motion only. Player movement and camera stay native.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Sites = require(Shared:WaitForChild("world"):WaitForChild("TrainingSites"))
local Training = {}
type Joint = Motor6D | AnimationConstraint
type Layer = { base: CFrame, applied: CFrame }
local joints: { [Joint]: Layer } = {}
local targets: { [Model]: CFrame } = {}

function Training.mount()
	RunService.PreSimulation:Connect(function()
		local now = workspace:GetServerTimeNow()
		local active: { [Joint]: boolean } = {}
		local pulses: { [string]: number } = {}
		for _, player in Players:GetPlayers() do
			local started = player:GetAttribute(Sites.START_ATTRIBUTE)
			local world = player:GetAttribute(Sites.WORLD_ATTRIBUTE)
			local character = player.Character
			if character == nil or type(started) ~= "number" or type(world) ~= "string" then
				continue
			end
			local humanoid = character:FindFirstChildOfClass("Humanoid")
			if humanoid == nil or humanoid.Health <= 0 then
				continue
			end
			local pulse = player:GetAttribute(Sites.PULSE_ATTRIBUTE)
			if type(pulse) == "number" then
				pulses[world] = math.max(pulses[world] or 0, pulse)
			end
			for _, joint in character:GetDescendants() do
				if not joint:IsA("Motor6D") and not joint:IsA("AnimationConstraint") then
					continue
				end
				local right = joint.Name == "RightShoulder" or joint.Name == "Right Shoulder"
				local left = joint.Name == "LeftShoulder" or joint.Name == "Left Shoulder"
				if not right and not left then
					continue
				end
				local layered = joints[joint]
				local base = joint.Transform
				if layered ~= nil and base == layered.applied then
					base = layered.base
				end
				active[joint] = true
				local swing =
					math.max(0, math.sin((now - started) * 7 + (if left then math.pi else 0)))
				joint.Transform = base
					* CFrame.Angles(swing * -1.25, 0, swing * (if left then -0.15 else 0.15))
				joints[joint] = { base = base, applied = joint.Transform }
			end
		end
		for joint, layer in joints do
			if not active[joint] then
				if joint.Parent ~= nil and joint.Transform == layer.applied then
					joint.Transform = layer.base
				end
				joints[joint] = nil
			end
		end
		for _, site in CollectionService:GetTagged(Sites.TAG) do
			local dummy = site:FindFirstChild("TrainingDummy")
			if dummy == nil or not dummy:IsA("Model") then
				continue
			end
			local base = targets[dummy] or dummy:GetPivot()
			targets[dummy] = base
			local pulse = pulses[site:GetAttribute("WorldId")]
			local elapsed = if pulse then now - pulse else 1
			local recoil = if elapsed >= 0 and elapsed < 0.35
				then math.sin(elapsed / 0.35 * math.pi)
				else 0
			dummy:PivotTo(base * CFrame.Angles(-recoil * 0.1, 0, recoil * 0.035))
		end
		for dummy in targets do
			if dummy.Parent == nil then
				targets[dummy] = nil
			end
		end
	end)
end

return Training
