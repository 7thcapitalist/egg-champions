--!strict
--[[
	Server entry point.

	Proves the generated config loads, then starts the server in order: the
	worlds are built from config, Guard creates every remote, the services and
	portals hook their handlers, and only then do profiles start loading, so no
	player can send a request before its handler exists.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local Profiles = require(script:WaitForChild("Profiles"))
local Guard = require(script:WaitForChild("Guard"))

local Services = script:WaitForChild("Services")
local ClickService = require(Services:WaitForChild("ClickService"))
local ShopService = require(Services:WaitForChild("ShopService"))
local TeamService = require(Services:WaitForChild("TeamService"))
local GymService = require(Services:WaitForChild("GymService"))
local RebirthService = require(Services:WaitForChild("RebirthService"))

local World = script:WaitForChild("World")
local Builder = require(World:WaitForChild("Builder"))
local Portals = require(World:WaitForChild("Portals"))

print(
	string.format(
		"%s server ready: %d pets, %d eggs, %d worlds",
		Config.constants.game_name,
		#Config.pets,
		#Config.eggs,
		#Config.worlds
	)
)

local built = Builder.buildAll()
print(
	string.format(
		"worlds built: %d egg stands, %d gyms, %d portals",
		built.counts.eggStands,
		built.counts.gyms,
		built.counts.portals
	)
)

Guard.start()
ClickService.start()
ShopService.start()
TeamService.start()
GymService.start()
RebirthService.start()
Portals.start(built)
Profiles.start()
