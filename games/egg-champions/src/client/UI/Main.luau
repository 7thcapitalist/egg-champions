--!strict
--[[
	Main: the screen the player sees most, in the approved style of
	design/ui/Main.dc.html (dark flat panels, thin borders, gold accent), but
	showing as little as possible at once.

	Every rectangle comes from shared/ui/HudLayout, which the specs check for
	overlaps at 1280 x 720, 1920 x 1080 and a 844 x 390 phone. The layout is
	redone whenever the screen size or the number of team slots changes.

	- Top bar: coins and coins per click on the left, the world name centred
	  on its own, the rebirth count small on the right. Game passes are not
	  here; they live only in the Shop screen (UI/Shop).
	- Left menu: four compact buttons, Eggs, Pets, Rebirth and Shop. The
	  Index is a tab inside the Pets screen.
	- Next-goal card on the right, picked by shared/ui/NextGoal: one line and
	  one button. Hidden while any menu screen is open (Screens.anyOpen).
	- Team bar at the bottom: hidden until the player owns a pet, then one
	  slot per owned pet up to constants.team_size (HudLayout.teamSlots).

	Clicking: there is no click button. A full screen transparent button sits
	behind every panel and fires Click on press. Panels are Active so they
	swallow their own presses, and a press over any panel is also ignored by
	position, so pressing a menu button never earns a coin.

	Every number shown comes from the server through ProfileChanged (see
	State). Coins per click and each pet's click power are derived fields the
	server sends; this module only formats them.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GuiService = game:GetService("GuiService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local PetVisual = require(Shared:WaitForChild("PetVisual"))
local uiShared = Shared:WaitForChild("ui")
local Format = require(uiShared:WaitForChild("Format"))
local NextGoal = require(uiShared:WaitForChild("NextGoal"))
local HudLayout = require(uiShared:WaitForChild("HudLayout"))

local Theme = require(script.Parent:WaitForChild("Theme"))
local Screens = require(script.Parent:WaitForChild("Screens"))
local State = require(script.Parent:WaitForChild("State"))

local colors = Theme.colors
local sizes = Theme.sizes
local textSizes = Theme.textSizes

-- Layering inside the ScreenGui. The click layer is lowest.
local Z_CLICK = 1
local Z_PANEL = 2

-- The screen each HudLayout.MENU entry opens. Shop is the accent button.
local MENU_SCREEN: { [string]: string } = {
	Eggs = Screens.names.Eggs,
	Pets = Screens.names.Pets,
	Rebirth = Screens.names.Rebirth,
	Shop = Screens.names.Shop,
}
local MENU_ACCENT = "Shop"

local GOAL_ACTION: { [string]: { label: string, screen: string } } = {
	egg = { label = "Open eggs", screen = Screens.names.Eggs },
	gym = { label = "To the gym", screen = Screens.names.Battle },
	rebirth = { label = "Rebirth", screen = Screens.names.Rebirth },
}

-- A plain lookup, so a pet id the client does not know shows as empty
-- instead of erroring like Config.petById would.
local petsById: { [string]: Config.Pet } = {}
for _, pet in Config.pets do
	petsById[pet.id] = pet
end

export type ClickListener = (position: Vector2) -> ()

local Main = {}

local clickListeners: { ClickListener } = {}

-- Called with the screen position of every world click, for the coin pop.
-- The server decides the amount.
function Main.onWorldClick(listener: ClickListener)
	table.insert(clickListeners, listener)
end

local function frame(name: string, parent: Instance?): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.BorderSizePixel = 0
	f.BackgroundTransparency = 1
	f.Parent = parent
	return f
end

local function list(parent: Instance, direction: Enum.FillDirection, padding: number): UIListLayout
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = direction
	layout.Padding = UDim.new(0, padding)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = parent
	return layout
end

-- A solid, Active panel that swallows presses on it.
local function panel(name: string, parent: Instance, radius: number?): Frame
	local f = frame(name, parent)
	f.BackgroundTransparency = 0
	f.BackgroundColor3 = colors.panel
	f.Active = true
	f.ZIndex = Z_PANEL
	Theme.panel(f, radius)
	return f
end

local function button(name: string, text: string, parent: Instance, accent: boolean): TextButton
	local b = Instance.new("TextButton")
	b.Name = name
	b.AutoButtonColor = true
	b.BackgroundColor3 = colors.panel
	b.BorderSizePixel = 0
	b.FontFace = Theme.fonts.label
	b.TextSize = textSizes.button
	b.TextColor3 = if accent then colors.gold else colors.text
	b.Text = Theme.label(text)
	b.ZIndex = Z_PANEL
	b.Parent = parent
	Theme.panel(b, sizes.radius, if accent then colors.gold else colors.border)
	return b
end

-- A label that shrinks its text to fit its box, never past maxSize.
local function fitted(props: {
	name: string,
	parent: Instance,
	font: Font?,
	maxSize: number,
	color: Color3?,
	align: Enum.TextXAlignment?,
}): TextLabel
	local label = Theme.text({
		name = props.name,
		font = props.font,
		size = props.maxSize,
		color = props.color,
		parent = props.parent,
	})
	label.AutomaticSize = Enum.AutomaticSize.None
	label.TextScaled = true
	label.TextXAlignment = props.align or Enum.TextXAlignment.Left
	label.TextTruncate = Enum.TextTruncate.AtEnd
	local limit = Instance.new("UITextSizeConstraint")
	limit.MaxTextSize = props.maxSize
	limit.Parent = label
	return label
end

local function place(g: GuiObject, r: HudLayout.Rect)
	g.Position = UDim2.fromOffset(r.x, r.y)
	g.Size = UDim2.fromOffset(r.w, r.h)
end

type TopBar = {
	bar: Frame,
	coinsBox: Frame,
	coin: Frame,
	coins: TextLabel,
	perClick: TextLabel,
	world: TextLabel,
	rebirths: TextLabel,
}

local function buildTopBar(parent: Instance): TopBar
	local bar = panel("TopBar", parent, 0)
	bar.Position = UDim2.fromScale(0, 0)

	local coinsBox = frame("Coins", bar)
	local coin = frame("Coin", coinsBox)
	coin.BackgroundTransparency = 0
	coin.BackgroundColor3 = colors.gold
	coin.AnchorPoint = Vector2.new(0, 0.5)
	coin.Position = UDim2.fromScale(0, 0.5)
	coin.Size = UDim2.fromOffset(sizes.coin, sizes.coin)
	local round = Instance.new("UICorner")
	round.CornerRadius = UDim.new(0.5, 0)
	round.Parent = coin

	local textLeft = sizes.coin + 10
	local coins = fitted({
		name = "Total",
		parent = coinsBox,
		font = Theme.fonts.heading,
		maxSize = textSizes.coins,
	})
	coins.Text = "0"
	coins.Position = UDim2.new(0, textLeft, 0.08, 0)
	coins.Size = UDim2.new(1, -textLeft, 0.52, 0)
	local perClick = fitted({
		name = "PerClick",
		parent = coinsBox,
		font = Theme.fonts.label,
		maxSize = textSizes.small,
		color = colors.gold,
	})
	perClick.Position = UDim2.new(0, textLeft, 0.6, 0)
	perClick.Size = UDim2.new(1, -textLeft, 0.3, 0)

	local world = fitted({
		name = "World",
		parent = bar,
		font = Theme.fonts.heading,
		maxSize = textSizes.worldName,
		align = Enum.TextXAlignment.Center,
	})

	local rebirths = fitted({
		name = "Rebirths",
		parent = bar,
		font = Theme.fonts.label,
		maxSize = textSizes.small,
		color = colors.muted,
		align = Enum.TextXAlignment.Right,
	})
	rebirths.Text = Theme.label("Rebirths 0")

	return {
		bar = bar,
		coinsBox = coinsBox,
		coin = coin,
		coins = coins,
		perClick = perClick,
		world = world,
		rebirths = rebirths,
	}
end

type Menu = {
	frame: Frame,
	layout: UIListLayout,
	buttons: { TextButton },
}

local function buildMenu(parent: Instance): Menu
	local menu = frame("Menu", parent)
	menu.Active = true
	menu.ZIndex = Z_PANEL
	local layout = list(menu, Enum.FillDirection.Vertical, 6)
	local buttons = {}
	for position, entry in HudLayout.MENU do
		local b = button(entry, entry, menu, entry == MENU_ACCENT)
		b.LayoutOrder = position
		local screen = MENU_SCREEN[entry]
		b.Activated:Connect(function()
			Screens.open(screen)
		end)
		table.insert(buttons, b)
	end
	return { frame = menu, layout = layout, buttons = buttons }
end

type GoalCard = {
	frame: Frame,
	line: TextLabel,
	action: TextButton,
	actionStroke: UIStroke,
}

local goalScreen: string? = nil

local function buildGoal(parent: Instance): GoalCard
	local goal = panel("NextGoal", parent)
	local line = fitted({
		name = "Line",
		parent = goal,
		font = Theme.fonts.label,
		maxSize = textSizes.body,
	})
	local action = button("Action", "", goal, false)
	local actionStroke = action:FindFirstChildOfClass("UIStroke") :: UIStroke
	action.Activated:Connect(function()
		local screen = goalScreen
		if screen ~= nil then
			Screens.open(screen)
		end
	end)
	return { frame = goal, line = line, action = action, actionStroke = actionStroke }
end

type Slot = {
	frame: Frame,
	stripe: Frame,
	block: Frame,
	info: Frame,
	name: TextLabel,
	power: TextLabel,
}

local function buildTeam(parent: Instance): (Frame, UIListLayout, UIPadding, { Slot })
	local team = panel("Team", parent)
	team.Visible = false
	local padding = Instance.new("UIPadding")
	padding.Parent = team
	local layout = list(team, Enum.FillDirection.Horizontal, 8)

	local slots: { Slot } = {}
	for position = 1, Config.constants.team_size do
		local slot = frame("Slot" .. position, team)
		slot.LayoutOrder = position
		slot.BackgroundTransparency = 0
		slot.BackgroundColor3 = colors.raised
		slot.ClipsDescendants = true
		slot.Visible = false
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, sizes.slotRadius)
		corner.Parent = slot

		local stripe = frame("Rarity", slot)
		stripe.BackgroundTransparency = 0
		stripe.Size = UDim2.new(0, sizes.stripe, 1, 0)

		local block = frame("Pet", slot)
		block.BackgroundTransparency = 0
		block.AnchorPoint = Vector2.new(0, 0.5)
		block.Position = UDim2.new(0, sizes.stripe + 8, 0.5, 0)
		local blockCorner = Instance.new("UICorner")
		blockCorner.CornerRadius = UDim.new(0, sizes.slotRadius)
		blockCorner.Parent = block

		local info = frame("Info", slot)
		local name = fitted({
			name = "Name",
			parent = info,
			font = Theme.fonts.label,
			maxSize = textSizes.petName,
		})
		name.Position = UDim2.fromScale(0, 0.1)
		name.Size = UDim2.fromScale(1, 0.45)
		local power = fitted({
			name = "Power",
			parent = info,
			font = Theme.fonts.label,
			maxSize = textSizes.petPower,
			color = colors.gold,
		})
		power.Position = UDim2.fromScale(0, 0.55)
		power.Size = UDim2.fromScale(1, 0.35)

		table.insert(slots, {
			frame = slot,
			stripe = stripe,
			block = block,
			info = info,
			name = name,
			power = power,
		})
	end
	return team, layout, padding, slots
end

-- True when the point is inside any of the given panels.
local function overAny(point: Vector2, panels: { GuiObject }): boolean
	for _, p in panels do
		if p.Visible then
			local low = p.AbsolutePosition
			local high = low + p.AbsoluteSize
			if
				point.X >= low.X
				and point.X <= high.X
				and point.Y >= low.Y
				and point.Y <= high.Y
			then
				return true
			end
		end
	end
	return false
end

local function number(value: any): number
	return if type(value) == "number" then value else 0
end

-- Builds the main screen under playerGui and keeps it in step with State.
function Main.mount(playerGui: PlayerGui, click: RemoteEvent): ScreenGui
	local gui = Instance.new("ScreenGui")
	gui.Name = "Main"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	-- Behind everything: the world view. Pressing it earns coins.
	local clickLayer = Instance.new("TextButton")
	clickLayer.Name = "ClickLayer"
	clickLayer.Text = ""
	clickLayer.AutoButtonColor = false
	clickLayer.BackgroundTransparency = 1
	clickLayer.BorderSizePixel = 0
	clickLayer.Size = UDim2.fromScale(1, 1)
	clickLayer.ZIndex = Z_CLICK
	clickLayer.Selectable = false
	clickLayer.Parent = gui

	-- Everything else sits below the Roblox top bar.
	local content = frame("Content", gui)
	content.ZIndex = Z_PANEL
	local inset = GuiService:GetGuiInset()
	content.Position = UDim2.fromOffset(0, inset.Y)
	content.Size = UDim2.new(1, 0, 1, -inset.Y)

	local top = buildTopBar(content)
	local menu = buildMenu(content)
	local goal = buildGoal(content)
	local teamFrame, teamLayout, teamPadding, slots = buildTeam(content)
	local panels: { GuiObject } = { top.bar, menu.frame, goal.frame, teamFrame }

	local shownSlots = 0
	local goalWanted = true

	local function applyLayout()
		local area = content.AbsoluteSize
		if area.X <= 0 or area.Y <= 0 then
			return
		end
		local layout = HudLayout.compute(area.X, area.Y, shownSlots)
		local s = layout.sizes

		top.bar.Size = UDim2.new(1, 0, 0, layout.topBar.h)
		place(top.coinsBox, layout.coins)
		place(top.world, layout.world)
		local rebirthRect = layout.rebirths
		top.rebirths.Position = UDim2.fromOffset(rebirthRect.x, rebirthRect.y + rebirthRect.h * 0.3)
		top.rebirths.Size = UDim2.fromOffset(rebirthRect.w, rebirthRect.h * 0.4)
		local coinSize = math.min(sizes.coin, layout.coins.h - 16)
		top.coin.Size = UDim2.fromOffset(coinSize, coinSize)

		place(menu.frame, layout.menu)
		menu.layout.Padding = UDim.new(0, s.menuGap)
		for _, b in menu.buttons do
			b.Size = UDim2.new(1, 0, 0, s.menuButton)
		end

		place(goal.frame, layout.goal)
		goal.line.Position = UDim2.fromOffset(s.goalPad, s.goalPad)
		goal.line.Size = UDim2.new(1, -2 * s.goalPad, 0, s.goalLine)
		goal.action.Position = UDim2.fromOffset(s.goalPad, s.goalPad + s.goalLine + s.goalGap)
		goal.action.Size = UDim2.new(1, -2 * s.goalPad, 0, s.goalButton)
		goal.frame.Visible = goalWanted and not Screens.anyOpen()

		local teamRect = layout.team
		teamFrame.Visible = teamRect ~= nil
		if teamRect ~= nil then
			place(teamFrame, teamRect)
			teamPadding.PaddingTop = UDim.new(0, s.teamPad)
			teamPadding.PaddingBottom = UDim.new(0, s.teamPad)
			teamPadding.PaddingLeft = UDim.new(0, s.teamPad)
			teamPadding.PaddingRight = UDim.new(0, s.teamPad)
			teamLayout.Padding = UDim.new(0, s.slotGap)
			local block = s.slotHeight - 12
			for position, slot in slots do
				slot.frame.Visible = position <= shownSlots
				slot.frame.Size = UDim2.fromOffset(s.slotWidth, s.slotHeight)
				slot.block.Size = UDim2.fromOffset(block, block)
				local infoLeft = sizes.stripe + 16 + block
				slot.info.Position = UDim2.fromOffset(infoLeft, 0)
				slot.info.Size = UDim2.new(1, -(infoLeft + 6), 1, 0)
			end
		end
	end

	content:GetPropertyChangedSignal("AbsoluteSize"):Connect(applyLayout)
	Screens.onChange(function()
		goal.frame.Visible = goalWanted and not Screens.anyOpen()
	end)

	clickLayer.MouseButton1Down:Connect(function(x: number, y: number)
		local point = Vector2.new(x, y)
		if overAny(point, panels) then
			return
		end
		click:FireServer()
		for _, listener in clickListeners do
			task.spawn(listener, point)
		end
	end)

	local function render(payload: State.Payload)
		local profile = payload.profile
		local derived = payload.derived
		local coins = number(profile.coins)
		local rebirths = number(profile.rebirths)
		local goalState: NextGoal.State = {
			coins = coins,
			rebirths = rebirths,
			index = if type(profile.index) == "table" then profile.index else {},
			gymsBeaten = if type(profile.gymsBeaten) == "table" then profile.gymsBeaten else {},
			feesPaid = if type(profile.feesPaid) == "table" then profile.feesPaid else {},
		}

		top.coins.Text = Format.abbreviate(coins)
		top.perClick.Text = Theme.label(
			string.format("+%s per click", Format.abbreviate(number(derived.coinsPerClick)))
		)
		local world = NextGoal.currentWorld(goalState)
		top.world.Text = Theme.label(world.name)
		top.rebirths.Text = Theme.label(string.format("Rebirths %s", Format.abbreviate(rebirths)))

		local picked = NextGoal.pick(goalState, number(derived.rebirthCost))
		goal.line.Text = string.format(
			"%s  %s / %s",
			Theme.label(picked.title),
			Format.abbreviate(picked.have),
			Format.abbreviate(picked.need)
		)
		local action = GOAL_ACTION[picked.kind]
		if picked.ready and action ~= nil then
			goalScreen = action.screen
			goal.action.Text = Theme.label(action.label)
			goal.action.TextColor3 = colors.gold
			goal.action.BackgroundColor3 = colors.panel
			goal.actionStroke.Color = colors.gold
			goal.action.AutoButtonColor = true
		else
			goalScreen = nil
			goal.action.Text = Theme.label("Not enough coins")
			goal.action.TextColor3 = colors.muted
			goal.action.BackgroundColor3 = colors.raised
			goal.actionStroke.Color = colors.border
			goal.action.AutoButtonColor = false
		end

		local owned: { [string]: any } = {}
		local ownedCount = 0
		if type(profile.pets) == "table" then
			for _, pet in profile.pets do
				if type(pet) == "table" and type(pet.uid) == "string" then
					owned[pet.uid] = pet
					ownedCount += 1
				end
			end
		end
		local slotCount = HudLayout.teamSlots(ownedCount, Config.constants.team_size)
		if slotCount ~= shownSlots then
			shownSlots = slotCount
			applyLayout()
		end

		local team = if type(profile.team) == "table" then profile.team else {}
		local powers = if type(derived.teamClickPower) == "table"
			then derived.teamClickPower
			else {}
		for position, slot in slots do
			local uid = team[position]
			local pet = if uid ~= nil then owned[uid] else nil
			local data = if pet ~= nil then petsById[pet.petId] else nil
			if data ~= nil and uid ~= nil then
				slot.stripe.BackgroundColor3 = Theme.rarityColor(data.rarity)
				slot.block.BackgroundTransparency = 0
				slot.block.BackgroundColor3 = colors.panel
				local key = PetVisual.key(pet.petId, pet.variant, nil)
				if slot.block:GetAttribute("PetKey") ~= key then
					PetVisual.view(slot.block, pet.petId, pet.variant, nil)
					slot.block:SetAttribute("PetKey", key)
				end
				slot.name.Text = data.name
				slot.name.TextColor3 = colors.text
				local power = powers[uid]
				slot.power.Text = if type(power) == "number"
					then Theme.label(string.format("+%s click", Format.abbreviate(power)))
					else ""
			else
				slot.stripe.BackgroundColor3 = colors.border
				slot.block.BackgroundTransparency = 1
				local view = slot.block:FindFirstChild("PetView")
				if view ~= nil then
					view:Destroy()
				end
				slot.block:SetAttribute("PetKey", nil)
				slot.name.Text = "Empty"
				slot.name.TextColor3 = colors.muted
				slot.power.Text = ""
			end
		end
	end

	gui.Parent = playerGui
	applyLayout()
	State.subscribe(render)
	return gui
end

return Main
