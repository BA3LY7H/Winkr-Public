local unlocker,
---@class mint
mint = ...

local UnitManager = mint.UnitManager
local Settings = mint.Settings

---@class Keybinds
---@field keybinds table
---@field listener Frame
---@field pending table?
---@field ticker number
local Keybinds = {}
Keybinds.__index = Keybinds

function Keybinds:New()
    local self = setmetatable({}, Keybinds)

    local _, _, ClassID = UnitClass("player")

	self.keybinds = Settings.keybinds[mint.class]
	self.listener = CreateFrame("Frame")
    self.pending = nil

    return self
end

function Keybinds:ParseKeyCombination(key)
	local modifier = false
	local main_key = key

	local dash_pos = key:find("-")
	if dash_pos then
		local prefix = key:sub(1, dash_pos - 1)
		local suffix = key:sub(dash_pos + 1)

		-- Ensure prefix is a valid modifier and suffix is non-empty
		if (prefix == "SHIFT" or prefix == "CTRL" or prefix == "ALT" or prefix == "META") and #suffix > 0 then
			modifier = prefix
			main_key = suffix
		end
	end

	-- Validate main_key: either 1 char or matches F1+ or M1+ (I know, too much, but fuck it)
	if not main_key:match("^.$") and not main_key:match("^[FM]%d%d?$") then
		error("Invalid main key: " .. tostring(main_key))
	end

	return main_key, modifier
end

function Keybinds:HandleCast(data)
    local enabled, spellId, name, target = data.enabled, data.spellId, data.name, data.target
    -- SpellCancelQueuedSpell()

    if FindBaseSpellByID(spellId) ~= spellId then
        spellId = FindBaseSpellByID(spellId)
    end

    if target == "Self" then
        CastSpellByID(spellId, "player")
    elseif target == "Target" then
        local tar = UnitManager:Get("target")
        if tar and tar:GetExists() then
            CastSpellByID(spellId, "target")
        end
    elseif target == "Mouseover" then
        local tar = UnitManager:Get("mouseover")
        if tar and tar:GetExists() then
            CastSpellByID(spellId, "mouseover")
        end
    elseif target == "Focus" then
        local tar = UnitManager:Get("focus")
        if tar and tar:GetExists() then
            CastSpellByID(spellId, "focus")
        end
    elseif target == "Cursor" then
        CastSpellByID(spellId, "cursor")
    end
end

function Keybinds:Tick()
    -- No keybinds while mounted
    if IsMounted() then return end

    if not mint.data.toggles.engine then return end

    -- No keybinds while typing in chat
    if _G["ACTIVE_CHAT_EDIT_BOX"] and _G["ACTIVE_CHAT_EDIT_BOX"]:HasFocus() then
        return
    end

    local binds = self.keybinds

    for k, v in pairs(binds) do
        if v.enabled then
            local is_down = false

            -- Parse key combination (e.g., "M", "SHIFT+M", "CTRL+M", etc.)
            local main_key, modifier = self:ParseKeyCombination(v.keybind)

			local spell = mint.Spell.New(v.spellId)
            -- print(main_key, modifier)
            -- "M", "SHIFT"

            if modifier then
                if modifier == "SHIFT" then
                    if IsKeyDown(main_key) and IsShiftKeyDown() then
                        self:HandleCast(v)
                        return not spell:IsOnCD()
                    end
                elseif modifier == "ALT" then
                    if IsKeyDown(main_key) and IsAltKeyDown() then
                        self:HandleCast(v)
                        return not spell:IsOnCD()
                    end
                elseif modifier == "CTRL" then
                    if IsKeyDown(main_key) and IsControlKeyDown() then
                        self:HandleCast(v)
                        return not spell:IsOnCD()
                    end
                elseif modifier == "META" then
                    if IsKeyDown(main_key) and IsMetaKeyDown() then
                        self:HandleCast(v)
                        return not spell:IsOnCD()
                    end
                end
            else
                if IsKeyDown(main_key) and not IsModifierKeyDown() then
                    self:HandleCast(v)
					return not spell:IsOnCD()
                end
            end
        end
    end

	-- Return false if no keybind is down
	return false

end

function Keybinds:IsListening()
	return self.pending ~= nil
end

function Keybinds:SetListening(listen)
    -- mint:Log("Set Listening", listen)
    if listen then
        self.listener:SetScript("OnKeyDown", function(_, key)
			self:OnKeyDown(key)
        end)
    else
        self.listener:SetScript("OnKeyDown", nil)
    end
end

function Keybinds:StopListening()
	if not self:IsListening() then return end
    -- mint:Log("Stop listening")

	self.pending = nil

	self:SetListening(false)
end

-- Table is the whole keybinds table
-- Cell is the cell that was clicked
-- Row is the row that was clicked
function Keybinds:StartListening(table, cell, row, rowIndex)
    -- mint:Log("Start listening")
    local name = row.name
    local spellId = row.spellId
    local index = rowIndex

    self.pending = {
        bind = {
            index = index,
            name = name,
            spellId = spellId
        },
        row = row,
        button = cell,
        opt_table = table
    }

    cell.text:SetText("Listening...")

    self:SetListening(true)
end

function Keybinds:OnKeyDown(key)
    -- mint:Log("KeyDown:", key)
    self:ProcessInput(key)
end


function Keybinds:ProcessInput(input)
    local pending = self.pending;

	if not pending then
		return false
	end

	local currentAction = GetBindingFromClick(input);

	-- print(currentAction)

	if currentAction == "SCREENSHOT" then
		RunBinding("SCREENSHOT");
		return false;
	end

	if input == "ESCAPE" then
		self:UnbindKey(pending)
		self:StopListening()
		return true;
	end

	local key = GetConvertedKeyOrButton(input);
	if IsKeyPressIgnoredForBinding(key) then
		return false;
	end


	local newKey = CreateKeyChordStringUsingMetaKeyState(key)

	self:StopListening()
	self:BindKey(pending, newKey)

	return true;
end

function Keybinds:BindKey(pending, newKey)
    -- mint:Log("Bind Key", newKey)
    if not pending.button then
        return false
    end

	local data = Settings.keybinds[mint.class]

    pending.row.keybind = newKey
    pending.button.text:SetText(newKey)
    data[pending.bind.index].keybind = newKey
    pending.opt_table:SetData(data)
end

function Keybinds:UnbindKey(pending)
    -- mint:Log("Unbind Key", pending.row.name)
    if not pending.button then
        return false
    end

	local data = Settings.keybinds[mint.class]

    pending.row.keybind = "None"
    pending.button.text:SetText("None")
    data[pending.bind.index].keybind = "None"
    pending.opt_table:SetData(data)
end

return Keybinds