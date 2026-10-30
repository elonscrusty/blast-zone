--!strict
-- The one door for player input. Other pieces never read keys or touches themselves.
--   Controls.getMove()    -> x, y   (x right, y forward = screen up, length <= 1)
--   Controls.getAim()     -> x, y, hasAim   (unit vector on screen: x right, y UP)
--   Controls.getAimWorld() -> Vector3?  (unit direction on the ground, x/z only; nil = no aim input)
--   Controls.isFiring()   -> boolean
--   Controls.Action       -> Signal of action names: "slide" "reload" "swap" "upgrade1".."upgrade3"
--   Controls.device()     -> "keyboard" | "touch" | "gamepad"
-- Movement is camera-relative: piece 02 turns (x, y) into a world direction with the camera yaw.
-- All input is cleared whenever controls turn off, so nothing stays stuck after a death or a menu.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Signal = require(Shared.Signal)

local InputState = require("./InputState")

local Controls = {}

local state = InputState.new()

-- Fires the name of every one-shot action (only while controls are on).
Controls.Action = Signal.new()
-- Fires the new device name when the player switches (touch <-> keyboard <-> gamepad).
Controls.DeviceChanged = Signal.new()

function Controls.getMove(): (number, number)
	return InputState.move(state)
end

function Controls.getAim(): (number, number, boolean)
	return InputState.aim(state)
end

local function flat(v: Vector3): Vector3?
	local f = Vector3.new(v.X, 0, v.Z)
	if f.Magnitude < 1e-3 then
		return nil
	end
	return f.Unit
end

-- The aim as a unit direction on the ground plane, ready to shoot or turn the body toward.
-- Mouse: through the cursor onto the floor at the character's height. Sticks: relative to the
-- camera's heading. nil when nothing is aiming (or the camera / character is missing).
function Controls.getAimWorld(): Vector3?
	local camera = workspace.CurrentCamera
	local _, _, hasAim = InputState.aim(state)
	if camera == nil or not hasAim then
		return nil
	end
	if state.device == "keyboard" then
		local character = Players.LocalPlayer.Character
		local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
		if root == nil or not root:IsA("BasePart") then
			return nil
		end
		local mouse = UserInputService:GetMouseLocation()
		local ray = camera:ViewportPointToRay(mouse.X, mouse.Y)
		if math.abs(ray.Direction.Y) < 1e-4 then
			return nil
		end
		local t = (root.Position.Y - ray.Origin.Y) / ray.Direction.Y
		if t <= 0 then
			return nil
		end
		local hit = ray.Origin + ray.Direction * t
		return flat(hit - root.Position)
	end
	local x, y = InputState.aim(state)
	local forward = flat(camera.CFrame.LookVector) or flat(camera.CFrame.UpVector)
	local right = flat(camera.CFrame.RightVector)
	if forward == nil or right == nil then
		return nil
	end
	return flat(right * x + forward * y)
end

function Controls.isFiring(): boolean
	return InputState.firing(state)
end

function Controls.device(): InputState.Device
	return state.device
end

function Controls.isEnabled(): boolean
	return state.enabled
end

-- ===== used by ControlsSystem, TouchControls and HudSystem (not by other pieces) =====

function Controls.setEnabled(enabled: boolean)
	InputState.setEnabled(state, enabled)
end

function Controls.reset()
	InputState.reset(state)
end

function Controls.setAimSensitivity(value: number)
	state.aimSensitivity = value
end

function Controls.noteDevice(device: InputState.Device)
	if InputState.noteDevice(state, device) then
		Controls.DeviceChanged:fire(device)
	end
end

function Controls.keyDown(code: string)
	local action = InputState.keyDown(state, code)
	if action then
		Controls.Action:fire(action)
	end
end

function Controls.keyUp(code: string)
	InputState.keyUp(state, code)
end

-- A touch button pressed (slide, reload, swap).
function Controls.trigger(action: string)
	if state.enabled then
		Controls.Action:fire(action)
	end
end

function Controls.setTouchMove(x: number, y: number)
	InputState.setTouchMove(state, x, y)
end

function Controls.setTouchAim(x: number, y: number, active: boolean)
	InputState.setTouchAim(state, x, y, active)
end

function Controls.setPadMove(x: number, y: number)
	InputState.setPadMove(state, x, y)
end

function Controls.setPadAim(x: number, y: number)
	InputState.setPadAim(state, x, y)
end

function Controls.setPadTrigger(amount: number)
	InputState.setPadTrigger(state, amount)
end

function Controls.setPointer(px: number, py: number, originX: number, originY: number)
	InputState.setPointer(state, px, py, originX, originY)
end

function Controls.setMouseDown(down: boolean)
	InputState.setMouseDown(state, down)
end

return Controls
