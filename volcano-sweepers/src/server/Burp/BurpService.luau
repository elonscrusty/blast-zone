--!strict
-- The volcano's burps on the server. Runs the shared BurpDirector (pure state machine) every 0.25 s
-- with live player positions and carries out what it says. The rules are in shared/Burp
-- (BurpDirector, BurpGlue; tested in Lune): this file only touches the world.
--
--   BurpService.init()   once, after FindsService.init (Main order). Safe to call twice.
--
-- What each director event does here:
--   phase    -> `Burp` remote to everyone (BurpInfo, server times). The sky/ambient light tweens toward
--               red in rumble and lava-pop events and back to normal afterwards. Camera shake is the
--               client's job (it hears the same remote). Round bookkeeping for burpDodged.
--   bombs    -> `Bombs` remote to everyone + falling lava bomb Parts (BombVisuals, at most 40 live).
--   land     -> BombVisuals.land, then every ready player outside the hub is hit-tested with
--               BurpDirector:hitTest. Hit = bounce (velocity away from the blast), lose
--               0.2 x (1 - armor) of the backpack (that ash falls back onto the ground nearby),
--               `BurpHit` remote, stat burpHits, a 2.5 s shield, director:reportHit. Nobody ever dies.
--   rain     -> AshService.grid:rain
--   golden   -> AshService.grid:spawnGolden (only zones somebody here has unlocked), clearGolden at
--               expiry, buff "golden" for the HUD timer
--   geysers  -> GeyserService.spawnWave
--   perfect  -> buff "perfect" (stretched by the best Spark "long buffs" in the server) + a gold Toast
--   burpDodged +1 for each ready player outside the hub who was around when a bomb landed and was not
--   hit by the time that event ended.
--
-- With nobody ready the director sleeps and nothing happens.

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BurpDirector = require(Shared.Burp.BurpDirector)
local BurpGlue = require(Shared.Burp.BurpGlue)
local Config = require(Shared.Config)
local Rng = require(Shared.Rng)
local Types = require(Shared.Types)

local Net = require(script.Parent.Parent.Core.Net)
local PlayerState = require(script.Parent.Parent.Player.PlayerState)
local BombVisuals = require(script.Parent.BombVisuals)
local GeyserService = require(script.Parent.GeyserService)

local TICK_SECONDS = 0.25
local RED = Color3.fromRGB(255, 80, 50)
local MAX_RED = 0.55 -- how far toward RED the light goes at intensity 1

type Target = {
	state: PlayerState.State,
	hrp: BasePart,
	hum: Humanoid,
	x: number,
	z: number,
}

local BurpService = {}

local started = false
local rng = Rng.new(os.time() + 104729 + math.floor(os.clock() * 1000))
local director: BurpDirector.BurpDirector = BurpDirector.new(Rng.new(os.time() + 31337))
local book = BurpGlue.newBook()
local round = BurpGlue.newRound()
local goldenUntil: number? = nil
local ashMod: any = nil
local lastWarn = -10

local function warnThrottled(msg: string)
	if os.clock() - lastWarn > 5 then
		lastWarn = os.clock()
		warn("[BurpService] " .. msg)
	end
end

-- AshService is written by another piece and may be missing or broken: lazy pcall-require, then cached.
local function ashService(): any
	if ashMod ~= nil then
		return ashMod
	end
	local ok, mod = pcall(function(): any
		local folder = script.Parent.Parent:FindFirstChild("Ash")
		local m = if folder ~= nil then folder:FindFirstChild("AshService") else nil
		if m ~= nil and m:IsA("ModuleScript") then
			return require(m)
		end
		return nil
	end)
	if ok and mod ~= nil then
		ashMod = mod
	end
	return ashMod
end

-- ===== sky tint =====

type Base = { ambient: Color3, outdoor: Color3, atmosphere: Atmosphere?, atmosColor: Color3? }
local tintBase: Base? = nil
local tintTweens: { Tween } = {}
local tintToken = 0

local function setTint(intensity: number, seconds: number)
	tintToken += 1
	local token = tintToken
	for _, tw in tintTweens do
		tw:Cancel()
	end
	tintTweens = {}
	local base = tintBase
	if base == nil then
		if intensity <= 0 then
			return
		end
		local atmos = Lighting:FindFirstChildOfClass("Atmosphere")
		base = {
			ambient = Lighting.Ambient,
			outdoor = Lighting.OutdoorAmbient,
			atmosphere = atmos,
			atmosColor = if atmos ~= nil then atmos.Color else nil,
		}
		tintBase = base
	end
	local b = base :: Base
	local amount = MAX_RED * math.clamp(intensity, 0, 1)
	local info = TweenInfo.new(seconds, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)
	local function go(inst: Instance, props: { [string]: any })
		local ok, tw = pcall(function()
			return TweenService:Create(inst, info, props)
		end)
		if ok and tw ~= nil then
			table.insert(tintTweens, tw)
			tw:Play()
		end
	end
	go(Lighting, {
		Ambient = b.ambient:Lerp(RED, amount),
		OutdoorAmbient = b.outdoor:Lerp(RED, amount),
	})
	local atmos, atmosColor = b.atmosphere, b.atmosColor
	if atmos ~= nil and atmosColor ~= nil and atmos.Parent ~= nil then
		go(atmos, { Color = atmosColor:Lerp(RED, amount) })
	end
	if intensity <= 0 then
		-- fully restored: forget the remembered colours so a later change elsewhere is not undone
		task.delay(seconds + 0.1, function()
			if tintToken == token then
				tintBase = nil
			end
		end)
	end
end

-- ===== players =====

local function bodyOf(player: Player): (BasePart?, Humanoid?)
	local char = player.Character
	if char == nil then
		return nil, nil
	end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	local hum = char:FindFirstChildOfClass("Humanoid")
	if hrp == nil or not hrp:IsA("BasePart") or hum == nil or hum.Health <= 0 then
		return nil, nil
	end
	return hrp, hum
end

-- Ready players that currently have a living character, with flat positions.
local function gather(): ({ Target }, number)
	local ready = PlayerState.all()
	local targets: { Target } = {}
	for _, state in ready do
		local hrp, hum = bodyOf(state.player)
		if hrp ~= nil and hum ~= nil then
			local p = hrp.Position
			if BurpGlue.finite(p.X) and BurpGlue.finite(p.Z) then
				table.insert(targets, { state = state, hrp = hrp, hum = hum, x = p.X, z = p.Z })
			end
		end
	end
	return targets, #ready
end

local function toastAll(text: string, kind: "info" | "good" | "warn" | "gold")
	local info: Types.ToastInfo = { text = text, kind = kind }
	Net.fireAll("Toast", info)
end

local function bounce(t: Target, vx: number, vy: number, vz: number)
	-- Not a ragdoll: one velocity kick and the Humanoid is told it is airborne so it does not fight it.
	pcall(function()
		t.hrp.AssemblyLinearVelocity = Vector3.new(vx, vy, vz)
		t.hum:ChangeState(Enum.HumanoidStateType.Freefall)
	end)
end

local function applyHit(t: Target, bomb: Types.Bomb, now: number)
	local state = t.state
	local player = state.player
	state.lastHitAt = now
	local lost = PlayerState.dropCarried(player, BurpGlue.dropFraction(state.derived.armor))
	if lost > 0 then
		local ash = ashService()
		if ash ~= nil then
			local ok, err = pcall(ash.dropAround, t.x, t.z, lost)
			if not ok then
				warnThrottled("dropAround failed: " .. tostring(err))
			end
		end
	end
	PlayerState.addStat(player, "burpHits", 1)
	local info: Types.BurpHitInfo = { userId = player.UserId, dropped = lost }
	Net.fireAll("BurpHit", info)
	local vx, vy, vz = BurpGlue.knockback(t.x, t.z, bomb.x, bomb.z)
	bounce(t, vx, vy, vz)
	Net.fire(
		"Toast",
		player,
		{
			text = if lost > 0 then `Bonk! You dropped {lost} ash.` else "Bonk! Lava bounce!",
			kind = "warn",
		} :: Types.ToastInfo
	)
	director:reportHit(player.UserId, now)
	BurpGlue.roundHit(round, player.UserId)
end

-- ===== executing commands =====

local function finishRound()
	for _, userId in BurpGlue.roundFinish(round) do
		local player = Players:GetPlayerByUserId(userId)
		if player ~= nil and PlayerState.get(player) ~= nil then
			PlayerState.addStat(player, "burpDodged", 1)
		end
	end
end

local function unlockedZones(): { [number]: boolean }?
	local out: { [number]: boolean } = {}
	local found = false
	for _, state in PlayerState.all() do
		for key, owned in state.profile.zones do
			local id = tonumber(key)
			if owned == true and id ~= nil then
				out[id] = true
				found = true
			end
		end
	end
	return if found then out else nil
end

local function bestBuffTime(): number
	local best = 1
	for _, state in PlayerState.all() do
		local m = state.derived.buffTime
		if BurpGlue.finite(m) and m > best then
			best = m
		end
	end
	return best
end

local function execute(cmd: BurpGlue.Command, now: number, targets: { Target })
	local kind = cmd.kind
	if kind == "phase" then
		local info = cmd.info :: Types.BurpInfo
		Net.fireAll("Burp", info)
		if info.phase == "rumble" then
			BurpGlue.roundReset(round)
		elseif info.phase == "recover" or info.phase == "calm" then
			finishRound()
		end
		local seconds = if info.phase == "rumble" then 3 elseif info.phase == "event" then 1.5 else 4
		setTint(cmd.tint or 0, seconds)
	elseif kind == "bombs" then
		local bombs = cmd.bombs :: { Types.Bomb }
		local bombsInfo: Types.BombsInfo = { bombs = bombs }
		Net.fireAll("Bombs", bombsInfo)
		for _, bomb in bombs do
			BombVisuals.spawn(bomb, now)
		end
	elseif kind == "land" then
		local bomb = cmd.bomb :: Types.Bomb
		BombVisuals.land(bomb.id)
		local present: { number } = {}
		for _, t in targets do
			if not BurpGlue.inHub(t.x, t.z) then
				table.insert(present, t.state.player.UserId)
				if
					director:hitTest(bomb, t.x, t.z)
					and BurpGlue.canBeHit(t.state.lastHitAt, now)
				then
					applyHit(t, bomb, now)
				end
			end
		end
		BurpGlue.roundLand(round, present)
	elseif kind == "rain" then
		local ash = ashService()
		if ash ~= nil then
			ash.grid:rain(rng, cmd.fraction :: number)
		end
	elseif kind == "golden" then
		local untilAt = cmd.untilAt :: number
		local ash = ashService()
		if ash ~= nil then
			local flagged = ash.grid:spawnGolden(rng, cmd.cells :: number, unlockedZones())
			goldenUntil = untilAt
			Net.fireAll("Golden", { cells = flagged, endsAt = untilAt })
		end
		PlayerState.setBuff("golden", untilAt)
	elseif kind == "geysers" then
		GeyserService.spawnWave(cmd.spots :: { BurpDirector.Spot })
	elseif kind == "perfect" then
		local untilAt = BurpGlue.buffUntil(now, cmd.untilAt :: number, bestBuffTime())
		PlayerState.setBuff("perfect", untilAt)
		local pct = math.floor((Config.Economy.perfectMult - 1) * 100 + 0.5)
		toastAll(`Perfect Dodge! Coins +{pct}%`, "gold")
	end
end

local function tick()
	local now = workspace:GetServerTimeNow()

	-- golden cells end on time even if nobody is around any more
	local gu = goldenUntil
	if gu ~= nil and now >= gu then
		goldenUntil = nil
		local ash = ashService()
		if ash ~= nil then
			ash.grid:clearGolden()
			Net.fireAll("Golden", { cells = {}, endsAt = 0 })
		end
	end

	local targets, readyCount = gather()
	local positions: { BurpDirector.PlayerPos } = {}
	for _, t in targets do
		table.insert(positions, {
			userId = t.state.player.UserId,
			x = t.x,
			z = t.z,
			zone = BurpGlue.zoneOf(t.x, t.z),
		})
	end
	local clean = 0
	local ash = ashService()
	if ash ~= nil then
		local ok, v = pcall(function()
			return ash.grid:totalClean()
		end)
		if ok and type(v) == "number" and v == v then
			clean = math.clamp(v, 0, 1)
		end
	end

	local events = director:step(now, {
		playerPositions = positions,
		cleanTotal = clean,
		playerCount = readyCount,
	})
	for _, cmd in BurpGlue.buildCommands(book, events, now) do
		local ok, err = pcall(execute, cmd, now, targets)
		if not ok then
			warnThrottled(`{cmd.kind} failed: {err}`)
		end
	end
end

function BurpService.init()
	if started then
		return
	end
	started = true
	BombVisuals.init()
	GeyserService.init()

	-- someone joining mid-burp should see the banner too
	PlayerState.onReady:connect(function(player: Player)
		local s = director:getState()
		if s.awake and s.phase ~= "calm" then
			local info: Types.BurpInfo = {
				phase = s.phase,
				kind = s.burpKind,
				startsAt = s.startsAt,
				endsAt = s.endsAt,
			}
			Net.fire("Burp", player, info)
		end
		local gu = goldenUntil
		local ash = ashService()
		if gu ~= nil and ash ~= nil and workspace:GetServerTimeNow() < gu then
			local cells = {}
			for idx in ash.grid.goldenSet do
				table.insert(cells, idx)
			end
			Net.fire("Golden", player, { cells = cells, endsAt = gu })
		end
	end)

	task.spawn(function()
		while true do
			task.wait(TICK_SECONDS)
			local ok, err = pcall(tick)
			if not ok then
				warnThrottled("tick failed: " .. tostring(err))
			end
		end
	end)
end

return BurpService
