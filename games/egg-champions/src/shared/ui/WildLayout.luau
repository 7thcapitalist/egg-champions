--!strict
local WildLayout = {}
-- Optional monetization never displaces an objective or a control.
function WildLayout.offer(width: number, height: number, blockers: { any }): any?
	local w, h = 154, 44
	for _, y in { 64, 128, math.floor((height - h) / 2) } do
		local candidate = { x = (width - w) / 2, y = y, width = w, height = h }
		local clear = candidate.x >= 8 and y >= 56 and y + h <= height - 120
		for _, b in blockers do
			if
				candidate.x < b.x + b.width
				and b.x < candidate.x + w
				and y < b.y + b.height
				and b.y < y + h
			then
				clear = false
			end
		end
		if clear then
			return candidate
		end
	end
	return nil
end
function WildLayout.card(width: number, height: number): any
	local short = height < 320
	local w = math.min(340, width - 24)
	local h = if short then 176 else 214
	return {
		width = w,
		height = h,
		x = (width - w) / 2,
		y = if short then 44 else math.min(80, math.max(44, (height - h) / 3)),
		portraitHeight = if short then 58 else 96,
	}
end
return WildLayout
