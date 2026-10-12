--!strict
--[[
	Profiles: the only door to saved player data.

	One DataStore, one key per user id. A profile loads when the player joins,
	saves when they leave, and autosaves every AUTOSAVE_SECONDS. Nothing else in
	the codebase may touch the DataStore.

	Each key holds a record:
		{ profile = <Profile>, session = { jobId, heartbeat } | nil }

	Session locking: a server claims a key by writing its own jobId and the
	current time into session, inside UpdateAsync, so the claim is atomic. Every
	autosave refreshes the heartbeat. Another server that finds a live session
	waits, retrying, until the heartbeat is older than LOCK_STALE_SECONDS. So
	two servers never write the same profile. Leaving releases the lock.

	Every DataStore call goes through pcall with a bounded retry. A failure is
	logged and retried, never swallowed. A profile that could not be loaded is
	never saved, so a failed load can not overwrite good data with an empty
	profile; that player is kicked with a message instead.

	On load the data goes through Profile.migrate, then Profile.validate.
	Repairable problems (a team that is too long, or that holds a uid the player
	does not own) are fixed and logged; anything else refuses the load.

	The numbers below are storage timing, not game numbers.
]]

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Profile = require(Shared:WaitForChild("rules"):WaitForChild("Profile"))

type Profile = Profile.Profile

type Session = {
	jobId: string,
	heartbeat: number,
}

type Record = {
	profile: any,
	session: Session?,
}

local STORE_NAME = "PlayerProfiles"
local AUTOSAVE_SECONDS = 60
local LOCK_STALE_SECONDS = 300
local LOCK_RETRY_SECONDS = 10
local LOCK_MAX_WAIT_SECONDS = LOCK_STALE_SECONDS + 60
local CALL_ATTEMPTS = 5
local CALL_BACKOFF_SECONDS = 2

local store = DataStoreService:GetDataStore(STORE_NAME)

-- Studio servers share the empty JobId, so give each one its own id.
local jobId = if game.JobId ~= "" then game.JobId else "studio-" .. HttpService:GenerateGUID(false)

local loaded: { [Player]: Profile } = {}

local Profiles = {}

local function keyFor(userId: number): string
	return "user_" .. tostring(userId)
end

local function log(userId: number, message: string)
	warn(string.format("[Profiles] user %d: %s", userId, message))
end

-- Runs UpdateAsync with a bounded retry. Returns ok and the stored result.
local function update(userId: number, label: string, transform: (any) -> any): (boolean, any)
	local key = keyFor(userId)
	local lastError: any = nil
	for attempt = 1, CALL_ATTEMPTS do
		local ok, result = pcall(function()
			return store:UpdateAsync(key, transform)
		end)
		if ok then
			return true, result
		end
		lastError = result
		log(
			userId,
			string.format(
				"%s failed (try %d of %d): %s",
				label,
				attempt,
				CALL_ATTEMPTS,
				tostring(result)
			)
		)
		if attempt < CALL_ATTEMPTS then
			task.wait(CALL_BACKOFF_SECONDS * attempt)
		end
	end
	log(
		userId,
		string.format("%s gave up after %d tries: %s", label, CALL_ATTEMPTS, tostring(lastError))
	)
	return false, nil
end

local function lockIsFree(session: Session?, now: number): boolean
	if session == nil then
		return true
	end
	if session.jobId == jobId then
		return true
	end
	return now - session.heartbeat > LOCK_STALE_SECONDS
end

-- Claims the key for this server. Returns "claimed" with the stored profile
-- data (nil for a new player), "locked" when another live server holds it, or
-- "failed" when the DataStore could not be reached.
local function claim(userId: number): (string, any)
	local outcome = "failed"
	local data: any = nil
	local ok = update(userId, "claim", function(old: any): any
		local record: Record = if type(old) == "table"
			then old
			else { profile = nil, session = nil }
		local now = os.time()
		if not lockIsFree(record.session, now) then
			outcome = "locked"
			return nil -- leave the record alone
		end
		outcome = "claimed"
		data = record.profile
		record.session = { jobId = jobId, heartbeat = now }
		return record
	end)
	if not ok then
		return "failed", nil
	end
	return outcome, data
end

-- Waits for the lock, then migrates, validates and repairs the profile.
-- Returns the profile, or nil and a reason the player can be shown.
local function load(player: Player): (Profile?, string?)
	local userId = player.UserId
	local started = os.clock()
	local outcome, data
	while true do
		outcome, data = claim(userId)
		if outcome ~= "locked" then
			break
		end
		if player.Parent == nil then
			return nil, "left while waiting"
		end
		if os.clock() - started > LOCK_MAX_WAIT_SECONDS then
			log(userId, "still locked by another server, giving up")
			return nil, "Your save is still open on another server. Please rejoin in a few minutes."
		end
		log(userId, "locked by another server, waiting for it to release or go stale")
		task.wait(LOCK_RETRY_SECONDS)
	end
	if outcome == "failed" then
		return nil, "Your save could not be loaded right now. Please rejoin."
	end

	if data == nil then
		log(userId, "no save found, starting a new profile")
		return Profile.new(), nil
	end

	local okMigrate, migrated = pcall(Profile.migrate, data)
	if not okMigrate then
		log(userId, "refused save: " .. tostring(migrated))
		return nil, "Your save could not be read by this server. It has not been changed."
	end

	local problems = Profile.validate(migrated)
	if #problems == 0 then
		return migrated, nil
	end
	for _, problem in problems do
		log(userId, string.format("save problem %s: %s", problem.kind, problem.detail))
	end
	local repaired, remaining = Profile.repair(migrated)
	if #remaining > 0 then
		for _, problem in remaining do
			log(userId, string.format("cannot repair %s: %s", problem.kind, problem.detail))
		end
		return nil, "Your save has a problem we could not fix. It has not been changed."
	end
	log(userId, "save repaired")
	return repaired, nil
end

-- Writes the profile and refreshes (or releases) the lock. Refuses to write
-- when another server has taken the lock, so a stale server never overwrites.
local function save(userId: number, profile: Profile, release: boolean): boolean
	local lost = false
	local ok = update(
		userId,
		if release then "save and release" else "autosave",
		function(old: any): any
			local record: Record = if type(old) == "table"
				then old
				else { profile = nil, session = nil }
			local session = record.session
			if session ~= nil and session.jobId ~= jobId then
				lost = true
				return nil
			end
			record.profile = profile
			record.session = if release then nil else { jobId = jobId, heartbeat = os.time() }
			return record
		end
	)
	if lost then
		log(userId, "lock is held by another server, this save was not written")
		return false
	end
	return ok
end

-- The loaded profile for a player, or nil while loading or after a failed load.
function Profiles.get(player: Player): Profile?
	return loaded[player]
end

local function onJoin(player: Player)
	local profile, reason = load(player)
	if profile == nil then
		if player.Parent ~= nil then
			player:Kick(reason)
		end
		return
	end
	if player.Parent == nil then
		-- Left while loading: release the lock without changing anything.
		save(player.UserId, profile, true)
		return
	end
	loaded[player] = profile
end

local function onLeave(player: Player)
	local profile = loaded[player]
	if profile == nil then
		return
	end
	loaded[player] = nil
	save(player.UserId, profile, true)
end

local started = false

-- Hooks joins, leaves, shutdown and the autosave loop. Call once.
function Profiles.start()
	if started then
		return
	end
	started = true

	Players.PlayerAdded:Connect(onJoin)
	Players.PlayerRemoving:Connect(onLeave)
	for _, player in Players:GetPlayers() do
		task.spawn(onJoin, player)
	end

	task.spawn(function()
		while true do
			task.wait(AUTOSAVE_SECONDS)
			for player, profile in loaded do
				task.spawn(save, player.UserId, profile, false)
			end
		end
	end)

	game:BindToClose(function()
		local pending = 0
		for player, profile in loaded do
			pending += 1
			loaded[player] = nil
			task.spawn(function()
				save(player.UserId, profile, true)
				pending -= 1
			end)
		end
		while pending > 0 do
			task.wait()
		end
		if RunService:IsStudio() then
			task.wait(1)
		end
	end)
end

return Profiles
