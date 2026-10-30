--!strict
-- Wires the game's server messages to sounds and music. Everything here only listens: the server
-- already decided what happened, this just makes it audible. Volume sliders are the Settings
-- piece's SoundGroups (see AudioPlayer). Needs sound ids in AudioIds.luau; with none, it is silent.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Ids = require(Shared.Ids)

local Net = require(script.Parent.Parent.Core.Net)

local AudioEvents = require(script.Parent.AudioEvents)
local AudioIds = require(script.Parent.AudioIds)
local AudioPlayer = require(script.Parent.AudioPlayer)

local AudioClientSystem = {}
AudioClientSystem.order = 70 -- after Settings (60) has made the SoundGroups

local warnedHandlers: { [string]: boolean } = {}

-- A bad message or a missing remote must never stop the game: warn once and carry on.
local function listen(remote: string, handler: (any) -> ())
	local ok, err = pcall(Net.on, remote, function(payload: any)
		local fine, problem = pcall(handler, payload)
		if not fine and not warnedHandlers[remote] then
			warnedHandlers[remote] = true
			warn(`[Audio] {remote} handler failed: {problem}`)
		end
	end)
	if not ok then
		warn(`[Audio] cannot listen to {remote}: {err}`)
	end
end

function AudioClientSystem.start()
	local tracker =
		AudioEvents.new(Ids.player(Players.LocalPlayer.UserId), Config.Weapons.Explosive.id)
	AudioPlayer.start(AudioIds)
	AudioPlayer.setMusic("music_lobby")

	local function play(request: AudioEvents.Request?)
		if request then
			AudioPlayer.play(request)
		end
	end

	-- Containers: the hit message has only an id, so find the box by its tag.
	local containers: { [string]: BasePart } = {}
	local function seeContainer(inst: Instance)
		local id = inst:GetAttribute("ContainerId")
		if inst:IsA("BasePart") and typeof(id) == "string" then
			containers[id] = inst
		end
	end
	for _, inst in CollectionService:GetTagged(Config.Tags.SupplyContainer) do
		seeContainer(inst)
	end
	CollectionService:GetInstanceAddedSignal(Config.Tags.SupplyContainer):Connect(seeContainer)

	listen("MatchState", function(p: any)
		local change = tracker:matchState(p)
		if change == nil then
			return
		end
		if change.resetEffects then
			AudioPlayer.stopEffects()
		end
		if change.musicChanged then
			AudioPlayer.setMusic(change.music)
		end
	end)

	listen("ShotFx", function(p: any)
		play(tracker:shot(p))
	end)
	listen("ExplosionFx", function(p: any)
		play(tracker:explosion(p))
	end)
	listen("HitConfirm", function(p: any)
		play(tracker:hit(p))
	end)
	listen("DamageTaken", function(p: any)
		play(tracker:damageTaken(p))
	end)
	listen("AmmoState", function(p: any)
		play(tracker:ammoState(p))
	end)
	listen("SlideFx", function(p: any)
		play(tracker:slide(p))
	end)
	listen("ContainerHit", function(p: any)
		local part = if type(p) == "table" then containers[p.containerId] else nil
		if part and part.Parent then
			play(tracker:containerHit(part.Position))
		end
	end)
	listen("ContainerBroken", function(p: any)
		play(tracker:containerBroken(p))
		if type(p) == "table" then
			containers[p.containerId] = nil
		end
	end)
	listen("PickupRemoved", function(p: any)
		play(tracker:pickupRemoved(p))
	end)
	listen("XpState", function(p: any)
		play(tracker:xp(p))
	end)
	listen("UpgradeApplied", function(p: any)
		play(tracker:upgradeApplied(p))
	end)
	listen("ZoneState", function(p: any)
		play(tracker:zone(p))
	end)
	listen("Eliminated", function(p: any)
		play(tracker:eliminated(p))
	end)
	listen("Results", function(p: any)
		play(tracker:results(p))
	end)
end

return AudioClientSystem
