local _, addon = ...
local window, minimapButton
local page, pageSize = 1, 12
local colors = {
    Win = { 0.20, 0.85, 0.35 }, Loss = { 1, 0.30, 0.30 },
    ["In progress"] = { 1, 0.82, 0.25 },
    Left = { 0.65, 0.65, 0.70 }, Interrupted = { 0.65, 0.65, 0.70 },
    Unknown = { 0.80, 0.70, 0.45 }, Draw = { 0.65, 0.75, 0.95 },
}
local columns = {
    { "BG start (local)", 150, "LEFT" }, { "Battleground", 184, "LEFT" },
    { "Duration", 78, "RIGHT" }, { "HK honor", 82, "RIGHT" },
    { "Additional", 85, "RIGHT" }, { "Total", 72, "RIGHT" },
    { "Result", 98, "LEFT" },
}

local function label(parent, text, font)
    local value = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightSmall")
    value:SetText(text)
    return value
end

local function button(parent, text, width, action)
    local result = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    result:SetSize(width, 24)
    result:SetText(text)
    result:SetScript("OnClick", action)
    return result
end

local function positionMinimap()
    local angle = math.rad(addon.tracker.db.minimapAngle)
    minimapButton:ClearAllPoints()
    minimapButton:SetPoint("CENTER", Minimap, "CENTER",
        math.cos(angle) * (Minimap:GetWidth() / 2 + 8),
        math.sin(angle) * (Minimap:GetHeight() / 2 + 8))
end

local function createMinimapButton()
    minimapButton = CreateFrame("Button", "BGTrackerMinimapButton", Minimap)
    minimapButton:SetSize(32, 32)
    minimapButton:SetFrameStrata("MEDIUM")
    minimapButton:SetFrameLevel(Minimap:GetFrameLevel() + 8)
    minimapButton:RegisterForClicks("LeftButtonUp")
    minimapButton:RegisterForDrag("LeftButton")
    minimapButton:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    local icon = minimapButton:CreateTexture(nil, "ARTWORK")
    icon:SetTexture("Interface\\Icons\\INV_BannerPVP_02")
    icon:SetSize(20, 20)
    icon:SetPoint("CENTER")
    icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
    local border = minimapButton:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetSize(54, 54)
    border:SetPoint("TOPLEFT")
    minimapButton:SetScript("OnClick", function(self)
        if self.suppressClick then self.suppressClick = nil; return end
        addon.ToggleUI()
    end)
    minimapButton:SetScript("OnDragStart", function(self)
        self.suppressClick = true
        GameTooltip:Hide()
        self:SetScript("OnUpdate", function()
            local x, y = GetCursorPosition()
            local centerX, centerY = Minimap:GetCenter()
            local scale = Minimap:GetEffectiveScale()
            addon.tracker.db.minimapAngle = math.deg(math.atan2(y / scale - centerY, x / scale - centerX))
            positionMinimap()
        end)
    end)
    minimapButton:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
        -- OnClick may follow OnDragStop in the same frame.
        C_Timer.After(0, function() self.suppressClick = nil end)
    end)
    minimapButton:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("BG Tracker", 1, 0.82, 0)
        GameTooltip:AddLine("Click to show match history.", 1, 1, 1)
        GameTooltip:AddLine("Drag to move around the minimap.", 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    minimapButton:SetScript("OnLeave", function() GameTooltip:Hide() end)
    positionMinimap()
end

local function rowTooltip(self)
    local match = self.match
    if not match then return end
    GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
    GameTooltip:AddLine(match.name, 1, 0.82, 0)
    GameTooltip:AddLine("HK honor: estimates reported by the game's honor messages.", 1, 1, 1, true)
    GameTooltip:AddLine("Additional: non-HK honor awarded while inside this BG.", 1, 1, 1, true)
    GameTooltip:AddLine("Duration: the game's battleground timer, including preparation if reported.", 0.8, 0.8, 0.8, true)
    if match.partial then
        GameTooltip:AddLine("Partial tracking: honor from before entry or while offline is unavailable.", 1, 0.75, 0.2, true)
    end
    if match.unparsedHonor then
        GameTooltip:AddLine("Some honor messages could not be read; totals may be incomplete.", 1, 0.55, 0.2, true)
    end
    if match.result == "Left" or match.result == "Interrupted" then
        GameTooltip:AddLine("The final result was not observed. This is not counted as a loss.", 0.8, 0.8, 0.8, true)
    elseif match.result == "Unknown" then
        GameTooltip:AddLine("Match ended, but your scoreboard team was unavailable.", 0.8, 0.8, 0.8, true)
    end
    GameTooltip:Show()
end

function addon.RefreshUI()
    if not window or not window:IsShown() then return end
    local matches = addon.tracker:GetRows()
    local pages = math.max(1, math.ceil(#matches / pageSize))
    page = math.max(1, math.min(page, pages))
    local wins, losses, total = 0, 0, 0
    for _, match in ipairs(matches) do
        if match.result == "Win" then wins = wins + 1 end
        if match.result == "Loss" then losses = losses + 1 end
        total = total + match.hkHonor + match.additionalHonor
    end
    window.summary:SetText(string.format("%d matches  |  %d wins / %d losses  |  %d honor recorded", #matches, wins, losses, total))
    window.pageLabel:SetText(string.format("Page %d / %d", page, pages))
    window.previous:SetEnabled(page > 1)
    window.next:SetEnabled(page < pages)
    window.empty:SetShown(#matches == 0)
    for i, row in ipairs(window.rows) do
        local match = matches[(page - 1) * pageSize + i]
        row.match = match
        row:SetShown(match ~= nil)
        if match then
            local color = colors[match.result] or colors.Unknown
            row.background:SetColorTexture(color[1], color[2], color[3], 0.15)
            row.accent:SetColorTexture(color[1], color[2], color[3], 0.95)
            local values = {
                date("%Y-%m-%d %H:%M", match.startedAt),
                match.name .. ((match.partial or match.unparsedHonor) and " *" or ""),
                addon.Tracker.FormatDuration(match.duration), match.hkHonor,
                match.additionalHonor, match.hkHonor + match.additionalHonor, match.result,
            }
            for j, cell in ipairs(row.cells) do
                cell:SetText(values[j])
                cell:SetTextColor(color[1], color[2], color[3])
            end
        end
    end
end

function addon.ToggleUI()
    if window:IsShown() then window:Hide() else window:Show() end
end

function addon.CreateUI()
    window = CreateFrame("Frame", "BGTrackerWindow", UIParent, "BackdropTemplate")
    window:SetSize(905, 510)
    window:SetPoint("CENTER")
    window:SetScale(math.min(1, (UIParent:GetWidth() - 40) / 905))
    window:SetFrameStrata("DIALOG")
    window:SetClampedToScreen(true)
    window:SetMovable(true)
    window:EnableMouse(true)
    window:RegisterForDrag("LeftButton")
    window:SetScript("OnDragStart", function(self) self:StartMoving() end)
    window:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    window:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    window:SetBackdropColor(0.055, 0.06, 0.075, 0.97)
    window:SetBackdropBorderColor(0.45, 0.40, 0.26, 1)
    local title = label(window, "BG Tracker", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 20, -18)
    window.summary = label(window, "")
    window.summary:SetPoint("TOPLEFT", 20, -47)
    local close = CreateFrame("Button", nil, window, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -5, -5)
    close:SetScript("OnClick", function() window:Hide() end)
    local x = 25
    for _, column in ipairs(columns) do
        local heading = label(window, column[1], "GameFontNormalSmall")
        heading:SetPoint("TOPLEFT", x, -83)
        heading:SetSize(column[2] - 10, 18)
        heading:SetJustifyH(column[3])
        x = x + column[2]
    end
    window.rows = {}
    for i = 1, pageSize do
        local row = CreateFrame("Frame", nil, window)
        row:SetPoint("TOPLEFT", 18, -108 - (i - 1) * 27)
        row:SetSize(869, 25)
        row:EnableMouse(true)
        row:SetScript("OnEnter", rowTooltip)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
        row.background = row:CreateTexture(nil, "BACKGROUND")
        row.background:SetAllPoints()
        row.accent = row:CreateTexture(nil, "ARTWORK")
        row.accent:SetPoint("TOPLEFT")
        row.accent:SetPoint("BOTTOMLEFT")
        row.accent:SetWidth(3)
        row.cells = {}
        x = 7
        for j, column in ipairs(columns) do
            local cell = label(row, "")
            cell:SetPoint("LEFT", x, 0)
            cell:SetSize(column[2] - 10, 23)
            cell:SetJustifyH(column[3])
            cell:SetWordWrap(false)
            row.cells[j] = cell
            x = x + column[2]
        end
        window.rows[i] = row
    end
    window.empty = label(window, "No battlegrounds recorded yet.\nJoin a battleground to start tracking automatically.", "GameFontHighlight")
    window.empty:SetPoint("CENTER", 0, 0)
    window.previous = button(window, "Previous", 85, function() page = page - 1; addon.RefreshUI() end)
    window.previous:SetPoint("BOTTOMLEFT", 20, 42)
    window.next = button(window, "Next", 85, function() page = page + 1; addon.RefreshUI() end)
    window.next:SetPoint("BOTTOMRIGHT", -20, 42)
    window.pageLabel = label(window, "")
    window.pageLabel:SetPoint("BOTTOM", 0, 48)
    local note = label(window, "Newest first  |  Hover a row for honor details  |  * Partial data  |  /bgt to toggle")
    note:SetPoint("BOTTOMLEFT", 20, 18)
    note:SetTextColor(0.6, 0.6, 0.65)
    window:EnableMouseWheel(true)
    window:SetScript("OnMouseWheel", function(_, delta)
        page = page + (delta < 0 and 1 or -1)
        addon.RefreshUI()
    end)
    window:SetScript("OnShow", addon.RefreshUI)
    window:Hide()
    UISpecialFrames[#UISpecialFrames + 1] = "BGTrackerWindow"
    createMinimapButton()
end
