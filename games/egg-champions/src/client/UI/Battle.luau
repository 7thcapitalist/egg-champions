--!strict
--[[
	Battle: the gym battle screen, built to match design/ui/Battle.dc.html.

	The screen renders what the server decided and decides nothing itself:
	- HP panels for both active pets (name, type marker, HP bar and number,
	  speed, and team markers for the pets each side has left), the arena with
	  both active pets as colored blocks, the battle log, the two move buttons
	  and Give up.
	- Every number on screen comes from the server. BattleMove answers with the
	  turn's event list and the battle view after it. The events are queued
	  and played one at a time (EVENT_SECONDS each), each one writing its log
	  line (shared/ui/BattleView) and moving the HP bars by the numbers the
	  event carries. When the queue is empty the screen resyncs to the view
	  the server sent, so if the two ever disagree the server is right.
	- Move 2 shows the cooldown the server sent and cannot be pressed while it
	  cools down. Both buttons wait while events play.

	Entering: stepping on a gym floor (tagged GymFloor by the world builder)
	or pressing the menu's gym button opens the fee prompt. It shows the fee
	from config and that attempts are free until the next rebirth, pays with
	PayGymFee when unpaid, then sends StartBattle.

	Leaving: a win shows the badge and the newly open world; a loss shows the
	server's retry wait as a countdown before the gym can be entered again.
	Battle particles and motion are task 16.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local PetVisual = require(Shared:WaitForChild("PetVisual"))
local uiShared = Shared:WaitForChild("ui")
local BattleView = require(uiShared:WaitForChild("BattleView"))

local Theme = require(script.Parent:WaitForChild("Theme"))
local Screens = require(script.Parent:WaitForChild("Screens"))
local State = require(script.Parent:WaitForChild("State"))

local colors = Theme.colors
local sizes = Theme.sizes

-- How long one server event plays on screen. The one knob for battle speed.
local EVENT_SECONDS = 0.7

-- Touch debounce for the gym floor, not a game number.
local FLOOR_COOLDOWN_SECONDS = 2
local GYM_FLOOR_TAG = "GymFloor"

-- Layout of the mockup, in pixels at 1280 x 720.
local DESIGN = Vector2.new(1280, 720)
local LAYOUT = table.freeze({
	topBar = 56,
	floorHeight = 260,
	panelX = 40,
	panelY = 90,
	panelWidth = 380,
	panelPadX = 18,
	panelPadY = 14,
	hpBar = 10,
	marker = Vector2.new(22, 6),
	blockSize = 150,
	blockX = 240,
	blockY = 300,
	popupY = 250,
	bottomGap = 24,
	rowHeight = 88,
	moveWidth = 230,
	giveUpWidth = 110,
	rowGap = 12,
	logLines = 60,
	promptWidth = 460,
	nameSize = 26,
	titleSize = 24,
	moveName = 24,
	moveSub = 14,
	popupSize = 40,
	logSize = 16,
	small = 13,
})

local Battle = {}

local opener: ((string) -> ())? = nil
local isShown: (() -> boolean)? = nil

-- Opens the fee prompt for a world's gym.
function Battle.openGym(worldId: string)
	if opener ~= nil then
		opener(worldId)
	end
end

function Battle.isOpen(): boolean
	return isShown ~= nil and isShown()
end

local function flags(value: any): { [string]: boolean }
	return if type(value) == "table" then value else {}
end

local function gymState(): BattleView.GymState
	local payload = State.get()
	local profile = if payload ~= nil then payload.profile else {}
	return {
		badges = flags(profile.badges),
		gymsBeaten = flags(profile.gymsBeaten),
		feesPaid = flags(profile.feesPaid),
	}
end

local function frame(name: string, parent: Instance?): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.BorderSizePixel = 0
	f.BackgroundTransparency = 1
	f.Parent = parent
	return f
end

local function filled(name: string, color: Color3, parent: Instance?): Frame
	local f = frame(name, parent)
	f.BackgroundTransparency = 0
	f.BackgroundColor3 = color
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

local function pad(parent: Instance, x: number, y: number)
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, y)
	padding.PaddingBottom = UDim.new(0, y)
	padding.PaddingLeft = UDim.new(0, x)
	padding.PaddingRight = UDim.new(0, x)
	padding.Parent = parent
end

local function button(name: string, parent: Instance): (TextButton, UIStroke)
	local b = Instance.new("TextButton")
	b.Name = name
	b.AutoButtonColor = true
	b.BorderSizePixel = 0
	b.BackgroundColor3 = colors.panel
	b.TextColor3 = colors.text
	b.FontFace = Theme.fonts.label
	b.TextSize = Theme.textSizes.button
	b.Parent = parent
	Theme.panel(b, sizes.radius)
	return b, b:FindFirstChildOfClass("UIStroke") :: UIStroke
end

type HpPanel = {
	name: TextLabel,
	typeLabel: TextLabel,
	fill: Frame,
	hp: TextLabel,
	speed: TextLabel,
	markers: Frame,
}

local function hpPanel(name: string, parent: Instance, rightSide: boolean): HpPanel
	local panel = filled(name, colors.panel, parent)
	panel.Size = UDim2.fromOffset(LAYOUT.panelWidth, 0)
	panel.AutomaticSize = Enum.AutomaticSize.Y
	panel.AnchorPoint = Vector2.new(if rightSide then 1 else 0, 0)
	panel.Position = if rightSide
		then UDim2.new(1, -LAYOUT.panelX, 0, LAYOUT.panelY)
		else UDim2.fromOffset(LAYOUT.panelX, LAYOUT.panelY)
	Theme.panel(panel)
	pad(panel, LAYOUT.panelPadX, LAYOUT.panelPadY)
	list(panel, Enum.FillDirection.Vertical, 8)

	local head = frame("Head", panel)
	head.LayoutOrder = 1
	head.Size = UDim2.new(1, 0, 0, LAYOUT.nameSize + 4)
	local petName = Theme.text({
		name = "Name",
		font = Theme.fonts.heading,
		size = LAYOUT.nameSize,
		parent = head,
	})
	local typeLabel = Theme.text({
		name = "Type",
		font = Theme.fonts.label,
		size = LAYOUT.small,
		parent = head,
	})
	typeLabel.AnchorPoint = Vector2.new(1, 0.5)
	typeLabel.Position = UDim2.fromScale(1, 0.5)

	local bar = filled("Bar", colors.border, panel)
	bar.LayoutOrder = 2
	bar.Size = UDim2.new(1, 0, 0, LAYOUT.hpBar)
	local fill = filled("Fill", colors.healthy, bar)
	fill.Size = UDim2.fromScale(1, 1)

	local numbers = frame("Numbers", panel)
	numbers.LayoutOrder = 3
	numbers.Size = UDim2.new(1, 0, 0, Theme.textSizes.body + 4)
	local hp = Theme.text({ name = "Hp", parent = numbers })
	local speed = Theme.text({ name = "Speed", color = colors.muted, parent = numbers })
	speed.AnchorPoint = Vector2.new(1, 0)
	speed.Position = UDim2.fromScale(1, 0)

	local team = frame("Team", panel)
	team.LayoutOrder = 4
	team.Size = UDim2.new(1, 0, 0, Theme.textSizes.small + 4)
	local teamList = list(team, Enum.FillDirection.Horizontal, 6)
	teamList.VerticalAlignment = Enum.VerticalAlignment.Center
	Theme.text({
		name = "Label",
		text = Theme.label("Team"),
		font = Theme.fonts.label,
		size = Theme.textSizes.small,
		color = colors.muted,
		parent = team,
	}).LayoutOrder =
		0
	local markers = frame("Markers", team)
	markers.LayoutOrder = 1
	markers.AutomaticSize = Enum.AutomaticSize.XY
	list(markers, Enum.FillDirection.Horizontal, 6).VerticalAlignment =
		Enum.VerticalAlignment.Center

	return {
		name = petName,
		typeLabel = typeLabel,
		fill = fill,
		hp = hp,
		speed = speed,
		markers = markers,
	}
end

type MoveButton = {
	button: TextButton,
	stroke: UIStroke,
	title: TextLabel,
	sub: TextLabel,
}

local function moveButton(name: string, parent: Instance, order: number): MoveButton
	local b, stroke = button(name, parent)
	b.LayoutOrder = order
	b.Text = ""
	b.Size = UDim2.new(0, LAYOUT.moveWidth, 1, 0)
	pad(b, LAYOUT.panelPadX, 0)
	local words = list(b, Enum.FillDirection.Vertical, 2)
	words.VerticalAlignment = Enum.VerticalAlignment.Center
	local title = Theme.text({
		name = "Title",
		font = Theme.fonts.heading,
		size = LAYOUT.moveName,
		parent = b,
	})
	title.LayoutOrder = 1
	local sub = Theme.text({
		name = "Sub",
		size = LAYOUT.moveSub,
		color = colors.muted,
		parent = b,
	})
	sub.LayoutOrder = 2
	return { button = b, stroke = stroke, title = title, sub = sub }
end

-- Builds the screen under playerGui. Call once.
function Battle.mount(
	playerGui: PlayerGui,
	payGymFee: RemoteFunction,
	startBattle: RemoteFunction,
	battleMove: RemoteFunction,
	giveUp: RemoteFunction
): ScreenGui
	local gui = Instance.new("ScreenGui")
	gui.Name = "Battle"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = 20
	gui.Enabled = false

	-- The battle itself: a full screen arena with a 1280 x 720 canvas scaled
	-- to fit, so the layout is the mockup's at any screen size.
	local arena = Instance.new("TextButton")
	arena.Name = "Arena"
	arena.Text = ""
	arena.AutoButtonColor = false
	arena.BorderSizePixel = 0
	arena.BackgroundColor3 = colors.arena
	arena.Size = UDim2.fromScale(1, 1)
	arena.Visible = false
	arena.Parent = gui
	local ground = filled("Ground", colors.arenaFloor, arena)
	ground.AnchorPoint = Vector2.new(0, 1)
	ground.Position = UDim2.fromScale(0, 1)
	ground.Size = UDim2.fromScale(1, LAYOUT.floorHeight / DESIGN.Y)

	local canvas = frame("Canvas", arena)
	canvas.AnchorPoint = Vector2.new(0.5, 0.5)
	canvas.Position = UDim2.fromScale(0.5, 0.5)
	canvas.Size = UDim2.fromOffset(DESIGN.X, DESIGN.Y)
	local scale = Instance.new("UIScale")
	scale.Parent = canvas
	local function fit()
		local size = gui.AbsoluteSize
		if size.X > 0 and size.Y > 0 then
			scale.Scale = math.min(size.X / DESIGN.X, size.Y / DESIGN.Y)
		end
	end
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)

	-- Top bar: gym name and whose move it is.
	local top = filled("Top", colors.panel, arena)
	top.Size = UDim2.new(1, 0, 0, LAYOUT.topBar)
	pad(top, sizes.gutter, 0)
	local topLine = filled("Line", colors.border, top)
	topLine.AnchorPoint = Vector2.new(0, 1)
	topLine.Position = UDim2.new(0, -sizes.gutter, 1, 0)
	topLine.Size = UDim2.new(1, sizes.gutter * 2, 0, sizes.border)
	local gymTitle = Theme.text({
		name = "Gym",
		font = Theme.fonts.heading,
		size = LAYOUT.titleSize,
		parent = top,
	})
	gymTitle.AnchorPoint = Vector2.new(0, 0.5)
	gymTitle.Position = UDim2.fromScale(0, 0.5)
	local turnLabel = Theme.text({
		name = "Turn",
		font = Theme.fonts.label,
		size = Theme.textSizes.body,
		color = colors.gold,
		parent = top,
	})
	turnLabel.AnchorPoint = Vector2.new(1, 0.5)
	turnLabel.Position = UDim2.fromScale(1, 0.5)

	local playerPanel = hpPanel("PlayerPanel", canvas, false)
	local leaderPanel = hpPanel("LeaderPanel", canvas, true)

	local playerBlock = filled("PlayerPet", colors.muted, canvas)
	playerBlock.Size = UDim2.fromOffset(LAYOUT.blockSize, LAYOUT.blockSize)
	playerBlock.Position = UDim2.fromOffset(LAYOUT.blockX, LAYOUT.blockY)
	Theme.panel(playerBlock, sizes.radius, colors.panel)
	local leaderBlock = filled("LeaderPet", colors.muted, canvas)
	leaderBlock.AnchorPoint = Vector2.new(1, 0)
	leaderBlock.Size = UDim2.fromOffset(LAYOUT.blockSize, LAYOUT.blockSize)
	leaderBlock.Position = UDim2.new(1, -LAYOUT.blockX, 0, LAYOUT.blockY)
	Theme.panel(leaderBlock, sizes.radius, colors.panel)

	local function popup(name: string, block: Frame): TextLabel
		local label = Theme.text({
			name = name,
			font = Theme.fonts.heading,
			size = LAYOUT.popupSize,
			color = colors.gold,
			parent = canvas,
		})
		label.AnchorPoint = Vector2.new(0.5, 1)
		label.Position = UDim2.new(
			block.Position.X.Scale,
			block.Position.X.Offset
				+ (if block.AnchorPoint.X == 1 then -1 else 1) * LAYOUT.blockSize / 2,
			0,
			LAYOUT.blockY - 8
		)
		label.Visible = false
		return label
	end
	local playerPopup = popup("PlayerPopup", playerBlock)
	local leaderPopup = popup("LeaderPopup", leaderBlock)

	-- Bottom row: log, move 1, move 2, Give up.
	local row = frame("Row", canvas)
	row.AnchorPoint = Vector2.new(0, 1)
	row.Position = UDim2.new(0, LAYOUT.panelX, 1, -LAYOUT.bottomGap)
	row.Size = UDim2.new(1, -LAYOUT.panelX * 2, 0, LAYOUT.rowHeight)
	list(row, Enum.FillDirection.Horizontal, LAYOUT.rowGap)

	local logWidth = LAYOUT.moveWidth * 2 + LAYOUT.giveUpWidth + LAYOUT.rowGap * 3
	local log = Instance.new("ScrollingFrame")
	log.Name = "Log"
	log.LayoutOrder = 1
	log.BorderSizePixel = 0
	log.BackgroundColor3 = colors.panel
	log.Size = UDim2.new(1, -logWidth, 1, 0)
	log.CanvasSize = UDim2.fromOffset(0, 0)
	log.AutomaticCanvasSize = Enum.AutomaticSize.Y
	log.ScrollBarThickness = 4
	log.ScrollBarImageColor3 = colors.border
	log.Parent = row
	Theme.panel(log)
	pad(log, LAYOUT.panelPadX, 8)
	list(log, Enum.FillDirection.Vertical, 4)

	local move1 = moveButton("Move1", row, 2)
	local move2 = moveButton("Move2", row, 3)
	local giveUpButton = button("GiveUp", row)
	giveUpButton.LayoutOrder = 4
	giveUpButton.Size = UDim2.new(0, LAYOUT.giveUpWidth, 1, 0)
	giveUpButton.Text = Theme.label("Give up")

	-- The fee prompt and the result share one centered card over a dim.
	local dim = Instance.new("TextButton")
	dim.Name = "Dim"
	dim.Text = ""
	dim.AutoButtonColor = false
	dim.BorderSizePixel = 0
	dim.BackgroundColor3 = colors.backdrop
	dim.BackgroundTransparency = 0.5
	dim.Size = UDim2.fromScale(1, 1)
	dim.ZIndex = 5
	dim.Visible = false
	dim.Parent = gui

	local card = filled("Card", colors.panel, dim)
	card.Active = true
	card.AnchorPoint = Vector2.new(0.5, 0.5)
	card.Position = UDim2.fromScale(0.5, 0.5)
	card.Size = UDim2.fromScale(0.9, 0)
	card.AutomaticSize = Enum.AutomaticSize.Y
	card.ZIndex = 6
	local cardLimit = Instance.new("UISizeConstraint")
	cardLimit.MaxSize = Vector2.new(LAYOUT.promptWidth, math.huge)
	cardLimit.Parent = card
	Theme.panel(card, sizes.radius + 2)
	pad(card, sizes.gutter, sizes.gutter)
	list(card, Enum.FillDirection.Vertical, 12)

	local cardTitle = Theme.text({
		name = "Title",
		font = Theme.fonts.heading,
		size = LAYOUT.titleSize,
		parent = card,
	})
	cardTitle.LayoutOrder = 1
	local function wrapped(name: string, order: number, color: Color3): TextLabel
		local label = Theme.text({ name = name, color = color, parent = card })
		label.LayoutOrder = order
		label.AutomaticSize = Enum.AutomaticSize.Y
		label.Size = UDim2.fromScale(1, 0)
		label.TextWrapped = true
		label.TextXAlignment = Enum.TextXAlignment.Left
		return label
	end
	local cardBody = wrapped("Body", 2, colors.text)
	local cardStatus = wrapped("Status", 3, colors.gold)

	local cardButtons = frame("Buttons", card)
	cardButtons.LayoutOrder = 4
	cardButtons.Size = UDim2.new(1, 0, 0, sizes.minTap)
	list(cardButtons, Enum.FillDirection.Horizontal, 10)
	local primary, primaryStroke = button("Primary", cardButtons)
	primary.LayoutOrder = 1
	primary.Size = UDim2.new(0.6, -5, 1, 0)
	local secondary = button("Secondary", cardButtons)
	secondary.LayoutOrder = 2
	secondary.Size = UDim2.new(0.4, -5, 1, 0)
	secondary.Text = Theme.label("Close")

	gui.Parent = playerGui
	fit()

	-- What the screen is showing. None of it is game state: display is the
	-- last view the server sent, moved event by event while a turn plays.
	local mode: "closed" | "prompt" | "battle" | "result" = "closed"
	local promptWorld: string? = nil
	local sessionId: string? = nil
	local battleWorld: string? = nil
	local display: BattleView.Snapshot? = nil
	local busy = false
	local playing = false
	local logCount = 0
	-- Display only: when the server's retry wait ends, per world. The server
	-- enforces the wait itself.
	local retryUntil: { [string]: number } = {}

	local function showCard(visible: boolean)
		dim.Visible = visible
	end

	local function setPrimary(text: string, enabled: boolean)
		primary.Text = Theme.label(text)
		primary.Active = enabled
		primary.AutoButtonColor = enabled
		primary.BackgroundColor3 = if enabled then colors.raised else colors.panel
		primary.TextColor3 = if enabled then colors.gold else colors.muted
		primaryStroke.Color = if enabled then colors.gold else colors.border
	end

	local function addLog(text: string, muted: boolean)
		logCount += 1
		local line = Theme.text({
			name = string.format("Line%04d", logCount),
			text = text,
			size = LAYOUT.logSize,
			color = if muted then colors.muted else colors.text,
			parent = log,
		})
		line.LayoutOrder = logCount
		line.AutomaticSize = Enum.AutomaticSize.Y
		line.Size = UDim2.fromScale(1, 0)
		line.TextWrapped = true
		line.TextXAlignment = Enum.TextXAlignment.Left
		-- Keep the log short; the oldest lines go first.
		local lines = {}
		for _, child in log:GetChildren() do
			if child:IsA("TextLabel") then
				table.insert(lines, child)
			end
		end
		table.sort(lines, function(a, b)
			return a.LayoutOrder < b.LayoutOrder
		end)
		for position = 1, #lines - LAYOUT.logLines do
			lines[position]:Destroy()
		end
		task.defer(function()
			log.CanvasPosition = Vector2.new(0, math.max(0, log.AbsoluteCanvasSize.Y))
		end)
	end

	local function clearLog()
		for _, child in log:GetChildren() do
			if child:IsA("TextLabel") then
				child:Destroy()
			end
		end
	end

	local function renderPanel(
		panel: HpPanel,
		block: Frame,
		snapshot: BattleView.Snapshot,
		side: string
	)
		local sideView = if side == "player" then snapshot.player else snapshot.leader
		local fighter = BattleView.active(snapshot, side)
		if fighter == nil then
			-- The side is out of pets: show the last one, fainted.
			local last = sideView.fighters[#sideView.fighters]
			fighter = last
		end
		local shown = fighter :: BattleView.FighterView
		local index = math.min(sideView.active, #sideView.fighters)
		panel.name.Text = Theme.label(BattleView.fighterName(snapshot, side, index))
		panel.typeLabel.Text = Theme.label(BattleView.typeName(shown.type))
		panel.typeLabel.TextColor3 = Theme.typeColor(shown.type)
		local share = BattleView.hpShare(shown.hp, shown.maxHp)
		panel.fill.Size = UDim2.fromScale(share, 1)
		panel.fill.BackgroundColor3 = if share > 0.5 then colors.healthy else colors.gold
		panel.hp.Text = BattleView.hpText(shown.hp, shown.maxHp)
		panel.speed.Text = BattleView.speedText(shown.speed)
		for _, child in panel.markers:GetChildren() do
			if child:IsA("Frame") then
				child:Destroy()
			end
		end
		for position, member in sideView.fighters do
			local marker = filled(
				"Pet" .. position,
				if member.hp > 0 then colors.healthy else colors.fainted,
				panel.markers
			)
			marker.LayoutOrder = position
			marker.Size = UDim2.fromOffset(LAYOUT.marker.X, LAYOUT.marker.Y)
		end
		block.BackgroundColor3 = colors.panel
		block.BackgroundTransparency = if shown.hp > 0 then 0 else 0.6
		local key = PetVisual.key(shown.pet, shown.variant, shown.type)
		local view = block:FindFirstChild("PetView")
		if block:GetAttribute("PetKey") ~= key or view == nil then
			view = PetVisual.view(block, shown.pet, shown.variant, shown.type)
			block:SetAttribute("PetKey", key)
		end
		if view ~= nil and view:IsA("ViewportFrame") then
			view.ImageTransparency = if shown.hp > 0 then 0 else 0.6
		end
	end

	local function renderButtons(snapshot: BattleView.Snapshot)
		local fighter = BattleView.active(snapshot, "player")
		local waiting = busy or playing or mode ~= "battle"
		if fighter == nil then
			move1.title.Text = ""
			move2.title.Text = ""
			return
		end
		move1.title.Text = Theme.label(BattleView.basicMoveName(fighter.type))
		move1.sub.Text = "Basic attack. Always ready."
		move1.stroke.Color = Theme.typeColor(fighter.type)
		move1.button.Active = not waiting
		move1.button.AutoButtonColor = not waiting

		move2.title.Text = Theme.label(BattleView.specialName(fighter.special))
		local cooling = fighter.cooldown > 0 or not snapshot.specialReady
		move2.sub.Text = BattleView.cooldownText(fighter.cooldown)
		local pressable = not cooling and not waiting
		move2.button.Active = pressable
		move2.button.AutoButtonColor = pressable
		move2.button.BackgroundColor3 = if cooling then colors.raised else colors.panel
		move2.title.TextColor3 = if cooling then colors.muted else colors.text
		move2.stroke.Color = if cooling then colors.border else Theme.typeColor(fighter.type)
		giveUpButton.Active = not busy and mode == "battle"
	end

	local function render()
		local snapshot = display
		if snapshot == nil then
			return
		end
		renderPanel(playerPanel, playerBlock, snapshot, "player")
		renderPanel(leaderPanel, leaderBlock, snapshot, "leader")
		local turnText = string.format("Turn %d", snapshot.turn + 1)
		if not playing and not busy and mode == "battle" then
			turnText ..= ". Your move"
		end
		turnLabel.Text = Theme.label(turnText)
		renderButtons(snapshot)
	end

	local function showPopup(event: any)
		local label = if event.side == "player" then playerPopup else leaderPopup
		label.Text =
			BattleView.damageText(if type(event.amount) == "number" then event.amount else 0)
		label.Visible = true
		task.delay(EVENT_SECONDS, function()
			label.Visible = false
		end)
	end

	-- Prompt and result

	local refreshPrompt: () -> ()

	local function countdownLeft(worldId: string): number
		local untilTime = retryUntil[worldId]
		if untilTime == nil then
			return 0
		end
		return math.max(0, untilTime - os.clock())
	end

	local function runCountdown(worldId: string)
		task.spawn(function()
			while (mode == "prompt" or mode == "result") and countdownLeft(worldId) > 0 do
				if mode == "prompt" and promptWorld == worldId then
					refreshPrompt()
				elseif mode == "result" and battleWorld == worldId then
					cardStatus.Text = BattleView.countdownText(countdownLeft(worldId))
				end
				task.wait(1)
			end
			if mode == "prompt" and promptWorld == worldId then
				refreshPrompt()
			elseif mode == "result" and battleWorld == worldId then
				cardStatus.Text = BattleView.countdownText(0)
			end
		end)
	end

	function refreshPrompt()
		local worldId = promptWorld
		if worldId == nil then
			return
		end
		local prompt = BattleView.feePrompt(worldId, gymState())
		cardTitle.Text = Theme.label(prompt.title)
		cardBody.Text = prompt.body
		local left = countdownLeft(worldId)
		if left > 0 then
			cardStatus.Text = BattleView.countdownText(left)
			cardStatus.Visible = true
		elseif
			cardStatus.Text == "" or string.find(cardStatus.Text, "try again", 1, true) ~= nil
		then
			cardStatus.Text = ""
			cardStatus.Visible = false
		end
		local label = if prompt.paid
			then "Fight"
			else string.format("Pay %s and fight", prompt.feeText)
		setPrimary(label, left <= 0 and not busy)
	end

	local function closeAll()
		mode = "closed"
		promptWorld = nil
		showCard(false)
		arena.Visible = false
		gui.Enabled = false
	end

	local function openPrompt(worldId: string)
		if mode == "battle" then
			return
		end
		mode = "prompt"
		promptWorld = worldId
		battleWorld = nil
		cardStatus.Text = ""
		arena.Visible = false
		gui.Enabled = true
		showCard(true)
		primary.Visible = true
		secondary.Text = Theme.label("Close")
		refreshPrompt()
		runCountdown(worldId)
	end

	local function showResult(won: boolean, reply: any)
		mode = "result"
		local worldId = battleWorld or ""
		cardTitle.Text = Theme.label(if won then "Victory" else "Defeat")
		if won then
			cardBody.Text = BattleView.winText(worldId, reply.newBadge == true)
			cardStatus.Text = ""
			cardStatus.Visible = false
		else
			cardBody.Text = "Your team is out. Hatch or equip stronger pets and try again."
			local wait = if type(reply.retrySeconds) == "number" then reply.retrySeconds else 0
			retryUntil[worldId] = os.clock() + wait
			cardStatus.Text = BattleView.countdownText(wait)
			cardStatus.Visible = true
			runCountdown(worldId)
		end
		primary.Visible = false
		secondary.Text = Theme.label("Close")
		showCard(true)
		render()
	end

	local function invoke(remote: RemoteFunction, ...: any): any
		local args = table.pack(...)
		local ok, reply = pcall(function(): any
			return remote:InvokeServer(table.unpack(args, 1, args.n))
		end)
		if not ok or type(reply) ~= "table" then
			return { ok = false, reason = "no_answer" }
		end
		return reply
	end

	local function enterBattle(worldId: string, reply: any)
		sessionId = reply.sessionId
		battleWorld = worldId
		display = BattleView.copy(reply.battle)
		mode = "battle"
		promptWorld = nil
		showCard(false)
		primary.Visible = true
		clearLog()
		gymTitle.Text = Theme.label(BattleView.feePrompt(worldId, gymState()).title)
		arena.Visible = true
		addLog("The battle begins. Pick a move.", true)
		render()
	end

	local function fight()
		local worldId = promptWorld
		if worldId == nil or busy or countdownLeft(worldId) > 0 then
			return
		end
		busy = true
		refreshPrompt()
		if not BattleView.feePrompt(worldId, gymState()).paid then
			local paid = invoke(payGymFee, worldId)
			if paid.ok ~= true and paid.reason ~= "fee_already_paid" then
				busy = false
				cardStatus.Text = BattleView.reasonText(paid.reason)
				cardStatus.Visible = true
				refreshPrompt()
				return
			end
		end
		local started = invoke(startBattle, worldId)
		busy = false
		if started.ok ~= true or type(started.battle) ~= "table" then
			cardStatus.Text = BattleView.reasonText(started.reason)
			cardStatus.Visible = true
			refreshPrompt()
			return
		end
		enterBattle(worldId, started)
	end

	-- Plays a turn's events one at a time, then resyncs to the server's view.
	local function play(reply: any)
		playing = true
		render()
		local snapshot = display
		local events = if type(reply.events) == "table" then reply.events else {}
		for _, event in events do
			if snapshot ~= nil and BattleView.handles(event.kind) then
				addLog(BattleView.lineFor(event, snapshot), event.side == "leader")
				BattleView.apply(snapshot, event)
				if event.kind == "damage" then
					showPopup(event)
				end
				render()
				task.wait(EVENT_SECONDS)
			end
		end
		if type(reply.battle) == "table" then
			display = BattleView.copy(reply.battle)
		end
		playing = false
		if reply.finished == true then
			showResult(reply.won == true, reply)
		else
			render()
		end
	end

	local function sendMove(move: number)
		local snapshot = display
		if mode ~= "battle" or busy or playing or sessionId == nil or snapshot == nil then
			return
		end
		if move == 2 then
			local fighter = BattleView.active(snapshot, "player")
			if fighter == nil or fighter.cooldown > 0 or not snapshot.specialReady then
				return
			end
		end
		busy = true
		render()
		local reply = invoke(battleMove, sessionId, move)
		busy = false
		if reply.ok ~= true then
			addLog(BattleView.reasonText(reply.reason), true)
			if reply.reason == "session_ended" or reply.reason == "no_session" then
				closeAll()
			else
				render()
			end
			return
		end
		play(reply)
	end

	local function surrender()
		if mode ~= "battle" or busy or playing or sessionId == nil then
			return
		end
		busy = true
		local reply = invoke(giveUp, sessionId)
		busy = false
		if reply.ok ~= true then
			addLog(BattleView.reasonText(reply.reason), true)
			render()
			return
		end
		play(reply)
	end

	move1.button.Activated:Connect(function()
		sendMove(1)
	end)
	move2.button.Activated:Connect(function()
		sendMove(2)
	end)
	giveUpButton.Activated:Connect(surrender)
	primary.Activated:Connect(fight)
	secondary.Activated:Connect(function()
		if mode == "prompt" or mode == "result" then
			closeAll()
		end
	end)

	State.subscribe(function()
		if mode == "prompt" then
			refreshPrompt()
		end
	end)

	opener = openPrompt
	isShown = function(): boolean
		return mode ~= "closed"
	end
	Screens.register(Screens.names.Battle, function()
		openPrompt(BattleView.pickGym(gymState()))
	end)

	-- The gym floors in the world open the prompt for their gym.
	local player = Players.LocalPlayer
	local lastOpen = 0
	local hooked: { [Instance]: boolean } = {}
	local function hook(instance: Instance)
		if hooked[instance] or not instance:IsA("BasePart") then
			return
		end
		hooked[instance] = true
		local floor = instance :: BasePart
		floor.Touched:Connect(function(hit: BasePart)
			local character = player.Character
			if character == nil or not hit:IsDescendantOf(character) then
				return
			end
			local worldId = floor:GetAttribute("WorldId")
			local now = os.clock()
			if type(worldId) ~= "string" or mode ~= "closed" then
				return
			end
			if now - lastOpen < FLOOR_COOLDOWN_SECONDS then
				return
			end
			lastOpen = now
			openPrompt(worldId)
		end)
	end
	for _, instance in CollectionService:GetTagged(GYM_FLOOR_TAG) do
		hook(instance)
	end
	CollectionService:GetInstanceAddedSignal(GYM_FLOOR_TAG):Connect(hook)
	CollectionService:GetInstanceRemovedSignal(GYM_FLOOR_TAG):Connect(function(instance: Instance)
		hooked[instance] = nil
	end)

	return gui
end

return Battle
