--!strict
-- Puts a Pose on an R15 body. Finds the joints once, then each frame turns the pose numbers into
-- Motor6D.Transform. Cosmetic only: nothing here is read by the server or by hit checks.
--
-- Pose angles are in the preview's convention (facing +Z); Roblox characters face -Z, so the swing
-- and side-lean angles flip sign here, and nowhere else.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Pose = require(Shared.Character.Pose)

local CharacterRig = {}

export type Joints = {
	root: Motor6D,
	waist: Motor6D,
	neck: Motor6D,
	rShoulder: Motor6D,
	rElbow: Motor6D,
	lShoulder: Motor6D,
	lElbow: Motor6D,
	rHip: Motor6D,
	rKnee: Motor6D,
	lHip: Motor6D,
	lKnee: Motor6D,
	rootHeight: number, -- studs from the ground to the hips pivot, used to scale hips drops
}

-- Hips height the poses were drawn for (studs).
local DRAWN_HIP_HEIGHT = 2.15

local function motor(model: Model, partName: string, jointName: string): Motor6D?
	local part = model:FindFirstChild(partName)
	local joint = if part ~= nil then part:FindFirstChild(jointName) else nil
	if joint ~= nil and joint:IsA("Motor6D") then
		return joint
	end
	return nil
end

-- Nil when the model is not a complete R15 body (yet).
function CharacterRig.find(model: Model): Joints?
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local rootPart = model:FindFirstChild("HumanoidRootPart")
	if humanoid == nil or rootPart == nil or not rootPart:IsA("BasePart") then
		return nil
	end
	local root = motor(model, "LowerTorso", "Root")
	local waist = motor(model, "UpperTorso", "Waist")
	local neck = motor(model, "Head", "Neck")
	local rShoulder = motor(model, "RightUpperArm", "RightShoulder")
	local rElbow = motor(model, "RightLowerArm", "RightElbow")
	local lShoulder = motor(model, "LeftUpperArm", "LeftShoulder")
	local lElbow = motor(model, "LeftLowerArm", "LeftElbow")
	local rHip = motor(model, "RightUpperLeg", "RightHip")
	local rKnee = motor(model, "RightLowerLeg", "RightKnee")
	local lHip = motor(model, "LeftUpperLeg", "LeftHip")
	local lKnee = motor(model, "LeftLowerLeg", "LeftKnee")
	if
		root == nil
		or waist == nil
		or neck == nil
		or rShoulder == nil
		or rElbow == nil
		or lShoulder == nil
		or lElbow == nil
		or rHip == nil
		or rKnee == nil
		or lHip == nil
		or lKnee == nil
	then
		return nil
	end
	return {
		root = root,
		waist = waist,
		neck = neck,
		rShoulder = rShoulder,
		rElbow = rElbow,
		lShoulder = lShoulder,
		lElbow = lElbow,
		rHip = rHip,
		rKnee = rKnee,
		lHip = lHip,
		lKnee = lKnee,
		rootHeight = humanoid.HipHeight + rootPart.Size.Y / 2,
	}
end

function CharacterRig.apply(j: Joints, p: Pose.Pose)
	local drop = j.rootHeight / DRAWN_HIP_HEIGHT
	j.root.Transform = CFrame.new(0, p.hy * drop, 0) * CFrame.Angles(-p.hrx, 0, -p.hrz)
	j.waist.Transform = CFrame.Angles(-p.tx, p.ty, 0)
	j.neck.Transform = CFrame.Angles(-p.hdx, p.hdy, 0)
	j.rShoulder.Transform = CFrame.Angles(-p.aRx, 0, -p.aRz)
	j.rElbow.Transform = CFrame.Angles(-p.eRx, 0, 0)
	j.lShoulder.Transform = CFrame.Angles(-p.aLx, 0, -p.aLz)
	j.lElbow.Transform = CFrame.Angles(-p.eLx, 0, 0)
	j.rHip.Transform = CFrame.Angles(-p.lRx, 0, -p.lRz)
	j.rKnee.Transform = CFrame.Angles(-p.sRx, 0, 0)
	j.lHip.Transform = CFrame.Angles(-p.lLx, 0, -p.lLz)
	j.lKnee.Transform = CFrame.Angles(-p.sLx, 0, 0)
end

return CharacterRig
