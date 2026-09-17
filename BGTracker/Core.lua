local addonName, addon = ...
local events = CreateFrame("Frame")
local initialized, loading = false, true
local elapsed, scoreElapsed = 0, 0

local function now()
    return GetServerTime and GetServerTime() or time()
end

local function playerFaction()
    if not GetNumBattlefieldScores or not GetBattlefieldScore then return end
    local player, realm = UnitFullName("player")
    realm = (realm or GetRealmName()):gsub("%s", "")
    for i = 1, GetNumBattlefieldScores() do
        local name, _, _, _, _, faction = GetBattlefieldScore(i)
        if name == player or name == player .. "-" .. realm then return faction end
    end
    -- Do not guess from race: TBC supports same-faction battlegrounds.
end

local function battlefieldInfo()
    local inside, instanceType = IsInInstance()
    if not inside or instanceType ~= "pvp" then return end
    local name, _, _, _, _, _, _, mapID = GetInstanceInfo()
    local instanceID
    for i = 1, (GetMaxBattlefieldID and GetMaxBattlefieldID() or 3) do
        local status, _, id = GetBattlefieldStatus(i)
        if status == "active" then instanceID = id; break end
    end
    return {
        name = name or GetRealZoneText(), mapID = mapID, instanceID = instanceID,
        runtime = (GetBattlefieldInstanceRunTime() or 0) / 1000,
        winner = GetBattlefieldWinner(), faction = playerFaction(),
    }
end

local function refresh()
    if addon.RefreshUI then addon.RefreshUI() end
end

local function sync(checkIdentity, recovering)
    if not initialized or loading then return end
    local info = battlefieldInfo()
    local tracker = addon.tracker
    if info then
        if tracker.db.active and checkIdentity and not tracker:IsSameMatch(info, now()) then
            tracker:Archive(recovering and "Interrupted" or "Left")
        end
        if tracker.db.active and recovering and now() - tracker.db.active.lastSeen > 15 then
            tracker.db.active.partial = true
        end
        if not tracker.db.active then tracker:Start(info, now()) end
        tracker:Update(info, now())
    elseif tracker.db.active then
        tracker:Archive(recovering and "Interrupted" or "Left")
    end
    refresh()
end

events:SetScript("OnEvent", function(_, event, ...)
    if event == "ADDON_LOADED" then
        if ... ~= addonName then return end
        BGTrackerDB = BGTrackerDB or {}
        addon.tracker = addon.Tracker.New(BGTrackerDB, {
            { kind = "hk", format = COMBATLOG_HONORGAIN },
            { kind = "hk", format = COMBATLOG_HONORGAIN_NO_RANK },
            { kind = "additional", format = COMBATLOG_HONORAWARD },
        })
        initialized = true
        addon.CreateUI()
        SLASH_BGTRACKER1 = "/bgt"
        SLASH_BGTRACKER2 = "/bgtracker"
        SlashCmdList.BGTRACKER = function() addon.ToggleUI() end
    elseif not initialized then
        return
    elseif event == "PLAYER_ENTERING_WORLD" then
        loading = false
        sync(true, not addon.enteredWorld)
        addon.enteredWorld = true
        if addon.tracker.db.active then RequestBattlefieldScoreData() end
    elseif event == "PLAYER_LEAVING_WORLD" then
        sync(false)
        loading = true
    elseif event == "PLAYER_LOGOUT" then
        if not loading then sync(false) end
    elseif event == "CHAT_MSG_COMBAT_HONOR_GAIN" then
        local inside, instanceType = IsInInstance()
        if loading or not inside or instanceType ~= "pvp" then return end
        if not addon.tracker.db.active then sync(false) end
        addon.tracker:AddHonor(select(1, ...), select(11, ...))
        refresh()
    elseif event == "UPDATE_BATTLEFIELD_SCORE" or event == "UPDATE_BATTLEFIELD_STATUS" then
        sync(false)
    end
end)

events:SetScript("OnUpdate", function(_, delta)
    if not initialized or loading then return end
    elapsed = elapsed + delta
    scoreElapsed = scoreElapsed + delta
    if elapsed >= 1 then
        elapsed = 0
        sync(false)
    end
    if scoreElapsed >= 10 then
        scoreElapsed = 0
        if addon.tracker.db.active then RequestBattlefieldScoreData() end
    end
end)

for _, event in ipairs({
    "ADDON_LOADED", "PLAYER_ENTERING_WORLD", "PLAYER_LEAVING_WORLD",
    "PLAYER_LOGOUT", "UPDATE_BATTLEFIELD_STATUS", "UPDATE_BATTLEFIELD_SCORE",
    "CHAT_MSG_COMBAT_HONOR_GAIN",
}) do
    events:RegisterEvent(event)
end
