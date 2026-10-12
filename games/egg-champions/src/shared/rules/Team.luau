--!strict
--[[
	Team: which owned pets may be equipped.

	There is one team. The same equipped list earns coins per click and fights
	gym battles, so nothing here knows which of the two a caller wants.

	A team is a plain list of pet uids, in equip order. The owned pets are a
	plain list of uids too. Every function leaves its inputs untouched: equip
	and unequip return a new list, or nil and a reason, so a rejected request
	can never change the team.

	The size limit comes from Config.constants.team_size.
]]

local Config = require(script.Parent.Parent.Config)

export type Uid = string
export type TeamList = { Uid }

export type Reason = "not_owned" | "already_equipped" | "team_full" | "not_equipped"

local Team = {}

Team.reasons = table.freeze({
	notOwned = "not_owned" :: Reason,
	alreadyEquipped = "already_equipped" :: Reason,
	teamFull = "team_full" :: Reason,
	notEquipped = "not_equipped" :: Reason,
})

function Team.maxSize(): number
	return Config.constants.team_size
end

function Team.isEquipped(team: TeamList, petUid: Uid): boolean
	return table.find(team, petUid) ~= nil
end

-- Returns true, or false and the reason the pet cannot be equipped.
-- Checked in a fixed order: ownership, then duplicates, then room.
function Team.canEquip(team: TeamList, owned: { Uid }, petUid: Uid): (boolean, Reason?)
	if table.find(owned, petUid) == nil then
		return false, Team.reasons.notOwned
	end
	if Team.isEquipped(team, petUid) then
		return false, Team.reasons.alreadyEquipped
	end
	if #team >= Team.maxSize() then
		return false, Team.reasons.teamFull
	end
	return true, nil
end

-- Returns a new team with the pet added at the end, or nil and a reason.
function Team.equip(team: TeamList, owned: { Uid }, petUid: Uid): (TeamList?, Reason?)
	local ok, reason = Team.canEquip(team, owned, petUid)
	if not ok then
		return nil, reason
	end
	local nextTeam = table.clone(team)
	table.insert(nextTeam, petUid)
	return nextTeam, nil
end

-- Returns a new team without the pet, or nil and a reason.
function Team.unequip(team: TeamList, petUid: Uid): (TeamList?, Reason?)
	local position = table.find(team, petUid)
	if position == nil then
		return nil, Team.reasons.notEquipped
	end
	local nextTeam = table.clone(team)
	table.remove(nextTeam, position)
	return nextTeam, nil
end

return Team
