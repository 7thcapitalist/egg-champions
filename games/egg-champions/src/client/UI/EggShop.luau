--!strict
--[[
	EggShop: where coins become pets, built to match design/ui/EggShop.dc.html.

	- One card per egg of an unlocked world, in config order, plus the next
	  locked egg as a teaser (shared/ui/EggShopView.shownCards decides), so a
	  new egg needs no code change.
	- Where everything sits comes from shared/ui/EggShopLayout, whose specs
	  check that HATCH is visible without scrolling at 808 x 432 and
	  1280 x 720. The panel starts below the Roblox top bar (GuiService inset)
	  and the HUD top bar.
	- The top of each card holds the egg's real model (ReplicatedStorage.
	  PetModels, named by egg id; a flat placeholder until it loads), name,
	  price, HATCH and HATCH X3. The five pets with rarity and hatch chance
	  sit behind "Show odds". The chances are the table the server rolls
	  with, so the screen cannot drift from the roll.
	- A locked egg says what unlocks it. An egg the player cannot afford shows
	  its price muted. Both buttons still send the request: the client only
	  hints, the server decides and its refusal is shown as a readable message.
	- Hatch sends BuyEgg with the egg id and a count of 1. Hatch x3 sends the
	  triple count and is only offered when the server reports the Triple Hatch
	  pass. Neither ever sends a price.
	- The result overlays the card's egg and name area (never its buttons) and
	  shows what hatched, its rarity and its variant, straight from the
	  server's reply, or why the server refused. The list never moves, so the
	  scroll position is kept. Effects.playHatch then plays the hatch sequence
	  over the screen for the same reply; it is skippable by tapping, and the
	  result underneath already holds the answer. Tapping the result hides it.

	EggShop.openAt(eggId) opens the screen scrolled to that egg's card, for the
	egg stands in the world.
]]

local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local PetVisual = require(Shared:WaitForChild("PetVisual"))
local uiShared = Shared:WaitForChild("ui")
local Format = require(uiShared:WaitForChild("Format"))
local EggShopView = require(uiShared:WaitForChild("EggShopView"))
local EggShopLayout = require(uiShared:WaitForChild("EggShopLayout"))
local HudLayout = require(uiShared:WaitForChild("HudLayout"))
local NextGoal = require(uiShared:WaitForChild("NextGoal"))

local Theme = require(script.Parent:WaitForChild("Theme"))
local Pointer = require(script.Parent:WaitForChild("Pointer"))
local Screens = require(script.Parent:WaitForChild("Screens"))
local Effects =
	require((script.Parent :: Instance).Parent:WaitForChild("Effects"):WaitForChild("Effects"))
local State = require(script.Parent:WaitForChild("State"))

local colors = Theme.colors
local sizes = Theme.sizes
local textSizes = Theme.textSizes

local EggShop = {}

-- Where the asset stage puts each egg's model, named by egg id.
local MODELS_FOLDER = "PetModels"
-- How the egg model is framed in its card: camera field of view in degrees,
-- and the share of room left around the model. Display only.
local EGG_FOV = 30
local EGG_FRAME = 1.15

-- Set by mount.
local opener: ((string?) -> ())? = nil
local shown: (() -> boolean)? = nil

type CardView = {
	frame: Frame,
	eggSlot: Frame,
	words: Frame,
	name: TextLabel,
	price: TextLabel,
	lock: TextLabel,
	names: { TextLabel },
	odds: { TextLabel },
	oddsPanel: Frame,
	toggle: TextButton,
	result: TextButton,
	hatch: TextButton,
	hatchStroke: UIStroke,
	triple: TextButton,
	tripleStroke: UIStroke,
}

-- Draw order inside a card: the result and odds overlays sit over the egg,
-- name and buttons.
local Z_OVERLAY = 5

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

local function place(object: GuiObject, r: EggShopLayout.Rect, originX: number, originY: number)
	object.Position = UDim2.fromOffset(r.x - originX, r.y - originY)
	object.Size = UDim2.fromOffset(r.w, r.h)
end

-- The egg in a card: its real model from PetModels in a ViewportFrame, or a
-- flat oval placeholder until the asset stage has loaded it.
local function eggView(slot: Frame, eggId: string)
	for _, child in slot:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	local folder = ReplicatedStorage:FindFirstChild(MODELS_FOLDER)
	local template = if folder ~= nil then folder:FindFirstChild(eggId) else nil
	if template ~= nil and template:IsA("Model") then
		local viewport = Instance.new("ViewportFrame")
		viewport.Name = "EggView"
		viewport.BackgroundTransparency = 1
		viewport.BorderSizePixel = 0
		viewport.Size = UDim2.fromScale(1, 1)
		viewport.Ambient = Color3.fromRGB(200, 200, 200)
		viewport.LightColor = Color3.fromRGB(255, 255, 255)
		viewport.LightDirection = Vector3.new(-1, -1, -1)
		local model = (template :: Model):Clone()
		for _, item in model:GetDescendants() do
			if item:IsA("BasePart") then
				item.Anchored = true
			end
		end
		model:PivotTo(CFrame.new())
		local box, extents = model:GetBoundingBox()
		model:PivotTo(box:Inverse() * model:GetPivot())
		model.Parent = viewport
		local camera = Instance.new("Camera")
		camera.FieldOfView = EGG_FOV
		local radius = extents.Magnitude / 2
		local distance = radius / math.tan(math.rad(EGG_FOV / 2)) * EGG_FRAME
		camera.CFrame = CFrame.lookAt(Vector3.new(0, radius * 0.3, distance), Vector3.zero)
		camera.Parent = viewport
		viewport.CurrentCamera = camera
		viewport.Parent = slot
		return
	end
	local shell = frame("EggShell", slot)
	shell.BackgroundTransparency = 0
	shell.BackgroundColor3 = shellColor(eggId)
	shell.AnchorPoint = Vector2.new(0.5, 0.5)
	shell.Position = UDim2.fromScale(0.5, 0.5)
	shell.Size = UDim2.fromScale(0.78, 1)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = shell
	local stroke = Instance.new("UIStroke")
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Thickness = 2
	stroke.Color = colors.border
	stroke.Parent = shell
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
	Theme.panel(panel, sizes.radius + 2)

	-- Header: world name, title, coins and Close.
	local header = frame("Header", panel)
	local titles = frame("Titles", header)
	titles.AnchorPoint = Vector2.new(0, 0.5)
	titles.Position = UDim2.fromScale(0, 0.5)
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
	local titleLabel = Theme.text({
		name = "Title",
		text = Theme.label("Eggs"),
		font = Theme.fonts.heading,
		parent = titles,
	})
	titleLabel.LayoutOrder = 2

	local right = frame("Right", header)
	right.AnchorPoint = Vector2.new(1, 0.5)
	right.Position = UDim2.fromScale(1, 0.5)
	right.AutomaticSize = Enum.AutomaticSize.XY
	local rightList = list(right, Enum.FillDirection.Horizontal, 12)
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
		size = textSizes.heading,
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

	-- The cards, two per row, scrolling when there are more than fit. Nothing
	-- above the list ever changes height, so the scroll position is kept.
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
	grid.Parent = scroll

	local footer = Theme.text({
		name = "Note",
		text = EggShopView.variantNote(),
		size = textSizes.small,
		color = colors.muted,
		parent = panel,
	})
	footer.AutomaticSize = Enum.AutomaticSize.None
	footer.TextTruncate = Enum.TextTruncate.AtEnd
	footer.TextXAlignment = Enum.TextXAlignment.Left
	footer.TextYAlignment = Enum.TextYAlignment.Center

	local cards: { [string]: CardView } = {}
	local busy = false
	local ownsTriple = false
	local layout: EggShopLayout.Layout? = nil

	local function clearResult(view: CardView)
		for _, child in view.result:GetChildren() do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
		view.result.Visible = false
	end

	local function clearResults()
		for _, view in cards do
			clearResult(view)
		end
	end

	local function showMessage(eggId: string, text: string)
		local view = cards[eggId]
		if view == nil then
			return
		end
		clearResults()
		local message = Theme.text({
			name = "Message",
			text = text,
			size = textSizes.small,
			parent = view.result,
		})
		message.AutomaticSize = Enum.AutomaticSize.None
		message.Size = UDim2.fromScale(1, 1)
		message.TextWrapped = true
		message.ZIndex = Z_OVERLAY + 1
		view.result.Visible = true
	end

	local function showHatched(eggId: string, reply: any)
		local view = cards[eggId]
		if view == nil then
			return
		end
		local lines = EggShopView.hatchLines(reply)
		if #lines == 0 then
			showMessage(eggId, "The shop answered, but nothing hatched.")
			return
		end
		clearResults()
		local s = (layout :: EggShopLayout.Layout).sizes
		for position, line in lines do
			local pet = Config.petById[line.petId]
			local entry = frame("Pet" .. position, view.result)
			entry.LayoutOrder = position
			entry.AutomaticSize = Enum.AutomaticSize.XY
			local entryList = list(entry, Enum.FillDirection.Horizontal, 6)
			entryList.VerticalAlignment = Enum.VerticalAlignment.Center
			local block = frame("Block", entry)
			block.LayoutOrder = 1
			block.BackgroundTransparency = 0
			block.BackgroundColor3 = colors.panel
			block.Size = UDim2.fromOffset(s.resultBlock, s.resultBlock)
			block.ZIndex = Z_OVERLAY + 1
			local blockCorner = Instance.new("UICorner")
			blockCorner.CornerRadius = UDim.new(0, sizes.slotRadius)
			blockCorner.Parent = block
			local stroke = Instance.new("UIStroke")
			stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
			stroke.Thickness = 2
			stroke.Color = Theme.rarityColor(line.rarity)
			stroke.Parent = block
			PetVisual.view(block, pet.id, line.variant, nil).ZIndex = Z_OVERLAY + 2
			local words = frame("Words", entry)
			words.LayoutOrder = 2
			words.AutomaticSize = Enum.AutomaticSize.XY
			list(words, Enum.FillDirection.Vertical, 0)
			local nameLabel = Theme.text({
				name = "Name",
				text = line.name,
				font = Theme.fonts.label,
				size = s.price,
				parent = words,
			})
			nameLabel.LayoutOrder = 1
			nameLabel.ZIndex = Z_OVERLAY + 1
			local detail = Theme.label(line.rarityName)
			if line.variantName ~= nil then
				detail = Theme.label(line.variantName) .. " " .. detail
			end
			if line.newInIndex then
				detail ..= "  " .. Theme.label("New")
			end
			local rarityLabel = Theme.text({
				name = "Rarity",
				text = detail,
				font = Theme.fonts.label,
				size = textSizes.small,
				color = if line.variantName ~= nil
					then colors.gold
					else Theme.rarityColor(line.rarity),
				parent = words,
			})
			rarityLabel.LayoutOrder = 2
			rarityLabel.ZIndex = Z_OVERLAY + 1
		end
		view.result.Visible = true
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
			showMessage(eggId, "The shop did not answer. Try again.")
		elseif reply.ok == true then
			showHatched(eggId, reply)
			-- Visuals only: the server already decided what hatched.
			busy = true
			Effects.playHatch(gui, shellColor(eggId), EggShopView.hatchLines(reply), function()
				busy = false
			end)
		else
			showMessage(eggId, EggShopView.reasonText(reply.reason))
		end
	end

	local function buildCard(egg: Config.Egg, position: number): CardView
		local card = frame(egg.id, scroll)
		card.LayoutOrder = position
		card.BackgroundTransparency = 0
		card.BackgroundColor3 = colors.raised
		card.Visible = false
		Theme.panel(card)

		local eggSlot = frame("Egg", card)
		eggView(eggSlot, egg.id)

		local words = frame("Words", card)
		words.ClipsDescendants = true
		local wordsList = list(words, Enum.FillDirection.Vertical, 0)
		wordsList.VerticalAlignment = Enum.VerticalAlignment.Center
		local nameLabel = Theme.text({
			name = "Name",
			text = Theme.label(egg.name),
			font = Theme.fonts.heading,
			parent = words,
		})
		nameLabel.LayoutOrder = 1
		local priceLabel = Theme.text({
			name = "Price",
			font = Theme.fonts.label,
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

		local hatch, hatchStroke = button("Hatch", card)
		local triple, tripleStroke = button("HatchTriple", card)
		triple.Text = Theme.label(string.format("Hatch x%d", EggShopView.TRIPLE_COUNT))

		local toggle = Instance.new("TextButton")
		toggle.Name = "ShowOdds"
		toggle.BackgroundTransparency = 1
		toggle.BorderSizePixel = 0
		toggle.FontFace = Theme.fonts.label
		toggle.TextSize = textSizes.small
		toggle.TextColor3 = colors.muted
		toggle.Text = Theme.label("Show odds")
		toggle.Parent = card

		-- The odds, over the card above the toggle, hidden until asked for.
		local oddsPanel = frame("Odds", card)
		oddsPanel.BackgroundTransparency = 0
		oddsPanel.BackgroundColor3 = colors.raised
		oddsPanel.ZIndex = Z_OVERLAY
		oddsPanel.Visible = false
		Theme.panel(oddsPanel)
		pad(oddsPanel, 8)
		list(oddsPanel, Enum.FillDirection.Vertical, 0)
		local rows = #Config.rarities
		local names: { TextLabel } = {}
		local odds: { TextLabel } = {}
		for row = 1, rows do
			local line = frame("Row" .. row, oddsPanel)
			line.LayoutOrder = row
			line.Size = UDim2.fromScale(1, 1 / rows)
			line.ZIndex = Z_OVERLAY
			local nameText = Theme.text({ name = "Pet", parent = line })
			nameText.AnchorPoint = Vector2.new(0, 0.5)
			nameText.Position = UDim2.fromScale(0, 0.5)
			nameText.ZIndex = Z_OVERLAY + 1
			local chanceText = Theme.text({ name = "Chance", parent = line })
			chanceText.AnchorPoint = Vector2.new(1, 0.5)
			chanceText.Position = UDim2.fromScale(1, 0.5)
			chanceText.ZIndex = Z_OVERLAY + 1
			table.insert(names, nameText)
			table.insert(odds, chanceText)
		end

		-- The hatch result, over the egg and name only. Tapping hides it.
		local result = Instance.new("TextButton")
		result.Name = "Result"
		result.Text = ""
		result.AutoButtonColor = false
		result.BorderSizePixel = 0
		result.BackgroundColor3 = colors.raised
		result.ZIndex = Z_OVERLAY
		result.ClipsDescendants = true
		result.Visible = false
		result.Parent = card
		Theme.panel(result)
		pad(result, 8)
		local resultList = list(result, Enum.FillDirection.Horizontal, 10)
		resultList.VerticalAlignment = Enum.VerticalAlignment.Center

		local view: CardView = {
			frame = card,
			eggSlot = eggSlot,
			words = words,
			name = nameLabel,
			price = priceLabel,
			lock = lock,
			names = names,
			odds = odds,
			oddsPanel = oddsPanel,
			toggle = toggle,
			result = result,
			hatch = hatch,
			hatchStroke = hatchStroke,
			triple = triple,
			tripleStroke = tripleStroke,
		}

		local eggId = egg.id
		Pointer.register("hatch:" .. eggId, hatch)
		hatch.Activated:Connect(function()
			buy(eggId, 1)
		end)
		triple.Activated:Connect(function()
			if ownsTriple then
				buy(eggId, EggShopView.TRIPLE_COUNT)
			else
				showMessage(eggId, EggShopView.reasonText("no_triple_hatch_pass"))
			end
		end)
		toggle.Activated:Connect(function()
			oddsPanel.Visible = not oddsPanel.Visible
			toggle.Text = Theme.label(if oddsPanel.Visible then "Hide odds" else "Show odds")
		end)
		result.Activated:Connect(function()
			clearResult(view)
		end)
		return view
	end

	for position, egg in Config.eggs do
		cards[egg.id] = buildCard(egg, position)
	end

	-- Places the panel and every card part from EggShopLayout for the
	-- current screen size, below the Roblox and HUD top bars.
	local function applyLayout()
		local screen = gui.AbsoluteSize
		if screen.X <= 0 or screen.Y <= 0 then
			return
		end
		local inset = GuiService:GetGuiInset().Y
		local hud = HudLayout.compute(screen.X, screen.Y - inset, 0)
		local l = EggShopLayout.compute(screen.X, screen.Y, inset + hud.topBar.h)
		layout = l
		local s = l.sizes
		local p = l.panel
		place(panel, p, 0, 0)
		place(header, l.header, p.x, p.y)
		place(scroll, l.list, p.x, p.y)
		place(footer, l.footer, p.x, p.y)
		titleLabel.TextSize = s.title
		grid.CellSize = UDim2.fromOffset(l.cardWidth, l.cardHeight)
		grid.CellPadding = UDim2.fromOffset(s.gap, s.gap)
		local parts = l.parts
		for _, view in cards do
			place(view.eggSlot, parts.egg, 0, 0)
			place(view.words, parts.words, 0, 0)
			place(view.hatch, parts.hatch, 0, 0)
			place(view.triple, parts.triple, 0, 0)
			place(view.toggle, parts.toggle, 0, 0)
			place(view.oddsPanel, parts.odds, 0, 0)
			place(view.result, parts.result, 0, 0)
			view.name.TextSize = s.cardTitle
			view.price.TextSize = s.price
			for row = 1, #view.names do
				view.names[row].TextSize = s.odds
				view.odds[row].TextSize = s.odds
			end
		end
	end
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(applyLayout)
	applyLayout()

	-- An egg model loaded later replaces its card's placeholder.
	task.spawn(function()
		local folder = ReplicatedStorage:WaitForChild(MODELS_FOLDER)
		folder.ChildAdded:Connect(function(child: Instance)
			local view = cards[child.Name]
			if view ~= nil and child:IsA("Model") then
				eggView(view.eggSlot, child.Name)
			end
		end)
		for eggId, view in cards do
			if folder:FindFirstChild(eggId) ~= nil then
				eggView(view.eggSlot, eggId)
			end
		end
	end)

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
		local listed: { [string]: boolean } = {}
		for _, data in EggShopView.shownCards(state, { luckyEggs = passes.luckyEggs == true }) do
			listed[data.eggId] = true
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
		for eggId, view in cards do
			view.frame.Visible = listed[eggId] == true
		end
	end

	local function hide()
		gui.Enabled = false
	end

	-- Scrolls so the card of eggId sits at the top of the list.
	local function scrollTo(eggId: string?)
		local view = if eggId ~= nil then cards[eggId] else nil
		if view == nil or not view.frame.Visible then
			scroll.CanvasPosition = Vector2.zero
			return
		end
		-- Wait a frame so the grid has laid out the newly shown cards.
		RunService.Heartbeat:Wait()
		local card = view.frame
		local offset = card.AbsolutePosition.Y - scroll.AbsolutePosition.Y + scroll.CanvasPosition.Y
		scroll.CanvasPosition = Vector2.new(0, math.max(0, offset))
	end

	opener = function(eggId: string?)
		local wasOpen = gui.Enabled
		if not wasOpen then
			clearResults()
		end
		render(State.get())
		gui.Enabled = true
		applyLayout()
		if not wasOpen or eggId ~= nil then
			task.spawn(scrollTo, eggId)
		end
	end

	close.Activated:Connect(hide)
	backdrop.Activated:Connect(hide)

	render(nil)
	gui.Parent = playerGui
	applyLayout()
	State.subscribe(render)
	Screens.track(gui)
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
