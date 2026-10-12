--!strict
--[[
	RebirthService: rebirth when the player can afford it.

	Rebirth.canRebirth decides affordability and Rebirth.apply decides what is
	cleared and kept. The result is written back into the loaded profile table
	in place, so Profiles keeps saving the same table. A rebirth is refused
	while a gym battle is running, since the battle was built from the run
	that is about to end.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local rules = Shared:WaitForChild("rules")
local Profile = require(rules:WaitForChild("Profile"))
local Rebirth = require(rules:WaitForChild("Rebirth"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local Guard = require(script.Parent.Parent:WaitForChild("Guard"))
local GymService = require(script.Parent:WaitForChild("GymService"))

type Profile = Profile.Profile

local RebirthService = {}

local function onRebirth(player: Player, profile: Profile): (boolean, any)
	if GymService.inBattle(player) then
		return false, "in_battle"
	end
	if not Rebirth.canRebirth(profile :: any) then
		return false, "cannot_afford"
	end
	local nextState: any = Rebirth.apply(profile :: any)
	local target: any = profile
	for key, value in nextState do
		target[key] = value
	end
	return true, { rebirths = profile.rebirths }
end

function RebirthService.start()
	Guard.addDerived("rebirthCost", function(_player: Player, profile: Profile): number
		return Rebirth.cost(profile.rebirths)
	end)
	Guard.onInvoke(Remotes.names.Rebirth, onRebirth)
end

return RebirthService
