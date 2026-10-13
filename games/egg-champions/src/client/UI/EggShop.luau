--!strict
--[[
	EggShop: where coins become pets, built to match design/ui/EggShop.dc.html.

	- One card per egg, in config order (shared/ui/EggShopView decides what each
	  card says), so a new egg needs no code change.
	- Each card lists its five pets with rarity and hatch chance. The chances
	  are the table the server rolls with, so the screen cannot drift from the
	  roll.
	- A locked egg says what unlocks it. An egg the player cannot afford shows
	  its price muted. Both buttons still send the request: the client only
	  hints, the server decides and its refusal is shown as a readable message.
	- Hatch sends BuyEgg with the egg id and a count of 1. Hatch x3 sends the
	  triple count and is only offered when the server reports the Triple Hatch
	  pass. Neither ever sends a price.
	- The result panel shows what hatched, its rarity and its variant, straight
	  from the server's reply. Effects.playHatch then plays the hatch sequence
	  over the screen for the same reply; it is skippable by tapping, and the
	  result panel underneath already holds the answer.

	EggShop.openAt(eggId) opens the screen scrolled to that egg's card, for the
	egg stands in the world.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local PetVisual = require(Shared:WaitForChild("PetVisual"))
local uiShared = Shared:WaitForChild("ui")
local Format = require(uiShared:WaitForChild("Format"))
local EggShopView = require(uiShared:WaitForChild("EggShopView"))
local NextGoal = require(uiShared:WaitForChild("NextGoal"))

local Theme = require(script.Parent:WaitForChild("Theme"))
local Screens = require(script.Parent:WaitForChild("Screens"))
local Effects =
	require((script.Parent :: Instance).Parent:WaitForChild("Effects"):WaitForChild("Effects"))
local State = require(script.Parent:WaitForChild("State"))

local colors = Theme.colors
local sizes = Theme.sizes
local textSizes = Theme.textSizes

-- Layout of the mockup, in pixels at 1280 x 720.
local LAYOUT = table.freeze({
	panelWidth = 1080,
	panelHeight = 0.9,
	padding = 28,
	gap = 20,
	cardPadding = 20,
	cardHeight = 380,
	eggWidth = 72,
	eggHeight = 92,
	eggStroke = 3,
	oddsRow = 30,
	buttonHeight = 52,
	tripleWidth = 150,
	headerHeight = 56,
	resultHeight = 84,
	resultBlock = 44,
	title = 34,
	cardTitle = 28,
	priceSize = 18,
	odds = 16,
})

local EggShop = {}

-- Set by mount.
local opener: ((string?) -> ())? = nil
local shown: (() -> boolean)? = nil

type CardView = {
	frame: Frame,
	price: TextLabel,
	lock: TextLabel,
	names: { TextLabel },
	odds: { TextLabel },
	hatch: TextButton,
	hatchStroke: UIStroke,
	triple: TextButton,
	tripleStroke: UIStroke,
}

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

local function button(name: string, parent: Instance): (TextButton, UIStroke)
	local b = Instance.new("TextButton")
	b.Name = name
	b.AutoButtonColor = true
	b.BorderSizePixel = 0
	b.FontFace = Theme.fonts.label
	b.TextSize = textSizes.button
	b.Parent = parent
	Theme.panel(b, sizes.radius)
	return b, b:FindFirstChildOfClass("UIStroke") :: UIStroke
end

-- The three looks a button can have: the green Hatch, the gold accent, and
-- muted for a hint that the server will likely refuse.
type Look = "hatch" | "accent" | "muted"

local function style(b: TextButton, stroke: UIStroke, look: Look)
	if look == "hatch" then
		b.BackgroundColor3 = colors.hatch
		b.TextColor3 = colors.white
		stroke.Transparency = 1
	elseif look == "accent" then
		b.BackgroundColor3 = colors.raised
		b.TextColor3 = colors.gold
		stroke.Color = colors.gold
		stroke.Transparency = 0
	else
		b.BackgroundColor3 = colors.panel
		b.TextColor3 = colors.muted
		stroke.Color = colors.border
		stroke.Transparency = 0
	end
end

-- The egg shell is tinted by the type of the egg's most common pet, until the
-- asset stage gives eggs their own look.
local function shellColor(eggId: string): Color3
	local best: Config.Pet? = nil
	for _, pet in Config.pets do
		if pet.egg == eggId then
			local order = Config.rarityById[pet.rarity].order
			if best == nil or order < Config.rarityById[best.rarity].order then
				best = pet
			end
		end
	end
	return if best ~= nil then Theme.typeColor(best.type) else colors.muted
end

local function number(value: any): number
	return if type(value) == "number" then value else 0
end

local function flags(value: any): { [string]: boolean }
	return if type(value) == "table" then value else {}
end

-- Builds the screen under playerGui. Call once.
function EggShop.mount(playerGui: PlayerGui, buyEgg: RemoteFunction): ScreenGui
	local gui = Instance.new("ScreenGui")
	gui.Name = "EggShop"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = 10
	gui.Enabled = false

	-- Dims the world and swallows presses, so shopping never earns clicks.
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
	panel.Size = UDim2.fromScale(0.92, LAYOUT.panelHeight)
	local limit = Instance.new("UISizeConstraint")
	limit.MaxSize = Vector2.new(LAYOUT.panelWidth, math.huge)
	limit.Parent = panel
	Theme.panel(panel, sizes.radius + 2)
	pad(panel, LAYOUT.padding)

	-- Header: world name, title, coins and Close.
	local header = frame("Header", panel)
	header.Size = UDim2.new(1, 0, 0, LAYOUT.headerHeight)
	local titles = frame("Titles", header)
	titles.AutomaticSize = Enum.AutomaticSize.XY
	list(titles, Enum.FillDirection.Vertical, 0)
	local worldLabel = Theme.text({
		name = "World",
		font = Theme.fonts.label,
		size = textSizes.small,
		color = colors.muted,
		parent = titles,
	})
	worldLabel.LayoutOrder = 1
	Theme.text({
		name = "Title",
		text = Theme.label("Eggs"),
		font = Theme.fonts.heading,
		size = LAYOUT.title,
		parent = titles,
	}).LayoutOrder =
		2

	local right = frame("Right", header)
	right.AnchorPoint = Vector2.new(1, 0.5)
	right.Position = UDim2.fromScale(1, 0.5)
	right.AutomaticSize = Enum.AutomaticSize.XY
	local rightList = list(right, Enum.FillDirection.Horizontal, 16)
	rightList.VerticalAlignment = Enum.VerticalAlignment.Center
	local coin = frame("Coin", right)
	coin.LayoutOrder = 1
	coin.BackgroundTransparency = 0
	coin.BackgroundColor3 = colors.gold
	coin.Size = UDim2.fromOffset(sizes.coin - 4, sizes.coin - 4)
	local round = Instance.new("UICorner")
	round.CornerRadius = UDim.new(0.5, 0)
	round.Parent = coin
	local coinsLabel = Theme.text({
		name = "Coins",
		text = "0",
		font = Theme.fonts.heading,
		size = textSizes.coins - 8,
		parent = right,
	})
	coinsLabel.LayoutOrder = 2
	local close, closeStroke = button("Close", right)
	close.LayoutOrder = 3
	close.Text = Theme.label("Close")
	close.AutomaticSize = Enum.AutomaticSize.X
	close.Size = UDim2.fromOffset(0, sizes.minTap)
	pad(close, 0)
	local closePad = close:FindFirstChildOfClass("UIPadding") :: UIPadding
	closePad.PaddingLeft = UDim.new(0, 18)
	closePad.PaddingRight = UDim.new(0, 18)
	style(close, closeStroke, "muted")
	close.TextColor3 = colors.text
	close.BackgroundColor3 = colors.raised

	-- Result strip: what the server says hatched, or why it refused.
	local result = frame("Result", panel)
	result.Position = UDim2.fromOffset(0, LAYOUT.headerHeight + LAYOUT.gap)
	result.Size = UDim2.new(1, 0, 0, LAYOUT.resultHeight)
	result.BackgroundTransparency = 0
	result.BackgroundColor3 = colors.raised
	result.Visible = false
	Theme.panel(result)
	pad(result, 12)
	local resultList = list(result, Enum.FillDirection.Horizontal, 12)
	resultList.VerticalAlignment = Enum.VerticalAlignment.Center

	-- The cards, two per row, scrolling when there are more than fit.
	local footerHeight = textSizes.body + 8
	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "Cards"
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 6
	scroll.ScrollBarImageColor3 = colors.border
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.CanvasSize = UDim2.new()
	scroll.Parent = panel
	local grid = Instance.new("UIGridLayout")
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.CellPadding = UDim2.fromOffset(LAYOUT.gap, LAYOUT.gap)
	grid.CellSize = UDim2.new(0.5, -LAYOUT.gap, 0, LAYOUT.cardHeight)
	grid.Parent = scroll

	local footer = Theme.text({
		name = "Note",
		text = EggShopView.variantNote(),
		color = colors.muted,
		parent = panel,
	})
	footer.AnchorPoint = Vector2.new(0, 1)
	footer.Position = UDim2.fromScale(0, 1)
	footer.AutomaticSize = Enum.AutomaticSize.None
	footer.Size = UDim2.new(1, 0, 0, footerHeight)
	footer.TextWrapped = true
	footer.TextXAlignment = Enum.TextXAlignment.Left

	local function fitScroll()
		local top = LAYOUT.headerHeight + LAYOUT.gap
		if result.Visible then
			top += LAYOUT.resultHeight + LAYOUT.gap
		end
		scroll.Position = UDim2.fromOffset(0, top)
		scroll.Size = UDim2.new(1, 0, 1, -(top + footerHeight + LAYOUT.gap))
	end
	fitScroll()

	local cards: { [string]: CardView } = {}
	local busy = false
	local ownsTriple = false

	local function clearResult()
		for _, child in result:GetChildren() do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
	end

	local function showMessage(text: string)
		clearResult()
		local message = Theme.text({ name = "Message", text = text, parent = result })
		message.TextWrapped = true
		result.Visible = true
		fitScroll()
	end

	local function showHatched(reply: any)
		clearResult()
		local lines = EggShopView.hatchLines(reply)
		if #lines == 0 then
			showMessage("The shop answered, but nothing hatched.")
			return
		end
		local heading = Theme.text({
			name = "Heading",
			text = Theme.label("Hatched"),
			font = Theme.fonts.label,
			size = textSizes.small,
			color = colors.muted,
			parent = result,
		})
		heading.LayoutOrder = 0
		for position, line in lines do
			local pet = Config.petById[line.petId]
			local entry = frame("Pet" .. position, result)
			entry.LayoutOrder = position
			entry.AutomaticSize = Enum.AutomaticSize.XY
			local entryList = list(entry, Enum.FillDirection.Horizontal, 10)
			entryList.VerticalAlignment = Enum.VerticalAlignment.Center
			local block = frame("Block", entry)
			block.LayoutOrder = 1
			block.BackgroundTransparency = 0
			block.BackgroundColor3 = colors.panel
			block.Size = UDim2.fromOffset(LAYOUT.resultBlock, LAYOUT.resultBlock)
			local blockCorner = Instance.new("UICorner")
			blockCorner.CornerRadius = UDim.new(0, sizes.slotRadius)
			blockCorner.Parent = block
			local stroke = Instance.new("UIStroke")
			stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
			stroke.Thickness = 2
			stroke.Color = Theme.rarityColor(line.rarity)
			stroke.Parent = block
			PetVisual.view(block, pet.id, line.variant, nil)
			local words = frame("Words", entry)
			words.LayoutOrder = 2
			words.AutomaticSize = Enum.AutomaticSize.XY
			list(words, Enum.FillDirection.Vertical, 0)
			Theme.text({
				name = "Name",
				text = line.name,
				font = Theme.fonts.label,
				size = textSizes.petName,
				parent = words,
			}).LayoutOrder =
				1
			local detail = Theme.label(line.rarityName)
			if line.variantName ~= nil then
				detail = Theme.label(line.variantName) .. " " .. detail
			end
			if line.newInIndex then
				detail ..= "  " .. Theme.label("New")
			end
			Theme.text({
				name = "Rarity",
				text = detail,
				font = Theme.fonts.label,
				size = textSizes.small,
				color = if line.variantName ~= nil
					then colors.gold
					else Theme.rarityColor(line.rarity),
				parent = words,
			}).LayoutOrder =
				2
		end
		result.Visible = true
		fitScroll()
	end

	local function buy(eggId: string, count: number)
		if busy then
			return
		end
		busy = true
		local ok, reply = pcall(function(): any
			return buyEgg:InvokeServer(eggId, count)
		end)
		busy = false
		if not ok or type(reply) ~= "table" then
			showMessage("The shop did not answer. Try again.")
		elseif reply.ok == true then
			showHatched(reply)
			-- Visuals only: the server already decided what hatched.
			busy = true
			Effects.playHatch(gui, shellColor(eggId), EggShopView.hatchLines(reply), function()
				busy = false
			end)
		else
			showMessage(EggShopView.reasonText(reply.reason))
		end
	end

	local function buildCard(egg: Config.Egg, position: number): CardView
		local card = frame(egg.id, scroll)
		card.LayoutOrder = position
		card.BackgroundTransparency = 0
		card.BackgroundColor3 = colors.raised
		Theme.panel(card)
		pad(card, LAYOUT.cardPadding)
		list(card, Enum.FillDirection.Vertical, 14)

		local top = frame("Top", card)
		top.LayoutOrder = 1
		top.Size = UDim2.new(1, 0, 0, LAYOUT.eggHeight)
		local topList = list(top, Enum.FillDirection.Horizontal, 16)
		topList.VerticalAlignment = Enum.VerticalAlignment.Center
		local shell = frame("Egg", top)
		shell.LayoutOrder = 1
		shell.BackgroundTransparency = 0
		shell.BackgroundColor3 = shellColor(egg.id)
		shell.Size = UDim2.fromOffset(LAYOUT.eggWidth, LAYOUT.eggHeight)
		local shellCorner = Instance.new("UICorner")
		shellCorner.CornerRadius = UDim.new(0.5, 0)
		shellCorner.Parent = shell
		local shellStroke = Instance.new("UIStroke")
		shellStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		shellStroke.Thickness = LAYOUT.eggStroke
		shellStroke.Color = colors.border
		shellStroke.Parent = shell

		local words = frame("Words", top)
		words.LayoutOrder = 2
		words.AutomaticSize = Enum.AutomaticSize.XY
		list(words, Enum.FillDirection.Vertical, 2)
		Theme.text({
			name = "Name",
			text = Theme.label(egg.name),
			font = Theme.fonts.heading,
			size = LAYOUT.cardTitle,
			parent = words,
		}).LayoutOrder =
			1
		local priceLabel = Theme.text({
			name = "Price",
			font = Theme.fonts.label,
			size = LAYOUT.priceSize,
			color = colors.gold,
			parent = words,
		})
		priceLabel.LayoutOrder = 2
		local lock = Theme.text({
			name = "Lock",
			font = Theme.fonts.label,
			size = textSizes.small,
			color = colors.muted,
			parent = words,
		})
		lock.LayoutOrder = 3

		local oddsFrame = frame("Odds", card)
		oddsFrame.LayoutOrder = 2
		oddsFrame.AutomaticSize = Enum.AutomaticSize.Y
		oddsFrame.Size = UDim2.fromScale(1, 0)
		list(oddsFrame, Enum.FillDirection.Vertical, 0)
		local names: { TextLabel } = {}
		local odds: { TextLabel } = {}
		for row = 1, #Config.rarities do
			local line = frame("Row" .. row, oddsFrame)
			line.LayoutOrder = row
			line.Size = UDim2.new(1, 0, 0, LAYOUT.oddsRow)
			if row < #Config.rarities then
				local rule = frame("Rule", line)
				rule.BackgroundTransparency = 0
				rule.BackgroundColor3 = colors.border
				rule.AnchorPoint = Vector2.new(0, 1)
				rule.Position = UDim2.fromScale(0, 1)
				rule.Size = UDim2.new(1, 0, 0, sizes.border)
			end
			local nameLabel = Theme.text({ name = "Pet", size = LAYOUT.odds, parent = line })
			nameLabel.AnchorPoint = Vector2.new(0, 0.5)
			nameLabel.Position = UDim2.fromScale(0, 0.5)
			local chanceLabel = Theme.text({ name = "Chance", size = LAYOUT.odds, parent = line })
			chanceLabel.AnchorPoint = Vector2.new(1, 0.5)
			chanceLabel.Position = UDim2.fromScale(1, 0.5)
			table.insert(names, nameLabel)
			table.insert(odds, chanceLabel)
		end

		local buttons = frame("Buttons", card)
		buttons.LayoutOrder = 3
		buttons.Size = UDim2.new(1, 0, 0, LAYOUT.buttonHeight)
		local hatch, hatchStroke = button("Hatch", buttons)
		hatch.Size = UDim2.new(1, -(LAYOUT.tripleWidth + 10), 1, 0)
		local triple, tripleStroke = button("HatchTriple", buttons)
		triple.AnchorPoint = Vector2.new(1, 0)
		triple.Position = UDim2.fromScale(1, 0)
		triple.Size = UDim2.new(0, LAYOUT.tripleWidth, 1, 0)
		triple.Text = Theme.label(string.format("Hatch x%d", EggShopView.TRIPLE_COUNT))

		local eggId = egg.id
		hatch.Activated:Connect(function()
			buy(eggId, 1)
		end)
		triple.Activated:Connect(function()
			if ownsTriple then
				buy(eggId, EggShopView.TRIPLE_COUNT)
			else
				showMessage(EggShopView.reasonText("no_triple_hatch_pass"))
			end
		end)

		return {
			frame = card,
			price = priceLabel,
			lock = lock,
			names = names,
			odds = odds,
			hatch = hatch,
			hatchStroke = hatchStroke,
			triple = triple,
			tripleStroke = tripleStroke,
		}
	end

	for position, egg in Config.eggs do
		cards[egg.id] = buildCard(egg, position)
	end

	local function render(payload: State.Payload?)
		local profile = if payload ~= nil then payload.profile else {}
		local derived = if payload ~= nil then payload.derived else {}
		local passes = flags(derived.hatchPasses)
		ownsTriple = passes.tripleHatch == true
		local coins = number(profile.coins)
		coinsLabel.Text = Format.commas(coins)
		local gymsBeaten = flags(profile.gymsBeaten)
		local world = NextGoal.currentWorld({
			coins = coins,
			rebirths = number(profile.rebirths),
			index = flags(profile.index),
			gymsBeaten = gymsBeaten,
			feesPaid = flags(profile.feesPaid),
		})
		worldLabel.Text = Theme.label(world.name)

		local state: EggShopView.State = { coins = coins, gymsBeaten = gymsBeaten }
		for _, data in EggShopView.cards(state, { luckyEggs = passes.luckyEggs == true }) do
			local view = cards[data.eggId]
			view.price.Text = data.priceText
			view.price.TextColor3 = if data.affordable and not data.locked
				then colors.gold
				else colors.muted
			view.lock.Text = if data.locked and data.unlockText ~= nil
				then Theme.label(data.unlockText)
				else ""
			view.lock.Visible = data.locked
			for row, line in data.pets do
				local nameLabel = view.names[row]
				local chanceLabel = view.odds[row]
				if nameLabel ~= nil and chanceLabel ~= nil then
					nameLabel.Text = line.name
					chanceLabel.Text = string.format("%s %s", line.rarityName, line.chanceText)
					chanceLabel.TextColor3 = Theme.rarityColor(line.rarity)
				end
			end
			-- Hints only: every button still sends, and the server decides.
			if data.locked then
				view.hatch.Text = Theme.label("Locked")
				style(view.hatch, view.hatchStroke, "muted")
			elseif not data.affordable then
				view.hatch.Text =
					Theme.label(string.format("Need %s more", Format.commas(data.short)))
				style(view.hatch, view.hatchStroke, "muted")
			else
				view.hatch.Text = Theme.label("Hatch")
				style(view.hatch, view.hatchStroke, "hatch")
			end
			local tripleReady = ownsTriple
				and not data.locked
				and coins >= data.price * EggShopView.TRIPLE_COUNT
			style(view.triple, view.tripleStroke, if tripleReady then "accent" else "muted")
		end
	end

	local function hide()
		gui.Enabled = false
	end

	-- Scrolls so the card of eggId sits at the top of the list.
	local function scrollTo(eggId: string?)
		if eggId == nil or cards[eggId] == nil then
			scroll.CanvasPosition = Vector2.zero
			return
		end
		-- Wait a frame so the grid has laid out the newly shown cards.
		RunService.Heartbeat:Wait()
		local card = cards[eggId].frame
		local offset = card.AbsolutePosition.Y - scroll.AbsolutePosition.Y + scroll.CanvasPosition.Y
		scroll.CanvasPosition = Vector2.new(0, math.max(0, offset))
	end

	opener = function(eggId: string?)
		if not gui.Enabled then
			clearResult()
			result.Visible = false
			fitScroll()
		end
		render(State.get())
		gui.Enabled = true
		task.spawn(scrollTo, eggId)
	end

	close.Activated:Connect(hide)
	backdrop.Activated:Connect(hide)

	render(nil)
	gui.Parent = playerGui
	State.subscribe(render)
	Screens.register(Screens.names.Eggs, function()
		EggShop.openAt(nil)
	end)
	shown = function(): boolean
		return gui.Enabled
	end
	return gui
end

-- Opens the screen, scrolled to eggId's card when given. Does nothing before
-- mount.
function EggShop.openAt(eggId: string?)
	if opener ~= nil then
		opener(eggId)
	end
end

function EggShop.isOpen(): boolean
	return shown ~= nil and shown()
end

return EggShop
