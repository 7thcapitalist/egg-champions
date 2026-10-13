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
	- GiveUp(sessionId): ends the session as a loss.

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
-- retryAt[player][worldId] = os.clock() time the next attempt is allowed.
local retryAt: { [Player]: { [string]: number } } = {}

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

-- Ends a session. Returns true when a win gave a new badge.
local function finish(player: Player, profile: Profile, session: Session, won: boolean): boolean
	session.ended = true
	if won then
		local waits = retryAt[player]
		if waits ~= nil then
			waits[session.worldId] = nil
		end
		return Progression.beatGym(profile :: any, session.worldIndex)
	end
	local waits = retryAt[player] or {}
	retryAt[player] = waits
	waits[session.worldId] = os.clock() + Gym.retrySeconds()
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

local function onStartBattle(player: Player, profile: Profile, worldId: any): (boolean, any)
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
	local waits = retryAt[player]
	local readyAt = if waits ~= nil then waits[worldId] else nil
	if readyAt ~= nil and os.clock() < readyAt then
		return false, "retry_wait"
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
		newBadge = finish(player, profile, session, winner == "player")
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
	finish(player, profile, session, false)
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
	Players.PlayerRemoving:Connect(function(player: Player)
		forgetSession(player)
		retryAt[player] = nil
	end)
end

return GymService
