--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Format = require(Shared:WaitForChild("ui"):WaitForChild("Format"))
local Theme = require(script.Parent.Theme)
local State = require(script.Parent.State)

local OfflineReward = {}

function OfflineReward.mount(playerGui: PlayerGui)
	local shown = false
	State.subscribe(function(payload: State.Payload)
		local reward = payload.derived.offlineReward
		if shown or type(reward) ~= "table" or type(reward.coins) ~= "number" or reward.coins <= 0 then
			return
		end
		shown = true
		local gui = Instance.new("ScreenGui")
		gui.Name = "OfflineReward"
		gui.ResetOnSpawn = false
		gui.DisplayOrder = 30
		local card = Instance.new("Frame")
		card.AnchorPoint = Vector2.new(0.5, 0)
		card.Position = UDim2.new(0.5, 0, 0, 66)
		card.Size = UDim2.fromOffset(280, 72)
		card.BackgroundColor3 = Theme.colors.panel
		Theme.panel(card)
		card.Parent = gui
		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.Position = UDim2.fromOffset(10, 8)
		label.Size = UDim2.new(1, -56, 1, -16)
		label.FontFace = Theme.fonts.label
		label.TextSize = 15
		label.TextColor3 = Theme.colors.text
		label.TextWrapped = true
		label.Text = "WELCOME BACK!\nPets earned +" .. Format.abbreviate(reward.coins) .. " coins"
		label.Parent = card
		local close = Instance.new("TextButton")
		close.BackgroundTransparency = 1
		close.Size = UDim2.fromOffset(44, 44)
		close.Position = UDim2.new(1, -44, 0, 0)
		close.Text = "X"
		close.TextSize = 18
		close.TextColor3 = Theme.colors.text
		close.Parent = card
		close.Activated:Connect(function()
			gui:Destroy()
		end)
		gui.Parent = playerGui
		task.delay(12, function()
			gui:Destroy()
		end)
	end)
end

return OfflineReward
