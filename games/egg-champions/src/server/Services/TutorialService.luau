--!strict
--[[
	TutorialService: keeps the first-time tutorial step in the profile.

	The rules live in shared/rules/Tutorial. Services call TutorialService.note
	with the event that just happened (coins, hatched, equipped, gym_started)
	before the state is pushed, so the step the client shows is always the
	server's. SkipTutorial ends the tutorial; it carries no arguments.

	When a profile loads, the saved step is resumed (Tutorial.resume) and the
	state is pushed again if that moved it.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local rules = Shared:WaitForChild("rules")
local Profile = require(rules:WaitForChild("Profile"))
local Tutorial = require(rules:WaitForChild("Tutorial"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local server = script.Parent.Parent
local Guard = require(server:WaitForChild("Guard"))
local Profiles = require(server:WaitForChild("Profiles"))

type Profile = Profile.Profile

local TutorialService = {}

-- Moves the profile's tutorial step for an event. The caller pushes.
function TutorialService.note(profile: Profile, event: Tutorial.Event)
	profile.tutorialStep = Tutorial.advance(profile :: any, event)
end

local function onSkip(_player: Player, profile: Profile): (boolean, any)
	TutorialService.note(profile, Tutorial.events.skip)
	return true, { tutorialStep = profile.tutorialStep }
end

function TutorialService.start()
	Guard.onInvoke(Remotes.names.SkipTutorial, onSkip)
	Profiles.onLoaded(function(player: Player, profile: Profile)
		local resumed = Tutorial.resume(profile :: any)
		if resumed ~= profile.tutorialStep then
			profile.tutorialStep = resumed
			Guard.push(player)
		end
	end)
end

return TutorialService
