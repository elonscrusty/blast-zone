--!strict
-- INVITE button (stage 3, piece 26). Opens Roblox's own friend invite prompt. Phone first: it is a big touch
-- button; on PC it is clicked. Shown in the lobby and while watching a match you are not in (FriendInvite.showButton).
-- The invite carries "inv:<myUserId>" so the server knows who the friend came for. Nothing here is trusted by the
-- server: it only reads the launch data as a hint (see server/Social/SocialSystem).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SocialService = game:GetService("SocialService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local FriendInvite = require(Shared.FriendInvite)
local MatchPhase = require(Shared.MatchPhase)

local Net = require(script.Parent.Parent:WaitForChild("Core"):WaitForChild("Net"))
local UiLayers = require(script.Parent.Parent.Ui.UiLayers)

local player = Players.LocalPlayer
local FONT = Enum.Font.FredokaOne
local MIN_TOUCH = Config.Settings.minTouchTarget

type Look = {
	panel: string,
	ink: string,
	outline: string,
	accent: string,
	strokeScale: number,
	shadowOffset: number,
}

local function loadLook(): Look
	local hud = script.Parent.Parent:FindFirstChild("Hud")
	local module = if hud then hud:FindFirstChild("Theme") else nil
	if module and module:IsA("ModuleScript") then
		local ok, theme = pcall(require, module)
		if ok then
			return theme.get(nil)
		end
	end
	return {
		panel = "#FFF4D6",
		ink = Config.Palette.Navy,
		outline = Config.Palette.Navy,
		accent = Config.Palette.RewardGold,
		strokeScale = 0.0085,
		shadowOffset = 0.011,
	}
end

local InviteButtonSystem = {}
InviteButtonSystem.order = 220

function InviteButtonSystem.start()
	local look = loadLook()

	local gui = Instance.new("ScreenGui")
	gui.Name = "InviteFriends"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = UiLayers.MatchFlow -- lobby layer, so an open panel (Modal) covers it
	gui.Enabled = false

	-- Bottom middle, under PLAY and SETTINGS: easy for a thumb, clear of the joystick and fire button.
	local slot = Instance.new("Frame")
	slot.Name = "InviteSlot"
	slot.BackgroundTransparency = 1
	slot.AnchorPoint = Vector2.new(0.5, 0.5)
	slot.Position = UDim2.fromScale(0.5, 0.88)
	slot.Size = UDim2.fromScale(0.24, 0.1)
	slot.Parent = gui
	local minSize = Instance.new("UISizeConstraint")
	minSize.MinSize = Vector2.new(MIN_TOUCH * 3, MIN_TOUCH)
	minSize.MaxSize = Vector2.new(320, 80)
	minSize.Parent = slot

	local shadow = Instance.new("Frame")
	shadow.Name = "Shadow"
	shadow.BackgroundColor3 = Color3.fromHex(look.outline)
	shadow.BorderSizePixel = 0
	shadow.Size = UDim2.fromScale(1, 1)
	shadow.Parent = slot
	local shadowCorner = Instance.new("UICorner")
	shadowCorner.CornerRadius = UDim.new(0.3, 0)
	shadowCorner.Parent = shadow

	local button = Instance.new("TextButton")
	button.Name = "Invite"
	button.Size = UDim2.fromScale(1, 1)
	button.Text = "+ INVITE"
	button.Font = FONT
	button.TextScaled = true
	button.AutoButtonColor = true
	button.BackgroundColor3 = Color3.fromHex(look.panel)
	button.TextColor3 = Color3.fromHex(look.ink)
	button.Parent = slot
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.3, 0)
	corner.Parent = button
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0.2, 0)
	pad.PaddingBottom = UDim.new(0.2, 0)
	pad.Parent = button
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromHex(look.outline)
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = button

	local function resize()
		local h = gui.AbsoluteSize.Y
		stroke.Thickness = math.max(2, math.floor(h * look.strokeScale + 0.5))
		shadow.Position = UDim2.fromOffset(0, math.max(2, math.floor(h * look.shadowOffset + 0.5)))
	end
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(resize)
	gui.Parent = player:WaitForChild("PlayerGui")
	resize()

	-- ===== when to show it =====
	local phase = MatchPhase.Waiting
	local function inMatch(): boolean
		local character = player.Character
		return character ~= nil and character:GetAttribute(Config.Attributes.ParticipantId) ~= nil
	end
	local function refresh()
		gui.Enabled = FriendInvite.showButton(phase, inMatch())
	end
	Net.on("MatchState", function(state: any)
		if type(state) == "table" and type(state.phase) == "string" then
			phase = state.phase
			refresh()
		end
	end)
	player.CharacterAdded:Connect(function(character)
		character:GetAttributeChangedSignal(Config.Attributes.ParticipantId):Connect(refresh)
		refresh()
	end)

	-- ===== the prompt =====
	local busy = false
	local function flash(words: string)
		button.Text = words
		task.delay(2, function()
			button.Text = "+ INVITE"
		end)
	end
	button.Activated:Connect(function()
		if busy then
			return
		end
		busy = true
		local okCheck, canSend = pcall(function()
			return SocialService:CanSendGameInviteAsync(player)
		end)
		if not okCheck or not canSend then
			flash("NO INVITES HERE") -- Studio, or the account can't send invites
			busy = false
			return
		end
		local options = Instance.new("ExperienceInviteOptions")
		options.LaunchData = FriendInvite.makeLaunchData(player.UserId)
		options.PromptMessage = `Come play {Config.Game.Name} with me!`
		local okPrompt = pcall(function()
			SocialService:PromptGameInvite(player, options)
		end)
		if not okPrompt then
			flash("TRY AGAIN")
		end
		busy = false
	end)

	refresh()
end

return InviteButtonSystem
