--!strict
--[[
	Guide: the tutorial inside screens. It joins the step the server sent
	(Main hands it over with setStep), which screens are open (Screens), and
	whether an owned pet is selected on the pets screen (Pets hands it over
	with setPetSelected), asks shared/rules/Tutorial for the card, and then:

	- points UI/Pointer at the card's target, a button the player can see;
	- hands the card's in-screen line to every screen that listens (onText),
	  so the open screen shows it as a one-line bar in its header;
	- closes the egg shop after the hatch step ends, so the pointer never
	  targets a button hidden behind it, but only once the hatch animation
	  and the reveal card are over (EggShop reports them with setHatching;
	  shared/ui/HatchReveal.shopCloses decides).

	While Main says a small goal comes before the gym (setHoldGym), the gym
	step shows nothing here: no pointer, no bar.

	When no tutorial target is showing, Main can ask for the beam and edge
	arrow to a gym (setGymBeam): after the player taps the goal card's "Next"
	line, or once the team is full. Like the gym step, it only shows while no
	screen covers the world.

	The client decides nothing here: the step only ever comes from the server.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Tutorial = require(Shared:WaitForChild("rules"):WaitForChild("Tutorial"))
local HatchReveal = require(Shared:WaitForChild("ui"):WaitForChild("HatchReveal"))

local Pointer = require(script.Parent:WaitForChild("Pointer"))
local Theme = require(script.Parent:WaitForChild("Theme"))
local Screens = require(script.Parent:WaitForChild("Screens"))

-- The ScreenGui names of the screens the tutorial looks into.
local EGG_SHOP_GUI = "EggShop"
local PETS_GUI = "Pets"

local Guide = {}

local step: any = nil
local holdGym = false
-- A hatch animation or reveal is playing, and a shop close is waiting on it.
local hatching = false
local closePending = false
-- The world whose gym the beam points at outside the tutorial, or nil.
local beamWorld: string? = nil
local petSelected = false
local text: string? = nil
local listeners: { (string?) -> () } = {}

-- Works the card out again and updates the pointer and every bar.
function Guide.refresh()
	local card = Tutorial.card(step, {
		eggsOpen = Screens.isShown(EGG_SHOP_GUI),
		petsOpen = Screens.isShown(PETS_GUI),
		petSelected = petSelected,
	})
	if card ~= nil and card.step == Tutorial.steps.gym and holdGym then
		card = nil
	end
	local target = if card ~= nil then card.target else nil
	-- The gym pointer (highlight, beam, edge arrow) is for the world view:
	-- none of it shows while a screen covers the world.
	if card ~= nil and card.step == Tutorial.steps.gym and Screens.anyOpen() then
		target = nil
	end
	local beam = beamWorld
	if target == nil and beam ~= nil and not Screens.anyOpen() then
		target = "gym:" .. beam
	end
	Pointer.set(target)
	local line = if card ~= nil then card.screenText else nil
	if line ~= text then
		text = line
		for _, listener in listeners do
			task.spawn(listener, line)
		end
	end
end

-- The in-screen line now, or nil for none.
function Guide.text(): string?
	return text
end

-- Calls listener with the new in-screen line (or nil) whenever it changes.
function Guide.onText(listener: (string?) -> ())
	table.insert(listeners, listener)
end

-- Builds the one-line bar a screen shows in its header, filled from
-- onText and hidden while there is no line. The caller places and sizes it.
-- onShown, when given, hears whether the bar shows after every change.
function Guide.bar(parent: Instance, onShown: ((boolean) -> ())?): Frame
	local bar = Instance.new("Frame")
	bar.Name = "TutorialBar"
	bar.BorderSizePixel = 0
	bar.BackgroundColor3 = Theme.colors.raised
	Theme.panel(bar, Theme.sizes.radius, Theme.colors.gold)
	local line = Theme.text({
		name = "Line",
		font = Theme.fonts.label,
		size = Theme.textSizes.small + 2,
		color = Theme.colors.gold,
		parent = bar,
	})
	line.AutomaticSize = Enum.AutomaticSize.None
	line.Size = UDim2.new(1, -16, 1, 0)
	line.Position = UDim2.fromOffset(8, 0)
	line.TextTruncate = Enum.TextTruncate.AtEnd
	line.TextXAlignment = Enum.TextXAlignment.Center
	line.TextYAlignment = Enum.TextYAlignment.Center
	local function show(value: string?)
		line.Text = value or ""
		bar.Visible = value ~= nil
		if onShown ~= nil then
			onShown(value ~= nil)
		end
	end
	show(Guide.text())
	Guide.onText(show)
	bar.Parent = parent
	return bar
end

-- Closes the egg shop when the tutorial asked for it and no hatch plays.
local function closeShopIfDone()
	if HatchReveal.shopCloses(closePending, hatching, step == Tutorial.steps.hatch) then
		closePending = false
		if Screens.isShown(EGG_SHOP_GUI) then
			Screens.close(EGG_SHOP_GUI)
		end
	end
end

-- The tutorial step the server sent.
function Guide.setStep(newStep: any)
	local before = step
	step = newStep
	if Tutorial.closesEggShop(before, newStep) and Screens.isShown(EGG_SHOP_GUI) then
		closePending = true
	end
	closeShopIfDone()
	Guide.refresh()
end

-- Whether a hatch animation or its reveal is playing in the egg shop.
function Guide.setHatching(playing: boolean)
	hatching = playing
	closeShopIfDone()
end

-- The world whose gym gets the beam and edge arrow, or nil for none.
function Guide.setGymBeam(worldId: string?)
	if worldId ~= beamWorld then
		beamWorld = worldId
		Guide.refresh()
	end
end

-- Whether a small goal comes before the gym, so the gym step waits.
function Guide.setHoldGym(hold: boolean)
	if hold ~= holdGym then
		holdGym = hold
		Guide.refresh()
	end
end

-- Whether an owned pet is selected on the pets screen.
function Guide.setPetSelected(selected: boolean)
	if selected ~= petSelected then
		petSelected = selected
		Guide.refresh()
	end
end

Screens.onChange(Guide.refresh)

return Guide
