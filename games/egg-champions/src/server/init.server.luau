--!strict
--[[
	Server entry point.

	Proves the generated config loads, then starts the server in order: the
	worlds are built from config, Guard creates every remote, the services and
	portals hook their handlers, and only then do profiles start loading, so no
	player can send a request before its handler exists. Each profile is pushed
	to its player as soon as it loads, so the HUD starts with real numbers.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local function movement(player: Player)
	local function characterAdded(character: Model)
		local humanoid = character:WaitForChild("Humanoid", 10)
		if humanoid and humanoid:IsA("Humanoid") then
			humanoid.WalkSpeed = Config.constants.character_walk_speed
		end
	end
	player.CharacterAdded:Connect(characterAdded)
	if player.Character then
		task.spawn(characterAdded, player.Character)
	end
end
Players.PlayerAdded:Connect(movement)
for _, player in Players:GetPlayers() do
	movement(player)
end
local Profiles = require(script:WaitForChild("Profiles"))
local Guard = require(script:WaitForChild("Guard"))
local Analytics = require(script:WaitForChild("Analytics"))
local ModelLibrary = require(script:WaitForChild("ModelLibrary"))

local Services = script:WaitForChild("Services")
local ClickService = require(Services:WaitForChild("ClickService"))
local ShopService = require(Services:WaitForChild("ShopService"))
local TeamService = require(Services:WaitForChild("TeamService"))
local GymService = require(Services:WaitForChild("GymService"))
local RebirthService = require(Services:WaitForChild("RebirthService"))
local PassService = require(Services:WaitForChild("PassService"))
local TutorialService = require(Services:WaitForChild("TutorialService"))

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

-- Pet and egg models load in their own thread; until one loads, PetVisual
-- shows its placeholder block.
task.spawn(ModelLibrary.start)
-- Each egg stand swaps its placeholder for the egg's model once it loads.
task.spawn(Builder.dressEggStands, built, ModelLibrary.FOLDER)

Guard.start()
ClickService.start()
ShopService.start()
TeamService.start()
GymService.start()
RebirthService.start()
PassService.start(ClickService.autoClick)
TutorialService.start()
Portals.start(built)
-- Session start and end, and the analytics flush loop. Before Profiles.start,
-- so the first profile load already counts as a session start.
Analytics.start(ClickService.coinsPerClick)
-- Send each player their first state as soon as it loads, so the HUD shows the
-- real numbers before the first click.
Profiles.onLoaded(function(player: Player)
	Guard.push(player)
end)
Profiles.start()
