--!strict
-- Squads on the server (video 3 gap 11). Logic only: the look comes from Claude Design.
--
--   Lobby      players vote Solo / Duo / Trio (same window as the map vote). The server counts.
--   Spawning   the winning size and the friend parties go into the squad book; MatchController seats the teams.
--   Match      teammates cannot hurt each other (damage door guard); shots and shells skip them (Combatants);
--              bots never target them (BotSystem). Each human is told their squad and who is still alive.
--   Reset      everyone is told "solo" so the squad list goes away.
--
-- For other pieces:
--   SquadSystem.teamOf(id) / SquadSystem.sameTeam(a, b)   read the seated teams (nil / false when solo).
-- The rules themselves (seating, counting, ranking) are pure and tested: shared/Squads/SquadBook, Match/TeamRank.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Ids = require(Shared.Ids)
local MatchPhase = require(Shared.MatchPhase)
local SquadBook = require(Shared.Squads.SquadBook)
local VoteFlow = require(Shared.MapVote.VoteFlow)

local Core = script.Parent.Parent:WaitForChild("Core")
local Damage = require(Core.Damage)
local MatchContext = require(Core.MatchContext)
local Net = require(Core.Net)
local Participants = require(Core.Participants)
local Squads = require(Core.Squads)

local SquadSystem = {}
SquadSystem.order = 130 -- after MatchSystem (50) and SocialSystem (120)

local rng = Random.new()
local modes = Config.Squads.modes
local flow: VoteFlow.Flow = VoteFlow.new(SquadBook.pool(modes), function(n: number)
	return rng:NextInteger(1, n)
end)
local dirty = false

-- Friends who joined each other: userId -> the userId of the first host in the chain.
local partyRoot: { [number]: number } = {}

local function voterId(player: Player): string
	return Ids.player(player.UserId)
end

function SquadSystem.teamOf(id: string): number?
	return Squads:teamOf(id)
end

function SquadSystem.sameTeam(a: string, b: string): boolean
	return Squads:sameTeam(a, b)
end

-- ===== vote =====
local function voteState(player: Player)
	local state = flow:state(voterId(player))
	local list = {}
	for i, entry in state.maps do
		table.insert(list, {
			id = entry.id,
			name = entry.name,
			size = modes[i].size,
			votes = entry.votes,
		})
	end
	return { open = state.open, modes = list, yourVote = state.yourVote, chosen = state.nextMapId }
end

local function sendVote(player: Player)
	Net.fire("SquadVoteState", player, voteState(player))
end

local function sendVoteAll()
	dirty = false
	for _, player in Players:GetPlayers() do
		sendVote(player)
	end
end

-- ===== parties =====
local function currentParties(): { { string } }
	local groups: { [number]: { string } } = {}
	local order: { number } = {}
	for _, player in Players:GetPlayers() do
		local root = partyRoot[player.UserId]
		if root ~= nil then
			if groups[root] == nil then
				groups[root] = {}
				table.insert(order, root)
				local host = Players:GetPlayerByUserId(root)
				if host then
					table.insert(groups[root], Ids.player(root)) -- the host leads their party
				end
			end
			table.insert(groups[root], Ids.player(player.UserId))
		end
	end
	local out: { { string } } = {}
	for _, root in order do
		if #groups[root] >= 2 then
			table.insert(out, groups[root])
		end
	end
	return out
end

-- ===== squad state for each human =====
local function squadPayload(id: string)
	local team = Squads:teamOf(id)
	local mates = {}
	for _, mateId in Squads:matesOf(id) do
		local p = Participants:get(mateId)
		table.insert(mates, {
			id = mateId,
			name = if p then p.displayName else "?",
			alive = p ~= nil and p.alive,
		})
	end
	return {
		matchId = MatchContext:getMatchId(),
		size = if Squads:active() then Squads:size() else 1,
		team = team,
		mates = mates,
	}
end

local function sendSquadState(player: Player)
	Net.fire("SquadState", player, squadPayload(Ids.player(player.UserId)))
end

local function sendSquadStateAll()
	for _, player in Players:GetPlayers() do
		sendSquadState(player)
	end
end

function SquadSystem.start()
	if not Config.Squads.enabled then
		return -- Solo only: no vote, no teams, nothing is sent
	end
	-- Friendly fire is off in a squad match. The zone has no source, and hurting yourself is still allowed.
	Damage:addGuard(function(req)
		if Squads:blocksDamage(req.sourceId, req.targetId, Config.Squads.friendlyFire) then
			return "teammate"
		end
		return nil
	end)

	Net.onRequest("SquadVoteRequest", function(player: Player, modeId: string)
		flow:vote(voterId(player), modeId) -- the flow checks the window and that the mode exists
		dirty = true
		sendVote(player) -- the voter always gets the truth back, even for a refused vote
	end)
	Net.onRequest("SquadVoteStateRequest", function(player: Player)
		sendVote(player)
		sendSquadState(player)
	end)

	MatchContext.PhaseChanged:connect(function(phase: string)
		flow:onPhase(phase)
		if phase == MatchPhase.Spawning then
			-- MatchController seats the teams right after this phase change.
			local chosen = flow:takeWinner()
			Squads:setWanted(SquadBook.sizeOf(modes, chosen, Config.Squads.defaultMode))
			Squads:setParties(currentParties())
		elseif phase == MatchPhase.Resetting then
			sendSquadStateAll() -- the book is already cleared: everyone sees "solo"
		end
		sendVoteAll()
	end)

	-- Seated: tell every human their squad. Then keep the alive flags fresh.
	Squads.Assigned:connect(sendSquadStateAll)
	Participants.Eliminated:connect(function()
		if Squads:active() then
			sendSquadStateAll()
		end
	end)
	Participants.Removed:connect(function()
		if Squads:active() then
			sendSquadStateAll()
		end
	end)

	-- Friends who came for a host play together. SocialSystem tells us; without it parties stay empty.
	local socialFolder = script.Parent.Parent:FindFirstChild("Social")
	local socialModule = if socialFolder then socialFolder:FindFirstChild("SocialSystem") else nil
	if socialModule and socialModule:IsA("ModuleScript") then
		local ok, social = pcall(require, socialModule)
		if ok and type(social) == "table" and social.Joined then
			(social.Joined :: any):connect(function(friend: Player, host: Player)
				local root = partyRoot[host.UserId] or host.UserId
				partyRoot[host.UserId] = root
				partyRoot[friend.UserId] = root
			end)
		end
	end

	Players.PlayerRemoving:Connect(function(player: Player)
		flow:leave(voterId(player))
		partyRoot[player.UserId] = nil
		dirty = true
	end)

	-- The running count reaches everyone at most once per stateRepeatSeconds.
	task.spawn(function()
		while true do
			task.wait(Config.Squads.stateRepeatSeconds)
			if dirty then
				sendVoteAll()
			end
		end
	end)
end

return SquadSystem
