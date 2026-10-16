--!strict
-- Orders autosaves and the final save for one loaded player session.
-- A release closes the session immediately, then waits for any active save.
local SaveOrder = {}

export type State = { busy: boolean, closing: boolean }
export type Decision = "run" | "wait" | "skip"

function SaveOrder.new(): State
	return { busy = false, closing = false }
end

function SaveOrder.begin(state: State, release: boolean): Decision
	if release then
		state.closing = true
	elseif state.closing then
		return "skip"
	end
	if state.busy then
		return "wait"
	end
	state.busy = true
	return "run"
end

function SaveOrder.finish(state: State)
	state.busy = false
end

function SaveOrder.ownsSession(recordJobId: string?, currentJobId: string): boolean
	return recordJobId ~= nil and recordJobId == currentJobId
end

return SaveOrder
