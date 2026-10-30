--!strict
-- What you see when a street prop bursts (piece 43, "Chunk Burst"): chunky blocks in the prop's own
-- colours fly out, tumble, land and shrink away. The server already took the prop off the street
-- and left the scorch and rubble; this is only the flying part. Cosmetic: nothing decides anything.
-- Cheap: a few small parts per burst, one RenderStepped for all, and a cap on live chunks.
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)

local Net = require(script.Parent.Parent.Core.Net)
local ChunkFlight = require("./ChunkFlight")

local BreakFxSystem = {}

type Chunk = {
	part: Part,
	throw: ChunkFlight.Throw,
	born: number,
	spin: Vector3,
	size: number,
}

local live: { Chunk } = {}
local folder: Folder? = nil
local rng = Random.new()

local function effectsFolder(): Folder
	if folder ~= nil and folder.Parent ~= nil then
		return folder
	end
	local found = Workspace:FindFirstChild(Config.Workspace.EffectsFolder)
	if found ~= nil and found:IsA("Folder") then
		folder = found
		return found
	end
	local made = Instance.new("Folder")
	made.Name = Config.Workspace.EffectsFolder
	made.Parent = Workspace
	folder = made
	return made
end

local function onBroken(p: any)
	if type(p) ~= "table" or type(p.x) ~= "number" or type(p.z) ~= "number" then
		return
	end
	local cfg = Config.Breakables
	local kind = cfg.kinds[p.kind]
	local want = if kind then kind.chunks else 6
	local room = cfg.fly.maxLiveChunks - #live
	local count = math.min(want, room)
	if count <= 0 then
		return
	end
	local sx = if type(p.sx) == "number" then p.sx else 4
	local sy = if type(p.sy) == "number" then p.sy else 3
	local sz = if type(p.sz) == "number" then p.sz else 4
	local y = if type(p.y) == "number" then p.y else 2
	local floorY = y - sy / 2
	local base = Color3.fromHex(if type(p.color) == "string" then p.color else "8794A6")
	local palette =
		{ base, base:Lerp(Color3.new(0, 0, 0), 0.5), base:Lerp(Color3.new(1, 1, 1), 0.35) }
	local now = os.clock()
	local parent = effectsFolder()
	for i = 1, count do
		local size = math.clamp(math.min(sx, sz) * 0.28, 0.7, 1.7) * (0.7 + rng:NextNumber() * 0.6)
		local part = Instance.new("Part")
		part.Name = "BreakChunk"
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.CastShadow = false
		part.Material = Enum.Material.SmoothPlastic
		part.Color = palette[1 + (i % #palette)]
		part.Size = Vector3.new(size, size, size)
		part.Parent = parent
		Debris:AddItem(part, cfg.fly.seconds + 1) -- if this system ever stops, the part still goes
		table.insert(live, {
			part = part,
			throw = ChunkFlight.throw(
				p.x + (rng:NextNumber() - 0.5) * sx * 0.6,
				y + (rng:NextNumber() - 0.2) * sy * 0.4,
				p.z + (rng:NextNumber() - 0.5) * sz * 0.6,
				floorY + size / 2,
				rng:NextNumber() * math.pi * 2,
				rng:NextNumber(),
				rng:NextNumber(),
				cfg.fly.sideSpeed,
				cfg.fly.upSpeed
			),
			born = now,
			spin = Vector3.new(
				rng:NextNumber() * 8 - 4,
				rng:NextNumber() * 8 - 4,
				rng:NextNumber() * 8 - 4
			),
			size = size,
		})
	end
end

local function step()
	if #live == 0 then
		return
	end
	local now = os.clock()
	local cfg = Config.Breakables.fly
	local i = 1
	while i <= #live do
		local c = live[i]
		local t = now - c.born
		if t >= cfg.seconds or c.part.Parent == nil then
			c.part:Destroy()
			live[i] = live[#live]
			live[#live] = nil
		else
			local x, y, z = ChunkFlight.position(c.throw, cfg.gravity, t)
			local landed = math.min(t, ChunkFlight.landTime(c.throw, cfg.gravity))
			local k = ChunkFlight.scale(t, cfg.seconds, 0.35)
			c.part.Size = Vector3.one * (c.size * math.max(k, 0.01))
			c.part.CFrame = CFrame.new(x, y, z)
				* CFrame.Angles(c.spin.X * landed, c.spin.Y * landed, c.spin.Z * landed)
			i += 1
		end
	end
end

function BreakFxSystem.start()
	Net.on("PropBroken", onBroken)
	RunService.RenderStepped:Connect(step)
end

return BreakFxSystem
