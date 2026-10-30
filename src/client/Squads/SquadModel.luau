--!strict
-- What this client knows about its squad (video 3 gap 11). The server sends it; plates and the squad list read it.
-- Holds no rules: the server decides who is a teammate.

local Signal = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared").Signal)

export type Mate = { id: string, name: string, alive: boolean }
export type State = { size: number, team: number?, mates: { Mate } }

local SquadModel = {}
SquadModel.Changed = Signal.new() -- ()

local current: State = { size = 1, team = nil, mates = {} }
local mateIds: { [string]: boolean } = {}

function SquadModel.set(state: State)
	current = state
	mateIds = {}
	for _, mate in state.mates do
		mateIds[mate.id] = true
	end
	SquadModel.Changed:fire()
end

function SquadModel.get(): State
	return current
end

function SquadModel.isMate(participantId: any): boolean
	return type(participantId) == "string" and mateIds[participantId] == true
end

return SquadModel
