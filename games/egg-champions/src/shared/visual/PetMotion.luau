--!strict
-- Limb poses are local to the model pivot and survive scaling and PivotTo.
local PetMotion = {}
type Joint = { part: BasePart, rest: CFrame, pivot: CFrame, role: string }
local cache: { [Model]: { Joint } } = setmetatable({}, { __mode = "k" }) :: any

function PetMotion.pose(
	model: Model,
	seconds: number,
	moving: number,
	travelPhase: number?,
	battleEffort: number?
)
	local joints = cache[model]
	if joints == nil then
		joints = {}
		local base = model:GetPivot()
		for _, item in model:GetDescendants() do
			local role = item:GetAttribute("MotionRole")
			if item:IsA("BasePart") and type(role) == "string" then
				local point = item:GetAttribute("MotionPivot")
				local pivot = if typeof(point) == "Vector3"
					then CFrame.new(point * model:GetScale())
					else base:ToObjectSpace(item.CFrame)
				table.insert(joints, {
					part = item,
					rest = pivot:ToObjectSpace(base:ToObjectSpace(item.CFrame)),
					pivot = pivot,
					role = role,
				})
			end
		end
		cache[model] = joints
	end
	local base = model:GetPivot()
	local stride = math.sin(travelPhase or seconds * 11) * math.clamp(moving, 0, 1) * 0.38
	local effort = math.clamp(battleEffort or 0, -1, 1)
	for _, joint in joints do
		local role = joint.role
		local turn = CFrame.identity
		if role == "legA" or role == "legB" then
			turn = CFrame.Angles((if role == "legA" then stride else -stride) - effort * 0.22, 0, 0)
		elseif role == "tail" then
			turn = CFrame.Angles(
				0,
				math.sin(seconds * (2 + moving * 1.5)) * (0.08 + moving * 0.12) + effort * 0.25,
				0
			)
		elseif role == "wings" then
			turn = CFrame.Angles(math.sin(seconds * 7) * 0.12 + effort * 0.3, 0, 0)
		elseif role == "bounce" then
			turn = CFrame.Angles(stride * 0.2, 0, 0)
		elseif role == "feelers" then
			turn = CFrame.Angles(0, math.sin(seconds * 2) * 0.04, 0)
		elseif role == "wingL" or role == "wingR" then
			turn = CFrame.Angles(
				0,
				0,
				(math.sin(seconds * (4.5 + moving * 2)) * (0.22 + moving * 0.16) + effort * 0.35)
					* (if role == "wingL" then -1 else 1)
			)
		end
		joint.part.CFrame = base * joint.pivot * turn * joint.rest
	end
end

return PetMotion
