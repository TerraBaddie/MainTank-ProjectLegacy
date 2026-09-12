-- MainTank REFAC1 - Back navigation and legacy public bridge
-- Final historical layer from Engine.lua; must load after Core/Mitigation.lua.

local MT = MainTank
local E = MT._engine
local StyleLegacyButton = E.StyleLegacyButton
local FinalizeLegacyWindow = E.FinalizeLegacyWindow
local Print = E.Print
local CalculateBlockValue = E.CalculateBlockValue

-- ============================================================================
-- FR1P module bridge
-- ============================================================================
-- The historical engine keeps private lexical helpers for compatibility.
-- New modules consume these narrow public adapters instead of reaching across
-- file boundaries for locals. This is the key rule that makes gradual Lua 5.0
-- modularization safe.
function MT:PrintMessage(msg)
    Print(msg)
end

function MT:ApplyLegacyButtonStyle(button)
    StyleLegacyButton(button)
end

-- UI modules can request the exact same pfUI/Blizzard window treatment
-- without reaching across Engine.lua's private lexical helpers.
function MT:ApplyLegacyWindowStyle(frame)
    FinalizeLegacyWindow(frame)
end

function MT:LoadInventoryTooltip(slot)
    if RC6J_LoadInventoryTooltip then
        return RC6J_LoadInventoryTooltip(slot)
    end
    return {}, "none"
end

-- Default adapter. Modules/BlockAnalysis.lua replaces this with the finalized
-- bounded FR1i scanner without modifying RefreshBlockValue's lexical scope.
function MT:CalculateBlockValue()
    return CalculateBlockValue()
end


-- ============================================================================
-- MainTank Back Navigation v1
-- Adds a stateful Back button only when analysis navigation moves beyond the
-- first page opened from Main.  MT Main remains the direct escape to Main.
-- The history snapshot preserves view/mode/page/filter state so returning from
-- Details restores the exact Timeline/Pie/Biggest context that opened it.
-- ============================================================================

function MT:BackNavCopyTable(source)
    if type(source) ~= "table" then return source end
    local copy = {}
    local key, value
    for key, value in pairs(source) do copy[key] = value end
    return copy
end

function MT:CaptureBackNavState(pageName)
    return {
        pageName = pageName,
        currentView = self.currentView,
        currentPage = self.currentPage,
        timelineMode = self.timelineMode,
        timelinePage = self.timelinePage,
        pieMode = self.pieMode,
        detailsFilter = self:BackNavCopyTable(self.detailsFilter),
        detailsSelectedEnemy = self.detailsSelectedEnemy,
        detailsEnemyPage = self.detailsEnemyPage,
        detailsAbilityPage = self.detailsAbilityPage,
        detailsEventPage = self.detailsEventPage,
        detailsSelectedEvent = self.detailsSelectedEvent,
        timelineSelection = self:BackNavCopyTable(self.timelineSelection)
    }
end

function MT:RestoreBackNavState(state)
    if not state then return end
    self.currentView = state.currentView or self.currentView
    self.currentPage = state.currentPage or self.currentPage
    self.timelineMode = state.timelineMode or self.timelineMode
    self.timelinePage = tonumber(state.timelinePage) or 0
    self.pieMode = state.pieMode or self.pieMode
    self.detailsFilter = self:BackNavCopyTable(state.detailsFilter)
    self.detailsSelectedEnemy = state.detailsSelectedEnemy
    self.detailsEnemyPage = tonumber(state.detailsEnemyPage) or 1
    self.detailsAbilityPage = tonumber(state.detailsAbilityPage) or 1
    self.detailsEventPage = tonumber(state.detailsEventPage) or 1
    self.detailsSelectedEvent = state.detailsSelectedEvent
    self.timelineSelection = self:BackNavCopyTable(state.timelineSelection)
end

function MT:EnsureBackButton(frame)
    if not frame or frame == self.frame or frame.mtBackButton then return end
    local button = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    button:SetWidth(38)
    button:SetHeight(18)
    button:SetPoint("TOPLEFT", frame, "TOPLEFT", 67, -6)
    button:SetText("Back")
    button:SetScript("OnClick", function() MT:NavigateBack() end)
    if self.ApplyLegacyButtonStyle then self:ApplyLegacyButtonStyle(button) end
    button:Hide()
    frame.mtBackButton = button
end

function MT:LayoutDetailsHeader()
    local frame = self.detailsFrame
    if not frame or not frame.title then return end

    frame.title:ClearAllPoints()
    if frame.mtBackButton and frame.mtBackButton:IsVisible() and self.currentManagedPage == "DETAILS" then
        -- BACK4: the Back button is shown by UpdateBackButtonState *after* the
        -- Details updater runs.  Earlier BACK1-3 checked visibility too early,
        -- so the title was restored to its centered/default anchor before Back
        -- became visible.  Anchor only after the button's final visibility is
        -- known, using TOP edges so Vanilla 1.12 cannot reinterpret the vertical
        -- center while the button template changes its rendered bounds.
        frame.title:SetPoint("TOPLEFT", frame.mtBackButton, "TOPRIGHT", 10, -3)
        frame.title:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -25, -9)
        frame.title:SetJustifyH("LEFT")
    else
        frame.title:SetPoint("TOPLEFT", frame, "TOPLEFT", 68, -9)
        frame.title:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -25, -9)
        frame.title:SetJustifyH("CENTER")
    end
end

function MT:UpdateBackButtonState()
    self:RefreshManagedPageRegistry()
    local hasHistory = self.backNavHistory and table.getn(self.backNavHistory) > 0
    local name, frame
    for name, frame in pairs(self.managedPages or {}) do
        if frame and name ~= "MAIN" then
            self:EnsureBackButton(frame)
            if frame.mtBackButton then
                if hasHistory and name == self.currentManagedPage then
                    frame.mtBackButton:Show()
                else
                    frame.mtBackButton:Hide()
                end
            end
        end
    end

    -- The header must be laid out AFTER Back's visibility has been finalized.
    self:LayoutDetailsHeader()
end

function MT:RefreshBackDestination(pageName)
    if pageName == "TIMELINE" then
        if self.UpdateTimelineWindow then self:UpdateTimelineWindow() end
    elseif pageName == "PIE" then
        if self.UpdatePieWindow then self:UpdatePieWindow() end
    elseif pageName == "DETAILS" then
        if self.UpdateDetailsWindow then self:UpdateDetailsWindow() end
    elseif pageName == "BIGGEST" then
        if self.UpdateBiggestWindow then self:UpdateBiggestWindow() end
    elseif pageName == "MAIN" then
        if self.SetPage then self:SetPage(self.currentPage or "RAW") end
        if self.UpdateDisplay then self:UpdateDisplay() end
    end
end

function MT:NavigateBack()
    if not self.backNavHistory or table.getn(self.backNavHistory) == 0 then return end
    local index = table.getn(self.backNavHistory)
    local state = self.backNavHistory[index]
    table.remove(self.backNavHistory, index)
    self:RestoreBackNavState(state)
    self.backNavSuppressPush = true
    self:ShowManagedPage(state.pageName or "MAIN")
    self.backNavSuppressPush = nil
    self:RefreshBackDestination(state.pageName or "MAIN")
    self:UpdateBackButtonState()
end

MT.backNavHistory = MT.backNavHistory or {}

MT_BackNavPreviousRegisterManagedPage = MT.RegisterManagedPage
function MT:RegisterManagedPage(name, frame)
    MT_BackNavPreviousRegisterManagedPage(self, name, frame)
    if name ~= "MAIN" then self:EnsureBackButton(frame) end
end

MT_BackNavPreviousShowManagedPage = MT.ShowManagedPage
function MT:ShowManagedPage(name, updater)
    name = name or "MAIN"
    local sourceName = self.currentManagedPage or "MAIN"

    if name == "MAIN" then
        self.backNavHistory = {}
    elseif not self.backNavSuppressPush and sourceName ~= "MAIN" and sourceName ~= name then
        self.backNavHistory = self.backNavHistory or {}
        table.insert(self.backNavHistory, self:CaptureBackNavState(sourceName))
    end

    MT_BackNavPreviousShowManagedPage(self, name, updater)
    self:UpdateBackButtonState()
end

-- Shorter title leaves room for [MT Main] [Back] while retaining the encounter
-- and filter context supplied by all earlier Details update layers.
MT_BackNavPreviousUpdateDetailsWindow = MT.UpdateDetailsWindow
function MT:UpdateDetailsWindow()
    MT_BackNavPreviousUpdateDetailsWindow(self)
    local frame = self.detailsFrame
    if not frame or not frame.title then return end
    local text = frame.title:GetText() or "Mitigation Details"
    text = string.gsub(text, "^Mitigation Details", "Details")
    frame.title:SetText(text)
    -- Do not decide the Back-aware anchor here. ShowManagedPage has not yet
    -- finished making the Back button visible at this point. UpdateBackButtonState
    -- performs the final header layout immediately afterward.
    self:LayoutDetailsHeader()
end
