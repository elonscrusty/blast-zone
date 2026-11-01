--!strict
-- Client door to the pure text helpers (shared/Ui/Format). Same functions, so panels only need
-- to require one Ui module for text:  Fmt.n(1234) -> "1.2K"

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Format = require(Shared.Ui.Format)

local Fmt = {}

Fmt.n = Format.compact -- 1.2K, 3.4M
Fmt.exact = Format.commas -- 1,234,567
Fmt.clock = Format.countdown -- 1:05
Fmt.seconds = Format.secondsLeft
Fmt.percent = Format.percent -- 45%
Fmt.pair = Format.pair -- 12/30

return Fmt
