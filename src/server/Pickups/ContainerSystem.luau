--!strict
-- Supply containers. Built on every part tagged ContainerSpot when a match reaches Spawning, removed
-- when it ends. The server keeps the health; each container breaks once.
--
-- Whoever lands a shot calls (piece 03, after IT checked range, walls and ammo):
--   ContainerSystem.damage(hitPart, amount, sourceId, matchId) -> true when hitPart is a container
-- so the shot stops there. `amount` is the weapon's own number, never anything from a client.
-- Nothing happens unless a combat phase is running, the match is current and the source is alive.
--
-- A ContainerSpot marker is a Part whose BOTTOM face is on the floor. Its "Tier" attribute
-- ("common", "rare" or "epic") forces a tier; with no attribute the tier is rolled by weight.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)

local Net = require(script.Parent.Parent.Core.Net)
local MatchContext = require(script.Parent.Parent.Core.MatchContext)
local Participants = require(script.Parent.Parent.Core.Participants)
local RunXp = require(script.Parent.Parent.Core.RunXp)

local ContainerRules = require("./ContainerRules")
local PickupSystem = require("./PickupSystem")

local ContainerSystem = {}
ContainerSystem.order = 110

type Record = {
	id: string,
	model: Model,
	body: BasePart,
	health: number,
	max: number,
	tier: string,
	matchId: number,
}

local byBody: { [BasePart]: Record } = {}
local byId: { [string]: Record } = {}
local folder: Folder? = nil

local function getFolder(): Folder
	if folder and folder.Parent then
		return folder
	end
	local found = Workspace:FindFirstChild(Config.Workspace.ContainersFolder)
	if found and found:IsA("Folder") then
		folder = found
		return found
	end
	local made = Instance.new("Folder")
	made.Name = Config.Workspace.ContainersFolder
	made.Parent = Workspace
	folder = made
	return made
end

-- The marker's own "Tier" wins if it names a real tier. Otherwise roll by weight.
local function tierFor(spot: BasePart): string
	local forced = spot:GetAttribute("Tier")
	if typeof(forced) == "string" and Config.Containers.tiers[forced] ~= nil then
		return forced
	end
	return ContainerRules.pickTier(Config.Containers.tierOrder, function(id: string): number
		return Config.Containers.tiers[id].weight
	end, math.random())
end

local function build(spot: BasePart, matchId: number, number: number): Record
	local cfg = Config.Containers
	local tier = tierFor(spot)
	local info = cfg.tiers[tier]
	local size = cfg.size
	local floorPoint = spot.Position - Vector3.new(0, spot.Size.Y / 2, 0)
	local _, yaw, _ = spot.CFrame:ToOrientation()
	local cframe = CFrame.new(floorPoint + Vector3.new(0, size / 2, 0)) * CFrame.Angles(0, yaw, 0)
	local id = `c{matchId}_{number}`

	local model = Instance.new("Model")
	model.Name = "SupplyContainer"

	local body = Instance.new("Part")
	body.Name = "Body"
	body.Size = Vector3.new(size, size, size)
	body.CFrame = cframe
	body.Color = Color3.fromHex(info.color)
	body.Material = Enum.Material.SmoothPlastic
	body.Anchored = true
	body.CanCollide = true -- blocks walking and shots, like a wall
	body.CanQuery = true
	body.CanTouch = false
	body.CastShadow = false
	body.Parent = model

	local band = Instance.new("Part")
	band.Name = "Band"
	band.Size = Vector3.new(size + 0.2, size * 0.2, size + 0.2)
	band.CFrame = cframe
	band.Color = Color3.fromHex(cfg.bandColor)
	band.Material = Enum.Material.Neon
	band.Anchored = true
	band.CanCollide = false
	band.CanQuery = false
	band.CanTouch = false
	band.CastShadow = false
	band.Parent = model

	model.PrimaryPart = body
	body:SetAttribute("ContainerId", id)
	body:SetAttribute("Tier", tier)
	body:AddTag(Config.Tags.SupplyContainer)
	body:AddTag(Config.Tags.BlocksShots)
	model.Parent = getFolder()

	return {
		id = id,
		model = model,
		body = body,
		health = info.health,
		max = info.health,
		tier = tier,
		matchId = matchId,
	}
end

-- Puts one container on every ContainerSpot marker. Returns how many were made.
function ContainerSystem.spawnAll(matchId: number): number
	ContainerSystem.clear()
	local made = 0
	for _, inst in CollectionService:GetTagged(Config.Tags.ContainerSpot) do
		if inst:IsA("BasePart") and inst:IsDescendantOf(Workspace) then
			made += 1
			local record = build(inst, matchId, made)
			byBody[record.body] = record
			byId[record.id] = record
		end
	end
	return made
end

function ContainerSystem.clear()
	for _, record in byBody do
		record.model:Destroy()
	end
	table.clear(byBody)
	table.clear(byId)
	for _, leftover in CollectionService:GetTagged(Config.Tags.SupplyContainer) do
		local model = leftover.Parent
		if model then
			model:Destroy()
		end
	end
end

function ContainerSystem.isContainer(hit: Instance): boolean
	return hit:IsA("BasePart") and byBody[hit] ~= nil
end

local function breakContainer(record: Record, breakerId: string)
	-- Gone from the tables first, so a second hit in the same moment finds nothing to break.
	byBody[record.body] = nil
	byId[record.id] = nil
	local center = record.body.Position
	local floorPoint = center - Vector3.new(0, Config.Containers.size / 2, 0)
	Net.fireAll("ContainerBroken", { containerId = record.id, pos = center })
	RunXp:award(breakerId, "containerBreak")
	PickupSystem.spawnOrbs(floorPoint, Config.Containers.tiers[record.tier].orbs, breakerId)
	record.model:Destroy()
end

function ContainerSystem.damage(
	hit: Instance,
	amount: number,
	sourceId: string?,
	matchId: number?
): boolean
	if not hit:IsA("BasePart") then
		return false
	end
	local record = byBody[hit]
	if record == nil then
		return false
	end
	-- It IS a container, so the shot stops here. Whether it hurts is decided below.
	local current = MatchContext:getMatchId()
	if
		not MatchContext:isCombat()
		or record.matchId ~= current
		or (matchId ~= nil and matchId ~= current)
		or sourceId == nil
		or not Participants:isAlive(sourceId)
	then
		return true
	end
	local health, broke = ContainerRules.applyDamage(record.health, amount)
	if health == record.health then
		return true
	end
	record.health = health
	Net.fireAll("ContainerHit", { containerId = record.id, health = health, max = record.max })
	if broke then
		breakContainer(record, sourceId)
	end
	return true
end

function ContainerSystem.start()
	MatchContext.MatchStarted:connect(function()
		ContainerSystem.clear()
	end)
	MatchContext.PhaseChanged:connect(function(phase: string, _old: string, matchId: number)
		if phase == "Spawning" then
			ContainerSystem.spawnAll(matchId)
		elseif phase == "Resetting" or phase == "Waiting" then
			ContainerSystem.clear()
		end
	end)
end

return ContainerSystem
