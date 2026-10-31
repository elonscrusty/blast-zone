--!strict
-- Piece 08 on the server: turns level-ups into three-card offers, checks every pick, and tells
-- the rest of the game what each participant's numbers are (EffectiveStats provider).
--
--   RunXp.LevelUp -> offer shown -> client sends UpgradeChoose -> checks -> stack added ->
--   RunXp:takeOffer(id) + EffectiveStats:invalidate(id) -> next waiting offer (if any)
--
-- RunXp's pendingOffers counts the offer on screen plus the ones waiting behind it. Waiting
-- offers beyond Config.Upgrades.queueMax are dropped. Bots take a random card after a short pause,
-- through the same checks, so they follow the player rules.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local StatBook = require(Shared.StatBook)
local UpgradeDefs = require(Shared.UpgradeDefs)

local Core = script.Parent.Parent:WaitForChild("Core")
local Net = require(Core.Net)
local Participants = require(Core.Participants)
local MatchContext = require(Core.MatchContext)
local RunXp = require(Core.RunXp)
local EffectiveStats = require(Core.EffectiveStats)

local RunUpgrades = require(script.Parent.RunUpgrades)
local TallySystem = require(script.Parent.Parent.Results.TallySystem)

local UpgradeSystem = {}
UpgradeSystem.order = 120 -- after the core services

local BOT_THINK_MIN = 0.8
local BOT_THINK_MAX = 2.0

local runUpgrades: any = nil
local rng = Random.new()

local function sendOffer(participant: any, payload: any?)
	if participant ~= nil and participant.player ~= nil and participant.player.Parent ~= nil then
		Net.fire("UpgradeOffer", participant.player, payload)
	end
end

local showNext: (id: string) -> ()

local function tryChoose(id: string, matchId: number, offerId: string, optionIndex: number)
	local participant = Participants:get(id)
	if participant == nil or not participant.alive then
		return
	end
	if not MatchContext:isCombat() or not MatchContext:isCurrent(matchId) then
		return
	end
	local result = runUpgrades:choose(id, matchId, offerId, optionIndex)
	if result.ok then
		TallySystem.add(id, "powers")
		RunXp:takeOffer(id)
		EffectiveStats:invalidate(id)
		if participant.player ~= nil then
			Net.fire("UpgradeApplied", participant.player, {
				upgradeId = result.upgradeId,
				stacks = result.stacks,
				text = result.text,
			})
		end
		showNext(id)
	elseif result.reason == "offer_invalid" then
		sendOffer(participant, nil)
		showNext(id)
	end
end

local function scheduleBotPick(id: string, payload: any)
	task.delay(rng:NextNumber(BOT_THINK_MIN, BOT_THINK_MAX), function()
		tryChoose(id, payload.matchId, payload.offerId, rng:NextInteger(1, #payload.options))
	end)
end

-- Shows the next waiting offer if none is open. Drops extra waiting ones past the queue limit.
showNext = function(id: string)
	local state = RunXp:get(id)
	local participant = Participants:get(id)
	if state == nil or participant == nil or not participant.alive then
		return
	end
	if runUpgrades:hasActive(id) then
		while state.pendingOffers > 1 + Config.Upgrades.queueMax do
			RunXp:takeOffer(id)
		end
		return
	end
	while state.pendingOffers > 0 do
		local payload, reason = runUpgrades:issue(id)
		if payload ~= nil then
			if participant.kind == "bot" then
				scheduleBotPick(id, payload)
			else
				sendOffer(participant, payload)
			end
			return
		end
		if reason ~= "nothing_eligible" then
			return
		end
		-- Nothing left that helps this build: the level-up still counts, the pick is just empty.
		RunXp:takeOffer(id)
	end
end

function UpgradeSystem.start()
	local ctx = {
		base = StatBook.base(Config),
		hasExplosive = Config.Features.explosiveWeapon,
		weaponNames = {
			firearm = Config.Weapons.Firearm.displayName,
			explosive = Config.Weapons.Explosive.displayName,
		},
	}
	runUpgrades = RunUpgrades.new(UpgradeDefs, ctx, function()
		return rng:NextNumber()
	end, os.clock, Config.Upgrades.selectionLockSeconds)

	EffectiveStats:setProvider(function(id: string)
		return runUpgrades:sheet(id)
	end)

	Participants.Enrolled:connect(function(p)
		runUpgrades:enroll(p.id, p.matchId)
		EffectiveStats:invalidate(p.id)
	end)

	Participants.Eliminated:connect(function(p)
		if runUpgrades:eliminate(p.id) then
			sendOffer(p, nil)
		end
	end)

	Participants.Removed:connect(function(p)
		runUpgrades:remove(p.id)
		EffectiveStats:invalidate(p.id)
	end)

	-- A match that is over or being reset keeps nothing: stacks, open offers, all of it.
	MatchContext.PhaseChanged:connect(function(phase: string)
		if phase == "Resetting" then
			for _, p in Participants:list() do
				sendOffer(p, nil)
				EffectiveStats:invalidate(p.id)
			end
			runUpgrades:clear()
		elseif phase == "Finished" then
			for _, p in Participants:list() do
				sendOffer(p, nil)
			end
		end
	end)

	RunXp.LevelUp:connect(function(id: string)
		showNext(id)
	end)

	Net.onRequest("UpgradeChoose", function(player: Player, offerId: string, optionIndex: number)
		local participant = Participants:ofPlayer(player)
		if participant == nil then
			return
		end
		tryChoose(participant.id, participant.matchId, offerId, optionIndex)
	end)
end

return UpgradeSystem
