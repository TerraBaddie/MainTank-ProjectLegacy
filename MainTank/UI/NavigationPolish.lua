-- MainTank v1.2.47 BOSSPROFILE2
-- Final release-facing button typography and Combat Highlights navigation.
-- Loaded after the historical UI stacks so presentation rules are authoritative
-- without disturbing parser, mitigation, persistence, or archive/history code.

local MT = MainTank

local NP_WHITE = 1.00
local NP_SELECTED = 0.48

-- MainTank has two historical button origins after the XML refactor:
-- XML-declared buttons and later Lua-created legacy buttons.  The latter may
-- inherit pfUI's configured global font size, which can be visibly larger than
-- the XML template font.  Treat Current as the canonical Main-page typography
-- and clone its exact font onto every text-bearing button.
local NP_FONT_FILE = nil
local NP_FONT_SIZE = nil
local NP_FONT_FLAGS = nil

local function NP_ButtonFontString(button)
    if not button or not button.GetFontString then return nil end
    return button:GetFontString()
end

local function NP_ReadButtonFont(button)
    if not button then return nil, nil, nil end
    if button.GetFont then
        local file, size, flags = button:GetFont()
        if file and size then return file, size, flags or "" end
    end
    local fs = NP_ButtonFontString(button)
    if fs and fs.GetFont then
        local file, size, flags = fs:GetFont()
        if file and size then return file, size, flags or "" end
    end
    return nil, nil, nil
end

local function NP_ResolveCanonicalFont(owner)
    local current = owner and owner.viewButtons and owner.viewButtons.CURRENT or nil
    local file, size, flags = NP_ReadButtonFont(current)
    if file and size then
        NP_FONT_FILE = file
        NP_FONT_SIZE = size
        NP_FONT_FLAGS = flags or ""
    end
end

local function NP_HasButtonText(button)
    if not button or not button.GetText then return false end
    local text = button:GetText()
    return text ~= nil and tostring(text) ~= ""
end

local function NP_ApplyCanonicalFont(button)
    if not NP_HasButtonText(button) then return end
    if not NP_FONT_FILE or not NP_FONT_SIZE then NP_ResolveCanonicalFont(MT) end
    if not NP_FONT_FILE or not NP_FONT_SIZE then return end

    if button.SetFont then
        button:SetFont(NP_FONT_FILE, NP_FONT_SIZE, NP_FONT_FLAGS or "")
    end
    local fs = NP_ButtonFontString(button)
    if fs and fs.SetFont then
        fs:SetFont(NP_FONT_FILE, NP_FONT_SIZE, NP_FONT_FLAGS or "")
    end
end

local function NP_SetButtonWhite(button)
    if not button then return end
    NP_ApplyCanonicalFont(button)
    if button.SetTextColor then button:SetTextColor(NP_WHITE, NP_WHITE, NP_WHITE) end
    if button.SetDisabledTextColor then button:SetDisabledTextColor(NP_WHITE, NP_WHITE, NP_WHITE) end
    local fontString = NP_ButtonFontString(button)
    if fontString and fontString.SetTextColor then
        fontString:SetTextColor(NP_WHITE, NP_WHITE, NP_WHITE)
    end
end

local function NP_SetSelectedTab(button)
    if not button then return end
    NP_ApplyCanonicalFont(button)
    -- Apply the selected color to both enabled and disabled text paths.  Most
    -- selectors are disabled while active, but this keeps the appearance stable
    -- if a historical wrapper temporarily changes enable state.
    if button.SetTextColor then button:SetTextColor(NP_SELECTED, NP_SELECTED, NP_SELECTED) end
    if button.SetDisabledTextColor then button:SetDisabledTextColor(NP_SELECTED, NP_SELECTED, NP_SELECTED) end
    local fontString = NP_ButtonFontString(button)
    if fontString and fontString.SetTextColor then
        fontString:SetTextColor(NP_SELECTED, NP_SELECTED, NP_SELECTED)
    end
end

local function NP_NormalizeButtonTree(frame)
    if not frame or not frame.GetChildren then return end
    local children = {frame:GetChildren()}
    local i, child
    for i = 1, table.getn(children) do
        child = children[i]
        if child and child.GetObjectType and child:GetObjectType() == "Button" then
            NP_SetButtonWhite(child)
        end
        NP_NormalizeButtonTree(child)
    end
end

function MT:ApplyUniformButtonText(frame)
    -- Resolve before walking the tree so late-created Compare/Fights/Export/Boss
    -- are forced to the exact same font family, size, and flags as Current.
    NP_ResolveCanonicalFont(self)
    NP_NormalizeButtonTree(frame)

    -- Current / Overall are a mutually-exclusive selector pair just like the
    -- RAW/Physical/Magic strip.  The selected view is grey; the other is white.
    if self.viewButtons then
        if self.currentView == "CURRENT" then
            NP_SetSelectedTab(self.viewButtons.CURRENT)
            NP_SetButtonWhite(self.viewButtons.OVERALL)
        elseif self.currentView == "OVERALL" then
            NP_SetButtonWhite(self.viewButtons.CURRENT)
            NP_SetSelectedTab(self.viewButtons.OVERALL)
        else
            -- A numbered saved fight is its own view, so neither selector is
            -- active while browsing that fight.
            NP_SetButtonWhite(self.viewButtons.CURRENT)
            NP_SetButtonWhite(self.viewButtons.OVERALL)
        end
    end

    -- RAW / Physical / Magic are mutually-exclusive tabs.
    local key, button
    for key, button in pairs(self.pageButtons or {}) do
        if key == self.currentPage then NP_SetSelectedTab(button)
        else NP_SetButtonWhite(button) end
    end

    -- The unified Fights browser is the other release-facing tab strip.
    local fights = self.fightsFrame or self.historyFrame or getglobal("MainTankHistoryFrame")
    local chrome = fights and fights.fightBrowserChrome
    if chrome then
        local tab = self.fightBrowserTab or "RECENT"
        if tab == "RECENT" then NP_SetSelectedTab(chrome.recentTab) else NP_SetButtonWhite(chrome.recentTab) end
        if tab == "ARCHIVE" then NP_SetSelectedTab(chrome.archiveTab) else NP_SetButtonWhite(chrome.archiveTab) end
        if tab == "HISTORY" then NP_SetSelectedTab(chrome.historyTab) else NP_SetButtonWhite(chrome.historyTab) end
    end
end

-- Reassert the selected-tab rule after page changes.
local NP_OldSetPage = MT.SetPage
function MT:SetPage(page)
    NP_OldSetPage(self, page)
    self:ApplyUniformButtonText(self.frame)
end

local NP_OldUpdateViewButtons = MT.UpdateViewButtons
function MT:UpdateViewButtons()
    NP_OldUpdateViewButtons(self)
    if self.frame then self:ApplyUniformButtonText(self.frame) end
end

local NP_OldUpdateFightBrowserTabs = MT.UpdateFightBrowserTabs
if NP_OldUpdateFightBrowserTabs then
    function MT:UpdateFightBrowserTabs(frame, tab)
        NP_OldUpdateFightBrowserTabs(self, frame, tab)
        self:ApplyUniformButtonText(frame)
    end
end

-- Back buttons are created lazily. Normalize them immediately so their text is
-- identical to MT Main rather than inheriting a later legacy grey.
local NP_OldEnsureBackButton = MT.EnsureBackButton
if NP_OldEnsureBackButton then
    function MT:EnsureBackButton(frame)
        NP_OldEnsureBackButton(self, frame)
        if frame and frame.mtBackButton then NP_SetButtonWhite(frame.mtBackButton) end
    end
end

-- Every managed page gets a final typography pass after historical styling,
-- page guards, Back navigation, and safe-dragging have finished their work.
local NP_OldShowManagedPage = MT.ShowManagedPage
function MT:ShowManagedPage(name, updater)
    local result = NP_OldShowManagedPage(self, name, updater)
    local frame = self.managedPages and self.managedPages[name or "MAIN"]
    if not frame and (name == nil or name == "MAIN") then frame = self.frame end
    if frame then self:ApplyUniformButtonText(frame) end
    return result
end

-- Mini/full reconciliation can run independently of page navigation.  Reapply
-- typography afterward so login, /reload, and mode toggles cannot expose the
-- older legacy font/color on late-created Main buttons.
local NP_OldReconcileMainWindowMode = MT.ReconcileMainWindowMode
if NP_OldReconcileMainWindowMode then
    function MT:ReconcileMainWindowMode()
        NP_OldReconcileMainWindowMode(self)
        if self.frame then self:ApplyUniformButtonText(self.frame) end
    end
end

-- Timeline and Pie use one cycling action button (View: RAW / PHYSICAL / MAGIC),
-- not a selected tab strip.  Older RC6P refresh code historically repainted
-- this button gold after interaction.  Reassert the release rule after the
-- complete historical update chain so initial render, cycling, /reload, and
-- revisiting the page all remain white.
local NP_OldUpdatePieWindow = MT.UpdatePieWindow
function MT:UpdatePieWindow()
    local result = NP_OldUpdatePieWindow(self)
    if self.pieFrame and self.pieFrame.modeButton then
        NP_SetButtonWhite(self.pieFrame.modeButton)
    end
    return result
end

local NP_OldUpdateTimelineWindow = MT.UpdateTimelineWindow
function MT:UpdateTimelineWindow()
    local result = NP_OldUpdateTimelineWindow(self)
    if self.timelineFrame and self.timelineFrame.modeButton then
        NP_SetButtonWhite(self.timelineFrame.modeButton)
    end
    return result
end

-- ==========================================================================
-- Combat Highlights
-- "Biggest Hits" was too narrow: this view also surfaces armor reduction,
-- blocks, resists, and avoided attacks.  Keep the proven BIGGEST internal page
-- identity for compatibility while presenting it as Combat Highlights.
-- ==========================================================================

local NP_HIGHLIGHT_LABELS = {
    "Largest RAW Hit",
    "Largest Hit Taken",
    "Largest Armor Reduction",
    "Largest Block",
    "Largest Resist",
    "Largest Avoided Hit",
    "Largest Crit / Crush Hit"
}

function MT:OpenHighlightedEventDetails()
    local event = self.biggestSelectedEvent
    if not event then return end

    -- The combined Crit/Crush highlight is intentionally an encounter-wide
    -- gateway: Events opens with one authoritative filter over the saved event
    -- flags, showing every Critical or Crushing event in this fight.
    if self.biggestSelectedFilterKind == "CRIT_CRUSH" then
        self.detailsFilter = {kind = "CRIT_CRUSH", label = "Critical / Crushing"}
        self.detailsSelectedEnemy = nil
        self.detailsEnemyPage = 1
        self.detailsAbilityPage = 1
        self.detailsEventPage = 1
        self.detailsSelectedEvent = nil
        self:CreateDetailsWindow()
        self:ShowManagedPage("DETAILS", function(owner) owner:UpdateDetailsWindow() end)
        return
    end

    -- Every other highlight retains the established exact-event behavior.
    self.detailsFilter = nil
    self.detailsSelectedEnemy = event.source or "Unknown"
    self.detailsEnemyPage = 1
    self.detailsAbilityPage = 1

    local events = self:GetFilteredDetailEvents() or {}
    local index = 1
    local i
    for i = 1, table.getn(events) do
        if events[i] == event then index = i; break end
    end
    self.detailsSelectedEvent = index
    self.detailsEventPage = index

    self:CreateDetailsWindow()
    self:ShowManagedPage("DETAILS", function(owner) owner:UpdateDetailsWindow() end)
end

local NP_OldCreateBiggestWindow = MT.CreateBiggestWindow
function MT:CreateBiggestWindow()
    local frame = NP_OldCreateBiggestWindow(self)
    if not frame or frame.npHighlightsPolished then return frame end
    if frame.title then frame.title:SetText("Combat Highlights") end

    -- Give each two-line category card enough internal leading that its heading
    -- and event line no longer visually touch on Vanilla's small outlined font.
    local i, row
    for i = 1, table.getn(frame.rows or {}) do
        row = frame.rows[i]
        row:ClearAllPoints()
        row:SetWidth(272)
        -- Vanilla's outlined small font needs a little more leading than the
        -- previous 21px card allowed.  Keep the 300x231 window unchanged and
        -- give each two-line card 23px so heading/source glyphs never touch.
        row:SetHeight(23)
        row:SetPoint("TOPLEFT", frame, "TOPLEFT", 14, -31 - ((i - 1) * 23))
        if row.label then
            row.label:ClearAllPoints()
            row.label:SetPoint("TOPLEFT", row, "TOPLEFT", 3, -1)
            row.label:SetWidth(190)
            row.label:SetJustifyH("LEFT")
        end
        if row.value then
            row.value:ClearAllPoints()
            row.value:SetPoint("TOPRIGHT", row, "TOPRIGHT", -3, -1)
            row.value:SetJustifyH("RIGHT")
        end
        if row.source then
            row.source:ClearAllPoints()
            row.source:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 3, 1)
            row.source:SetWidth(264)
            row.source:SetJustifyH("LEFT")
        end
        -- Final presentation layer owns only the selection intent.  Normal
        -- highlights still select one exact event; the combined Crit/Crush row
        -- selects the encounter-wide flag filter consumed by Events.
        row:SetScript("OnClick", function()
            if not this.entry or not this.entry.event then return end
            if this.entry.filterKind == "CRIT_CRUSH" then
                MT.biggestSelectedFilterKind = "CRIT_CRUSH"
                MT.biggestSelectedEvent = this.entry.event
                local second = math.floor(this.entry.event.time or 0)
                MT.timelineSelection = {firstSecond=second, lastSecond=second, mode=MT.timelineMode or "RAW"}
                MT:UpdateBiggestWindow()
            else
                MT.biggestSelectedFilterKind = nil
                MT:JumpToEvent(this.entry.event)
            end
        end)
    end

    -- Replace the plain "Selected Event" label with a real action button.
    if frame.inspectorHeader then frame.inspectorHeader:Hide() end
    frame.viewEventButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.viewEventButton:SetWidth(118)
    frame.viewEventButton:SetHeight(18)
    frame.viewEventButton:SetPoint("TOPLEFT", frame, "TOPLEFT", 14, -193)
    frame.viewEventButton:SetText("View Event Details")
    frame.viewEventButton:SetScript("OnClick", function() MT:OpenHighlightedEventDetails() end)
    frame.viewEventButton:SetScript("OnEnter", function()
        if not MT.biggestSelectedEvent then return end
        local tip = MT:GetAnalysisTooltip()
        tip:SetOwner(this, "ANCHOR_LEFT")
        tip:SetText("View Event Details", 1, 0.82, 0)
        if MT.biggestSelectedFilterKind == "CRIT_CRUSH" then
            tip:AddLine("Open all Critical and Crushing events in Events.", 0.85, 0.85, 0.85)
        else
            tip:AddLine("Open this exact combat event in Events.", 0.85, 0.85, 0.85)
        end
        tip:AddLine("Back returns to Combat Highlights.", 0.85, 0.85, 0.85)
        tip:Show()
    end)
    frame.viewEventButton:SetScript("OnLeave", function() MT:HideAnalysisTooltip() end)
    if self.ApplyLegacyButtonStyle then self:ApplyLegacyButtonStyle(frame.viewEventButton) end
    NP_SetButtonWhite(frame.viewEventButton)
    frame.viewEventButton:Hide()

    if frame.inspector then
        frame.inspector:ClearAllPoints()
        frame.inspector:SetPoint("TOPLEFT", frame, "TOPLEFT", 14, -213)
        frame.inspector:SetWidth(272)
        frame.inspector:SetHeight(17)
        frame.inspector:SetJustifyH("LEFT")
        frame.inspector:SetJustifyV("TOP")
    end

    frame.npHighlightsPolished = true
    self:ApplyUniformButtonText(frame)
    return frame
end

local function NP_HighlightEventIsCurrent(owner, target)
    if not target then return false end
    local events = owner:GetDisplayEvents() or {}
    local i
    for i = 1, table.getn(events) do
        if events[i] == target then return true end
    end
    return false
end

local NP_HIGHLIGHT_EMPTY_SOURCE = {
    "No RAW hit recorded",
    "No damage-taken hit recorded",
    "No armor reduction recorded",
    "No blocked hit recorded",
    "No resisted hit recorded",
    "No avoided hit recorded",
    "No Critical / Crushing events"
}

local NP_OldUpdateBiggestWindow = MT.UpdateBiggestWindow
function MT:UpdateBiggestWindow()
    -- A selected event belongs to one exact detailed fight.  Clear it before
    -- the historical update chain runs if the user changed fights; otherwise
    -- the inspector/button can display a stale event from the previous fight.
    if self.biggestSelectedEvent and not NP_HighlightEventIsCurrent(self, self.biggestSelectedEvent) then
        self.biggestSelectedEvent = nil
        self.biggestSelectedFilterKind = nil
    end

    NP_OldUpdateBiggestWindow(self)
    local frame = self.biggestFrame
    if not frame then return end

    if frame.title then frame.title:SetText("Combat Highlights - " .. self:GetViewLabel()) end

    local i, row, entry, hasMeaningfulEvent
    for i = 1, table.getn(frame.rows or {}) do
        row = frame.rows[i]
        entry = row and row.entry or nil
        if row and row.label and NP_HIGHLIGHT_LABELS[i] then
            row.label:SetText(NP_HIGHLIGHT_LABELS[i])
        end

        -- Keep all seven cards in a clean continuous stack.  The legacy view
        -- hid zero-value categories, which left conspicuous holes whenever a
        -- fight had no Resist or no Crit/Crush.  Empty cards are now explicit
        -- non-clickable placeholders instead of missing geometry.
        hasMeaningfulEvent = false
        if entry and entry.event then
            if entry.filterKind == "CRIT_CRUSH" then
                hasMeaningfulEvent = true
            elseif (tonumber(entry.value) or 0) > 0 then
                hasMeaningfulEvent = true
            end
        end

        if row and not hasMeaningfulEvent then
            row.entry = nil
            row.value:SetText(i == 7 and "0 / 0" or "0")
            row.source:SetText(NP_HIGHLIGHT_EMPTY_SOURCE[i] or "No matching event")
            if row.selected then row.selected:Hide() end
            if row.highlight then row.highlight:Hide() end
            row:Show()
        elseif row and entry and entry.filterKind == "CRIT_CRUSH" then
            -- A Crit/Crush event may legitimately have zero Taken after full
            -- prevention.  The authoritative event flag still makes the row
            -- meaningful, so show the paired values even if both are zero.
            row.value:SetText(self:FormatNumber(entry.critValue or 0) .. " / " .. self:FormatNumber(entry.crushValue or 0))
            row.source:SetText(entry.sourceText or "All Critical / Crushing events")
            row:Show()
        end

        if row and row.selected and self.biggestSelectedFilterKind == "CRIT_CRUSH" then
            if row.entry and row.entry.filterKind == "CRIT_CRUSH" then row.selected:Show() else row.selected:Hide() end
        end
    end

    if frame.inspectorHeader then frame.inspectorHeader:Hide() end
    if frame.viewEventButton then
        if self.biggestSelectedEvent then frame.viewEventButton:Show()
        else frame.viewEventButton:Hide() end
        NP_SetButtonWhite(frame.viewEventButton)
    end
    if frame.inspector and not self.biggestSelectedEvent then
        frame.inspector:SetText("Select a highlight above to inspect its damage flow.")
    end
    self:ApplyUniformButtonText(frame)
end

-- ==========================================================================
-- Events presentation
-- Keep the proven DETAILS internal page identity/function chain, but present
-- the player-facing analysis as Events. This avoids overloading the generic
-- word "Details" while preserving every historical navigation contract.
-- ==========================================================================

local NP_OldCreateDetailsWindow = MT.CreateDetailsWindow
function MT:CreateDetailsWindow()
    local frame = NP_OldCreateDetailsWindow(self)
    if frame and frame.title then frame.title:SetText("Events") end
    return frame
end

local NP_OldUpdateDetailsWindow = MT.UpdateDetailsWindow
function MT:UpdateDetailsWindow()
    local result = NP_OldUpdateDetailsWindow(self)
    local frame = self.detailsFrame
    if frame and frame.title then
        local text = frame.title:GetText() or "Events"
        text = string.gsub(text, "^Mitigation Details", "Events")
        text = string.gsub(text, "^Details", "Events")
        frame.title:SetText(text)
    end
    return result
end

-- Final CreateUI pass: rename the release-facing action and normalize every
-- Main button only after Compare/Fights/Export/Boss have all been created.
local NP_OldCreateUI = MT.CreateUI
function MT:CreateUI()
    NP_OldCreateUI(self)
    local frame = self.frame
    if not frame then return end

    local biggest = getglobal("MainTankFrameBiggestButton")
    if not biggest and self.fullControls then biggest = self.fullControls[2] end
    if biggest then biggest:SetText("Highlights") end

    local eventsButton = getglobal("MainTankFrameDetailsButton")
    if not eventsButton and self.fullControls then eventsButton = self.fullControls[3] end
    if eventsButton then eventsButton:SetText("Events") end

    self:ApplyUniformButtonText(frame)
end
