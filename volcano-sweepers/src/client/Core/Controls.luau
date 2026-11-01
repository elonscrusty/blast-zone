--!strict
-- Input -> intent. Sweeping is "hold": while a sweep source is held (the on-screen SWEEP button, mouse
-- button 1, E, gamepad R2) or Auto-Sweep finds ash in front of you, one `Sweep` remote goes out
-- every derived.interval seconds (never faster than Config.Player.minInterval). The remote carries
-- NO position: the server uses the character's own position and facing. Each swing also gives local
-- feedback at once (puff, camera nudge, sound, haptic) so it feels instant; the server does the rest.
--
--   Controls.setSweepHeld(bool)   the on-screen button (touch) calls this on press / release
--   Controls.sweepHeld()          true while any hold source is down
--   Controls.requestSell()        ask the server to sell (F, gamepad X, or the SELL button)
--   Controls.autoSweepActive()    true when the Auto-Sweep setting is on
--   Controls.setAutoSweep(bool)   ask the server to flip the Auto-Sweep setting
--   Controls.isSweeping()         true if a swing was sent in the last 0.6 s
--   Controls.swept                Signal, fires after every swing sent (no arguments)
--
-- Auto-Sweep fires only while the character stands on the ground and some cell in the fan in front
-- of it has ash AND is in a zone you have unlocked. Nothing is sent while the backpack is full.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local CullLogic = require(Shared.Client.CullLogic)
local Layout = require(Shared.Ash.Layout)
local Signal = require(Shared.Signal)
local StoreLogic = require(Shared.Client.StoreLogic)
local Tools = require(Shared.Catalog.Tools)
local Zones = require(Shared.Catalog.Zones)
local Net = require(script.Parent.Net)
local Store = require(script.Parent.Store)

-- Optional neighbours: Controls still works (without that feedback) if one of them fails to load.
local function softRequire(parent: Instance?, folderName: string, moduleName: string): any?
	if parent == nil then
		return nil
	end
	local folder = parent:FindFirstChild(folderName)
	local mod = if folder ~= nil then folder:FindFirstChild(moduleName) else nil
	if mod == nil or not mod:IsA("ModuleScript") then
		return nil
	end
	local ok, result = pcall(require, mod)
	if not ok then
		warn(`[Controls] could not load {moduleName}: {result}`)
		return nil
	end
	return result
end

local clientRoot = script.Parent.Parent
local Sfx: any = softRequire(clientRoot, "Core", "Sfx")
local Haptics: any = softRequire(clientRoot, "Core", "Haptics")
local CameraFx: any = softRequire(clientRoot, "Core", "CameraFx")
local AshRenderer: any = softRequire(clientRoot, "Ash", "AshRenderer")
local Vfx: any = softRequire(clientRoot, "Vfx", "Vfx")

local Controls = {}
Controls.swept = Signal.new()

local GROUND_Y: number = Config.World.groundY
local ZONE_COUNT: number = #Layout.zoneIds
local SELL_GAP = 0.35 -- seconds between sell requests
local AUTO_CHECK_GAP = 0.1
local FULL_NOTE_GAP = 2

local sources: { [string]: boolean } = { ui = false, mouse = false, key = false, pad = false }
local nextSweepAt = 0
local lastSellAt = -10
local lastSweepSentAt = -10
local lastFullNoteAt = -10
local lastAutoCheckAt = -10

local function anyHeld(): boolean
	return sources.ui or sources.mouse or sources.key or sources.pad
end

function Controls.setSweepHeld(held: boolean)
	sources.ui = held == true
end

function Controls.sweepHeld(): boolean
	return anyHeld()
end

function Controls.requestSell()
	local now = os.clock()
	if now - lastSellAt < SELL_GAP then
		return
	end
	lastSellAt = now
	Net.send("Sell")
end

function Controls.autoSweepActive(): boolean
	return StoreLogic.setting(Store.view(), "autoSweep", false)
end

function Controls.setAutoSweep(on: boolean)
	Net.send("SetSetting", "autoSweep", on == true)
end

function Controls.isSweeping(): boolean
	return os.clock() - lastSweepSentAt < 0.6
end

-- ===== keyboard, mouse, gamepad =====

local function setSource(name: string, on: boolean)
	sources[name] = on
end

UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
	local key = input.KeyCode
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		if not processed then
			setSource("mouse", true)
		end
	elseif key == Enum.KeyCode.E then
		if not processed then
			setSource("key", true)
		end
	elseif key == Enum.KeyCode.ButtonR2 then
		setSource("pad", true)
	elseif key == Enum.KeyCode.F then
		if not processed then
			Controls.requestSell()
		end
	elseif key == Enum.KeyCode.ButtonX then
		Controls.requestSell()
	end
end)

UserInputService.InputEnded:Connect(function(input: InputObject)
	local key = input.KeyCode
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		setSource("mouse", false)
	elseif key == Enum.KeyCode.E then
		setSource("key", false)
	elseif key == Enum.KeyCode.ButtonR2 then
		setSource("pad", false)
	end
end)

-- Losing the window while a key is down would otherwise leave a source stuck on.
UserInputService.WindowFocusReleased:Connect(function()
	setSource("mouse", false)
	setSource("key", false)
	setSource("pad", false)
end)

-- ===== the sweep loop =====

local function num(v: any, fallback: number): number
	if type(v) == "number" and v == v then
		return v
	end
	return fallback
end

local function characterParts(): (BasePart?, Humanoid?)
	local character = Players.LocalPlayer.Character
	if character == nil then
		return nil, nil
	end
	local hrp = character:FindFirstChild("HumanoidRootPart")
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if hrp == nil or not hrp:IsA("BasePart") then
		return nil, humanoid
	end
	return hrp, humanoid
end

local function feedback(
	hrp: BasePart,
	lookX: number,
	lookZ: number,
	reach: number,
	ashNear: boolean
)
	if Sfx ~= nil then
		Sfx.play("sweep")
	end
	if Haptics ~= nil then
		Haptics.tap(0.3)
	end
	if CameraFx ~= nil then
		CameraFx.nudge(0.45)
	end
	if ashNear and Vfx ~= nil then
		local ahead = math.min(reach * 0.6, 8)
		local x = hrp.Position.X + lookX * ahead
		local z = hrp.Position.Z + lookZ * ahead
		local zone = Layout.zoneAt(x, z) or Layout.zoneAt(hrp.Position.X, hrp.Position.Z)
		local ashHex = "#B8B2AA"
		if zone ~= nil and Zones.byId[zone] ~= nil then
			ashHex = Zones.byId[zone].ash
		end
		local tool = Tools.byId[tostring(Store.get("tool"))]
		if tool ~= nil then
			ashHex = CullLogic.mixHex(ashHex, tool.color, 0.3)
		end
		Vfx.puff(Vector3.new(x, GROUND_Y + 0.6, z), ashHex, 6)
	end
end

local function onHeartbeat()
	if not Store.ready then
		return
	end
	local now = os.clock()
	if now < nextSweepAt then
		return
	end
	local view = Store.view()
	local manual = anyHeld()
	local auto = not manual and StoreLogic.setting(view, "autoSweep", false)
	if not manual and not auto then
		return
	end
	if auto and now - lastAutoCheckAt < AUTO_CHECK_GAP then
		return
	end
	lastAutoCheckAt = now

	local hrp, humanoid = characterParts()
	if hrp == nil or humanoid == nil or humanoid.Health <= 0 then
		return
	end

	if StoreLogic.backpackFull(view) then
		if manual and now - lastFullNoteAt > FULL_NOTE_GAP then
			lastFullNoteAt = now
			if Sfx ~= nil then
				Sfx.play("error", 0.4)
			end
			if Haptics ~= nil then
				Haptics.tap(0.2)
			end
		end
		return
	end

	local look = hrp.CFrame.LookVector
	local lx, lz = look.X, look.Z
	local len = math.sqrt(lx * lx + lz * lz)
	if len < 1e-3 then
		if auto then
			return
		end
		lx, lz, len = 0, -1, 1
	end
	lx, lz = lx / len, lz / len

	local derived = view.derived
	local reach, arc = 7.0, 80.0
	if type(derived) == "table" then
		reach = num(derived.reach, reach)
		arc = num(derived.arcDeg, arc)
	end

	local ashNear = false
	if AshRenderer ~= nil then
		local allowed = StoreLogic.unlockedSet(view, ZONE_COUNT)
		ashNear = AshRenderer.ashAhead(hrp.Position.X, hrp.Position.Z, lx, lz, reach, arc, allowed)
	end
	if auto then
		if not ashNear or humanoid.FloorMaterial == Enum.Material.Air then
			return
		end
	end

	Net.send("Sweep")
	lastSweepSentAt = now
	local interval = StoreLogic.sweepInterval(view)
	if now - nextSweepAt > interval then
		nextSweepAt = now + interval
	else
		nextSweepAt += interval
	end
	feedback(hrp, lx, lz, reach, ashNear)
	Controls.swept:fire()
end

RunService.Heartbeat:Connect(onHeartbeat)

return Controls
