---@class DebugFrame
local DebugFrame = {}
DebugFrame.__index = DebugFrame

-- Constructor
---@return DebugFrame
function DebugFrame.New(title)
    -- Create a new instance of DebugFrame
    local instance = setmetatable({}, DebugFrame)

    -- Tracker frame used for OnUpdate handling
    instance.tracker = CreateFrame("Frame")
    instance.ticker = 0

    -- Main container frame with a default panel style
    instance.frame = CreateFrame("Frame", nil, UIParent, "DefaultPanelFlatTemplate")
    instance.frame:SetSize(200, 50)
    instance.frame:SetPoint("CENTER")
    instance.frame.TitleContainer.TitleText:SetText(title or "Debug Frame")

    -- Allow the frame to be moved by dragging
    instance.frame:SetMovable(true)
    instance.frame:EnableMouse(true)
    instance.frame:RegisterForDrag("LeftButton")
    instance.frame:SetScript("OnDragStart", instance.frame.StartMoving)
    instance.frame:SetScript("OnDragStop", instance.frame.StopMovingOrSizing)

    -- Data structure for row tracking
    instance.data = {
        rowCount = 0,     -- Number of rows currently added
        rows = {},        -- Stores row definitions
        rowHeight = 40,   -- Height of each row block
        headerHeight = 10,-- Height reserved for header spacing
        padding = 20      -- Extra padding at bottom
    }

    -- Update handler for refreshing row values
    instance.tracker:SetScript("OnUpdate", function(self, elapsed)
        instance.ticker = instance.ticker + elapsed

        -- Only refresh once every 0.1s to reduce performance impact
        if instance.ticker < 0.1 then return end
        instance.ticker = 0

        -- Update each row with the latest callback result
        for i, row in ipairs(instance.data.rows) do
            local value = tostring(row.callback() or "nil")
            row.text:SetText(value)
        end
    end)

    return instance
end

-- Recalculate frame height based on number of rows
function DebugFrame:UpdateHeight()
    local contentHeight = self.data.headerHeight + (self.data.rowCount * self.data.rowHeight) + self.data.padding
    self.frame:SetHeight(contentHeight)
end

-- Add a new row with a label and dynamic value
---@param title string   -- The label text
---@param callback fun():any -- Function returning the value to display
function DebugFrame:AddRow(title, callback)
    local rowCount = self.data.rowCount

    -- Calculate vertical offset for this row
    local yOffset = -self.data.headerHeight - (rowCount * self.data.rowHeight)

    -- Create the row label
    local label = self.frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("TOPLEFT", self.frame.NineSlice.TopLeftCorner, "LEFT", 20, yOffset)
    label:SetText(title)

    -- Create the row value text (updated by callback)
    local text = self.frame:CreateFontString(nil, "OVERLAY", "WhiteNormalNumberFont")
    text:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 5, -5)
    text:SetText("---") -- Initial placeholder

    -- Save this row’s data for updates
    rowCount = rowCount + 1
    self.data.rows[rowCount] = {
        label = label,
        text = text,
        callback = callback
    }
    self.data.rowCount = rowCount

    -- Adjust the frame height to fit the new row
    self:UpdateHeight()
end

return DebugFrame
