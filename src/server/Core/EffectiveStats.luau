--!strict
-- What a participant's numbers are right now: EffectiveStats:get(participantId) -> StatSheet.
-- Movement and combat read this. Piece 08 installs the upgrade provider:
--   EffectiveStats:setProvider(function(id) return sheet end)  then  EffectiveStats:invalidate(id)
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local StatBook = require(Shared.StatBook)

return StatBook.new(Config)
