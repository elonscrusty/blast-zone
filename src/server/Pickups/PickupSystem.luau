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
local MoveGuard = require(script.Parent.Parent.AntiCheat.MoveGuard)

local HealPacks = require(script.Parent.Parent.Loot.HealPacks)
local ContainerRules = require(script.Parent.ContainerRules)
local PickupRules = require(script.Parent.PickupRules)

local PickupSystem = {}
PickupSystem.order = 100

local TAG = "Pickup"

type Record = { part: BasePart, data: PickupRules.Pickup, kind: string } -- kind: "xp" or "heal"

local records: { [string]: Record } = {}
local oldestFirst: { string } = {} -- XP orbs only (they are the ones that crowd the cap)
local healOldest: { string } = {}
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
	local list = if record.kind == "heal" then healOldest else oldestFirst
	local at = table.find(list, id)
	if at then
		table.remove(list, at)
	end
	local position = record.part.Position
	record.part:Destroy()
	Net.fireAll(
		"PickupRemoved",
		{ pickupId = id, collectedBy = collectedBy, pos = position, kind = record.kind }
	)
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
			kind = "xp",
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

-- Puts one heal pack on the floor at `floorPoint` (piece 42). Packs wait Config.Loot.heal.lifetimeSeconds,
-- are claimed by the same rules as orbs, and only count against their own cap.
function PickupSystem.spawnHeal(floorPoint: Vector3): string?
	local cfg = Config.Loot.heal
	if not MatchContext:isCombat() and MatchContext:getPhase() ~= "Spawning" then
		return nil
	end
	local matchId = MatchContext:getMatchId()
	local now = os.clock()
	local serverNow = Workspace:GetServerTimeNow()
	while #healOldest >= cfg.maxOnFloor do
		remove(healOldest[1], nil)
	end
	nextNumber += 1
	local id = `h{matchId}_{nextNumber}`
	local part = Instance.new("Part")
	part.Name = "HealPack"
	part.Size = Vector3.new(cfg.size, cfg.size, cfg.size)
	part.Material = Enum.Material.Neon
	part.Color = Color3.fromHex(cfg.color)
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Position = floorPoint + Vector3.new(0, Config.Pickups.orbHeight + 0.5, 0)
	part:SetAttribute("PickupId", id)
	part:SetAttribute("Kind", "heal")
	part:SetAttribute("ExpiresAt", serverNow + cfg.lifetimeSeconds)
	part:SetAttribute("ReservedFor", "")
	part:SetAttribute("ReservedUntil", 0)
	-- Placeholder look: a white plus that always faces the camera. Claude Design owns the real one.
	local gui = Instance.new("BillboardGui")
	gui.Name = "Plus"
	gui.Size = UDim2.fromScale(cfg.size * 1.4, cfg.size * 1.4)
	gui.AlwaysOnTop = false
	gui.LightInfluence = 0
	local plus = Instance.new("TextLabel")
	plus.BackgroundTransparency = 1
	plus.Size = UDim2.fromScale(1, 1)
	plus.Text = "+"
	plus.Font = Enum.Font.GothamBlack
	plus.TextScaled = true
	plus.TextColor3 = Color3.fromHex(cfg.crossColor)
	plus.Parent = gui
	gui.Parent = part
	part:AddTag(TAG)
	part.Parent = getFolder()
	records[id] = {
		part = part,
		kind = "heal",
		data = {
			id = id,
			matchId = matchId,
			expiresAt = now + cfg.lifetimeSeconds,
			reservedFor = nil,
			reservedUntil = 0,
			claimed = false,
		},
	}
	table.insert(healOldest, id)
	Net.fireAll("PickupSpawned", { pickupId = id, kind = "heal", pos = part.Position })
	return id
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
	if record.kind == "heal" then
		-- A full bag leaves the pack where it is (nothing is claimed).
		if not HealPacks.add(participantId) then
			return false, "full"
		end
	else
		RunXp:award(participantId, "orbPickup")
	end
	record.data.claimed = true
	remove(pickupId, participantId)
	return true, nil
end

-- Removes every orb. Used when a match is over or a new one begins.
-- No message per orb: a destroyed part is already gone from every screen, and a whole floor of orbs
-- would otherwise be sixty broadcasts in one frame at the end of every match.
function PickupSystem.clear()
	for _, record in records do
		record.part:Destroy()
	end
	table.clear(records)
	table.clear(oldestFirst)
	table.clear(healOldest)
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
		-- Where the server believes the player is (piece 27), never a spot a cheat just jumped to.
		local position = MoveGuard.trustedPosition(player)
		if participant == nil or position == nil or MoveGuard.isHeld(participant.id) then
			return
		end
		PickupSystem.tryClaim(participant.id, position, pickupId)
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
