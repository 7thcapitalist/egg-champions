--!strict
--[[
	Server entry point.

	For now it only proves the generated config loads. Gameplay services arrive
	in later tasks and hang off this script.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

print(
	string.format(
		"%s server ready: %d pets, %d eggs, %d worlds",
		Config.constants.game_name,
		#Config.pets,
		#Config.eggs,
		#Config.worlds
	)
)
