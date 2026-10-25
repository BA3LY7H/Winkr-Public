local unlocker,
---@class mint
mint = ...

---@class Actor
---@field class string|boolean
---@field spec number|boolean
---@field condition string|boolean
---@field synced table
local Actor = {}
Actor.__index = Actor

local Constants = mint.Constants
local actors = mint.data.actors

function Actor.New(details)
    local instance = setmetatable({}, Actor)

    -- self.spec = details.spec or false
    instance.class = details.class or false
    instance.spec = details.spec or false
    instance.condition = details.condition or false

    instance.synced = {}

    table.insert(actors, instance)

    return instance
end

function Actor:Sync(func, rate)
    rate = rate or 0.05

    local sync = {}
    sync.tick = rate
    sync.func = func
    sync.last_tick = 0
    table.insert(self.synced, sync)
end

function Actor:ShouldRun()
    local _, className = UnitClass("player")
    if self.class and string.lower(className) ~= string.lower(self.class) then return false end
    if self.spec and self.spec ~= GetSpecialization() then return false end
    if self.condition and not self.condition() then return false end

    return true
end

function Actor:Tick()
    for i = 1, #self.synced do
        local obj = self.synced[i]

        if GetTime() - obj.last_tick > obj.tick then
            local success, err = pcall(obj.func)
            if not success then
                mint.console.log("|cFFFF0000[Actor Error]:|r ", err)
            end
            obj.last_tick = GetTime()
        end
    end
end

function Actor:GetUI()
	local Page = mint.Interface.Page

	local id = GetSpecializationInfo(self.spec)

	local icon = "|TInterface\\Icons\\" .. mint.Constants.SpecIconMap[id] .. ":21:21:0:0:64:64:4:60:4:60|t"
	local page_name = icon .. " " .. mint.Constants.SpecNameByID[id]

	local class = string.lower(self.class) or ""

	self.ui = Page:New(page_name, class, Constants.SpecNameByID[id])

	return self.ui
end

return Actor