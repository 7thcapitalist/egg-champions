--!strict
-- Presentation only: normalized poses with anticipation, strike and recovery.
-- Distances are shares of model height. No battle timing or damage lives here.
local BattleMotion = {}
BattleMotion.families = table.freeze({
	leafpup = "pounce",
	puddlet = "hop",
	emberkit = "pounce",
	abacatudo = "hop",
	voltibun = "hop",
	zapmoth = "fly",
	mossnail = "brace",
	sparkit = "pounce",
	cinderhog = "brace",
	brookdeer = "pounce",
	bubblecrab = "brace",
	kelpony = "pounce",
	zapeel = "coil",
	pearlotter = "pounce",
	tidewhale = "breach",
	driftgull = "fly",
	fuzzbolt = "hop",
	bananao = "hop",
	reefwyrm = "coil",
	thundrake = "dragon",
	coalmole = "brace",
	steamtoad = "hop",
	moranguete = "hop",
	ashwolf = "pounce",
	thornback = "brace",
	sootbat = "fly",
	geyserpup = "pounce",
	voltscorp = "brace",
	lavalynx = "pounce",
	magmaroc = "dive",
})
export type Pose = {
	x: number,
	y: number,
	z: number,
	pitch: number,
	yaw: number,
	roll: number,
	effort: number,
}
local function smooth(t: number): number
	return t * t * (3 - 2 * t)
end

function BattleMotion.sample(petId: string, kind: string, alpha: number): Pose
	local t = math.clamp(alpha, 0, 1)
	local pose: Pose = { x = 0, y = 0, z = 0, pitch = 0, yaw = 0, roll = 0, effort = 0 }
	if t == 0 or t == 1 then
		return pose
	end
	if kind == "hit" then
		local recoil = if t < 0.18 then smooth(t / 0.18) else 1 - smooth((t - 0.18) / 0.82)
		pose.z, pose.pitch, pose.roll =
			recoil * 0.10, -recoil * 0.14, math.sin(t * math.pi * 4) * recoil * 0.08
		return pose
	end
	if kind ~= "attack" then
		return pose
	end
	local drive = if t < 0.24
		then -0.3 * smooth(t / 0.24)
		elseif t < 0.52 then -0.3 + 1.3 * smooth((t - 0.24) / 0.28)
		else 1 - smooth((t - 0.52) / 0.48)
	local lift = math.sin(t * math.pi) ^ 2
	local family = BattleMotion.families[petId] or "pounce"
	pose.z, pose.pitch, pose.effort = -drive * 0.13, drive * 0.12, drive
	if family == "hop" then
		pose.y, pose.pitch = lift * 0.12, drive * 0.20
	elseif family == "brace" then
		pose.y, pose.yaw = -lift * 0.03, -drive * 0.12
	elseif family == "fly" then
		pose.y, pose.roll = lift * 0.09, drive * 0.16
	elseif family == "coil" or family == "dragon" then
		pose.yaw, pose.roll = drive * 0.30, -drive * 0.10
		pose.y = lift * (if family == "dragon" then 0.07 else 0.02)
	elseif family == "breach" then
		pose.y, pose.pitch, pose.roll = lift * 0.16, -drive * 0.26, drive * 0.12
	elseif family == "dive" then
		pose.y, pose.pitch, pose.roll =
			lift * 0.10 - math.max(drive, 0) * 0.07, drive * 0.30, -drive * 0.18
	else
		pose.y = lift * 0.055
	end
	return pose
end

return BattleMotion
