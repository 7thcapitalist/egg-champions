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

	beside places the tutorial's bouncing arrow next to an on-screen button
	(a rect in screen pixels): on the side with more room, level with the
	button's middle, pointing at it. bounce pushes it that many pixels
	further away, so animating bounce makes it bounce toward the button.
	The arrow is kept inside the viewport.
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

export type Rect = { x: number, y: number, w: number, h: number }

-- Moves an edge arrow (a square of side size, centred on the placement) off
-- any HUD rect it would cover, such as the menu: just above the rect, or
-- just below when there is no room above. The angle stays the same.
function EdgeArrow.avoid(
	placed: Placement,
	size: number,
	rects: { Rect },
	viewport: Point,
	gap: number
): Placement
	if not placed.visible then
		return placed
	end
	local half = size / 2
	local y = placed.y
	for _, r in rects do
		local overlaps = placed.x + half > r.x
			and placed.x - half < r.x + r.w
			and y + half > r.y
			and y - half < r.y + r.h
		if overlaps then
			local above = r.y - gap - half
			if above - half >= 0 then
				y = above
			else
				y = math.min(r.y + r.h + gap + half, viewport.y - half)
			end
		end
	end
	return { visible = true, x = placed.x, y = y, angle = placed.angle }
end

function EdgeArrow.beside(
	viewport: Point,
	rect: Rect,
	size: number,
	gap: number,
	bounce: number
): Placement
	local half = size / 2
	local middle = rect.x + rect.w / 2
	local onRight = middle <= viewport.x / 2
	local push = gap + half + math.max(bounce, 0)
	local x = if onRight then rect.x + rect.w + push else rect.x - push
	local y = rect.y + rect.h / 2
	x = math.clamp(x, half, math.max(viewport.x - half, half))
	y = math.clamp(y, half, math.max(viewport.y - half, half))
	return {
		visible = true,
		x = x,
		y = y,
		-- On the right it points left (180), on the left it points right (0).
		angle = if onRight then 180 else 0,
	}
end

return EdgeArrow
