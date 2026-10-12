--!strict
--[[
	Portals: walking into a portal moves a player to the next world, if the
	server agrees.

	The server decides: on touch it loads the player's profile and asks
	Progression.worldUnlocked for the portal's target world. An open portal
	moves the character onto that world's arrival point. A locked portal, or
	the last world's "coming soon" portal, refuses and sends the player a
	Notice saying what is needed.

	The cooldown below is touch debounce timing, not a game number.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Progression = require(Shared:WaitForChild("rules"):WaitForChild("Progression"))

local server = script.Parent.Parent
local Guard = require(server:WaitForChild("Guard"))
local Profiles = require(server:WaitForChild("Profiles"))
local Builder = require(script.Parent:WaitForChild("Builder"))

local TOUCH_COOLDOWN_SECONDS = 2
local ARRIVAL_LIFT = 4

local Portals = {}

local lastTouch: { [Player]: number } = {}

-- What happens when a player touches a portal. Returns true when they moved.
function Portals.tryEnter(player: Player, site: Builder.PortalSite, built: Builder.Built): boolean
	local portal = site.portal
	local profile = Profiles.get(player)
	if profile == nil then
		return false
	end
	local toIndex = portal.toIndex
	local toWorldId = portal.toWorldId
	if toIndex == nil or toWorldId == nil then
		Guard.notify(player, portal.lockedMessage)
		return false
	end
	if not Progression.worldUnlocked(profile :: any, toIndex) then
		Guard.notify(player, portal.lockedMessage)
		return false
	end
	local character = player.Character
	if character == nil then
		return false
	end
	local arrival = built.plan.arrivals[toWorldId]
	character:PivotTo(CFrame.new(arrival.x, arrival.y + ARRIVAL_LIFT, arrival.z))
	return true
end

function Portals.start(built: Builder.Built)
	for _, site in built.portals do
		site.trigger.Touched:Connect(function(hit: BasePart)
			local character = hit.Parent
			if character == nil then
				return
			end
			local player = Players:GetPlayerFromCharacter(character)
			if player == nil then
				return
			end
			local now = os.clock()
			local last = lastTouch[player]
			if last ~= nil and now - last < TOUCH_COOLDOWN_SECONDS then
				return
			end
			lastTouch[player] = now
			local ok, err = pcall(Portals.tryEnter, player, site, built)
			if not ok then
				warn(string.format("[World] portal for %s failed: %s", player.Name, tostring(err)))
			end
		end)
	end
	Players.PlayerRemoving:Connect(function(player: Player)
		lastTouch[player] = nil
	end)
end

return Portals
