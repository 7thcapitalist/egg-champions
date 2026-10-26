--!strict
--[[
	Pointer: the tutorial's pulsing outline around the thing to use next.

	Screens register the buttons the tutorial can point at under a name (see
	Tutorial.card for the names): "menu:<entry>", "hatch:<eggId>", "equip".
	A "gym:<worldId>" target is the gym model in the world, found by name. It
	gets a pulsing Highlight instead of an outline, a gold Beam along the
	ground from the player's feet to the gym floor, and an arrow at the
	screen edge whenever the gym is off camera (placed by shared/ui/EdgeArrow).

	A button gets a 6 px gold outline that pulses between opaque and a
	little lighter (never faint), plus a gold arrow beside it that bounces
	toward it (placed by EdgeArrow.beside, drawn above every screen).

	Pointer.set picks the current target, or nil for none. A button that is
	registered again (such as EQUIP, rebuilt with the pets detail) gets the
	outline again. The pulse timing below is display timing, not a game number.
]]

local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EdgeArrow =
	require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ui"):WaitForChild("EdgeArrow"))

local WorldNames =
	require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("world"):WaitForChild("Names"))

local Theme = require(script.Parent:WaitForChild("Theme"))

local OUTLINE_NAME = "TutorialPointer"
local OUTLINE_GROW = 6
-- Outline: thickness in pixels at the two ends of the pulse, and its
-- transparency at the light end (the other end is fully opaque).
local OUTLINE_THICKNESS = 6
local OUTLINE_THICKNESS_PULSE = 5
local OUTLINE_PULSE_TRANSPARENCY = 0.3
local PULSE_SECONDS = 0.6
-- Bouncing arrow beside a button: size, gap to the button, bounce distance
-- and one bounce in seconds, all in pixels. Drawn above every screen.
local POINT_ARROW_SIZE = 44
local POINT_ARROW_GAP = 6
local POINT_ARROW_BOUNCE = 12
local POINT_ARROW_SECONDS = 0.7
local POINT_ARROW_ORDER = 50
local GYM_PREFIX = "gym:"
local TRAINING_PREFIX = "training:"
local TrainingSites = require(ReplicatedStorage.Shared.world.TrainingSites)
-- How often a gym that is not in the world yet is looked for again.
local GYM_RETRY_SECONDS = 1
-- Gym highlight: fill and outline transparency at the two ends of the pulse.
local GYM_FILL = 0.6
local GYM_FILL_PULSE = 0.8
local GYM_OUTLINE_PULSE = 0.4
-- Gym beam: width in studs, how far below the root part it starts (the
-- feet), and how far above the gym floor it ends.
local BEAM_WIDTH = 1.2
local BEAM_DROP = 2.6
local BEAM_LIFT = 0.6
local BEAM_TRANSPARENCY = 0.25
-- Screen-edge arrow: size and distance from the screen edge, in pixels.
local ARROW_SIZE = 56
local ARROW_MARGIN = 48

local Pointer = {}

local targets: { [string]: GuiObject } = {}
local current: string? = nil
local shown: Instance? = nil
local pulse: Tween? = nil
local lastLook = -math.huge
-- The beam, the arrow and their per-frame loop while a gym is the target.
local extras: { Instance } = {}
local loop: RBXScriptConnection? = nil

local function clear()
	if loop ~= nil then
		loop:Disconnect()
		loop = nil
	end
	for _, extra in extras do
		extra:Destroy()
	end
	table.clear(extras)
	if pulse ~= nil then
		pulse:Cancel()
		pulse = nil
	end
	if shown ~= nil then
		shown:Destroy()
		shown = nil
	end
end

local function pulseOn(instance: Instance, goal: { [string]: any })
	local info =
		TweenInfo.new(PULSE_SECONDS, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
	local tween = TweenService:Create(instance, info, goal)
	tween:Play()
	pulse = tween
end

-- True when target and every GuiObject above it are visible and its
-- ScreenGui is enabled, so the arrow only shows beside a button on screen.
local function onScreen(target: GuiObject): boolean
	local node: Instance? = target
	while node ~= nil do
		if node:IsA("GuiObject") and not node.Visible then
			return false
		end
		if node:IsA("LayerCollector") then
			return node.Enabled
		end
		node = node.Parent
	end
	return false
end

-- The gold arrow beside a button, bouncing toward it.
local function pointArrow(target: GuiObject)
	local playerGui = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
	if playerGui == nil then
		return
	end
	local gui = Instance.new("ScreenGui")
	gui.Name = OUTLINE_NAME .. "Point"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = POINT_ARROW_ORDER
	local arrow = Instance.new("TextLabel")
	arrow.Name = "Arrow"
	arrow.BackgroundTransparency = 1
	arrow.AnchorPoint = Vector2.new(0.5, 0.5)
	arrow.Size = UDim2.fromOffset(POINT_ARROW_SIZE, POINT_ARROW_SIZE)
	arrow.FontFace = Theme.fonts.heading
	arrow.Text = ">"
	arrow.TextScaled = true
	arrow.TextColor3 = Theme.colors.gold
	arrow.TextStrokeColor3 = Theme.colors.panel
	arrow.TextStrokeTransparency = 0
	arrow.Visible = false
	arrow.Active = false
	arrow.Parent = gui
	gui.Parent = playerGui
	table.insert(extras, gui)

	loop = RunService.RenderStepped:Connect(function()
		if target.Parent == nil or not onScreen(target) then
			arrow.Visible = false
			return
		end
		local size = gui.AbsoluteSize
		local wave = (math.sin(os.clock() * 2 * math.pi / POINT_ARROW_SECONDS) + 1) / 2
		local placed = EdgeArrow.beside({ x = size.X, y = size.Y }, {
			x = target.AbsolutePosition.X,
			y = target.AbsolutePosition.Y,
			w = target.AbsoluteSize.X,
			h = target.AbsoluteSize.Y,
		}, POINT_ARROW_SIZE, POINT_ARROW_GAP, wave * POINT_ARROW_BOUNCE)
		arrow.Visible = placed.visible
		arrow.Position = UDim2.fromOffset(placed.x, placed.y)
		arrow.Rotation = placed.angle
	end)
end

local function outline(target: GuiObject)
	local box = Instance.new("Frame")
	box.Name = OUTLINE_NAME
	box.BackgroundTransparency = 1
	box.BorderSizePixel = 0
	box.AnchorPoint = Vector2.new(0.5, 0.5)
	box.Position = UDim2.fromScale(0.5, 0.5)
	box.Size = UDim2.new(1, OUTLINE_GROW * 2, 1, OUTLINE_GROW * 2)
	box.ZIndex = target.ZIndex + 1
	box.Active = false
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, Theme.sizes.radius + OUTLINE_GROW)
	corner.Parent = box
	local stroke = Instance.new("UIStroke")
	stroke.Color = Theme.colors.gold
	stroke.Thickness = OUTLINE_THICKNESS
	stroke.Transparency = 0
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = box
	box.Parent = target
	shown = box
	pulseOn(
		stroke,
		{ Transparency = OUTLINE_PULSE_TRANSPARENCY, Thickness = OUTLINE_THICKNESS_PULSE }
	)
	pointArrow(target)
end

local function highlightGym(worldId: string, training: boolean?)
	local model = workspace:FindFirstChild(
		if training then TrainingSites.modelName(worldId) else WorldNames.gymModel(worldId),
		true
	)
	if model == nil or not model:IsA("Model") then
		return
	end
	local highlight = Instance.new("Highlight")
	highlight.Name = OUTLINE_NAME
	highlight.Adornee = model
	highlight.FillColor = Theme.colors.gold
	highlight.OutlineColor = Theme.colors.gold
	highlight.FillTransparency = GYM_FILL
	highlight.OutlineTransparency = 0
	highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	highlight.Parent = model
	shown = highlight
	pulseOn(
		highlight,
		{ OutlineTransparency = GYM_OUTLINE_PULSE, FillTransparency = GYM_FILL_PULSE }
	)

	-- Where the beam ends: on the gym floor, or the model's pivot.
	local floor = model:FindFirstChild("Floor", true)
	local anchorPart: BasePart? = if floor ~= nil and floor:IsA("BasePart")
		then floor
		else model:FindFirstChildWhichIsA("BasePart", true)
	if anchorPart == nil then
		return
	end
	local goal = Instance.new("Attachment")
	goal.Name = OUTLINE_NAME .. "End"
	goal.Position = Vector3.new(0, anchorPart.Size.Y / 2 + BEAM_LIFT, 0)
	goal.Parent = anchorPart
	table.insert(extras, goal)

	local beam = Instance.new("Beam")
	beam.Name = OUTLINE_NAME .. "Beam"
	beam.Attachment1 = goal
	beam.Color = ColorSequence.new(Theme.colors.gold)
	beam.Transparency = NumberSequence.new(BEAM_TRANSPARENCY)
	beam.Width0 = BEAM_WIDTH
	beam.Width1 = BEAM_WIDTH
	beam.FaceCamera = true
	beam.LightEmission = 0.5
	beam.Segments = 1
	beam.Parent = anchorPart
	table.insert(extras, beam)

	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")
	local gui = Instance.new("ScreenGui")
	gui.Name = OUTLINE_NAME .. "Arrow"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	local holder = Instance.new("Frame")
	holder.Name = "Holder"
	holder.AnchorPoint = Vector2.new(0.5, 0.5)
	holder.Size = UDim2.fromOffset(ARROW_SIZE, ARROW_SIZE)
	holder.BackgroundColor3 = Theme.colors.panel
	holder.BackgroundTransparency = 0.15
	holder.BorderSizePixel = 0
	holder.Visible = false
	holder.Parent = gui
	local round = Instance.new("UICorner")
	round.CornerRadius = UDim.new(0.5, 0)
	round.Parent = holder
	local ring = Instance.new("UIStroke")
	ring.Color = Theme.colors.gold
	ring.Thickness = 2
	ring.Parent = holder
	local arrow = Instance.new("TextLabel")
	arrow.Name = "Arrow"
	arrow.BackgroundTransparency = 1
	arrow.AnchorPoint = Vector2.new(0.5, 0.5)
	arrow.Position = UDim2.fromScale(0.5, 0.5)
	arrow.Size = UDim2.fromScale(1, 1)
	arrow.FontFace = Theme.fonts.heading
	arrow.Text = ">"
	arrow.TextScaled = true
	arrow.TextColor3 = Theme.colors.gold
	arrow.Parent = holder
	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.BackgroundTransparency = 1
	label.AnchorPoint = Vector2.new(0.5, 0)
	label.Position = UDim2.new(0.5, 0, 1, 2)
	label.Size = UDim2.fromOffset(ARROW_SIZE * 2, 18)
	label.FontFace = Theme.fonts.label
	label.Text = if training then "TRAIN" else "GYM"
	label.TextSize = Theme.textSizes.small
	label.TextColor3 = Theme.colors.gold
	label.TextStrokeTransparency = 0.4
	label.Parent = holder
	gui.Parent = playerGui
	table.insert(extras, gui)

	local start: Attachment? = nil
	loop = RunService.RenderStepped:Connect(function()
		-- Follow the current character, so a respawn keeps the beam.
		local character = player.Character
		local root = if character ~= nil then character:FindFirstChild("HumanoidRootPart") else nil
		if root ~= nil and root:IsA("BasePart") then
			if start == nil or start.Parent ~= root then
				if start ~= nil then
					start:Destroy()
				end
				local made = Instance.new("Attachment")
				made.Name = OUTLINE_NAME .. "Start"
				made.Position = Vector3.new(0, -BEAM_DROP, 0)
				made.Parent = root
				start = made
				table.insert(extras, made)
				beam.Attachment0 = made
			end
		end

		local camera = workspace.CurrentCamera
		if camera == nil or anchorPart.Parent == nil then
			holder.Visible = false
			return
		end
		local projected = camera:WorldToViewportPoint(anchorPart.Position)
		local size = camera.ViewportSize
		local placed = EdgeArrow.place(
			{ x = size.X, y = size.Y },
			{ x = projected.X, y = projected.Y },
			projected.Z,
			ARROW_MARGIN
		)
		holder.Visible = placed.visible
		if placed.visible then
			holder.Position = UDim2.fromOffset(placed.x, placed.y)
			arrow.Rotation = placed.angle
		end
	end)
end

local function refresh()
	clear()
	lastLook = os.clock()
	local name = current
	if name == nil then
		return
	end
	if string.sub(name, 1, #TRAINING_PREFIX) == TRAINING_PREFIX then
		highlightGym(string.sub(name, #TRAINING_PREFIX + 1), true)
		return
	end
	if string.sub(name, 1, #GYM_PREFIX) == GYM_PREFIX then
		highlightGym(string.sub(name, #GYM_PREFIX + 1))
		return
	end
	local target = targets[name]
	if target ~= nil and target.Parent ~= nil then
		outline(target)
	end
end

-- Registers a button the tutorial can point at. Registering a name again
-- replaces the old button.
function Pointer.register(name: string, target: GuiObject)
	targets[name] = target
	if name == current then
		refresh()
	end
end

-- Forgets a name's button, such as an EQUIP button that is gone.
function Pointer.unregister(name: string, target: GuiObject)
	if targets[name] == target then
		targets[name] = nil
		if name == current then
			refresh()
		end
	end
end

-- Points at a target by name, or at nothing for nil. Setting the same name
-- again looks for it again, so a gym that streamed in late is found.
function Pointer.set(name: string?)
	if name == current then
		if shown ~= nil and shown.Parent ~= nil then
			return
		end
		-- Not found last time: look again, but not on every state push.
		if os.clock() - lastLook < GYM_RETRY_SECONDS then
			return
		end
	end
	current = name
	refresh()
end

return Pointer
