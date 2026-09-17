-- Run from the project root: lua5.1 tests/run.lua
local passed = 0
local function equal(actual, expected, message)
    assert(actual == expected, (message or "Unexpected value") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
local function test(name, run)
    local ok, err = pcall(run)
    if not ok then error("FAIL " .. name .. "\n" .. tostring(err), 0) end
    passed = passed + 1
    print("PASS " .. name)
end

local hkFormat = "%s dies, honorable kill Rank: %s (Estimated Honor Points: %d)"
local bonusFormat = "You have been awarded %d honor points."
local addon = {}
assert(loadfile("BGTracker/Tracker.lua"))("BGTracker", addon)
local Tracker = addon.Tracker
local function tracker()
    return Tracker.New({}, {
        { kind = "hk", format = hkFormat },
        { kind = "additional", format = bonusFormat },
    })
end
local function info(runtime, winner, faction)
    return { name = "Warsong Gulch", mapID = 489, instanceID = 17,
        runtime = runtime, winner = winner, faction = faction }
end

test("honor separates HK and bonus without using victim/rank digits", function()
    local t = tracker()
    t:Start(info(0), 1000)
    t:AddHonor("Player42 dies, honorable kill Rank: Rank 10 (Estimated Honor Points: 21)", 1)
    t:AddHonor("You have been awarded 100 honor points.", 2)
    equal(t.db.active.hkHonor, 21)
    equal(t.db.active.additionalHonor, 100)
end)

test("duplicate line IDs ignored; equal amounts on different lines counted", function()
    local t = tracker()
    t:Start(info(0), 1000)
    for _, id in ipairs({ 1, 1, 2 }) do t:AddHonor("You have been awarded 10 honor points.", id) end
    equal(t.db.active.additionalHonor, 20)
end)

test("localized positional placeholders, punctuation, and links", function()
    local t = Tracker.New({}, {
        { kind = "hk", format = "%3$d Ehre: %1$s stirbt (%2$s)." },
        { kind = "additional", format = "Bonus + %d [Ehre]!" },
    })
    t:Start(info(0), 1000)
    t:AddHonor("1.234 Ehre: |cff00ff00|Hplayer:Foo|h[Foo]|h|r stirbt (Rang 8).")
    t:AddHonor("Bonus + 22 [Ehre]!")
    equal(t.db.active.hkHonor, 1234)
    equal(t.db.active.additionalHonor, 22)
end)

test("unknown honor message marks incomplete data without inventing honor", function()
    local t = tracker()
    t:Start(info(0), 1000)
    equal(t:AddHonor("Unknown message 999"), false)
    equal(t.db.active.unparsedHonor, 1)
    equal(t.db.active.hkHonor + t.db.active.additionalHonor, 0)
end)

test("win freezes time and still accepts late completion honor", function()
    local t = tracker()
    t:Start(info(100), 1000)
    t:Update(info(200, 1, 1), 1100)
    t:Update(info(220, 1, 1), 1120)
    t:AddHonor("You have been awarded 200 honor points.")
    equal(t.db.active.result, "Win")
    equal(t.db.active.duration, 200)
    equal(t.db.active.startedAt, 900)
    equal(t.db.active.additionalHonor, 200)
    t:Archive()
    t:Archive()
    equal(#t.db.history, 1)
end)

test("winner zero, loss, draw, and late team information", function()
    local t = tracker()
    t:Start(info(0), 1000)
    t:Update(info(100, 0), 1100)
    equal(t.db.active.result, "Unknown")
    t:Update(info(100, 0, 0), 1101)
    equal(t.db.active.result, "Win")
    t:Archive()
    t:Start(info(0), 2000)
    t:Update(info(100, 0, 1), 2100)
    equal(t.db.active.result, "Loss")
    t:Archive()
    t:Start(info(0), 3000)
    t:Update(info(100, 255), 3100)
    equal(t.db.active.result, "Draw")
end)

test("reload recovery recognizes live and completed matches", function()
    local t = tracker()
    t:Start(info(100), 1000)
    equal(t:IsSameMatch(info(120), 1020), true)
    equal(t:IsSameMatch(info(0), 1400), false)
    t:Update(info(200, 1, 1), 1100)
    equal(t:IsSameMatch(info(200, 1, 1), 1200), true)
    equal(t:IsSameMatch(info(0), 1200), false)
end)

test("abandoned matches are not recorded as losses", function()
    local t = tracker()
    t:Start(info(100), 1000)
    t:Archive("Left")
    equal(t.db.history[1].result, "Left")
    t:Start(info(100), 2000)
    t:Archive("Interrupted")
    equal(t.db.history[1].result, "Interrupted")
end)

test("mid-match joins and unavailable clocks", function()
    local t = tracker()
    t:Start(info(600), 1000)
    equal(t.db.active.partial, true)
    equal(t.db.active.startedAt, 400)
    t:Archive()
    t:Start(info(0), 2000)
    t:Update(info(0), 2010)
    equal(t.db.active.duration, 10)
    equal(Tracker.FormatDuration(3661), "1:01:01")
    equal(Tracker.FormatDuration(65), "1:05")
end)

test("history keeps latest 1000 matches in newest-first order", function()
    local t = tracker()
    for i = 1, 1002 do t:Start(info(0), i); t:Archive() end
    equal(#t.db.history, 1000)
    equal(t.db.history[1].startedAt, 1002)
    equal(t.db.history[1000].startedAt, 3)
end)

-- Explicit UI stand-ins catch load errors and exercise actual addon events.
local methods = {}
local function widget(name)
    local value = setmetatable({ scripts = {}, shown = true, name = name }, { __index = methods })
    if name then _G[name] = value end
    return value
end
for _, method in ipairs({ "SetFrameStrata", "SetFrameLevel", "RegisterForClicks", "RegisterForDrag",
    "SetHighlightTexture", "SetTexCoord", "ClearAllPoints", "SetClampedToScreen", "SetMovable",
    "EnableMouse", "SetBackdrop", "SetBackdropColor", "SetBackdropBorderColor", "SetJustifyH",
    "SetWordWrap", "EnableMouseWheel", "SetAllPoints", "SetScale", "SetOwner", "AddLine",
    "StartMoving", "StopMovingOrSizing" }) do
    methods[method] = function() end
end
function methods:SetPoint(...) self.point = { ... } end
function methods:SetSize(w, h) self.width, self.height = w, h end
function methods:SetWidth(w) self.width = w end
function methods:GetWidth() return self.width or 140 end
function methods:GetHeight() return self.height or 140 end
function methods:GetFrameLevel() return 1 end
function methods:GetCenter() return 100, 100 end
function methods:GetEffectiveScale() return 1 end
function methods:SetTexture(value) self.texture = value end
function methods:SetColorTexture(...) self.color = { ... } end
function methods:SetTextColor(...) self.color = { ... } end
function methods:SetText(value) self.text = tostring(value) end
function methods:SetEnabled(value) self.enabled = value end
function methods:SetScript(event, handler) self.scripts[event] = handler end
function methods:RegisterEvent(event) self.events = self.events or {}; self.events[event] = true end
function methods:CreateTexture() return widget() end
function methods:CreateFontString() return widget() end
function methods:IsShown() return self.shown end
function methods:SetShown(value) if value then self:Show() else self:Hide() end end
function methods:Show()
    local wasShown = self.shown
    self.shown = true
    if not wasShown and self.scripts.OnShow then self.scripts.OnShow(self) end
end
function methods:Hide() self.shown = false end

local clock, inside, instanceType, runtime, winner, team, instanceID, zone
local requests, eventFrame
UIParent = widget(); UIParent:SetSize(1920, 1080)
Minimap = widget()
GameTooltip = widget()
UISpecialFrames, SlashCmdList = {}, {}
C_Timer = { After = function(_, callback) callback() end }
COMBATLOG_HONORGAIN, COMBATLOG_HONORAWARD = hkFormat, bonusFormat
GetServerTime = function() return clock end
IsInInstance = function() return inside, instanceType end
GetInstanceInfo = function() return zone, instanceType, 0, "", 0, 0, false, 489 end
GetBattlefieldInstanceRunTime = function() return runtime * 1000 end
GetBattlefieldWinner = function() return winner end
GetMaxBattlefieldID = function() return 3 end
GetBattlefieldStatus = function(i) if inside and i == 1 then return "active", zone, instanceID end return "none" end
UnitFullName = function() return "Player", "Test Realm" end
GetRealmName = function() return "Test Realm" end
GetNumBattlefieldScores = function() return 2 end
GetBattlefieldScore = function(i)
    if i == 1 then return "Player-OtherRealm", 0, 0, 0, 99999, 1 end
    if team ~= nil then return "Player-TestRealm", 0, 0, 0, 99999, team end
end
RequestBattlefieldScoreData = function() requests = requests + 1 end
GetCursorPosition = function() return 150, 150 end
date = os.date
CreateFrame = function(_, name)
    local value = widget(name)
    if not name then eventFrame = value end
    return value
end

local function loadAddon(db)
    BGTrackerDB = db
    local namespace = {}
    for _, file in ipairs({ "Tracker", "UI", "Core" }) do
        assert(loadfile("BGTracker/" .. file .. ".lua"))("BGTracker", namespace)
    end
    local event = eventFrame
    event.scripts.OnEvent(event, "ADDON_LOADED", "BGTracker")
    return namespace, event
end
local live, frame
local function emit(event, ...) frame.scripts.OnEvent(frame, event, ...) end
local function reset()
    clock, inside, instanceType, runtime, winner, team, instanceID, zone = 10000, false, "none", 0, nil, 0, 17, "Warsong Gulch"
    requests = 0
    live, frame = loadAddon(nil)
    emit("PLAYER_ENTERING_WORLD")
end
local function enter()
    inside, instanceType = true, "pvp"
    emit("PLAYER_ENTERING_WORLD")
end

test("addon boots with hidden window and clickable minimap icon", function()
    reset()
    equal(BGTrackerWindow:IsShown(), false)
    BGTrackerMinimapButton.scripts.OnClick(BGTrackerMinimapButton)
    equal(BGTrackerWindow:IsShown(), true)
    equal(BGTrackerWindow.empty:IsShown(), true)
    SlashCmdList.BGTRACKER()
    equal(BGTrackerWindow:IsShown(), false)
end)

test("events track a complete game, delayed rewards, green row, and exit once", function()
    reset(); enter()
    emit("CHAT_MSG_COMBAT_HONOR_GAIN", "Enemy dies, honorable kill Rank: Scout (Estimated Honor Points: 18)")
    emit("CHAT_MSG_COMBAT_HONOR_GAIN", "You have been awarded 50 honor points.")
    clock, runtime, winner = 10600, 600, 0
    emit("UPDATE_BATTLEFIELD_SCORE")
    emit("CHAT_MSG_COMBAT_HONOR_GAIN", "You have been awarded 100 honor points.")
    SlashCmdList.BGTRACKER()
    equal(BGTrackerWindow.rows[1].cells[7].text, "Win")
    assert(BGTrackerWindow.rows[1].background.color[2] > BGTrackerWindow.rows[1].background.color[1])
    clock, runtime = 10630, 630
    emit("PLAYER_LEAVING_WORLD")
    inside, instanceType = false, "none"
    emit("PLAYER_ENTERING_WORLD")
    emit("UPDATE_BATTLEFIELD_STATUS")
    equal(#BGTrackerDB.history, 1)
    equal(BGTrackerDB.history[1].hkHonor, 18)
    equal(BGTrackerDB.history[1].additionalHonor, 150)
    equal(BGTrackerDB.history[1].duration, 600)
    equal(BGTrackerDB.history[1].result, "Win")
end)

test("loss rows are red and player lookup distinguishes realms", function()
    reset(); enter()
    clock, runtime, winner = 10600, 600, 1
    emit("UPDATE_BATTLEFIELD_SCORE")
    SlashCmdList.BGTRACKER()
    equal(BGTrackerWindow.rows[1].cells[7].text, "Loss")
    assert(BGTrackerWindow.rows[1].background.color[1] > BGTrackerWindow.rows[1].background.color[2])
end)

test("world PvP and arena honor are ignored", function()
    reset()
    emit("CHAT_MSG_COMBAT_HONOR_GAIN", "You have been awarded 500 honor points.")
    inside, instanceType = true, "arena"
    emit("PLAYER_ENTERING_WORLD")
    emit("CHAT_MSG_COMBAT_HONOR_GAIN", "You have been awarded 500 honor points.")
    equal(BGTrackerDB.active, nil)
    equal(#BGTrackerDB.history, 0)
end)

test("reload preserves active honor and avoids duplicate rows", function()
    reset(); enter()
    clock, runtime = 10100, 100
    emit("UPDATE_BATTLEFIELD_SCORE")
    emit("CHAT_MSG_COMBAT_HONOR_GAIN", "You have been awarded 50 honor points.")
    emit("PLAYER_LOGOUT")
    clock, runtime = 10105, 105
    live, frame = loadAddon(BGTrackerDB)
    emit("PLAYER_ENTERING_WORLD")
    equal(BGTrackerDB.active.additionalHonor, 50)
    equal(#BGTrackerDB.history, 0)
    equal(#live.tracker:GetRows(), 1)
end)

test("reload on result screen with stopped game timer retains one match", function()
    reset(); enter()
    clock, runtime, winner = 10600, 600, 0
    emit("UPDATE_BATTLEFIELD_SCORE")
    clock = 10700
    live, frame = loadAddon(BGTrackerDB)
    emit("PLAYER_ENTERING_WORLD")
    equal(#live.tracker:GetRows(), 1)
    equal(BGTrackerDB.active.result, "Win")
end)

test("startup events cannot mutate saved match before entering world", function()
    reset(); enter()
    clock, runtime = 10100, 100
    emit("PLAYER_LOGOUT")
    clock, inside, instanceType = 10130, false, "none"
    live, frame = loadAddon(BGTrackerDB)
    emit("UPDATE_BATTLEFIELD_STATUS")
    frame.scripts.OnUpdate(frame, 30)
    equal(BGTrackerDB.active.lastSeen, 10100)
    inside, instanceType, runtime = true, "pvp", 130
    emit("PLAYER_ENTERING_WORLD")
    equal(#BGTrackerDB.history, 0)
    equal(BGTrackerDB.active.partial, true)
end)

test("login outside the BG archives unrecoverable active match", function()
    reset(); enter()
    clock, runtime = 10100, 100
    emit("PLAYER_LOGOUT")
    clock, inside, instanceType = 20000, false, "none"
    live, frame = loadAddon(BGTrackerDB)
    emit("PLAYER_ENTERING_WORLD")
    equal(BGTrackerDB.active, nil)
    equal(BGTrackerDB.history[1].result, "Interrupted")
    equal(BGTrackerDB.history[1].duration, 100)
end)

test("a new instance cannot inherit the previous match's honor", function()
    reset(); enter()
    emit("CHAT_MSG_COMBAT_HONOR_GAIN", "You have been awarded 50 honor points.")
    emit("PLAYER_LEAVING_WORLD")
    instanceID = 18
    emit("PLAYER_ENTERING_WORLD")
    equal(#BGTrackerDB.history, 1)
    equal(BGTrackerDB.active.additionalHonor, 0)
end)

test("pagination works and clamps to available pages", function()
    reset()
    for i = 1, 15 do live.tracker:Start(info(0), 1000 + i); live.tracker:Archive() end
    SlashCmdList.BGTRACKER()
    equal(BGTrackerWindow.pageLabel.text, "Page 1 / 2")
    BGTrackerWindow.next.scripts.OnClick()
    equal(BGTrackerWindow.pageLabel.text, "Page 2 / 2")
    equal(BGTrackerWindow.rows[4]:IsShown(), false)
    BGTrackerWindow.scripts.OnMouseWheel(BGTrackerWindow, -1)
    equal(BGTrackerWindow.pageLabel.text, "Page 2 / 2")
end)

test("periodic updates advance live time and request scores", function()
    reset(); enter()
    clock, runtime = 10010, 10
    frame.scripts.OnUpdate(frame, 10)
    equal(BGTrackerDB.active.duration, 10)
    equal(requests, 2)
end)

print(string.format("\n%d tests passed.", passed))
