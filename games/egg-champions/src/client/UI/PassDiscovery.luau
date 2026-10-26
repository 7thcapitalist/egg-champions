--!strict
-- Optional store discovery. Never starts a payment prompt; the shop owns that action.
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Layout = require(Shared.ui.WildLayout)
local State = require(script.Parent.State)
local Theme = require(script.Parent.Theme)
local Screens = require(script.Parent.Screens)
local Discovery = {}
function Discovery.mount(parent: PlayerGui)
	local gui = Instance.new("ScreenGui")
	gui.IgnoreGuiInset = true
	gui.Name, gui.ResetOnSpawn, gui.DisplayOrder = "PassDiscovery", false, 12
	gui.Parent = parent
	local frame = Instance.new("Frame")
	frame.Name, frame.AnchorPoint = "OptionalBoosts", Vector2.new(1, 0)
	frame.Position, frame.Size = UDim2.new(1, -12, 0, 68), UDim2.fromOffset(154, 44)
	frame.BackgroundColor3, frame.Visible, frame.Parent = Theme.colors.panel, false, gui
	Theme.panel(frame)
	local open = Instance.new("TextButton")
	open.Name, open.TextSize, open.FontFace = "OpenBoostShop", 14, Theme.fonts.label
	open.BackgroundTransparency, open.TextColor3 = 1, Theme.colors.gold
	open.Size, open.Parent = UDim2.new(1, -44, 1, 0), frame
	local close = Instance.new("TextButton")
	close.Name, close.Text, close.TextSize = "Dismiss", "X", 16
	close.BackgroundTransparency, close.TextColor3 = 1, Theme.colors.muted
	close.Position, close.Size, close.Parent = UDim2.new(1, -44, 0, 0), UDim2.fromOffset(44, 44), frame
	local dismissed, introduced = false, false
	local latest: any = nil
	local wildGui = parent:FindFirstChild("WildEncounter")
	local wildCard = if wildGui then wildGui:FindFirstChild("FocusBattle") else nil
	local wildInvite = if wildGui then wildGui:FindFirstChild("EncounterInvite") else nil
	local function render()
		local offer: string? = nil
		if latest then
			for _, pass in latest.derived.passes or {} do
				if
					pass.known == true
					and not pass.owned
					and type(pass.productId) == "number"
					and pass.productId > 0
				then
					for _, config in Config.passes do
						if config.id == pass.id then
							offer = config.name
							break
						end
					end
					if offer then
						break
					end
				end
			end
		end
		local blockers = {}
		local main = parent:FindFirstChild("Main")
		local content = if main then main:FindFirstChild("Content") else nil
		if content then
			for _, part in content:GetChildren() do
				if part:IsA("GuiObject") and part.Visible then
					table.insert(blockers, {
						x = part.AbsolutePosition.X,
						y = part.AbsolutePosition.Y,
						width = part.AbsoluteSize.X,
						height = part.AbsoluteSize.Y,
					})
				end
			end
		end
		local camera = workspace.CurrentCamera
		local spot = if camera then Layout.offer(camera.ViewportSize.X, camera.ViewportSize.Y, blockers) else nil
		if spot then
			frame.Position = UDim2.fromOffset(spot.x + spot.width, spot.y)
		end
		frame.Visible = spot ~= nil
			and not dismissed
			and offer ~= nil
			and latest ~= nil
			and #(latest.profile.pets or {}) > 0
			and Players.LocalPlayer:GetAttribute("TrainingWorld") ~= nil
			and not Screens.anyOpen()
			and not (wildCard and wildCard:IsA("GuiObject") and wildCard.Visible)
			and not (wildInvite and wildInvite:IsA("GuiObject") and wildInvite.Visible)
		open.Text = (offer or "BOOSTS") .. " >"
		if frame.Visible and not introduced then
			introduced = true
			local stroke = frame:FindFirstChildOfClass("UIStroke")
			if stroke then
				stroke.Color = Theme.colors.gold
				TweenService:Create(
					stroke,
					TweenInfo.new(0.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, 2, true),
					{ Transparency = 0.8 }
				):Play()
			end
		end
	end
	open.Activated:Connect(function()
		Screens.open(Screens.names.Shop)
	end)
	close.Activated:Connect(function()
		dismissed = true
		render()
	end)
	State.subscribe(function(payload)
		latest = payload
		render()
	end)
	Screens.onChange(render)
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(render)
	if wildInvite then
		wildInvite:GetPropertyChangedSignal("Visible"):Connect(render)
	end
	if wildCard then
		wildCard:GetPropertyChangedSignal("Visible"):Connect(render)
	end
	Players.LocalPlayer:GetAttributeChangedSignal("TrainingWorld"):Connect(render)
end
return Discovery
