--!strict
-- Friends who join (stage 3, piece 26). Roblox already sends an invited friend to the inviter's server, and one
-- server is one lobby and one match. This system makes sure they PLAY together: when the host is queued or
-- fighting, the friend is queued for the next match too. Rules live in shared/FriendInvite (Lune-tested).
--
-- No remote: the invite prompt is Roblox's own (client side), and the launch data the joiner brings is only a
-- hint. The host must really be in this server, and all it can do is queue the joiner, the same as pressing PLAY.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local FriendInvite = require(Shared.FriendInvite)
local Ids = require(Shared.Ids)
local MatchPhase = require(Shared.MatchPhase)

local Core = script.Parent.Parent:WaitForChild("Core")
local MatchContext = require(Core.MatchContext)
local Net = require(Core.Net)
local Participants = require(Core.Participants)

local QUEUED_ATTRIBUTE = "QueuedByFriend" -- the lobby PLAY button shows READY when this is set

type MatchSystemApi = {
	queuePlayer: (player: Player) -> boolean,
	isQueued: (player: Player) -> boolean,
}

local SocialSystem = {}
SocialSystem.order = 120 -- after MatchSystem (50)

local matchSystem: MatchSystemApi? = nil

local function loadMatchSystem(): MatchSystemApi?
	local folder = script.Parent.Parent:FindFirstChild("Match")
	local module = if folder then folder:FindFirstChild("MatchSystem") else nil
	if module and module:IsA("ModuleScript") then
		local ok, result = pcall(require, module)
		if ok and type(result) == "table" and type(result.queuePlayer) == "function" then
			return result :: any
		end
	end
	warn("[social] MatchSystem.queuePlayer is missing: friends will not be queued together")
	return nil
end

local function presentUserIds(): { [number]: boolean }
	local present: { [number]: boolean } = {}
	for _, p in Players:GetPlayers() do
		present[p.UserId] = true
	end
	return present
end

local function launchDataOf(player: Player): any
	local ok, data = pcall(function()
		return player:GetJoinData()
	end)
	if ok and type(data) == "table" then
		return data.LaunchData
	end
	return nil
end

local function matchRunning(): boolean
	local phase = MatchContext:getPhase()
	return phase ~= MatchPhase.Waiting and phase ~= MatchPhase.Countdown
end

local function onPlayerAdded(player: Player)
	local hostId = FriendInvite.findHost(
		player.UserId,
		launchDataOf(player),
		player.FollowUserId,
		presentUserIds()
	)
	if hostId == nil then
		return
	end
	local host = Players:GetPlayerByUserId(hostId)
	if host == nil then
		return
	end

	-- MatchSystem adds the player on its own PlayerAdded; give it a moment so the order never matters.
	task.wait(0.5)
	if player.Parent == nil or host.Parent == nil then
		return
	end

	local api = matchSystem
	local hostState = {
		queued = api ~= nil and api.isQueued(host),
		inMatch = Participants:get(Ids.player(host.UserId)) ~= nil,
	}
	if api and FriendInvite.shouldQueue(hostState) and api.queuePlayer(player) then
		player:SetAttribute(QUEUED_ATTRIBUTE, true)
	end

	Net.fire("Announce", host, { kind = "kill", text = FriendInvite.hostLine(player.DisplayName) })
	-- The joiner's client may still be loading: say it a little later.
	task.delay(2, function()
		if player.Parent then
			Net.fire(
				"Announce",
				player,
				{ kind = "kill", text = FriendInvite.friendLine(host.DisplayName, matchRunning()) }
			)
		end
	end)
	print(
		`[social] {player.Name} joined friend {host.Name} (queued: {player:GetAttribute(
			QUEUED_ATTRIBUTE
		) == true})`
	)
end

function SocialSystem.start()
	matchSystem = loadMatchSystem()
	Players.PlayerAdded:Connect(function(player)
		task.spawn(onPlayerAdded, player)
	end)
	-- Pressing PLAY / lobby again is the player's own choice from then on.
	MatchContext.PhaseChanged:connect(function(phase: string)
		if phase == MatchPhase.Resetting then
			for _, p in Players:GetPlayers() do
				p:SetAttribute(QUEUED_ATTRIBUTE, nil)
			end
		end
	end)
end

return SocialSystem
