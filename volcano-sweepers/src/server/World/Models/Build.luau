--!strict
-- The one Roblox-side piece of the model kit: turns a Kit.Model (plain numbers) into real, anchored
-- Parts inside a Model, standing at `origin`. Uses WorldUtil.part, so every part is Anchored, Massless,
-- cannot be touched, and only the parts a model marks `collide` are solid.
--
--   local hut = Build.into(folder, Registry.spec("TradeHut", { style = "toy" }), CFrame.new(x, 0, z))
--   local sellAt = Build.anchorPoint(spec, "sell", origin)   -- Vector3 for a prompt / sign

local WorldUtil = require(script.Parent.Parent.WorldUtil)
local Kit = require(script.Parent.Kit)

local Build = {}

local function material(name: string): Enum.Material
	local ok, item = pcall(function()
		return (Enum.Material :: any):FromName(name)
	end)
	if ok and item ~= nil then
		return item :: Enum.Material
	end
	return Enum.Material.SmoothPlastic
end

-- `scale` stretches the whole model (positions and sizes) around its origin. Parent is set LAST.
function Build.into(parent: Instance, model: Kit.Model, origin: CFrame, scale: number?): Model
	local k = scale or 1
	local holder = Instance.new("Model")
	holder.Name = model.name
	for _, s in model.parts do
		local cf = origin * CFrame.new(s.x * k, s.y * k, s.z * k) * CFrame.Angles(s.rx, s.ry, s.rz)
		local size = Vector3.new(s.sx * k, s.sy * k, s.sz * k)
		local shape: Enum.PartType? = nil
		if s.kind == "ball" then
			shape = Enum.PartType.Ball
		elseif s.kind == "cyl" then
			-- a Roblox cylinder lies along X: size is (height, diameter, diameter), turned upright
			shape = Enum.PartType.Cylinder
			size = Vector3.new(s.sy * k, s.sx * k, s.sx * k)
			cf = cf * CFrame.Angles(0, 0, math.pi / 2)
		end
		local part = WorldUtil.part(holder, {
			name = s.name,
			size = size,
			cf = cf,
			color = s.color,
			material = material(s.mat),
			shape = shape,
			transparency = s.alpha,
			collide = s.collide,
			shadow = s.shadow,
			wedge = s.kind == "wedge",
		})
		if s.text ~= nil then
			WorldUtil.faceText(part, Enum.NormalId.Front, {
				text = s.text,
				textColor = s.textColor or "#FFFFFF",
			})
		end
	end
	holder.WorldPivot = origin
	holder.Parent = parent
	return holder
end

-- World position of a named anchor of a model placed at `origin`.
function Build.anchorPoint(model: Kit.Model, name: string, origin: CFrame, scale: number?): Vector3?
	local a = model.anchors[name]
	if a == nil then
		return nil
	end
	local k = scale or 1
	return origin:PointToWorldSpace(Vector3.new(a.x * k, a.y * k, a.z * k))
end

return Build
