--!strict
--[[
	Requests: the checks every remote request passes before a service acts.

	Pure Luau with no engine calls, so the server's validation helper
	(server/Services/Guard.luau) can lean on it and the headless tests can
	cover it. Every check returns true, or false and a reason string; the
	caller logs the reason with the player.

	Nothing a client sends is trusted as a number. A client sends choices
	only, and each choice is checked against a set the server built itself.
]]

local Requests = {}

-- The longest choice string accepted. Ids and uids are far shorter; this
-- only stops a client from sending megabytes into a lookup or a log line.
Requests.MAX_CHOICE_LENGTH = 64

-- The two moves a player can pick in a battle.
Requests.MOVE_BASIC = 1
Requests.MOVE_SPECIAL = 2
Requests.TEAM_CRITERION_COINS = "coins"
Requests.TEAM_CRITERION_BATTLE = "battle"

Requests.reasons = table.freeze({
	noProfile = "no_profile",
	badChoice = "bad_choice",
	unknownChoice = "unknown_choice",
	badMove = "bad_move",
	noSession = "no_session",
	notOwner = "not_session_owner",
	sessionEnded = "session_ended",
	onCooldown = "special_on_cooldown",
	rateLimited = "rate_limited",
})

-- A set of allowed choice strings, built from a list.
function Requests.setOf(values: { string }): { [string]: boolean }
	local set: { [string]: boolean } = {}
	for _, value in values do
		set[value] = true
	end
	return set
end

-- True when value is a short string. Says nothing about whether it exists.
function Requests.isChoiceString(value: any): boolean
	return type(value) == "string" and #value > 0 and #value <= Requests.MAX_CHOICE_LENGTH
end

-- Checks value is a choice string found in the allowed set.
function Requests.checkChoice(value: any, allowed: { [string]: boolean }): (boolean, string?)
	if not Requests.isChoiceString(value) then
		return false, Requests.reasons.badChoice
	end
	if allowed[value] ~= true then
		return false, Requests.reasons.unknownChoice
	end
	return true, nil
end

-- Equip Best accepts no argument (coins by default), coins, or battle.
-- Client-provided pet ids, rankings and stat tables are refused.
function Requests.checkTeamCriterion(value: any): (boolean, string?)
	if
		value == nil
		or value == Requests.TEAM_CRITERION_COINS
		or value == Requests.TEAM_CRITERION_BATTLE
	then
		return true, nil
	end
	if not Requests.isChoiceString(value) then
		return false, Requests.reasons.badChoice
	end
	return false, Requests.reasons.unknownChoice
end

-- The parts of a server battle session the move check reads.
export type SessionView = {
	ownerId: number,
	ended: boolean,
	specialReady: boolean,
}

-- Checks a battle session exists, belongs to this user, and is still running.
function Requests.checkSession(session: SessionView?, userId: number): (boolean, string?)
	if session == nil then
		return false, Requests.reasons.noSession
	end
	if session.ownerId ~= userId then
		return false, Requests.reasons.notOwner
	end
	if session.ended then
		return false, Requests.reasons.sessionEnded
	end
	return true, nil
end

-- Checks a battle move: the session passes checkSession, the move is exactly
-- 1 or 2, and a move 2 is off cooldown.
function Requests.checkMove(session: SessionView?, userId: number, move: any): (boolean, string?)
	local ok, reason = Requests.checkSession(session, userId)
	if not ok or session == nil then
		return false, reason
	end
	if move ~= Requests.MOVE_BASIC and move ~= Requests.MOVE_SPECIAL then
		return false, Requests.reasons.badMove
	end
	if move == Requests.MOVE_SPECIAL and not session.specialReady then
		return false, Requests.reasons.onCooldown
	end
	return true, nil
end

-- A per key limiter: at most `limit` events in each `window` seconds. The
-- caller passes the clock, so tests need no engine time.
export type RateLimiter = {
	limit: number,
	window: number,
	buckets: { [any]: { start: number, count: number } },
}

function Requests.newRateLimiter(limit: number, window: number): RateLimiter
	if limit < 1 or window <= 0 then
		error("Requests.newRateLimiter: limit must be at least 1 and window above 0")
	end
	return { limit = limit, window = window, buckets = {} }
end

-- Counts one event for key at time now. Returns true when it is allowed, or
-- false and how many events this window has dropped so far.
function Requests.allow(limiter: RateLimiter, key: any, now: number): (boolean, number)
	local bucket = limiter.buckets[key]
	if bucket == nil or now - bucket.start >= limiter.window or now < bucket.start then
		bucket = { start = now, count = 0 }
		limiter.buckets[key] = bucket
	end
	bucket.count += 1
	if bucket.count > limiter.limit then
		return false, bucket.count - limiter.limit
	end
	return true, 0
end

-- Forgets a key, for a player who left.
function Requests.forget(limiter: RateLimiter, key: any)
	limiter.buckets[key] = nil
end

return Requests
