--!strict
--[[
	TeamService: equipping and unequipping pets.

	The client sends a pet uid. Team decides, and a refusal goes back with the
	rule module's own reason (not_owned, already_equipped, team_full,
	not_equipped). The team is only replaced when the rule module accepts.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local rules = Shared:WaitForChild("rules")
local Profile = require(rules:WaitForChild("Profile"))
local Team = require(rules:WaitForChild("Team"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Requests = require(Shared:WaitForChild("net"):WaitForChild("Requests"))

local Guard = require(script.Parent.Parent:WaitForChild("Guard"))

type Profile = Profile.Profile

local TeamService = {}

local function ownedUids(profile: Profile): { string }
	local uids: { string } = {}
	for _, pet in profile.pets do
		table.insert(uids, pet.uid)
	end
	return uids
end

local function onEquip(_player: Player, profile: Profile, uid: any): (boolean, any)
	if not Requests.isChoiceString(uid) then
		return false, Requests.reasons.badChoice
	end
	local nextTeam, reason = Team.equip(profile.team, ownedUids(profile), uid)
	if nextTeam == nil then
		return false, reason
	end
	profile.team = nextTeam
	return true, { team = table.clone(nextTeam) }
end

local function onUnequip(_player: Player, profile: Profile, uid: any): (boolean, any)
	if not Requests.isChoiceString(uid) then
		return false, Requests.reasons.badChoice
	end
	local nextTeam, reason = Team.unequip(profile.team, uid)
	if nextTeam == nil then
		return false, reason
	end
	profile.team = nextTeam
	return true, { team = table.clone(nextTeam) }
end

function TeamService.start()
	Guard.onInvoke(Remotes.names.Equip, onEquip)
	Guard.onInvoke(Remotes.names.Unequip, onUnequip)
end

return TeamService
