--!strict
-- Watches every player body each frame with MoveCheck and puts it back when a move is impossible
-- (teleport, speed or fly cheats). Bots are moved by the server and are not watched.
--   MoveGuard.place(player, cframe)  -- the server moves a player: use this, not PivotTo
--   MoveGuard.isHeld(participantId)  -- a move is waiting to be explained: refuse shots for now
--   MoveGuard.trustedPosition(player) -- where the server believes the player is

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Ids = require(Shared.Ids)
local MoveCheck = require(script.Parent.MoveCheck)

local MoveGuard = {}

local check = MoveCheck.new(Config.AntiCheat)
local roots: { [string]: BasePart } = {} -- the body each id was last checked with
local lastWarn: { [string]: number } = {}
local started = false

local function rootOf(player: Player): (BasePart?, Humanoid?)
	local character = player.Character
	if character == nil then
		return nil, nil
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if root == nil or not root:IsA("BasePart") then
		return nil, nil
	end
	return root, humanoid
end

local function trust(id: string, root: BasePart)
	roots[id] = root
	local p = root.Position
	check:reset(id, p.X, p.Y, p.Z, os.clock())
end

function MoveGuard.place(player: Player, at: CFrame)
	local character = player.Character
	if character == nil then
		return
	end
	character:PivotTo(at)
	local root = rootOf(player)
	if root ~= nil then
		trust(Ids.player(player.UserId), root)
	end
end

function MoveGuard.isHeld(participantId: string): boolean
	return check:isHeld(participantId)
end

function MoveGuard.trustedPosition(player: Player): Vector3?
	local x, y, z = check:good(Ids.player(player.UserId))
	if x == nil or y == nil or z == nil then
		return nil
	end
	return Vector3.new(x, y, z)
end

-- A slide was accepted for this player: let its distance through.
function MoveGuard.allowSlide(participantId: string, studs: number)
	check:addCredit(participantId, studs + Config.Slide.endTolerance, os.clock())
end

local function snapBack(player: Player, id: string, root: BasePart, x: number, y: number, z: number)
	local turn = root.CFrame - root.CFrame.Position
	root.AssemblyLinearVelocity = Vector3.zero
	root.CFrame = CFrame.new(x, y, z) * turn
	local now = os.clock()
	if (lastWarn[id] or -math.huge) + Config.AntiCheat.warnEverySeconds < now then
		lastWarn[id] = now
		warn(`[AntiCheat] {player.Name} moved too far; put back ({check:snaps(id)} times)`)
	end
end

local function stepPlayer(player: Player, now: number)
	local id = Ids.player(player.UserId)
	local root, humanoid = rootOf(player)
	if root == nil or humanoid == nil or humanoid.Health <= 0 then
		return
	end
	if roots[id] ~= root then
		trust(id, root) -- a new body: start fresh where it stands
		return
	end
	local p = root.Position
	-- WalkSpeed is read on the server, so a client that raises its own copy changes nothing here.
	local verdict, gx, gy, gz = check:step(id, p.X, p.Y, p.Z, now, humanoid.WalkSpeed)
	if verdict == "snap" then
		snapBack(player, id, root, gx, gy, gz)
	end
end

function MoveGuard.start()
	if started then
		return
	end
	started = true
	RunService.Heartbeat:Connect(function()
		local now = os.clock()
		for _, player in Players:GetPlayers() do
			stepPlayer(player, now)
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		local id = Ids.player(player.UserId)
		check:forget(id)
		roots[id] = nil
		lastWarn[id] = nil
	end)
end

return MoveGuard
