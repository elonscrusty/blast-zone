--!strict
-- Plays the cues. Every sound goes through the Music or Effects SoundGroup that the Settings panel
-- controls, so the volume sliders work with no extra code here. Sounds are 2D with their loudness
-- worked out from distance (AudioMath), capped by AudioLimiter, and removed when they end.
-- A cue with no id (AudioIds.luau) is skipped quietly.

local ContentProvider = game:GetService("ContentProvider")
local Players = game:GetService("Players")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local AudioCatalog = require("./AudioCatalog")
local AudioEvents = require("./AudioEvents")
local AudioLimiter = require("./AudioLimiter")
local AudioMath = require("./AudioMath")
local MusicPlan = require("./MusicPlan")

local AudioPlayer = {}

local MAX_VOICES = 18 -- effects playing at once
local RESERVE = 4 -- extra room for the player's own sounds
local UNKNOWN_POSITION_SCALE = 0.5 -- a world sound with no position is played at half volume
local LOAD_WARN = "[Audio] cue '%s' (id %d) did not load: pick another sound for it"

local limiter = AudioLimiter.new(MAX_VOICES, RESERVE)
local ids: { [string]: number } = {}
local voices: { [Sound]: string } = {} -- live effect sounds
local warned: { [string]: boolean } = {}
local voicesFolder: Folder? = nil

local musicName: string? = nil
local musicSound: Sound? = nil

local function groupNamed(name: string): SoundGroup
	local found = SoundService:WaitForChild(name, 5)
	if found and found:IsA("SoundGroup") then
		return found
	end
	-- The Settings piece normally makes these first; this keeps sound working if it did not.
	local g = Instance.new("SoundGroup")
	g.Name = name
	g.Parent = SoundService
	return g
end

local function listenerPosition(): Vector3?
	local camera = Workspace.CurrentCamera
	if camera then
		local subject = camera.CameraSubject
		if subject and subject:IsA("Humanoid") and subject.RootPart then
			return subject.RootPart.Position
		end
	end
	local character = Players.LocalPlayer.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	if root and root:IsA("BasePart") then
		return root.Position
	end
	if camera then
		return camera.Focus.Position
	end
	return nil
end

local function toId(assetId: number): string
	return "rbxassetid://" .. tostring(math.floor(assetId))
end

local function release(sound: Sound)
	local name = voices[sound]
	if name == nil then
		return
	end
	voices[sound] = nil
	limiter:finish(name)
	sound:Destroy()
end

-- Give the player the ids table (AudioIds). Reports mistakes, makes the SoundGroups reachable and
-- starts loading every sound that has an id so the first shot is not late.
function AudioPlayer.start(idTable: { [string]: number })
	ids = idTable
	for _, problem in AudioCatalog.problems(ids) do
		warn("[Audio] AudioIds: " .. problem)
	end
	groupNamed("Effects")
	groupNamed("Music")

	local folder = Instance.new("Folder")
	folder.Name = "AudioVoices"
	folder.Parent = SoundService
	voicesFolder = folder

	task.spawn(function()
		local toLoad: { Instance } = {}
		for _, name in AudioCatalog.names() do
			local id = AudioCatalog.assetId(name, ids)
			if id ~= nil then
				local s = Instance.new("Sound")
				s.SoundId = toId(id)
				table.insert(toLoad, s)
			end
		end
		if #toLoad > 0 then
			pcall(function()
				ContentProvider:PreloadAsync(toLoad)
			end)
		end
		for _, s in toLoad do
			s:Destroy()
		end
	end)
end

function AudioPlayer.play(request: AudioEvents.Request)
	local cue = AudioCatalog.get(request.cue)
	if cue == nil or cue.group ~= "Effects" then
		return
	end
	local id = AudioCatalog.assetId(request.cue, ids)
	if id == nil then
		return
	end

	local scale = request.scale or 1
	if cue.distance then
		local listener = listenerPosition()
		if typeof(request.pos) == "Vector3" and listener then
			scale *= AudioMath.scale(
				AudioMath.groundDistance(request.pos :: any, listener :: any),
				cue.distance.ref,
				cue.distance.max
			)
		else
			scale *= UNKNOWN_POSITION_SCALE
		end
	end
	local volume = cue.volume * scale
	if volume < AudioMath.audibleBelow then
		return
	end
	if not limiter:tryStart(request.cue, cue, os.clock()) then
		return
	end

	local sound = Instance.new("Sound")
	sound.SoundId = toId(id)
	sound.Volume = math.clamp(volume, 0, 1)
	local spread = cue.pitchSpread or 0
	sound.PlaybackSpeed = 1 + (math.random() * 2 - 1) * spread
	sound.SoundGroup = groupNamed(cue.group)
	sound.Parent = voicesFolder or SoundService
	voices[sound] = request.cue
	sound.Ended:Once(function()
		release(sound)
	end)
	task.delay(cue.seconds, function()
		-- Still here after its longest time: a sound that never loads would otherwise hold a voice.
		if voices[sound] ~= nil and not sound.IsLoaded and not warned[request.cue] then
			warned[request.cue] = true
			warn(string.format(LOAD_WARN, request.cue, id))
		end
		release(sound)
	end)
	sound:Play()
end

-- A new match or a reset: stop every effect and forget the limits. Music keeps playing.
function AudioPlayer.stopEffects()
	for sound in voices do
		sound:Stop()
		sound:Destroy()
	end
	table.clear(voices)
	limiter:clear()
end

local function fadeOutAndDestroy(sound: Sound)
	local tween = TweenService:Create(sound, TweenInfo.new(MusicPlan.fadeOut), { Volume = 0 })
	tween.Completed:Once(function()
		sound:Destroy()
	end)
	tween:Play()
	-- Backup in case the tween never reports back (sound removed mid-fade).
	task.delay(MusicPlan.fadeOut + 1, function()
		if sound.Parent ~= nil then
			sound:Destroy()
		end
	end)
end

-- Fade to this track (nil = fade to quiet). Same track again does nothing.
function AudioPlayer.setMusic(name: string?)
	if name == musicName then
		return
	end
	musicName = name
	local previous = musicSound
	musicSound = nil
	if previous then
		fadeOutAndDestroy(previous)
	end
	if name == nil then
		return
	end
	local cue = AudioCatalog.get(name)
	local id = AudioCatalog.assetId(name, ids)
	if cue == nil or cue.group ~= "Music" or id == nil then
		return
	end
	local sound = Instance.new("Sound")
	sound.SoundId = toId(id)
	sound.Looped = true
	sound.Volume = 0
	sound.SoundGroup = groupNamed("Music")
	sound.Parent = voicesFolder or SoundService
	sound:Play()
	musicSound = sound
	TweenService:Create(sound, TweenInfo.new(MusicPlan.fadeIn), { Volume = cue.volume }):Play()
end

return AudioPlayer
