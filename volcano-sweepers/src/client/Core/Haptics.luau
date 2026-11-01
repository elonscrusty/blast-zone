--!strict
-- Controller rumble (and any vibration the device offers) through HapticService. Roblox has no
-- public API for a phone's own vibration motor, so on a phone this only does something when the
-- platform reports support. Guarded by settings.vibrate.
--   Haptics.tap(strength)   strength 0..1; a short pulse

local HapticService = game:GetService("HapticService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local StoreLogic = require(Shared.Client.StoreLogic)
local Store = require(script.Parent.Store)

local Haptics = {}

local TARGETS: { Enum.UserInputType } = { Enum.UserInputType.Gamepad1 }
local MIN_GAP = 0.05
local lastAt = 0
local token = 0

local function supportedMotor(target: Enum.UserInputType): Enum.VibrationMotor?
	local ok, supported = pcall(function()
		return HapticService:IsVibrationSupported(target)
	end)
	if not ok or not supported then
		return nil
	end
	for _, motor in { Enum.VibrationMotor.Small, Enum.VibrationMotor.Large } do
		local okMotor, has = pcall(function()
			return HapticService:IsMotorSupported(target, motor)
		end)
		if okMotor and has then
			return motor
		end
	end
	return nil
end

function Haptics.tap(strength: number)
	if not StoreLogic.setting(Store.view(), "vibrate", true) then
		return
	end
	if strength ~= strength then
		return
	end
	local now = os.clock()
	if now - lastAt < MIN_GAP then
		return
	end
	lastAt = now
	local power = math.clamp(strength, 0, 1)
	if power <= 0 then
		return
	end
	token += 1
	local mine = token
	for _, target in TARGETS do
		local motor = supportedMotor(target)
		if motor ~= nil then
			pcall(function()
				HapticService:SetMotor(target, motor, power)
			end)
			task.delay(0.06 + 0.12 * power, function()
				if mine == token then
					pcall(function()
						HapticService:SetMotor(target, motor, 0)
					end)
				end
			end)
		end
	end
end

return Haptics
