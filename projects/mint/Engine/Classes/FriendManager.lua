local unlocker,
---@class mint
mint = ...

local Unit = mint.Unit

local tremove = table.remove
local tinsert = table.insert
local tsort = table.sort

---@class FriendManager
---@field frame Frame
local FriendManager = {}
FriendManager.__index = FriendManager

function FriendManager:New()
	local self = setmetatable({}, FriendManager)

	self.units = {}

    self.frame = CreateFrame("Frame")

    self.frame:RegisterEvent("PLAYER_ENTERING_WORLD")
    self.frame:RegisterEvent("GROUP_ROSTER_UPDATE")

    self.frame:SetScript("OnEvent", function(this, event, ...)
        if event == "PLAYER_ENTERING_WORLD" then
            self:Reset()
        elseif event == "GROUP_ROSTER_UPDATE" then
            self:Reset()
        end
    end)

	return self
end

function FriendManager:Update()
	for i = 1, #self.units do
		self.units[i]:Update()
	end

	if #self.units > 1 then
		tsort(self.units, function(a, b)
			local a_range = a.in_range and 1 or 0
            local b_range = b.in_range and 1 or 0

            if a_range == b_range then
				if a.realized_hp == b.realized_hp then
					return a.max_health < b.max_health
				end
                return a.realized_hp < b.realized_hp
            end

            return a_range > b_range
		end)
	end
end

function FriendManager:Populate()
	local group = IsInRaid() and "raid" or "party"
    local size = group == "raid" and GetNumGroupMembers() or GetNumGroupMembers() - 1
    if group == "party" then
		-- local guid = UnitGUID("player")
        local member = Unit:Create("player")
        tinsert(self.units, member)
    end
    for i = 1, size do
        local unit = group..i
        if group == "raid" or not UnitIsUnit(unit, "player") then

            local member = Unit:Create(unit)
            if member then
                tinsert(self.units, member)
            end
        end
    end
end

function FriendManager:GetFriendByGUID(guid)
	for i = 1, #self.units do
		if self.units[i].guid == guid then
			return self.units[i]
		end
	end
end

function FriendManager:Add(unit)
	local guid = UnitGUID(unit)
    if not guid then return end
    for i = 1, #self.units do
        if self.units[i].guid == guid then
            return
        end
    end
    local member = Unit:Create(unit)
    if member then
        tinsert(self.units, member)
    end
end

function FriendManager:Remove(unit)
    local guid = UnitGUID(unit)
    if not guid then return end
    local idx = nil
    for i = 1, #self.units do
        if self.units[i].guid == guid then
            idx = i
            break
        end
    end
    if idx then return tremove(self.units, idx) end
end

function FriendManager:Reset()
	self.units = {}
	self:Populate()
end

function FriendManager:GetTanks()
    local tanks = {}

    for i = 1, #self.units do
        local unit = self.units[i]
        if unit.role == "TANK" then
            tanks[#tanks + 1] = unit
        end
    end

    return tanks
end

function FriendManager:GetFirstTank()
    for i = 1, #self.units do
        local unit = self.units[i]
        if unit.role == "TANK" and unit.in_range and unit.can_assist and not unit.is_dead then
            return unit
        end
    end
end

function FriendManager:GetCountBelow(hp, filter)
    local count = 0
    for i = 1, #self.units do
        local unit = self.units[i]
        if unit.realized_hp <= hp and ((filter and filter(unit)) or (not filter and unit.in_range and not unit.is_dead and unit.can_assist)) then
            count = count + 1
        end
    end
    return count
end

function FriendManager:GetLowest(hp, callback)
    for i = 1, #self.units do
        local unit = self.units[i]
        if (not hp or (hp and unit.realized_hp <= hp)) and not unit.is_dead and unit.in_range and unit.can_assist then
            if callback then
                if callback(unit) then
                    return unit
                end
            else
                return unit
            end
        end
    end
end

-- Return the percent of friends below specified HP
---@param aura Aura
function FriendManager:GetPctBelow(hp, filter)
    local count = 0
    for i = 1, #self.units do
        local unit = self.units[i]
        if unit.realized_hp <= hp and ((filter and filter(unit)) or (not filter and unit.in_range and not unit.is_dead and unit.can_assist)) then
            count = count + 1
        end
    end
    return (count / #self.units) * 100
end

-- Return the percent of living friends with this auras
---@param aura Aura
function FriendManager:GetPctFriendsWithBuff(aura)
    local count = 0

    for i = 1, #self.units do
        local unit = self.units[i]
        if not unit.is_dead and unit.in_range and unit.can_assist then
            if unit:FindBuff(aura, true):Active() then
                count = count + 1
            end
        end
    end

    return (count / #self.units) * 100
end

-- Return the number of living friends with this aura
---@param aura Aura
function FriendManager:GetNumFriendsWithBuff(aura)
    local count = 0

    for i = 1, #self.units do
        local unit = self.units[i]
        if not unit.is_dead and unit.in_range and unit.can_assist then
            if unit:FindBuff(aura, true):Active() then
                count = count + 1
            end
        end
    end

    return count
end

-- Return the number of living friends without this aura
---@param aura Aura
function FriendManager:GetNumFriendsWithoutBuff(aura)
    local count = 0

    for i = 1, #self.units do
        local unit = self.units[i]
        if not unit.is_dead and unit.in_range and unit.can_assist then
            if unit:FindBuff(aura, true):Inactive() then
                count = count + 1
            end
        end
    end

    return count
end

-- Return the lowest friend that can be dispelled by the list of Spells
---@param spells Spell[]
function FriendManager:GetBestDispel(spells)
    for i = 1, #self.units do
        local unit = self.units[i]
		if not unit.is_dead and unit.in_range and unit.can_assist then
			for _, spell in ipairs(spells) do
				if spell and spell:IsKnown() and spell:IsInRange(unit) then
					if unit:HasDispellableAura(spell) then
						return unit, spell
					end
				end
			end
		elseif unit.is_dead then
			-- If we hit a dead unit, there is no reason to scan MORE units.
			return mint.UnitManager:Get("none"), false
		end
    end
end

-- Generic loop function that breaks on true
---@param callback function(unit: Unit): boolean
function FriendManager:Loop(callback)
    for i = 1, #self.units do
        local unit = self.units[i]
        if unit.in_range and unit.can_assist then
            if callback(unit) then
                break
            end
        end
    end
end

-- Get number of friends
function FriendManager:GetCount()
    return #self.units
end

-- Generic loop function that breaks on true
---@param callback function(unit: Unit): boolean
function FriendManager:LoopRaw(callback)
    for i = 1, #self.units do
        local unit = self.units[i]
        if callback(unit) then
            break
        end
    end
end

function FriendManager:PlayerDropdownData()
    local dropdown = {}
    for i = 1, #self.units do
        local unit = self.units[i]
        tinsert(dropdown, { value = unit.guid, text = unit.name })
    end
    return dropdown
end

return FriendManager