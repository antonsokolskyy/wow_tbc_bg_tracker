local _, addon = ...

local Tracker = {}
addon.Tracker = Tracker

-- Build patterns from the client's translated format strings. Positional
-- placeholders (e.g. %3$d) are used by some locales.
local function messagePattern(format)
    if type(format) ~= "string" or format == "" then return end
    local parts, numericCapture, captures = {}, nil, 0
    local i = 1
    while i <= #format do
        local char = format:sub(i, i)
        if char == "%" then
            local token = format:sub(i):match("^%%[123456789]%$[sd]")
                or format:sub(i):match("^%%[sd]")
            if token then
                captures = captures + 1
                if token:sub(-1) == "d" then
                    parts[#parts + 1] = "([%d%s%.,]+)"
                    numericCapture = captures
                else
                    parts[#parts + 1] = "(.-)"
                end
                i = i + #token
            elseif format:sub(i, i + 1) == "%%" then
                parts[#parts + 1] = "%%"
                i = i + 2
            else
                parts[#parts + 1] = "%%"
                i = i + 1
            end
        else
            parts[#parts + 1] = char:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1")
            i = i + 1
        end
    end
    if numericCapture then
        return { pattern = "^" .. table.concat(parts) .. "$", capture = numericCapture }
    end
end

function Tracker.New(db, formats)
    db.history = db.history or {}
    db.minimapAngle = db.minimapAngle or 220
    db.version = 1
    local self = setmetatable({ db = db, patterns = {}, seenLines = {} }, { __index = Tracker })
    for _, entry in ipairs(formats) do
        local pattern = messagePattern(entry.format)
        if pattern then
            pattern.kind = entry.kind
            self.patterns[#self.patterns + 1] = pattern
        end
    end
    return self
end

function Tracker:ParseHonor(message)
    if type(message) ~= "string" then return end
    message = message:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    message = message:gsub("|H.-|h(.-)|h", "%1")
    for _, entry in ipairs(self.patterns) do
        local captures = { message:match(entry.pattern) }
        local value = captures[entry.capture]
        if value then
            return entry.kind, tonumber((value:gsub("%D", "")))
        end
    end
end

function Tracker:Start(info, now)
    local runtime = math.max(0, info.runtime or 0)
    self.db.active = {
        name = info.name, mapID = info.mapID, instanceID = info.instanceID,
        joinedAt = now, startedAt = now - runtime, lastSeen = now,
        duration = runtime, clockStart = runtime > 0 and now - runtime or nil,
        hkHonor = 0, additionalHonor = 0, result = "In progress",
        partial = runtime > 120,
    }
    self.seenLines = {}
    return self.db.active
end

function Tracker:IsSameMatch(info, now)
    local active = self.db.active
    if not active or active.mapID ~= info.mapID or active.name ~= info.name then return false end
    if active.instanceID and info.instanceID and active.instanceID ~= info.instanceID then return false end
    if active.endedAt then
        if info.winner ~= active.winner then return false end
        -- Some clients stop the runtime at the result screen. A reload while
        -- waiting to leave must not create a second copy of that match.
        if math.abs((info.runtime or 0) - active.duration) < 3 and now - active.endedAt < 600 then
            return true
        end
    end
    if active.clockStart and (info.runtime or 0) > 0 then
        return math.abs(now - info.runtime - active.clockStart) < 30
    end
    return now - active.lastSeen < 180
end

function Tracker:Update(info, now)
    local active = self.db.active
    if not active then return end
    active.lastSeen = now
    -- A scoreboard faction is the actual team, including same-faction games.
    if info.faction == 0 or info.faction == 1 then active.faction = info.faction end
    if not active.endedAt then
        if info.runtime and info.runtime > 0 then
            active.duration = math.floor(info.runtime)
            active.clockStart = now - info.runtime
            active.startedAt = math.floor(active.clockStart)
        else
            active.duration = math.max(0, now - active.startedAt)
        end
    end
    if info.winner ~= nil then
        if not active.endedAt then active.endedAt = now end
        active.winner = info.winner
    end
    if active.winner ~= nil then
        if active.winner == 255 then
            active.result = "Draw"
        elseif active.faction ~= nil then
            active.result = active.winner == active.faction and "Win" or "Loss"
        else
            active.result = "Unknown"
        end
    end
end

function Tracker:AddHonor(message, lineID)
    local active = self.db.active
    if not active then return false end
    local kind, amount = self:ParseHonor(message)
    if not kind or not amount then
        active.unparsedHonor = (active.unparsedHonor or 0) + 1
        return false
    end
    if lineID and lineID > 0 then
        if self.seenLines[lineID] then return false end
        self.seenLines[lineID] = true
    end
    local field = kind == "hk" and "hkHonor" or "additionalHonor"
    active[field] = active[field] + amount
    return true
end

function Tracker:Archive(reason)
    local active = self.db.active
    if not active then return end
    if not active.endedAt then
        active.result = reason or "Left"
        active.endedAt = active.lastSeen
    end
    table.insert(self.db.history, 1, active)
    -- Bound SavedVariables growth; always keep the most recent matches.
    while #self.db.history > 1000 do table.remove(self.db.history) end
    self.db.active = nil
    self.seenLines = {}
end

function Tracker:GetRows()
    local rows = {}
    if self.db.active then rows[1] = self.db.active end
    for _, entry in ipairs(self.db.history) do rows[#rows + 1] = entry end
    return rows
end

function Tracker.FormatDuration(seconds)
    seconds = math.max(0, math.floor(seconds or 0))
    if seconds >= 3600 then
        return string.format("%d:%02d:%02d", math.floor(seconds / 3600), math.floor(seconds / 60) % 60, seconds % 60)
    end
    return string.format("%d:%02d", math.floor(seconds / 60), seconds % 60)
end
