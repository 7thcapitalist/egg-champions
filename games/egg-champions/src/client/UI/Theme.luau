--!strict
--[[
	Theme: the approved look of every screen, in one place.

	Colors, type and sizes come from design/ui (Main.dc.html and its README).
	Every UI module reads its colors from here, and this is the only UI file
	that spells out a color. The RGB values are the hex codes of the mockup
	(panel #12161F, border #2A3242, text #F2F4F8, muted #9BA6BA, gold #E8B33A).

	Rarity colors follow the rarity order in config: the lowest rarity gets
	the first color of RARITY_PALETTE, the next one the second, and so on.
	The palette runs Common grey, Uncommon green, Rare blue, Epic purple,
	Legendary orange. A rarity past the end of the palette reuses its last
	color.

	Barlow is not a Roblox font, so the closest built in families stand in:
	Roboto for Barlow and Roboto Condensed for Barlow Condensed.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local Theme = {}

Theme.colors = table.freeze({
	panel = Color3.fromRGB(18, 22, 31),
	raised = Color3.fromRGB(30, 37, 50),
	border = Color3.fromRGB(42, 50, 66),
	text = Color3.fromRGB(242, 244, 248),
	muted = Color3.fromRGB(155, 166, 186),
	gold = Color3.fromRGB(232, 179, 58),
	badgeEmpty = Color3.fromRGB(90, 100, 120),
})

-- Lowest rarity first.
local RARITY_PALETTE = table.freeze({
	Color3.fromRGB(155, 166, 186),
	Color3.fromRGB(76, 191, 115),
	Color3.fromRGB(76, 141, 255),
	Color3.fromRGB(192, 155, 255),
	Color3.fromRGB(255, 174, 69),
})

-- Pets are colored blocks until the asset stage, tinted by type.
local TYPE_COLORS: { [string]: Color3 } = {
	fire = Color3.fromRGB(217, 98, 58),
	water = Color3.fromRGB(63, 142, 209),
	grass = Color3.fromRGB(79, 163, 82),
	electric = Color3.fromRGB(214, 190, 63),
}

local rarityColors: { [string]: Color3 } = {}
do
	local ordered = table.clone(Config.rarities)
	table.sort(ordered, function(a, b)
		return a.order < b.order
	end)
	for rank, rarity in ordered do
		rarityColors[rarity.id] = RARITY_PALETTE[math.min(rank, #RARITY_PALETTE)]
	end
end

function Theme.rarityColor(rarityId: string): Color3
	return rarityColors[rarityId] or Theme.colors.muted
end

function Theme.typeColor(typeId: string): Color3
	return TYPE_COLORS[typeId] or Theme.colors.muted
end

Theme.fonts = table.freeze({
	body = Font.new("rbxasset://fonts/families/Roboto.json", Enum.FontWeight.Medium),
	label = Font.new("rbxasset://fonts/families/Roboto.json", Enum.FontWeight.SemiBold),
	heading = Font.new("rbxasset://fonts/families/RobotoCondensed.json", Enum.FontWeight.Bold),
})

Theme.sizes = table.freeze({
	-- The mockups are drawn at 1280 x 720.
	designWidth = 1280,
	topBar = 64,
	gutter = 24,
	radius = 6,
	slotRadius = 4,
	border = 1,
	minTap = 44,
	menuWidth = 132,
	menuButton = 46,
	goalWidth = 270,
	goalMinWidth = 200,
	slotWidth = 168,
	petBlock = 40,
	stripe = 4,
	bar = 6,
	badge = 20,
	coin = 22,
})

Theme.textSizes = table.freeze({
	coins = 34,
	worldName = 24,
	heading = 24,
	body = 15,
	small = 12,
	petName = 16,
	petPower = 13,
	button = 15,
})

-- Labels are uppercase across the game.
function Theme.label(text: string): string
	return string.upper(text)
end

-- Small corner radius and a thin border, the look of every panel.
function Theme.panel(frame: GuiObject, radius: number?, borderColor: Color3?)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius or Theme.sizes.radius)
	corner.Parent = frame
	local stroke = Instance.new("UIStroke")
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Color = borderColor or Theme.colors.border
	stroke.Thickness = Theme.sizes.border
	stroke.Parent = frame
end

-- A text label with the theme's defaults and no background.
function Theme.text(props: {
	name: string,
	text: string?,
	font: Font?,
	size: number?,
	color: Color3?,
	parent: Instance?,
}): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = props.name
	label.BackgroundTransparency = 1
	label.BorderSizePixel = 0
	label.FontFace = props.font or Theme.fonts.body
	label.TextSize = props.size or Theme.textSizes.body
	label.TextColor3 = props.color or Theme.colors.text
	label.Text = props.text or ""
	label.AutomaticSize = Enum.AutomaticSize.XY
	label.Size = UDim2.fromOffset(0, 0)
	label.Parent = props.parent
	return label
end

return Theme
