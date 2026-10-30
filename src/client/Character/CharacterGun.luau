--!strict
-- Moves the Volt Pistol (built by the combat piece, welded to the hips) into the right hand so it
-- follows the arm. Nothing about the gun changes except what it is welded to, and a muzzle flash part.
-- It relies on the combat piece's names: a Model "CombatGun" with parts "Slide" (barrel along +X, up +Y) and "Grip".

local CharacterGun = {}

-- Gun axes in the hand's frame: the barrel (+X) runs down the forearm toward the fingers (-Y), and the
-- gun's top (+Y) points to the hand's -Z, which is up when the arm is raised forward.
local BARREL = Vector3.new(0, -1, 0)
local TOP = Vector3.new(0, 0, -1)
local FLASH_COLOR = Color3.fromRGB(255, 236, 160)

-- Returns the muzzle flash part, or nil if this is not the gun we expect.
function CharacterGun.attach(gun: Model, hand: BasePart): BasePart?
	local slide = gun:FindFirstChild("Slide")
	local grip = gun:FindFirstChild("Grip")
	if slide == nil or grip == nil or not slide:IsA("BasePart") or not grip:IsA("BasePart") then
		return nil
	end
	if gun:GetAttribute("InHand") == true then
		return gun:FindFirstChild("MuzzleFlash") :: BasePart?
	end
	gun:SetAttribute("InHand", true)

	-- Put the grip in the palm: the slide's frame in the hand's frame, shifted so the grip sits at the hand's origin.
	local axes = CFrame.fromMatrix(Vector3.zero, BARREL, TOP)
	local gripInSlide = slide.CFrame:ToObjectSpace(grip.CFrame).Position
	local slideInHand = CFrame.new(-(axes * gripInSlide)) * axes

	local pieces: { BasePart } = {}
	for _, d in gun:GetChildren() do
		if d:IsA("BasePart") then
			table.insert(pieces, d)
		end
	end
	for _, piece in pieces do
		local rel = slide.CFrame:ToObjectSpace(piece.CFrame)
		local old = piece:FindFirstChildOfClass("WeldConstraint")
		if old ~= nil then
			old:Destroy()
		end
		local weld = Instance.new("Weld")
		weld.Part0 = hand
		weld.Part1 = piece
		weld.C0 = slideInHand * rel
		weld.Parent = piece
	end

	local flash = Instance.new("Part")
	flash.Name = "MuzzleFlash"
	flash.Size = Vector3.new(0.9, 0.55, 0.55)
	flash.Color = FLASH_COLOR
	flash.Material = Enum.Material.Neon
	flash.Transparency = 1
	flash.Massless = true
	flash.CanCollide = false
	flash.CanQuery = false
	flash.CanTouch = false
	flash.CastShadow = false
	local weld = Instance.new("Weld")
	weld.Part0 = hand
	weld.Part1 = flash
	weld.C0 = slideInHand * CFrame.new(slide.Size.X / 2 + 0.45, 0, 0)
	weld.Parent = flash
	flash.Parent = gun
	return flash
end

return CharacterGun
