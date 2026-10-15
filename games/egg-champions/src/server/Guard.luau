--!strict
--[[
	Guard: the one door every remote request comes through.

	Guard.start creates every remote named in shared/Remotes, so the client
	never creates one. Services hook their handlers with Guard.onEvent and
	Guard.onInvoke, which apply the rules every remote shares:

	- A player with no loaded profile is rejected before the handler runs.
	- Every rejection is logged with the player, the remote and the reason.
	- Every RemoteFunction (SkipTutorial included) is rate limited per player
	  and per remote: past INVOKE_LIMIT calls in INVOKE_WINDOW_SECONDS the
	  call is refused with "rate_limited" before the handler runs.
	- A handler that errors is logged and answered with "server_error"; it
	  never leaks the error text to the client.
	- After a request succeeds, the player's state is pushed down through
	  ProfileChanged, so the client never computes state of its own.

	Choice checks (which egg, which uid, which move) live in shared/net/Requests,
	and handlers call them first. A client never sends a number the server uses
	as an amount.

	A handler for a RemoteFunction returns true and a result table, or false and
	a reason. The client gets { ok = true, ... } or { ok = false, reason = ... }.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local Requests = require(Shared:WaitForChild("net"):WaitForChild("Requests"))
local Profile = require(Shared:WaitForChild("rules"):WaitForChild("Profile"))
local Profiles = require(script.Parent:WaitForChild("Profiles"))
local Followers = require(Shared:WaitForChild("visual"):WaitForChild("Followers"))

type Profile = Profile.Profile

export type EventHandler = (Player, Profile, ...any) -> ()
export type InvokeHandler = (Player, Profile, ...any) -> (boolean, any, any?)

local SERVER_ERROR = "server_error"
-- Request flood limits for RemoteFunctions: anti abuse timing, not game
-- numbers. Far above what a person clicking a button can send.
local INVOKE_LIMIT = 8
local INVOKE_WINDOW_SECONDS = 1

local Guard = {}

local instances: { [string]: Instance } = {}
local derivedFields: { [string]: (Player, Profile) -> any } = {}
local started = false
-- One limiter per RemoteFunction, keyed by player.
local invokeLimiters: { [string]: Requests.RateLimiter } = {}

local function deepCopy(value: any): any
	if type(value) ~= "table" then
		return value
	end
	local copy = {}
	for key, inner in value do
		copy[deepCopy(key)] = deepCopy(inner)
	end
	return copy
end

Guard.copy = deepCopy

local function remote(name: string): Instance
	local instance = instances[name]
	if instance == nil then
		error(string.format("Guard: remote %s does not exist; call Guard.start first", name), 2)
	end
	return instance
end

-- Logs a rejected request with the player and the reason.
function Guard.reject(player: Player, action: string, reason: string)
	warn(
		string.format(
			"[Remotes] %s (%d) %s rejected: %s",
			player.Name,
			player.UserId,
			action,
			reason
		)
	)
end

-- Adds a field the server computes for the client, sent with every push, such
-- as coins per click. The client shows it and never works it out itself.
function Guard.addDerived(field: string, compute: (Player, Profile) -> any)
	derivedFields[field] = compute
end

-- Sends the player's current state down through ProfileChanged, and keeps
-- the player's FollowerTeam attribute (shared/visual/Followers) in step.
function Guard.push(player: Player)
	local profile = Profiles.get(player)
	if profile == nil or player.Parent == nil then
		return
	end
	local derived = {}
	for field, compute in derivedFields do
		local ok, value = pcall(compute, player, profile)
		if ok then
			derived[field] = value
		else
			warn(string.format("[Remotes] derived field %s failed: %s", field, tostring(value)))
		end
	end
	local event = remote(Remotes.names.ProfileChanged) :: RemoteEvent
	event:FireClient(player, { profile = deepCopy(profile), derived = derived })
	-- The equipped team, for every client's pet followers. Roblox only
	-- replicates the attribute when the string changes.
	local team = Followers.encode(profile.pets, profile.team)
	if player:GetAttribute(Followers.ATTRIBUTE) ~= team then
		player:SetAttribute(Followers.ATTRIBUTE, team)
	end
end

-- Sends the player a short message through Notice, such as why a portal
-- refused them. The client only shows it.
function Guard.notify(player: Player, message: string)
	if player.Parent == nil then
		return
	end
	local event = remote(Remotes.names.Notice) :: RemoteEvent
	event:FireClient(player, message)
end

-- Fires a server to client RemoteEvent to one player, such as
-- ClickCredited with the coins one click earned. The client only shows it.
function Guard.fire(player: Player, name: string, ...: any)
	if player.Parent == nil then
		return
	end
	if Remotes.kindOf(name) ~= "event" then
		error(string.format("Guard: %s is not an event remote", name), 2)
	end
	local event = remote(name) :: RemoteEvent
	event:FireClient(player, ...)
end

local function expectKind(name: string, kind: Remotes.Kind)
	local actual = Remotes.kindOf(name)
	if actual ~= kind then
		error(string.format("Guard: %s is a %s remote, not %s", name, tostring(actual), kind), 3)
	end
end

-- Hooks a RemoteEvent the client fires. The handler gets the loaded profile.
function Guard.onEvent(name: string, handler: EventHandler)
	expectKind(name, "event")
	local event = remote(name) :: RemoteEvent
	event.OnServerEvent:Connect(function(player: Player, ...: any)
		local profile = Profiles.get(player)
		if profile == nil then
			Guard.reject(player, name, Requests.reasons.noProfile)
			return
		end
		local ok, err = pcall(handler, player, profile, ...)
		if not ok then
			warn(
				string.format(
					"[Remotes] %s (%d) %s failed: %s",
					player.Name,
					player.UserId,
					name,
					tostring(err)
				)
			)
		end
	end)
end

-- Hooks a RemoteFunction. The handler returns true and a result table, or
-- false, a reason string and optionally a table of extra fields for the
-- refusal (such as the seconds left on a wait).
function Guard.onInvoke(name: string, handler: InvokeHandler)
	expectKind(name, "function")
	local fn = remote(name) :: RemoteFunction
	local limiter = Requests.newRateLimiter(INVOKE_LIMIT, INVOKE_WINDOW_SECONDS)
	invokeLimiters[name] = limiter
	fn.OnServerInvoke = function(player: Player, ...: any): any
		local allowed, dropped = Requests.allow(limiter, player, os.clock())
		if not allowed then
			-- Log the first refusal of a window only, so a flood can not
			-- flood the log too.
			if dropped == 1 then
				Guard.reject(player, name, Requests.reasons.rateLimited)
			end
			return { ok = false, reason = Requests.reasons.rateLimited }
		end
		local profile = Profiles.get(player)
		if profile == nil then
			Guard.reject(player, name, Requests.reasons.noProfile)
			return { ok = false, reason = Requests.reasons.noProfile }
		end
		local called, ok, value, extra = pcall(handler, player, profile, ...)
		if not called then
			warn(
				string.format(
					"[Remotes] %s (%d) %s failed: %s",
					player.Name,
					player.UserId,
					name,
					tostring(ok)
				)
			)
			return { ok = false, reason = SERVER_ERROR }
		end
		if not ok then
			local reason = tostring(value)
			Guard.reject(player, name, reason)
			local refusal: { [string]: any } = {}
			if type(extra) == "table" then
				for field, inner in extra do
					refusal[field] = deepCopy(inner)
				end
			end
			refusal.ok = false
			refusal.reason = reason
			return refusal
		end
		Guard.push(player)
		local result: { [string]: any } = if type(value) == "table" then value else {}
		result.ok = true
		return result
	end
end

-- Creates every remote in one folder in ReplicatedStorage, and pushes each
-- player's state once their profile loads. Call once, before the services.
function Guard.start()
	if started then
		return
	end
	started = true
	local folder = Instance.new("Folder")
	folder.Name = Remotes.FOLDER
	for _, entry in Remotes.list do
		local instance: Instance = if entry.kind == "event"
			then Instance.new("RemoteEvent")
			else Instance.new("RemoteFunction")
		instance.Name = entry.name
		instance.Parent = folder
		instances[entry.name] = instance
	end
	folder.Parent = ReplicatedStorage

	Profiles.onLoaded(function(player: Player, _profile: Profile)
		Guard.push(player)
	end)

	Players.PlayerRemoving:Connect(function(player: Player)
		for _, limiter in invokeLimiters do
			Requests.forget(limiter, player)
		end
	end)
end

return Guard
