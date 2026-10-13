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

return Effects
