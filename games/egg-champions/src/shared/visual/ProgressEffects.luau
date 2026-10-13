--!strict
--[[
	ProgressEffects: what the three progression effects show, as plain data.

	client/Effects/Progress draws them. Everything here is worked out from
	what the server sent, never guessed:
	- Portals: ProgressEffects.portals reads a ProfileChanged profile and says,
	  for every portal in the world plan, whether it is open, locked, or the
	  last world's "coming soon" gate, with its label, its locked message and
	  its swirl color from shared/world/WorldPalette. ProgressEffects.changes
	  compares two of those; the first payload after joining has nothing to
	  compare with, so a rejoin shows the right portals with no swirl
	  replayed, and a rebirth relocks portals with no swirl either.
	- Gym win: ProgressEffects.gymWin says what the badge burst shows for a
	  win the server reported: the badge, then either the portal that opened
	  or, for the last gym, the "coming soon" gate, decided by
	  Progression.isFinalGymBeaten.
	- Rebirth: ProgressEffects.onRebirthReply plays the rebirth effect only
	  for a reply in which the server confirmed the rebirth. A refused or lost
	  request plays nothing, since a flash would claim coins were spent.

	No engine globals, so the headless tests run it.
]]

local Config = require(script.Parent.Parent.Config)
local Layout = require(script.Parent.Parent.world.Layout)
local WorldPalette = require(script.Parent.Parent.world.WorldPalette)
local Progression = require(script.Parent.Parent.rules.Progression)
local Format = require(script.Parent.Parent.ui.Format)

export type RGB = WorldPalette.RGB
export type PortalStatus = "open" | "locked" | "soon"

export type PortalView = {
	-- The world the portal stands in.
	worldId: string,
	-- The world it leads to, or nil for the last world's gate.
	toWorldId: string?,
	status: PortalStatus,
	label: string,
	-- What a player is told when the portal refuses them.
	message: string,
	-- The swirl color: the color of the world the portal opens.
	color: RGB,
}

export type Changes = {
	-- Portals that just opened, by the world they stand in, sorted.
	opened: { string },
	-- Portals that just locked again (a rebirth), sorted.
	closed: { string },
}

export type GymWin = {
	worldId: string,
	newBadge: boolean,
	-- The world the win opened, or nil after the last gym.
	nextWorldId: string?,
	-- The last gym's "coming soon" text, or nil.
	finalGate: string?,
	caption: string,
	-- The color of the world that opened, for the badge caption.
	color: RGB?,
}

local ProgressEffects = {}

local plan = Layout.plan()

local function flags(value: any): { [string]: boolean }
	local out: { [string]: boolean } = {}
	if type(value) == "table" then
		for key, flag in value do
			if type(key) == "string" and flag == true then
				out[key] = true
			end
		end
	end
	return out
end

-- The progress fields Progression reads, copied from a profile payload.
local function progressOf(profile: any): Progression.State
	local source = if type(profile) == "table" then profile else {}
	return {
		coins = 0,
		rebirths = 0,
		pets = {},
		team = {},
		index = {},
		badges = flags(source.badges),
		gymsBeaten = flags(source.gymsBeaten),
		feesPaid = flags(source.feesPaid),
	}
end

local function worldName(worldId: string): string
	for _, world in Config.worlds do
		if world.id == worldId then
			return world.name
		end
	end
	return worldId
end

local function portalFrom(worldId: string): Layout.Portal?
	for _, portal in plan.portals do
		if portal.worldId == worldId then
			return portal
		end
	end
	return nil
end

-- The label an open portal shows.
function ProgressEffects.openLabel(toWorldId: string): string
	return string.format("To %s\nOpen", worldName(toWorldId))
end

-- Every portal's state for a profile, keyed by the world it stands in.
function ProgressEffects.portals(profile: any): { [string]: PortalView }
	local state = progressOf(profile)
	local views: { [string]: PortalView } = {}
	for _, portal in plan.portals do
		local toIndex = portal.toIndex
		local toWorldId = portal.toWorldId
		local view: PortalView
		if toIndex == nil or toWorldId == nil then
			view = {
				worldId = portal.worldId,
				toWorldId = nil,
				status = if Progression.isFinalGymBeaten(state) then "soon" else "locked",
				label = portal.label,
				message = portal.lockedMessage,
				color = WorldPalette.unlockColor(portal.worldId),
			}
		else
			local open = Progression.worldUnlocked(state, toIndex)
			view = {
				worldId = portal.worldId,
				toWorldId = toWorldId,
				status = if open then "open" else "locked",
				label = if open then ProgressEffects.openLabel(toWorldId) else portal.label,
				message = portal.lockedMessage,
				color = WorldPalette.unlockColor(toWorldId),
			}
		end
		views[portal.worldId] = view
	end
	return views
end

-- What changed between two portal states. With no earlier state (the first
-- payload after joining) nothing changed, so no effect replays on rejoin.
function ProgressEffects.changes(
	before: { [string]: PortalView }?,
	after: { [string]: PortalView }
): Changes
	local changes: Changes = { opened = {}, closed = {} }
	if before == nil then
		return changes
	end
	for worldId, view in after do
		local old = before[worldId]
		local wasOpen = old ~= nil and old.status == "open"
		if view.status == "open" and not wasOpen then
			table.insert(changes.opened, worldId)
		elseif view.status ~= "open" and wasOpen then
			table.insert(changes.closed, worldId)
		end
	end
	table.sort(changes.opened)
	table.sort(changes.closed)
	return changes
end

-- What the badge burst shows for a gym win the server reported. `profile` is
-- the latest payload; the win itself is counted in even if the payload that
-- records it has not arrived yet.
function ProgressEffects.gymWin(worldId: string, profile: any, newBadge: boolean): GymWin
	local state = progressOf(profile)
	state.gymsBeaten[worldId] = true
	state.badges[worldId] = true
	local portal = portalFrom(worldId)
	local nextWorldId = if portal ~= nil then portal.toWorldId else nil
	if nextWorldId == nil and Progression.isFinalGymBeaten(state) then
		local gate = if portal ~= nil then portal.label else "Coming soon"
		return {
			worldId = worldId,
			newBadge = newBadge,
			nextWorldId = nil,
			finalGate = gate,
			caption = gate,
			color = nil,
		}
	end
	local caption = if nextWorldId ~= nil
		then string.format("%s is open", worldName(nextWorldId))
		else string.format("%s badge", worldName(worldId))
	return {
		worldId = worldId,
		newBadge = newBadge,
		nextWorldId = nextWorldId,
		finalGate = nil,
		caption = caption,
		color = if nextWorldId ~= nil then WorldPalette.unlockColor(nextWorldId) else nil,
	}
end

-- True when a Rebirth reply is the server confirming the rebirth.
function ProgressEffects.rebirthConfirmed(reply: any): boolean
	return type(reply) == "table" and reply.ok == true and type(reply.rebirths) == "number"
end

-- The one way the rebirth effect is started: `play` runs, with the new
-- rebirth count, only for a reply in which the server confirmed the rebirth.
-- Returns whether it played.
function ProgressEffects.onRebirthReply(reply: any, play: (rebirths: number) -> ()): boolean
	if not ProgressEffects.rebirthConfirmed(reply) then
		return false
	end
	play(reply.rebirths)
	return true
end

-- The rebirth prompt's text, from the cost the server derived.
function ProgressEffects.rebirthPromptText(cost: number): string
	return string.format(
		"Rebirth for %s coins. Your coins and gym wins reset, so worlds lock again. You keep your pets, your index and your badges.",
		Format.abbreviate(cost)
	)
end

local REBIRTH_REASONS: { [string]: string } = {
	cannot_afford = "You do not have enough coins to rebirth yet.",
	in_battle = "Finish your gym battle first.",
}

-- A readable message for a refused rebirth.
function ProgressEffects.rebirthReasonText(reason: any): string
	if type(reason) == "string" and REBIRTH_REASONS[reason] ~= nil then
		return REBIRTH_REASONS[reason]
	end
	return "The rebirth did not go through. Try again."
end

return ProgressEffects
