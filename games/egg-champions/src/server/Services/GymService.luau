--!strict
--[[
	GymService: gym fees and battles, held entirely on the server.

	- PayGymFee(worldId): the world must be open, the fee is charged once per
	  rebirth run (Profile.feesPaid), and retries are free after that.
	- StartBattle(worldId): needs the fee paid, a non empty team, no battle
	  already running, and no retry wait. Builds the player team from the
	  equipped pets and the leader team from Gym.leaderTeam, and opens a
	  session the server keeps.
	- BattleMove(sessionId, move): resolves exactly one turn with
	  Battle.takeTurn and returns its event list. A win calls
	  Progression.beatGym; a loss starts the gym_retry_seconds wait.

	The retry wait is a deadline in the player's profile (Profile.gymRetryAt,
	server unix time), not server memory, so leaving and rejoining, even on
	another server, does not clear it. A "retry_wait" refusal carries
	retrySeconds, the whole seconds left, for the client's countdown.
	- GiveUp(sessionId): ends the session as a loss.
	- Leaving the game with a battle running ends it as giving up, before the
	  profile saves, so leaving and rejoining cannot skip the wait.

	The client holds no HP and no cooldown. Every answer carries a view of the
	battle (HP, max HP, cooldowns, the active pets) that it renders as sent.
	The rng never leaves the server.
]]

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local rules = Shared:WaitForChild("rules")
local Battle = require(rules:WaitForChild("Battle"))
local Config = require(Shared:WaitForChild("Config"))
local Gym = require(rules:WaitForChild("Gym"))
local Profile = require(rules:WaitForChild("Profile"))
local Progression = require(rules:WaitForChild("Progression"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Requests = require(Shared:WaitForChild("net"):WaitForChild("Requests"))
local BattleView = require(Shared:WaitForChild("ui"):WaitForChild("BattleView"))

local Guard = require(script.Parent.Parent:WaitForChild("Guard"))
local Passes = require(script.Parent.Parent:WaitForChild("Passes"))
local Analytics = require(script.Parent.Parent:WaitForChild("Analytics"))
local TutorialService = require(script.Parent:WaitForChild("TutorialService"))
local Profiles = require(script.Parent.Parent:WaitForChild("Profiles"))

type Profile = Profile.Profile

type Session = {
	id: string,
	ownerId: number,
	worldId: string,
	worldIndex: number,
	state: Battle.State,
	ended: boolean,
}

local GymService = {}

local worldIds: { string } = {}
for _, world in Config.worlds do
	table.insert(worldIds, world.id)
end
local knownWorlds = Requests.setOf(worldIds)

local rng = Random.new()

-- Every session by id. A player keeps at most one: the running one, or the
-- last one that ended, so a late move on it is answered "session_ended".
local sessions: { [string]: Session } = {}
local sessionOf: { [Player]: string } = {}
-- The server's clock for retry deadlines: unix seconds, shared by every
-- server, so a deadline saved on one server means the same on the next.
local function now(): number
	return DateTime.now().UnixTimestampMillis / 1000
end

-- The profile's retry deadlines, created if an older table lacks them.
local function retryWaits(profile: Profile): Gym.RetryWaits
	local waits = profile.gymRetryAt
	if type(waits) ~= "table" then
		waits = {}
		profile.gymRetryAt = waits
	end
	return waits
end

-- The battle view every answer carries: HP, max HP, speed, cooldowns and the
-- active pets. The battle screen renders it as sent.
local function view(state: Battle.State): BattleView.Snapshot
	return BattleView.snapshot(state)
end

local function sessionView(session: Session?): Requests.SessionView?
	if session == nil then
		return nil
	end
	return {
		ownerId = session.ownerId,
		ended = session.ended,
		specialReady = Battle.canUseSpecial(session.state),
	}
end

-- The running session for a player, or nil.
local function running(player: Player): Session?
	local id = sessionOf[player]
	local session = if id ~= nil then sessions[id] else nil
	if session ~= nil and not session.ended then
		return session
	end
	return nil
end

-- True while the player has a battle running. Rebirth refuses meanwhile.
function GymService.inBattle(player: Player): boolean
	return running(player) ~= nil
end

local function forgetSession(player: Player)
	local id = sessionOf[player]
	if id ~= nil then
		sessions[id] = nil
		sessionOf[player] = nil
	end
end

local function worldExists(worldIndex: number): boolean
	for _, world in Config.worlds do
		if world.index == worldIndex then
			return true
		end
	end
	return false
end

local function trackResult(player: Player, session: Session, outcome: string)
	Analytics.track(
		player,
		"gym_result",
		Analytics.withPlaytime(player, {
			worldIndex = session.worldIndex,
			outcome = outcome,
		})
	)
end

-- Ends a session with an Analytics.outcomes value. Returns true when a win
-- gave a new badge.
local function finish(player: Player, profile: Profile, session: Session, outcome: string): boolean
	session.ended = true
	if outcome == Analytics.outcomes.win then
		Gym.clearWait(retryWaits(profile), session.worldId)
		local nextIndex = session.worldIndex + 1
		local hasNext = worldExists(nextIndex)
		local wasOpen = hasNext and Progression.worldUnlocked(profile :: any, nextIndex)
		local newBadge = Progression.beatGym(profile :: any, session.worldIndex)
		trackResult(player, session, outcome)
		if hasNext and not wasOpen and Progression.worldUnlocked(profile :: any, nextIndex) then
			Analytics.track(
				player,
				"world_unlocked",
				Analytics.withPlaytime(player, { worldIndex = nextIndex })
			)
		end
		return newBadge
	end
	trackResult(player, session, outcome)
	Gym.recordEnd(retryWaits(profile), session.worldId, outcome, now())
	return false
end

local function onPayGymFee(_player: Player, profile: Profile, worldId: any): (boolean, any)
	local valid, reason = Requests.checkChoice(worldId, knownWorlds)
	if not valid then
		return false, reason
	end
	local world = Config.worldById[worldId]
	if not Progression.worldUnlocked(profile :: any, world.index) then
		return false, "world_locked"
	end
	if profile.feesPaid[worldId] == true then
		return false, "fee_already_paid"
	end
	local fee = Gym.fee(worldId)
	if profile.coins < fee then
		return false, "cannot_afford"
	end
	profile.coins -= fee
	profile.feesPaid[worldId] = true
	return true, { worldId = worldId, fee = fee }
end

local function onStartBattle(player: Player, profile: Profile, worldId: any): (boolean, any, any)
	local valid, reason = Requests.checkChoice(worldId, knownWorlds)
	if not valid then
		return false, reason
	end
	local world = Config.worldById[worldId]
	if not Progression.worldUnlocked(profile :: any, world.index) then
		return false, "world_locked"
	end
	if profile.feesPaid[worldId] ~= true then
		return false, "fee_not_paid"
	end
	if running(player) ~= nil then
		return false, "already_in_battle"
	end
	local waitReason, secondsLeft = Gym.retryRefusal(retryWaits(profile), worldId, now())
	if waitReason ~= nil then
		-- The seconds left ride along so the client can count down, even
		-- right after a rejoin when it never saw the loss.
		return false, waitReason, { retrySeconds = secondsLeft }
	end
	if #profile.team == 0 then
		return false, "team_empty"
	end

	local byUid: { [string]: Profile.OwnedPet } = {}
	for _, pet in profile.pets do
		byUid[pet.uid] = pet
	end
	local equipped: { Gym.OwnedPet } = {}
	for _, uid in profile.team do
		local pet = byUid[uid]
		if pet ~= nil then
			table.insert(equipped, { petId = pet.petId, variant = pet.variant })
		end
	end
	if #equipped == 0 then
		return false, "team_empty"
	end

	local state = Gym.startBattle({
		worldId = worldId,
		pets = equipped,
		rebirths = profile.rebirths,
		passes = Passes.owned(player),
	}, rng :: any)
	forgetSession(player)
	local session: Session = {
		id = HttpService:GenerateGUID(false),
		ownerId = player.UserId,
		worldId = worldId,
		worldIndex = world.index,
		state = state,
		ended = false,
	}
	sessions[session.id] = session
	sessionOf[player] = session.id
	TutorialService.note(profile, "gym_started")
	Analytics.track(
		player,
		"gym_attempt",
		Analytics.withPlaytime(player, { worldIndex = world.index })
	)
	return true, { sessionId = session.id, worldId = worldId, battle = view(state) }
end

local function onBattleMove(
	player: Player,
	profile: Profile,
	sessionId: any,
	move: any
): (boolean, any)
	if not Requests.isChoiceString(sessionId) then
		return false, Requests.reasons.badChoice
	end
	local session = sessions[sessionId]
	local ok, reason = Requests.checkMove(sessionView(session), player.UserId, move)
	if not ok or session == nil then
		return false, reason
	end

	local nextState, events = Battle.takeTurn(session.state, move)
	session.state = nextState
	local winner = Battle.isOver(nextState)
	local newBadge = false
	if winner ~= nil then
		newBadge = finish(
			player,
			profile,
			session,
			if winner == "player" then Analytics.outcomes.win else Analytics.outcomes.loss
		)
	end
	return true,
		{
			sessionId = session.id,
			events = events,
			battle = view(nextState),
			finished = winner ~= nil,
			won = winner == "player",
			newBadge = newBadge,
			retrySeconds = if winner == "leader" then Gym.retrySeconds() else nil,
		}
end

local function onGiveUp(player: Player, profile: Profile, sessionId: any): (boolean, any)
	if not Requests.isChoiceString(sessionId) then
		return false, Requests.reasons.badChoice
	end
	local session = sessions[sessionId]
	local ok, reason = Requests.checkSession(sessionView(session), player.UserId)
	if not ok or session == nil then
		return false, reason
	end
	finish(player, profile, session, Analytics.outcomes.gaveUp)
	return true,
		{
			sessionId = session.id,
			events = { { kind = "lose", side = "player" } },
			battle = view(session.state),
			finished = true,
			won = false,
			newBadge = false,
			retrySeconds = Gym.retrySeconds(),
		}
end

function GymService.start()
	Guard.onInvoke(Remotes.names.PayGymFee, onPayGymFee)
	Guard.onInvoke(Remotes.names.StartBattle, onStartBattle)
	Guard.onInvoke(Remotes.names.BattleMove, onBattleMove)
	Guard.onInvoke(Remotes.names.GiveUp, onGiveUp)
	-- Leaving with a battle running counts as giving up, so the retry wait
	-- applies after a rejoin. Profiles runs this before it saves the profile
	-- on leave (and on shutdown), so the deadline is in the saved data.
	Profiles.onLeaving(function(player: Player, profile: Profile)
		local session = running(player)
		if session ~= nil then
			finish(player, profile, session, Analytics.outcomes.gaveUp)
		end
		forgetSession(player)
	end)
	-- A player whose profile never loaded has no session; this only tidies.
	Players.PlayerRemoving:Connect(function(player: Player)
		task.defer(forgetSession, player)
	end)
end

return GymService
