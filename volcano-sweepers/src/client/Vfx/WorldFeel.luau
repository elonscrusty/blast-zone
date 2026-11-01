--!strict
-- Small "juice" that makes every second feel alive, all on this client:
--   * "+N" pops out of every swing near you: what the ash you just picked up is worth in coins,
--     coloured by zone (warm white on the beach .. hot pink in the Lava Heart), BIG and gold for
--     golden cells. Driven by the Store (carried / carriedValue going up), so it shows exactly what
--     the server gave you. Throttled (Shared/Client/FloatLogic).
--   * "FULL!" pops once when the backpack fills up.
--   * A soft dust trail at your feet while you run (ash-coloured when you kick through ash).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local FloatLogic = require(Shared.Client.FloatLogic)
local Layout = require(Shared.Ash.Layout)
local Zones = require(Shared.Catalog.Zones)
local Store = require(script.Parent.Parent.Core.Store)
local Vfx = require(script.Parent.Vfx)

local function softRequire(folderName: string, moduleName: string): any?
	local folder = script.Parent.Parent:FindFirstChild(folderName)
	local mod = if folder ~= nil then folder:FindFirstChild(moduleName) else nil
	if mod == nil or not mod:IsA("ModuleScript") then
		return nil
	end
	local ok, result = pcall(require, mod)
	if not ok then
		return nil
	end
	return result
end

local AshRenderer: any = softRequire("Ash", "AshRenderer")

local WorldFeel = {}

local LocalPlayer = Players.LocalPlayer
local GROUND_Y: number = Config.World.groundY
local FLUSH_GAP = 0.16 -- seconds between "+N" pops (about one per swing)
local DUST_GAP = 0.16
local DUST_MIN_SPEED = 6

local acc = FloatLogic.new()
local seenUnits: number? = nil
local seenValue: number? = nil
local side = 1 -- alternate the pops left / right so they never stack on one spot

local function num(v: any): number?
	if type(v) == "number" and v == v and v > -1e15 and v < 1e15 then
		return v
	end
	return nil
end

local function myRoot(): BasePart?
	local character = LocalPlayer.Character
	local hrp = if character ~= nil then character:FindFirstChild("HumanoidRootPart") else nil
	if hrp ~= nil and hrp:IsA("BasePart") then
		return hrp
	end
	return nil
end

-- Richest zone value around me (where I stand and where my sweep lands).
local function zoneValueNear(hrp: BasePart): number
	local p = hrp.Position
	local look = hrp.CFrame.LookVector
	local best = 0
	for _, d in { 0, 6 } do
		local zone = Layout.zoneAt(p.X + look.X * d, p.Z + look.Z * d)
		if zone ~= nil then
			best = math.max(best, Zones.valueOf(zone))
		end
	end
	return best
end

-- Called whenever carried or carriedValue changes (both are merged before either listener runs).
local function sync()
	local view = Store.view()
	local units = num(view.carried)
	local value = num(view.carriedValue)
	if units == nil then
		return
	end
	local oldUnits, oldValue = seenUnits, seenValue
	seenUnits = units
	seenValue = value
	if oldUnits == nil then
		return -- first value from the server: nothing was swept, it is just the starting pack
	end
	local dUnits = units - oldUnits
	if dUnits > 0 then
		local dValue = if value ~= nil and oldValue ~= nil then value - oldValue else 0
		local hrp = myRoot()
		FloatLogic.add(acc, dUnits, dValue, if hrp ~= nil then zoneValueNear(hrp) else 1)
	end
	local derived = view.derived
	local capacity = if type(derived) == "table" then num(derived.capacity) else nil
	if FloatLogic.becameFull(oldUnits, units, capacity) then
		local hrp = myRoot()
		if hrp ~= nil then
			task.delay(0.2, function()
				Vfx.floatText(
					hrp.Position + Vector3.new(0, 4.5, 0),
					"FULL!",
					"bad",
					{ scale = 1.15 }
				)
			end)
		end
	end
end

Store.subscribe("carried", function()
	sync()
end)
Store.subscribe("carriedValue", function()
	sync()
end)

local function flush(now: number)
	if not FloatLogic.ready(acc, now, FLUSH_GAP) then
		return
	end
	local hrp = myRoot()
	if hrp == nil then
		FloatLogic.take(acc, now, 1) -- drop it: nowhere to show it
		return
	end
	local derived = Store.get("derived")
	local mult = if type(derived) == "table" then num(derived.sellMult) else nil
	local pop = FloatLogic.take(acc, now, mult)
	if pop == nil then
		return
	end
	local style = FloatLogic.style(pop)
	local look = hrp.CFrame.LookVector
	local right = hrp.CFrame.RightVector
	side = -side
	local at = hrp.Position
		+ Vector3.new(look.X, 0, look.Z) * 2.5
		+ Vector3.new(right.X, 0, right.Z) * (0.9 * side + (math.random() - 0.5) * 0.6)
		+ Vector3.new(0, 2.2, 0)
	Vfx.floatText(at, style.text, if pop.golden then "coin" else "ash", {
		color = style.color,
		scale = style.scale,
	})
end

-- ===== dust trail =====

local dustAcc = 0
local function dust(dt: number)
	dustAcc += dt
	if dustAcc < DUST_GAP then
		return
	end
	dustAcc = 0
	local character = LocalPlayer.Character
	local hrp = myRoot()
	local humanoid = if character ~= nil then character:FindFirstChildOfClass("Humanoid") else nil
	if hrp == nil or humanoid == nil or humanoid.FloorMaterial == Enum.Material.Air then
		return
	end
	local v = hrp.AssemblyLinearVelocity
	if v.X * v.X + v.Z * v.Z < DUST_MIN_SPEED * DUST_MIN_SPEED then
		return
	end
	local p = hrp.Position
	local zone = Layout.zoneAt(p.X, p.Z)
	if zone == nil then
		return -- the hub / paths stay clean
	end
	local z = Zones.byId[zone]
	local cell = Layout.cellOf(p.X, p.Z)
	local inAsh = cell ~= nil and AshRenderer ~= nil and AshRenderer.levelAt(cell) > 0
	local hex = if z == nil then "#E8DCC0" elseif inAsh then z.ash else z.ground
	Vfx.dust(Vector3.new(p.X, GROUND_Y + 0.4, p.Z), hex, if inAsh then 3 else 1)
end

RunService.Heartbeat:Connect(function(dt: number)
	flush(os.clock())
	dust(dt)
end)

return WorldFeel
