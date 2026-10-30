--!strict
-- The server's hop over low cover (piece 45). Same shape as the slide: the player's own client
-- carries the body (it owns its character), the server makes its own plan from where the body is,
-- says yes or no, and checks where the body ended up. The move watch is told how far the hop may
-- carry the player, so a real hop is never mistaken for a cheat.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Ids = require(Shared.Ids)
local SlideRules = require(Shared.Movement.SlideRules)
local VaultCast = require(Shared.Movement.VaultCast)
local VaultRules = require(Shared.Movement.VaultRules)

local Core = script.Parent.Parent.Core
local MatchContext = require(Core.MatchContext)
local Net = require(Core.Net)
local Participants = require(Core.Participants)

local SlideService = require("./SlideService")

local VaultService = {}

local readyAt: { [string]: number } = {} -- id -> server time the next hop may start
local hopping: { [string]: number } = {} -- id -> server time the current hop ends

local function arenaBounds(): VaultCast.Bounds
	local half = Config.Arena.size / 2
	return {
		minX = Config.Arena.centerX - half,
		maxX = Config.Arena.centerX + half,
		minZ = Config.Arena.centerZ - half,
		maxZ = Config.Arena.centerZ + half,
	}
end

function VaultService.isVaulting(id: string): boolean
	local untilTime = hopping[id]
	return untilTime ~= nil and Workspace:GetServerTimeNow() < untilTime
end

-- A player asks to hop. Returns true when it was accepted (the Fx has gone out).
function VaultService.request(player: Player, dirX: number?, dirZ: number?): boolean
	if not Config.Vault.enabled then
		return false
	end
	local id = Ids.player(player.UserId)
	local character = player.Character
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	if character == nil or humanoid == nil or root == nil or not root:IsA("BasePart") then
		return false
	end
	local participant = Participants:get(id)
	if
		humanoid.Health <= 0
		or (participant ~= nil and (not participant.alive or not MatchContext:isCombat()))
	then
		return false
	end
	local now = Workspace:GetServerTimeNow()
	if now < (readyAt[id] or 0) or SlideService.isSliding(id) or VaultService.isVaulting(id) then
		return false
	end

	local look = root.CFrame.LookVector
	local dx, dz = SlideRules.direction(dirX, dirZ, look.X, look.Z)
	if dx == nil or dz == nil then
		return false
	end
	local bounds = if participant ~= nil then arenaBounds() else nil
	local plan = VaultCast.plan(character, root, humanoid.HipHeight, dx, dz, bounds)
	if plan == nil then
		return false
	end

	readyAt[id] = now + Config.Vault.cooldownSeconds
	hopping[id] = now + plan.duration
	local from = root.Position
	SlideService.PlayerSlid:fire(id, plan.distance) -- the move watch lets the hop's distance through
	Net.fireAll("VaultFx", {
		participantId = id,
		fromPos = from,
		toPos = plan.toPos,
		peak = plan.peak,
		duration = plan.duration,
	})

	local walk = humanoid.WalkSpeed
	local stamp = hopping[id]
	task.delay(plan.duration + Config.Vault.endGrace, function()
		if hopping[id] ~= stamp or root.Parent == nil then
			return
		end
		hopping[id] = nil
		local here = root.Position
		if
			not VaultRules.endPlausible(
				from.X,
				from.Z,
				here.X,
				here.Z,
				plan.distance,
				walk,
				Config.Vault.endGrace,
				Config.Vault.endTolerance
			)
		then
			root.CFrame = CFrame.new(plan.toPos) * (root.CFrame - root.CFrame.Position)
		end
	end)
	return true
end

function VaultService.start()
	Net.onRequest("VaultRequest", function(player: Player, dir: Vector3?)
		local ok =
			VaultService.request(player, if dir then dir.X else nil, if dir then dir.Z else nil)
		if not ok then
			Net.fire("VaultDenied", player, {}) -- the client puts the body back on the ground
		end
	end)

	Participants.Eliminated:connect(function(p)
		hopping[p.id] = nil
	end)
	MatchContext.MatchStarted:connect(function()
		table.clear(readyAt)
		table.clear(hopping)
	end)
	Players.PlayerRemoving:Connect(function(player)
		local id = Ids.player(player.UserId)
		readyAt[id] = nil
		hopping[id] = nil
	end)
end

return VaultService
