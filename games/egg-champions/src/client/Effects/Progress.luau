--!strict
--[[
	Progress: the three effects that mark real progress, drawn from what the
	server sent. shared/visual/ProgressEffects decides what each one shows;
	every size and duration is a row of EffectsBudget.PROGRESS.

	Gym win: Battle.luau calls Progress.playGymWin when the server reports a
	win. The badge pops in with a burst in the gold accent, with a caption
	naming the world that opened, or, after the last gym, the "coming soon"
	gate (Progression.isFinalGymBeaten decides which).

	World unlock: every portal's look comes from ProfileChanged through
	UI/State. A portal that opens lights up once the badge has played, with a
	swirl in the color of the world it opens (shared/world/WorldPalette, the
	same table the world builder paints with). It lights wherever the player
	stands, so returning finds it open; the swirl itself only plays when the
	portal is near the camera. A locked portal dims and its label says what is
	needed. Walking through an open portal plays a short swirl on screen.

	Rebirth: the rebirth screen hands every Rebirth reply to
	ProgressEffects.onRebirthReply with Progress.playRebirth, so the flash and
	the rising ring play only after the server confirms the rebirth.

	The first payload after joining only sets the portals, so a rejoin shows
	the right portals and badges with no effect replayed, and a rebirth
	relocks portals with no effect.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local visual = Shared:WaitForChild("visual")
local EffectsBudget = require(visual:WaitForChild("EffectsBudget"))
local ProgressEffects = require(visual:WaitForChild("ProgressEffects"))

local UI = (script.Parent :: Instance).Parent:WaitForChild("UI")
local Theme = require(UI:WaitForChild("Theme"))
local State = require(UI:WaitForChild("State"))

local PROGRESS = EffectsBudget.PROGRESS
local PORTAL_TAG = "Portal"

local player = Players.LocalPlayer

local Progress = {}

local layer: ScreenGui? = nil

local function rgbColor(c: ProgressEffects.RGB): Color3
	return Color3.fromRGB(c.r, c.g, c.b)
end

local function tween(instance: Instance, seconds: number, goal: { [string]: any }): Tween
	local t = TweenService:Create(
		instance,
		TweenInfo.new(seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		goal
	)
	t:Play()
	return t
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

-- Gym win

function Progress.playGymWin(win: ProgressEffects.GymWin)
	local gui = layer
	if gui == nil then
		return
	end
	local holder = blank("GymWin", gui)
	holder.Size = UDim2.fromOffset(PROGRESS.badgeSize, PROGRESS.badgeSize)

	for i = 1, PROGRESS.badgeBurstDots do
		local dot = blank("Spark", holder)
		dot.BackgroundTransparency = 0
		dot.BackgroundColor3 = Theme.colors.gold
		dot.Size = UDim2.fromOffset(PROGRESS.badgeBurstDotSize, PROGRESS.badgeBurstDotSize)
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0.5, 0)
		corner.Parent = dot
		local angle = (i - 1) / PROGRESS.badgeBurstDots * math.pi * 2
		local d = PROGRESS.badgeBurstDistance
		tween(dot, PROGRESS.badgeBurstSeconds, {
			Position = UDim2.new(0.5, math.cos(angle) * d, 0.5, math.sin(angle) * d),
			BackgroundTransparency = 1,
		})
	end

	local badge = blank("Badge", holder)
	badge.BackgroundTransparency = 0
	badge.BackgroundColor3 = Theme.colors.gold
	badge.Rotation = 45
	badge.Size = UDim2.fromOffset(0, 0)
	local stroke = Instance.new("UIStroke")
	stroke.Color = Theme.colors.white
	stroke.Thickness = 3
	stroke.Parent = badge
	local side = PROGRESS.badgeSize / math.sqrt(2)
	tween(badge, PROGRESS.badgeInSeconds, { Size = UDim2.fromOffset(side, side) })

	local caption = Theme.text({
		name = "Caption",
		text = Theme.label(win.caption),
		font = Theme.fonts.heading,
		size = PROGRESS.captionSize,
		color = if win.color ~= nil then rgbColor(win.color) else Theme.colors.text,
		parent = holder,
	})
	caption.AnchorPoint = Vector2.new(0.5, 0)
	caption.Position = UDim2.new(0.5, 0, 1, PROGRESS.badgeSize * 0.4)
	caption.TextStrokeColor3 = Theme.colors.backdrop
	caption.TextStrokeTransparency = 0.4

	task.delay(PROGRESS.badgeInSeconds + PROGRESS.badgeHoldSeconds, function()
		tween(badge, PROGRESS.badgeOutSeconds, { BackgroundTransparency = 1 })
		tween(stroke, PROGRESS.badgeOutSeconds, { Transparency = 1 })
		tween(caption, PROGRESS.badgeOutSeconds, {
			TextTransparency = 1,
			TextStrokeTransparency = 1,
		})
		task.delay(PROGRESS.badgeOutSeconds, function()
			holder:Destroy()
		end)
	end)
end

-- Rebirth

-- Only ProgressEffects.onRebirthReply calls this, with a confirmed reply.
function Progress.playRebirth(_rebirths: number)
	local gui = layer
	if gui == nil then
		return
	end
	local flash = Instance.new("Frame")
	flash.Name = "RebirthFlash"
	flash.BorderSizePixel = 0
	flash.BackgroundColor3 = Theme.colors.white
	flash.BackgroundTransparency = PROGRESS.flashStrength
	flash.Size = UDim2.fromScale(1, 1)
	flash.Parent = gui
	tween(flash, PROGRESS.flashSeconds, { BackgroundTransparency = 1 })
	task.delay(PROGRESS.flashSeconds, function()
		flash:Destroy()
	end)

	local character = player.Character
	local root = if character ~= nil then character:FindFirstChild("HumanoidRootPart") else nil
	if root == nil or not root:IsA("BasePart") then
		return
	end
	-- A flat ring at the feet that rises and widens around the player.
	local flat = CFrame.Angles(math.pi / 2, 0, 0)
	local feet = -root.Size.Y * 1.5
	local ring = Instance.new("CylinderHandleAdornment")
	ring.Name = "RebirthRing"
	ring.Adornee = root
	ring.AlwaysOnTop = false
	ring.Color3 = Theme.colors.gold
	ring.Transparency = 0.2
	ring.Height = PROGRESS.ringThickness
	ring.Radius = PROGRESS.ringSize / 2
	ring.InnerRadius = PROGRESS.ringSize / 2 - PROGRESS.ringThickness
	ring.CFrame = CFrame.new(0, feet, 0) * flat
	ring.Parent = gui
	local wide = (PROGRESS.ringSize + PROGRESS.ringGrow) / 2
	tween(ring, PROGRESS.ringSeconds, {
		CFrame = CFrame.new(0, feet + PROGRESS.ringRise, 0) * flat,
		Radius = wide,
		InnerRadius = wide - PROGRESS.ringThickness,
		Transparency = 1,
	})
	task.delay(PROGRESS.ringSeconds, function()
		ring:Destroy()
	end)
end

-- World unlock and portals

type PortalSite = {
	model: Model,
	trigger: BasePart?,
	emitter: ParticleEmitter?,
	label: TextLabel?,
}

local sites: { [string]: PortalSite } = {}
local views: { [string]: ProgressEffects.PortalView }? = nil
-- Portals waiting for the badge to finish before they light up.
local waiting: { [string]: boolean } = {}

local function siteLabel(model: Model): TextLabel?
	for _, item in model:GetDescendants() do
		if item:IsA("TextLabel") then
			return item
		end
	end
	return nil
end

local function show(site: PortalSite, view: ProgressEffects.PortalView, lit: boolean)
	local trigger = site.trigger
	if trigger ~= nil then
		trigger.Transparency = if lit
			then PROGRESS.openTransparency
			else PROGRESS.lockedTransparency
	end
	-- An open portal still waiting for the badge keeps its old label.
	local label = site.label
	if label ~= nil and (lit or view.status ~= "open") then
		label.Text = view.label
	end
end

local function nearCamera(part: BasePart): boolean
	local camera = Workspace.CurrentCamera
	if camera == nil then
		return false
	end
	return (camera.CFrame.Position - part.Position).Magnitude <= PROGRESS.swirlDistance
end

local function swirl(site: PortalSite, color: ProgressEffects.RGB)
	local trigger = site.trigger
	if trigger == nil or not nearCamera(trigger) then
		return
	end
	local emitter = site.emitter
	if emitter == nil then
		local made = Instance.new("ParticleEmitter")
		made.Name = "UnlockSwirl"
		made.Enabled = false
		made.Rate = 0
		made.LightEmission = 0.6
		made.Lifetime = NumberRange.new(PROGRESS.swirlLifetime)
		made.Speed = NumberRange.new(PROGRESS.swirlSpeed * 0.5, PROGRESS.swirlSpeed)
		made.SpreadAngle = Vector2.new(180, 180)
		made.Rotation = NumberRange.new(0, 360)
		made.RotSpeed = NumberRange.new(PROGRESS.swirlSpin, PROGRESS.swirlSpin)
		made.Size = NumberSequence.new(PROGRESS.swirlSize, 0)
		made.Transparency = NumberSequence.new(0, 1)
		made.Parent = trigger
		site.emitter = made
		emitter = made
	end
	local e = emitter :: ParticleEmitter
	e.Color = ColorSequence.new(rgbColor(color))
	e:Emit(PROGRESS.swirlParticles)
end

local function lightUp(worldId: string)
	waiting[worldId] = nil
	local current = views
	local site = sites[worldId]
	if current == nil or site == nil then
		return
	end
	local view = current[worldId]
	if view == nil or view.status ~= "open" then
		return
	end
	show(site, view, true)
	swirl(site, view.color)
end

-- A short swirl on screen in the destination world's color.
local function walkSwirl(color: ProgressEffects.RGB)
	local gui = layer
	if gui == nil then
		return
	end
	local ring = blank("PortalSwirl", gui)
	ring.Size = UDim2.fromOffset(PROGRESS.walkSwirlSize, PROGRESS.walkSwirlSize)
	local stroke = Instance.new("UIStroke")
	stroke.Color = rgbColor(color)
	stroke.Thickness = 12
	stroke.Parent = ring
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.25, 0)
	corner.Parent = ring
	local grown = PROGRESS.walkSwirlSize * 3
	tween(ring, PROGRESS.walkSwirlSeconds, {
		Rotation = 360 * PROGRESS.walkSwirlTurns,
		Size = UDim2.fromOffset(grown, grown),
	})
	tween(stroke, PROGRESS.walkSwirlSeconds, { Transparency = 1 })
	task.delay(PROGRESS.walkSwirlSeconds, function()
		ring:Destroy()
	end)
end

local walkedAt = 0

local function hookPortal(instance: Instance)
	if not instance:IsA("Model") then
		return
	end
	local worldId = instance:GetAttribute("WorldId")
	if type(worldId) ~= "string" or sites[worldId] ~= nil then
		return
	end
	local trigger = instance:FindFirstChild("Trigger")
	local site: PortalSite = {
		model = instance,
		trigger = if trigger ~= nil and trigger:IsA("BasePart") then trigger else nil,
		emitter = nil,
		label = siteLabel(instance),
	}
	sites[worldId] = site
	local current = views
	if current ~= nil and current[worldId] ~= nil then
		local view = current[worldId]
		show(site, view, view.status == "open" and not waiting[worldId])
	end
	local part = site.trigger
	if part ~= nil then
		part.Touched:Connect(function(hit: BasePart)
			local character = player.Character
			if character == nil or not hit:IsDescendantOf(character) then
				return
			end
			local now = os.clock()
			if now - walkedAt < PROGRESS.walkSwirlSeconds * 2 then
				return
			end
			local latest = views
			local view = if latest ~= nil then latest[worldId] else nil
			-- The server decides whether the player moves; the swirl only
			-- plays for a portal the server's state already shows open.
			if view ~= nil and view.status == "open" and not waiting[worldId] then
				walkedAt = now
				walkSwirl(view.color)
			end
		end)
	end
end

local function unhookPortal(instance: Instance)
	for worldId, site in sites do
		if site.model == instance then
			sites[worldId] = nil
		end
	end
end

local function onPayload(payload: State.Payload)
	local before = views
	local after = ProgressEffects.portals(payload.profile)
	views = after
	local changes = ProgressEffects.changes(before, after)
	for _, worldId in changes.opened do
		-- The only way a portal opens is a gym win, so it lights once the
		-- badge has played.
		waiting[worldId] = true
		task.delay(EffectsBudget.badgeSeconds(), lightUp, worldId)
	end
	for worldId, view in after do
		local site = sites[worldId]
		if site ~= nil and not waiting[worldId] then
			show(site, view, view.status == "open")
		elseif site ~= nil and view.status ~= "open" then
			waiting[worldId] = nil
			show(site, view, false)
		end
	end
end

-- Builds the effect layer and starts following ProfileChanged. Call once.
function Progress.mount(playerGui: PlayerGui)
	local gui = Instance.new("ScreenGui")
	gui.Name = "ProgressEffects"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 30
	gui.Parent = playerGui
	layer = gui

	for _, instance in CollectionService:GetTagged(PORTAL_TAG) do
		hookPortal(instance)
	end
	CollectionService:GetInstanceAddedSignal(PORTAL_TAG):Connect(hookPortal)
	CollectionService:GetInstanceRemovedSignal(PORTAL_TAG):Connect(unhookPortal)

	State.subscribe(onPayload)
end

return Progress
