--!strict
--[[
	Main: the screen the player sees most, built to match
	design/ui/Main.dc.html.

	- Top bar (64px): coins, coins per click in gold, the world index and name
	  centred, rebirth count, and one badge marker per world, filled when won.
	- Pass chips in the top bar's badge area, one per game pass in config:
	  gold when owned, and a purchase prompt on press when not. Ownership is
	  the server's derived "passes" field; the client never checks it.
	- Left menu: Eggs, Pets, Index, Rebirth, Shop. Each opens its screen
	  through Screens.
	- Next-goal panel on the right, picked by shared/ui/NextGoal.
	- The team bar at the bottom, one slot per constants.team_size.

	Clicking: there is no click button. A full screen transparent button sits
	behind every panel and fires Click on press. Panels are Active so they
	swallow their own presses, and a press over any panel is also ignored by
	position, so pressing a menu button never earns a coin.

	Every number shown comes from the server through ProfileChanged (see
	State). Coins per click and each pet's click power are derived fields the
	server sends; this module only formats them.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local GuiService = game:GetService("GuiService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local PetVisual = require(Shared:WaitForChild("PetVisual"))
local uiShared = Shared:WaitForChild("ui")
local Format = require(uiShared:WaitForChild("Format"))
local NextGoal = require(uiShared:WaitForChild("NextGoal"))

local Theme = require(script.Parent:WaitForChild("Theme"))
local Screens = require(script.Parent:WaitForChild("Screens"))
local State = require(script.Parent:WaitForChild("State"))

local colors = Theme.colors
local sizes = Theme.sizes
local textSizes = Theme.textSizes

-- Layering inside the ScreenGui. The click layer is lowest.
local Z_CLICK = 1
local Z_PANEL = 2

local MENU = table.freeze({
	{ label = "Eggs", screen = Screens.names.Eggs, accent = false },
	{ label = "Pets", screen = Screens.names.Pets, accent = false },
	{ label = "Index", screen = Screens.names.Index, accent = false },
	{ label = "Rebirth", screen = Screens.names.Rebirth, accent = false },
	{ label = "Shop", screen = Screens.names.Shop, accent = true },
})

local GOAL_ROW_LABEL: { [string]: string } = {
	egg = "Price",
	gym = "Fee",
	rebirth = "Cost",
}

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

-- Called with the screen position of every world click, for the coin pop
-- that task 15 adds. The server decides the amount.
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

local function list(
	parent: Instance,
	direction: Enum.FillDirection,
	padding: number,
	align: Enum.VerticalAlignment?
)
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = direction
	layout.Padding = UDim.new(0, padding)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.VerticalAlignment = align or Enum.VerticalAlignment.Top
	layout.Parent = parent
	return layout
end

local function pad(parent: Instance, all: number)
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, all)
	padding.PaddingBottom = UDim.new(0, all)
	padding.PaddingLeft = UDim.new(0, all)
	padding.PaddingRight = UDim.new(0, all)
	padding.Parent = parent
end

-- A solid, Active panel that swallows presses on it.
local function panel(name: string, parent: Instance, radius: number?, borderColor: Color3?): Frame
	local f = frame(name, parent)
	f.BackgroundTransparency = 0
	f.BackgroundColor3 = colors.panel
	f.Active = true
	f.ZIndex = Z_PANEL
	Theme.panel(f, radius, borderColor)
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

type TopBar = {
	coins: TextLabel,
	perClick: TextLabel,
	worldIndex: TextLabel,
	worldName: TextLabel,
	rebirths: TextLabel,
	badges: { [string]: Frame },
	passes: { [string]: TextButton },
}

-- The Roblox id to prompt for each pass, as the server last sent it. 0 or
-- missing means the pass cannot be bought yet.
local passProducts: { [string]: number } = {}
local passOwned: { [string]: boolean } = {}

local function promptPass(passId: string)
	if passOwned[passId] == true then
		return
	end
	local productId = passProducts[passId]
	if productId == nil or productId <= 0 then
		return
	end
	pcall(function()
		MarketplaceService:PromptGamePassPurchase(Players.LocalPlayer, productId)
	end)
end

local function buildTopBar(parent: Instance): (Frame, TopBar)
	local bar = panel("TopBar", parent, 0)
	bar.Size = UDim2.new(1, 0, 0, sizes.topBar)
	bar.Position = UDim2.fromScale(0, 0)
	-- Only the bottom border shows in the mockup; a full stroke reads the same
	-- on a bar that spans the screen.

	local left = frame("Coins", bar)
	left.AnchorPoint = Vector2.new(0, 0.5)
	left.Position = UDim2.new(0, sizes.gutter, 0.5, 0)
	left.AutomaticSize = Enum.AutomaticSize.XY
	list(left, Enum.FillDirection.Horizontal, 12, Enum.VerticalAlignment.Center)

	local coin = frame("Coin", left)
	coin.LayoutOrder = 1
	coin.BackgroundTransparency = 0
	coin.BackgroundColor3 = colors.gold
	coin.Size = UDim2.fromOffset(sizes.coin, sizes.coin)
	local round = Instance.new("UICorner")
	round.CornerRadius = UDim.new(0.5, 0)
	round.Parent = coin

	local coins = Theme.text({
		name = "Total",
		text = "0",
		font = Theme.fonts.heading,
		size = textSizes.coins,
		parent = left,
	})
	coins.LayoutOrder = 2

	local perClick = Theme.text({
		name = "PerClick",
		font = Theme.fonts.label,
		color = colors.gold,
		parent = left,
	})
	perClick.LayoutOrder = 3

	local centre = frame("World", bar)
	centre.AnchorPoint = Vector2.new(0.5, 0.5)
	centre.Position = UDim2.fromScale(0.5, 0.5)
	centre.AutomaticSize = Enum.AutomaticSize.XY
	local centreList = list(centre, Enum.FillDirection.Vertical, 0)
	centreList.HorizontalAlignment = Enum.HorizontalAlignment.Center

	local worldIndex = Theme.text({
		name = "Index",
		font = Theme.fonts.label,
		size = textSizes.small,
		color = colors.muted,
		parent = centre,
	})
	worldIndex.LayoutOrder = 1
	local worldName = Theme.text({
		name = "Name",
		font = Theme.fonts.heading,
		size = textSizes.worldName,
		parent = centre,
	})
	worldName.LayoutOrder = 2

	local right = frame("Progress", bar)
	right.AnchorPoint = Vector2.new(1, 0.5)
	right.Position = UDim2.new(1, -sizes.gutter, 0.5, 0)
	right.AutomaticSize = Enum.AutomaticSize.XY
	local rightList = list(right, Enum.FillDirection.Horizontal, 20, Enum.VerticalAlignment.Center)
	rightList.HorizontalAlignment = Enum.HorizontalAlignment.Right

	local rebirthGroup = frame("Rebirths", right)
	rebirthGroup.LayoutOrder = 1
	rebirthGroup.AutomaticSize = Enum.AutomaticSize.XY
	list(rebirthGroup, Enum.FillDirection.Horizontal, 6, Enum.VerticalAlignment.Center)
	Theme.text({
		name = "Label",
		text = Theme.label("Rebirths"),
		font = Theme.fonts.label,
		parent = rebirthGroup,
	}).LayoutOrder =
		1
	local rebirths = Theme.text({
		name = "Count",
		text = "0",
		font = Theme.fonts.label,
		color = colors.gold,
		parent = rebirthGroup,
	})
	rebirths.LayoutOrder = 2

	local badgeGroup = frame("Badges", right)
	badgeGroup.LayoutOrder = 2
	badgeGroup.AutomaticSize = Enum.AutomaticSize.XY
	list(badgeGroup, Enum.FillDirection.Horizontal, 12, Enum.VerticalAlignment.Center)
	Theme.text({
		name = "Label",
		text = Theme.label("Badges"),
		font = Theme.fonts.label,
		parent = badgeGroup,
	}).LayoutOrder =
		0

	local worlds = table.clone(Config.worlds)
	table.sort(worlds, function(a, b)
		return a.index < b.index
	end)
	local badges: { [string]: Frame } = {}
	for _, world in worlds do
		-- A rotated square inside a holder, so the layout spaces the holders
		-- and the rotation never overlaps a neighbour.
		local holder = frame("Badge" .. world.index, badgeGroup)
		holder.LayoutOrder = world.index
		holder.Size = UDim2.fromOffset(sizes.badge, sizes.badge)
		local diamond = frame("Marker", holder)
		diamond.AnchorPoint = Vector2.new(0.5, 0.5)
		diamond.Position = UDim2.fromScale(0.5, 0.5)
		diamond.Size = UDim2.fromOffset(sizes.badge, sizes.badge)
		diamond.Rotation = 45
		diamond.BackgroundColor3 = colors.gold
		local stroke = Instance.new("UIStroke")
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		stroke.Color = colors.badgeEmpty
		stroke.Thickness = 2
		stroke.Parent = diamond
		badges[world.id] = diamond
	end

	-- One chip per game pass, after the world badges.
	local passGroup = frame("Passes", right)
	passGroup.LayoutOrder = 3
	passGroup.AutomaticSize = Enum.AutomaticSize.XY
	list(passGroup, Enum.FillDirection.Horizontal, 6, Enum.VerticalAlignment.Center)
	local passes: { [string]: TextButton } = {}
	for position, pass in Config.passes do
		local chip = Instance.new("TextButton")
		chip.Name = "Pass_" .. pass.id
		chip.LayoutOrder = position
		chip.AutoButtonColor = true
		chip.AutomaticSize = Enum.AutomaticSize.X
		chip.Size = UDim2.fromOffset(0, sizes.badge + 12)
		chip.BackgroundColor3 = colors.panel
		chip.BorderSizePixel = 0
		chip.FontFace = Theme.fonts.label
		chip.TextSize = textSizes.small
		chip.TextColor3 = colors.muted
		chip.Text = Theme.label("+ " .. pass.name)
		chip.ZIndex = Z_PANEL
		chip.Parent = passGroup
		local chipPad = Instance.new("UIPadding")
		chipPad.PaddingLeft = UDim.new(0, 6)
		chipPad.PaddingRight = UDim.new(0, 6)
		chipPad.Parent = chip
		Theme.panel(chip, sizes.radius, colors.border)
		chip.Activated:Connect(function()
			promptPass(pass.id)
		end)
		passes[pass.id] = chip
	end

	return bar,
		{
			coins = coins,
			perClick = perClick,
			worldIndex = worldIndex,
			worldName = worldName,
			rebirths = rebirths,
			badges = badges,
			passes = passes,
		}
end

local function buildMenu(parent: Instance): Frame
	local menu = frame("Menu", parent)
	menu.Position = UDim2.fromOffset(sizes.gutter, sizes.topBar + 32)
	menu.Size = UDim2.fromOffset(sizes.menuWidth, 0)
	menu.AutomaticSize = Enum.AutomaticSize.Y
	menu.Active = true
	menu.ZIndex = Z_PANEL
	list(menu, Enum.FillDirection.Vertical, 6)
	for position, entry in MENU do
		local b = button(entry.label, entry.label, menu, entry.accent)
		b.LayoutOrder = position
		b.Size = UDim2.new(1, 0, 0, math.max(sizes.menuButton, sizes.minTap))
		local screen = entry.screen
		b.Activated:Connect(function()
			Screens.open(screen)
		end)
	end
	return menu
end

type GoalPanel = {
	title: TextLabel,
	detail: TextLabel,
	rowLabel: TextLabel,
	rowValue: TextLabel,
	fill: Frame,
	action: TextButton,
	actionStroke: UIStroke,
}

local goalScreen: string? = nil

local function buildGoal(parent: Instance): (Frame, GoalPanel)
	local goal = panel("NextGoal", parent)
	goal.AnchorPoint = Vector2.new(1, 0)
	goal.Position = UDim2.new(1, -sizes.gutter, 0, sizes.topBar + 32)
	goal.Size = UDim2.fromScale(sizes.goalWidth / sizes.designWidth, 0)
	goal.AutomaticSize = Enum.AutomaticSize.Y
	local limit = Instance.new("UISizeConstraint")
	limit.MinSize = Vector2.new(sizes.goalMinWidth, 0)
	limit.MaxSize = Vector2.new(sizes.goalWidth, math.huge)
	limit.Parent = goal
	pad(goal, 16)
	list(goal, Enum.FillDirection.Vertical, 8)

	Theme.text({
		name = "Header",
		text = Theme.label("Next goal"),
		font = Theme.fonts.label,
		size = textSizes.small,
		color = colors.muted,
		parent = goal,
	}).LayoutOrder =
		1

	local title = Theme.text({
		name = "Title",
		font = Theme.fonts.heading,
		size = textSizes.heading,
		parent = goal,
	})
	title.LayoutOrder = 2
	title.AutomaticSize = Enum.AutomaticSize.Y
	title.Size = UDim2.fromScale(1, 0)
	title.TextWrapped = true
	title.TextXAlignment = Enum.TextXAlignment.Left

	local detail = Theme.text({ name = "Detail", color = colors.muted, parent = goal })
	detail.LayoutOrder = 3
	detail.AutomaticSize = Enum.AutomaticSize.Y
	detail.Size = UDim2.fromScale(1, 0)
	detail.TextWrapped = true
	detail.TextXAlignment = Enum.TextXAlignment.Left

	local row = frame("Row", goal)
	row.LayoutOrder = 4
	row.Size = UDim2.new(1, 0, 0, textSizes.body + 4)
	local rowLabel = Theme.text({ name = "Label", font = Theme.fonts.label, parent = row })
	local rowValue = Theme.text({ name = "Value", font = Theme.fonts.label, parent = row })
	rowValue.AnchorPoint = Vector2.new(1, 0)
	rowValue.Position = UDim2.fromScale(1, 0)

	local track = frame("Bar", goal)
	track.LayoutOrder = 5
	track.BackgroundTransparency = 0
	track.BackgroundColor3 = colors.border
	track.Size = UDim2.new(1, 0, 0, sizes.bar)
	local fill = frame("Fill", track)
	fill.BackgroundTransparency = 0
	fill.BackgroundColor3 = colors.gold
	fill.Size = UDim2.fromScale(0, 1)

	local action = button("Action", "", goal, false)
	action.LayoutOrder = 6
	action.Size = UDim2.new(1, 0, 0, sizes.minTap)
	action.TextSize = textSizes.body - 1
	local actionStroke = action:FindFirstChildOfClass("UIStroke") :: UIStroke
	action.Activated:Connect(function()
		local screen = goalScreen
		if screen ~= nil then
			Screens.open(screen)
		end
	end)

	return goal,
		{
			title = title,
			detail = detail,
			rowLabel = rowLabel,
			rowValue = rowValue,
			fill = fill,
			action = action,
			actionStroke = actionStroke,
		}
end

type Slot = {
	stripe: Frame,
	block: Frame,
	name: TextLabel,
	power: TextLabel,
}

local function buildTeam(parent: Instance): (Frame, { Slot })
	local team = panel("Team", parent)
	team.AnchorPoint = Vector2.new(0.5, 1)
	team.Position = UDim2.new(0.5, 0, 1, -20)
	team.AutomaticSize = Enum.AutomaticSize.XY
	pad(team, 8)
	list(team, Enum.FillDirection.Horizontal, 8)

	local slots: { Slot } = {}
	for position = 1, Config.constants.team_size do
		local slot = frame("Slot" .. position, team)
		slot.LayoutOrder = position
		slot.BackgroundTransparency = 0
		slot.BackgroundColor3 = colors.raised
		slot.Size = UDim2.fromOffset(sizes.slotWidth, sizes.petBlock + 16)
		slot.ClipsDescendants = true
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, sizes.slotRadius)
		corner.Parent = slot

		local stripe = frame("Rarity", slot)
		stripe.BackgroundTransparency = 0
		stripe.Size = UDim2.new(0, sizes.stripe, 1, 0)

		local block = frame("Pet", slot)
		block.BackgroundTransparency = 0
		block.AnchorPoint = Vector2.new(0, 0.5)
		block.Position = UDim2.new(0, sizes.stripe + 10, 0.5, 0)
		block.Size = UDim2.fromOffset(sizes.petBlock, sizes.petBlock)
		local blockCorner = Instance.new("UICorner")
		blockCorner.CornerRadius = UDim.new(0, sizes.slotRadius)
		blockCorner.Parent = block

		local info = frame("Info", slot)
		info.AnchorPoint = Vector2.new(0, 0.5)
		info.Position = UDim2.new(0, sizes.stripe + 20 + sizes.petBlock, 0.5, 0)
		info.AutomaticSize = Enum.AutomaticSize.XY
		list(info, Enum.FillDirection.Vertical, 0)
		local name = Theme.text({
			name = "Name",
			font = Theme.fonts.label,
			size = textSizes.petName,
			parent = info,
		})
		name.LayoutOrder = 1
		local power = Theme.text({
			name = "Power",
			font = Theme.fonts.label,
			size = textSizes.petPower,
			color = colors.gold,
			parent = info,
		})
		power.LayoutOrder = 2

		table.insert(slots, { stripe = stripe, block = block, name = name, power = power })
	end
	return team, slots
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
	local function fitInset()
		local inset = GuiService:GetGuiInset()
		content.Position = UDim2.fromOffset(0, inset.Y)
		content.Size = UDim2.new(1, 0, 1, -inset.Y)
	end
	fitInset()

	local topBar, top = buildTopBar(content)
	local menu = buildMenu(content)
	local goalFrame, goal = buildGoal(content)
	local teamFrame, slots = buildTeam(content)
	local panels: { GuiObject } = { topBar, menu, goalFrame, teamFrame }

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
		top.worldIndex.Text = Theme.label(string.format("World %d", world.index))
		top.worldName.Text = Theme.label(world.name)
		top.rebirths.Text = Format.abbreviate(rebirths)
		local badges = if type(profile.badges) == "table" then profile.badges else {}
		for worldId, marker in top.badges do
			marker.BackgroundTransparency = if badges[worldId] == true then 0 else 1
		end

		local passList = if type(derived.passes) == "table" then derived.passes else {}
		for _, entry in passList do
			if type(entry) == "table" and type(entry.id) == "string" then
				passOwned[entry.id] = entry.owned == true
				passProducts[entry.id] = if type(entry.productId) == "number"
					then entry.productId
					else 0
			end
		end
		for _, pass in Config.passes do
			local chip = top.passes[pass.id]
			local owned = passOwned[pass.id] == true
			local buyable = (passProducts[pass.id] or 0) > 0
			chip.Text = Theme.label(if owned then pass.name else "+ " .. pass.name)
			chip.TextColor3 = if owned
				then colors.gold
				elseif buyable then colors.text
				else colors.muted
			chip.AutoButtonColor = not owned and buyable
			local stroke = chip:FindFirstChildOfClass("UIStroke")
			if stroke ~= nil then
				stroke.Color = if owned then colors.gold else colors.border
			end
		end

		local picked = NextGoal.pick(goalState, number(derived.rebirthCost))
		goal.title.Text = Theme.label(picked.title)
		goal.detail.Text = picked.detail
		goal.rowLabel.Text = GOAL_ROW_LABEL[picked.kind] or ""
		goal.rowValue.Text =
			string.format("%s / %s", Format.abbreviate(picked.have), Format.abbreviate(picked.need))
		goal.fill.Size = UDim2.fromScale(picked.progress, 1)
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
		if type(profile.pets) == "table" then
			for _, pet in profile.pets do
				if type(pet) == "table" and type(pet.uid) == "string" then
					owned[pet.uid] = pet
				end
			end
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
	State.subscribe(render)
	return gui
end

return Main
