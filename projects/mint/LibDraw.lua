local _, LibDraw, fns = ...

---@class LibDraw
---@field version number Library version number.
---@field state {r:number, g:number, b:number, a:number, w:number}? Current drawing state when instantiated.
---@field objects {lines:Frame[], lines_used:Frame[], fontstrings:FontString[], fontstrings_used:FontString[], buttons:Button[], buttons_used:Button[]}? Object pools for draw primitives.
LibDraw = {
    version = 1.2
}
if _G['LibDraw'] and _G['LibDraw'].version and _G['LibDraw'].version > LibDraw.version then
    return
else
    _G['LibDraw'] = LibDraw
end


local GetCameraPosition, CallProtected = fns.GetCameraPosition, fns.CallProtected

local sin, cos, atan, atan2, sqrt, rad, floor = math.sin, math.cos, math.atan, math.atan2, math.sqrt, math.rad, math.floor
local tinsert, tremove, GetDefaultScale, CreateFrame, ipairs = tinsert, tremove, GetDefaultScale, CreateFrame, ipairs

---@return LibDraw instance A new LibDraw instance ready for drawing.
function LibDraw:New()
    local instance = {
        level = "BACKGROUND",
        callbacks = {},
        canvas = nil,
        ---@type {r:number, g:number, b:number, a:number, w:number}
        state = {
            r = 0,
            g = 1,
            b = 1,
            a = 1,
            w = 2,
        },
        ---@type {lines:Frame[], lines_used:Frame[], fontstrings:FontString[], fontstrings_used:FontString[], buttons:Button[], buttons_used:Button[]}
        objects = {
            lines = {},
            lines_used = {},
            fontstrings = {},
            fontstrings_used = {},
            buttons = {},
            buttons_used = {},
        },
    }
    setmetatable(instance, { __index = self })
    instance:InitializeCanvas()
    return instance
end

---@return nil
function LibDraw:InitializeCanvas()
    if not self.canvas then
        local canvas = CreateFrame("frame", WorldFrame)
        canvas:SetPoint("TOPLEFT", WorldFrame, "TOPLEFT")
        canvas:SetPoint("BOTTOMRIGHT", WorldFrame, "BOTTOMRIGHT")
        canvas:SetFrameStrata("BACKGROUND")
        canvas:SetFrameLevel(1)
        canvas:Show()
        self.canvas = canvas
    end
end

local UIParent, WorldToViewport = UIParent, fns.WorldToViewport
local function WorldToScreen(sx, sy, sz)
    local onscreen, x, y = WorldToViewport(sx, sy, sz, false)
    if x == 0 and y == 0 then
        return
    end
    local scale = UIParent:GetScale()
    local width = UIParent:GetWidth() * scale
    local height = UIParent:GetHeight() * scale
    x = x * width
    y = -(height - (y * height))
    return x, y
end

---@param r number Red color value (0-255).
---@param g number Green color value (0-255).
---@param b number Blue color value (0-255).
---@param a? number Alpha color value (0-255).
---@return number old_r Previous red value.
---@return number old_g Previous green value.
---@return number old_b Previous blue value.
---@return number old_a Previous alpha value.
function LibDraw:SetColor(r, g, b, a)
    local state = self.state
    local old_r, old_g, old_b, old_a = state.r, state.g, state.b, state.a
    state.r = r * 0.00390625
    state.g = g * 0.00390625
    state.b = b * 0.00390625
    state.a = a and a * 0.00390625 or 1
    return old_r, old_g, old_b, old_a
end

---@param r number Red color value (0-1).
---@param g number Green color value (0-1).
---@param b number Blue color value (0-1).
---@param a? number Alpha color value (0-1).
---@return number old_r Previous red value.
---@return number old_g Previous green value.
---@return number old_b Previous blue value.
---@return number old_a Previous alpha value.
function LibDraw:SetColorRaw(r, g, b, a)
    local state = self.state
    local old_r, old_g, old_b, old_a = state.r, state.g, state.b, state.a
    state.r = r
    state.g = g
    state.b = b
    state.a = a and a or 1
    return old_r, old_g, old_b, old_a
end

---@param a? number Alpha value (0-100).
---@return number old_a Previous alpha value.
function LibDraw:SetAlpha(a)
    local state = self.state
    local old_a = state.a
    state.a = a and a * 0.01 or 1
    return old_a
end

---@param a? number Alpha value (0-1).
---@return number old_a Previous alpha value.
function LibDraw:SetAlphaRaw(a)
    local state = self.state
    local old_a = state.a
    state.a = a and a or 1
    return old_a
end

---@param w number Line width in pixels.
---@return number old_w Previous line width.
function LibDraw:SetWidth(w)
    local state = self.state
    local old_w = state.w
    state.w = w
    return old_w
end

---@param sx number Start X coordinate on screen.
---@param sy number Start Y coordinate on screen.
---@param ex number End X coordinate on screen.
---@param ey number End Y coordinate on screen.
---@return nil
function LibDraw:Line2D(sx, sy, ex, ey)
    if not sx or not sy or not ex or not ey then return end
    ---@type {lines:Frame[], lines_used:Frame[], fontstrings:FontString[], fontstrings_used:FontString[], buttons:Button[], buttons_used:Button[]} objects
    local objects = self.objects
    ---@type Frame canvas
    local canvas = self.canvas

        local L = tremove(objects.lines)
        if not L then
                L = CreateFrame("frame", canvas)
        L:SetFrameStrata(self.level)
        L:SetFrameLevel(1)
    	L.line = L:CreateLine()
		L.line:SetDrawLayer(self.level)
	end
	tinsert(objects.lines_used, L)

	L:ClearAllPoints()

	if sx > ex and sy > ey or sx < ex and sy < ey  then
		L:SetPoint("TOPRIGHT", canvas, "TOPLEFT", sx, sy)
		L:SetPoint("BOTTOMLEFT", canvas, "TOPLEFT", ex, ey)
		L.line:SetStartPoint('TOPRIGHT')
		L.line:SetEndPoint('BOTTOMLEFT')
	elseif sx < ex and sy > ey then
		L:SetPoint("TOPLEFT", canvas, "TOPLEFT", sx, sy)
		L:SetPoint("BOTTOMRIGHT", canvas, "TOPLEFT", ex, ey)
		L.line:SetStartPoint('TOPLEFT')
		L.line:SetEndPoint('BOTTOMRIGHT')
	elseif sx > ex and sy < ey then
		L:SetPoint("TOPRIGHT", canvas, "TOPLEFT", sx, sy)
		L:SetPoint("BOTTOMLEFT", canvas, "TOPLEFT", ex, ey)
		L.line:SetStartPoint('TOPLEFT')
		L.line:SetEndPoint('BOTTOMRIGHT')
	else
		L:SetPoint("TOPLEFT", canvas, "TOPLEFT", sx, sy)
		L:SetPoint("BOTTOMLEFT", canvas, "TOPLEFT", ex, ey)
		L.line:SetStartPoint('TOPLEFT')
		L.line:SetEndPoint('BOTTOMLEFT')
	end

    local state = self.state
  	L.line:SetThickness(state.w)
	L.line:SetColorTexture(state.r, state.g, state.b, state.a)

	L:Show()
end

---@param x1 number
---@param y1 number
---@param z1 number
---@param x2 number
---@param y2 number
---@param z2 number
---@return nil
function LibDraw:Line(x1, y1, z1, x2, y2, z2)
    local sx, sy = WorldToScreen(x1, y1, z1)
    local ex, ey = WorldToScreen(x2, y2, z2)
    if sx and sy and ex and ey then
        self:Line2D(sx, sy, ex, ey)
    end
end

---@param x1 number
---@param y1 number
---@param z1 number
---@param x2 number
---@param y2 number
---@param z2 number
---@return nil
function LibDraw:Line3D(x1, y1, z1, x2, y2, z2)
    local sx, sy = WorldToScreen(x1, y1, z1)
    local ex, ey = WorldToScreen(x2, y2, z2)
    if sx and sy and ex and ey then
        self:Line2D(sx, sy, ex, ey)
    end
end

---@param config {texture:any, width:number, height:number, left?:number, right?:number, top?:number, bottom?:number, scale?:number, alpha?:number}
---@param x number
---@param y number
---@param z number
---@param alphaA? number
---@return nil
function LibDraw:Texture(config, x, y, z, alphaA)
	local texture, width, height = config.texture, config.width, config.height
	local left, right, top, bottom, scale =  config.left, config.right, config.top, config.bottom, config.scale
	local alpha = config.alpha or alphaA

	if not texture or not width or not height or not x or not y or not z then return end
	if not left or not right or not top or not bottom then
		left = 0
		right = 1
		top = 0
		bottom = 1
	end
	if not scale then
		local cx, cy, cz = GetCameraPosition()
		-- scale = width / LibDraw.Distance(x, y, z, cx, cy, cz)
        -- must do distance by hand
        scale = width / sqrt((x - cx)^2 + (y - cy)^2 + (z - cz)^2)
	end

	local sx, sy = WorldToScreen(x, y, z)
	if not sx or not sy then return end
	local w = width * scale
	local h = height * scale
	sx = sx - w*0.5
	sy = sy + h*0.5
	local ex, ey = sx + w, sy - h

	local T = tremove(LibDraw.textures) or false
	if T == false then
		T = LibDraw.canvas:CreateTexture(nil, "BACKGROUND")
		T:SetDrawLayer(LibDraw.level)
		T:SetTexture(LibDraw.texture)
	end
	tinsert(LibDraw.textures_used, T)
	T:ClearAllPoints()
	T:SetTexCoord(left, right, top, bottom)
	T:SetTexture(texture)
	T:SetWidth(width)
	T:SetHeight(height)
	T:SetPoint("TOPLEFT", LibDraw.canvas, "TOPLEFT", sx, sy)
	T:SetPoint("BOTTOMRIGHT", LibDraw.canvas, "TOPLEFT", ex, ey)
	T:SetVertexColor(1, 1, 1, 1)
	if alpha then T:SetAlpha(alpha) else T:SetAlpha(1) end
	T:Show()

end

---@param text string
---@param font any
---@param x number
---@param y number
---@param z number
---@return nil
function LibDraw:Text(text, font, x, y, z)
    local sx, sy = WorldToScreen(x, y, z)
    if sx and sy then
        ---@type {lines:Frame[], lines_used:Frame[], fontstrings:FontString[], fontstrings_used:FontString[], buttons:Button[], buttons_used:Button[]} objects
        local objects = self.objects
        local state = self.state
        local f = tremove(objects.fontstrings) or self.canvas:CreateFontString(nil, self.level)
        f:SetFontObject(font)
        f:SetText(text)
        f:SetTextColor(state.r, state.g, state.b, state.a)
        f:SetPoint("TOPLEFT", UIParent, "TOPLEFT", sx-(f:GetStringWidth()*0.5), sy)
        f:Show()
        tinsert(objects.fontstrings_used, f)
    end
end

---@param cx number
---@param cy number
---@param cz number
---@param px number
---@param py number
---@param pz number
---@param r? number
---@return number nx
---@return number ny
---@return number nz
local function RotateX(cx, cy, cz, px, py, pz, r)
    if not r then
        return px, py, pz
    end
    local s = sin(r)
    local c = cos(r)
    py, pz = py - cy, pz - cz
    return px, ((py * c - pz * s) + cy), ((py * s + pz * c) + cz)
end
LibDraw.RotateX = RotateX

---@param cx number
---@param cy number
---@param cz number
---@param px number
---@param py number
---@param pz number
---@param r? number
---@return number nx
---@return number ny
---@return number nz
local function RotateY(cx, cy, cz, px, py, pz, r)
    if not r then
        return px, py, pz
    end
    local s = sin(r)
    local c = cos(r)
    px, pz = px - cx, pz - cz
    return ((pz * s + px * c) + cx), py, ((pz * c - px * s) + cz)
end
LibDraw.RotateY = RotateY

---@param cx number
---@param cy number
---@param cz number
---@param px number
---@param py number
---@param pz number
---@param r? number
---@return number nx
---@return number ny
---@return number nz
local function RotateZ(cx, cy, cz, px, py, pz, r)
    if not r then
        return px, py, pz
    end
    local s = sin(r)
    local c = cos(r)
    px, py = px - cx, py - cy
    return ((px * c - py * s) + cx), ((px * s + py * c) + cy), pz
end
LibDraw.RotateZ = RotateZ

---@param vectors number[][] Array of vector line definitions {sx, sy, sz, ex, ey, ez}.
---@param x number
---@param y number
---@param z number
---@param rotation_x? number
---@param rotation_y? number
---@param rotation_z? number
---@return nil
function LibDraw:Array(vectors, x, y, z, rotation_x, rotation_y, rotation_z)
    for _, vector in ipairs(vectors) do
        ---@type number[] vector
        local sx, sy, sz = x + vector[1], y + vector[2], z + vector[3]
        local ex, ey, ez = x + vector[4], y + vector[5], z + vector[6]

        if rotation_x then
            sx, sy, sz = RotateX(x, y, z, sx, sy, sz, rotation_x)
            ex, ey, ez = RotateX(x, y, z, ex, ey, ez, rotation_x)
        end
        if rotation_y then
            sx, sy, sz = RotateY(x, y, z, sx, sy, sz, rotation_y)
            ex, ey, ez = RotateY(x, y, z, ex, ey, ez, rotation_y)
        end
        if rotation_z then
            sx, sy, sz = RotateZ(x, y, z, sx, sy, sz, rotation_z)
            ex, ey, ez = RotateZ(x, y, z, ex, ey, ez, rotation_z)
        end

        self:Line3D(sx, sy, sz, ex, ey, ez)
    end
end

---@type number[][]
local arrow = {
    {-1, 0, 0,   1,    0, 0},
    { 1, 0, 0, 0.5,  0.5, 0},
    { 1, 0, 0, 0.5, -0.5, 0},
}

---@param x number
---@param y number
---@param z number
---@param direction number
---@param multiplier? number
---@return nil
function LibDraw:Arrow(x, y, z, direction, multiplier)
    if multiplier then
        local sx, sy, sz, ex, ey, ez
        for _, vector in ipairs(arrow) do
            ---@type number[] vector
            sx, sy, sz = x + vector[1] * multiplier, y + vector[2], z + vector[3]
            ex, ey, ez = x + vector[4] * multiplier, y + vector[5], z + vector[6]

            sx, sy, sz = RotateZ(x, y, z, sx, sy, sz, direction)
            ex, ey, ez = RotateZ(x, y, z, ex, ey, ez, direction)
            
            self:Line3D(sx, sy, sz, ex, ey, ez)
        end
    else
        self:Array(arrow, x, y, z, nil, nil, direction)
    end
end

local factor = 2 * math.pi
---@param x number
---@param y number
---@param z number
---@param radius number
---@param precision? number
---@return nil
function LibDraw:Outline(x, y, z, radius, precision)
    precision = precision or 120
    local lx, ly, cx, cy = x + radius, y, nil, nil
    local angle_step = factor / precision
    local angle = angle_step
    for i = 1, precision do
        cx = x + radius * cos(angle)
        cy = y + radius * sin(angle)
        self:Line3D(lx, ly, z, cx, cy, z)
        lx, ly = cx, cy
        angle = angle + angle_step
    end
end

---@param x number
---@param y number
---@param z number
---@param radius number
---@param precision? number
---@return nil
function LibDraw:Circle(x, y, z, radius, precision)
    precision = precision or 120
    local lx, ly, cx, cy = x + radius, y, nil, nil
    local angle_step = factor / precision
    local angle = angle_step
    for i = 1, precision do
        cx = x + radius * cos(angle)
        cy = y + radius * sin(angle)
        self:Line3D(lx, ly, z, cx, cy, z)
        lx, ly = cx, cy
        angle = angle + angle_step
    end
end

-- Add the FilledCircle function to LibDraw
---@param x number
---@param y number
---@param z number
---@param radius number
---@return nil
function LibDraw:FilledCircle(x, y, z, radius)
    -- Ensure radius is positive
    radius = math.abs(radius)
    
    -- Convert world coordinates to screen coordinates
    local sx, sy = WorldToScreen(x, y, z)
    if not sx or not sy then return end
    
    -- Get the scale and dimensions of UIParent for accurate drawing
    local scale = UIParent:GetScale()
    local width = UIParent:GetWidth() * scale
    local height = UIParent:GetHeight() * scale
    
    -- Iterate over each y-offset within the circle's radius
    for dy = -radius, radius do
        local current_y = sy + dy
        -- Calculate the horizontal distance (dx) from the center to the edge of the circle at this y
        local dx = math.sqrt(radius * radius - dy * dy)
        -- Calculate the start and end points of the horizontal line
        local start_x = sx - dx
        local end_x = sx + dx
        -- Draw the horizontal line using Line2D
        self:Line2D(start_x, current_y, end_x, current_y)
    end
end


---@param x number
---@param y number
---@param radius number
---@param precision? number
---@return nil
function LibDraw:Circle2D(x, y, radius, precision)
    precision = precision or 120
    local lx, ly, cx, cy = x + radius, y, nil, nil
    local angle_step = factor / precision
    local angle = angle_step
    for i = 1, precision do
        cx = x + radius * cos(angle)
        cy = y + radius * sin(angle)
        self:Line2D(lx, ly, cx, cy)
        lx, ly = cx, cy
        angle = angle + angle_step
    end
end

local Intersection = fns.Intersection
---@param x number
---@param y number
---@param z number
---@param radius number
---@param precision? number
---@return nil
function LibDraw:GroundCircle(x, y, z, radius, precision)
    precision = precision or 120
    local lx, ly, lz, cx, cy = x + radius, y, z, nil, nil
    local upper_z = z + 100
    local lower_z = z - 100
    local intersection, ix, iy, iz = Intersection(lx, ly, upper_z, lx, ly, lower_z, 0x100)
    if intersection then lz = iz end
    local angle_step = factor / precision
    local angle = angle_step
    for i = 1, precision do
        cx = x + radius * cos(angle)
        cy = y + radius * sin(angle)
        intersection, ix, iy, iz = Intersection(cx, cy, upper_z, cx, cy, lower_z, 0x100)
        if intersection then
            self:Line3D(lx, ly, lz, cx, cy, iz)
            lz = iz
        else
            self:Line3D(lx, ly, lz, cx, cy, z)
            lz = z
        end
        lx, ly = cx, cy
        angle = angle + angle_step
    end
end

local to_half_radian = math.pi / 180.0 * 0.5
---@param x number
---@param y number
---@param z number
---@param rotation number
---@param radius number
---@param field_of_view number
---@param precision? number
---@return nil
function LibDraw:Sector(x, y, z, rotation, radius, field_of_view, precision)
    precision = floor((precision or 120) / (360.0 / field_of_view))
    local half_fov_rads = field_of_view * to_half_radian
    local angle, angle_step = rotation - half_fov_rads, half_fov_rads * 2 / precision
    local fx, fy = WorldToScreen(x + radius * cos(angle), y + radius * sin(angle), z)
    angle = angle + angle_step
    local lx, ly, cx, cy = fx, fy, nil, nil
    for i = 1, precision do
        cx, cy = WorldToScreen(x + radius * cos(angle), y + radius * sin(angle), z)
        if lx and ly and cx and cy then
            self:Line2D(lx, ly, cx, cy)
        end
        lx, ly = cx, cy
        angle = angle + angle_step
    end
    local px, py = WorldToScreen(x, y, z)
    if px and py and fx and fy and lx and ly then
        self:Line2D(px, py, fx, fy)
        self:Line2D(px, py, lx, ly)
    end
end

---@param x number
---@param y number
---@param z number
---@param size number
---@param arc number
---@param rotation number
---@return nil
function LibDraw:Arc(x, y, z, size, arc, rotation)
    return self:Sector(x, y, z, rotation, size, arc)
	--[[local lx, ly, nx, ny, fx, fy = false, false, false, false, false, false
	local half_arc = arc * 0.5
	local ss = (arc/half_arc)
	local as, ae = -half_arc, half_arc
	for v = as, ae, ss do
		nx, ny = WorldToScreen( (x+cos(rotation+rad(v))*size), (y+sin(rotation+rad(v))*size), z )
		if lx and ly then
			self:Line2D(lx, ly, nx, ny)
		else
			fx, fy = nx, ny
		end
		lx, ly = nx, ny
	end
	local px, py = WorldToScreen(x, y, z)
	self:Line2D(px, py, lx, ly)
	self:Line2D(px, py, fx, fy)]]
end

---@param x number
---@param y number
---@param z number
---@param text string
---@param func fun(button:Button)
---@return nil
function LibDraw:Button(x, y, z, text, func)
    local cx, cy, cz = GetCameraPosition()
    if cx and cy and cz then
        ---@type {lines:Frame[], lines_used:Frame[], fontstrings:FontString[], fontstrings_used:FontString[], buttons:Button[], buttons_used:Button[]} objects
        local objects = self.objects
        local sx, sy = WorldToScreen(x, y, z)
        local xdiff, ydiff, zdiff = cx - x, cy - y, cz - z
        local distance = sqrt((xdiff * xdiff) + (ydiff * ydiff) + (zdiff * zdiff))
        local scale = 100 / (100 + distance)
        local btn = tremove(objects.buttons)
        if not btn then
            btn = CallProtected(CreateFrame, "Button", nil, canvas, "UIPanelButtonTemplate")
        end
        CallProtected(btn.SetText, btn, text)
        local size = 40 * scale
        local half_size = size / 2
        btn:SetSize(size, size)
        btn:SetPoint("TOPLEFT", UIParent, "TOPLEFT", sx - half_size, sy + half_size)
        CallProtected(btn.SetScript, btn, "OnClick", func)
        btn:Show()
        tinsert(objects.buttons_used, btn)
    end
end

---@return nil
function LibDraw:ClearCanvas()
    ---@type {lines:Frame[], lines_used:Frame[], fontstrings:FontString[], fontstrings_used:FontString[], buttons:Button[], buttons_used:Button[]} objects
    local objects = self.objects
    ---@type Button[] buttons_used
    local buttons_used = objects.buttons_used
    for i = #buttons_used, 1, -1 do
        CallProtected(buttons_used[i].SetScript, buttons_used[i], "OnClick", nil)
        buttons_used[i]:Hide()
        tinsert(objects.buttons, tremove(buttons_used))
    end
    ---@type FontString[] fontstrings_used
    local fontstrings_used = objects.fontstrings_used
    for i = #fontstrings_used, 1, -1 do
        fontstrings_used[i]:Hide()
        tinsert(objects.fontstrings, tremove(fontstrings_used))
    end
    ---@type Frame[] lines_used
    local lines_used = objects.lines_used
    for i = #lines_used, 1, -1 do
        lines_used[i]:Hide()
        tinsert(objects.lines, tremove(lines_used))
    end
end
