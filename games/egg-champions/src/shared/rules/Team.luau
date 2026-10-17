--!strict
--[[
	Team: which owned pets may be equipped.

	There is one team. The same equipped list earns coins per click and fights
	gym battles. Equip Best can rank for either purpose before replacing it.

	A team is a plain list of pet uids, in equip order. The owned pets are a
	plain list of uids too. Every function leaves its inputs untouched: equip
	and unequip return a new list, or nil and a reason, so a rejected request
	can never change the team.

	The size limit comes from Config.constants.team_size.
]]

local Config = require(script.Parent.Parent.Config)
local Coins = require(script.Parent.Coins)
local Battle = require(script.Parent.Battle)

export type Uid = string
export type TeamList = { Uid }
export type OwnedPet = {
	uid: Uid,
	petId: string,
	variant: string?,
}

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

-- Replace the whole team with the strongest owned pets for coins per click.
-- Ties keep inventory order, including when two variants have equal power.
-- The caller passes server-owned profile pets, never client rankings or uids.
type Ranked = { uid: Uid, power: number, speed: number, index: number }

local function bestFromRanked(ranked: { Ranked }): TeamList
	table.sort(ranked, function(a, b)
		if a.power ~= b.power then
			return a.power > b.power
		end
		if a.speed ~= b.speed then
			return a.speed > b.speed
		end
		return a.index < b.index
	end)
	local team: TeamList = {}
	local seen: { [Uid]: boolean } = {}
	for _, pet in ranked do
		if not seen[pet.uid] then
			table.insert(team, pet.uid)
			seen[pet.uid] = true
			if #team >= Team.maxSize() then
				break
			end
		end
	end
	return team
end

function Team.bestForCoins(owned: { OwnedPet }): TeamList
	local ranked: { Ranked } = {}
	local anchor = Coins.legacyAnchor(owned)
	for index, pet in owned do
		table.insert(
			ranked,
			{ uid = pet.uid, power = Coins.clickPowerOf(pet, anchor), speed = 0, index = index }
		)
	end
	return bestFromRanked(ranked)
end

-- A general battle recommendation, not an opponent-specific matchup.
-- HP and Attack use the same multiplier as battle start; Speed breaks equal
-- strength scores, and inventory order breaks a remaining tie.
function Team.bestForBattle(owned: { OwnedPet }, rebirths: number): TeamList
	local ranked: { Ranked } = {}
	for index, pet in owned do
		local fighter = Battle.fighterFromPet(pet.petId, pet.variant)
		local multiplier = Battle.playerMultiplier(rebirths, pet.variant)
		table.insert(ranked, {
			uid = pet.uid,
			power = (fighter.hp * multiplier) * (fighter.attack * multiplier),
			speed = fighter.speed,
			index = index,
		})
	end
	return bestFromRanked(ranked)
end

function Team.unequipAll(): TeamList
	return {}
end

return Team
