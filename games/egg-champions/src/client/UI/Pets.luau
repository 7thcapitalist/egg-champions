--!strict
--[[
	Pets: what the player owns, what they are missing, and the team of 3,
	built to match design/ui/Pets.dc.html.

	- Three tabs: My pets, Index and Fruit Edition. shared/ui/PetsView decides
	  what every tile and panel says, so the headless tests cover it.
	- My pets: one tile per owned pet with a rarity stripe on top, a variant
	  marker for shiny and golden, and an EQUIPPED marker. Sort and filter
	  buttons cycle through Click Power (the default), rarity, type and egg.
	- Index: every pet in config grouped by egg, each tile with three marks for
	  normal, shiny and golden. Each egg row shows its completion count and the
	  coin bonus a completed egg gives, and a completed egg is marked.
	- Fruit Edition: the pets whose config edition is set, on their own page.
	- Detail panel: the selected pet's stats with its variant applied, its
	  type, rarity and role, both moves, and Equip or Unequip for an owned pet.
	  Equip and Unequip send the remotes; the server decides and a refusal is
	  shown as a readable message. The team bar on the main screen updates from
	  the ProfileChanged push the server sends after an accepted change.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local PetsView = require(Shared:WaitForChild("ui"):WaitForChild("PetsView"))

local Theme = require(script.Parent:WaitForChild("Theme"))
local Screens = require(script.Parent:WaitForChild("Screens"))
local State = require(script.Parent:WaitForChild("State"))

local colors = Theme.colors
local sizes = Theme.sizes
local textSizes = Theme.textSizes

-- Layout of the mockup, in pixels at 1280 x 720.
local LAYOUT = table.freeze({
	panelWidth = 1140,
	panelHeight = 0.9,
	padding = 24,
	gap = 16,
	headerHeight = 48,
	tabHeight = 40,
	controlsHeight = 36,
	detailWidth = 340,
	tileHeight = 116,
	columns = 5,
	tileBlock = 44,
	eggRowHeight = 32,
	mark = 12,
	detailBlock = 96,
	statRow = 26,
	equipHeight = 48,
})

type Tab = "pets" | "index" | "fruit"

type Selection = {
	petId: string,
	variant: string?,
	uid: string?,
}

local Pets = {}

local opener: ((Tab) -> ())? = nil

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

local function pad(parent: Instance, all: number)
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, all)
	padding.PaddingBottom = UDim.new(0, all)
	padding.PaddingLeft = UDim.new(0, all)
	padding.PaddingRight = UDim.new(0, all)
	padding.Parent = parent
end

local function button(name: string, parent: Instance, text: string): (TextButton, UIStroke)
	local b = Instance.new("TextButton")
	b.Name = name
	b.AutoButtonColor = true
	b.BorderSizePixel = 0
	b.FontFace = Theme.fonts.label
	b.TextSize = textSizes.button
	b.Text = text
	b.BackgroundColor3 = colors.raised
	b.TextColor3 = colors.text
	b.Parent = parent
	Theme.panel(b, sizes.radius)
	return b, b:FindFirstChildOfClass("UIStroke") :: UIStroke
end

local function clear(parent: Instance)
	for _, child in parent:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
end

-- A colored block stands in for the pet until task 14.
local function block(parent: Instance, petId: string, size: number): Frame
	local pet = Config.petById[petId]
	local b = frame("Block", parent)
	b.BackgroundTransparency = 0
	b.BackgroundColor3 = Theme.typeColor(pet.type)
	b.Size = UDim2.fromOffset(size, size)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, sizes.slotRadius)
	corner.Parent = b
	return b
end

local function stripe(parent: Instance, rarity: string)
	local s = frame("Stripe", parent)
	s.BackgroundTransparency = 0
	s.BackgroundColor3 = Theme.rarityColor(rarity)
	s.Size = UDim2.new(1, 0, 0, sizes.stripe)
	s.ZIndex = 2
end

-- A tile button with the shared look: raised panel, rarity stripe, block and
-- name. Returns the button and a frame for the tile's markers.
local function tileButton(
	parent: Instance,
	name: string,
	petId: string,
	rarity: string,
	order: number,
	dim: boolean
): (TextButton, Frame)
	local tile = Instance.new("TextButton")
	tile.Name = name
	tile.Text = ""
	tile.AutoButtonColor = true
	tile.BorderSizePixel = 0
	tile.BackgroundColor3 = colors.raised
	tile.LayoutOrder = order
	tile.ClipsDescendants = true
	tile.Parent = parent
	Theme.panel(tile, sizes.radius)
	stripe(tile, rarity)
	local body = frame("Body", tile)
	body.Size = UDim2.fromScale(1, 1)
	pad(body, 10)
	local bodyList = list(body, Enum.FillDirection.Vertical, 6)
	bodyList.HorizontalAlignment = Enum.HorizontalAlignment.Center
	local pet = block(body, petId, LAYOUT.tileBlock)
	pet.LayoutOrder = 1
	if dim then
		pet.BackgroundTransparency = 0.7
	end
	local label = Theme.text({
		name = "Name",
		text = Config.petById[petId].name,
		font = Theme.fonts.label,
		size = textSizes.petName,
		color = if dim then colors.muted else colors.text,
		parent = body,
	})
	label.LayoutOrder = 2
	local marks = frame("Marks", body)
	marks.LayoutOrder = 3
	marks.AutomaticSize = Enum.AutomaticSize.XY
	local marksList = list(marks, Enum.FillDirection.Horizontal, 6)
	marksList.VerticalAlignment = Enum.VerticalAlignment.Center
	return tile, marks
end

local function marker(parent: Instance, text: string, color: Color3, order: number)
	Theme.text({
		name = "Marker",
		text = Theme.label(text),
		font = Theme.fonts.label,
		size = textSizes.small,
		color = color,
		parent = parent,
	}).LayoutOrder =
		order
end

-- A small square mark for one index state: filled when seen.
local function seenMark(parent: Instance, name: string, seen: boolean, color: Color3, order: number)
	local holder = frame(name, parent)
	holder.LayoutOrder = order
	holder.AutomaticSize = Enum.AutomaticSize.XY
	local holderList = list(holder, Enum.FillDirection.Horizontal, 3)
	holderList.VerticalAlignment = Enum.VerticalAlignment.Center
	local dot = frame("Dot", holder)
	dot.LayoutOrder = 1
	dot.Size = UDim2.fromOffset(LAYOUT.mark, LAYOUT.mark)
	dot.BackgroundTransparency = if seen then 0 else 1
	dot.BackgroundColor3 = color
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 2)
	corner.Parent = dot
	local stroke = Instance.new("UIStroke")
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Color = if seen then color else colors.border
	stroke.Parent = dot
	Theme.text({
		name = "Letter",
		text = string.sub(name, 1, 1),
		font = Theme.fonts.label,
		size = textSizes.small,
		color = if seen then colors.text else colors.muted,
		parent = holder,
	}).LayoutOrder =
		2
end

local function grid(parent: Instance): UIGridLayout
	local g = Instance.new("UIGridLayout")
	g.SortOrder = Enum.SortOrder.LayoutOrder
	g.CellPadding = UDim2.fromOffset(10, 10)
	g.CellSize = UDim2.new(1 / LAYOUT.columns, -10, 0, LAYOUT.tileHeight)
	g.Parent = parent
	return g
end

local function scrolling(name: string, parent: Instance): ScrollingFrame
	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = name
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 6
	scroll.ScrollBarImageColor3 = colors.border
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.CanvasSize = UDim2.new()
	scroll.Parent = parent
	return scroll
end

local function ownedTable(value: any): { any }
	return if type(value) == "table" then value else {}
end

-- Builds the screen under playerGui. Call once.
function Pets.mount(playerGui: PlayerGui, equip: RemoteFunction, unequip: RemoteFunction): ScreenGui
	local gui = Instance.new("ScreenGui")
	gui.Name = "Pets"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = 10
	gui.Enabled = false

	-- Dims the world and swallows presses, so browsing never earns clicks.
	local backdrop = Instance.new("TextButton")
	backdrop.Name = "Backdrop"
	backdrop.Text = ""
	backdrop.AutoButtonColor = false
	backdrop.BackgroundColor3 = colors.backdrop
	backdrop.BackgroundTransparency = 0.5
	backdrop.BorderSizePixel = 0
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.Parent = gui

	local panel = frame("Panel", gui)
	panel.BackgroundTransparency = 0
	panel.BackgroundColor3 = colors.panel
	panel.Active = true
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromScale(0.94, LAYOUT.panelHeight)
	local limit = Instance.new("UISizeConstraint")
	limit.MaxSize = Vector2.new(LAYOUT.panelWidth, math.huge)
	limit.Parent = panel
	Theme.panel(panel, sizes.radius + 2)
	pad(panel, LAYOUT.padding)

	-- Header: the three tabs and Close.
	local header = frame("Header", panel)
	header.Size = UDim2.new(1, 0, 0, LAYOUT.headerHeight)
	local tabsFrame = frame("Tabs", header)
	tabsFrame.AutomaticSize = Enum.AutomaticSize.X
	tabsFrame.Size = UDim2.fromScale(0, 1)
	local tabsList = list(tabsFrame, Enum.FillDirection.Horizontal, 8)
	tabsList.VerticalAlignment = Enum.VerticalAlignment.Center

	local tabButtons: { [Tab]: { button: TextButton, stroke: UIStroke } } = {}
	local tabOrder: { Tab } = { "pets", "index", "fruit" }
	for position, tab in tabOrder do
		local b, stroke = button("Tab_" .. tab, tabsFrame, "")
		b.LayoutOrder = position
		b.AutomaticSize = Enum.AutomaticSize.X
		b.Size = UDim2.fromOffset(0, LAYOUT.tabHeight)
		local tabPad = Instance.new("UIPadding")
		tabPad.PaddingLeft = UDim.new(0, 16)
		tabPad.PaddingRight = UDim.new(0, 16)
		tabPad.Parent = b
		tabButtons[tab] = { button = b, stroke = stroke }
	end

	local close = button("Close", header, Theme.label("Close"))
	close.AnchorPoint = Vector2.new(1, 0.5)
	close.Position = UDim2.fromScale(1, 0.5)
	close.Size = UDim2.fromOffset(100, sizes.minTap)

	-- Body: content on the left, the detail panel on the right.
	local bodyTop = LAYOUT.headerHeight + LAYOUT.gap
	local content = frame("Content", panel)
	content.Position = UDim2.fromOffset(0, bodyTop)
	content.Size = UDim2.new(1, -(LAYOUT.detailWidth + LAYOUT.gap), 1, -bodyTop)

	local detail = frame("Detail", panel)
	detail.AnchorPoint = Vector2.new(1, 0)
	detail.Position = UDim2.new(1, 0, 0, bodyTop)
	detail.Size = UDim2.new(0, LAYOUT.detailWidth, 1, -bodyTop)
	detail.BackgroundTransparency = 0
	detail.BackgroundColor3 = colors.raised
	Theme.panel(detail)
	pad(detail, 18)

	-- My pets page: a hint line, the sort and filter controls, then the grid.
	local petsPage = frame("MyPets", content)
	petsPage.Size = UDim2.fromScale(1, 1)
	local hint = Theme.text({ name = "Hint", color = colors.muted, parent = petsPage })
	hint.Size = UDim2.new(1, 0, 0, textSizes.body + 4)
	hint.AutomaticSize = Enum.AutomaticSize.None
	hint.TextXAlignment = Enum.TextXAlignment.Left
	local controls = frame("Controls", petsPage)
	controls.Position = UDim2.fromOffset(0, textSizes.body + 12)
	controls.Size = UDim2.new(1, 0, 0, LAYOUT.controlsHeight)
	list(controls, Enum.FillDirection.Horizontal, 8)
	local function control(name: string, order: number): TextButton
		local b = button(name, controls, "")
		b.LayoutOrder = order
		b.TextSize = textSizes.small
		b.AutomaticSize = Enum.AutomaticSize.X
		b.Size = UDim2.fromScale(0, 1)
		local p = Instance.new("UIPadding")
		p.PaddingLeft = UDim.new(0, 12)
		p.PaddingRight = UDim.new(0, 12)
		p.Parent = b
		return b
	end
	local sortButton = control("Sort", 1)
	local rarityButton = control("Rarity", 2)
	local typeButton = control("Type", 3)
	local eggButton = control("Egg", 4)
	local petsTop = textSizes.body + 12 + LAYOUT.controlsHeight + 10
	local petsScroll = scrolling("Grid", petsPage)
	petsScroll.Position = UDim2.fromOffset(0, petsTop)
	petsScroll.Size = UDim2.new(1, 0, 1, -petsTop)

	-- Index and Fruit Edition pages.
	local indexScroll = scrolling("Index", content)
	indexScroll.Size = UDim2.fromScale(1, 1)
	list(indexScroll, Enum.FillDirection.Vertical, 12)
	local fruitPage = frame("Fruit", content)
	fruitPage.Size = UDim2.fromScale(1, 1)
	local fruitNote = Theme.text({
		name = "Note",
		color = colors.muted,
		text = "A collection line, one per world. The tag never changes a pet's stats.",
		parent = fruitPage,
	})
	fruitNote.Size = UDim2.new(1, 0, 0, textSizes.body + 4)
	fruitNote.AutomaticSize = Enum.AutomaticSize.None
	fruitNote.TextXAlignment = Enum.TextXAlignment.Left
	local fruitScroll = scrolling("Grid", fruitPage)
	fruitScroll.Position = UDim2.fromOffset(0, textSizes.body + 14)
	fruitScroll.Size = UDim2.new(1, 0, 1, -(textSizes.body + 14))
	grid(fruitScroll)

	local tab: Tab = "pets"
	local sortKey: PetsView.SortKey = PetsView.DEFAULT_SORT
	local filter: PetsView.Filter = {}
	local selected: Selection? = nil
	local message: string? = nil
	local busy = false

	local render: () -> ()

	local function choose(choice: Selection)
		selected = choice
		message = nil
		render()
	end

	local function send(remote: RemoteFunction, uid: string)
		if busy then
			return
		end
		busy = true
		local ok, reply = pcall(function(): any
			return remote:InvokeServer(uid)
		end)
		busy = false
		if not ok or type(reply) ~= "table" then
			message = "The server did not answer. Try again."
		elseif reply.ok == true then
			message = nil
		else
			message = PetsView.reasonText(reply.reason)
		end
		render()
	end

	local function renderDetail(teamUids: { [string]: boolean })
		clear(detail)
		list(detail, Enum.FillDirection.Vertical, 10)
		local choice = selected
		if choice == nil then
			local empty = Theme.text({
				name = "Empty",
				text = "Pick a pet to see its stats and moves.",
				color = colors.muted,
				parent = detail,
			})
			empty.TextWrapped = true
			empty.AutomaticSize = Enum.AutomaticSize.Y
			empty.Size = UDim2.fromScale(1, 0)
			return
		end
		local info = PetsView.detail(choice.petId, choice.variant)
		local pet = Config.petById[choice.petId]

		local top = frame("Top", detail)
		top.LayoutOrder = 1
		top.Size = UDim2.new(1, 0, 0, LAYOUT.detailBlock)
		local topList = list(top, Enum.FillDirection.Horizontal, 14)
		topList.VerticalAlignment = Enum.VerticalAlignment.Center
		local big = block(top, choice.petId, LAYOUT.detailBlock)
		big.LayoutOrder = 1
		local bigStroke = Instance.new("UIStroke")
		bigStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		bigStroke.Thickness = 2
		bigStroke.Color = Theme.rarityColor(pet.rarity)
		bigStroke.Parent = big
		local words = frame("Words", top)
		words.LayoutOrder = 2
		words.AutomaticSize = Enum.AutomaticSize.XY
		list(words, Enum.FillDirection.Vertical, 4)
		Theme.text({
			name = "Name",
			text = Theme.label(info.name),
			font = Theme.fonts.heading,
			size = textSizes.heading,
			parent = words,
		}).LayoutOrder =
			1
		if info.variantName ~= nil then
			marker(words, info.variantName, colors.gold, 2)
		end
		marker(words, info.rarityName, Theme.rarityColor(pet.rarity), 3)
		marker(words, info.typeName .. "  " .. info.roleName, colors.muted, 4)
		if info.editionName ~= nil then
			marker(words, info.editionName, colors.gold, 5)
		end

		local stats = frame("Stats", detail)
		stats.LayoutOrder = 2
		stats.AutomaticSize = Enum.AutomaticSize.Y
		stats.Size = UDim2.fromScale(1, 0)
		list(stats, Enum.FillDirection.Vertical, 0)
		for position, stat in info.stats do
			local row = frame("Stat" .. position, stats)
			row.LayoutOrder = position
			row.Size = UDim2.new(1, 0, 0, LAYOUT.statRow)
			local rule = frame("Rule", row)
			rule.BackgroundTransparency = 0
			rule.BackgroundColor3 = colors.border
			rule.AnchorPoint = Vector2.new(0, 1)
			rule.Position = UDim2.fromScale(0, 1)
			rule.Size = UDim2.new(1, 0, 0, sizes.border)
			local name = Theme.text({
				name = "Label",
				text = stat.label,
				color = colors.muted,
				parent = row,
			})
			name.AnchorPoint = Vector2.new(0, 0.5)
			name.Position = UDim2.fromScale(0, 0.5)
			local value = Theme.text({
				name = "Value",
				text = stat.value,
				font = Theme.fonts.label,
				parent = row,
			})
			value.AnchorPoint = Vector2.new(1, 0.5)
			value.Position = UDim2.fromScale(1, 0.5)
		end

		local moves = frame("Moves", detail)
		moves.LayoutOrder = 3
		moves.AutomaticSize = Enum.AutomaticSize.Y
		moves.Size = UDim2.fromScale(1, 0)
		list(moves, Enum.FillDirection.Vertical, 4)
		for position, move in info.moves do
			local line = Theme.text({
				name = "Move" .. position,
				text = string.format("%s (%s): %s", move.name, move.kind, move.text),
				size = textSizes.small + 1,
				parent = moves,
			})
			line.LayoutOrder = position
			line.TextWrapped = true
			line.TextXAlignment = Enum.TextXAlignment.Left
			line.AutomaticSize = Enum.AutomaticSize.Y
			line.Size = UDim2.fromScale(1, 0)
		end

		local uid = choice.uid
		if uid ~= nil then
			local equipped = teamUids[uid] == true
			local action =
				button("Equip", detail, Theme.label(if equipped then "Unequip" else "Equip"))
			action.LayoutOrder = 4
			action.Size = UDim2.new(1, 0, 0, LAYOUT.equipHeight)
			if not equipped then
				action.BackgroundColor3 = colors.raised
				action.TextColor3 = colors.gold
				local stroke = action:FindFirstChildOfClass("UIStroke") :: UIStroke
				stroke.Color = colors.gold
			end
			action.Activated:Connect(function()
				-- The client never decides: both go to the server as they are.
				send(if equipped then unequip else equip, uid)
			end)
		else
			marker(detail, "Not owned in this form", colors.muted, 4)
		end
		if message ~= nil then
			local note = Theme.text({
				name = "Message",
				text = message,
				color = colors.gold,
				parent = detail,
			})
			note.LayoutOrder = 5
			note.TextWrapped = true
			note.AutomaticSize = Enum.AutomaticSize.Y
			note.Size = UDim2.fromScale(1, 0)
		end
	end

	local function indexTile(parent: Instance, tile: PetsView.IndexTile, order: number)
		local b, marks =
			tileButton(parent, tile.petId, tile.petId, tile.rarity, order, not tile.seenAny)
		seenMark(marks, "Normal", tile.seen.normal, colors.text, 1)
		seenMark(marks, "Shiny", tile.seen.shiny, colors.gold, 2)
		seenMark(marks, "Golden", tile.seen.golden, colors.gold, 3)
		b.Activated:Connect(function()
			choose({ petId = tile.petId, variant = nil, uid = nil })
		end)
	end

	render = function()
		local payload = State.get()
		local profile = if payload ~= nil then payload.profile else {}
		local pets = ownedTable(profile.pets)
		local team = ownedTable(profile.team)
		local index = ownedTable(profile.index)
		local teamUids: { [string]: boolean } = {}
		for _, uid in team do
			if type(uid) == "string" then
				teamUids[uid] = true
			end
		end

		local counts = PetsView.tabCounts(pets, index)
		local labels: { [Tab]: string } = {
			pets = string.format("My pets  %d", counts.owned),
			index = string.format("Index  %d / %d", counts.seen, counts.total),
			fruit = string.format("Fruit Edition  %d / %d", counts.fruitSeen, counts.fruitTotal),
		}
		for key, view in tabButtons do
			view.button.Text = Theme.label(labels[key])
			local active = key == tab
			view.button.TextColor3 = if active then colors.gold else colors.muted
			view.stroke.Color = if active then colors.gold else colors.border
		end
		petsPage.Visible = tab == "pets"
		indexScroll.Visible = tab == "index"
		fruitPage.Visible = tab == "fruit"

		-- A selected owned pet that is gone (traded, or a new save) clears.
		local tiles = PetsView.tiles(pets, team)
		local current = selected
		if current ~= nil and current.uid ~= nil then
			local found = false
			for _, tile in tiles do
				if tile.uid == current.uid then
					found = true
				end
			end
			if not found then
				selected = nil
			end
		end

		if tab == "pets" then
			hint.Text = string.format(
				"Team %d of %d. The same team clicks and battles.",
				#team,
				Config.constants.team_size
			)
			sortButton.Text = Theme.label("Sort: " .. PetsView.SORT_NAMES[sortKey])
			rarityButton.Text =
				Theme.label("Rarity: " .. PetsView.filterName("rarity", filter.rarity))
			typeButton.Text = Theme.label("Type: " .. PetsView.filterName("type", filter.type))
			eggButton.Text = Theme.label("Egg: " .. PetsView.filterName("egg", filter.egg))
			clear(petsScroll)
			grid(petsScroll)
			for position, tile in PetsView.arrange(tiles, sortKey, filter) do
				local b, marks =
					tileButton(petsScroll, tile.uid, tile.petId, tile.rarity, position, false)
				marker(marks, tile.clickPowerText, colors.muted, 1)
				if tile.variantName ~= nil then
					marker(marks, tile.variantName, colors.gold, 2)
				end
				if tile.equipped then
					marker(marks, "Equipped", colors.gold, 3)
				end
				local chosen = selected
				if chosen ~= nil and chosen.uid == tile.uid then
					(b:FindFirstChildOfClass("UIStroke") :: UIStroke).Color = colors.gold
				end
				local uid, petId, variant = tile.uid, tile.petId, tile.variant
				b.Activated:Connect(function()
					choose({ petId = petId, variant = variant, uid = uid })
				end)
			end
		elseif tab == "index" then
			clear(indexScroll)
			list(indexScroll, Enum.FillDirection.Vertical, 12)
			for position, row in PetsView.eggProgress(index) do
				local section = frame(row.eggId, indexScroll)
				section.LayoutOrder = position
				section.AutomaticSize = Enum.AutomaticSize.Y
				section.Size = UDim2.new(1, -8, 0, 0)
				list(section, Enum.FillDirection.Vertical, 8)
				local head = frame("Head", section)
				head.LayoutOrder = 1
				head.Size = UDim2.new(1, 0, 0, LAYOUT.eggRowHeight)
				local headList = list(head, Enum.FillDirection.Horizontal, 12)
				headList.VerticalAlignment = Enum.VerticalAlignment.Center
				Theme.text({
					name = "Egg",
					text = Theme.label(row.name),
					font = Theme.fonts.heading,
					size = textSizes.petName + 2,
					parent = head,
				}).LayoutOrder =
					1
				marker(head, string.format("%d / %d", row.seen, row.total), colors.muted, 2)
				marker(
					head,
					if row.complete
						then "Complete " .. row.bonusText
						else "Complete for " .. row.bonusText,
					if row.complete then colors.gold else colors.muted,
					3
				)
				local cells = frame("Pets", section)
				cells.LayoutOrder = 2
				cells.AutomaticSize = Enum.AutomaticSize.Y
				cells.Size = UDim2.fromScale(1, 0)
				grid(cells)
				for order, tile in row.tiles do
					indexTile(cells, tile, order)
				end
			end
		else
			clear(fruitScroll)
			grid(fruitScroll)
			for order, tile in PetsView.fruitTiles(index) do
				indexTile(fruitScroll, tile, order)
			end
		end

		renderDetail(teamUids)
	end

	sortButton.Activated:Connect(function()
		sortKey = PetsView.nextSort(sortKey)
		render()
	end)
	rarityButton.Activated:Connect(function()
		filter.rarity = PetsView.nextFilter("rarity", filter.rarity)
		render()
	end)
	typeButton.Activated:Connect(function()
		filter.type = PetsView.nextFilter("type", filter.type)
		render()
	end)
	eggButton.Activated:Connect(function()
		filter.egg = PetsView.nextFilter("egg", filter.egg)
		render()
	end)
	for key, view in tabButtons do
		view.button.Activated:Connect(function()
			tab = key
			render()
		end)
	end

	local function hide()
		gui.Enabled = false
	end
	close.Activated:Connect(hide)
	backdrop.Activated:Connect(hide)

	opener = function(which: Tab)
		tab = which
		message = nil
		render()
		gui.Enabled = true
	end

	render()
	gui.Parent = playerGui
	State.subscribe(function()
		if gui.Enabled then
			render()
		end
	end)
	Screens.register(Screens.names.Pets, function()
		Pets.open("pets")
	end)
	Screens.register(Screens.names.Index, function()
		Pets.open("index")
	end)
	return gui
end

-- Opens the screen on a tab. Does nothing before mount.
function Pets.open(which: Tab)
	if opener ~= nil then
		opener(which)
	end
end

return Pets
