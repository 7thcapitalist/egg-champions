--!strict
--[[
	Events: the one list of analytics events the server may fire, and how a
	fired event becomes a record.

	Every event is a row in Events.list with its fields and what it measures.
	Building a record for a name that is not in the list is an error, and so is
	a missing, extra or wrongly typed field, so names and fields cannot drift
	between the code, the notes (notes/analytics-events.md) and the tuner.

	Each row says:
		name: the event name sent to Roblox
		fields: { name = kind }, kind "number", "string" or "list"
		kind: "custom" (AnalyticsService custom event) or "economy"
		value: the number field sent as the custom event value, if any
		dimensions: up to two slots, sent as custom fields 02 and 03. A slot
			is a list of fields; a slot with several fields is sent as their
			values joined by ", " ("2, win"), and a list field as its items
			joined by "," ("pet_a,pet_b"). Roblox allows three custom fields
			per event and field 01 is the stage, so this is how a field that
			matters still reaches Roblox.
		economy: for an economy event, which fields hold the amount, the
			balance after and the item, and the flow ("Sink" or "Source")
		onboardingStep: also logged as this onboarding funnel step
		measures: tuner targets in tuning/report.md this event measures, with
			every number written as N ("Gym N beaten")
		constants: the config pacing constants this event measures

	Every field of every event is sent (as the value, in a dimension slot, or
	as an economy amount, balance or item); Events.sentFields lists them, and
	a test checks that list against the event's fields and the notes table.

	Play time: totalPlaySeconds is the player's play time over every session
	(saved in the profile), and secondsSinceJoin the time in this session.

	Every record also carries the player's stage: the rebirth count and the
	current world, which is the highest world open in the current run. That
	goes in custom field 01, since almost every question starts with "at what
	stage". No personal data beyond the Roblox user id is ever recorded.

	Pure Luau: no Roblox service, so the test runner checks it headless.
]]

local Progression = require(script.Parent.Parent.rules.Progression)
local Config = require(script.Parent.Parent.Config)

export type FieldKind = "number" | "string" | "list"

export type Economy = {
	flow: "Sink" | "Source",
	amount: string,
	balance: string,
	item: string,
	transaction: string,
}

export type Event = {
	name: string,
	fields: { [string]: FieldKind },
	kind: "custom" | "economy",
	value: string?,
	dimensions: { { string } },
	economy: Economy?,
	onboardingStep: number?,
	measures: { string },
	constants: { string },
}

export type Context = {
	rebirths: number,
	world: number,
}

export type Record = {
	name: string,
	fields: { [string]: any },
	rebirths: number,
	world: number,
}

local Events = {}

local list: { Event } = {
	{
		name = "session_start",
		fields = { coinsPerClick = "number" },
		kind = "custom",
		value = "coinsPerClick",
		dimensions = {},
		measures = {},
		constants = {},
	},
	{
		name = "session_end",
		fields = { lengthSeconds = "number", coinsPerClick = "number" },
		kind = "custom",
		value = "lengthSeconds",
		dimensions = { { "coinsPerClick" } },
		measures = {},
		constants = {},
	},
	{
		name = "first_hatch",
		fields = { totalPlaySeconds = "number", secondsSinceJoin = "number" },
		kind = "custom",
		value = "totalPlaySeconds",
		dimensions = { { "secondsSinceJoin" } },
		onboardingStep = 1,
		measures = { "First hatch" },
		constants = { "pacing_first_hatch_minutes" },
	},
	{
		name = "egg_bought",
		fields = { eggId = "string", count = "number", price = "number", coinsAfter = "number" },
		kind = "economy",
		dimensions = { { "eggId" }, { "count" } },
		economy = {
			flow = "Sink",
			amount = "price",
			balance = "coinsAfter",
			item = "eggId",
			transaction = "Shop",
		},
		measures = {},
		constants = {},
	},
	{
		name = "pet_hatched",
		fields = { petId = "string", rarity = "string", variant = "string" },
		kind = "custom",
		dimensions = { { "petId" }, { "rarity", "variant" } },
		measures = {},
		constants = {},
	},
	{
		name = "pet_equipped",
		fields = { petId = "string", team = "list" },
		kind = "custom",
		dimensions = { { "petId" }, { "team" } },
		measures = {},
		constants = {},
	},
	{
		name = "gym_attempt",
		fields = {
			worldIndex = "number",
			totalPlaySeconds = "number",
			secondsSinceJoin = "number",
		},
		kind = "custom",
		value = "totalPlaySeconds",
		dimensions = { { "worldIndex" }, { "secondsSinceJoin" } },
		measures = {},
		constants = {},
	},
	{
		name = "gym_result",
		fields = {
			worldIndex = "number",
			outcome = "string",
			totalPlaySeconds = "number",
			secondsSinceJoin = "number",
		},
		kind = "custom",
		value = "totalPlaySeconds",
		dimensions = { { "worldIndex", "outcome" }, { "secondsSinceJoin" } },
		measures = { "Gym N beaten", "Final gym beaten", "Rebirths at gym N" },
		constants = {
			"pacing_gym1_minutes_min",
			"pacing_gym1_minutes_max",
			"pacing_final_gym_hours_min",
			"pacing_final_gym_hours_max",
		},
	},
	{
		name = "rebirth",
		fields = { count = "number", totalPlaySeconds = "number", secondsSinceJoin = "number" },
		kind = "custom",
		value = "totalPlaySeconds",
		dimensions = { { "count" }, { "secondsSinceJoin" } },
		measures = {},
		constants = {},
	},
	{
		name = "world_unlocked",
		fields = {
			worldIndex = "number",
			totalPlaySeconds = "number",
			secondsSinceJoin = "number",
		},
		kind = "custom",
		value = "totalPlaySeconds",
		dimensions = { { "worldIndex" }, { "secondsSinceJoin" } },
		measures = {},
		constants = {},
	},
	{
		name = "pass_purchased",
		fields = { passId = "string" },
		kind = "custom",
		dimensions = { { "passId" } },
		measures = {},
		constants = {},
	},
}

local byName: { [string]: Event } = {}
for _, event in list do
	byName[event.name] = event
end

Events.list = list
Events.byName = byName

-- The gym outcomes gym_result may carry.
Events.outcomes = table.freeze({ win = "win", loss = "loss", gaveUp = "gave_up" })

-- The variant name pet_hatched sends for a pet with no variant.
Events.NORMAL_VARIANT = "normal"

-- The event row for a name. Errors for a name that is not in the list.
function Events.get(name: string): Event
	local event = byName[name]
	if event == nil then
		error(
			string.format(
				"Analytics: unknown event '%s'; add it to Events.list first",
				tostring(name)
			),
			2
		)
	end
	return event
end

local function kindOf(value: any): FieldKind?
	local t = type(value)
	if t == "number" then
		return if value == value
				and value ~= math.huge
				and value ~= -math.huge
			then "number"
			else nil
	elseif t == "string" then
		return "string"
	elseif t == "table" then
		return "list"
	end
	return nil
end

-- The player's stage: rebirth count, and the highest world open in this run.
function Events.context(state: Progression.State): Context
	local world = 0
	for _, entry in Config.worlds do
		if entry.index > world and Progression.worldUnlocked(state, entry.index) then
			world = entry.index
		end
	end
	return { rebirths = state.rebirths, world = world }
end

-- A record for one event. Errors for an unknown name, or a field that is
-- missing, not in the row, or of the wrong kind.
function Events.build(name: string, fields: { [string]: any }, context: Context): Record
	local event = byName[name]
	if event == nil then
		error(
			string.format(
				"Analytics: unknown event '%s'; add it to Events.list first",
				tostring(name)
			),
			2
		)
	end
	local copy: { [string]: any } = {}
	for field, kind in event.fields do
		local value = fields[field]
		if value == nil then
			error(string.format("Analytics: event '%s' is missing field '%s'", name, field), 2)
		end
		if kindOf(value) ~= kind then
			error(
				string.format("Analytics: event '%s' field '%s' must be a %s", name, field, kind),
				2
			)
		end
		copy[field] = if kind == "list" then table.clone(value) else value
	end
	for field in fields do
		if event.fields[field] == nil then
			error(
				string.format("Analytics: event '%s' has no field '%s'", name, tostring(field)),
				2
			)
		end
	end
	return { name = name, fields = copy, rebirths = context.rebirths, world = context.world }
end

-- The stage string sent in custom field 01.
function Events.stage(record: Record): string
	return string.format("rebirths %d, world %d", record.rebirths, record.world)
end

local function fieldText(value: any): string
	if type(value) == "table" then
		local parts = {}
		for _, item in value do
			table.insert(parts, tostring(item))
		end
		return table.concat(parts, ",")
	end
	return tostring(value)
end

-- The custom fields sent with a record: 01 the stage, 02 and 03 the event's
-- dimension slots. Keys are the AnalyticsCustomFieldKeys names.
function Events.customFields(record: Record): { [string]: string }
	local event = Events.get(record.name)
	local custom: { [string]: string } = { CustomField01 = Events.stage(record) }
	local keys = { "CustomField02", "CustomField03" }
	for i, slot in event.dimensions do
		if keys[i] ~= nil then
			local parts = {}
			for _, field in slot do
				table.insert(parts, fieldText(record.fields[field]))
			end
			custom[keys[i]] = table.concat(parts, ", ")
		end
	end
	return custom
end

-- Every field of an event that reaches Roblox: the value, the fields in the
-- first two dimension slots, and an economy event's amount, balance and item.
-- Sorted, each once.
function Events.sentFields(event: Event): { string }
	local seen: { [string]: boolean } = {}
	if event.value ~= nil then
		seen[event.value] = true
	end
	for i, slot in event.dimensions do
		if i <= 2 then
			for _, field in slot do
				seen[field] = true
			end
		end
	end
	local economy = event.economy
	if economy ~= nil then
		seen[economy.amount] = true
		seen[economy.balance] = true
		seen[economy.item] = true
	end
	local names = {}
	for field in seen do
		table.insert(names, field)
	end
	table.sort(names)
	return names
end

-- The number sent as a custom event's value, or nil when the event has none.
function Events.value(record: Record): number?
	local event = Events.get(record.name)
	if event.value == nil then
		return nil
	end
	return record.fields[event.value]
end

-- A tuner target label with every number replaced by N, as rows name them.
function Events.targetLabel(label: string): string
	local trimmed = string.match(label, "^%s*(.-)%s*$") or label
	return (string.gsub(trimmed, "%d+", "N"))
end

-- True when some event measures this tuner target label.
function Events.measures(label: string): boolean
	local wanted = Events.targetLabel(label)
	for _, event in list do
		for _, measured in event.measures do
			if measured == wanted then
				return true
			end
		end
	end
	return false
end

return Events
