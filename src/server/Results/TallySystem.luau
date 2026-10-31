--!strict
-- Counts what each fighter did this match, for the results card (video 3 gap 29).
-- Other systems call TallySystem.add(id, kind) when something really happened (the server already checked it).
-- The book is cleared when a new match starts. Nothing here is saved or sent on its own:
-- MatchSystem asks for a player's counts when it sends that player's results.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local MatchTally = require(Shared.Results.MatchTally)

local ServerRoot = script.Parent.Parent
local MatchContext = require(ServerRoot.Core.MatchContext)

local TallySystem = {}
TallySystem.order = 40 -- before the systems that count (props, containers, upgrades) and before MatchSystem

local book: MatchTally.Book = MatchTally.new()

function TallySystem.add(id: string?, kind: string)
	MatchTally.add(book, id, kind)
end

function TallySystem.get(id: string): MatchTally.Counts
	return MatchTally.get(book, id)
end

function TallySystem.start()
	MatchContext.MatchStarted:connect(function()
		MatchTally.reset(book)
	end)
end

return TallySystem
