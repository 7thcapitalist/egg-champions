--!strict
--[[
	Screens: how the menu opens a screen without knowing how it is built.

	Each screen module registers an opener under its name (Eggs, Pets, Index,
	Rebirth, Shop, Battle). The main screen only calls Screens.open with a name.
	Opening a name no screen has registered yet does nothing but log it, so the
	menu works before every screen exists.
]]

local Screens = {}

Screens.names = table.freeze({
	Eggs = "Eggs",
	Pets = "Pets",
	Index = "Index",
	Rebirth = "Rebirth",
	Shop = "Shop",
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

return Screens
