--!strict
-- One local, noncolliding visitor per player. Rewards and encounter identity stay server-owned.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local PetVisual = require(Shared.PetVisual)
local PetMotion = require(Shared.visual.PetMotion)
local Motion = require(Shared.visual.BattleMotion)
local State = require(script.Parent.Parent.UI.State)
local Theme = require(script.Parent.Parent.UI.Theme)
local Visitor = {}
local model: Model? = nil
local base = CFrame.new()
local active: any = nil
local reactionAt, reactionKind = 0, "hit"
local expires = 0
function Visitor.react(kind: string)
	reactionAt, reactionKind = os.clock(), kind
end
local function clear()
	if model then
		model:Destroy()
	end
	model, active = nil, nil
end
function Visitor.mount()
	State.subscribe(function(payload)
		local e = payload.derived.wild and payload.derived.wild.encounter
		if
			not e
			or e.phase == "captured"
			or e.phase == "escaped"
			or workspace:GetServerTimeNow() >= e.expiresAt
		then
			clear()
			return
		end
		if active == e.id then
			return
		end
		clear()
		local position = Players.LocalPlayer:GetAttribute("TrainingTarget")
		if typeof(position) ~= "Vector3" then
			return
		end
		local fresh = PetVisual.create(e.petId, nil)
		local size = fresh:GetExtentsSize()
		fresh:ScaleTo(fresh:GetScale() * math.min(1, 4 / math.max(size.X, size.Y, size.Z)))
		local box, extent = fresh:GetBoundingBox()
		local floorOffset = extent.Y / 2 - (box.Position.Y - fresh:GetPivot().Position.Y)
		base = CFrame.new(position + Vector3.new(7, floorOffset + 0.2, 4))
			* CFrame.Angles(0, -math.pi / 2, 0)
		for _, part in fresh:GetDescendants() do
			if part:IsA("BasePart") then
				part.Anchored, part.CanCollide, part.CanTouch, part.CanQuery =
					true, false, false, false
			end
		end
		fresh.Name = "LocalWildVisitor"
		fresh:PivotTo(base)
		fresh.Parent = workspace
		model, active, expires = fresh, e.id, e.expiresAt
		local label = Instance.new("BillboardGui")
		label.Name, label.Size, label.StudsOffset =
			"WildName", UDim2.fromOffset(160, 32), Vector3.new(0, extent.Y + 0.8, 0)
		label.Adornee = fresh:FindFirstChildWhichIsA("BasePart", true)
		label.AlwaysOnTop, label.MaxDistance, label.Parent = false, 45, fresh
		local text = Theme.text({
			name = "Wild",
			text = "WILD " .. Config.petById[e.petId].name,
			color = Theme.colors.gold,
			parent = label,
			size = 14,
		})
		text.AutomaticSize, text.Size = Enum.AutomaticSize.None, UDim2.fromScale(1, 1)
	end)
	Players.LocalPlayer:GetAttributeChangedSignal("TrainingWorld"):Connect(function()
		if Players.LocalPlayer:GetAttribute("TrainingWorld") == nil then
			clear()
		end
	end)
	local elapsed = 0
	RunService.RenderStepped:Connect(function(dt)
		if not model then
			return
		end
		if workspace:GetServerTimeNow() >= expires then
			clear()
			return
		end
		elapsed += dt
		if elapsed < 1 / 30 then
			return
		end
		elapsed = 0
		local pose = Motion.sample(
			model:GetAttribute("PetId") or "",
			reactionKind,
			(os.clock() - reactionAt) / 0.4
		)
		local height = model:GetExtentsSize().Y
		model:PivotTo(
			base
				* CFrame.new(pose.x * height, pose.y * height, pose.z * height)
				* CFrame.Angles(pose.pitch, pose.yaw, pose.roll)
		)
		PetMotion.pose(model, os.clock(), 0, nil, pose.effort)
	end)
end
return Visitor
