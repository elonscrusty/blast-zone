--!strict
-- Finds or creates the RemoteEvents listed in RemoteDefs. Not tested in Lune (uses Instances).
--   Server: Remotes.build() once at start (Core/Net does it).
--   Both:   Remotes.get(name) -> RemoteEvent  (the client waits for the server to build them)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require("./Config")
local RemoteDefs = require("./RemoteDefs")

local FOLDER_NAME = "Remotes"

local Remotes = {}

function Remotes.build(): Folder
	assert(RunService:IsServer(), "Remotes.build is server only")
	local folder = ReplicatedStorage:FindFirstChild(FOLDER_NAME)
	if folder == nil then
		folder = Instance.new("Folder")
		folder.Name = FOLDER_NAME
		folder.Parent = ReplicatedStorage
	end
	local f = folder :: Folder
	for _, def in RemoteDefs.list do
		if f:FindFirstChild(def.name) == nil then
			local ev = Instance.new("RemoteEvent")
			ev.Name = def.name
			ev.Parent = f
		end
	end
	return f
end

local cache: { [string]: RemoteEvent } = {}

function Remotes.get(name: string): RemoteEvent
	local cached = cache[name]
	if cached ~= nil and cached.Parent ~= nil then
		return cached -- every shot, hit and pickup goes through here: no tree lookups
	end
	if RemoteDefs.byName[name] == nil then
		error("Unknown remote '" .. tostring(name) .. "'. Add it to RemoteDefs first.", 2)
	end
	local folder = ReplicatedStorage:WaitForChild(FOLDER_NAME, Config.Net.clientWaitSeconds)
	if folder == nil then
		error("Remotes folder never appeared", 2)
	end
	local ev = folder:WaitForChild(name, Config.Net.clientWaitSeconds)
	if ev == nil or not ev:IsA("RemoteEvent") then
		error("Remote '" .. name .. "' missing", 2)
	end
	cache[name] = ev
	return ev
end

return Remotes
