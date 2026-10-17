--!strict
-- Celebrate real profile transitions once; never replay rewards on rejoin.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UI = script.Parent.Parent.UI
local State = require(UI.State)
local Theme = require(UI.Theme)
local Config = require(ReplicatedStorage.Shared.Config)
local Tutorial = require(ReplicatedStorage.Shared.rules.Tutorial)
local Milestones = {}
function Milestones.mount(parent: PlayerGui)
	local gui = Instance.new("ScreenGui")
	gui.Name, gui.DisplayOrder, gui.ResetOnSpawn = "Milestones", 60, false
	gui.Parent = parent
	local toast = Theme.text({
		name = "Reward",
		text = "",
		font = Theme.fonts.heading,
		size = 22,
		color = Theme.colors.gold,
		parent = gui,
	})
	toast.AnchorPoint, toast.Position = Vector2.new(0.5, 0), UDim2.fromScale(0.5, 0.16)
	toast.Size, toast.TextWrapped = UDim2.new(0.72, 0, 0, 68), true
	toast.BackgroundColor3, toast.BackgroundTransparency = Theme.colors.panel, 0.08
	toast.Visible = false
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 14)
	corner.Parent = toast
	local limit = Instance.new("UISizeConstraint")
	limit.MaxSize = Vector2.new(600, 68)
	limit.Parent = toast
	local previous: any = nil
	local serial = 0
	local function celebrate(message: string)
		serial += 1
		local current = serial
		toast.Text, toast.Visible, toast.TextTransparency = message, true, 0
		toast.Position = UDim2.fromScale(0.5, 0.13)
		TweenService:Create(
			toast,
			TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
			{ Position = UDim2.fromScale(0.5, 0.16) }
		):Play()
		-- One bounded burst per milestone; no effects for initial profile load.
		for i = 1, 12 do
			local spark = Instance.new("Frame")
			spark.Size = UDim2.fromOffset(5, 12)
			spark.Position = UDim2.fromScale(0.5, 0.2)
			spark.Rotation = i * 37
			spark.BackgroundColor3 = if i % 2 == 0 then Theme.colors.gold else Theme.colors.text
			spark.BorderSizePixel = 0
			spark.Parent = gui
			local a = i * math.pi / 6
			TweenService
				:Create(
					spark,
					TweenInfo.new(0.65, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
					{
						Position = UDim2.new(0.5, math.cos(a) * 130, 0.2, math.sin(a) * 55),
						BackgroundTransparency = 1,
						Rotation = i * 37 + 90,
					}
				)
				:Play()
			game:GetService("Debris"):AddItem(spark, 0.7)
		end
		task.delay(2.1, function()
			if serial == current then
				toast.Visible = false
			end
		end)
	end
	State.subscribe(function(payload)
		local profile = payload.profile
		if previous then
			for _, w in Config.worlds do
				if (profile.badges or {})[w.id] and not (previous.badges or {})[w.id] then
					celebrate(w.name .. " BADGE EARNED!")
				end
			end
			if
				previous.tutorialStep == Tutorial.steps.equip
				and profile.tutorialStep == Tutorial.steps.gym
			then
				celebrate("PET EQUIPPED! Every click is now stronger")
			end
		end
		previous = profile
	end)
end
return Milestones
