--!strict
-- Invite friends (stage 3, piece 26). Pure rules so Lune can test them; no Roblox calls in here.
--
-- How a friend ends up next to you:
--   1. You tap INVITE. The client opens Roblox's own invite prompt (SocialService) with launch data "inv:<yourUserId>".
--   2. Your friend taps the invite. Roblox puts them in YOUR server (a server is one lobby and one match).
--   3. The server reads who they came for: the invite's launch data, or Player.FollowUserId ("Join" on a profile).
--      The launch data is only a hint: the host must really be in this server, and it never gives anything but a
--      spot in the queue for the next match.
--   4. If the host is queued or in a match, the friend is queued too, so they start the next match together.
--      Mid-match (or a full match), the friend watches and goes in next time. The game stays free-for-all.

local FriendInvite = {}

FriendInvite.prefix = "inv:"
FriendInvite.maxLaunchDataLength = 32 -- "inv:" + a userId; anything longer is not ours

-- What the inviter's client puts in the invite.
function FriendInvite.makeLaunchData(userId: number): string
	return FriendInvite.prefix .. tostring(math.floor(userId))
end

-- What the joiner's server reads back. Anything odd gives nil.
function FriendInvite.parseLaunchData(data: any): number?
	if type(data) ~= "string" or #data > FriendInvite.maxLaunchDataLength then
		return nil
	end
	local digits = string.match(data, "^inv:(%d+)$")
	if digits == nil or #digits > 15 then
		return nil
	end
	local userId = tonumber(digits)
	if userId == nil or userId <= 0 then
		return nil
	end
	return userId
end

-- Who did the joiner come for? Invite first, then "Join" on a friend's profile.
-- `present` is the set of userIds in this server. A host who is not here (or is the joiner) counts as nobody.
function FriendInvite.findHost(
	joinerUserId: number,
	launchData: any,
	followUserId: number?,
	present: { [number]: boolean }
): number?
	local candidates = { FriendInvite.parseLaunchData(launchData), followUserId }
	for i = 1, 2 do
		local userId = candidates[i]
		if userId and userId > 0 and userId ~= joinerUserId and present[userId] then
			return userId
		end
	end
	return nil
end

export type HostState = {
	queued: boolean, -- pressed PLAY / PLAY AGAIN for the next match
	inMatch: boolean, -- enrolled in the match running now
}

-- Queue the friend when the host is playing. A host sitting in the lobby menu keeps the choice to the friend.
function FriendInvite.shouldQueue(host: HostState): boolean
	return host.queued or host.inMatch
end

-- Feed lines (kept short for phones).
function FriendInvite.hostLine(friendName: string): string
	return `{friendName} joined you!`
end

function FriendInvite.friendLine(hostName: string, matchRunning: boolean): string
	if matchRunning then
		return `You joined {hostName}! Next match soon`
	end
	return `You joined {hostName}!`
end

-- The INVITE button shows when you are not fighting: lobby, countdown, or watching a match you are not in.
function FriendInvite.showButton(phase: string, inMatch: boolean): boolean
	if phase == "Waiting" or phase == "Countdown" or phase == "Resetting" then
		return true
	end
	if phase == "Spawning" or phase == "Active" or phase == "FinalPressure" then
		return not inMatch
	end
	return false -- Finished / Results: the results screen owns the bottom of the screen
end

return FriendInvite
