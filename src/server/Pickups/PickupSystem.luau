--!strict
-- XP orbs on the floor. Rules (Config.Policies.xpOwnership = "exclusive-first-valid-claim"):
--   * A broken container drops orbs. The player who broke it has first claim for Config.Pickups.reserveSeconds.
--   * The client asks with PickupRequest when it is close. The server checks the match, the phase, that the
--     participant is alive, that the orb is still there and unclaimed, and the distance. First valid claim wins.
--   * An orb lasts Config.Pickups.lifetimeSeconds. The client pull toward the player is only a look.
--   * Orbs are server Parts in Workspace.Pickups (tagged "Pickup"), so late joiners see them too.
-- Other pieces: PickupSystem.tryClaim(participantId, position, pickupId) is what bots call to collect.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)

local Net = require(script.Parent.Parent.Core.Net)
local MatchContext = require(script.Parent.Parent.Core.MatchContext)
local Participants = require(script.Parent.Parent.Core.Participants)
local RunXp = require(script.Parent.Parent.Core.RunXp)

local ContainerRules = require(script.Parent.ContainerRules)
local PickupRules = require(script.Parent.PickupRules)

local PickupSystem = {}
PickupSystem.order = 100

local TAG = "Pickup"

type Record = { part: BasePart, data: PickupRules.Pickup }

local records: { [string]: Record } = {}
local oldestFirst: { string } = {}
local nextNumber = 0
local folder: Folder? = nil
local sinceCheck = 0

local function getFolder(): Folder
	if folder and folder.Parent then
		return folder
	end
	local found = Workspace:FindFirstChild(Config.Workspace.PickupsFolder)
	if found and found:IsA("Folder") then
		folder = found
		return found
	end
	local made = Instance.new("Folder")
	made.Name = Config.Workspace.PickupsFolder
	made.Parent = Workspace
	folder = made
	return made
end

local function remove(id: string, collectedBy: string?)
	local record = records[id]
	if record == nil then
		return
	end
	records[id] = nil
	local at = table.find(oldestFirst, id)
	if at then
		table.remove(oldestFirst, at)
	end
	local position = record.part.Position
	record.part:Destroy()
	Net.fireAll("PickupRemoved", { pickupId = id, collectedBy = collectedBy, pos = position })
end

-- Drops `count` orbs on a ring around `floorPoint`. `reservedFor` gets first claim for a short time.
function PickupSystem.spawnOrbs(floorPoint: Vector3, count: number, reservedFor: string?)
	local cfg = Config.Pickups
	local matchId = MatchContext:getMatchId()
	local now = os.clock()
	local serverNow = Workspace:GetServerTimeNow()
	local offsets = ContainerRules.scatter(count, cfg.scatterRadius, math.random() * 2 * math.pi)
	for _, offset in offsets do
		while #oldestFirst >= cfg.maxActive do
			remove(oldestFirst[1], nil)
		end
		nextNumber += 1
		local id = `o{matchId}_{nextNumber}`
		local part = Instance.new("Part")
		part.Name = "XpOrb"
		part.Shape = Enum.PartType.Ball
		part.Size = Vector3.new(cfg.orbSize, cfg.orbSize, cfg.orbSize)
		part.Material = Enum.Material.Neon
		part.Color = Color3.fromHex(Config.Palette.RewardGold)
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.CastShadow = false
		part.Position = floorPoint + Vector3.new(offset.x, cfg.orbHeight, offset.z)
		part:SetAttribute("PickupId", id)
		part:SetAttribute("ExpiresAt", serverNow + cfg.lifetimeSeconds) -- server time, for the client blink
		part:SetAttribute("ReservedFor", reservedFor or "")
		part:SetAttribute(
			"ReservedUntil",
			if reservedFor then serverNow + cfg.reserveSeconds else 0
		)
		part:AddTag(TAG)
		part.Parent = getFolder()

		records[id] = {
			part = part,
			data = {
				id = id,
				matchId = matchId,
				expiresAt = now + cfg.lifetimeSeconds,
				reservedFor = reservedFor,
				reservedUntil = if reservedFor then now + cfg.reserveSeconds else 0,
				claimed = false,
			},
		}
		table.insert(oldestFirst, id)
		Net.fireAll("PickupSpawned", { pickupId = id, kind = "xp", pos = part.Position })
	end
end

-- The one place a claim is decided, for players (PickupRequest) and bots. `position` is where the
-- claimant really is, read by the server, never sent by a client.
function PickupSystem.tryClaim(
	participantId: string,
	position: Vector3,
	pickupId: string
): (boolean, string?)
	if not MatchContext:isCombat() then
		return false, "not-combat"
	end
	if not Participants:isAlive(participantId) then
		return false, "not-alive"
	end
	local record = records[pickupId]
	if record == nil then
		return false, "gone"
	end
	local ok, reason = PickupRules.check(
		record.data,
		participantId,
		os.clock(),
		(record.part.Position - position).Magnitude,
		Config.Pickups.collectRadius,
		Config.Pickups.claimSlack,
		MatchContext:getMatchId()
	)
	if not ok then
		return false, reason
	end
	record.data.claimed = true
	RunXp:award(participantId, "orbPickup")
	remove(pickupId, participantId)
	return true, nil
end

-- Removes every orb. Used when a match is over or a new one begins.
function PickupSystem.clear()
	for id in table.clone(records) do
		remove(id, nil)
	end
	for _, leftover in CollectionService:GetTagged(TAG) do
		leftover:Destroy()
	end
end

local function expire()
	local now = os.clock()
	for id, record in table.clone(records) do
		if now >= record.data.expiresAt then
			remove(id, nil)
		end
	end
end

function PickupSystem.start()
	Net.onRequest("PickupRequest", function(player: Player, pickupId: string)
		local participant = Participants:ofPlayer(player)
		local character = player.Character
		local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
		if participant == nil or root == nil or not root:IsA("BasePart") then
			return
		end
		PickupSystem.tryClaim(participant.id, root.Position, pickupId)
	end)

	MatchContext.MatchStarted:connect(function()
		PickupSystem.clear()
	end)
	MatchContext.PhaseChanged:connect(function(phase: string)
		if phase == "Resetting" or phase == "Waiting" then
			PickupSystem.clear()
		end
	end)

	RunService.Heartbeat:Connect(function(dt: number)
		sinceCheck += dt
		if sinceCheck >= Config.Pickups.expireCheckSeconds then
			sinceCheck = 0
			expire()
		end
	end)
end

return PickupSystem
