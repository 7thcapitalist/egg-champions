--!strict
--[[
	Server entry point.

	Proves the generated config loads, then starts the server services.
	More gameplay services arrive in later tasks and hang off this script.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local Profiles = require(script:WaitForChild("Profiles"))

print(
	string.format(
		"%s server ready: %d pets, %d eggs, %d worlds",
		Config.constants.game_name,
		#Config.pets,
		#Config.eggs,
		#Config.worlds
	)
)

Profiles.start()
