--!strict
-- Hooks the real devices into Controls: keyboard and mouse, gamepad, touch (via TouchControls),
-- and sends ReloadRequest / SwitchWeaponRequest / UseHealRequest. Starts itself (any "...System" module does).
-- Slide direction needs the camera, so piece 02 listens to Controls.Action and sends SlideRequest.
-- Firing is polled by piece 03 (Controls.isFiring / getAim); this module never sends FireRequest.

local Players = game:GetService("Players")
local GuiService = game:GetService("GuiService")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Net = require(script.Parent.Parent.Core.Net)
local Controls = require(script.Parent.Controls)
local TouchControls = require(script.Parent.TouchControls)

local ControlsSystem = {}
ControlsSystem.order = 50 -- before the HUD

-- Set by HudSystem so the swap button knows which weapon comes next.
local weaponSlot = 1
local weaponCount = 1

function ControlsSystem.setWeapons(slot: number, count: number)
	weaponSlot = slot
	weaponCount = count
end

local function deviceOf(input: InputObject): string?
	local t = input.UserInputType
	if t == Enum.UserInputType.Touch then
		return "touch"
	elseif
		t == Enum.UserInputType.Keyboard
		or t == Enum.UserInputType.MouseButton1
		or t == Enum.UserInputType.MouseButton2
		or t == Enum.UserInputType.MouseMovement
		or t == Enum.UserInputType.MouseWheel
	then
		return "keyboard"
	elseif string.sub(t.Name, 1, 7) == "Gamepad" then
		return "gamepad"
	end
	return nil
end

-- Where the character is drawn on screen, so the mouse aims from the character, not the centre.
local function characterOnScreen(): (number, number)
	local camera = workspace.CurrentCamera
	local fallback = if camera then camera.ViewportSize / 2 else Vector2.new(400, 300)
	if camera == nil then
		return fallback.X, fallback.Y
	end
	local character = Players.LocalPlayer.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	if root and root:IsA("BasePart") then
		local screen, onScreen = camera:WorldToViewportPoint(root.Position)
		if onScreen then
			return screen.X, screen.Y
		end
	end
	return fallback.X, fallback.Y
end

local function disableDefaultControls()
	-- The default WASD / thumbstick / jump button would fight with ours (and add a jump button).
	task.spawn(function()
		local playerScripts = Players.LocalPlayer:WaitForChild("PlayerScripts", 15)
		local module = if playerScripts then playerScripts:WaitForChild("PlayerModule", 15) else nil
		if module == nil then
			return
		end
		local ok, err = pcall(function()
			local playerModule = (require :: any)(module)
			playerModule:GetControls():Disable()
		end)
		if not ok then
			warn("[controls] could not turn off the default controls: " .. tostring(err))
		end
	end)
end

function ControlsSystem.start()
	disableDefaultControls()

	if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
		Controls.noteDevice("touch")
	elseif UserInputService.GamepadEnabled and not UserInputService.KeyboardEnabled then
		Controls.noteDevice("gamepad")
	end

	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		local device = deviceOf(input)
		if device and device ~= "touch" then
			Controls.noteDevice(device :: any)
		end
		if input.UserInputType == Enum.UserInputType.Keyboard then
			if not processed then -- typing in chat must not move or fire
				Controls.keyDown(input.KeyCode.Name)
			end
		elseif input.UserInputType == Enum.UserInputType.MouseButton1 then
			if not processed then
				Controls.setMouseDown(true)
			end
		elseif device == "gamepad" then
			Controls.keyDown(input.KeyCode.Name)
		end
	end)

	UserInputService.InputEnded:Connect(function(input: InputObject, _processed: boolean)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			Controls.setMouseDown(false)
		elseif
			input.UserInputType == Enum.UserInputType.Keyboard or deviceOf(input) == "gamepad"
		then
			Controls.keyUp(input.KeyCode.Name) -- always released, even if the press was swallowed
		end
	end)

	-- A hybrid laptop switches to the touch controls the moment a finger touches the screen.
	UserInputService.TouchStarted:Connect(function()
		Controls.noteDevice("touch")
	end)

	UserInputService.InputChanged:Connect(function(input: InputObject, _processed: boolean)
		local device = deviceOf(input)
		if device == "keyboard" then
			Controls.noteDevice("keyboard")
		elseif device == "gamepad" then
			if input.KeyCode == Enum.KeyCode.Thumbstick1 then
				Controls.setPadMove(input.Position.X, input.Position.Y)
			elseif input.KeyCode == Enum.KeyCode.Thumbstick2 then
				Controls.setPadAim(input.Position.X, input.Position.Y)
			elseif input.KeyCode == Enum.KeyCode.ButtonR2 then
				Controls.setPadTrigger(input.Position.Z)
			end
		end
	end)

	-- Anything that takes the keyboard or the window away clears all held input.
	UserInputService.WindowFocusReleased:Connect(Controls.reset)
	UserInputService.WindowFocused:Connect(Controls.reset) -- keys let go while away must not come back
	UserInputService.TextBoxFocused:Connect(Controls.reset)
	GuiService.MenuOpened:Connect(Controls.reset)
	GuiService.MenuClosed:Connect(Controls.reset)
	-- Unplugging a pad mid-fight (a dead battery, a pulled cable) must not leave a stick pushed.
	UserInputService.GamepadDisconnected:Connect(function()
		Controls.padDisconnected(UserInputService.TouchEnabled)
	end)

	-- Reload and weapon swap go straight to the server, which checks everything.
	Controls.Action:connect(function(action: string)
		if action == "reload" then
			Net.send("ReloadRequest")
		elseif action == "heal" then
			Net.send("UseHealRequest")
		elseif action == "swap" and weaponCount > 1 then
			local nextSlot = if weaponSlot >= weaponCount then 1 else weaponSlot + 1
			Net.send("SwitchWeaponRequest", nextSlot)
		end
	end)

	TouchControls.start()

	RunService.RenderStepped:Connect(function()
		if UserInputService.MouseEnabled and Controls.device() == "keyboard" then
			local mouse = UserInputService:GetMouseLocation()
			local ox, oy = characterOnScreen()
			Controls.setPointer(mouse.X, mouse.Y, ox, oy)
		end
	end)
end

return ControlsSystem
