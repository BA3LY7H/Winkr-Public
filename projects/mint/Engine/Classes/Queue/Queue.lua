local unlocker,
---@class mint
mint = ...

local ProjectileInfo = {
	[44425] = { id = 44425, velocity = 24, },
	[133] = { id = 133, velocity = 40, },
	[257541] = { id = 257541, velocity = 50, },
	[11366] = { id = 11366, velocity = 35, },
}

---@class Queue
---@field queue table
local Queue = {}
Queue.__index = Queue

-- Constructor
function Queue:New()
	local self = setmetatable({}, Queue)

	self.queue = {}

	return self
end

-- Add event
function Queue:AddEvent(key, start, time, type, target)
	if not time then
		if type == "PROJECTILE_IMPACT" then
			local info = ProjectileInfo[key]

			if info then
				if info.flightTime then
					time = start + 0.05 + info.flightTime
				else
					local player = mint.UnitManager:Get("player")
					local tar = mint.UnitManager:Get("target")
					time = start + 0.05 + (player:GetDistance(tar) / info.velocity)
				end
			end
		end
	end

	if key and start and time and type then
		if time < start then time = start + time end

		local event = {
			key = key,
			start = start,
			time = time,
			type = type,
			target = target,
			func = nil
		}

		table.insert(self.queue, event)
		table.sort(self.queue, function(a, b)
			return a.time < b.time
		end)

	end
end

-- Remove event
function Queue:RemoveEvent(key, type, reverse)
	if reverse then
		for i = #self.queue, 1, -1 do
			local event = self.queue[i]

			if event.key == key and event.type == type then
				table.remove(self.queue, i)
				return true
			end
		end
	else
		for i = 1, #self.queue do
			local event = self.queue[i]

			if event.key == key and event.type == type then
				table.remove(self.queue, i)
				return true
			end
		end
	end

	return false
end

function Queue:IsInFlight(spell_id)
	for i = 1, #self.queue do
		local event = self.queue[i]

		local key = spell_id

		if event.key == key and event.type == "PROJECTILE_IMPACT" then
			if event.start <= GetTime() + 0.05 then
				return true
			end
		end
	end

	return false
end

function Queue:FlightRemains(spell_id)
	for i = 1, #self.queue do
		local event = self.queue[i]

		local key = spell_id

		if event.key == key and event.type == "PROJECTILE_IMPACT" then
			if event.start <= GetTime() + 0.05 then
				return event.time - GetTime()
			end
		end
	end

	return 0
end

return Queue