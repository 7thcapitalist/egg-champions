--!strict
local Config = require(script.Parent.Parent.Config)

local Offline = {}

local function finite(value: any): boolean
	return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

function Offline.rate(activeRate: number, hasTeam: boolean): number
	if not hasTeam or not finite(activeRate) or activeRate <= 0 then
		return 0
	end
	local rate = activeRate * Config.constants.offline_rate_fraction
	return if finite(rate) then rate else 0
end

function Offline.reward(snapshot: any, now: number): (number, number)
	if
		type(snapshot) ~= "table"
		or not finite(now)
		or not finite(snapshot.at)
		or not finite(snapshot.rate)
		or snapshot.rate <= 0
		or snapshot.at < 0
		or snapshot.at > now
	then
		return 0, 0
	end
	local seconds = math.min(math.floor(now - snapshot.at), Config.constants.offline_max_seconds)
	local coins = math.floor(seconds * snapshot.rate)
	if not finite(coins) then
		return 0, 0
	end
	return coins, seconds
end

return Offline
