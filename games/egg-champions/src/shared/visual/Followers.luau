--!strict
--[[
	Followers: the plain math behind the pets that follow each player.

	The server writes each player's equipped team onto the Player as one
	string attribute (encode), so every client can see every team without a
	remote or any work per frame on the server. Each client decodes it and
	places the pets itself (client/Effects/Followers): a small arc behind the
	player, at a hover height, with a gentle bob.

	Everything here is display distance and timing, not game numbers, and
	nothing here touches the engine.
]]

export type Member = {
	petId: string,
	variant: string?,
}

-- An offset from the player's root part in its own space: x to the right,
-- y up, z backward (Roblox looks along -z, so +z is behind).
export type Offset = {
	x: number,
	y: number,
	z: number,
}

local Followers = {}

-- The Player attribute that carries the equipped team.
Followers.ATTRIBUTE = "FollowerTeam"

Followers.LOOK = table.freeze({
	-- How far behind the root part the arc sits, in studs.
	behind = 5,
	-- Half the angle the arc spans, in degrees, for a full team.
	spread = 40,
	-- The height of the pets over the root part, in studs.
	hover = 0.5,
	-- The bob: its height in studs and its period in seconds.
	bob = 0.35,
	bobSeconds = 1.6,
	-- Followers are only drawn for players this close to the camera.
	viewDistance = 160,
	-- How quickly a pet catches up with its spot, per second (0 to 1 share
	-- of the gap closed in one second is 1 - exp(-catchUp)).
	catchUp = 10,
})

local SEPARATOR = ","
local VARIANT_MARK = ":"

-- The equipped team as one attribute string: "petId:variant" per pet, in
-- team order. Pets the team names but the list does not own are skipped.
function Followers.encode(pets: any, team: any): string
	if type(pets) ~= "table" or type(team) ~= "table" then
		return ""
	end
	local byUid: { [string]: any } = {}
	for _, pet in pets do
		if type(pet) == "table" and type(pet.uid) == "string" then
			byUid[pet.uid] = pet
		end
	end
	local parts = {}
	for _, uid in team do
		local pet = byUid[uid]
		if pet ~= nil and type(pet.petId) == "string" then
			local variant = if type(pet.variant) == "string" then pet.variant else ""
			table.insert(parts, pet.petId .. VARIANT_MARK .. variant)
		end
	end
	return table.concat(parts, SEPARATOR)
end

-- The team back from an attribute value; anything that is not a string is
-- an empty team.
function Followers.decode(value: any): { Member }
	local members: { Member } = {}
	if type(value) ~= "string" or value == "" then
		return members
	end
	for _, part in string.split(value, SEPARATOR) do
		local mark = string.find(part, VARIANT_MARK, 1, true)
		local petId = if mark ~= nil then string.sub(part, 1, mark - 1) else part
		local variant = if mark ~= nil then string.sub(part, mark + 1) else ""
		if petId ~= "" then
			table.insert(members, {
				petId = petId,
				variant = if variant ~= "" then variant else nil,
			})
		end
	end
	return members
end

-- Where pet `index` of `count` hovers at `seconds`: spread evenly on an arc
-- behind the player, each bobbing a little out of step with the others.
function Followers.offset(index: number, count: number, seconds: number): Offset
	local look = Followers.LOOK
	local share = if count <= 1 then 0 else (index - 1) / (count - 1) * 2 - 1
	local angle = math.rad(look.spread) * share
	local phase = (index - 1) * 0.9
	local bob = math.sin(seconds / look.bobSeconds * 2 * math.pi + phase) * look.bob
	return {
		x = math.sin(angle) * look.behind,
		y = look.hover + bob,
		z = math.cos(angle) * look.behind,
	}
end

-- The share of the gap a follower closes in a frame of dt seconds.
function Followers.blend(dt: number): number
	if dt <= 0 then
		return 0
	end
	return 1 - math.exp(-Followers.LOOK.catchUp * dt)
end

return Followers
