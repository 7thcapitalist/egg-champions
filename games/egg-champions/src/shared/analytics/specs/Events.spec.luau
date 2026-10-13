--!strict
local Runner = require(script.Parent.Parent.Parent.testing.Runner)
local Config = require(script.Parent.Parent.Parent.Config)
local Progression = require(script.Parent.Parent.Parent.rules.Progression)
local Events = require(script.Parent.Parent.Events)
local Queue = require(script.Parent.Parent.Queue)

local describe = Runner.describe
local it = Runner.it
local expect = Runner.expect

local CONTEXT: Events.Context = { rebirths = 2, world = 3 }

-- A Markdown document the test runner mounts at ReplicatedStorage.Docs.
local function doc(folder: string, name: string): string
	local storage = script.Parent.Parent.Parent.Parent
	local docs = storage:FindFirstChild("Docs")
	assert(
		docs ~= nil,
		"no Docs in the test tree; run the specs through factory/tools/run_tests.py"
	)
	local dir = docs:FindFirstChild(folder)
	local node = if dir ~= nil then dir:FindFirstChild(name) else nil
	assert(node ~= nil, string.format("%s/%s.md is missing", folder, name))
	return (require :: any)(node)
end

local function lines(text: string): { string }
	local out = {}
	for line in string.gmatch(text .. "\n", "([^\n]*)\n") do
		table.insert(out, line)
	end
	return out
end

-- The first column of the first table under "Current numbers against the targets".
local function reportTargets(report: string): { string }
	local targets = {}
	local inside = false
	local rows = 0
	for _, line in lines(report) do
		if string.match(line, "^##%s") then
			if inside then
				break
			end
			inside = string.find(line, "Current numbers against the targets", 1, true) ~= nil
		elseif inside and rows > 0 and not string.match(line, "^|") then
			-- The first table under the heading has ended.
			break
		elseif inside and string.match(line, "^|") then
			rows += 1
			local first = string.match(line, "^|%s*([^|]-)%s*|")
			-- Row 1 is the header, row 2 the separator.
			if rows > 2 and first ~= nil and first ~= "" then
				table.insert(targets, first)
			end
		end
	end
	return targets
end

-- The notes row for an event: the table line whose first cell is `name`.
local function notesRow(notes: string, name: string): string?
	for _, line in lines(notes) do
		local first = string.match(line, "^|%s*`([^`]+)`%s*|")
		if first == name then
			return line
		end
	end
	return nil
end

local function sortedFields(event: Events.Event): { string }
	local names = {}
	for field in event.fields do
		table.insert(names, field)
	end
	table.sort(names)
	return names
end

-- Sample fields of the right kind for an event.
local function sample(event: Events.Event): { [string]: any }
	local fields: { [string]: any } = {}
	for field, kind in event.fields do
		fields[field] = if kind == "number" then 1 elseif kind == "string" then "x" else { "a" }
	end
	return fields
end

return function()
	describe("Analytics events", function()
		it("errors when firing an event that is not in the table", function()
			expect(function()
				Events.build("not_an_event", {}, CONTEXT)
			end).toThrow("unknown event 'not_an_event'")
			expect(function()
				Events.get("first_hatchh")
			end).toThrow("unknown event")
		end)

		it("errors on a missing, extra or wrongly typed field", function()
			expect(function()
				Events.build("first_hatch", {}, CONTEXT)
			end).toThrow("missing field 'secondsSinceJoin'")
			expect(function()
				Events.build("first_hatch", { secondsSinceJoin = 5, name = "someone" }, CONTEXT)
			end).toThrow("has no field 'name'")
			expect(function()
				Events.build("first_hatch", { secondsSinceJoin = "5" }, CONTEXT)
			end).toThrow("must be a number")
			expect(function()
				Events.build("first_hatch", { secondsSinceJoin = 0 / 0 }, CONTEXT)
			end).toThrow("must be a number")
		end)

		it("builds a record for every event, carrying rebirths and world", function()
			for _, event in Events.list do
				local record = Events.build(event.name, sample(event), CONTEXT)
				expect(record.name).toEqual(event.name)
				expect(record.rebirths).toEqual(2)
				expect(record.world).toEqual(3)
				expect(Events.customFields(record).CustomField01).toEqual("rebirths 2, world 3")
			end
		end)

		it("has unique names and well formed rows", function()
			local seen = {}
			for _, event in Events.list do
				expect(seen[event.name] == nil).toBeTrue()
				seen[event.name] = true
				expect(string.match(event.name, "^[a-z_]+$") ~= nil).toBeTrue()
				expect(#event.dimensions <= 2).toBeTrue()
				for _, field in event.dimensions do
					expect(event.fields[field] ~= nil).toBeTrue()
				end
				if event.value ~= nil then
					expect(event.fields[event.value]).toEqual("number")
				end
				local economy = event.economy
				expect(economy ~= nil).toEqual(event.kind == "economy")
				if economy ~= nil then
					expect(event.fields[economy.amount]).toEqual("number")
					expect(event.fields[economy.balance]).toEqual("number")
					expect(event.fields[economy.item]).toEqual("string")
				end
			end
		end)

		it("has every event the brief lists", function()
			for _, name in
				{
					"first_hatch",
					"gym_attempt",
					"gym_result",
					"egg_bought",
					"pet_hatched",
					"pet_equipped",
					"rebirth",
					"world_unlocked",
					"pass_purchased",
					"session_start",
					"session_end",
				}
			do
				expect(Events.byName[name] ~= nil).toBeTrue()
			end
		end)

		it("sends dimensions as custom fields and the value field as the value", function()
			local record = Events.build(
				"gym_result",
				{ worldIndex = 2, outcome = Events.outcomes.win, secondsSinceJoin = 90 },
				CONTEXT
			)
			expect(Events.customFields(record)).toEqual({
				CustomField01 = "rebirths 2, world 3",
				CustomField02 = "2",
				CustomField03 = "win",
			})
			expect(Events.value(record)).toEqual(90)
			local hatched = Events.build(
				"pet_hatched",
				{ petId = "p", rarity = "rare", variant = Events.NORMAL_VARIANT },
				CONTEXT
			)
			expect(Events.value(hatched)).toEqual(nil)
		end)

		it("copies list fields, so a later team change does not alter a record", function()
			local team = { "a", "b" }
			local record = Events.build("pet_equipped", { petId = "a", team = team }, CONTEXT)
			table.insert(team, "c")
			expect(record.fields.team).toEqual({ "a", "b" })
		end)

		it("puts a new player in the first world and moves the world on with gym wins", function()
			local state = Progression.newState()
			local first = math.huge
			for _, world in Config.worlds do
				first = math.min(first, world.index)
			end
			expect(Events.context(state)).toEqual({ rebirths = 0, world = first })
			Progression.beatGym(state, first)
			if Config.worldByIndex[first + 1] ~= nil then
				expect(Events.context(state).world).toEqual(first + 1)
			end
		end)

		it("covers every tuner target named in tuning/report.md", function()
			local targets = reportTargets(doc("tuning", "report"))
			expect(#targets > 0).toBeTrue()
			for _, target in targets do
				if not Events.measures(target) then
					error(
						string.format("no analytics event measures the tuner target '%s'", target)
					)
				end
			end
		end)

		it("covers every pacing constant in config", function()
			local measured = {}
			for _, event in Events.list do
				for _, constant in event.constants do
					expect(Config.constants[constant] ~= nil).toBeTrue()
					measured[constant] = true
				end
			end
			local count = 0
			for key in Config.constants :: any do
				if string.sub(key, 1, 7) == "pacing_" then
					count += 1
					if not measured[key] then
						error(string.format("no analytics event measures the constant '%s'", key))
					end
				end
			end
			expect(count > 0).toBeTrue()
		end)

		it("has a row in notes/analytics-events.md for every event, naming each field", function()
			local notes = doc("notes", "analytics-events")
			for _, event in Events.list do
				local row = notesRow(notes, event.name)
				if row == nil then
					error(
						string.format("notes/analytics-events.md has no row for '%s'", event.name)
					)
				end
				for _, field in sortedFields(event) do
					if string.find(row, "`" .. field .. "`", 1, true) == nil then
						error(
							string.format(
								"the notes row for '%s' does not name field '%s'",
								event.name,
								field
							)
						)
					end
				end
			end
		end)

		it("documents no event that is not in the table", function()
			local notes = doc("notes", "analytics-events")
			for _, line in lines(notes) do
				local first = string.match(line, "^|%s*`([^`]+)`%s*|")
				if first ~= nil and Events.byName[first] == nil then
					error(
						string.format(
							"notes/analytics-events.md documents unknown event '%s'",
							first
						)
					)
				end
			end
		end)
	end)

	describe("Analytics queue", function()
		it("sends in order and empties the queue", function()
			local queue = Queue.new(10)
			Queue.push(queue, "a")
			Queue.push(queue, "b")
			local sent = {}
			local ok, failed = Queue.flush(queue, function(item: string)
				table.insert(sent, item)
			end, function() end)
			expect(sent).toEqual({ "a", "b" })
			expect(ok).toEqual(2)
			expect(failed).toEqual(0)
			expect(#queue.items).toEqual(0)
		end)

		it("drops a failed send with a log and keeps sending the rest", function()
			local queue = Queue.new(10)
			Queue.push(queue, "a")
			Queue.push(queue, "bad")
			Queue.push(queue, "c")
			local sent, logged = {}, {}
			local ok, failed = Queue.flush(queue, function(item: string)
				if item == "bad" then
					error("network down")
				end
				table.insert(sent, item)
			end, function(item: string, err: string)
				table.insert(logged, item)
				expect(string.find(err, "network down", 1, true) ~= nil).toBeTrue()
			end)
			expect(sent).toEqual({ "a", "c" })
			expect(logged).toEqual({ "bad" })
			expect(ok).toEqual(2)
			expect(failed).toEqual(1)
			-- Not retried: the next flush sends nothing.
			local again = Queue.flush(queue, function() end, function() end)
			expect(again).toEqual(0)
		end)

		it("drops the oldest item when full", function()
			local queue = Queue.new(2)
			expect(Queue.push(queue, 1)).toBeFalse()
			expect(Queue.push(queue, 2)).toBeFalse()
			expect(Queue.push(queue, 3)).toBeTrue()
			expect(queue.items).toEqual({ 2, 3 })
			expect(queue.dropped).toEqual(1)
		end)

		it("survives a log function that errors", function()
			local queue = Queue.new(2)
			Queue.push(queue, 1)
			local _, failed = Queue.flush(queue, function()
				error("send failed")
			end, function()
				error("log failed")
			end)
			expect(failed).toEqual(1)
		end)
	end)
end
