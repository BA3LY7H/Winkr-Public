local unlocker,
---@class mint
mint = ...

-- Create a Vector3 class
---@class Vector3
local Vector3 = { }
Vector3.__index = Vector3

---@return string
function Vector3:__tostring()
    return "Vector3(" .. self.x .. ", " .. self.y .. ", " .. self.z .. ")"
end

---@param other Vector3
---@return Vector3
function Vector3:__add(other)
    return Vector3:New(self.x + other.x, self.y + other.y, self.z + other.z)
end

---@param other Vector3
---@return Vector3
function Vector3:__sub(other)
    if type(other) == "number" then
        return Vector3:New(self.x - other, self.y - other, self.z - other)
    end
    return Vector3:New(self.x - other.x, self.y - other.y, self.z - other.z)
end

---@param other number
---@return Vector3
function Vector3:__mul(other)
    return Vector3:New(self.x * other, self.y * other, self.z * other)
end

---@param other number
---@return Vector3
function Vector3:__div(other)
    return Vector3:New(self.x / other, self.y / other, self.z / other)
end

---@param other Vector3
---@return boolean
function Vector3:__eq(other)
    return self.x == other.x and self.y == other.y and self.z == other.z
end

---@param other Vector3
---@return boolean
function Vector3:__lt(other)
    return self.x < other.x and self.y < other.y and self.z < other.z
end

---@param other Vector3
---@return boolean
function Vector3:__le(other)
    return self.x <= other.x and self.y <= other.y and self.z <= other.z
end

---@return Vector3
function Vector3:__unm()
    return Vector3:New(-self.x, -self.y, -self.z)
end

---@return number
function Vector3:__len()
    return math.sqrt(self.x * self.x + self.y * self.y + self.z * self.z)
end

function Vector3:__index(k)
    if Vector3[k] then
        return Vector3[k]
    end

    ---@class Vector3
    ---@field length number
    if k == "length" then
        return math.sqrt(self.x * self.x + self.y * self.y + self.z * self.z)
    end

    ---@class Vector3
    ---@field normalized Vector3
    if k == "normalized" then
        local length = math.sqrt(self.x * self.x + self.y * self.y + self.z * self.z)
        if length < 1e-10 then return Vector3:New(0, 0, 0) end
        return Vector3:New(self.x / length, self.y / length, self.z / length)
    end

    ---@class Vector3
    ---@field magnitude number
    if k == "magnitude" then
        return math.sqrt(self.x * self.x + self.y * self.y + self.z * self.z)
    end

    ---@class Vector3
    ---@field sqrMagnitude number
    if k == "sqrMagnitude" then
        return self.x * self.x + self.y * self.y + self.z * self.z
    end

    ---@class Vector3
    ---@field zero Vector3
    if k == "zero" then
        return Vector3:New(0, 0, 0)
    end

    ---@class Vector3
    ---@field one Vector3
    if k == "one" then
        return Vector3:New(1, 1, 1)
    end

    ---@class Vector3
    ---@field up Vector3
    if k == "up" then
        return Vector3:New(0, 1, 0)
    end

    ---@class Vector3
    ---@field down Vector3
    if k == "down" then
        return Vector3:New(0, -1, 0)
    end

    ---@class Vector3
    ---@field left Vector3
    if k == "left" then
        return Vector3:New(-1, 0, 0)
    end

    ---@class Vector3
    ---@field right Vector3
    if k == "right" then
        return Vector3:New(1, 0, 0)
    end

    ---@class Vector3
    ---@field forward Vector3
    if k == "forward" then
        return Vector3:New(0, 0, 1)
    end

    ---@class Vector3
    ---@field back Vector3
    if k == "back" then
        return Vector3:New(0, 0, -1)
    end

    ---@class Vector3
    ---@field positiveInfinity Vector3
    if k == "positiveInfinity" then
        return Vector3:New(math.huge, math.huge, math.huge)
    end

    ---@class Vector3
    ---@field negativeInfinity Vector3
    if k == "negativeInfinity" then
        return Vector3:New(-math.huge, -math.huge, -math.huge)
    end

    ---@class Vector3
    ---@field nan Vector3
    if k == "nan" then
        return Vector3:New(0 / 0, 0 / 0, 0 / 0)
    end

    ---@class Vector3
    ---@field epsilon number
    if k == "epsilon" then
        return 1.401298E-45
    end

    ---@class Vector3
    ---@field maxValue number
    if k == "maxValue" then
        return 3.402823E+38
    end

    ---@class Vector3
    ---@field minValue number
    if k == "minValue" then
        return -3.402823E+38
    end

    ---@class Vector3
    ---@field x number
    if k == "x" then
        return self[1]
    end

    ---@class Vector3
    ---@field y number
    if k == "y" then
        return self[2]
    end

    ---@class Vector3
    ---@field z number
    if k == "z" then
        return self[3]
    end

    return nil
end

function Vector3:__newindex(k, v)
    if k == "x" then
        self[1] = v
    elseif k == "y" then
        self[2] = v
    elseif k == "z" then
        self[3] = v
    else
        rawset(self, k, v)
    end
end

---@param x number
---@param y number
---@param z number
---@return Vector3
function Vector3:New(x, y, z)
    if x == false or not x then
        return Vector3:New(0, 0, 0)
    end

    local self = setmetatable({ x, y, z }, Vector3)
    return self
end

---@param rhs Vector3
---@return number
function Vector3:Dot(rhs)
    return self.x * rhs.x + self.y * rhs.y + self.z * rhs.z
end

---@param rhs Vector3
---@return Vector3
function Vector3:Cross(rhs)
    return Vector3:New(self.y * rhs.z - self.z * rhs.y, self.z * rhs.x - self.x * rhs.z, self.x * rhs.y - self.y * rhs.x)
end

---@param b Vector3
---@return number
function Vector3:Distance(b)
	return math.sqrt((self.x - b.x) ^ 2 + (self.y - b.y) ^ 2 + (self.z - b.z) ^ 2)
end

---@param b Vector3
---@return number
function Vector3:DistanceSquared(b)
    local dx = self.x - b.x
    local dy = self.y - b.y
    local dz = self.z - b.z
    return dx * dx + dy * dy + dz * dz
end

---@param to Vector3
---@return number
function Vector3:Angle(to)
    local selfLen = math.sqrt(self.x * self.x + self.y * self.y + self.z * self.z)
    local toLen = math.sqrt(to.x * to.x + to.y * to.y + to.z * to.z)
    local denom = selfLen * toLen
    if denom < 1e-10 then return 0 end
    local cosAngle = self:Dot(to) / denom
    -- Clamp to [-1,1] to avoid NaN from floating point error
    cosAngle = math.max(-1, math.min(1, cosAngle))
    return math.acos(cosAngle)
end

---@param to Vector3
---@return number
function Vector3:Angle2D(to)
    local delta = to - self
    return math.atan2(delta.y, delta.x)
end

---@return boolean
function Vector3:IsValid()
	if self.x and self.y and self.z then
		if self ~= Vector3.zero then
			return true
		end
	end

	return false
end

---@param maxLength number
---@return Vector3
function Vector3:ClampMagnitude(maxLength)
    if self:Dot(self) > maxLength * maxLength then
        return self.normalized * maxLength
    end

    return self
end

-- Implement a clamp function
---@param x number
---@param min number
---@param max number
---@return number
local function clamp(x, min, max)
    return x < min and min or (x > max and max or x)
end

---@param b Vector3
---@param t number
---@return Vector3
function Vector3:Lerp(b, t)
    t = clamp(t, 0, 1)
    return Vector3:New(self.x + (b.x - self.x) * t, self.y + (b.y - self.y) * t, self.z + (b.z - self.z) * t)
end

---@param target Vector3
---@param maxDistanceDelta number
---@return Vector3
function Vector3:MoveTowards(target, maxDistanceDelta)
    local toVector = target - self
    local distance = toVector.magnitude
    if distance <= maxDistanceDelta or distance == 0 then
        return target
    end

    return self + toVector / distance * maxDistanceDelta
end

---@param b Vector3
---@return Vector3
function Vector3:Scale(b)
    return Vector3:New(self.x * b.x, self.y * b.y, self.z * b.z)
end

---@param onNormal Vector3
---@return Vector3
function Vector3:Project(onNormal)
    local num = onNormal:Dot(onNormal)
    if num < 1.401298E-45 then
        return Vector3:New(0, 0, 0)
    end

    return onNormal * self:Dot(onNormal) / num
end

---@param planeNormal Vector3
---@return Vector3
function Vector3:ProjectOnPlane(planeNormal)
    return self - self:Project(planeNormal)
end

---@param inNormal Vector3
---@return Vector3
function Vector3:Reflect(inNormal)
    return -2 * inNormal:Dot(self) * inNormal + self
end

---@return Vector3
function Vector3:Normalize()
    local num = self:Dot(self)
    if num > 1E-05 then
        return self / math.sqrt(num)
    end

    return Vector3:New(0, 0, 0)
end

---@param to Vector3
---@return number
function Vector3:Pitch(to)
	local delta = to - self
    local horizontalDistance = math.sqrt(delta.x * delta.x + delta.y * delta.y)

    -- Check if the target is nearly directly above or below
    if horizontalDistance < 2 then
        return math.pi / 2 * (delta.z >= 0 and 1 or -1)
    else
        return math.atan2(delta.z, horizontalDistance)
    end
end

local CollisionFlags = bit.bor(0x1, 0x2, 0x10, 0x20, 0x100, 0x100000)
function Vector3:GroundZ()
	local tx, ty, tz = mint.TraceLine(self.x, self.y, self.z+1, self.x, self.y, self.z - 25, CollisionFlags)
	if tx == 0 then
        return self
    end

	return mint.Vector3:New(tx, ty, tz)
end

---@return boolean
function Vector3:IsNearGround()
	local tx, ty, tz = mint.TraceLine(self.x, self.y, self.z, self.x, self.y, -1000, bit.bor(0x1, 0x2, 0x10, 0x20, 0x100, 0x100000))
	if tx == 0 then
		tz = self.z
	end

	if math.abs(self.z - tz) < 5 then
		return true
	else
		return false
	end
end

---@return boolean
function Vector3:IsAbove(other, range)
	return self.z > other.z + range
end

function Vector3:IsVisibleTo(other)
	return mint.TraceLine(self.x, self.y, self.z+0.5, other.x, other.y, other.z+0.5, bit.bor(0x1, 0x2, 0x10, 0x20, 0x100, 0x100000)) == 0
end

---@param vectors table
---@return Vector3
function Vector3:GetCentroid(vectors)
	local total = Vector3:New(0, 0, 0)
	local count = #vectors

	if count == 0 then
		return total
	end

	for _, vector in ipairs(vectors) do
		total = total + vector
	end

	local centroid = total / count
	return centroid
end

---@return self Vector3
function Vector3:Humanize()
	self.x = self.x + (math.random(-199, 199) / 100)
	self.y = self.y + (math.random(-199, 199) / 100)

	return self
end

return Vector3
