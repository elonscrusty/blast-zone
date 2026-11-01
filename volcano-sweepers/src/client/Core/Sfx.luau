--!strict
-- Sound hooks. Every sound is looked up by name in Config.Audio.ids; a name with no id is simply
-- silent (no errors), so the game works with an empty list. Never invent ids (plans/AUDIO-IDS.md).
--   Sfx.play(name, volume?, pitch?)   one-shot from a small pool of Sound objects
--   Sfx.music()                       start/stop the looping music to match settings.music and
--                                     Config.Audio.musicId (safe to call any time; it also re-runs
--                                     itself when the setting changes)
-- Names the game asks for: sweep, puff, sell, coin, upgrade, unlock, find, rare, rumble, bomb, hit,
-- party, click, error.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local StoreLogic = require(Shared.Client.StoreLogic)
local Store = require(script.Parent.Store)

local Sfx = {}

local POOL_PER_NAME = 4
local JITTER: { [string]: number } = { sweep = 0.07, puff = 0.08, coin = 0.05, click = 0.04 }

local pools: { [string]: { Sound } } = {}
local nextSlot: { [string]: number } = {}
local warned: { [string]: boolean } = {}
local musicSound: Sound? = nil

local group = Instance.new("Folder")
group.Name = "VSSfx"
group.Parent = SoundService

local function validId(id: any): string?
	if type(id) ~= "string" then
		return nil
	end
	if string.match(id, "^rbxassetid://%d+$") == nil then
		return nil
	end
	return id
end

local function idFor(name: string): string?
	local raw = (Config.Audio.ids :: { [string]: string })[name]
	if raw == nil or raw == "" then
		return nil
	end
	local id = validId(raw)
	if id == nil and not warned[name] then
		warned[name] = true
		warn(`[Sfx] bad sound id for '{name}' (use rbxassetid://<number>)`)
	end
	return id
end

function Sfx.play(name: string, volume: number?, pitch: number?)
	local id = idFor(name)
	if id == nil then
		return
	end
	if not StoreLogic.setting(Store.view(), "sfx", true) then
		return
	end
	local pool = pools[name]
	if pool == nil then
		pool = {}
		pools[name] = pool
	end
	local list = pool :: { Sound }
	local sound: Sound? = nil
	for _, s in list do
		if not s.IsPlaying then
			sound = s
			break
		end
	end
	if sound == nil then
		if #list < POOL_PER_NAME then
			local fresh = Instance.new("Sound")
			fresh.Name = name
			fresh.SoundId = id
			fresh.Parent = group
			table.insert(list, fresh)
			sound = fresh
		else
			local slot = (nextSlot[name] or 0) % #list + 1
			nextSlot[name] = slot
			sound = list[slot]
		end
	end
	local s = sound :: Sound
	local jitter = JITTER[name] or 0
	local speed = pitch or 1
	if jitter > 0 then
		speed *= 1 + (math.random() * 2 - 1) * jitter
	end
	s.Volume = math.clamp(volume or 0.6, 0, 2)
	s.PlaybackSpeed = math.clamp(speed, 0.25, 4)
	s.TimePosition = 0
	s:Play()
end

function Sfx.music()
	local want = StoreLogic.setting(Store.view(), "music", true)
	local id = validId(Config.Audio.musicId)
	local m = musicSound
	if not want or id == nil then
		if m ~= nil then
			m:Stop()
		end
		return
	end
	if m == nil then
		local fresh = Instance.new("Sound")
		fresh.Name = "Music"
		fresh.Looped = true
		fresh.Volume = 0.35
		fresh.SoundId = id
		fresh.Parent = group
		musicSound = fresh
		m = fresh
	end
	if not m.IsPlaying then
		m:Play()
	end
end

Store.subscribe("settings", function()
	Sfx.music()
end)

return Sfx
