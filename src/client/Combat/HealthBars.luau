--!strict
-- A small health bar over every fighter's head, read from the Health / MaxHealth attributes the server
-- keeps on the character. Your own bar belongs to the HUD, so it is skipped. An enemy bar shows for a
-- few seconds after their health changes, so the arena is not full of bars.
-- With Config.Plates.enabled (piece 46) the always-on name plate in Moments/PlateSystem replaces that
-- bar; this file then only keeps the id -> model list and tells the plates when a fighter appears.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Look = require(script.Parent.Parent.Ui.Look)

local HealthBars = {}

local CORAL = Look.color("danger")
local NAVY = Look.color("outline")

-- Every fighter's model by participant id, so a hit can find who it landed on without scanning the map.
local models: { [string]: Model } = {}

-- Fighters already announced to the listeners (weak, so a removed model is not held).
local announced: { [Model]: boolean } = setmetatable({}, { __mode = "k" }) :: any
local listeners: { (Model) -> () } = {}

-- `fn` runs once for every fighter model, now and whenever a new one appears.
function HealthBars.onFighter(fn: (Model) -> ())
	table.insert(listeners, fn)
	for model in announced do
		task.spawn(fn, model)
	end
end

function HealthBars.modelOf(id: string): Model?
	local model = models[id]
	if model ~= nil and model.Parent ~= nil then
		return model
	end
	return nil
end

local function attach(model: Model)
	local id = model:GetAttribute(Config.Attributes.ParticipantId)
	if typeof(id) == "string" then
		models[id] = model
	end
	if not announced[model] then
		announced[model] = true
		for _, fn in listeners do
			task.spawn(fn, model)
		end
	end
	if Config.Plates.enabled then
		return -- the name plate carries the bar
	end
	if model:FindFirstChild("CombatHealthBar") ~= nil then
		return
	end
	if model == Players.LocalPlayer.Character then
		return
	end
	local root = model:FindFirstChild("HumanoidRootPart")
	if root == nil or not root:IsA("BasePart") then
		return
	end
	local gui = Instance.new("BillboardGui")
	gui.Name = "CombatHealthBar"
	gui.Size = UDim2.fromOffset(64, 8)
	gui.StudsOffset = Vector3.new(0, 3.6, 0)
	gui.LightInfluence = 0
	gui.AlwaysOnTop = false
	gui.Enabled = false
	gui.Adornee = root
	gui.Parent = model
	local back = Instance.new("Frame")
	back.Size = UDim2.fromScale(1, 1)
	back.BackgroundColor3 = NAVY
	back.BorderSizePixel = 0
	back.Parent = gui
	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = CORAL
	fill.BorderSizePixel = 0
	fill.Parent = back

	local shownUntil = 0
	local lastHealth: number? = nil
	local function refresh()
		local hp = model:GetAttribute("Health")
		local max = model:GetAttribute("MaxHealth")
		local alive = model:GetAttribute("Alive")
		if typeof(hp) ~= "number" or typeof(max) ~= "number" or max <= 0 then
			gui.Enabled = false
			return
		end
		fill.Size = UDim2.fromScale(math.clamp(hp / max, 0, 1), 1)
		if lastHealth ~= nil and hp < lastHealth then
			shownUntil = os.clock() + Config.Combat.healthBarSeconds
		end
		lastHealth = hp
		gui.Enabled = alive ~= false and hp < max
		if gui.Enabled then
			task.delay(Config.Combat.healthBarSeconds + 0.05, function()
				if gui.Parent ~= nil and os.clock() >= shownUntil then
					gui.Enabled = false
				end
			end)
		end
	end
	model:GetAttributeChangedSignal("Health"):Connect(refresh)
	model:GetAttributeChangedSignal("Alive"):Connect(refresh)
	refresh()
end

local function consider(inst: Instance)
	if inst:IsA("Model") then
		if inst:GetAttribute(Config.Attributes.ParticipantId) ~= nil then
			attach(inst)
		else
			inst:GetAttributeChangedSignal(Config.Attributes.ParticipantId):Once(function()
				attach(inst)
			end)
		end
	end
end

-- Fighters sit at the top of Workspace (or in Workspace.Participants), so only those places are watched.
-- Listening to every descendant meant a callback for every spark, damage number and orb that ever appeared.
local function watch(holder: Instance)
	for _, child in holder:GetChildren() do
		consider(child)
	end
	holder.ChildAdded:Connect(consider)
end

function HealthBars.start()
	watch(Workspace)
	local folder = Workspace:FindFirstChild("Participants")
	if folder ~= nil then
		watch(folder)
	end
	Workspace.ChildAdded:Connect(function(child)
		if child.Name == "Participants" then
			watch(child)
		end
	end)
end

return HealthBars
