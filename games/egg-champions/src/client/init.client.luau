--!strict
--[[
	Client entry point.

	The client only sends requests and shows results. It:
	- keeps the latest state the server sent (UI/State) and builds the main
	  screen (UI/Main), where pressing the world view fires Click and the
	  tutorial card's SKIP sends SkipTutorial;
	- shows the server's Notice messages (such as why a portal refused);
	- builds the egg shop (UI/EggShop), where Hatch and Hatch x3 send BuyEgg;
	- builds the pets and index screen (UI/Pets), where Equip and Unequip send
	  their remotes;
	- opens the egg shop scrolled to a stand's egg when the player touches an
	  egg stand. The server decides whether any purchase goes through;
	- builds the gym battle screen (UI/Battle), which pays the fee, starts the
	  battle and sends each move choice, then plays the server's events;
	- mounts Effects, which pops the coins the server credited (ClickCredited)
	  at each world click and plays the hatch sequence in the egg shop;
	- mounts Progress, the gym win, rebirth and world unlock effects, which
	  shows every portal open or locked from ProfileChanged;
	- builds the rebirth prompt (UI/Rebirth), which sends Rebirth and plays
	  the rebirth effect only when the server confirms it;
	- builds the shop (UI/Shop), the only place game passes are offered;
	- mounts Followers, which shows every nearby player's equipped pets
	  hovering behind them;
	- mounts WorldLighting, which fades the sky, haze and color grade to each
	  world's look when the player enters it.

	The cooldown below is touch debounce timing, not a game number.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local ModelTemplates = require(Shared:WaitForChild("visual"):WaitForChild("ModelTemplates"))
local WorldNames = require(Shared:WaitForChild("world"):WaitForChild("Names"))

local STAND_TAG = "EggStand"
local STAND_COOLDOWN_SECONDS = 2

local player = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild(Remotes.FOLDER)

local UI = script:WaitForChild("UI")
local State = require(UI:WaitForChild("State"))
local Main = require(UI:WaitForChild("Main"))
local EggShop = require(UI:WaitForChild("EggShop"))
local Pets = require(UI:WaitForChild("Pets"))
local Battle = require(UI:WaitForChild("Battle"))
local Rebirth = require(UI:WaitForChild("Rebirth"))
local Shop = require(UI:WaitForChild("Shop"))
local Effects = require(script:WaitForChild("Effects"):WaitForChild("Effects"))
local Progress = require(script:WaitForChild("Effects"):WaitForChild("Progress"))
local Followers = require(script:WaitForChild("Effects"):WaitForChild("Followers"))
local WorldLighting = require(script:WaitForChild("Effects"):WaitForChild("WorldLighting"))

State.start(remotes:WaitForChild(Remotes.names.ProfileChanged) :: RemoteEvent)
Effects.mount(
	player:WaitForChild("PlayerGui") :: PlayerGui,
	remotes:WaitForChild(Remotes.names.ClickCredited) :: RemoteEvent
)
Progress.mount(player:WaitForChild("PlayerGui") :: PlayerGui)
Followers.mount()
WorldLighting.mount()
Main.onWorldClick(Effects.clicked)
Main.mount(
	player:WaitForChild("PlayerGui") :: PlayerGui,
	remotes:WaitForChild(Remotes.names.Click) :: RemoteEvent,
	remotes:WaitForChild(Remotes.names.SkipTutorial) :: RemoteFunction
)
EggShop.mount(
	player:WaitForChild("PlayerGui") :: PlayerGui,
	remotes:WaitForChild(Remotes.names.BuyEgg) :: RemoteFunction
)
Pets.mount(
	player:WaitForChild("PlayerGui") :: PlayerGui,
	remotes:WaitForChild(Remotes.names.Equip) :: RemoteFunction,
	remotes:WaitForChild(Remotes.names.Unequip) :: RemoteFunction
)

Battle.mount(
	player:WaitForChild("PlayerGui") :: PlayerGui,
	remotes:WaitForChild(Remotes.names.PayGymFee) :: RemoteFunction,
	remotes:WaitForChild(Remotes.names.StartBattle) :: RemoteFunction,
	remotes:WaitForChild(Remotes.names.BattleMove) :: RemoteFunction,
	remotes:WaitForChild(Remotes.names.GiveUp) :: RemoteFunction
)

Rebirth.mount(
	player:WaitForChild("PlayerGui") :: PlayerGui,
	remotes:WaitForChild(Remotes.names.Rebirth) :: RemoteFunction
)

Shop.mount(player:WaitForChild("PlayerGui") :: PlayerGui)

local function show(title: string, text: string)
	local ok = pcall(function()
		StarterGui:SetCore("SendNotification", { Title = title, Text = text, Duration = 4 })
	end)
	if not ok then
		print(string.format("[%s] %s", title, text))
	end
end

local notice = remotes:WaitForChild(Remotes.names.Notice) :: RemoteEvent
notice.OnClientEvent:Connect(function(message: any)
	if type(message) == "string" then
		show("Portal", message)
	end
end)

local lastOpen = 0

local function onStandTouched(stand: BasePart, hit: BasePart)
	local character = player.Character
	if character == nil or not hit:IsDescendantOf(character) then
		return
	end
	local eggId = stand:GetAttribute("EggId")
	if type(eggId) ~= "string" then
		return
	end
	local now = os.clock()
	if EggShop.isOpen() or now - lastOpen < STAND_COOLDOWN_SECONDS then
		return
	end
	lastOpen = now
	EggShop.openAt(eggId)
end

local hooked: { [Instance]: boolean } = {}
local function hook(instance: Instance)
	if hooked[instance] or not instance:IsA("BasePart") then
		return
	end
	hooked[instance] = true
	local stand = instance :: BasePart
	stand.Touched:Connect(function(hit: BasePart)
		onStandTouched(stand, hit)
	end)
end

for _, instance in CollectionService:GetTagged(STAND_TAG) do
	hook(instance)
end
CollectionService:GetInstanceAddedSignal(STAND_TAG):Connect(hook)
CollectionService:GetInstanceRemovedSignal(STAND_TAG):Connect(function(instance: Instance)
	hooked[instance] = nil
end)

print("client ready")

-- The asset seam: every pet template the server builds in PetModels
-- replaces that pet's placeholder block here too.
local function useModel(child: Instance)
	ModelTemplates.applySeam(ModelTemplates.seamFrom({ child.Name }))
end
task.spawn(function()
	local models = ReplicatedStorage:WaitForChild("PetModels")
	models.ChildAdded:Connect(useModel)
	for _, child in models:GetChildren() do
		useModel(child)
	end
end)

-- Egg stands: each egg on a stand turns slowly. The server places it and tags
-- it; spinning here keeps the per-frame motion off the network. Spin speed is
-- display timing, not a game number.
local EGG_SPIN_TAG = WorldNames.SPINNING_EGG_TAG
local EGG_SPIN_RADIANS_PER_SECOND = math.rad(40)
local spinning: { [Model]: CFrame } = {}
local function addSpin(instance: Instance)
	if instance:IsA("Model") and instance:IsDescendantOf(workspace) then
		spinning[instance] = instance:GetPivot()
	end
end
for _, instance in CollectionService:GetTagged(EGG_SPIN_TAG) do
	addSpin(instance)
end
CollectionService:GetInstanceAddedSignal(EGG_SPIN_TAG):Connect(addSpin)
CollectionService:GetInstanceRemovedSignal(EGG_SPIN_TAG):Connect(function(instance: Instance)
	spinning[instance :: Model] = nil
end)
game:GetService("RunService").RenderStepped:Connect(function()
	local turn = CFrame.Angles(0, os.clock() * EGG_SPIN_RADIANS_PER_SECOND, 0)
	for model, base in spinning do
		if model.Parent == nil then
			spinning[model] = nil
		else
			model:PivotTo(base * turn)
		end
	end
end)
