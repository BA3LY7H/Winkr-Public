local unlocker,
---@class mint
mint = ...

--! Mint Locals !--
local Spell = mint.Spell.New

---@class TotemManager
---@field totems table
---@field events EventManager
---@field spells table
---@field totem_spells table
---@field GetTotemInfo fun(self:TotemManager, slotIndex: number): table|nil
---@field IsActive fun(self:TotemManager, spell_id: number): boolean
---@field TimeRemaining fun(self:TotemManager, spell_id: number): number
local TotemManager = {}
TotemManager.__index = TotemManager


-- Constructor
---@return TotemManager
function TotemManager:New()
	local self = setmetatable({}, TotemManager)

	self.totems = {}
	self.events = mint.EventManager.New()

	-- We use Icon IDs rather than spell IDs, as GetTotemInfo uses icon IDs.
	self.totem_spells = {
        -- Shaman
		[136013] 		= Spell(192058), -- Capacitor Totem
		[136102] 		= Spell(2484), -- Earthbind Totem
		[136098] 		= Spell(198838), -- Earthen Wall Totem
		[135127] 		= Spell(5394), -- Healing Stream Totem
		[538569] 		= Spell(108280), -- Healing Tide Totem
		[971079] 		= Spell(192222), -- Liquid Magma Totem
		[4667424] 		= Spell(16191), -- Mana Tide Totem
		[136070] 		= Spell(383013), -- Poison Cleansing Totem
		[237586] 		= Spell(98008), -- Spirit Link Totem
		[538572] 		= Spell(108270), -- Stone Bulwark Totem
		[5927655] 		= Spell(444995), -- Surging Totem
		[136108] 		= Spell(8143), -- Tremor Totem
		[538576] 		= Spell(192077), -- Wind Rush Totem

        -- Monk
		[574571] 		= Spell(322118), --Yulon
		[877514] 		= Spell(325197), -- ChiJi
		[620831] 		= Spell(115313), -- Jade Serpent Statue
		[620832] 		= Spell(123904), -- Xuen

        -- Druid
        [132129]        = Spell(102693), -- Grove Guardians
	}

	-- Importantly, the slot index does not change if you cast other totems.
	self.events:RegisterWoWEvent("PLAYER_TOTEM_UPDATE", function(...)
		-- slotIndex
		local args = { ... }

		-- This will give us either a valid totem or nil
		local totem = self:GetTotemInfo(args[1])

		self.totems[args[1]] = totem

	end)

	return self
end

---@param spell_id number
---@return boolean
function TotemManager:IsActive(spell_id)
	for _, totem in pairs(self.totems) do
		if totem and totem.spell_id == spell_id then
			return totem.start_time + totem.duration > GetTime()
		end
	end
	return false
end

---@param spell_id number
---@return number
function TotemManager:ActiveCount(spell_id)
    local count = 0
	for _, totem in pairs(self.totems) do
		if totem and totem.spell_id == spell_id then
			count = count + 1
		end
	end

	return count
end

---@param spell_id number
---@return number
function TotemManager:TimeRemaining(spell_id)
	for _, totem in pairs(self.totems) do
		if totem and totem.spell_id == spell_id then
			return totem.start_time + totem.duration - GetTime()
		end
	end
	return 0
end

---@param slotIndex number
---@return table|nil
function TotemManager:GetTotemInfo(slotIndex)
	local args = { GetTotemInfo(slotIndex) }
	if args[1] then
		if not self.totem_spells[args[5]] then return nil end
		local totem = {
			spell_id = self.totem_spells[args[5]].id,
			icon = args[5],
			start_time = args[3],
			duration = args[4]
		}
		return totem
	else
		return nil
	end
end

return TotemManager