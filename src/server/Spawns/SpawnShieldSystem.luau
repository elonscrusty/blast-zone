--!strict
-- Spawn shield (piece 21). When the fight starts, everyone alive (bots too) gets a short shield so
-- nobody is shot before they can look around. Hits on a shielded target are dropped at the damage
-- door. Firing ends your own shield (Combat/Firing). The look is Roblox's glowing ForceField.

local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local MatchPhase = require(Shared.MatchPhase)

local Core = ServerScriptService:WaitForChild("Server"):WaitForChild("Core")
local Damage = require(Core.Damage)
local MatchContext = require(Core.MatchContext)
local Participants = require(Core.Participants)
local SpawnShields = require(Core.SpawnShields)

local SpawnShieldSystem = {}
SpawnShieldSystem.order = 250 -- after the match flow, before bots

local FIELD_NAME = "SpawnShieldField"
local ATTRIBUTE = "SpawnShield" -- on the body: true while shielded (for HUD or effects)

local fields: { [string]: ForceField } = {}

local function bodyOf(id: string): Model?
	local p = Participants:get(id)
	local player = p and p.player
	if player then
		return player.Character
	end
	-- Bots: rigs carry the ParticipantId attribute (piece 09).
	for _, inst in Workspace:GetDescendants() do
		if inst:IsA("Model") and inst:GetAttribute(Config.Attributes.ParticipantId) == id then
			return inst
		end
	end
	return nil
end

local function removeField(id: string)
	local field = fields[id]
	fields[id] = nil
	if field then
		local body = field.Parent
		if body then
			body:SetAttribute(ATTRIBUTE, nil)
		end
		field:Destroy()
	end
end

local function addField(id: string)
	local body = bodyOf(id)
	if not body then
		return
	end
	removeField(id)
	local field = Instance.new("ForceField")
	field.Name = FIELD_NAME
	field.Visible = true
	field.Parent = body
	body:SetAttribute(ATTRIBUTE, true)
	fields[id] = field
end

local function clearAll()
	SpawnShields:clear()
	for id in fields do
		removeField(id)
	end
end

function SpawnShieldSystem.start()
	Damage:addGuard(SpawnShields:guard())

	MatchContext.PhaseChanged:connect(function(phase: string)
		if phase == MatchPhase.Active then
			local seconds = Config.SpawnShield.seconds
			for _, p in Participants:aliveList() do
				SpawnShields:give(p.id, seconds)
				addField(p.id)
			end
		elseif not MatchPhase.isCombat(phase) then
			clearAll()
		end
	end)

	-- Take the glow off as soon as a shield ends (time up, fired, or eliminated).
	task.spawn(function()
		while true do
			task.wait(0.1)
			for id in fields do
				if not SpawnShields:isShielded(id) or not Participants:isAlive(id) then
					SpawnShields:drop(id)
					removeField(id)
				end
			end
		end
	end)
end

return SpawnShieldSystem
