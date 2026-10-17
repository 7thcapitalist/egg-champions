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
	  A beginner (tutorial running, or fewer than 4 pets, PetsView.beginner)
	  sees name, rarity, type and Click Power, with battle stats and moves
	  behind a Battle stats toggle. EQUIP is a filled gold button.
	- The panel keeps clear of the HUD's left menu, and with few pets it is
	  narrower and centered with bigger tiles (PetsLayout options).
	  Equip and Unequip send the remotes; the server decides and a refusal is
	  shown as a readable message. The team bar on the main screen updates from
	  the ProfileChanged push the server sends after an accepted change.
	- Where everything sits comes from shared/ui/PetsLayout, whose specs check
	  808 x 432 and 1280 x 720: EQUIP sits right under the pet name and the
	  rest of the detail panel scrolls; the filter row wraps; tile markers
	  each get their own line.
	- Tutorial: the header shows UI/Guide's one-line bar while a step has a
	  line for this screen. The first owned pet tile registers as the
	  "pet:first" pointer target, and the selection goes to Guide so the
	  pointer moves on to EQUIP.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local PetVisual = require(Shared:WaitForChild("PetVisual"))
local uiShared = Shared:WaitForChild("ui")
local PetsView = require(uiShared:WaitForChild("PetsView"))
local PetsLayout = require(uiShared:WaitForChild("PetsLayout"))
local HudInsets = require(script.Parent:WaitForChild("HudInsets"))

local Theme = require(script.Parent:WaitForChild("Theme"))
local Guide = require(script.Parent:WaitForChild("Guide"))
local Pointer = require(script.Parent:WaitForChild("Pointer"))
local Screens = require(script.Parent:WaitForChild("Screens"))
local State = require(script.Parent:WaitForChild("State"))

local colors = Theme.colors
local sizes = Theme.sizes
local textSizes = Theme.textSizes

-- Pixel sizes that do not change with the screen. Everything that does
-- comes from shared/ui/PetsLayout.
local LAYOUT = table.freeze({
	tabHeight = 40,
	eggRowHeight = 32,
	mark = 12,
})

-- The pointer target name of the first owned pet tile (Tutorial.card).
local FIRST_PET_TARGET = "pet:first"

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
		if child:IsA("GuiObject") or child:IsA("UIGridStyleLayout") then
			child:Destroy()
		end
	end
end

-- A framed pet view from PetVisual, the one place a pet's look is built.
local function block(parent: Instance, petId: string, size: number, variant: string?): Frame
	local b = frame("Block", parent)
	b.BackgroundTransparency = 0
	b.BackgroundColor3 = colors.panel
	b.Size = UDim2.fromOffset(size, size)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, sizes.slotRadius)
	corner.Parent = b
	PetVisual.view(b, petId, variant, nil)
	return b
end

local function stripe(parent: Instance, rarity: string)
	local s = frame("Stripe", parent)
	s.BackgroundTransparency = 0
	s.BackgroundColor3 = Theme.rarityColor(rarity)
	s.Size = UDim2.new(1, 0, 0, sizes.stripe)
	s.ZIndex = 2
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, sizes.stripe)
	corner.Parent = s
end

-- A tile button with the shared look: raised panel, rarity stripe, block and
-- name. Returns the button and a frame for the tile's markers, which stack
-- one per line when stacked is true. Tiles do not clip, so the tutorial
-- outline around one shows in full.
local function tileButton(
	parent: Instance,
	s: PetsLayout.Sizes,
	name: string,
	petId: string,
	rarity: string,
	order: number,
	dim: boolean,
	stacked: boolean,
	variant: string?
): (TextButton, Frame)
	local tile = Instance.new("TextButton")
	tile.Name = name
	tile.Text = ""
	tile.AutoButtonColor = true
	tile.BorderSizePixel = 0
	tile.BackgroundColor3 = colors.raised
	tile.LayoutOrder = order
	tile.ClipsDescendants = false
	tile.Parent = parent
	Theme.panel(tile, sizes.radius)
	stripe(tile, rarity)
	local body = frame("Body", tile)
	body.Size = UDim2.fromScale(1, 1)
	pad(body, s.tilePad)
	local bodyList = list(body, Enum.FillDirection.Vertical, s.markerGap)
	bodyList.HorizontalAlignment = Enum.HorizontalAlignment.Center
	if s.tileHorizontal then
		bodyList:Destroy()
	end
	local pet = block(body, petId, s.tileBlock, variant)
	pet.LayoutOrder = 1
	if dim then
		pet.BackgroundTransparency = 0.7
		local view = pet:FindFirstChild("PetView")
		if view ~= nil and view:IsA("ViewportFrame") then
			view.ImageTransparency = 0.6
		end
	end
	local label = Theme.text({
		name = "Name",
		text = Config.petById[petId].name,
		font = Theme.fonts.label,
		size = s.tileName - 2,
		color = if dim then colors.muted else colors.text,
		parent = body,
	})
	label.LayoutOrder = 2
	label.AutomaticSize = Enum.AutomaticSize.None
	label.Size = UDim2.new(1, 0, 0, s.tileName)
	label.TextTruncate = Enum.TextTruncate.AtEnd
	local marks = frame("Marks", body)
	marks.LayoutOrder = 3
	if stacked then
		marks.AutomaticSize = Enum.AutomaticSize.Y
		marks.Size = UDim2.fromScale(1, 0)
		local marksList = list(marks, Enum.FillDirection.Vertical, s.markerGap)
		marksList.HorizontalAlignment = Enum.HorizontalAlignment.Center
	else
		marks.AutomaticSize = Enum.AutomaticSize.XY
		local marksList = list(marks, Enum.FillDirection.Horizontal, 6)
		marksList.VerticalAlignment = Enum.VerticalAlignment.Center
	end
	if s.tileHorizontal then
		local textX = s.tileBlock + s.tilePad
		pet.Position = UDim2.fromOffset(0, 0)
		label.Position = UDim2.fromOffset(textX, 0)
		label.Size = UDim2.new(1, -textX, 0, s.tileName)
		label.TextXAlignment = Enum.TextXAlignment.Left
		marks.Position = UDim2.fromOffset(textX, s.tileName + s.markerGap)
		marks.Size = UDim2.new(1, -textX, 0, 0)
	end
	return tile, marks
end

-- One marker line on a tile: full width, cut off with an ellipsis rather
-- than running out of the tile.
local function tileMarker(
	parent: Instance,
	s: PetsLayout.Sizes,
	text: string,
	color: Color3,
	order: number
)
	local line = Theme.text({
		name = "Marker",
		text = Theme.label(text),
		font = Theme.fonts.label,
		size = s.marker - 1,
		color = color,
		parent = parent,
	})
	line.LayoutOrder = order
	line.AutomaticSize = Enum.AutomaticSize.None
	line.Size = UDim2.new(1, 0, 0, s.marker)
	line.TextTruncate = Enum.TextTruncate.AtEnd
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

local function grid(parent: Instance, layout: PetsLayout.Layout): UIGridLayout
	local g = Instance.new("UIGridLayout")
	g.SortOrder = Enum.SortOrder.LayoutOrder
	g.CellPadding = UDim2.fromOffset(layout.sizes.tileGap, layout.sizes.tileGap)
	g.CellSize = UDim2.fromOffset(layout.tileWidth, layout.tileHeight)
	g.Parent = parent
	return g
end

local function place(object: GuiObject, r: PetsLayout.Rect, originX: number, originY: number)
	object.Position = UDim2.fromOffset(r.x - originX, r.y - originY)
	object.Size = UDim2.fromOffset(r.w, r.h)
end

-- Room around the tiles inside a scrolling grid, so the tutorial outline
-- around a tile is not cut off at the edges.
local function gridPad(scroll: ScrollingFrame, s: PetsLayout.Sizes)
	local p = scroll:FindFirstChild("GridPad") :: UIPadding?
	if p == nil then
		local made = Instance.new("UIPadding")
		made.Name = "GridPad"
		made.Parent = scroll
		p = made
	end
	local padding = p :: UIPadding
	padding.PaddingTop = UDim.new(0, s.gridPad)
	padding.PaddingBottom = UDim.new(0, s.gridPad)
	padding.PaddingLeft = UDim.new(0, s.gridPad)
	padding.PaddingRight = UDim.new(0, s.gridPad + s.scrollBar)
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
function Pets.mount(
	playerGui: PlayerGui,
	equip: RemoteFunction,
	unequip: RemoteFunction,
	equipBest: RemoteFunction,
	unequipAll: RemoteFunction
): ScreenGui
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
	Theme.panel(panel, sizes.radius + 2)

	-- Header: the three tabs and Close.
	local header = frame("Header", panel)
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

	-- The tutorial's line for this screen, right under the tabs. Showing or
	-- hiding it moves the body, so the layout is worked out again.
	local guideShown = false
	local applyLayout: () -> ()
	local guideBar = Guide.bar(panel, function(shown: boolean)
		if shown ~= guideShown then
			guideShown = shown
			if applyLayout ~= nil then
				applyLayout()
			end
		end
	end, function()
		return gui.AbsoluteSize.Y >= 560
	end)

	-- Body: content on the left, the detail panel on the right.
	local content = frame("Content", panel)
	local actions = frame("TeamActions", panel)
	local bestCoins = button("BestCoins", actions, "BEST COINS")
	local bestBattle = button("BestBattle", actions, "BEST BATTLE")
	local clearTeam = button("UnequipAll", actions, "UNEQUIP ALL")
	bestCoins.BackgroundColor3 = colors.gold
	bestCoins.TextColor3 = colors.panel
	local teamActions = { bestCoins, bestBattle, clearTeam }
	for position, b in teamActions do
		b.Position = UDim2.new((position - 1) / #teamActions, 3, 0, 0)
		b.Size = UDim2.new(1 / #teamActions, -6, 1, 0)
	end

	local detail = frame("Detail", panel)
	detail.BackgroundTransparency = 0
	detail.BackgroundColor3 = colors.raised
	Theme.panel(detail)
	-- The pet view and name, EQUIP right under them, then everything else
	-- in a scrolling area, so EQUIP never leaves the panel.
	local detailTop = frame("Top", detail)
	local equipSlot = frame("EquipSlot", detail)
	local detailScroll = scrolling("More", detail)

	-- My pets page: a hint line, the sort and filter controls, then the grid.
	local petsPage = frame("MyPets", content)
	petsPage.Size = UDim2.fromScale(1, 1)
	local hint = Theme.text({ name = "Hint", color = colors.muted, parent = petsPage })
	hint.AutomaticSize = Enum.AutomaticSize.None
	hint.TextXAlignment = Enum.TextXAlignment.Left
	hint.TextTruncate = Enum.TextTruncate.AtEnd
	local function control(name: string): TextButton
		local b = button(name, petsPage, "")
		b.TextSize = textSizes.small
		b.TextScaled = true
		b.TextTruncate = Enum.TextTruncate.AtEnd
		local limit = Instance.new("UITextSizeConstraint")
		limit.MaxTextSize = textSizes.small
		limit.MinTextSize = 8
		limit.Parent = b
		local p = Instance.new("UIPadding")
		p.PaddingLeft = UDim.new(0, 8)
		p.PaddingRight = UDim.new(0, 8)
		p.Parent = b
		return b
	end
	local controlButtons: { TextButton } = {}
	for _, name in PetsLayout.CONTROLS do
		table.insert(controlButtons, control(name))
	end
	local sortButton = controlButtons[1]
	local rarityButton = controlButtons[2]
	local typeButton = controlButtons[3]
	local eggButton = controlButtons[4]
	local searchRow = frame("SearchRow", petsPage)
	local search = Instance.new("TextBox")
	search.Name = "Search"
	search.BackgroundColor3 = colors.raised
	search.BorderSizePixel = 0
	search.ClearTextOnFocus = false
	search.FontFace = Theme.fonts.body
	search.TextColor3 = colors.text
	search.PlaceholderColor3 = colors.muted
	search.PlaceholderText = "Search name, type or variant..."
	search.Text = ""
	search.TextSize = textSizes.small + 1
	search.TextXAlignment = Enum.TextXAlignment.Left
	search.Size = UDim2.new(1, -86, 1, 0)
	search.Parent = searchRow
	Theme.panel(search)
	pad(search, 8)
	local filtersButton = button("Filters", searchRow, "FILTERS")
	filtersButton.AnchorPoint = Vector2.new(1, 0)
	filtersButton.Position = UDim2.fromScale(1, 0)
	filtersButton.Size = UDim2.new(0, 80, 1, 0)
	filtersButton.TextSize = textSizes.small
	local petsScroll = scrolling("Grid", petsPage)
	local emptyState = button("EmptyInventory", petsPage, "")
	emptyState.TextWrapped = true
	emptyState.TextSize = textSizes.body
	emptyState.Visible = false

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
	fruitNote.AutomaticSize = Enum.AutomaticSize.None
	fruitNote.TextXAlignment = Enum.TextXAlignment.Left
	fruitNote.TextTruncate = Enum.TextTruncate.AtEnd
	local fruitScroll = scrolling("Grid", fruitPage)

	-- The layout for the current screen size, worked out before first use.
	-- The parts a player with this many pets sees (PetsView.screenParts).
	local function currentParts()
		local payload = State.get()
		local owned = if payload ~= nil then ownedTable(payload.profile.pets) else {}
		return PetsView.screenParts(#PetsView.tiles(owned, {}))
	end
	local showFilters = false
	local layoutFilters = false
	local tab: Tab = "pets"
	local function computeLayout(): PetsLayout.Layout
		layoutFilters = showFilters
		local screen = gui.AbsoluteSize
		local width = if screen.X > 0 then screen.X else 1280
		local height = if screen.Y > 0 then screen.Y else 720
		local insets = HudInsets.read(Vector2.new(width, height))
		-- Few pets: bigger tiles and a narrower panel. The panel always keeps
		-- clear of the left menu, so EGGS and PETS stay pressable.
		return PetsLayout.compute(
			width,
			height,
			insets.top,
			guideShown and height >= 560,
			layoutFilters,
			{ few = not currentParts().filters, tools = true, actions = tab == "pets" }
		)
	end
	local layout: PetsLayout.Layout = computeLayout()

	local sortKey: PetsView.SortKey = PetsView.DEFAULT_SORT
	local filter: PetsView.Filter = {}
	local selected: Selection? = nil
	local message: string? = nil
	local busy = false
	local renderedGrid: string? = nil
	local lastState: string? = nil
	local ownedButtons: { [string]: TextButton } = {}
	-- Beginner detail: battle stats and moves stay behind a toggle.
	local battleOpen = false

	local render: () -> ()

	local function choose(choice: Selection)
		selected = choice
		message = nil
		render()
	end

	local function send(remote: RemoteFunction, choice: string?, success: string?)
		if busy then
			return
		end
		busy = true
		for _, b in teamActions do
			b.Active = false
			b.AutoButtonColor = false
		end
		local ok, reply = pcall(function(): any
			return remote:InvokeServer(choice)
		end)
		busy = false
		for _, b in teamActions do
			b.Active = true
			b.AutoButtonColor = true
		end
		if not ok or type(reply) ~= "table" then
			message = "The server did not answer. Try again."
		elseif reply.ok == true then
			message = success
		else
			message = PetsView.reasonText(reply.reason)
		end
		render()
	end

	local function renderDetail(teamUids: { [string]: boolean }, beginner: boolean)
		clear(detailTop)
		clear(equipSlot)
		clear(detailScroll)
		list(detailScroll, Enum.FillDirection.Vertical, 10)
		local s = layout.sizes
		local choice = selected
		if choice == nil then
			local empty = Theme.text({
				name = "Empty",
				text = "Pick a pet to see its stats and moves.",
				color = colors.muted,
				parent = detailTop,
			})
			empty.TextWrapped = true
			empty.AutomaticSize = Enum.AutomaticSize.None
			empty.Size = UDim2.fromScale(1, 1)
			empty.TextXAlignment = Enum.TextXAlignment.Left
			return
		end
		local payload = State.get()
		local info = PetsView.detail(
			choice.petId,
			choice.variant,
			PetsView.anchor(if payload then payload.profile.pets else {})
		)
		local parts = PetsView.detailParts(info, beginner, battleOpen)
		local pet = Config.petById[choice.petId]

		-- Top: the pet view and its name, with the markers beside it.
		local topList = list(detailTop, Enum.FillDirection.Horizontal, 12)
		topList.VerticalAlignment = Enum.VerticalAlignment.Center
		local big = block(detailTop, choice.petId, s.detailBlock, choice.variant)
		big.LayoutOrder = 1
		local bigStroke = Instance.new("UIStroke")
		bigStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		bigStroke.Thickness = 2
		bigStroke.Color = Theme.rarityColor(pet.rarity)
		bigStroke.Parent = big
		local words = frame("Words", detailTop)
		words.LayoutOrder = 2
		words.Size = UDim2.new(1, -(s.detailBlock + 12), 1, 0)
		local wordsList = list(words, Enum.FillDirection.Vertical, 2)
		wordsList.VerticalAlignment = Enum.VerticalAlignment.Center
		local nameLabel = Theme.text({
			name = "Name",
			text = Theme.label(info.name),
			font = Theme.fonts.heading,
			size = s.title,
			parent = words,
		})
		nameLabel.LayoutOrder = 1
		nameLabel.AutomaticSize = Enum.AutomaticSize.None
		nameLabel.Size = UDim2.new(1, 0, 0, s.title + 2)
		nameLabel.TextXAlignment = Enum.TextXAlignment.Left
		nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
		-- Two short lines, so the top stays inside its fixed height.
		local variantName = info.variantName
		local wordLines: { { text: string, color: Color3 } } = {
			{
				text = if variantName ~= nil
					then variantName .. "  " .. info.rarityName
					else info.rarityName,
				color = if variantName ~= nil then colors.gold else Theme.rarityColor(pet.rarity),
			},
			{
				text = parts.typeLine,
				color = colors.muted,
			},
		}
		for position, line in wordLines do
			local label = Theme.text({
				name = "Marker",
				text = Theme.label(line.text),
				font = Theme.fonts.label,
				size = s.small,
				color = line.color,
				parent = words,
			})
			label.LayoutOrder = position + 1
			label.AutomaticSize = Enum.AutomaticSize.None
			label.Size = UDim2.new(1, 0, 0, s.small + 2)
			label.TextXAlignment = Enum.TextXAlignment.Left
			label.TextTruncate = Enum.TextTruncate.AtEnd
		end

		-- EQUIP, at its fixed place right under the name.
		local uid = choice.uid
		if uid ~= nil then
			local equipped = teamUids[uid] == true
			local action =
				button("Equip", equipSlot, Theme.label(if equipped then "Unequip" else "Equip"))
			-- Inset in its slot, so the outline is never clipped and never
			-- touches the pet picture above.
			local inner = layout.equipButton
			action.Position = UDim2.fromOffset(inner.x - layout.equip.x, inner.y - layout.equip.y)
			action.Size = UDim2.fromOffset(inner.w, inner.h)
			if not equipped then
				-- The primary action: a filled gold button with dark text.
				action.BackgroundColor3 = colors.gold
				action.TextColor3 = colors.panel
				local stroke = action:FindFirstChildOfClass("UIStroke") :: UIStroke
				stroke.Color = colors.gold
				Pointer.register("equip", action)
			end
			action.Activated:Connect(function()
				-- The client never decides: both go to the server as they are.
				send(if equipped then unequip else equip, uid)
			end)
		else
			local note = Theme.text({
				name = "NotOwned",
				text = Theme.label("Not owned in this form"),
				font = Theme.fonts.label,
				size = textSizes.small,
				color = colors.muted,
				parent = equipSlot,
			})
			note.AutomaticSize = Enum.AutomaticSize.None
			note.Size = UDim2.fromScale(1, 1)
		end

		-- The rest scrolls: a refusal message first, then stats and moves.
		if message ~= nil then
			local note = Theme.text({
				name = "Message",
				text = message,
				color = colors.gold,
				parent = detailScroll,
			})
			note.LayoutOrder = 1
			note.TextWrapped = true
			note.AutomaticSize = Enum.AutomaticSize.Y
			note.Size = UDim2.new(1, -8, 0, 0)
		end

		local stats = frame("Stats", detailScroll)
		stats.LayoutOrder = 2
		stats.AutomaticSize = Enum.AutomaticSize.Y
		stats.Size = UDim2.new(1, -8, 0, 0)
		list(stats, Enum.FillDirection.Vertical, 0)
		for position, stat in parts.stats do
			local row = frame("Stat" .. position, stats)
			row.LayoutOrder = position
			-- Text size plus padding, so every label fits its row.
			row.Size = UDim2.new(1, 0, 0, PetsLayout.statRow(s))
			local rule = frame("Rule", row)
			rule.BackgroundTransparency = 0
			rule.BackgroundColor3 = colors.border
			rule.AnchorPoint = Vector2.new(0, 1)
			rule.Position = UDim2.fromScale(0, 1)
			rule.Size = UDim2.new(1, 0, 0, sizes.border)
			local name = Theme.text({
				name = "Label",
				text = stat.label,
				size = s.text,
				color = colors.muted,
				parent = row,
			})
			name.AnchorPoint = Vector2.new(0, 0.5)
			name.Position = UDim2.fromScale(0, 0.5)
			local value = Theme.text({
				name = "Value",
				text = stat.value,
				size = s.text,
				font = Theme.fonts.label,
				parent = row,
			})
			value.AnchorPoint = Vector2.new(1, 0.5)
			value.Position = UDim2.fromScale(1, 0.5)
		end

		local toggleText = parts.toggle
		if toggleText ~= nil then
			local toggle = button("BattleStats", detailScroll, Theme.label(toggleText))
			toggle.LayoutOrder = 3
			toggle.TextSize = s.small + 1
			toggle.TextColor3 = colors.muted
			toggle.Size = UDim2.new(1, -8, 0, s.small + 2 * s.statPad + 4)
			toggle.Activated:Connect(function()
				battleOpen = not battleOpen
				render()
			end)
		end
		if not parts.moves then
			return
		end

		local moves = frame("Moves", detailScroll)
		moves.LayoutOrder = 4
		moves.AutomaticSize = Enum.AutomaticSize.Y
		moves.Size = UDim2.new(1, -8, 0, 0)
		list(moves, Enum.FillDirection.Vertical, 4)
		for position, move in info.moves do
			local line = Theme.text({
				name = "Move" .. position,
				text = string.format("%s: %s", move.name, move.text),
				size = s.small + 1,
				parent = moves,
			})
			line.LayoutOrder = position
			line.TextWrapped = true
			line.TextXAlignment = Enum.TextXAlignment.Left
			line.AutomaticSize = Enum.AutomaticSize.Y
			line.Size = UDim2.fromScale(1, 0)
		end
	end

	local function indexTile(parent: Instance, tile: PetsView.IndexTile, order: number)
		local b, marks = tileButton(
			parent,
			layout.sizes,
			tile.petId,
			tile.petId,
			tile.rarity,
			order,
			not tile.seenAny,
			false,
			nil
		)
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

		-- With few pets: no filter row and no Index or Fruit Edition tabs.
		local parts = PetsView.screenParts(#PetsView.tiles(pets, {}))
		if table.find(parts.tabs, tab) == nil then
			tab = "pets"
		end
		local counts = PetsView.tabCounts(pets, index)
		local labels: { [Tab]: string } = {
			pets = string.format("My pets  %d", counts.owned),
			index = string.format("Index  %d/%d", counts.seen, counts.total),
			fruit = string.format("Fruit  %d/%d", counts.fruitSeen, counts.fruitTotal),
		}
		if gui.AbsoluteSize.X < 500 then
			labels.pets = string.format("Pets %d", counts.owned)
			labels.index = string.format("Index %d/%d", counts.seen, counts.total)
			labels.fruit = string.format("Fruit %d/%d", counts.fruitSeen, counts.fruitTotal)
		end
		for key, view in tabButtons do
			view.button.Visible = table.find(parts.tabs, key) ~= nil
			view.button.Text = Theme.label(labels[key])
			local active = key == tab
			view.button.TextColor3 = if active then colors.gold else colors.muted
			view.stroke.Color = if active then colors.gold else colors.border
		end
		petsPage.Visible = tab == "pets"
		indexScroll.Visible = tab == "index"
		fruitPage.Visible = tab == "fruit"
		actions.Visible = tab == "pets"

		-- A selected owned pet that is gone (traded, or a new save) clears.
		local tiles = PetsView.tiles(pets, team)
		local current = selected
		if tab == "pets" and current ~= nil and current.uid ~= nil then
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
		if selected == nil and tab == "pets" and #tiles > 0 then
			local first = PetsView.arrange(tiles, sortKey, filter)[1]
			if first ~= nil then
				selected = { uid = first.uid, petId = first.petId, variant = first.variant }
			end
		end
		if selected == nil and tab ~= "pets" then
			local first = if tab == "fruit"
				then PetsView.fruitTiles(index)[1]
				else PetsView.indexTiles(index)[1]
			if first ~= nil then
				selected = { petId = first.petId }
			end
		end
		-- Collection tiles name a pet and form, not one owned copy. Resolve a
		-- matching UID from this profile so the detail action can equip it.
		-- Prefer a copy already equipped; otherwise keep inventory order.
		if tab ~= "pets" and selected ~= nil then
			local choice = selected :: Selection
			local matchingUid: string? = nil
			for _, pet in pets do
				if
					type(pet) == "table"
					and pet.petId == choice.petId
					and pet.variant == choice.variant
					and type(pet.uid) == "string"
				then
					if matchingUid == nil then
						matchingUid = pet.uid
					end
					if teamUids[pet.uid] == true then
						matchingUid = pet.uid
						break
					end
				end
			end
			selected = { petId = choice.petId, variant = choice.variant, uid = matchingUid }
		end
		local stateKey = PetsView.signature(profile)
		local nextGrid = table.concat({
			stateKey,
			tab,
			sortKey,
			filter.rarity or "",
			filter.type or "",
			filter.egg or "",
			filter.query or "",
			tostring(layout.tileWidth),
			tostring(layout.sizes.tileBlock),
		}, ":")
		local rebuild = nextGrid ~= renderedGrid
		renderedGrid = nextGrid

		if tab == "pets" then
			local power = 0
			for _, tile in tiles do
				if tile.equipped then
					power += tile.clickPower
				end
			end
			hint.Text = message
				or string.format(
					"Team %d/%d  |  Click power +%s  |  %d pets",
					#team,
					Config.constants.team_size,
					PetsView.number(power),
					#tiles
				)
			hint.TextColor3 = if message ~= nil then colors.gold else colors.muted
			filtersButton.Text = if showFilters then "HIDE" else "FILTERS"
			sortButton.Text = Theme.label("Sort: " .. PetsView.SORT_NAMES[sortKey])
			rarityButton.Text =
				Theme.label("Rarity: " .. PetsView.filterName("rarity", filter.rarity))
			typeButton.Text = Theme.label("Type: " .. PetsView.filterName("type", filter.type))
			eggButton.Text = Theme.label("Egg: " .. PetsView.filterName("egg", filter.egg))
			local arranged = PetsView.arrange(tiles, sortKey, filter)
			emptyState.Visible = #arranged == 0
			emptyState.Text = if #tiles == 0
				then "Your team starts here.\nOpen EGGS to hatch your first pet."
				else "No pets match these filters.\nTap here to clear search and filters."
			if rebuild then
				clear(petsScroll)
				table.clear(ownedButtons)
				grid(petsScroll, layout)
				local s = layout.sizes
				for position, tile in arranged do
					local b, marks = tileButton(
						petsScroll,
						s,
						tile.uid,
						tile.petId,
						tile.rarity,
						position,
						false,
						true,
						tile.variant
					)
					ownedButtons[tile.uid] = b
					-- Each marker on its own line: "Click +3", variant, Equipped.
					tileMarker(marks, s, tile.clickPowerText, colors.muted, 1)
					if tile.variantName ~= nil then
						tileMarker(marks, s, tile.variantName, colors.gold, 2)
					end
					if tile.equipped then
						tileMarker(marks, s, "Equipped", colors.gold, 3)
					end
					if position == 1 then
						Pointer.register(FIRST_PET_TARGET, b)
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
			end
			for uid, b in ownedButtons do
				local chosen = selected
				local stroke = b:FindFirstChildOfClass("UIStroke") :: UIStroke
				stroke.Color = if chosen ~= nil and chosen.uid == uid
					then colors.gold
					else colors.border
			end
		elseif tab == "index" and rebuild then
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
				grid(cells, layout)
				for order, tile in row.tiles do
					indexTile(cells, tile, order)
				end
			end
		elseif tab == "fruit" and rebuild then
			clear(fruitScroll)
			grid(fruitScroll, layout)
			for order, tile in PetsView.fruitTiles(index) do
				indexTile(fruitScroll, tile, order)
			end
		end

		renderDetail(teamUids, PetsView.beginner(#tiles, Guide.reserved()))
		local now = selected
		Guide.setPetSelected(now ~= nil and now.uid ~= nil)
	end

	-- Places every part from PetsLayout for the current screen size and
	-- guide strip, then rebuilds the grids for the new tile size.
	applyLayout = function()
		layout = computeLayout()
		local l = layout
		local s = l.sizes
		local p = l.panel
		place(panel, p, 0, 0)
		place(header, l.header, p.x, p.y)
		local tabHeight = math.min(LAYOUT.tabHeight, s.header)
		for _, view in tabButtons do
			view.button.Size = UDim2.fromOffset(0, tabHeight)
			view.button.TextSize = if l.compact then textSizes.small + 1 else textSizes.button
		end
		close.Size =
			UDim2.fromOffset(if l.compact then 80 else 100, math.min(sizes.minTap, s.header))
		local portrait = gui.AbsoluteSize.X < 500
		tabsFrame.AnchorPoint = Vector2.new(0, if portrait then 0 else 0.5)
		tabsFrame.Position = if portrait then UDim2.fromOffset(0, 44) else UDim2.fromScale(0, 0.5)
		tabsFrame.Size = if portrait then UDim2.fromOffset(0, 32) else UDim2.fromScale(0, 1)
		close.Position = if portrait then UDim2.new(1, 0, 0, 18) else UDim2.fromScale(1, 0.5)
		if portrait then
			close.Size = UDim2.fromOffset(80, 36)
		end
		for _, view in tabButtons do
			local tabPad = view.button:FindFirstChildOfClass("UIPadding") :: UIPadding
			tabPad.PaddingLeft = UDim.new(0, if portrait then 4 else 16)
			tabPad.PaddingRight = tabPad.PaddingLeft
			view.button.AutomaticSize = if portrait
				then Enum.AutomaticSize.None
				else Enum.AutomaticSize.X
			if portrait then
				view.button.Size = UDim2.fromOffset(math.floor((l.header.w - 16) / 3), 32)
			end
		end
		local strip = l.guide
		guideBar.Visible = strip ~= nil
		if strip ~= nil then
			place(guideBar, strip, p.x, p.y)
		end
		local c = l.content
		place(content, c, p.x, p.y)
		if l.actions ~= nil then
			place(actions, l.actions, p.x, p.y)
		end
		if l.search ~= nil then
			place(searchRow, l.search, c.x, c.y)
		end
		local d = l.detail
		place(detail, d, p.x, p.y)
		place(detailTop, l.detailTop, d.x, d.y)
		place(equipSlot, l.equip, d.x, d.y)
		place(detailScroll, l.detailScroll, d.x, d.y)
		place(hint, l.hint, c.x, c.y)
		hint.TextSize = s.text
		for position, b in controlButtons do
			local r = l.controls[position]
			b.Visible = r ~= nil
			if r ~= nil then
				place(b, r, c.x, c.y)
			end
		end
		place(petsScroll, l.grid, c.x, c.y)
		place(emptyState, l.grid, c.x, c.y)
		place(fruitNote, l.hint, c.x, c.y)
		fruitNote.TextSize = s.text
		local fruitTop = l.hint.h + s.controlGap
		fruitScroll.Position = UDim2.fromOffset(0, fruitTop)
		fruitScroll.Size = UDim2.new(1, 0, 1, -fruitTop)
		gridPad(petsScroll, s)
		gridPad(fruitScroll, s)
		renderedGrid = nil
		render()
	end

	bestCoins.Activated:Connect(function()
		send(equipBest, "coins", "Best coin team equipped.")
	end)
	bestBattle.Activated:Connect(function()
		send(equipBest, "battle", "Recommended battle team equipped. Type matchups still matter.")
	end)
	clearTeam.Activated:Connect(function()
		send(unequipAll, nil, "Team cleared. Pets stay in your inventory.")
	end)
	search:GetPropertyChangedSignal("Text"):Connect(function()
		filter.query = search.Text
		petsScroll.CanvasPosition = Vector2.zero
		render()
	end)
	filtersButton.Activated:Connect(function()
		showFilters = not showFilters
		applyLayout()
	end)
	emptyState.Activated:Connect(function()
		local payload = State.get()
		if payload ~= nil and #ownedTable(payload.profile.pets) == 0 then
			gui.Enabled = false
			Screens.open(Screens.names.Eggs)
		else
			filter = {}
			search.Text = ""
			render()
		end
	end)

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
			selected = nil
			message = nil
			battleOpen = false
			applyLayout()
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
		battleOpen = false
		renderedGrid = nil
		gui.Enabled = true
		applyLayout()
	end

	local function relayout()
		if gui.Enabled then
			applyLayout()
		end
	end
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(relayout)
	HudInsets.onChange(relayout)
	applyLayout()
	gui.Parent = playerGui
	State.subscribe(function(payload)
		local key = PetsView.signature(payload.profile)
		if gui.Enabled and key ~= lastState then
			lastState = key
			render()
		end
	end)
	Screens.track(gui)
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
