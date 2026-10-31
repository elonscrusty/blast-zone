--!strict
-- Wires the server's messages into the HUD model and draws it every frame. Starts itself.
-- Reads: HealthState, AmmoState, SlideState, MatchState, ZoneState, XpState, DamageTaken,
-- HitConfirm, Notice, Eliminated. Sends nothing (reload/swap are sent by ControlsSystem).
-- Hides itself outside fighting phases and after the local player is eliminated.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)

local Net = require(script.Parent.Parent.Core.Net)
local CameraHeading = require(script.Parent.Parent.Movement.CameraHeading)
local Controls = require(script.Parent.Parent.Controls.Controls)
local ControlsSystem = require(script.Parent.Parent.Controls.ControlsSystem)
local TouchControls = require(script.Parent.Parent.Controls.TouchControls)
local Settings = require(script.Parent.Parent.Settings.Settings)
local SettingsPanel = require(script.Parent.Parent.Settings.SettingsPanel)

local BigMapModel = require(script.Parent.BigMapModel)
local BigMapView = require(script.Parent.BigMapView)
local HudModel = require(script.Parent.HudModel)
local HudView = require(script.Parent.HudView)
local Layout = require(script.Parent.Layout)
local MinimapMath = require(script.Parent.MinimapMath)
local UiKit = require(script.Parent.UiKit)

local HudSystem = {}
HudSystem.order = 200

local MINIMAP_RANGE = 80 -- studs from the minimap centre to its rim

local function hudConfig(): HudModel.Config
	local pistol = Config.Weapons.Firearm
	local mortar = Config.Weapons.Explosive
	local weapons = {
		{
			id = pistol.id,
			name = pistol.displayName,
			magazine = pistol.magazine,
			reloadSeconds = pistol.reloadSeconds,
		},
	}
	if Config.Features.explosiveWeapon then
		table.insert(weapons, {
			id = mortar.id,
			name = mortar.displayName,
			magazine = mortar.magazine,
			reloadSeconds = mortar.reloadSeconds,
		})
	end
	return {
		maxHealth = Config.Health.max,
		weapons = weapons,
		slideCooldown = Config.Slide.cooldown,
		lowHealthFraction = 0.3,
		lowAmmoFraction = 0.25,
		edgeTolerance = Config.Zone.edgeTolerance,
		noticeSeconds = 3,
		hurtSeconds = 0.6,
		hitConfirmSeconds = 0.25,
	}
end

local function localPosition(): (number?, number?)
	local character = Players.LocalPlayer.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	if root and root:IsA("BasePart") then
		return root.Position.X, root.Position.Z
	end
	return nil, nil
end

function HudSystem.start()
	local config = hudConfig()
	local localId = "p" .. Players.LocalPlayer.UserId
	local model = HudModel.new(config, localId)

	local view = HudView.new({
		minimapRange = MINIMAP_RANGE,
		cameraYaw = Config.Camera.yawDegrees,
		weaponCount = #config.weapons,
	})
	view:mount()
	view:setScale(Settings.number("hudScale"))
	ControlsSystem.setWeapons(1, #config.weapons)
	local function syncControls()
		Controls.setEnabled(HudModel.controlsOn(model)) -- off until the server says a match is live
		Controls.setWalking(HudModel.walkOn(model)) -- the lobby: walking only
	end
	syncControls()

	-- ===== big map: tap the minimap (touch), M (keyboard) or Y (pad); any tap on it closes it =====
	local bigMap = BigMapModel.new()
	local bigMapView = BigMapView.new(Config.Arena, function()
		BigMapModel.close(bigMap)
	end)
	local offerUp = false -- a level-up offer is on screen; its cards and chips need the space
	local function hudShows(): boolean
		return HudModel.visible(model) and not offerUp
	end
	local function toggleBigMap()
		if Config.BigMap.enabled then
			BigMapModel.toggle(bigMap, os.clock(), hudShows())
		end
	end
	view.mapButton.Activated:Connect(toggleBigMap)
	Controls.Action:connect(function(action: string)
		if action == "map" then
			toggleBigMap()
		end
	end)
	Net.on("UpgradeOffer", function(offer: any)
		offerUp = offer ~= nil
		if offerUp then
			BigMapModel.close(bigMap)
		end
	end)
	UserInputService.InputBegan:Connect(function(input: InputObject)
		if input.KeyCode == Enum.KeyCode.ButtonB and bigMap.open then
			BigMapModel.close(bigMap)
		end
	end)

	-- the gear that opens the settings
	local gear = Instance.new("TextButton")
	gear.Name = "Gear"
	gear.Text = "⚙"
	gear.Font = UiKit.FONT
	gear.TextScaled = true
	gear.TextColor3 = UiKit.color(UiKit.look().ink)
	gear.BackgroundColor3 = UiKit.color(UiKit.look().panel)
	gear.AutoButtonColor = false
	gear.BorderSizePixel = 0
	gear.Parent = view.root
	UiKit.place(gear, Layout.regions.settings)
	UiKit.circle(gear)
	local gearStroke = Instance.new("UIStroke")
	gearStroke.Color = UiKit.color(UiKit.look().outline)
	gearStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	gearStroke.Parent = gear
	UiKit.styleStroke(gearStroke, view.root, 0.8)
	gear.Activated:Connect(function()
		SettingsPanel.toggle()
	end)

	Settings.Changed:connect(function(key: string, value: number | boolean)
		if key == "hudScale" and type(value) == "number" then
			view:setScale(value)
		end
	end)

	-- ===== server messages (all payloads are checked inside HudModel) =====
	local function now(): number
		return workspace:GetServerTimeNow()
	end

	Net.on("HealthState", function(p: any)
		HudModel.applyHealth(model, p)
	end)
	Net.on("AmmoState", function(p: any)
		HudModel.applyAmmo(model, p, config)
		ControlsSystem.setWeapons(model.slot, #config.weapons)
	end)
	Net.on("SlideState", function(p: any)
		HudModel.applySlide(model, p)
	end)
	Net.on("MatchState", function(p: any)
		HudModel.applyMatch(model, p, config)
		syncControls()
	end)
	Net.on("ZoneState", function(p: any)
		HudModel.applyZone(model, p)
	end)
	Net.on("XpState", function(p: any)
		HudModel.applyXp(model, p)
	end)
	Net.on("DamageTaken", function(p: any)
		local dir = nil
		if typeof(p.fromDir) == "Vector3" then
			dir = { x = p.fromDir.X, z = p.fromDir.Z }
		end
		HudModel.applyDamageTaken(model, { amount = p.amount, fromDir = dir }, now())
	end)
	Net.on("HitConfirm", function(p: any)
		HudModel.applyHitConfirm(model, p, now())
	end)
	Net.on("Notice", function(p: any)
		HudModel.applyNotice(model, p, now(), config)
	end)
	Net.on("Eliminated", function(p: any)
		HudModel.applyEliminated(model, p.victimId)
		syncControls()
	end)

	-- ===== every frame =====
	RunService.RenderStepped:Connect(function()
		local t = now()
		local px, pz = localPosition()
		local derived = HudModel.derive(model, t, px, pz, config)

		local safe = nil
		local zone = model.zone
		if zone and px ~= nil and pz ~= nil and derived.zoneRadius ~= nil then
			safe = MinimapMath.safeCircle(
				px,
				pz,
				zone.centerX,
				zone.centerZ,
				derived.zoneRadius,
				MINIMAP_RANGE,
				CameraHeading.get()
			)
		end

		view:update({
			view = derived,
			now = t,
			hurtDirX = model.hurtDirX,
			hurtDirZ = model.hurtDirZ,
			safe = safe,
			reduceFlashes = Settings.flag("reduceFlashes"),
			hitAmount = model.hitConfirmAmount,
		})
		local mapOpen =
			BigMapModel.step(bigMap, os.clock(), hudShows(), Config.BigMap.autoCloseSeconds)
		local drawZone = nil
		if mapOpen and zone and derived.zoneRadius ~= nil then
			drawZone = {
				centerX = zone.centerX,
				centerZ = zone.centerZ,
				radius = derived.zoneRadius,
				targetRadius = zone.toRadius,
			}
		end
		bigMapView:update({
			open = mapOpen,
			px = px,
			pz = pz,
			yaw = CameraHeading.get(),
			zone = drawZone,
		})
		TouchControls.update(
			derived.visible and HudModel.controlsOn(model),
			derived.slideReady,
			derived.slideFraction,
			derived.slideSeconds,
			HudModel.walkOn(model)
		)
	end)
end

return HudSystem
