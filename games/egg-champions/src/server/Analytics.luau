--!strict
--[[
	Analytics: the one door every analytics event goes through. Server only.

	Analytics.fire(player, eventName, fields) checks the event against the
	fixed list in shared/analytics/Events (an unknown name or a bad field is an
	error), adds the player's stage (rebirths and current world), and queues
	it. The queue is flushed every FLUSH_SECONDS and when a player leaves.
	Services call Analytics.track, the same call wrapped in pcall, because by
	then their request has already changed the profile.

	Sending uses Roblox's AnalyticsService: egg_bought as an economy event,
	first_hatch also as onboarding funnel step 1, and everything else as a
	custom event. Every send runs in pcall through Queue.flush; a failed send
	is logged and dropped, never retried. Analytics never breaks gameplay.

	session_start fires when a profile loads, session_end when the player
	leaves. Only the Roblox user id identifies a player; no other personal
	data is recorded. See notes/analytics-events.md for every event.

	The numbers below are send timing and memory limits, not game numbers.
]]

local AnalyticsService = game:GetService("AnalyticsService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local analytics = Shared:WaitForChild("analytics")
local Events = require(analytics:WaitForChild("Events"))
local Queue = require(analytics:WaitForChild("Queue"))
local Profile = require(Shared:WaitForChild("rules"):WaitForChild("Profile"))

local Profiles = require(script.Parent:WaitForChild("Profiles"))

type Profile = Profile.Profile

type Pending = {
	player: Player,
	record: Events.Record,
}

local FLUSH_SECONDS = 30
local QUEUE_LIMIT = 1000
local CURRENCY = "Coins"

local Analytics = {}

local queue: Queue.Queue<Pending> = Queue.new(QUEUE_LIMIT)
local joinedAt: { [Player]: number } = {}
-- The last loaded profile per player, so session_end still has the stage
-- after Profiles has let go of the player.
local lastProfile: { [Player]: Profile } = {}
local coinsPerClick: (Player, Profile) -> number = function(
	_player: Player,
	_profile: Profile
): number
	return 0
end
local started = false

-- The variant name pet_hatched sends for a pet with no variant, and the
-- outcomes gym_result may carry.
Analytics.NORMAL_VARIANT = Events.NORMAL_VARIANT
Analytics.outcomes = Events.outcomes

-- Seconds since this player's profile loaded in this session.
function Analytics.secondsSinceJoin(player: Player): number
	local at = joinedAt[player]
	if at == nil then
		return 0
	end
	return math.floor(os.clock() - at)
end

-- Queues one event. Errors when the event is not in Events.list or a field is
-- wrong. Does nothing for a player with no loaded profile.
function Analytics.fire(player: Player, eventName: string, fields: { [string]: any })
	local _ = Events.get(eventName)
	local profile = Profiles.get(player) or lastProfile[player]
	if profile == nil then
		return
	end
	local record = Events.build(eventName, fields, Events.context(profile :: any))
	if Queue.push(queue, { player = player, record = record }) then
		warn("[Analytics] queue full, dropped the oldest event")
	end
end

local function send(item: Pending)
	local record = item.record
	local event = Events.get(record.name)
	local custom = Events.customFields(record)
	local economy = event.economy
	if economy ~= nil then
		local flow = if economy.flow == "Sink"
			then Enum.AnalyticsEconomyFlowType.Sink
			else Enum.AnalyticsEconomyFlowType.Source
		AnalyticsService:LogEconomyEvent(
			item.player,
			flow,
			CURRENCY,
			record.fields[economy.amount],
			record.fields[economy.balance],
			economy.transaction,
			record.fields[economy.item],
			custom
		)
		return
	end
	if event.onboardingStep ~= nil then
		AnalyticsService:LogOnboardingStepEvent(item.player, event.onboardingStep, record.name)
	end
	AnalyticsService:LogCustomEvent(item.player, record.name, Events.value(record) or 1, custom)
end

local function logFailure(item: Pending, err: string)
	warn(
		string.format(
			"[Analytics] dropped %s for user %d: %s",
			item.record.name,
			item.player.UserId,
			err
		)
	)
end

-- Sends everything waiting. Safe to call at any time.
function Analytics.flush()
	Queue.flush(queue, send, logFailure)
end

local function safeFire(player: Player, eventName: string, fields: () -> { [string]: any })
	local ok, err = pcall(function()
		Analytics.fire(player, eventName, fields())
	end)
	if not ok then
		warn(
			string.format(
				"[Analytics] %s for user %d failed: %s",
				eventName,
				player.UserId,
				tostring(err)
			)
		)
	end
end

-- Analytics.fire for services, called after a request has already changed
-- the profile: a bad event is logged loudly instead of failing the request,
-- so analytics never breaks gameplay.
function Analytics.track(player: Player, eventName: string, fields: { [string]: any })
	safeFire(player, eventName, function()
		return fields
	end)
end

-- Hooks session start and end and the flush loop. Call once, before
-- Profiles.start. coinsPerClickOf reports a player's coins per click, as the
-- server computes it.
function Analytics.start(coinsPerClickOf: (Player, Profile) -> number)
	if started then
		return
	end
	started = true
	coinsPerClick = coinsPerClickOf

	Profiles.onLoaded(function(player: Player, profile: Profile)
		joinedAt[player] = os.clock()
		lastProfile[player] = profile
		safeFire(player, "session_start", function()
			return { coinsPerClick = coinsPerClick(player, profile) }
		end)
	end)

	Players.PlayerRemoving:Connect(function(player: Player)
		local profile = lastProfile[player]
		if profile ~= nil then
			safeFire(player, "session_end", function()
				return {
					lengthSeconds = Analytics.secondsSinceJoin(player),
					coinsPerClick = coinsPerClick(player, profile),
				}
			end)
		end
		Analytics.flush()
		joinedAt[player] = nil
		lastProfile[player] = nil
	end)

	task.spawn(function()
		while true do
			task.wait(FLUSH_SECONDS)
			Analytics.flush()
		end
	end)

	game:BindToClose(function()
		Analytics.flush()
	end)
end

return Analytics
