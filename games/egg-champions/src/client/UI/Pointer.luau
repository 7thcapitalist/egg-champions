--!strict
--[[
	Pointer: the tutorial's pulsing outline around the thing to use next.

	Screens register the buttons the tutorial can point at under a name (see
	Tutorial.card for the names): "menu:<entry>", "hatch:<eggId>", "equip".
	A "gym:<worldId>" target is the gym model in the world, found by name, and
	gets a pulsing Highlight instead of an outline.

	Pointer.set picks the current target, or nil for none. A button that is
	registered again (such as EQUIP, rebuilt with the pets detail) gets the
	outline again. The pulse timing below is display timing, not a game number.
]]

local TweenService = game:GetService("TweenService")

local Theme = require(script.Parent:WaitForChild("Theme"))

local OUTLINE_NAME = "TutorialPointer"
local OUTLINE_GROW = 6
local OUTLINE_THICKNESS = 3
local PULSE_SECONDS = 0.6
local GYM_PREFIX = "gym:"
local GYM_MODEL_PREFIX = "Gym_"
-- How often a gym that is not in the world yet is looked for again.
local GYM_RETRY_SECONDS = 1

local Pointer = {}

local targets: { [string]: GuiObject } = {}
local current: string? = nil
local shown: Instance? = nil
local pulse: Tween? = nil
local lastLook = -math.huge

local function clear()
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
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = box
	box.Parent = target
	shown = box
	pulseOn(stroke, { Transparency = 0.8 })
end

local function highlightGym(worldId: string)
	local model = workspace:FindFirstChild(GYM_MODEL_PREFIX .. worldId, true)
	if model == nil or not model:IsA("Model") then
		return
	end
	local highlight = Instance.new("Highlight")
	highlight.Name = OUTLINE_NAME
	highlight.Adornee = model
	highlight.FillColor = Theme.colors.gold
	highlight.OutlineColor = Theme.colors.gold
	highlight.FillTransparency = 0.85
	highlight.OutlineTransparency = 0
	highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	highlight.Parent = model
	shown = highlight
	pulseOn(highlight, { OutlineTransparency = 0.7, FillTransparency = 1 })
end

local function refresh()
	clear()
	lastLook = os.clock()
	local name = current
	if name == nil then
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
