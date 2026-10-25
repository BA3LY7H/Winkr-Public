-- Create a notification class for the notifications list (takes icon and text)
---@class Notification
local Notification = {
}
Notification.__index = Notification

-- Constructor
---@param list NotificationManager
---@param icon string
---@param text string
---@param duration number
---@return Notification
function Notification:New(list, icon, text, duration)
    local self = setmetatable({}, Notification)

    if not duration then duration = 2 end

    -- Create a frame for the notification
    self.frame = CreateFrame("Frame", nil, list.frame)
    self.frame:SetSize(5, 5)
    self.frame:SetPoint("CENTER", list.frame, "CENTER", 0, 0)
    self.frame:SetFrameStrata("HIGH")

    -- Create the icon texture
    self.icon = self.frame:CreateTexture(nil, "ARTWORK")
    self.icon:SetSize(40, 40)
    self.icon:SetPoint("LEFT", self.frame, "LEFT", 0, 0)
    self.icon:SetTexture(icon)
    self.iconPath = icon

    self.mask = self.frame:CreateMaskTexture()
    self.mask:SetAllPoints(self.icon)
    self.mask:SetTexture("Interface/CHARACTERFRAME/TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    self.icon:AddMaskTexture(self.mask)

    -- Create a fontstring for the text
    self.text = self.frame:CreateFontString(nil, "BACKGROUND", "NumberFontNormal")
    self.text:SetPoint("LEFT", self.frame, "LEFT", 40 + 20, 0)
    self.text:SetText(text)
    self.text:SetFont(GameFontNormalHugeOutline:GetFont(), 24, "OUTLINE")

    -- set the frame size to the size of the text + icon
    self.frame:SetSize(self.text:GetStringWidth() + 40 + 20, 40)

    self.addedAt = GetTime()
    self.duration = duration
    self.list = list

    return self
end

-- Remove notification
---@return nil
function Notification:Remove()
    -- Fade out the notification frame and remove it after the fade
    UIFrameFadeOut(self.frame, 0.2, 1, 0)
    C_Timer.After(0.5, function()
        self.frame:Hide()
        self.frame:ClearAllPoints()
        self.frame:SetParent(nil)
        self.frame = nil
        self.list:Update()
    end)
end

return Notification