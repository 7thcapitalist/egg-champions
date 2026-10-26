--!strict
--[[
	Reveal: the centered card after every hatch. For each pet that hatched it
	shows the pet model, name, rarity in the rarity color, a Shiny or Golden
	badge and "Click +N", with one "Nice!" button under them.

	It closes when the player taps "Nice!" or after HatchReveal.SECONDS, then
	calls onDone. What it shows and when it ends come from shared/ui/
	HatchReveal; every number comes from the server's reply.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local PetVisual = require(Shared:WaitForChild("PetVisual"))
local HatchReveal = require(Shared:WaitForChild("ui"):WaitForChild("HatchReveal"))

local Theme = require(script.Parent:WaitForChild("Theme"))

local colors = Theme.colors
local sizes = Theme.sizes
local textSizes = Theme.textSizes

-- Card look, in pixels. Display only.
local PET_SIZE = 120
local ENTRY_WIDTH = 170
local CARD_PAD = 18
local ENTRY_GAP = 14
local BUTTON_WIDTH = 160
local Z = 70

local Reveal = {}

local function list(parent: Instance, direction: Enum.FillDirection, gap: number): UIListLayout
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = direction
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, gap)
	layout.Parent = parent
	return layout
end

local function blank(name: string, parent: Instance): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.BackgroundTransparency = 1
	f.BorderSizePixel = 0
	f.ZIndex = Z
	f.Parent = parent
	return f
end

local function line(parent: Instance, name: string, text: string, color: Color3, size: number, order: number)
	local label = Theme.text({
		name = name,
		text = text,
		font = Theme.fonts.label,
		size = size,
		color = color,
		parent = parent,
	})
	label.LayoutOrder = order
	label.ZIndex = Z + 1
	return label
end

local function entryView(parent: Instance, entry: HatchReveal.Entry, order: number)
	local rarityColor = Theme.rarityColor(entry.rarity)
	local column = blank("Pet" .. order, parent)
	column.LayoutOrder = order
	column.Size = UDim2.fromOffset(ENTRY_WIDTH, 0)
	column.AutomaticSize = Enum.AutomaticSize.Y
	list(column, Enum.FillDirection.Vertical, 4)

	local block = blank("Block", column)
	block.LayoutOrder = 1
	block.BackgroundTransparency = 0
	block.BackgroundColor3 = colors.raised
	block.Size = UDim2.fromOffset(PET_SIZE, PET_SIZE)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, sizes.radius)
	corner.Parent = block
	local stroke = Instance.new("UIStroke")
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Thickness = 3
	stroke.Color = rarityColor
	stroke.Parent = block
	PetVisual.view(block, entry.petId, entry.variant, nil).ZIndex = Z + 1

	line(column, "Name", entry.name, colors.text, textSizes.heading, 2)
	line(column, "Rarity", Theme.label(entry.rarityName), rarityColor, textSizes.body, 3)
	local badge = entry.badge
	if badge ~= nil then
		local pill = Instance.new("TextLabel")
		pill.Name = "Badge"
		pill.LayoutOrder = 4
		pill.AutomaticSize = Enum.AutomaticSize.X
		pill.Size = UDim2.fromOffset(0, sizes.badge + 4)
		pill.BackgroundColor3 = colors.gold
		pill.BorderSizePixel = 0
		pill.FontFace = Theme.fonts.label
		pill.TextSize = textSizes.small
		pill.TextColor3 = colors.panel
		pill.Text = "  " .. Theme.label(badge) .. "  "
		pill.ZIndex = Z + 1
		local pillCorner = Instance.new("UICorner")
		pillCorner.CornerRadius = UDim.new(0.5, 0)
		pillCorner.Parent = pill
		pill.Parent = column
	end
	local click = entry.clickText
	if click ~= nil then
		line(column, "Click", click, colors.gold, textSizes.petName, 5)
	end
end

-- Shows the reveal over parent and calls onDone once it closes.
function Reveal.show(parent: Instance, entries: { HatchReveal.Entry }, onDone: (() -> ())?)
	local closed = false
	local function done()
		if onDone ~= nil then
			onDone()
		end
	end
	if #entries == 0 then
		done()
		return
	end

	local backdrop = Instance.new("TextButton")
	backdrop.Name = "PetReveal"
	backdrop.Text = ""
	backdrop.AutoButtonColor = false
	backdrop.Active = true
	backdrop.BackgroundColor3 = colors.backdrop
	backdrop.BackgroundTransparency = 0.4
	backdrop.BorderSizePixel = 0
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.ZIndex = Z - 1
	backdrop.Parent = parent

	local card = blank("Card", backdrop)
	card.AnchorPoint = Vector2.new(0.5, 0.5)
	card.Position = UDim2.fromScale(0.5, 0.5)
	card.AutomaticSize = Enum.AutomaticSize.XY
	card.BackgroundTransparency = 0
	card.BackgroundColor3 = colors.panel
	Theme.panel(card, sizes.radius, colors.gold)
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, CARD_PAD)
	padding.PaddingBottom = UDim.new(0, CARD_PAD)
	padding.PaddingLeft = UDim.new(0, CARD_PAD)
	padding.PaddingRight = UDim.new(0, CARD_PAD)
	padding.Parent = card
	list(card, Enum.FillDirection.Vertical, ENTRY_GAP)

	local row = blank("Pets", card)
	row.LayoutOrder = 1
	row.AutomaticSize = Enum.AutomaticSize.XY
	list(row, Enum.FillDirection.Horizontal, ENTRY_GAP)
	for order, entry in entries do
		entryView(row, entry, order)
	end

	local nice = Instance.new("TextButton")
	nice.Name = "Nice"
	nice.LayoutOrder = 2
	nice.AutoButtonColor = true
	nice.BorderSizePixel = 0
	nice.BackgroundColor3 = colors.hatch
	nice.TextColor3 = colors.white
	nice.FontFace = Theme.fonts.label
	nice.TextSize = textSizes.button
	nice.Text = Theme.label(HatchReveal.BUTTON)
	nice.Size = UDim2.fromOffset(BUTTON_WIDTH, sizes.minTap)
	nice.ZIndex = Z + 1
	local niceCorner = Instance.new("UICorner")
	niceCorner.CornerRadius = UDim.new(0, sizes.radius)
	niceCorner.Parent = nice
	nice.Parent = card

	local openedAt = os.clock()
	local tapped = false
	local function close()
		if closed then
			return
		end
		closed = true
		backdrop:Destroy()
		done()
	end
	nice.Activated:Connect(function()
		tapped = true
		close()
	end)
	task.spawn(function()
		while not closed do
			if HatchReveal.ended(openedAt, os.clock(), tapped) then
				close()
				return
			end
			RunService.Heartbeat:Wait()
		end
	end)
end

return Reveal
