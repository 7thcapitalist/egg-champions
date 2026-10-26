--!strict
--[[
	EggShop: where coins become pets, built to match design/ui/EggShop.dc.html.

	- One card per egg of an unlocked world, in config order, plus the next
	  locked egg as a teaser (shared/ui/EggShopView.shownCards decides), so a
	  new egg needs no code change.
	- Where everything sits comes from shared/ui/EggShopLayout, whose specs
	  check that HATCH is visible without scrolling at 808 x 432 and
	  1280 x 720. The panel starts below the Roblox top bar and the HUD top
	  bar (HudLayout contentTop, from UI/HudInsets).
	- The top of each card holds the egg's real model, from the same templates
	  the world egg stands use (ReplicatedStorage.PetModels, named by egg id),
	  framed on its bounding box. Until the template and its parts have
	  arrived, or if its copy has no parts, the card shows a coloured egg
	  shape (EggShopView.eggSource), never nothing. Then name, price, HATCH
	  and, only with the Triple Hatch pass after the tutorial and never on a
	  locked card, HATCH X3 (EggShopView.showsTriple). The five pets with rarity and hatch chance
	  sit behind "Show odds". The chances are the table the server rolls
	  with, so the screen cannot drift from the roll.
	- A locked egg says what unlocks it. An egg the player cannot afford shows
	  its price muted. Both buttons still send the request: the client only
	  hints, the server decides and its refusal is shown as a readable message.
	- Hatch sends BuyEgg with the egg id and a count of 1. Hatch x3 sends the
	  triple count. Neither ever sends a price.
	- Auto Hatch repeats one BuyEgg request only after its reveal ends. A Stop
	  button stays over the reveal, and closing or switching screens stops it.
	- A hatch is shown by Effects.playHatch and then the reveal, over the
	  screen, straight from the server's reply; the card keeps its egg and
	  name. Only a refusal (or no answer) is written over the card's egg and
	  name area (never its buttons); tapping it hides it. The list never
	  moves, so the scroll position is kept.
	- The list's content is sized from EggShopLayout.canvasHeight, with room
	  under the last card, so the last card is never cut off.

	EggShop.openAt(eggId) opens the screen scrolled to that egg's card, for the
	egg stands in the world.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local uiShared = Shared:WaitForChild("ui")
local Format = require(uiShared:WaitForChild("Format"))
local EggShopView = require(uiShared:WaitForChild("EggShopView"))
local HatchReveal = require(uiShared:WaitForChild("HatchReveal"))
local EggShopLayout = require(uiShared:WaitForChild("EggShopLayout"))
local HudLayout = require(uiShared:WaitForChild("HudLayout"))
local HudInsets = require(script.Parent:WaitForChild("HudInsets"))
local NextGoal = require(uiShared:WaitForChild("NextGoal"))

local Theme = require(script.Parent:WaitForChild("Theme"))
local Pointer = require(script.Parent:WaitForChild("Pointer"))
local Guide = require(script.Parent:WaitForChild("Guide"))
local Reveal = require(script.Parent:WaitForChild("Reveal"))
local Screens = require(script.Parent:WaitForChild("Screens"))
local Effects = require((script.Parent :: Instance).Parent:WaitForChild("Effects"):WaitForChild("Effects"))
local State = require(script.Parent:WaitForChild("State"))

local colors = Theme.colors
local sizes = Theme.sizes
local textSizes = Theme.textSizes

-- Share of the header width the tutorial bar takes, centered between the
-- title on the left and the coins and Close on the right.
local GUIDE_WIDTH = 0.44

local EggShop = {}

-- Where the asset stage puts each egg's model, named by egg id.
local MODELS_FOLDER = "PetModels"
-- How the egg model is framed in its card: camera field of view in degrees,
-- and the share of room left around the model. Display only.
local EGG_FOV = 30
local EGG_FRAME = 1.15
-- How long a card waits for its egg template, and its parts, to arrive
-- before it keeps the egg shape; and how often it looks. Display only.
local EGG_WAIT_SECONDS = 60
local EGG_POLL_SECONDS = 0.25

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
	auto: TextButton,
	autoStroke: UIStroke,
	-- Whether HATCH X3 shows, so HATCH can take its room when it does not.
	showsTriple: boolean,
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
		stroke.Color = colors.outline
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

local function partCount(root: Instance): number
	local count = 0
	for _, item in root:GetDescendants() do
		if item:IsA("BasePart") then
			count += 1
		end
	end
	return count
end

-- The egg's template in PetModels, or nil when it has not arrived.
local function eggTemplate(eggId: string): Instance?
	local folder = ReplicatedStorage:FindFirstChild(MODELS_FOLDER)
	return if folder ~= nil then folder:FindFirstChild(eggId) else nil
end

-- A copy of the template centred on its bounding box, with the camera
-- distance that frames it, or nil when the copy holds no parts.
local function eggCopy(template: Instance): (Model?, number)
	if not template:IsA("Model") then
		return nil, 0
	end
	-- Clone skips anything not Archivable, which would leave an empty Model.
	template.Archivable = true
	for _, item in template:GetDescendants() do
		item.Archivable = true
	end
	local copy = (template :: Model):Clone()
	if copy == nil then
		return nil, 0
	end
	local parts = partCount(copy)
	for _, item in copy:GetDescendants() do
		if item:IsA("BasePart") then
			item.Anchored = true
		end
	end
	local distance = 0
	if parts > 0 then
		local box, extents = copy:GetBoundingBox()
		copy:PivotTo(box:Inverse() * copy:GetPivot())
		distance = EggShopView.eggCameraDistance(extents.X, extents.Y, extents.Z, EGG_FOV, EGG_FRAME)
	end
	if EggShopView.eggSource(true, true, parts, distance) ~= "model" then
		copy:Destroy()
		return nil, 0
	end
	return copy, distance
end

-- The coloured egg shape: shown until the real egg arrives, and for good
-- when it never does.
local function eggShape(slot: Frame, eggId: string)
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
	stroke.Color = colors.outline
	stroke.Parent = shell
end

-- The egg in a card: its real model in a ViewportFrame, framed on its
-- bounding box, or the coloured egg shape. Returns true for the real model.
local function eggView(slot: Frame, eggId: string): boolean
	for _, child in slot:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	local template = eggTemplate(eggId)
	local model: Model?, distance = nil, 0
	if template ~= nil then
		model, distance = eggCopy(template)
	end
	if model == nil then
		eggShape(slot, eggId)
		return false
	end
	local viewport = Instance.new("ViewportFrame")
	viewport.Name = "EggView"
	viewport.BackgroundTransparency = 1
	viewport.BorderSizePixel = 0
	viewport.Size = UDim2.fromScale(1, 1)
	viewport.Ambient = Color3.fromRGB(200, 200, 200)
	viewport.LightColor = Color3.fromRGB(255, 255, 255)
	viewport.LightDirection = Vector3.new(-1, -1, -1)
	model.Parent = viewport
	local camera = Instance.new("Camera")
	camera.FieldOfView = EGG_FOV
	camera.CFrame = CFrame.lookAt(Vector3.new(0, 0, distance), Vector3.zero)
	camera.Parent = viewport
	viewport.CurrentCamera = camera
	viewport.Parent = slot
	return true
end

-- Waits for the egg's template and its parts (a model can arrive before its
-- mesh part does), then shows it. The shape stays meanwhile. Runs in its own
-- thread.
local function loadEgg(slot: Frame, eggId: string)
	local deadline = os.clock() + EGG_WAIT_SECONDS
	while os.clock() < deadline do
		local template = eggTemplate(eggId)
		if template ~= nil and partCount(template) > 0 then
			eggView(slot, eggId)
			return
		end
		task.wait(EGG_POLL_SECONDS)
	end
	-- Never fully arrived: show whatever there is, which falls back to the shape.
	eggView(slot, eggId)
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

	-- The tutorial's line for this screen (UI/Guide), between the title and
	-- the coins, such as "Tap HATCH on the Meadow Egg".
	local guideHost = frame("GuideHost", header)
	guideHost.Size = UDim2.fromScale(1, 1)
	local guideBar = Guide.bar(guideHost)
	guideBar.AnchorPoint = Vector2.new(0.5, 0.5)
	guideBar.Position = UDim2.fromScale(0.5, 0.5)
	guideBar.Size = UDim2.new(GUIDE_WIDTH, 0, 0, sizes.minTap - 8)

	-- The cards, two per row, scrolling when there are more than fit. Nothing
	-- above the list ever changes height, so the scroll position is kept.
	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "Cards"
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 6
	scroll.ScrollBarImageColor3 = colors.border
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.None
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

	-- Stays above the hatch reveal, so stopping auto is always reachable.
	local stopButton, stopStroke = button("StopAutoHatch", gui)
	stopButton.AnchorPoint = Vector2.new(1, 1)
	stopButton.Position = UDim2.new(1, -16, 1, -16)
	stopButton.Size = UDim2.fromOffset(156, sizes.minTap)
	stopButton.ZIndex = 100
	stopButton.Text = Theme.label("Stop Auto")
	stopButton.Visible = false
	style(stopButton, stopStroke, "accent")

	local cards: { [string]: CardView } = {}
	local busy = false
	local auto = EggShopView.newAutoState()
	local ownsTriple = false
	local layout: EggShopLayout.Layout? = nil
	local autoStep: (() -> ())? = nil

	local function renderAuto()
		stopButton.Visible = auto.active and gui.Enabled
		for eggId, view in cards do
			local selected = auto.active and auto.eggId == eggId
			view.auto.Text = Theme.label(if selected then "Auto on" else "Auto Hatch")
			style(view.auto, view.autoStroke, if selected then "accent" else "muted")
		end
	end

	local function stopAuto()
		if auto.active then
			auto = EggShopView.stopAuto(auto)
		end
		renderAuto()
	end

	local function otherScreenOpen(): boolean
		for _, name in Screens.names do
			if name ~= Screens.names.Eggs and Screens.isShown(name) then
				return true
			end
		end
		return false
	end

	local function autoEligible(eggId: string): (boolean, string?)
		if not gui.Enabled or otherScreenOpen() then
			return false, nil
		end
		local payload = State.get()
		if payload == nil then
			return false, "no_profile"
		end
		local state: EggShopView.State = {
			coins = number(payload.profile.coins),
			gymsBeaten = flags(payload.profile.gymsBeaten),
		}
		for _, card in EggShopView.cards(state) do
			if card.eggId == eggId then
				if card.locked then
					return false, "egg_locked"
				end
				if not card.affordable then
					return false, "cannot_afford"
				end
				return true, nil
			end
		end
		return false, "unknown_choice"
	end

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

	local function buy(eggId: string, count: number, done: ((boolean) -> ())?)
		if busy then
			return
		end
		busy = true
		-- The tutorial waits for the reveal before it closes the shop.
		Guide.setHatching(true)
		local ok, reply = pcall(function(): any
			return buyEgg:InvokeServer(eggId, count)
		end)
		busy = false
		if not ok or type(reply) ~= "table" then
			Guide.setHatching(false)
			showMessage(eggId, "The shop did not answer. Try again.")
			if done ~= nil then
				done(false)
			end
		elseif reply.ok == true then
			-- The reveal shows what hatched; the card keeps its egg and name.
			clearResults()
			-- Visuals only: the server already decided what hatched.
			busy = true
			local lines = EggShopView.hatchLines(reply)
			Effects.playHatch(gui, shellColor(eggId), lines, function()
				Reveal.show(gui, HatchReveal.entries(lines), function()
					busy = false
					Guide.setHatching(false)
					if done ~= nil then
						done(true)
					end
				end)
			end, function(slot)
				return eggView(slot, eggId)
			end)
		else
			Guide.setHatching(false)
			showMessage(eggId, EggShopView.reasonText(reply.reason))
			if done ~= nil then
				done(false)
			end
		end
	end

	autoStep = function()
		local eggId = auto.eggId
		if eggId == nil then
			return
		end
		local eligible, reason = autoEligible(eggId)
		local nextAuto = EggShopView.beginAuto(auto, eggId, eligible)
		if nextAuto == nil then
			stopAuto()
			if reason ~= nil and gui.Enabled then
				showMessage(eggId, EggShopView.reasonText(reason))
			end
			return
		end
		auto = nextAuto
		local token = auto.token
		buy(eggId, 1, function(succeeded: boolean)
			local stillEligible = autoEligible(eggId)
			auto = EggShopView.finishAuto(auto, token, succeeded, stillEligible)
			renderAuto()
			if auto.active and autoStep ~= nil then
				task.defer(autoStep)
			end
		end)
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
		local autoButton, autoStroke = button("AutoHatch", card)
		autoButton.TextSize = textSizes.small
		autoButton.Text = Theme.label("Auto Hatch")
		style(autoButton, autoStroke, "muted")

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
			auto = autoButton,
			autoStroke = autoStroke,
			showsTriple = false,
			triple = triple,
			tripleStroke = tripleStroke,
		}

		local eggId = egg.id
		Pointer.register("hatch:" .. eggId, hatch)
		hatch.Activated:Connect(function()
			stopAuto()
			buy(eggId, 1, nil)
		end)
		triple.Activated:Connect(function()
			if not view.showsTriple then
				return
			end
			if ownsTriple then
				stopAuto()
				buy(eggId, EggShopView.TRIPLE_COUNT, nil)
			else
				showMessage(eggId, EggShopView.reasonText("no_triple_hatch_pass"))
			end
		end)
		autoButton.Activated:Connect(function()
			if auto.active and auto.eggId == eggId then
				stopAuto()
				return
			end
			if busy or auto.inFlight then
				return
			end
			local eligible, reason = autoEligible(eggId)
			if not eligible then
				if reason ~= nil then
					showMessage(eggId, EggShopView.reasonText(reason))
				end
				return
			end
			local nextAuto = EggShopView.startAuto(auto, eggId)
			if nextAuto ~= nil then
				auto = nextAuto
				clearResults()
				renderAuto()
				if autoStep ~= nil then
					task.defer(autoStep)
				end
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
		local hud = HudLayout.compute(screen.X, screen.Y, 0, HudInsets.read(screen))
		local l = EggShopLayout.compute(screen.X, screen.Y, hud.contentTop)
		layout = l
		local s = l.sizes
		local p = l.panel
		place(panel, p, 0, 0)
		place(header, l.header, p.x, p.y)
		place(scroll, l.list, p.x, p.y)
		place(footer, l.footer, p.x, p.y)
		-- Give guidance its own row on phones so it never covers the title or balance.
		guideHost.Visible = not (screen.X > screen.Y and screen.Y < 360)
		local guideRow = if Guide.reserved() and guideHost.Visible then 44 else 0
		guideBar.AnchorPoint = Vector2.new(0, 0)
		guideBar.Position = UDim2.fromOffset(0, s.header + 4)
		guideBar.Size = UDim2.new(1, 0, 0, 36)
		local guideLine = guideBar:FindFirstChild("Line") :: TextLabel
		guideLine.TextWrapped = true
		guideLine.TextTruncate = Enum.TextTruncate.None
		scroll.Position += UDim2.fromOffset(0, guideRow)
		scroll.Size -= UDim2.fromOffset(0, guideRow)
		coin.Visible = screen.X >= 500
		coinsLabel.Visible = screen.X >= 500
		titleLabel.TextSize = EggShopLayout.titleSize(s, textSizes.small)
		scroll.ScrollBarThickness = math.max(1, s.scrollBar - 2)
		grid.CellSize = UDim2.fromOffset(l.cardWidth, l.cardHeight)
		grid.CellPadding = UDim2.fromOffset(s.gap, s.gap)
		local parts = l.parts
		for _, view in cards do
			place(view.eggSlot, parts.egg, 0, 0)
			place(view.words, parts.words, 0, 0)
			place(view.hatch, if view.showsTriple then parts.hatch else parts.hatchWide, 0, 0)
			place(view.triple, parts.triple, 0, 0)
			local autoWidth = math.floor((parts.toggle.w - s.innerGap) / 2)
			view.auto.Position = UDim2.fromOffset(parts.toggle.x, parts.toggle.y)
			view.auto.Size = UDim2.fromOffset(autoWidth, parts.toggle.h)
			view.toggle.Position = UDim2.fromOffset(parts.toggle.x + autoWidth + s.innerGap, parts.toggle.y)
			view.toggle.Size = UDim2.fromOffset(parts.toggle.w - autoWidth - s.innerGap, parts.toggle.h)
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
	-- The list's content height, from the cards shown now.
	local function sizeCanvas()
		if layout == nil then
			return
		end
		local count = 0
		for _, view in cards do
			if view.frame.Visible then
				count += 1
			end
		end
		scroll.CanvasSize = UDim2.fromOffset(0, EggShopLayout.canvasHeight(layout, count))
	end
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		applyLayout()
		sizeCanvas()
	end)
	HudInsets.onChange(applyLayout)
	applyLayout()

	-- Each card waits for its egg (the template and its parts) and swaps the
	-- shape for it; a template loaded again later is shown again.
	for eggId, view in cards do
		task.spawn(loadEgg, view.eggSlot, eggId)
	end
	task.spawn(function()
		local folder = ReplicatedStorage:WaitForChild(MODELS_FOLDER)
		folder.ChildAdded:Connect(function(child: Instance)
			local view = cards[child.Name]
			if view ~= nil then
				task.spawn(loadEgg, view.eggSlot, child.Name)
			end
		end)
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
			view.price.TextColor3 = if data.affordable and not data.locked then colors.gold else colors.muted
			view.lock.Text = if data.locked and data.unlockText ~= nil then Theme.label(data.unlockText) else ""
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
				view.hatch.Text = Theme.label(string.format("Need %s more", Format.commas(data.short)))
				style(view.hatch, view.hatchStroke, "muted")
			else
				view.hatch.Text = Theme.label("Hatch")
				style(view.hatch, view.hatchStroke, "hatch")
			end
			local showsTriple = EggShopView.showsTriple(profile.tutorialStep, ownsTriple, data.locked)
			if showsTriple ~= view.showsTriple then
				view.showsTriple = showsTriple
				if layout ~= nil then
					local parts = (layout :: EggShopLayout.Layout).parts
					place(view.hatch, if showsTriple then parts.hatch else parts.hatchWide, 0, 0)
				end
			end
			view.triple.Visible = showsTriple
			local look = EggShopView.tripleLook(
				profile.tutorialStep,
				ownsTriple,
				data.locked,
				coins >= data.price * EggShopView.TRIPLE_COUNT
			)
			style(view.triple, view.tripleStroke, look)
		end
		for eggId, view in cards do
			view.frame.Visible = listed[eggId] == true
		end
		sizeCanvas()
		if auto.active and auto.eggId ~= nil then
			local eligible = autoEligible(auto.eggId)
			if not eligible then
				stopAuto()
			end
		end
		-- No pass line while the tutorial runs.
		footer.Visible = EggShopView.showsNote(profile.tutorialStep)
	end

	local function hide()
		stopAuto()
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
		if auto.active and eggId ~= nil and auto.eggId ~= eggId then
			stopAuto()
		end
		local wasOpen = gui.Enabled
		if not wasOpen then
			clearResults()
		end
		render(State.get())
		gui.Enabled = true
		renderAuto()
		applyLayout()
		if not wasOpen or eggId ~= nil then
			task.spawn(scrollTo, eggId)
		end
	end

	close.Activated:Connect(hide)
	backdrop.Activated:Connect(hide)
	stopButton.Activated:Connect(stopAuto)
	gui:GetPropertyChangedSignal("Enabled"):Connect(function()
		if not gui.Enabled then
			stopAuto()
		end
	end)

	render(nil)
	gui.Parent = playerGui
	applyLayout()
	State.subscribe(render)
	Screens.track(gui)
	Screens.onChange(function()
		if auto.active and (not gui.Enabled or otherScreenOpen()) then
			stopAuto()
		end
	end)
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
