--!strict
--[[
	Pure camera math for pet ViewportFrames. Roblox models face local -Z, so
	the camera sits on that side with a small three-quarter offset. Fit uses
	the whole bounding box and the actual frame aspect ratio.
]]

local PetPortrait = {}

PetPortrait.FOV = 32
PetPortrait.MARGIN = 1.12

-- Unit vector from the model toward the camera. Negative Z is the face.
local rawX, rawY, rawZ = 0.28, 0.16, -1
local length = math.sqrt(rawX * rawX + rawY * rawY + rawZ * rawZ)
local dx, dy, dz = rawX / length, rawY / length, rawZ / length
local horizontal = math.sqrt(dx * dx + dz * dz)
local rx, rz = dz / horizontal, -dx / horizontal
local ux, uy, uz = dy * rz, horizontal, -dy * rx

function PetPortrait.direction(): (number, number, number)
	return dx, dy, dz
end

-- The box is centered at the origin and aligned to world axes. Extents are
-- full sizes. Returns 0 for invalid input so callers can use a safe fallback.
function PetPortrait.distance(x: number, y: number, z: number, aspect: number): number
	local function usable(value: number): boolean
		return value == value and value > 0 and value < math.huge
	end
	if not usable(x) or not usable(y) or not usable(z) or not usable(aspect) then
		return 0
	end
	local hx, hy, hz = x / 2, y / 2, z / 2
	local halfVertical = math.rad(PetPortrait.FOV / 2)
	local verticalTan = math.tan(halfVertical)
	local horizontalTan = verticalTan * aspect
	local depth = math.abs(dx) * hx + math.abs(dy) * hy + math.abs(dz) * hz
	local width = math.abs(rx) * hx + math.abs(rz) * hz
	local height = math.abs(ux) * hx + math.abs(uy) * hy + math.abs(uz) * hz
	return (depth + math.max(width / horizontalTan, height / verticalTan)) * PetPortrait.MARGIN
end

return PetPortrait
