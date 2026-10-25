local unlocker,
---@class mint
mint = ...

local Notification = mint.Notification

---@class NotificationManager
local NotificationManager = {
    notifications = {}
}
NotificationManager.__index = NotificationManager

-- Constructor
---@return NotificationManager
function NotificationManager:New()
    local self = setmetatable({}, NotificationManager)

    -- Create a frame for the notifications
    self.frame = CreateFrame("Frame", "notify", UIParent)
    self.frame:SetSize(600, 60)
    self.frame:SetPoint("TOP", UIParent, "TOP", 0, -300)
    self.frame:SetFrameStrata("HIGH")

    -- Remove notifications after 5 seconds
    C_Timer.NewTicker(0.1, function()
        for i, notification in ipairs(self.notifications) do
            if GetTime() - notification.addedAt > notification.duration then
                notification:Remove()
                table.remove(self.notifications, i)
            end
        end
    end)

    return self
end

-- Add a notification to the list
---@param icon string
---@param text string
---@param duration number
---@return nil
function NotificationManager:AddNotification(icon, text, duration, spam)
    -- Prevent duplicate notifications
    if not spam then
        for _, notification in ipairs(self.notifications) do
            if notification.iconPath == icon and notification.text:GetText() == text then
                -- Already showing this notification, skip
                return
            end
        end
    end

    -- Create a new notification
    local notification = Notification:New(self, icon, text, duration)

    -- Store the icon path for duplicate detection
    notification.iconPath = icon

    -- Add the notification to the list
    table.insert(self.notifications, notification)
    UIFrameFadeIn(notification.frame, 0.2, 0, 1)

    -- Update the notifications
    self:Update()
end

-- Update the notifications
---@return nil
function NotificationManager:Update()
    -- Loop through the notifications
    for i, notification in ipairs(self.notifications) do
        -- Set the position of the notification
        notification.frame:SetPoint("CENTER", self.frame, "CENTER", 0, -42 * (i - 1))
    end
end

-- Remove a notification from the list
---@param notification Notification
---@return nil
function NotificationManager:RemoveNotification(notification)
    -- Loop through the notifications
    for i, v in ipairs(self.notifications) do
        -- Check if the notification is the one we want to remove
        if v == notification then
            -- Remove the notification from the list
            table.remove(self.notifications, i)
            notification:Remove()
            break
        end
    end
end

-- Remove all notifications from the list
---@return nil
function NotificationManager:RemoveAllNotifications()
    -- Loop through the notifications
    for i, v in ipairs(self.notifications) do
        -- Remove the notification from the list
        table.remove(self.notifications, i)
        self.notifications[i]:Remove()
    end
end

-- Remove all notifications
return NotificationManager