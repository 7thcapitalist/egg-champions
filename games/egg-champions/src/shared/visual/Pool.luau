--!strict
--[[
	Pool: reuse instead of create, with a hard cap, as plain data.

	The click pop and the coin burst fire up to 20 times a second. Creating a
	label or a part per click would grow the instance count forever, so each
	effect keeps a pool:
	- acquire hands out a free item, or creates one while under the cap;
	- at the cap with nothing free, it takes back the oldest live item, so a
	  burst of clicks recycles instead of queuing more than the cap;
	- release puts an item back once its animation ends.

	Queue is the companion for clicks waiting on the server's answer: it keeps
	at most `max` entries, drops the oldest past that, and forgets entries
	older than a given age.

	No engine globals, so the headless tests can feed it thousands of clicks.
]]

local Pool = {}

export type Pool<T> = {
	cap: number,
	create: () -> T,
	free: { T },
	live: { T },
	created: number,
}

export type Entry<T> = {
	value: T,
	at: number,
}

export type Queue<T> = {
	max: number,
	entries: { Entry<T> },
}

function Pool.new<T>(cap: number, create: () -> T): Pool<T>
	assert(cap >= 1, "a pool needs a cap of at least 1")
	return { cap = cap, create = create, free = {}, live = {}, created = 0 }
end

-- Returns an item and whether it was taken back from a live animation.
function Pool.acquire<T>(pool: Pool<T>): (T, boolean)
	local item: T
	local recycled = false
	if #pool.free > 0 then
		item = table.remove(pool.free) :: T
	elseif pool.created < pool.cap then
		item = pool.create()
		pool.created += 1
	else
		item = table.remove(pool.live, 1) :: T
		recycled = true
	end
	table.insert(pool.live, item)
	return item, recycled
end

-- Puts an item back. Releasing an item that is not live does nothing.
function Pool.release<T>(pool: Pool<T>, item: T)
	local index = table.find(pool.live, item)
	if index == nil then
		return
	end
	table.remove(pool.live, index)
	table.insert(pool.free, item)
end

function Pool.liveCount<T>(pool: Pool<T>): number
	return #pool.live
end

-- Every item the pool ever created, live or free.
function Pool.size<T>(pool: Pool<T>): number
	return pool.created
end

function Pool.newQueue<T>(max: number): Queue<T>
	assert(max >= 1, "a queue needs a max of at least 1")
	return { max = max, entries = {} }
end

function Pool.push<T>(queue: Queue<T>, value: T, now: number)
	table.insert(queue.entries, { value = value, at = now })
	while #queue.entries > queue.max do
		table.remove(queue.entries, 1)
	end
end

-- The oldest entry no older than maxAge, or nil. Older entries are dropped.
function Pool.take<T>(queue: Queue<T>, now: number, maxAge: number): T?
	while #queue.entries > 0 do
		local entry = table.remove(queue.entries, 1) :: Entry<T>
		if now - entry.at <= maxAge then
			return entry.value
		end
	end
	return nil
end

function Pool.queued<T>(queue: Queue<T>): number
	return #queue.entries
end

return Pool
