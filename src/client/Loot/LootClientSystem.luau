--!strict
-- Piece 42: listens to LootState, keeps LootClient up to date and plays a tiny placeholder effect
-- (floating text and the pickup sparkle). Claude Design owns the real heal look and sound.

local Players = game:GetService("Players")

local Net = require(script.Parent.Parent.Core.Net)
local Fx = require(script.Parent.Parent.Effects.Fx)
local LootClient = require("./LootClient")

local LootClientSystem = {}

local REASON_TEXT: { [string]: string } = {
	none = "No heal pack",
	full = "Health is full",
}

local function bodyPosition(): Vector3?
	local character = Players.LocalPlayer.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	if root ~= nil and root:IsA("BasePart") then
		return root.Position
	end
	return nil
end

function LootClientSystem.start()
	Net.on("LootState", function(p: any)
		if type(p) ~= "table" then
			return
		end
		local packs, max, readyAt = p.healPacks, p.max, p.readyAt
		if type(packs) ~= "number" or type(max) ~= "number" or type(readyAt) ~= "number" then
			return
		end
		LootClient.set(packs, max, readyAt)
		local at = bodyPosition()
		if at == nil then
			return
		end
		local up = at + Vector3.new(0, 4, 0)
		if p.event == "picked" then
			Fx.number(up, `+1 HEAL ({packs})`, "xp")
		elseif p.event == "used" then
			Fx.number(up, "+HP", "heal")
			Fx.play("pickupMine", at, nil)
		elseif p.event == "denied" and type(p.reason) == "string" then
			local text = REASON_TEXT[p.reason]
			if text ~= nil then
				Fx.number(up, text, "mine")
			end
		end
	end)
end

return LootClientSystem
