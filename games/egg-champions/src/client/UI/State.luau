--!strict
--[[
	State: the latest player state the server sent through ProfileChanged.

	The client never works out state of its own. It keeps the last payload,
	{ profile, derived }, and tells every screen when a new one arrives.
]]

export type Payload = {
	profile: { [string]: any },
	derived: { [string]: any },
}

local State = {}

local latest: Payload? = nil
local listeners: { (Payload) -> () } = {}

function State.get(): Payload?
	return latest
end

-- Calls listener with every new payload, and at once with the current one.
function State.subscribe(listener: (Payload) -> ())
	table.insert(listeners, listener)
	if latest ~= nil then
		task.spawn(listener, latest)
	end
end

-- Hooks the ProfileChanged remote. Call once.
function State.start(profileChanged: RemoteEvent)
	profileChanged.OnClientEvent:Connect(function(payload: any)
		if type(payload) ~= "table" or type(payload.profile) ~= "table" then
			return
		end
		local fresh: Payload = {
			profile = payload.profile,
			derived = if type(payload.derived) == "table" then payload.derived else {},
		}
		latest = fresh
		for _, listener in listeners do
			task.spawn(listener, fresh)
		end
	end)
end

return State
