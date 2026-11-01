--!strict
-- Server-side lava bomb parts. A glowing orange ball falls from the sky and lands exactly when the
-- Burp Director says (landsAt); then it pops into a quick expanding ring that fades. The ground
-- circle (telegraph) is drawn by the client from the Bombs remote; these parts are only the fall + puff.
--
--   BombVisuals.init()
--   BombVisuals.spawn(bomb: Types.Bomb, now: number) -> boolean   false when 40 bombs are already live
--   BombVisuals.land(bombId: number)                               snap + pop now (the "land" event)
--   BombVisuals.liveCount() -> number
--   BombVisuals.clear()

local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BurpGlue = require(Shared.Burp.BurpGlue)
local Config = require(Shared.Config)
local Types = require(Shared.Types)

local FOLDER_NAME = "VSBurp"
local SKY_Y = 120
local BALL_SIZE = 5
local LAVA_COLOR = Color3.fromRGB(255, 120, 30)
local RING_COLOR = Color3.fromRGB(255, 190, 70)

type Entry = {
	id: number,
	ball: Part,
	tween: Tween,
	x: number,
	z: number,
	radius: number,
	done: boolean,
}

local BombVisuals = {}

local live: { [number]: Entry } = {}
local liveN = 0
local folder: Folder? = nil

local function getFolder(): Folder
	local cached = folder
	if cached ~= nil and cached.Parent ~= nil then
		return cached
	end
	local existing = workspace:FindFirstChild(FOLDER_NAME)
	if existing ~= nil and existing:IsA("Folder") then
		folder = existing
		return existing
	end
	local made = Instance.new("Folder")
	made.Name = FOLDER_NAME
	made.Parent = workspace
	folder = made
	return made
end

local function pop(entry: Entry)
	if entry.done then
		return
	end
	entry.done = true
	if live[entry.id] == entry then
		live[entry.id] = nil
		liveN -= 1
	end
	entry.ball:Destroy()

	-- flat expanding ring (a Cylinder's axis is its X axis, so lay it down with a 90 degree roll)
	local ring = Instance.new("Part")
	ring.Name = "LavaRing"
	ring.Shape = Enum.PartType.Cylinder
	ring.Material = Enum.Material.Neon
	ring.Color = RING_COLOR
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.CanTouch = false
	ring.CastShadow = false
	ring.Transparency = 0.15
	ring.Size = Vector3.new(0.4, 2, 2)
	ring.CFrame = CFrame.new(entry.x, Config.World.groundY + 0.3, entry.z)
		* CFrame.Angles(0, 0, math.rad(90))
	ring.Parent = getFolder()
	local d = entry.radius * 2.4
	local tween = TweenService:Create(
		ring,
		TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Size = Vector3.new(0.4, d, d), Transparency = 1 }
	)
	tween:Play()
	Debris:AddItem(ring, 0.6)
end

function BombVisuals.init()
	getFolder()
end

function BombVisuals.liveCount(): number
	return liveN
end

function BombVisuals.spawn(bomb: Types.Bomb, now: number): boolean
	if liveN >= BurpGlue.maxLiveBombs or live[bomb.id] ~= nil then
		return false
	end
	if not (BurpGlue.finite(bomb.x) and BurpGlue.finite(bomb.z)) then
		return false
	end
	local fall = BurpGlue.fallSeconds(bomb.landsAt, now)
	local landY = Config.World.groundY + BALL_SIZE / 2

	local ball = Instance.new("Part")
	ball.Name = "LavaBomb"
	ball.Shape = Enum.PartType.Ball
	ball.Material = Enum.Material.Neon
	ball.Color = LAVA_COLOR
	ball.Size = Vector3.new(BALL_SIZE, BALL_SIZE, BALL_SIZE)
	ball.Anchored = true
	ball.CanCollide = false
	ball.CanQuery = false
	ball.CanTouch = false
	ball.CastShadow = false
	ball.Position = Vector3.new(bomb.x, SKY_Y, bomb.z)
	ball.Parent = getFolder()
	-- backup cleanup even if everything else fails
	Debris:AddItem(ball, fall + 5)

	local tween = TweenService:Create(
		ball,
		TweenInfo.new(fall, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{ Position = Vector3.new(bomb.x, landY, bomb.z) }
	)
	local entry: Entry = {
		id = bomb.id,
		ball = ball,
		tween = tween,
		x = bomb.x,
		z = bomb.z,
		radius = bomb.radius,
		done = false,
	}
	live[bomb.id] = entry
	liveN += 1
	tween.Completed:Once(function()
		pop(entry)
	end)
	tween:Play()
	return true
end

-- The director says this bomb has landed: finish the fall now if the tween is still running.
function BombVisuals.land(bombId: number)
	local entry = live[bombId]
	if entry == nil then
		return
	end
	pop(entry) -- sets done first, so the tween's Completed (fired by Cancel) does nothing twice
	entry.tween:Cancel()
end

function BombVisuals.clear()
	for _, entry in live do
		pop(entry)
		entry.tween:Cancel()
	end
	live = {}
	liveN = 0
end

return BombVisuals
