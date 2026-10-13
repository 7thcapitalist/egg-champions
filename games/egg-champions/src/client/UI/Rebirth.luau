--!strict
--[[
	Rebirth: the rebirth prompt the menu's Rebirth button opens.

	It shows the cost the server derived (derived.rebirthCost) and what a
	rebirth resets and keeps. Confirm sends the Rebirth remote; the server
	decides. Every reply goes through ProgressEffects.onRebirthReply, so the
	flash and rising ring (client/Effects/Progress) play only when the server
	confirmed the rebirth. A refusal shows the server's reason and plays
	nothing. The new rebirth count and the relocked worlds then arrive through
	ProfileChanged like every other change.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ProgressEffects = require(Shared:WaitForChild("visual"):WaitForChild("ProgressEffects"))

local Progress = require(script.Parent.Parent:WaitForChild("Effects"):WaitForChild("Progress"))
local Theme = require(script.Parent:WaitForChild("Theme"))
local Screens = require(script.Parent:WaitForChild("Screens"))
local State = require(script.Parent:WaitForChild("State"))

local colors = Theme.colors
local sizes = Theme.sizes

-- Card width in pixels, from the battle prompt's card.
local CARD_WIDTH = 460

local Rebirth = {}

local function costNow(): number
	local payload = State.get()
	local cost = if payload ~= nil then payload.derived.rebirthCost else nil
	return if type(cost) == "number" then cost else 0
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

-- Builds the prompt and registers it as the Rebirth screen. Call once.
function Rebirth.mount(playerGui: PlayerGui, rebirthRemote: RemoteFunction)
	local gui = Instance.new("ScreenGui")
	gui.Name = "Rebirth"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 10
	gui.Enabled = false

	local dim = Instance.new("TextButton")
	dim.Name = "Dim"
	dim.Text = ""
	dim.AutoButtonColor = false
	dim.BorderSizePixel = 0
	dim.BackgroundColor3 = colors.backdrop
	dim.BackgroundTransparency = 0.5
	dim.Size = UDim2.fromScale(1, 1)
	dim.Parent = gui

	local card = Instance.new("Frame")
	card.Name = "Card"
	card.Active = true
	card.BorderSizePixel = 0
	card.BackgroundColor3 = colors.panel
	card.AnchorPoint = Vector2.new(0.5, 0.5)
	card.Position = UDim2.fromScale(0.5, 0.5)
	card.Size = UDim2.fromScale(0.9, 0)
	card.AutomaticSize = Enum.AutomaticSize.Y
	card.Parent = dim
	local limit = Instance.new("UISizeConstraint")
	limit.MaxSize = Vector2.new(CARD_WIDTH, math.huge)
	limit.Parent = card
	Theme.panel(card, sizes.radius + 2)
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, sizes.gutter)
	padding.PaddingBottom = UDim.new(0, sizes.gutter)
	padding.PaddingLeft = UDim.new(0, sizes.gutter)
	padding.PaddingRight = UDim.new(0, sizes.gutter)
	padding.Parent = card
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.Padding = UDim.new(0, 12)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = card

	local title = Theme.text({
		name = "Title",
		text = Theme.label("Rebirth"),
		font = Theme.fonts.heading,
		size = Theme.textSizes.heading,
		parent = card,
	})
	title.LayoutOrder = 1
	local function wrapped(name: string, order: number, color: Color3): TextLabel
		local label = Theme.text({ name = name, color = color, parent = card })
		label.LayoutOrder = order
		label.AutomaticSize = Enum.AutomaticSize.Y
		label.Size = UDim2.fromScale(1, 0)
		label.TextWrapped = true
		label.TextXAlignment = Enum.TextXAlignment.Left
		return label
	end
	local body = wrapped("Body", 2, colors.text)
	local status = wrapped("Status", 3, colors.gold)
	status.Visible = false

	local row = Instance.new("Frame")
	row.Name = "Buttons"
	row.BackgroundTransparency = 1
	row.BorderSizePixel = 0
	row.LayoutOrder = 4
	row.Size = UDim2.new(1, 0, 0, sizes.minTap)
	row.Parent = card
	local rowLayout = Instance.new("UIListLayout")
	rowLayout.FillDirection = Enum.FillDirection.Horizontal
	rowLayout.Padding = UDim.new(0, 10)
	rowLayout.SortOrder = Enum.SortOrder.LayoutOrder
	rowLayout.Parent = row
	local confirm, confirmStroke = button("Confirm", row)
	confirm.LayoutOrder = 1
	confirm.Size = UDim2.new(0.6, -5, 1, 0)
	confirm.Text = Theme.label("Rebirth")
	confirm.TextColor3 = colors.gold
	confirmStroke.Color = colors.gold
	local cancel = button("Cancel", row)
	cancel.LayoutOrder = 2
	cancel.Size = UDim2.new(0.4, -5, 1, 0)
	cancel.Text = Theme.label("Cancel")

	gui.Parent = playerGui

	local busy = false

	local function close()
		gui.Enabled = false
	end

	local function open()
		body.Text = ProgressEffects.rebirthPromptText(costNow())
		status.Text = ""
		status.Visible = false
		gui.Enabled = true
	end

	confirm.Activated:Connect(function()
		if busy then
			return
		end
		busy = true
		confirm.Text = Theme.label("Waiting")
		local ok, reply = pcall(function(): any
			return rebirthRemote:InvokeServer()
		end)
		busy = false
		confirm.Text = Theme.label("Rebirth")
		local answer = if ok then reply else nil
		if ProgressEffects.onRebirthReply(answer, Progress.playRebirth) then
			close()
			return
		end
		local reason = if type(answer) == "table" then answer.reason else nil
		status.Text = ProgressEffects.rebirthReasonText(reason)
		status.Visible = true
	end)
	cancel.Activated:Connect(close)
	dim.Activated:Connect(close)

	State.subscribe(function()
		if gui.Enabled and not busy then
			body.Text = ProgressEffects.rebirthPromptText(costNow())
		end
	end)

	Screens.register(Screens.names.Rebirth, open)
end

return Rebirth
