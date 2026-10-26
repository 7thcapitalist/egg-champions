--!strict
--[[
	Screens: how the menu opens a screen without knowing how it is built.

	Each screen module registers an opener under its name (Eggs, Pets, Index,
	Rebirth, Shop, Battle). The main screen only calls Screens.open with a name.
	Opening a name no screen has registered yet does nothing but log it, so the
	menu works before every screen exists.

	Each screen also hands its ScreenGui to track, so the main screen can ask
	anyOpen and hide its next-goal card while any menu screen is up.
]]

local Screens = {}

Screens.names = table.freeze({
	Eggs = "Eggs",
	Pets = "Pets",
	Index = "Index",
	Rebirth = "Rebirth",
	Shop = "Shop",
	Prisms = "Prisms",
	Battle = "Battle",
})

local openers: { [string]: () -> () } = {}

function Screens.register(name: string, open: () -> ())
	openers[name] = open
end

-- Opens a screen by name. Returns false when no screen has that name yet.
function Screens.open(name: string): boolean
	local open = openers[name]
	if open == nil then
		print(string.format("[UI] the %s screen is not built yet", name))
		return false
	end
	open()
	return true
end

local tracked: { ScreenGui } = {}
local changeListeners: { () -> () } = {}

local function changed()
	for _, listener in changeListeners do
		task.spawn(listener)
	end
end

-- Watches a screen's ScreenGui; it counts as open while it is Enabled.
function Screens.track(gui: ScreenGui)
	table.insert(tracked, gui)
	gui:GetPropertyChangedSignal("Enabled"):Connect(changed)
	changed()
end

-- True while any tracked screen is open.
function Screens.anyOpen(): boolean
	for _, gui in tracked do
		if gui.Enabled then
			return true
		end
	end
	return false
end

-- True while the tracked ScreenGui with this name is open.
function Screens.isShown(guiName: string): boolean
	for _, gui in tracked do
		if gui.Name == guiName and gui.Enabled then
			return true
		end
	end
	return false
end

-- Closes the tracked ScreenGui with this name, if it is open.
function Screens.close(guiName: string)
	for _, gui in tracked do
		if gui.Name == guiName then
			gui.Enabled = false
		end
	end
end

-- Calls listener whenever a tracked screen opens or closes.
function Screens.onChange(listener: () -> ())
	table.insert(changeListeners, listener)
end

return Screens
