local unlocker,
---@class mint
mint = ...

local sin, cos, atan2, sqrt, rad, floor, min, max = math.sin, math.cos, math.atan2, math.sqrt, math.rad, math.floor, math.min, math.max
local tinsert, tremove, ipairs = tinsert, tremove, ipairs
local PI2 = 2 * math.pi
local TO_HALF_RAD = math.pi / 180.0 * 0.5

---@class Draw
---@field canvas Frame
---@field state {r:number, g:number, b:number, a:number, w:number}
---@field lines table
---@field lines_used table
---@field strings table
---@field strings_used table
---@field textures table
---@field textures_used table
---@field callbacks table
local Draw = {}
Draw.__index = Draw

---@return Draw
function Draw:New()
	local instance = setmetatable({
		state = { r = 0, g = 1, b = 1, a = 1, w = 2 },
		lines = {},
		lines_used = {},
		strings = {},
		strings_used = {},
		textures = {},
		textures_used = {},
		callbacks = {},
		screenW = 1,
		screenH = 1,
	}, self)
	instance:_InitCanvas()
	return instance
end

function Draw:_InitCanvas()
	local ref = WorldFrame
	local canvas = CreateFrame("Frame", nil, ref)
	canvas:SetAllPoints(ref)
	canvas:Show()
	self.canvas = canvas
	self.screenW, self.screenH = ref:GetSize()
end

-- Convert normalized [0,1] coords from winkr_WorldToScreen to pixel offsets
-- relative to TOPLEFT of canvas. WoW Y-axis goes up, so Y is negated.
function Draw:WorldToScreen(wx, wy, wz)
	local sx, sy, visible = winkr_WorldToScreen(wx, wy, wz)
	if not visible or (sx == 0 and sy == 0) then
		return false, false
	end
	return sx * self.screenW, -(sy * self.screenH)
end

-- Register a draw callback (receives self as the draw object)
---@param callback function
function Draw:Sync(callback)
	if callback and type(callback) == "function" then
		tinsert(self.callbacks, callback)
	end
end

function Draw:Enable()
	self.canvas:SetScript("OnUpdate", function()
		self:Update()
	end)
end

function Draw:Disable()
	self.canvas:SetScript("OnUpdate", nil)
	self:ClearCanvas()
end

function Draw:Update()
	-- Refresh screen dimensions in case of resize
	local ref = self.canvas:GetParent()
	self.screenW, self.screenH = ref:GetSize()
	self:ClearCanvas()
	for _, cb in ipairs(self.callbacks) do
		cb(self)
	end
end

-------------------------------
--- Object Pool & Clear
-------------------------------

function Draw:ClearCanvas()
	local lines_used = self.lines_used
	for i = #lines_used, 1, -1 do
		lines_used[i]:Hide()
		tinsert(self.lines, tremove(lines_used, i))
	end

	local strings_used = self.strings_used
	for i = #strings_used, 1, -1 do
		strings_used[i]:Hide()
		tinsert(self.strings, tremove(strings_used, i))
	end

	local textures_used = self.textures_used
	for i = #textures_used, 1, -1 do
		textures_used[i]:Hide()
		tinsert(self.textures, tremove(textures_used, i))
	end
end

-------------------------------
--- State
-------------------------------

-- Set color (0-255 range). If r is a table {r,g,b[,a]}, g param becomes alpha.
---@param r number|table
---@param g number|nil
---@param b number|nil
---@param a number|nil
function Draw:SetColor(r, g, b, a)
	local state = self.state
	if type(r) == "table" then
		local t = r
		local alpha = g
		state.r = (t[1] or 0) / 255
		state.g = (t[2] or 0) / 255
		state.b = (t[3] or 0) / 255
		state.a = alpha and (alpha / 255) or (t[4] and (t[4] / 255) or 1)
	else
		state.r = (r or 0) / 255
		state.g = (g or 0) / 255
		state.b = (b or 0) / 255
		state.a = a and (a / 255) or 1
	end
end

---@param w number Line width in pixels
function Draw:SetWidth(w)
	self.state.w = w
end

-------------------------------
--- Distance
-------------------------------

function Draw:Distance(ax, ay, az, bx, by, bz)
	local dx, dy, dz = ax - bx, ay - by, az - bz
	return sqrt(dx * dx + dy * dy + dz * dz)
end

-------------------------------
--- 2D Line (screen space)
-------------------------------

---@param sx number Start screen X
---@param sy number Start screen Y
---@param ex number End screen X
---@param ey number End screen Y
function Draw:Line2D(sx, sy, ex, ey)
	if not sx or not sy or not ex or not ey then return end

	sx, sy, ex, ey = floor(sx), floor(sy), floor(ex), floor(ey)

	local line = tremove(self.lines)
	if not line then
		line = self.canvas:CreateLine()
	end

	local state = self.state
	line:SetColorTexture(state.r, state.g, state.b, min(1, max(0, state.a)))
	line:SetThickness(state.w)
	line:SetStartPoint("TOPLEFT", self.canvas, sx, sy)
	line:SetEndPoint("TOPLEFT", self.canvas, ex, ey)
	line:Show()
	tinsert(self.lines_used, line)
end

-------------------------------
--- 3D Line (world space)
-------------------------------

-- Draw a line between two world positions. maxD controls recursive subdivision
-- for long lines that cross behind the camera (default 50).
---@param x1 number
---@param y1 number
---@param z1 number
---@param x2 number
---@param y2 number
---@param z2 number
---@param maxD number|nil
function Draw:Line(x1, y1, z1, x2, y2, z2, maxD)
	maxD = maxD or 50
	local dist = self:Distance(x1, y1, z1, x2, y2, z2)
	if dist > maxD then
		local mx, my, mz = (x1 + x2) * 0.5, (y1 + y2) * 0.5, (z1 + z2) * 0.5
		self:Line(x1, y1, z1, mx, my, mz, maxD)
		self:Line(mx, my, mz, x2, y2, z2, maxD)
		return
	end
	local sx, sy = self:WorldToScreen(x1, y1, z1)
	local ex, ey = self:WorldToScreen(x2, y2, z2)
	if sx and sy and ex and ey then
		self:Line2D(sx, sy, ex, ey)
	end
end

-------------------------------
--- Circle
-------------------------------

---@param x number World X center
---@param y number World Y center
---@param z number World Z center
---@param radius number
---@param steps number|nil Number of segments (default 40)
function Draw:Circle(x, y, z, radius, steps)
	steps = steps or 40
	local angle_step = PI2 / steps
	local lx, ly = x + radius, y
	for i = 1, steps do
		local angle = i * angle_step
		local cx, cy = x + radius * cos(angle), y + radius * sin(angle)
		self:Line(lx, ly, z, cx, cy, z)
		lx, ly = cx, cy
	end
end

-------------------------------
--- Text
-------------------------------

---@param text string
---@param font string|table Font object or font name
---@param x number World X
---@param y number World Y
---@param z number World Z
function Draw:Text(text, font, x, y, z)
	local sx, sy = self:WorldToScreen(x, y, z)
	if not sx or not sy then return end

	local f = tremove(self.strings) or self.canvas:CreateFontString(nil, "BACKGROUND")
	f:SetFontObject(font)
	f:SetText(text)
	local state = self.state
	f:SetTextColor(state.r, state.g, state.b, state.a)
	f:ClearAllPoints()
	f:SetPoint("TOPLEFT", self.canvas, "TOPLEFT", sx - (f:GetStringWidth() * 0.5), sy)
	f:Show()
	tinsert(self.strings_used, f)
end

-------------------------------
--- Arc / Sector
-------------------------------

---@param x number World X center
---@param y number World Y center
---@param z number World Z center
---@param size number Radius of the arc
---@param arc number Field of view in degrees
---@param rotation number Rotation in radians
function Draw:Arc(x, y, z, size, arc, rotation)
	self:Sector(x, y, z, rotation, size, arc)
end

---@param x number
---@param y number
---@param z number
---@param rotation number Facing in radians
---@param radius number
---@param fov number Field of view in degrees
---@param precision number|nil
function Draw:Sector(x, y, z, rotation, radius, fov, precision)
	precision = floor((precision or 120) / (360.0 / fov))
	if precision < 1 then precision = 1 end
	local half_fov = fov * TO_HALF_RAD
	local angle = rotation - half_fov
	local angle_step = half_fov * 2 / precision

	local fx, fy = self:WorldToScreen(x + radius * cos(angle), y + radius * sin(angle), z)
	angle = angle + angle_step
	local lx, ly = fx, fy
	for i = 1, precision do
		local cx, cy = self:WorldToScreen(x + radius * cos(angle), y + radius * sin(angle), z)
		if lx and ly and cx and cy then
			self:Line2D(lx, ly, cx, cy)
		end
		lx, ly = cx, cy
		angle = angle + angle_step
	end
	local px, py = self:WorldToScreen(x, y, z)
	if px and py and fx and fy and lx and ly then
		self:Line2D(px, py, fx, fy)
		self:Line2D(px, py, lx, ly)
	end
end

-------------------------------
--- Rotation helpers
-------------------------------

local function RotateZ(cx, cy, cz, px, py, pz, r)
	if not r then return px, py, pz end
	local s, c = sin(r), cos(r)
	px, py = px - cx, py - cy
	return (px * c - py * s) + cx, (px * s + py * c) + cy, pz
end

-------------------------------
--- Array (vector shape drawing)
-------------------------------

---@param vectors table Array of {sx,sy,sz,ex,ey,ez} offset vectors
---@param x number World X origin
---@param y number World Y origin
---@param z number World Z origin
---@param rotation number|nil Rotation around Z axis (radians)
function Draw:Array(vectors, x, y, z, rotation)
	for _, v in ipairs(vectors) do
		local sx, sy, sz = x + v[1], y + v[2], z + v[3]
		local ex, ey, ez = x + v[4], y + v[5], z + v[6]
		if rotation then
			sx, sy, sz = RotateZ(x, y, z, sx, sy, sz, rotation)
			ex, ey, ez = RotateZ(x, y, z, ex, ey, ez, rotation)
		end
		self:Line(sx, sy, sz, ex, ey, ez)
	end
end

-------------------------------
--- Texture
-------------------------------

---@param config table {texture, width, height, left?, right?, top?, bottom?, scale?, alpha?}
---@param x number World X
---@param y number World Y
---@param z number World Z
---@param alphaOverride number|nil
function Draw:Texture(config, x, y, z, alphaOverride)
	local texture, width, height = config.texture, config.width, config.height
	if not texture or not width or not height or not x or not y or not z then return end

	local left = config.left or 0
	local right = config.right or 1
	local top = config.top or 0
	local bottom = config.bottom or 1
	local alpha = config.alpha or alphaOverride
	local scale = config.scale

	if not scale then
		local px, py, pz = UnitPosition("player")
		if px then
			scale = width / self:Distance(x, y, z, px, py, pz)
		else
			scale = 1
		end
	end

	local sx, sy = self:WorldToScreen(x, y, z)
	if not sx or not sy then return end

	local w = width * scale
	local h = height * scale
	sx = sx - w * 0.5
	sy = sy + h * 0.5
	local ex, ey = sx + w, sy - h

	local T = tremove(self.textures) or self.canvas:CreateTexture(nil, "BACKGROUND")
	T:ClearAllPoints()
	T:SetTexCoord(left, right, top, bottom)
	T:SetTexture(texture)
	T:SetWidth(width)
	T:SetHeight(height)
	T:SetPoint("TOPLEFT", self.canvas, "TOPLEFT", sx, sy)
	T:SetPoint("BOTTOMRIGHT", self.canvas, "TOPLEFT", ex, ey)
	T:SetVertexColor(1, 1, 1, 1)
	T:SetAlpha(alpha or 1)
	T:Show()
	tinsert(self.textures_used, T)
end

return Draw