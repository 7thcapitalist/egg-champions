--!strict
--[[
	EdgeArrow: where the screen-edge arrow toward an off-screen thing goes,
	as pure math so the specs can check it.

	place takes the viewport size, the thing's projected screen point and its
	depth (the Z of Camera:WorldToViewportPoint, below zero when it is behind
	the camera), and a margin in pixels. When the point is on screen inside
	the margin, the arrow is hidden. Otherwise it sits on the edge rectangle
	inset by the margin, on the line from the screen centre toward the point,
	and its angle (degrees, 0 = pointing right, 90 = pointing down, as a
	GuiObject's Rotation turns) points that way. A point behind the camera
	is mirrored through the centre first, since the projection flips it.
]]

export type Point = { x: number, y: number }

export type Placement = {
	visible: boolean,
	x: number,
	y: number,
	angle: number,
}

local EdgeArrow = {}

function EdgeArrow.place(viewport: Point, point: Point, depth: number, margin: number): Placement
	local cx = viewport.x / 2
	local cy = viewport.y / 2
	local inside = point.x >= margin
		and point.x <= viewport.x - margin
		and point.y >= margin
		and point.y <= viewport.y - margin
	if depth > 0 and inside then
		return { visible = false, x = point.x, y = point.y, angle = 0 }
	end

	local dx = point.x - cx
	local dy = point.y - cy
	if depth <= 0 then
		dx = -dx
		dy = -dy
	end
	if math.abs(dx) < 1e-6 and math.abs(dy) < 1e-6 then
		-- Straight behind: point down, toward the player.
		dy = 1
	end

	local halfX = math.max(cx - margin, 0)
	local halfY = math.max(cy - margin, 0)
	local scale = math.huge
	if math.abs(dx) > 1e-6 then
		scale = math.min(scale, halfX / math.abs(dx))
	end
	if math.abs(dy) > 1e-6 then
		scale = math.min(scale, halfY / math.abs(dy))
	end
	return {
		visible = true,
		x = cx + dx * scale,
		y = cy + dy * scale,
		angle = math.deg(math.atan2(dy, dx)),
	}
end

return EdgeArrow
