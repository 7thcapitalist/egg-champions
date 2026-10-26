--!strict
--[[
	Theme: the approved look of every screen, in one place.

	Colors, type and sizes come from design/ui (Main.dc.html and its README).
	Every UI module reads its colors from here, and this is the only UI file
	that spells out a color. The RGB values are the hex codes of the mockup
	(panel #12161F, border #2A3242, text #F2F4F8, muted #9BA6BA, gold #E8B33A).

	Rarity and type colors live in shared/visual/PetLook, the one place a
	pet's look is defined, so the 2D UI and the 3D pets always agree.

	Barlow is not a Roblox font, so the closest built in families stand in:
	Roboto for Barlow and Roboto Condensed for Barlow Condensed.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local PetLook = require(Shared:WaitForChild("visual"):WaitForChild("PetLook"))
local ThemeColors = require(Shared:WaitForChild("ui"):WaitForChild("ThemeColors"))

local Theme = {}

-- The colors live in shared/ui/ThemeColors, so the server's world signs
-- use the same ones.
Theme.colors = ThemeColors

-- Type and rarity colors come from PetLook, so the UI and the 3D pets agree.
local function color(c: PetLook.RGB): Color3
	return Color3.fromRGB(c.r, c.g, c.b)
end

function Theme.rarityColor(rarityId: string): Color3
	-- An unknown rarity gets PetLook's fallback, the same grey as muted.
	return color(PetLook.rarityColor(rarityId))
end

function Theme.typeColor(typeId: string): Color3
	local c = PetLook.TYPE_COLORS[typeId]
	return if c ~= nil then color(c) else Theme.colors.muted
end

Theme.fonts = table.freeze({
	body = Font.new("rbxasset://fonts/families/Roboto.json", Enum.FontWeight.Medium),
	label = Font.new("rbxasset://fonts/families/Roboto.json", Enum.FontWeight.SemiBold),
	heading = Font.fromEnum(Enum.Font.FredokaOne),
})

Theme.sizes = table.freeze({
	-- The mockups are drawn at 1280 x 720.
	designWidth = 1280,
	topBar = 64,
	gutter = 24,
	radius = 12,
	slotRadius = 8,
	border = 2,
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
	local isButton = frame:IsA("GuiButton")
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, if isButton then 8 else radius or Theme.sizes.radius)
	corner.Parent = frame
	local stroke = Instance.new("UIStroke")
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Color = borderColor or Theme.colors.border
	stroke.Thickness = if isButton then 1 else Theme.sizes.border
	stroke.Transparency = if isButton then 0.2 else 0
	stroke.Parent = frame
	if isButton then
		local gradient = Instance.new("UIGradient")
		gradient.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.new(0.86, 0.89, 0.94))
		gradient.Rotation = 90
		gradient.Parent = frame
	end
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
