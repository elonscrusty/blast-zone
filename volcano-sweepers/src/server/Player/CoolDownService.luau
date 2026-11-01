--!strict
-- CoolDown (prestige): Economy.canCoolDown decides, Economy.coolDownReset builds the new profile.
-- The result goes into the LIVE profile table IN PLACE (other services hold that table, so its
-- identity must never change), through Profiles.update so an invalid result is thrown away.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Economy = require(Shared.Rules.Economy)
local ProfileSchema = require(Shared.Profile.ProfileSchema)
local Types = require(Shared.Types)

local Net = require(script.Parent.Parent.Core.Net)
local Profiles = require(script.Parent.Parent.Profile.Profiles)
local PlayerState = require(script.Parent.PlayerState)

local CoolDownService = {}

local started = false

-- The helper service is optional here: a missing one only means bots rebuild on their own next tick.
local function refreshBots(player: Player)
	local server = script.Parent and script.Parent.Parent
	local folder = server and server:FindFirstChild("Helpers")
	local module = folder and folder:FindFirstChild("HelperService")
	if module == nil or not module:IsA("ModuleScript") then
		return
	end
	local ok, service = pcall(require, module)
	if ok and type(service) == "table" and type((service :: any).refresh) == "function" then
		pcall((service :: any).refresh, player)
	end
end

local function coolDown(player: Player)
	local state = PlayerState.get(player)
	if state == nil then
		return
	end
	if not Economy.canCoolDown(state.profile) then
		PlayerState.toast(player, "Not yet! Keep sweeping and earning coins.", "warn")
		return
	end

	-- Nothing below yields before the profile is replaced, so two taps can't both pass.
	local out: { gained: number } = { gained = 0 }
	local ok, why = Profiles.update(player, function(copy: Types.Profile): boolean?
		if not Economy.canCoolDown(copy) then
			return false
		end
		local fresh, gained = Economy.coolDownReset(copy)
		out.gained = gained
		ProfileSchema.assign(copy :: any, fresh :: any)
		return true
	end)
	if not ok then
		warn(`[CoolDown] {player.Name}: not applied ({tostring(why)})`)
		PlayerState.toast(player, "Something wobbled. Try again in a moment!", "warn")
		return
	end

	-- the run is over: empty the backpack, then bring every number up to date
	PlayerState.takeCarried(player)
	PlayerState.recompute(player)
	PlayerState.fullSync(player)
	refreshBots(player)
	Net.fire("CoolDownDone", player, { sparksGained = out.gained } :: Types.CoolDownInfo)
	PlayerState.toast(player, `Cool Down! You earned {out.gained} Sparks!`, "gold")
	task.spawn(function()
		Profiles.saveNow(player) -- a Cool Down is never lost to a crash
	end)
end

function CoolDownService.init()
	if started then
		return
	end
	started = true
	Net.onRequest("CoolDown", coolDown)
end

return CoolDownService
