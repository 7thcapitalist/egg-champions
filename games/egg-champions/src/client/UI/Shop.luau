--!strict
--[[
	Shop: the screen the menu's Shop button opens, and the only place the game
	passes are offered.

	One row per game pass in config: its name, what it does, and a button.
	Ownership and the Roblox id to prompt are the server's derived "passes"
	field; the client never checks ownership itself. An owned pass shows
	Owned, a pass with no Roblox id yet shows Soon, and any other press opens
	the Roblox purchase prompt. The server grants the pass.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))

local Theme = require(script.Parent:WaitForChild("Theme"))
local Screens = require(script.Parent:WaitForChild("Screens"))
local State = require(script.Parent:WaitForChild("State"))

local colors = Theme.colors
local sizes = Theme.sizes
local textSizes = Theme.textSizes

-- Card width and the width of each row's button, in pixels.
local CARD_WIDTH = 460
local CARD_HEIGHT = 380
local BUY_WIDTH = 110

local Shop = {}

type Row = {
	button: TextButton,
	stroke: UIStroke,
}

local owned: { [string]: boolean } = {}
local known: { [string]: boolean } = {}
local products: { [string]: number } = {}
local prices: { [number]: number } = {}
local unavailable: { [number]: boolean } = {}
local fetching: { [number]: boolean } = {}
local refresh = function() end
local function loadPrices()
	for _, id in products do
		if id > 0 and prices[id] == nil and not fetching[id] and not unavailable[id] then
			fetching[id] = true
			task.spawn(function()
				local ok, info = pcall(function()
					return MarketplaceService:GetProductInfoAsync(id, Enum.InfoType.GamePass)
				end)
				if ok and info.IsForSale and type(info.PriceInRobux) == "number" then
					prices[id] = info.PriceInRobux
				else
					unavailable[id] = true
				end
				fetching[id] = nil
				refresh()
			end)
		end
	end
end

local function readPasses(payload: State.Payload?)
	local list = if payload ~= nil and type(payload.derived.passes) == "table"
		then payload.derived.passes
		else {}
	for _, entry in list do
		if type(entry) == "table" and type(entry.id) == "string" then
			owned[entry.id] = entry.owned == true
			known[entry.id] = entry.known == true
			products[entry.id] = if type(entry.productId) == "number" then entry.productId else 0
		end
	end
end

local function prompt(passId: string)
	if owned[passId] == true or not known[passId] then
		return
	end
	local productId = products[passId]
	if productId == nil or productId <= 0 or prices[productId] == nil then
		return
	end
	pcall(function()
		MarketplaceService:PromptGamePassPurchase(Players.LocalPlayer, productId)
	end)
end

local function plainFrame(name: string, parent: Instance): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.BorderSizePixel = 0
	f.BackgroundTransparency = 1
	f.Parent = parent
	return f
end

-- Builds the shop and registers it as the Shop screen. Call once.
function Shop.mount(playerGui: PlayerGui)
	local gui = Instance.new("ScreenGui")
	gui.Name = "Shop"
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
	card.Size = UDim2.fromScale(0.9, 0.85)
	card.Parent = dim
	local limit = Instance.new("UISizeConstraint")
	limit.MaxSize = Vector2.new(CARD_WIDTH, CARD_HEIGHT)
	limit.Parent = card
	Theme.panel(card, sizes.radius + 2)
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 16)
	padding.PaddingBottom = UDim.new(0, 16)
	padding.PaddingLeft = UDim.new(0, 16)
	padding.PaddingRight = UDim.new(0, 16)
	padding.Parent = card
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.Padding = UDim.new(0, 8)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = card

	local header = plainFrame("Header", card)
	header.LayoutOrder = 0
	header.Size = UDim2.new(1, 0, 0, sizes.minTap)
	local title = Theme.text({
		name = "Title",
		text = Theme.label("Shop"),
		font = Theme.fonts.heading,
		size = textSizes.heading,
		parent = header,
	})
	title.AnchorPoint = Vector2.new(0, 0.5)
	title.Position = UDim2.fromScale(0, 0.5)
	local close = Instance.new("TextButton")
	close.Name = "Close"
	close.AutoButtonColor = true
	close.BorderSizePixel = 0
	close.BackgroundColor3 = colors.panel
	close.TextColor3 = colors.text
	close.FontFace = Theme.fonts.label
	close.TextSize = textSizes.button
	close.Text = Theme.label("Close")
	close.AnchorPoint = Vector2.new(1, 0.5)
	close.Position = UDim2.fromScale(1, 0.5)
	close.Size = UDim2.fromOffset(BUY_WIDTH, sizes.minTap)
	close.Parent = header
	Theme.panel(close, sizes.radius)

	local list = Instance.new("ScrollingFrame")
	list.Name = "PassList"
	list.LayoutOrder = 1
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.ScrollBarThickness = 6
	list.CanvasSize = UDim2.fromOffset(0, 0)
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.Size = UDim2.new(1, 0, 1, -(sizes.minTap + 8 + 32))
	list.Parent = card
	local listLayout = Instance.new("UIListLayout")
	listLayout.FillDirection = Enum.FillDirection.Vertical
	listLayout.Padding = UDim.new(0, 8)
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Parent = list

	local prisms = Instance.new("TextButton")
	prisms.Name, prisms.Text, prisms.TextSize, prisms.FontFace =
		"Prisms", "CAPTURE PRISMS  >", 14, Theme.fonts.label
	prisms.Size, prisms.BackgroundColor3, prisms.TextColor3, prisms.Parent =
		UDim2.new(1, -6, 0, 44), colors.raised, colors.gold, list
	prisms.LayoutOrder = 0
	Theme.panel(prisms)
	prisms.Activated:Connect(function()
		Screens.open(Screens.names.Prisms)
	end)
	local rows: { [string]: Row } = {}
	for position, pass in Config.passes do
		local row = Instance.new("Frame")
		row.Name = "Pass_" .. pass.id
		row.LayoutOrder = position
		row.BorderSizePixel = 0
		row.BackgroundColor3 = colors.raised
		row.Size = UDim2.new(1, 0, 0, sizes.minTap + 16)
		row.Parent = list
		Theme.panel(row, sizes.radius)

		local info = plainFrame("Info", row)
		info.Position = UDim2.fromOffset(12, 0)
		info.Size = UDim2.new(1, -(BUY_WIDTH + 36), 1, 0)
		local infoList = Instance.new("UIListLayout")
		infoList.FillDirection = Enum.FillDirection.Vertical
		infoList.VerticalAlignment = Enum.VerticalAlignment.Center
		infoList.SortOrder = Enum.SortOrder.LayoutOrder
		infoList.Parent = info
		local name = Theme.text({
			name = "Name",
			text = Theme.label(pass.name),
			font = Theme.fonts.label,
			parent = info,
		})
		name.LayoutOrder = 1
		local effect = Theme.text({
			name = "Effect",
			text = pass.effect,
			size = textSizes.small,
			color = colors.muted,
			parent = info,
		})
		effect.LayoutOrder = 2
		effect.TextTruncate = Enum.TextTruncate.AtEnd

		local buy = Instance.new("TextButton")
		buy.Name = "Buy"
		buy.AutoButtonColor = true
		buy.BorderSizePixel = 0
		buy.BackgroundColor3 = colors.panel
		buy.FontFace = Theme.fonts.label
		buy.TextSize = textSizes.button
		buy.AnchorPoint = Vector2.new(1, 0.5)
		buy.Position = UDim2.new(1, -12, 0.5, 0)
		buy.Size = UDim2.fromOffset(BUY_WIDTH, sizes.minTap)
		buy.Parent = row
		Theme.panel(buy, sizes.radius)
		local passId = pass.id
		buy.Activated:Connect(function()
			prompt(passId)
		end)
		rows[pass.id] = { button = buy, stroke = buy:FindFirstChildOfClass("UIStroke") :: UIStroke }
	end

	local function render()
		loadPrices()
		for _, pass in Config.passes do
			local row = rows[pass.id]
			local isOwned = owned[pass.id] == true
			local id = products[pass.id] or 0
			local buyable = known[pass.id] == true and id > 0 and prices[id] ~= nil
			row.button.Interactable = not isOwned and buyable
			row.button.Text = Theme.label(
				if isOwned
					then "Owned"
					elseif buyable then tostring(prices[id]) .. " ROBUX"
					elseif unavailable[id] then "Unavailable"
					elseif id > 0 then "Loading..."
					else "Soon"
			)
			row.button.TextColor3 = if isOwned
				then colors.gold
				elseif buyable then colors.text
				else colors.muted
			row.button.AutoButtonColor = not isOwned and buyable
			row.stroke.Color = if isOwned or buyable then colors.gold else colors.border
		end
	end

	refresh = render
	local function hide()
		gui.Enabled = false
	end
	close.Activated:Connect(hide)
	dim.Activated:Connect(hide)

	render()
	gui.Parent = playerGui
	State.subscribe(function(payload: State.Payload)
		readPasses(payload)
		render()
	end)

	Screens.track(gui)
	Screens.register(Screens.names.Shop, function()
		readPasses(State.get())
		table.clear(unavailable)
		render()
		gui.Enabled = true
	end)
end

return Shop
