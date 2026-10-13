--!strict
--[[
	Passes: what the services ask about game passes.

	Ownership comes from Services/PassService, which checks it with Roblox on
	the server. What each pass does comes from shared/rules/PassEffects.
	Services ask here and never check a pass themselves.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PassEffects = require(
	ReplicatedStorage:WaitForChild("Shared"):WaitForChild("rules"):WaitForChild("PassEffects")
)
local PassService = require(script.Parent:WaitForChild("Services"):WaitForChild("PassService"))

local Passes = {}

-- True when the player owns the pass with this config id.
function Passes.owns(player: Player, passId: string): boolean
	return PassService.owns(player, passId)
end

-- The player's owned passes, keyed by config pass id.
function Passes.owned(player: Player): PassEffects.Owned
	return PassService.owned(player)
end

-- The product of every owned pass's coin factor, for Coins.perClick.
function Passes.coinMultiplier(player: Player): number
	return PassEffects.coinMultiplier(PassService.owned(player))
end

return Passes
