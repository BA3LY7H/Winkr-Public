local unlocker,
---@class mint
mint = ...

---@class Utility
local Utility = mint.Utility
local FriendManager = mint.FriendManager

local arrow = {
    {-1, 0, 0,   1,    0, 0},
    { 1, 0, 0, 0.5,  0.5, 0},
    { 1, 0, 0, 0.5, -0.5, 0},
}

local arrow_colors = {
	{ text = '|cff00d8ff Cyan |r', value = 'cyan' }, -- 00d8ff
	{ text = '|cffffd200 Gold |r', value = 'gold' }, -- ffd200
	{ text = '|cff00ff12 Lime |r', value = 'lime' }, -- 00ff12
	{ text = '|cffffffff White |r', value = 'white' }, -- ffffff
	{ text = '|cffff2114 Red |r', value = 'red' }, -- ff2114
	{ text = '|cffff8000 Orange |r', value = 'orange' }, -- ff8000
	{ text = '|cfffff809 Yellow |r', value = 'yellow' }, -- fff809
	{ text = '|cffff80ff Pink |r', value = 'pink' }, -- ff80ff
	{ text = '|cffc845fa Purple |r', value = 'purple' }, -- c845fa
};

-- RGB 0-255
local colors = {
	["gold"] = { 1.000, 0.824, 0.000 },
	["cyan"] = { 0.000, 0.847, 1.000 },
	["lime"] = { 0.000, 1.000, 0.071 },
	["white"] = { 1.000, 1.000, 1.000 },
	["red"] = { 1.000, 0.129, 0.078 },
	["orange"] = { 1.000, 0.502, 0.000 },
	["yellow"] = { 1.000, 0.973, 0.035 },
	["pink"] = { 1.000, 0.502, 1.000 },
	["purple"] = { 0.784, 0.271, 0.980 },
}

local function Rotate(cx, cy, cz, px, py, pz, r)
    if not r then
        return px, py, pz
    end
    local s = math.sin(r)
    local c = math.cos(r)
    px, py = px - cx, py - cy
    return ((px * c - py * s) + cx), ((px * s + py * c) + cy), pz
end

local function array(draw, vectors, x, y, z, rotation)
    for _, vector in ipairs(vectors) do
		local sx, sy, sz = x + vector[1], y + vector[2], z + vector[3]
		local ex, ey, ez = x + vector[4], y + vector[5], z + vector[6]

		if rotation then
			sx, sy, sz = Rotate(x, y, z, sx, sy, sz, rotation)
			ex, ey, ez = Rotate(x, y, z, ex, ey, ez, rotation)
		end

		draw:Line(sx, sy, sz, ex, ey, ez, 1)
	end
end

-- Draw an arrow beneath the player
function Utility:DrawFacingArrow(draw, unit)
    local pos = unit:GetPosition()
    local facing = unit:GetFacing()

    if not pos or not facing then return end

    if pos:IsValid() then
        local color_config = mint.Settings.profile.general.indicator_color
        local color = colors[color_config] or "cyan"

        local opacity = mint.Settings.profile.general.indicator_opacity
        local opacityValue = (opacity / 100) * 255

        if color then
            draw:SetColor(color[1] * 255, color[2] * 255, color[3] * 255, opacityValue)
        else
            draw:SetColor(1, 1, 1, opacityValue)
        end

        draw:SetWidth(2)
        array(draw, arrow, pos.x, pos.y, pos.z, facing)
        draw:SetWidth(1)
    end
end

-- Draw a circle beneath selected players
function Utility:DrawCircleByGUID(draw, guid)
    local unit = FriendManager:GetFriendByGUID(guid) or mint.UnitManager:Get("none")
    if not unit:GetExists() then return false end
    local pos = unit:GetPosition()

    if not pos then return end

    if pos:IsValid() then
        local color_config = mint.Settings.profile.general.indicator_color
        local color = colors[color_config] or "cyan"

        local opacity = mint.Settings.profile.general.indicator_opacity
        local opacityValue = (opacity / 100) * 255

        if color then
            draw:SetColor(color[1] * 255, color[2] * 255, color[3] * 255, opacityValue)
        else
            draw:SetColor(1, 1, 1, opacityValue)
        end

        draw:SetWidth(2)
        draw:Circle(pos.x, pos.y, pos.z, 0.8)
    end
end

-- Draw the location of dead allies
-- function Utility:DrawDeadAllies(draw)

-- end

-- -- Draw the location of lootable enemies
-- function Utility:DrawLootableEnemies(draw)

-- end

-- -- Draw quest objectives
-- function Utility:DrawQuestObjectives(draw)

-- end

-- -- Draw player facing as an arrow
-- function Utility:DrawPlayerFacing(draw)

-- end

-- -- Draw target facing as an arrow
-- function Utility:DrawTargetFacing(draw)

-- end

