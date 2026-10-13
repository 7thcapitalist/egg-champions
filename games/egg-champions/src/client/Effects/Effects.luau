--!strict
--[[
	Effects: every effect the player sees, in one module with one budget.

	The budget is the table right below, Effects.BUDGET. Every particle count,
	lifetime, tween duration and pool cap in this file reads from it. It is
	defined in shared/visual/EffectsBudget so the headless tests can check
	that every rarity in config has a reveal, and so the phone budget sits in
	one place. Later effect tasks add their rows there and their code here.

	Nothing here changes what the player gets. The server has already decided
	every coin and every hatch; these are only the visuals for its answers.

	Click pop (main screen):
	- Main reports each world click position; it waits in a short queue.
	- The server answers each accepted click with ClickCredited and the coins
	  it added. That amount pops up at the oldest waiting click, rises and
	  fades, and a small coin burst plays in the world at the same point.
	- Labels and burst emitters come from pools capped by the budget, so 20
	  clicks a second recycle the same instances and never queue more.

	Hatch sequence (egg shop): Effects.playHatch shows each hatched pet in
	turn: the egg shakes, cracks with a flash in the rarity color, and the pet
	appears in front of turning light rays with its name and rarity. Hatch x3
	plays its reveals one after another. One tap skips the rest, and the shop's
	result strip underneath still lists what hatched.

	Battle effects (gym battle screen): Battle.luau plays a turn's events one
	at a time and hands each to Effects.playBattle, which draws its cue and
	returns how long to wait before the next event. The cue comes from
	shared/visual/BattleEffects, built only from what the event carries:
	- attack: the attacker hops toward the target and back;
	- damage: the target flashes white and shakes, a burst in the move type's
	  color (bigger for Smash and Off-type) and the damage number, gold and
	  larger when the event carried the strong type bonus;
	- guard: a shield ring that holds until the hit it absorbs;
	- heal: rising green crosses, or for Drain a stream from target to user;
	- rush: speed lines; faint: shrink and fade; switch: the next pet grows in.
	Every duration is a row of EffectsBudget.BATTLE_SECONDS, and each event's
	animations end inside its row, so no two events overlap. Pieces come from
	small pools, and resetBattle stops everything when the screen closes.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local visual = Shared:WaitForChild("visual")
local EffectsBudget = require(visual:WaitForChild("EffectsBudget"))
local Pool = require(visual:WaitForChild("Pool"))
local PetVisual = require(Shared:WaitForChild("PetVisual"))
local Format = require(Shared:WaitForChild("ui"):WaitForChild("Format"))

local UI = (script.Parent :: Instance).Parent:WaitForChild("UI")
local Theme = require(UI:WaitForChild("Theme"))

local BattleEffects = require(visual:WaitForChild("BattleEffects"))

local Effects = {}

-- The budget: counts, lifetimes and durations for every effect.
Effects.BUDGET = EffectsBudget
local CLICK = EffectsBudget.CLICK
local HATCH = EffectsBudget.HATCH

export type Reveal = {
	petId: string,
	variant: string?,
	name: string,
	rarity: string,
	rarityName: string,
	variantName: string?,
}

-- Click pop

type Pop = {
	label: TextLabel,
	serial: number,
	tween: Tween?,
}

type Burst = {
	attachment: Attachment,
	emitter: ParticleEmitter,
	serial: number,
}

local pops: Pool.Pool<Pop>? = nil
local bursts: Pool.Pool<Burst>? = nil
local pending: Pool.Queue<Vector2> = Pool.newQueue(CLICK.pendingMax)
local popLayer: ScreenGui? = nil

local function newPop(parent: Instance): Pop
	local label = Theme.text({
		name = "CoinPop",
		font = Theme.fonts.heading,
		size = CLICK.textSize,
		color = Theme.colors.gold,
		parent = parent,
	})
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.TextStrokeColor3 = Theme.colors.backdrop
	label.TextStrokeTransparency = 0.4
	label.Visible = false
	return { label = label, serial = 0, tween = nil }
end

-- A burst is an attachment on Terrain with one emitter: no part, no physics.
local function newBurst(holder: Instance): Burst
	local attachment = Instance.new("Attachment")
	attachment.Name = "CoinBurst"
	local emitter = Instance.new("ParticleEmitter")
	emitter.Enabled = false
	emitter.Rate = 0
	emitter.Color = ColorSequence.new(Theme.colors.gold)
	emitter.LightEmission = 0.5
	emitter.Lifetime = NumberRange.new(CLICK.burstLifetime)
	emitter.Speed = NumberRange.new(CLICK.burstSpeed * 0.5, CLICK.burstSpeed)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Acceleration = Vector3.new(0, -CLICK.burstSpeed * 2, 0)
	emitter.Size = NumberSequence.new(CLICK.burstSize, 0)
	emitter.Transparency = NumberSequence.new(0, 1)
	emitter.Parent = attachment
	attachment.Parent = holder
	return { attachment = attachment, emitter = emitter, serial = 0 }
end

local function playPop(position: Vector2, amount: number)
	local pool = pops
	if pool == nil then
		return
	end
	local pop = Pool.acquire(pool)
	pop.serial += 1
	local serial = pop.serial
	local previous = pop.tween
	if previous ~= nil then
		previous:Cancel()
	end
	local label = pop.label
	label.Text = "+" .. Format.abbreviate(amount)
	label.Position = UDim2.fromOffset(position.X, position.Y)
	label.TextTransparency = 0
	label.TextStrokeTransparency = 0.4
	label.Visible = true
	local tween = TweenService:Create(
		label,
		TweenInfo.new(CLICK.lifetime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{
			Position = UDim2.fromOffset(position.X, position.Y - CLICK.rise),
			TextTransparency = 1,
			TextStrokeTransparency = 1,
		}
	)
	pop.tween = tween
	tween.Completed:Connect(function()
		if pop.serial == serial then
			label.Visible = false
			pop.tween = nil
			Pool.release(pool, pop)
		end
	end)
	tween:Play()
end

local function playBurst(position: Vector2)
	local pool = bursts
	local camera = Workspace.CurrentCamera
	if pool == nil or camera == nil then
		return
	end
	local ray = camera:ViewportPointToRay(position.X, position.Y)
	local hit = Workspace:Raycast(ray.Origin, ray.Direction * CLICK.rayDistance)
	local point = if hit ~= nil
		then hit.Position
		else ray.Origin + ray.Direction * CLICK.fallbackDistance
	local burst = Pool.acquire(pool)
	burst.serial += 1
	local serial = burst.serial
	burst.attachment.WorldPosition = point
	burst.emitter:Emit(CLICK.burstParticles)
	task.delay(CLICK.burstLifetime, function()
		if burst.serial == serial then
			Pool.release(pool, burst)
		end
	end)
end

-- Called by Main with the screen position of every world click.
function Effects.clicked(position: Vector2)
	Pool.push(pending, position, os.clock())
end

-- Plays the pop for an amount the server credited, at the oldest waiting
-- click, or mid screen if none is waiting.
function Effects.credited(amount: number)
	local gui = popLayer
	if gui == nil then
		return
	end
	local position = Pool.take(pending, os.clock(), CLICK.pendingSeconds)
	if position == nil then
		position = gui.AbsoluteSize / 2
	end
	local at = position :: Vector2
	playPop(at, amount)
	playBurst(at)
end

-- Builds the pools and listens for credited clicks. Call once.
function Effects.mount(playerGui: PlayerGui, clickCredited: RemoteEvent)
	local gui = Instance.new("ScreenGui")
	gui.Name = "Effects"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 5
	gui.Parent = playerGui
	popLayer = gui

	pops = Pool.new(CLICK.maxLive, function(): Pop
		return newPop(gui)
	end)
	bursts = Pool.new(CLICK.burstPool, function(): Burst
		return newBurst(Workspace.Terrain)
	end)

	clickCredited.OnClientEvent:Connect(function(amount: any)
		if type(amount) == "number" then
			Effects.credited(amount)
		end
	end)
end

-- Hatch sequence

local function corner(parent: Instance, radius: UDim)
	local c = Instance.new("UICorner")
	c.CornerRadius = radius
	c.Parent = parent
end

local function blank(name: string, parent: Instance): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.BorderSizePixel = 0
	f.BackgroundTransparency = 1
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Position = UDim2.fromScale(0.5, 0.5)
	f.Parent = parent
	return f
end

local function tween(
	instance: Instance,
	seconds: number,
	goal: { [string]: any },
	reverses: boolean?
): Tween
	local t = TweenService:Create(
		instance,
		TweenInfo.new(seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, reverses == true),
		goal
	)
	t:Play()
	return t
end

-- Plays the reveals in order on top of `parent`, one at a time. A tap skips
-- everything left. onDone runs once, when the last reveal ends or on skip.
function Effects.playHatch(
	parent: Instance,
	shellColor: Color3,
	reveals: { Reveal },
	onDone: (() -> ())?
)
	if #reveals == 0 then
		if onDone ~= nil then
			onDone()
		end
		return
	end

	local overlay = Instance.new("TextButton")
	overlay.Name = "HatchReveal"
	overlay.Text = ""
	overlay.AutoButtonColor = false
	overlay.Active = true
	overlay.BackgroundColor3 = Theme.colors.backdrop
	overlay.BackgroundTransparency = 0.25
	overlay.BorderSizePixel = 0
	overlay.Size = UDim2.fromScale(1, 1)
	overlay.ZIndex = 50
	overlay.Parent = parent

	local hint = Theme.text({
		name = "Skip",
		text = Theme.label("Tap to skip"),
		font = Theme.fonts.label,
		size = Theme.textSizes.small,
		color = Theme.colors.muted,
		parent = overlay,
	})
	hint.AnchorPoint = Vector2.new(0.5, 1)
	hint.Position = UDim2.new(0.5, 0, 1, -Theme.sizes.gutter)
	hint.ZIndex = 60

	local stage = blank("Stage", overlay)
	stage.Size = UDim2.fromScale(1, 1)
	stage.ZIndex = 51

	local finished = false
	local running: { Tween } = {}

	local function finish()
		if finished then
			return
		end
		finished = true
		for _, t in running do
			t:Cancel()
		end
		overlay:Destroy()
		if onDone ~= nil then
			onDone()
		end
	end

	overlay.Activated:Connect(finish)

	local function play(
		instance: Instance,
		seconds: number,
		goal: { [string]: any },
		reverses: boolean?
	)
		table.insert(running, tween(instance, seconds, goal, reverses))
	end

	-- Waits, and says false when the player skipped meanwhile.
	local function hold(seconds: number): boolean
		local start = os.clock()
		while os.clock() - start < seconds do
			if finished then
				return false
			end
			RunService.Heartbeat:Wait()
		end
		table.clear(running)
		return not finished
	end

	local function reveal(entry: Reveal): boolean
		for _, child in stage:GetChildren() do
			child:Destroy()
		end
		local timing = EffectsBudget.hatchTiming(entry.rarity)
		local rarityColor = Theme.rarityColor(entry.rarity)

		-- The egg shakes three times.
		local egg = blank("Egg", stage)
		egg.BackgroundTransparency = 0
		egg.BackgroundColor3 = shellColor
		egg.Size = UDim2.fromOffset(HATCH.eggSize * 0.78, HATCH.eggSize)
		egg.ZIndex = 52
		corner(egg, UDim.new(0.5, 0))
		for shake = 1, HATCH.shakes do
			local side = if shake % 2 == 1 then 1 else -1
			play(egg, timing.shakeSeconds, { Rotation = timing.shakeAngle * side }, true)
			if not hold(timing.shakeSeconds * 2 + HATCH.shakeGap) then
				return false
			end
		end

		-- It cracks with a flash in the rarity color.
		egg:Destroy()
		local flash = blank("Flash", stage)
		flash.Size = UDim2.fromScale(1, 1)
		flash.BackgroundTransparency = 1 - timing.flashStrength
		flash.BackgroundColor3 = rarityColor
		flash.ZIndex = 58
		play(flash, timing.flashSeconds, { BackgroundTransparency = 1 })

		-- Light rays in the rarity color turn behind the pet.
		local rays = blank("Rays", stage)
		rays.Size = UDim2.fromOffset(timing.rayLength * 2, timing.rayLength * 2)
		rays.ZIndex = 53
		for ray = 1, timing.rays do
			local beam = blank("Ray" .. ray, rays)
			beam.BackgroundTransparency = HATCH.rayTransparency
			beam.BackgroundColor3 = rarityColor
			beam.Size = UDim2.fromOffset(HATCH.rayWidth, timing.rayLength * 2)
			beam.Rotation = (180 / timing.rays) * ray
			beam.ZIndex = 53
			corner(beam, UDim.new(0.5, 0))
		end
		local raysScale = Instance.new("UIScale")
		raysScale.Scale = 0
		raysScale.Parent = rays
		play(raysScale, timing.revealSeconds, { Scale = 1 })
		play(rays, timing.revealSeconds + timing.holdSeconds, { Rotation = timing.rayTurnDegrees })

		-- The pet grows in with its name and rarity.
		local pet = blank("Pet", stage)
		pet.Size = UDim2.fromOffset(HATCH.petSize, HATCH.petSize)
		pet.ZIndex = 55
		local petScale = Instance.new("UIScale")
		petScale.Scale = 0
		petScale.Parent = pet
		local view = PetVisual.view(pet, entry.petId, entry.variant, nil)
		view.ZIndex = 55
		play(petScale, timing.revealSeconds, { Scale = 1 })

		local words = Instance.new("Frame")
		words.Name = "Words"
		words.BackgroundTransparency = 1
		words.AnchorPoint = Vector2.new(0.5, 0)
		words.Position = UDim2.new(0.5, 0, 0.5, timing.rayLength * 0.55)
		words.AutomaticSize = Enum.AutomaticSize.XY
		words.ZIndex = 56
		words.Parent = stage
		local layout = Instance.new("UIListLayout")
		layout.FillDirection = Enum.FillDirection.Vertical
		layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
		layout.SortOrder = Enum.SortOrder.LayoutOrder
		layout.Parent = words
		local nameLabel = Theme.text({
			name = "Name",
			text = entry.name,
			font = Theme.fonts.heading,
			size = Theme.textSizes.heading + 8,
			parent = words,
		})
		nameLabel.LayoutOrder = 1
		nameLabel.ZIndex = 56
		local detail = Theme.label(entry.rarityName)
		if entry.variantName ~= nil then
			detail = Theme.label(entry.variantName) .. " " .. detail
		end
		local rarityLabel = Theme.text({
			name = "Rarity",
			text = detail,
			font = Theme.fonts.label,
			size = Theme.textSizes.heading,
			color = if entry.variantName ~= nil then Theme.colors.gold else rarityColor,
			parent = words,
		})
		rarityLabel.LayoutOrder = 2
		rarityLabel.ZIndex = 56

		return hold(math.max(timing.flashSeconds, timing.revealSeconds) + timing.holdSeconds)
	end

	task.spawn(function()
		for _, entry in reveals do
			if not reveal(entry) then
				return
			end
		end
		finish()
	end)
end

-- Battle effects

local BATTLE = EffectsBudget.BATTLE

type SideFx = {
	block: Frame,
	base: UDim2,
	scale: UIScale,
	flash: Frame,
	shield: Frame,
	shieldScale: UIScale,
	shieldStroke: UIStroke,
	-- +1 when the other side is to the right of this one.
	toward: number,
}

-- A pooled dot, bar or label. item is a Frame or a TextLabel by pool.
type Piece = {
	item: GuiObject,
	serial: number,
}

local battleLayer: Frame? = nil
local sides: { [string]: SideFx } = {}
local dots: Pool.Pool<Piece>? = nil
local bars: Pool.Pool<Piece>? = nil
local labels: Pool.Pool<Piece>? = nil
local dispatcher = BattleEffects.newDispatcher()
local battleTweens: { [Tween]: boolean } = {}
-- Bumped on reset, so a delayed step from a closed battle does nothing.
local generation = 0
local jitter = Random.new()

local function rgbColor(c: BattleEffects.RGB): Color3
	return Color3.fromRGB(c.r, c.g, c.b)
end

local function fx(
	instance: Instance,
	seconds: number,
	goal: { [string]: any },
	style: Enum.EasingStyle?,
	repeats: number?,
	reverses: boolean?
): Tween
	local t = TweenService:Create(
		instance,
		TweenInfo.new(
			seconds,
			style or Enum.EasingStyle.Quad,
			Enum.EasingDirection.Out,
			repeats or 0,
			reverses == true
		),
		goal
	)
	battleTweens[t] = true
	t.Completed:Connect(function()
		battleTweens[t] = nil
	end)
	t:Play()
	return t
end

-- Runs fn after `seconds`, unless the battle was reset meanwhile.
local function later(seconds: number, fn: () -> ())
	local gen = generation
	task.delay(seconds, function()
		if gen == generation then
			fn()
		end
	end)
end

local function take(pool: Pool.Pool<Piece>?): Piece?
	if pool == nil then
		return nil
	end
	local piece = Pool.acquire(pool)
	piece.serial += 1
	return piece
end

local function giveBack(pool: Pool.Pool<Piece>?, piece: Piece, seconds: number)
	local serial = piece.serial
	later(seconds, function()
		if pool ~= nil and piece.serial == serial then
			piece.item.Visible = false
			Pool.release(pool, piece)
		end
	end)
end

local function centerOf(side: SideFx): UDim2
	local block = side.block
	local size = block.Size
	local anchor = block.AnchorPoint
	return UDim2.new(
		side.base.X.Scale,
		side.base.X.Offset + (0.5 - anchor.X) * size.X.Offset,
		side.base.Y.Scale,
		side.base.Y.Offset + (0.5 - anchor.Y) * size.Y.Offset
	)
end

local function newDot(layer: Instance): Piece
	local dot = Instance.new("Frame")
	dot.Name = "Dot"
	dot.BorderSizePixel = 0
	dot.AnchorPoint = Vector2.new(0.5, 0.5)
	dot.Visible = false
	dot.ZIndex = 3
	corner(dot, UDim.new(0.5, 0))
	dot.Parent = layer
	return { item = dot, serial = 0 }
end

local function newBar(layer: Instance): Piece
	local bar = Instance.new("Frame")
	bar.Name = "Bar"
	bar.BorderSizePixel = 0
	bar.AnchorPoint = Vector2.new(0.5, 0.5)
	bar.Visible = false
	bar.ZIndex = 2
	corner(bar, UDim.new(0.5, 0))
	bar.Parent = layer
	return { item = bar, serial = 0 }
end

local function newLabel(layer: Instance): Piece
	local label = Theme.text({
		name = "Number",
		font = Theme.fonts.heading,
		parent = layer,
	})
	label.AnchorPoint = Vector2.new(0.5, 1)
	label.TextStrokeColor3 = Theme.colors.backdrop
	label.Visible = false
	label.ZIndex = 4
	return { item = label, serial = 0 }
end

local function sideFx(block: Frame, toward: number): SideFx
	local scale = Instance.new("UIScale")
	scale.Name = "FxScale"
	scale.Parent = block

	local flash = Instance.new("Frame")
	flash.Name = "Flash"
	flash.BorderSizePixel = 0
	flash.BackgroundColor3 = rgbColor(BattleEffects.COLORS.flash)
	flash.BackgroundTransparency = 1
	flash.Size = UDim2.fromScale(1, 1)
	flash.ZIndex = 2
	corner(flash, UDim.new(0, Theme.sizes.radius))
	flash.Parent = block

	local shield = Instance.new("Frame")
	shield.Name = "Shield"
	shield.BackgroundTransparency = 1
	shield.BorderSizePixel = 0
	shield.AnchorPoint = Vector2.new(0.5, 0.5)
	shield.Position = UDim2.fromScale(0.5, 0.5)
	shield.Size = UDim2.new(1, BATTLE.shieldPad * 2, 1, BATTLE.shieldPad * 2)
	shield.Visible = false
	shield.ZIndex = 3
	corner(shield, UDim.new(0.5, 0))
	local stroke = Instance.new("UIStroke")
	stroke.Color = rgbColor(BattleEffects.COLORS.shield)
	stroke.Thickness = BATTLE.shieldThickness
	stroke.Parent = shield
	local shieldScale = Instance.new("UIScale")
	shieldScale.Parent = shield
	shield.Parent = block

	return {
		block = block,
		base = block.Position,
		scale = scale,
		flash = flash,
		shield = shield,
		shieldScale = shieldScale,
		shieldStroke = stroke,
		toward = toward,
	}
end

local function hop(side: SideFx)
	side.block.Position = side.base
	fx(
		side.block,
		BATTLE.hopSeconds,
		{ Position = side.base + UDim2.fromOffset(side.toward * BATTLE.hopDistance, 0) },
		Enum.EasingStyle.Quad,
		0,
		true
	)
end

local function hit(side: SideFx)
	side.flash.BackgroundTransparency = BATTLE.flashStart
	fx(side.flash, BATTLE.flashSeconds, { BackgroundTransparency = 1 })
	side.block.Position = side.base
	fx(
		side.block,
		BATTLE.shakeSeconds,
		{ Position = side.base + UDim2.fromOffset(BATTLE.shakeOffset, 0) },
		Enum.EasingStyle.Sine,
		BATTLE.shakes - 1,
		true
	)
end

local function burst(side: SideFx, look: BattleEffects.Burst)
	local center = centerOf(side)
	local color = rgbColor(look.color)
	local count = BATTLE.burstParticles
	local size = BATTLE.burstSize * look.scale
	for i = 1, count do
		local piece = take(dots)
		if piece == nil then
			return
		end
		local angle = (i / count) * math.pi * 2 + jitter:NextNumber(-0.3, 0.3)
		local reach = BATTLE.burstDistance * look.scale * jitter:NextNumber(0.6, 1)
		local dot = piece.item :: Frame
		dot.BackgroundColor3 = color
		dot.BackgroundTransparency = 0
		dot.Size = UDim2.fromOffset(size, size)
		dot.Position = center
		dot.Visible = true
		fx(dot, BATTLE.burstLifetime, {
			Position = center + UDim2.fromOffset(math.cos(angle) * reach, math.sin(angle) * reach),
			Size = UDim2.fromOffset(0, 0),
			BackgroundTransparency = 1,
		})
		giveBack(dots, piece, BATTLE.burstLifetime)
	end
end

local function number(side: SideFx, shown: BattleEffects.Number)
	local piece = take(labels)
	if piece == nil then
		return
	end
	local label = piece.item :: TextLabel
	local whole = Format.commas(math.ceil(shown.amount))
	label.Text = if shown.heal then "+" .. whole else "-" .. whole
	label.TextColor3 = rgbColor(
		if shown.heal
			then BattleEffects.COLORS.healNumber
			elseif shown.strong then BattleEffects.COLORS.strongNumber
			else BattleEffects.COLORS.number
	)
	label.TextSize = if shown.strong then BATTLE.strongNumberSize else BATTLE.numberSize
	label.TextTransparency = 0
	label.TextStrokeTransparency = 0.3
	local at = centerOf(side) + UDim2.fromOffset(0, -side.block.Size.Y.Offset / 2 - 8)
	label.Position = at
	label.Visible = true
	fx(label, BATTLE.numberSeconds, {
		Position = at + UDim2.fromOffset(0, -BATTLE.numberRise),
		TextTransparency = 1,
		TextStrokeTransparency = 1,
	})
	giveBack(labels, piece, BATTLE.numberSeconds)
end

local function shieldUp(side: SideFx)
	side.shield.Visible = true
	side.shieldStroke.Transparency = 0
	side.shieldScale.Scale = 0.6
	fx(side.shieldScale, BATTLE.shieldInSeconds, { Scale = 1 }, Enum.EasingStyle.Back)
end

local function shieldBreak(side: SideFx)
	fx(side.shieldScale, BATTLE.shieldBreakSeconds, { Scale = 1.3 })
	fx(side.shieldStroke, BATTLE.shieldBreakSeconds, { Transparency = 1 })
	later(BATTLE.shieldBreakSeconds, function()
		side.shield.Visible = false
	end)
end

local function crosses(side: SideFx)
	local center = centerOf(side)
	local width = side.block.Size.X.Offset
	local height = side.block.Size.Y.Offset
	local count = BATTLE.crosses
	for i = 1, count do
		local piece = take(labels)
		if piece == nil then
			return
		end
		local label = piece.item :: TextLabel
		label.Text = "+"
		label.TextColor3 = rgbColor(BattleEffects.COLORS.cross)
		label.TextSize = BATTLE.crossSize
		label.TextTransparency = 0
		label.TextStrokeTransparency = 0.5
		local x = (i - (count + 1) / 2) * (width / count)
		local at = center + UDim2.fromOffset(x, height * 0.3)
		label.Position = at
		label.Visible = true
		local rise = BATTLE.crossRise * (if i % 2 == 0 then 1 else 0.7)
		fx(label, BATTLE.crossSeconds, {
			Position = at + UDim2.fromOffset(0, -rise),
			TextTransparency = 1,
			TextStrokeTransparency = 1,
		})
		giveBack(labels, piece, BATTLE.crossSeconds)
	end
end

local function speedLines(side: SideFx)
	local center = centerOf(side)
	local half = side.block.Size.X.Offset / 2
	local height = side.block.Size.Y.Offset
	local count = BATTLE.speedLines
	for i = 1, count do
		local piece = take(bars)
		if piece == nil then
			return
		end
		local bar = piece.item :: Frame
		bar.BackgroundColor3 = rgbColor(BattleEffects.COLORS.speedLine)
		bar.BackgroundTransparency = 0.2
		bar.Size = UDim2.fromOffset(BATTLE.speedLineLength, BATTLE.speedLineWidth)
		local y = ((i - 0.5) / count - 0.5) * height * 0.8
		local at = center + UDim2.fromOffset(-side.toward * half, y)
		bar.Position = at
		bar.Visible = true
		fx(bar, BATTLE.speedLineSeconds, {
			Position = at + UDim2.fromOffset(-side.toward * BATTLE.speedLineLength, 0),
			BackgroundTransparency = 1,
		})
		giveBack(bars, piece, BATTLE.speedLineSeconds)
	end
end

local function stream(from: SideFx, to: SideFx)
	local start = centerOf(from)
	local finish = centerOf(to)
	local color = rgbColor(BattleEffects.COLORS.stream)
	for i = 1, BATTLE.streamDots do
		later((i - 1) * BATTLE.streamStagger, function()
			local piece = take(dots)
			if piece == nil then
				return
			end
			local dot = piece.item :: Frame
			dot.BackgroundColor3 = color
			dot.BackgroundTransparency = 0
			dot.Size = UDim2.fromOffset(BATTLE.streamDotSize, BATTLE.streamDotSize)
			dot.Position = start
			dot.Visible = true
			fx(dot, BATTLE.streamSeconds, {
				Position = finish,
				BackgroundTransparency = 0.6,
			}, Enum.EasingStyle.Sine)
			giveBack(dots, piece, BATTLE.streamSeconds)
		end)
	end
end

local function faint(side: SideFx)
	fx(side.scale, BATTLE.faintSeconds, { Scale = 0 }, Enum.EasingStyle.Back)
	fx(side.block, BATTLE.faintSeconds, { BackgroundTransparency = 1 })
	local view = side.block:FindFirstChild("PetView")
	if view ~= nil and view:IsA("ViewportFrame") then
		fx(view, BATTLE.faintSeconds, { ImageTransparency = 1 })
	end
end

local function enter(side: SideFx)
	side.scale.Scale = 0
	fx(side.scale, BATTLE.enterSeconds, { Scale = 1 }, Enum.EasingStyle.Back)
end

-- Builds the battle effect layer over the battle canvas. Call once, after
-- both pet blocks are placed.
function Effects.mountBattle(canvas: Frame, playerBlock: Frame, leaderBlock: Frame)
	local layer = Instance.new("Frame")
	layer.Name = "BattleEffects"
	layer.BackgroundTransparency = 1
	layer.BorderSizePixel = 0
	layer.Size = UDim2.fromScale(1, 1)
	layer.ZIndex = 4
	layer.Parent = canvas
	battleLayer = layer

	-- The player stands on the left of the mockup; read it from the layout.
	local playerRight = playerBlock.Position.X.Scale <= leaderBlock.Position.X.Scale
	sides.player = sideFx(playerBlock, if playerRight then 1 else -1)
	sides.leader = sideFx(leaderBlock, if playerRight then -1 else 1)

	dots = Pool.new(BATTLE.dotPool, function(): Piece
		return newDot(layer)
	end)
	bars = Pool.new(BATTLE.barPool, function(): Piece
		return newBar(layer)
	end)
	labels = Pool.new(BATTLE.labelPool, function(): Piece
		return newLabel(layer)
	end)
end

-- Draws one server event and returns the seconds it plays for. The caller
-- waits that long before the next event, so events never overlap.
function Effects.playBattle(event: any): number
	local cue = BattleEffects.cue(dispatcher, event)
	if cue == nil then
		return EffectsBudget.battleSeconds("")
	end
	local side = sides[cue.side]
	if battleLayer == nil or side == nil then
		return cue.seconds
	end
	if cue.hop then
		hop(side)
	end
	if cue.hit then
		hit(side)
	end
	local look = cue.burst
	if look ~= nil then
		burst(side, look)
	end
	local shown = cue.number
	if shown ~= nil then
		number(side, shown)
	end
	if cue.shieldUp then
		shieldUp(side)
	end
	if cue.shieldBreak then
		shieldBreak(side)
	end
	if cue.crosses then
		crosses(side)
	end
	if cue.speedLines then
		speedLines(side)
	end
	local from = cue.streamFrom
	if from ~= nil and sides[from] ~= nil then
		stream(sides[from], side)
	end
	if cue.faint then
		faint(side)
	end
	if cue.enter then
		enter(side)
	end
	return cue.seconds
end

local function hideAll(pool: Pool.Pool<Piece>?)
	if pool == nil then
		return
	end
	for _, piece in table.clone(pool.live) do
		piece.item.Visible = false
		Pool.release(pool, piece)
	end
end

-- Stops every battle effect and puts both pets back. Call when a battle
-- starts and when the battle screen closes, so nothing runs off screen.
function Effects.resetBattle()
	generation += 1
	dispatcher = BattleEffects.newDispatcher()
	local running = {}
	for t in battleTweens do
		table.insert(running, t)
	end
	for _, t in running do
		t:Cancel()
	end
	table.clear(battleTweens)
	for _, side in sides do
		side.block.Position = side.base
		side.scale.Scale = 1
		side.flash.BackgroundTransparency = 1
		side.shield.Visible = false
		side.shieldScale.Scale = 1
		side.shieldStroke.Transparency = 0
	end
	hideAll(dots)
	hideAll(bars)
	hideAll(labels)
end

return Effects
