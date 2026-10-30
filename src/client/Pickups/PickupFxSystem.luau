--!strict
-- What you see and do for containers and XP orbs. The server owns all of it; this only draws and asks.
--   * Containers flash when hit and burst when broken (color and size by loot tier).
--   * Orbs bob, spin, lean toward you when close, and blink before they vanish.
--   * Phone first: nothing to press. When you are close to an orb the client asks for it by itself
--     (PickupRequest). The server checks distance, phase and who got there first.

local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)

local Net = require(script.Parent.Parent.Core.Net)

local PickupFxSystem = {}

local ORB_TAG = "Pickup"
local BLINK_SECONDS = 5 -- orbs blink this long before they vanish
local ASK_SECONDS = 0.15 -- least time between two PickupRequests
local RE_ASK_SECONDS = 0.4 -- least time before asking for the same orb again
local SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"
local BURST_SIZE = { common = 12, rare = 18, epic = 30 }

local localPlayer = Players.LocalPlayer
local liveEffects = 0

-- Containers and orbs seen so far, by the ids the server uses in its messages.
type Seen = { part: BasePart, tier: string, base: Color3 }
local containers: { [string]: Seen } = {}
type Orb = { base: Vector3, phase: number, askedAt: number }
local orbs: { [BasePart]: Orb } = {}
local lastAsk = 0

local function emit(position: Vector3, count: number, speed: number, first: Color3, second: Color3)
	if liveEffects >= Config.Perf.maxLiveEffects then
		return
	end
	liveEffects += 1
	local anchor = Instance.new("Part")
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(0.2, 0.2, 0.2)
	anchor.Position = position

	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = SPARKLE
	emitter.Rate = 0
	emitter.Lifetime = NumberRange.new(0.4, 0.7)
	emitter.Speed = NumberRange.new(speed * 0.6, speed)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Size =
		NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.9), NumberSequenceKeypoint.new(1, 0) })
	emitter.Color = ColorSequence.new(first, second)
	emitter.LightEmission = 0.6
	emitter.Parent = anchor
	anchor.Parent = Workspace
	emitter:Emit(count)

	Debris:AddItem(anchor, 1.2)
	task.delay(1.2, function()
		liveEffects -= 1
	end)
end

local function seeContainer(inst: Instance)
	if not inst:IsA("BasePart") then
		return
	end
	local id = inst:GetAttribute("ContainerId")
	local tier = inst:GetAttribute("Tier")
	if typeof(id) == "string" and typeof(tier) == "string" then
		containers[id] = { part = inst, tier = tier, base = inst.Color }
	end
end

local function seeOrb(inst: Instance)
	if inst:IsA("BasePart") then
		orbs[inst] = { base = inst.Position, phase = math.random() * math.pi * 2, askedAt = 0 }
	end
end

local function onHit(payload: any)
	if type(payload) ~= "table" then
		return
	end
	local seen = containers[payload.containerId]
	if seen == nil or seen.part.Parent == nil then
		return
	end
	seen.part.Color = Color3.fromHex(Config.Containers.flashColor)
	TweenService:Create(seen.part, TweenInfo.new(0.15), { Color = seen.base }):Play()
end

local function onBroken(payload: any)
	if type(payload) ~= "table" or typeof(payload.pos) ~= "Vector3" then
		return
	end
	local seen = containers[payload.containerId]
	containers[payload.containerId] = nil
	local tier = if seen then seen.tier else "common"
	local color = Color3.fromHex(Config.Containers.tiers[tier].color)
	emit(payload.pos, BURST_SIZE[tier] or 12, 22, Color3.fromHex(Config.Palette.RewardGold), color)
end

local function onRemoved(payload: any)
	if type(payload) ~= "table" or typeof(payload.pos) ~= "Vector3" then
		return
	end
	local gold = Color3.fromHex(Config.Palette.RewardGold)
	emit(payload.pos, 6, 10, gold, Color3.new(1, 1, 1))
end

local function step()
	if next(orbs) == nil then
		return
	end
	local now = Workspace:GetServerTimeNow()
	local clock = os.clock()
	local character = localPlayer.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	local rootPosition = if root and root:IsA("BasePart") then root.Position else nil
	local myId = "p" .. tostring(localPlayer.UserId)

	local nearest: BasePart? = nil
	local nearestDistance = math.huge

	for part, orb in orbs do
		if part.Parent == nil then
			orbs[part] = nil
		else
			local position = orb.base + Vector3.new(0, 0.5 * math.sin(clock * 3 + orb.phase), 0)
			if rootPosition then
				local reservedFor = part:GetAttribute("ReservedFor")
				local reservedUntil = part:GetAttribute("ReservedUntil")
				local mine = reservedFor == nil
					or reservedFor == ""
					or reservedFor == myId
					or (typeof(reservedUntil) == "number" and now >= reservedUntil)
				local distance = (rootPosition - orb.base).Magnitude
				if mine and distance < Config.Pickups.magnetRadius then
					-- Only a look: the orb leans toward you. The server decides who gets it.
					position = position:Lerp(
						rootPosition,
						0.8 * (1 - distance / Config.Pickups.magnetRadius)
					)
					if distance <= Config.Pickups.collectRadius and distance < nearestDistance then
						if clock - orb.askedAt >= RE_ASK_SECONDS then
							nearest = part
							nearestDistance = distance
						end
					end
				end
			end
			part.CFrame = CFrame.new(position) * CFrame.Angles(0, clock * 2 + orb.phase, 0)

			local expiresAt = part:GetAttribute("ExpiresAt")
			if typeof(expiresAt) == "number" and expiresAt - now < BLINK_SECONDS then
				part.Transparency = if math.floor(clock * 6) % 2 == 0 then 0 else 0.6
			end
		end
	end

	-- One ask at a time, nearest first, so the request limit is never the thing that loses you an orb.
	if nearest and clock - lastAsk >= ASK_SECONDS then
		local id = nearest:GetAttribute("PickupId")
		if typeof(id) == "string" then
			lastAsk = clock
			orbs[nearest].askedAt = clock
			Net.send("PickupRequest", id)
		end
	end
end

function PickupFxSystem.start()
	for _, inst in CollectionService:GetTagged(Config.Tags.SupplyContainer) do
		seeContainer(inst)
	end
	CollectionService:GetInstanceAddedSignal(Config.Tags.SupplyContainer):Connect(seeContainer)
	for _, inst in CollectionService:GetTagged(ORB_TAG) do
		seeOrb(inst)
	end
	CollectionService:GetInstanceAddedSignal(ORB_TAG):Connect(seeOrb)

	Net.on("ContainerHit", onHit)
	Net.on("ContainerBroken", onBroken)
	Net.on("PickupRemoved", onRemoved)
	RunService.RenderStepped:Connect(step)
end

return PickupFxSystem
