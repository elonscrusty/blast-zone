--!strict
-- A light movement check for every ready player (rules: Shared/Player/MoveRules, tested in Lune).
-- The character's position is owned by the client, so every server rule that uses it (sweep spot,
-- sell range, gem pickup, gate prompt, hub safe zone, lava hit) asks HERE instead of reading the
-- HumanoidRootPart directly.
--
--   MoveWatch.init()                       once, right after PlayerState (Main boot order)
--   MoveWatch.position(player) -> (Vector3?, boolean)
--        where the server believes the player is: the real HumanoidRootPart position when it is
--        reachable from the last trusted spot, else the trusted spot (Y from the real body).
--        The boolean is false when the player is "suspect" (moved faster than possible): rules
--        that hand out coins (sell, gems, gates, sweeping) should refuse while it is false.
--        nil when there is no living character.
--   MoveWatch.grace(player, seconds)       accept any move for a moment (lava bounce, server moves)
--   MoveWatch.teleported(player)           the server itself moved the character: trust the new spot
--
-- Cost: one look per player 5 times a second, a few multiplies each. Honest players and lag spikes
-- of a few seconds are never touched. A teleport or speed hack gains at most a little (the trusted
-- spot follows at walking speed); repeated jumps put the character back on the trusted spot.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local MoveRules = require(Shared.Player.MoveRules)

local PlayerState = require(script.Parent.Parent.Player.PlayerState)

local LOOK_SECONDS = 0.2
local SPAWN_GRACE = 3

local MoveWatch = {}

local started = false
local tracks: { [Player]: MoveRules.Track } = {}
local charConns: { [Player]: RBXScriptConnection } = {}
local lastWarn = -10

local function rootOf(player: Player): BasePart?
	local char = player.Character
	if char == nil then
		return nil
	end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	local hum = char:FindFirstChildOfClass("Humanoid")
	if hrp == nil or not hrp:IsA("BasePart") or hum == nil or hum.Health <= 0 then
		return nil
	end
	return hrp
end

local function walkSpeedOf(player: Player): number
	local s = PlayerState.get(player)
	return if s ~= nil then s.derived.walkSpeed else 16
end

local function trackOf(player: Player, hrp: BasePart, now: number): MoveRules.Track
	local tr = tracks[player]
	if tr == nil then
		local p = hrp.Position
		tr = MoveRules.new(p.X, p.Z, now, SPAWN_GRACE)
		tracks[player] = tr
	end
	return tr :: MoveRules.Track
end

local function snapBack(hrp: BasePart, tr: MoveRules.Track)
	pcall(function()
		local p = hrp.Position
		local rot = hrp.CFrame - p
		hrp.AssemblyLinearVelocity = Vector3.zero
		hrp.CFrame = CFrame.new(tr.x, p.Y, tr.z) * rot
	end)
end

local function look()
	local now = os.clock()
	for _, state in PlayerState.all() do
		local player = state.player
		local hrp = rootOf(player)
		if hrp ~= nil then
			local tr = trackOf(player, hrp, now)
			local p = hrp.Position
			local verdict = MoveRules.observe(tr, p.X, p.Z, now, state.derived.walkSpeed)
			if verdict == "clamped" and MoveRules.shouldSnap(tr, p.X, p.Z, now) then
				snapBack(hrp, tr)
				MoveRules.reset(tr, tr.x, tr.z, now, 0)
			end
		end
	end
end

function MoveWatch.position(player: Player): (Vector3?, boolean)
	local hrp = rootOf(player)
	if hrp == nil then
		return nil, false
	end
	local now = os.clock()
	local tr = trackOf(player, hrp, now)
	local p = hrp.Position
	local x, z, ok = MoveRules.check(tr, p.X, p.Z, now, walkSpeedOf(player))
	if ok then
		return p, true
	end
	return Vector3.new(x, p.Y, z), false
end

function MoveWatch.grace(player: Player, seconds: number)
	local tr = tracks[player]
	if tr ~= nil then
		tr.graceUntil = math.max(tr.graceUntil, os.clock() + math.clamp(seconds, 0, 10))
	end
end

function MoveWatch.teleported(player: Player)
	local hrp = rootOf(player)
	local tr = tracks[player]
	if hrp ~= nil and tr ~= nil then
		local p = hrp.Position
		MoveRules.reset(tr, p.X, p.Z, os.clock(), 1)
	end
end

local function hook(player: Player)
	if charConns[player] ~= nil then
		return
	end
	charConns[player] = player.CharacterAdded:Connect(function()
		-- a (re)spawn moves the body: start fresh with a short grace
		tracks[player] = nil
	end)
end

function MoveWatch.init()
	if started then
		return
	end
	started = true
	for _, p in Players:GetPlayers() do
		hook(p)
	end
	Players.PlayerAdded:Connect(hook)
	Players.PlayerRemoving:Connect(function(player)
		tracks[player] = nil
		local conn = charConns[player]
		if conn ~= nil then
			conn:Disconnect()
			charConns[player] = nil
		end
	end)
	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc < LOOK_SECONDS then
			return
		end
		acc = 0
		local ok, err = pcall(look)
		if not ok and os.clock() - lastWarn > 5 then
			lastWarn = os.clock()
			warn(`[MoveWatch] look failed: {err}`)
		end
	end)
end

return MoveWatch
