--!strict
--[[
	Passes: what the services ask about game passes.

	Task 18 wires this to real game pass ownership. Until then nobody owns a
	pass, so Triple Hatch and Lucky Eggs are refused or off, and the coin
	multiplier is 1. Services ask here and never check a pass themselves, so
	task 18 changes this one file.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local Passes = {}

-- True when the player owns the pass with this config id.
function Passes.owns(_player: Player, passId: string): boolean
	local _ = Config.passById[passId]
	return false
end

-- The product of every owned pass's coin factor, for Coins.perClick.
function Passes.coinMultiplier(_player: Player): number
	return 1
end

return Passes
