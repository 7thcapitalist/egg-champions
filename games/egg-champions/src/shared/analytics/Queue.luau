--!strict
--[[
	Queue: the batch of analytics records waiting to be sent.

	Records wait in order until the server flushes them, on an interval and
	when a player leaves. A full queue drops its oldest record, so a send that
	keeps failing can never grow memory without bound. Each send runs in its
	own pcall: a failed send is logged and dropped, never retried, because
	analytics must never get in the way of gameplay.

	Pure Luau: no Roblox service, so the test runner checks it headless.
]]

export type Queue<T> = {
	limit: number,
	items: { T },
	dropped: number,
}

local Queue = {}

-- An empty queue that holds at most limit items.
function Queue.new<T>(limit: number): Queue<T>
	assert(limit >= 1, "Queue: limit must be at least 1")
	return { limit = limit, items = {}, dropped = 0 }
end

-- Adds an item. Returns true when the queue was full and dropped its oldest.
function Queue.push<T>(queue: Queue<T>, item: T): boolean
	local full = #queue.items >= queue.limit
	if full then
		table.remove(queue.items, 1)
		queue.dropped += 1
	end
	table.insert(queue.items, item)
	return full
end

-- Takes every waiting item, oldest first, and leaves the queue empty.
function Queue.take<T>(queue: Queue<T>): { T }
	local items = queue.items
	queue.items = {}
	return items
end

-- Sends every waiting item once. A send that errors is passed to log and
-- dropped. Returns how many were sent and how many failed.
function Queue.flush<T>(queue: Queue<T>, send: (T) -> (), log: (T, string) -> ()): (number, number)
	local sent, failed = 0, 0
	for _, item in Queue.take(queue) do
		local ok, err = pcall(send, item)
		if ok then
			sent += 1
		else
			failed += 1
			pcall(log, item, tostring(err))
		end
	end
	return sent, failed
end

return Queue
