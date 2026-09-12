-- MainTank v1.2.35 FIGHTBROWSER2
-- Unified player-facing browser for the final three-layer persistence model:
--   Recent (8 detailed) -> Archive (8 priority detailed) -> History (64 summary)
--
-- The proven persistence/restore code remains in Modules/Consolidation.lua.
-- This file is UI/navigation only, apart from calling the existing public
-- RestoreArchivedFight operation when the player explicitly presses Restore.

if not MainTank then return end
local MT = MainTank
local format = string.format

local FB_RECENT_LIMIT = 8
local FB_ARCHIVE_LIMIT = 8
local FB_LIST_HEIGHT = 231

local function FB_N(n)
    if MT.FormatNumber then return MT:FormatNumber(tonumber(n) or 0) end
    return tostring(math.floor((tonumber(n) or 0) + 0.5))
end

local function FB_Truncate(text, limit)
    text = tostring(text or "Unknown")
    limit = tonumber(limit) or 18
    if string.len(text) > limit then return string.sub(text, 1, limit - 1) .. "~" end
    return text
end

local function FB_FightRaw(fight)
    if type(fight) ~= "table" then return 0 end
    local d = fight.data or {}
    local raw = tonumber(d.rawIncoming) or tonumber(d.raw) or tonumber(fight.raw)
    if raw ~= nil then return raw end
    raw = 0
    local i, e
    for i = 1, table.getn(fight.events or {}) do
        e = fight.events[i]
        raw = raw + (tonumber(e and e.raw) or 0)
    end
    return raw
end

local function FB_HistoryPct(summary)
    if type(summary) ~= "table" then return 0 end
    local raw = tonumber(summary.raw) or 0
    if raw <= 0 then return 0 end
    local stopped = tonumber(summary.stopped)
    if stopped == nil then
        stopped = raw - (tonumber(summary.taken) or 0)
    end
    if stopped < 0 then stopped = 0 end
    return (stopped / raw) * 100
end

local function FB_Tag(fight, raw, priority)
    if type(fight) == "table" then
        if fight.combatType == "PVP" or fight.pvp == true then return "PvP" end
        if fight.isBoss == true then return "BOSS" end
    end
    priority = tonumber(priority)
    if priority == 1 then return "PvP" end
    if priority == 4 then return "BOSS" end
    if priority == 3 then return "MAJOR" end
    if (tonumber(raw) or 0) >= 50000 then return "MAJOR" end
    return "MINOR"
end

local function FB_Style(button)
    if button and MT.ApplyLegacyButtonStyle then MT:ApplyLegacyButtonStyle(button) end
end

local function FB_HistorySummaries(owner)
    if owner.GetExternalHistoryProfile then
        local hp = owner:GetExternalHistoryProfile(true)
        if hp and type(hp.summaries) == "table" then return hp.summaries end
    end
    return {}
end

local function FB_HideObject(object)
    if object and object.Hide then object:Hide() end
end


local function FB_HideLegacyHistory(frame)
    if not frame then return end
    local i
    for i = 1, table.getn(frame.rows or {}) do FB_HideObject(frame.rows[i]) end
    FB_HideObject(frame.capacity)
    FB_HideObject(frame.prev)
    FB_HideObject(frame.next)
    FB_HideObject(frame.pageText)
    FB_HideObject(frame.backList)
    FB_HideObject(frame.detailHeader)
    FB_HideObject(frame.detailMeta)
    FB_HideObject(frame.grid)
    FB_HideObject(frame.magicHeader)
    FB_HideObject(frame.estHeader)
    FB_HideObject(frame.countsButton)
    FB_HideObject(frame.countsDetail)
end

local function FB_PositionListTitle(frame)
    if not frame or not frame.title then return end
    frame.title:ClearAllPoints()
    frame.title:SetPoint("TOPLEFT", frame, "TOPLEFT", 68, -9)
    frame.title:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -25, -9)
    frame.title:SetJustifyH("CENTER")
end

local function FB_RefreshManifest(owner)
    if owner.RefreshStorageManifestsForUI then
        return owner:RefreshStorageManifestsForUI()
    end
    local p = owner.profile or {}
    return p.archiveManifest or {}, p.historyManifest or {}
end

function MT:CreateFightBrowserChrome(frame)
    if not frame or frame.fightBrowserChrome then return frame and frame.fightBrowserChrome end

    local chrome = CreateFrame("Frame", "MainTankFightBrowserChrome", frame, "MainTankFightBrowserChromeTemplate")
    chrome:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)

    chrome.recentTab = getglobal("MainTankFightBrowserChromeRecentTab")
    chrome.archiveTab = getglobal("MainTankFightBrowserChromeArchiveTab")
    chrome.historyTab = getglobal("MainTankFightBrowserChromeHistoryTab")
    chrome.capacity = getglobal("MainTankFightBrowserChromeCapacity")
    chrome.capacity:SetJustifyH("CENTER")

    chrome.recentTab:SetScript("OnClick", function() MT:SetFightBrowserTab("RECENT") end)
    chrome.archiveTab:SetScript("OnClick", function() MT:SetFightBrowserTab("ARCHIVE") end)
    chrome.historyTab:SetScript("OnClick", function() MT:SetFightBrowserTab("HISTORY") end)
    FB_Style(chrome.recentTab)
    FB_Style(chrome.archiveTab)
    FB_Style(chrome.historyTab)

    chrome.recentRows = {}
    local i, row
    for i = 1, FB_RECENT_LIMIT do
        row = CreateFrame("Button", "MainTankFightBrowserRecentRow" .. i, chrome, "MainTankFightBrowserRecentRowTemplate")
        row:SetPoint("TOPLEFT", chrome, "TOPLEFT", 15, -69 - ((i - 1) * 19))
        row.indexText = getglobal("MainTankFightBrowserRecentRow" .. i .. "Index")
        row.tagText = getglobal("MainTankFightBrowserRecentRow" .. i .. "Tag")
        row.nameText = getglobal("MainTankFightBrowserRecentRow" .. i .. "Name")
        row.rawText = getglobal("MainTankFightBrowserRecentRow" .. i .. "Raw")
        row.indexText:SetJustifyH("RIGHT")
        row.tagText:SetJustifyH("LEFT")
        row.nameText:SetJustifyH("LEFT")
        row.rawText:SetJustifyH("RIGHT")
        row:SetText("")
        row:SetScript("OnClick", function()
            if this.fightIndex then MT:OpenRecentFightFromBrowser(this.fightIndex) end
        end)
        row:SetScript("OnEnter", function()
            local fight = this.fight
            if not fight then return end
            local tip = MT:GetAnalysisTooltip()
            tip:SetOwner(this, "ANCHOR_CURSOR")
            tip:SetText(tostring(fight.label or "Saved Fight"), 1, 0.82, 0)
            tip:AddLine(FB_Tag(fight, FB_FightRaw(fight)) .. "  |  DETAILED", 0.85, 0.85, 0.85)
            tip:AddLine("RAW " .. FB_N(FB_FightRaw(fight)) .. "  |  " .. format("%.1fs", tonumber(fight.duration) or 0), 1, 1, 1)
            tip:AddLine("Click to view this detailed fight on Main.", 0.65, 0.85, 1)
            tip:Show()
        end)
        row:SetScript("OnLeave", function() MT:HideAnalysisTooltip() end)
        FB_Style(row)
        chrome.recentRows[i] = row
    end

    chrome.archiveRows = {}
    for i = 1, FB_ARCHIVE_LIMIT do
        row = CreateFrame("Frame", "MainTankFightBrowserArchiveRow" .. i, chrome, "MainTankFightBrowserArchiveRowTemplate")
        row:SetPoint("TOPLEFT", chrome, "TOPLEFT", 15, -69 - ((i - 1) * 19))
        row.indexText = getglobal("MainTankFightBrowserArchiveRow" .. i .. "Index")
        row.tagText = getglobal("MainTankFightBrowserArchiveRow" .. i .. "Tag")
        row.nameText = getglobal("MainTankFightBrowserArchiveRow" .. i .. "Name")
        row.rawText = getglobal("MainTankFightBrowserArchiveRow" .. i .. "Raw")
        row.restore = getglobal("MainTankFightBrowserArchiveRow" .. i .. "Restore")
        row.indexText:SetJustifyH("RIGHT")
        row.tagText:SetJustifyH("LEFT")
        row.nameText:SetJustifyH("LEFT")
        row.rawText:SetJustifyH("RIGHT")
        row.restore:SetText("Restore")
        row.restore:SetScript("OnClick", function()
            local index = this.archiveIndex
            if not index then return end
            if MT:RestoreArchivedFight(index) then
                MT.fightBrowserTab = "RECENT"
                MT.historyBrowserMode = "LIST"
                MT:UpdateHistoryWindow()
            end
        end)
        row.restore:SetScript("OnEnter", function()
            if not this.archiveEntry then return end
            local tip = MT:GetAnalysisTooltip()
            tip:SetOwner(this, "ANCHOR_CURSOR")
            tip:SetText("Restore archived fight", 1, 0.82, 0)
            tip:AddLine(tostring(this.archiveEntry.label or "Unknown"), 0.85, 0.85, 0.85)
            tip:AddLine("Moves this detailed fight back into Recent.", 0.65, 0.85, 1)
            tip:AddLine("If Recent is full, its oldest fight follows normal Archive priority rules.", 1, 0.82, 0)
            tip:Show()
        end)
        row.restore:SetScript("OnLeave", function() MT:HideAnalysisTooltip() end)
        FB_Style(row.restore)
        row:EnableMouse(true)
        row:SetScript("OnEnter", function()
            if not this.archiveEntry then return end
            local e = this.archiveEntry
            local tip = MT:GetAnalysisTooltip()
            tip:SetOwner(this, "ANCHOR_CURSOR")
            tip:SetText(tostring(e.label or "Archived Fight"), 1, 0.82, 0)
            tip:AddLine(FB_Tag(e, e.raw, e.priority) .. "  |  DETAILED ARCHIVE", 0.85, 0.85, 0.85)
            if e.raw ~= nil then tip:AddLine("RAW " .. FB_N(e.raw), 1, 1, 1) end
            tip:AddLine("Use Restore to return this fight to Recent.", 0.65, 0.85, 1)
            tip:Show()
        end)
        row:SetScript("OnLeave", function() MT:HideAnalysisTooltip() end)
        chrome.archiveRows[i] = row
    end

    frame.fightBrowserChrome = chrome
    chrome:Hide()

    -- History list rows used to begin directly below the title.  In the unified
    -- browser they sit below the three tabs.  Detail/More Info geometry is not
    -- moved at all and therefore retains the proven HIST64UI14 layout.
    for i = 1, table.getn(frame.rows or {}) do
        row = frame.rows[i]
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", frame, "TOPLEFT", 15, -67 - ((i - 1) * 19))

        local columns = CreateFrame("Frame", "MainTankFightBrowserHistoryColumns" .. i, row, "MainTankFightBrowserHistoryColumnsTemplate")
        columns:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
        columns.indexText = getglobal("MainTankFightBrowserHistoryColumns" .. i .. "Index")
        columns.tagText = getglobal("MainTankFightBrowserHistoryColumns" .. i .. "Tag")
        columns.nameText = getglobal("MainTankFightBrowserHistoryColumns" .. i .. "Name")
        columns.rawText = getglobal("MainTankFightBrowserHistoryColumns" .. i .. "Raw")
        columns.pctText = getglobal("MainTankFightBrowserHistoryColumns" .. i .. "Pct")
        columns.indexText:SetJustifyH("RIGHT")
        columns.tagText:SetJustifyH("LEFT")
        columns.nameText:SetJustifyH("LEFT")
        columns.rawText:SetJustifyH("RIGHT")
        columns.pctText:SetJustifyH("RIGHT")
        row.fightBrowserColumns = columns
        row:SetText("")
    end

    return chrome
end

local FB_OldCreateHistoryWindow = MT.CreateHistoryWindow
function MT:CreateHistoryWindow()
    local frame = FB_OldCreateHistoryWindow(self)
    self:CreateFightBrowserChrome(frame)
    self.fightsFrame = frame
    return frame
end

function MT:GetFightBrowserCounts()
    local archiveManifest = FB_RefreshManifest(self)
    local summaries = FB_HistorySummaries(self)
    return table.getn(self.fights or {}), table.getn(archiveManifest or {}), table.getn(summaries or {})
end

function MT:UpdateFightBrowserTabs(frame, tab)
    if not frame or not frame.fightBrowserChrome then return end
    local chrome = frame.fightBrowserChrome
    local recentCount, archiveCount, historyCount = self:GetFightBrowserCounts()
    chrome.recentTab:SetText("Recent " .. recentCount .. "/8")
    chrome.archiveTab:SetText("Archive " .. archiveCount .. "/8")
    chrome.historyTab:SetText("History " .. historyCount .. "/64")

    local buttons = {
        RECENT = chrome.recentTab,
        ARCHIVE = chrome.archiveTab,
        HISTORY = chrome.historyTab
    }
    local name, button
    for name, button in pairs(buttons) do
        if name == tab then button:Disable() else button:Enable() end
    end
end

function MT:UpdateRecentFightBrowser(frame)
    local chrome = frame.fightBrowserChrome
    local fights = self.fights or {}
    local i, fight, row, raw, tag, label
    chrome.capacity:SetText("Detailed fights  |  click a row to view")

    for i = 1, FB_RECENT_LIMIT do
        row = chrome.recentRows[i]
        fight = fights[i]
        row.fightIndex = nil
        row.fight = nil
        if fight then
            raw = FB_FightRaw(fight)
            tag = FB_Tag(fight, raw)
            label = FB_Truncate(fight.label or ("Fight " .. i), 20)
            row:SetText("")
            row.indexText:SetText("R" .. i)
            row.tagText:SetText(tag)
            row.nameText:SetText(label)
            row.rawText:SetText(FB_N(raw))
            row.fightIndex = i
            row.fight = fight
            row:Enable()
            row:Show()
        else
            row:SetText("")
            row.indexText:SetText("")
            row.tagText:SetText("")
            row.nameText:SetText("")
            row.rawText:SetText("")
            row:Disable()
            row:Hide()
        end
    end

    for i = 1, FB_ARCHIVE_LIMIT do FB_HideObject(chrome.archiveRows[i]) end
end

function MT:UpdateArchiveFightBrowser(frame)
    local chrome = frame.fightBrowserChrome
    local manifest = FB_RefreshManifest(self)
    local i, entry, row, tag, label, rawText
    chrome.capacity:SetText("Priority detailed storage  |  Restore returns a fight to Recent")

    for i = 1, FB_RECENT_LIMIT do FB_HideObject(chrome.recentRows[i]) end
    for i = 1, FB_ARCHIVE_LIMIT do
        row = chrome.archiveRows[i]
        entry = manifest and manifest[i]
        row.archiveEntry = nil
        row.restore.archiveIndex = nil
        row.restore.archiveEntry = nil
        if entry then
            tag = FB_Tag(entry, entry.raw, entry.priority)
            label = FB_Truncate(entry.label or "Unknown", 12)
            rawText = entry.raw ~= nil and FB_N(entry.raw) or "--"
            row.indexText:SetText("A" .. i)
            row.tagText:SetText(tag)
            row.nameText:SetText(label)
            row.rawText:SetText(rawText)
            row.archiveEntry = entry
            row.restore.archiveIndex = i
            row.restore.archiveEntry = entry
            row.restore:Enable()
            row:Show()
        else
            row.indexText:SetText("")
            row.tagText:SetText("")
            row.nameText:SetText("")
            row.rawText:SetText("")
            row.restore:Disable()
            row:Hide()
        end
    end
end

local function FB_UpdateHistoryColumns(frame)
    local i, row, columns, summary, index, label
    for i = 1, table.getn(frame.rows or {}) do
        row = frame.rows[i]
        columns = row and row.fightBrowserColumns
        summary = row and row.historySummary
        index = row and row.historyIndex
        if columns then
            row:SetText("")
            if summary and index then
                label = FB_Truncate(summary.label or "Unknown", 16)
                columns.indexText:SetText("H" .. index)
                columns.tagText:SetText(FB_Tag(summary, summary.raw))
                columns.nameText:SetText(label)
                columns.rawText:SetText(FB_N(summary.raw))
                columns.pctText:SetText(format("%.1f%%", FB_HistoryPct(summary)))
                columns:Show()
            else
                columns.indexText:SetText("")
                columns.tagText:SetText("")
                columns.nameText:SetText("")
                columns.rawText:SetText("")
                columns.pctText:SetText("")
                columns:Hide()
            end
        end
    end
end

local FB_OldUpdateHistoryWindow = MT.UpdateHistoryWindow
function MT:UpdateHistoryWindow()
    local frame = self:CreateHistoryWindow()
    local tab = self.fightBrowserTab or "RECENT"

    -- History detail and More Info remain exactly the existing History UI.  The
    -- tabs disappear while drilling down; the existing Back button returns to
    -- History LIST mode, at which point this wrapper restores the browser tabs.
    if tab == "HISTORY" and (self.historyBrowserMode == "DETAIL" or self.historyBrowserMode == "COUNTS") then
        if frame.fightBrowserChrome then frame.fightBrowserChrome:Hide() end
        FB_OldUpdateHistoryWindow(self)
        return
    end

    frame:SetHeight(FB_LIST_HEIGHT)
    FB_HideLegacyHistory(frame)
    FB_PositionListTitle(frame)
    frame.title:SetText("Fights")
    frame.fightBrowserChrome:Show()
    self:UpdateFightBrowserTabs(frame, tab)

    if tab == "RECENT" then
        self.historyBrowserMode = "LIST"
        self:UpdateRecentFightBrowser(frame)
    elseif tab == "ARCHIVE" then
        self.historyBrowserMode = "LIST"
        self:UpdateArchiveFightBrowser(frame)
    else
        self.fightBrowserTab = "HISTORY"
        self.historyBrowserMode = "LIST"
        FB_OldUpdateHistoryWindow(self)
        FB_UpdateHistoryColumns(frame)
        -- Old History list update intentionally owns paging/row contents, but
        -- its pre-browser title/capacity are replaced by the unified shell.
        frame.title:SetText("Fights")
        FB_PositionListTitle(frame)
        frame.fightBrowserChrome:Show()
        FB_HideObject(frame.capacity)
        frame.fightBrowserChrome.capacity:SetText("Summary-only long-term records  |  click a row to view")
        self:UpdateFightBrowserTabs(frame, "HISTORY")
        local i
        for i = 1, FB_RECENT_LIMIT do FB_HideObject(frame.fightBrowserChrome.recentRows[i]) end
        for i = 1, FB_ARCHIVE_LIMIT do FB_HideObject(frame.fightBrowserChrome.archiveRows[i]) end
    end

    if self.ApplyLegacyWindowStyle then self:ApplyLegacyWindowStyle(frame) end
    if MT.BlackenButtonsDeep then MT.BlackenButtonsDeep(frame, 0, {}) end
end

function MT:SetFightBrowserTab(tab)
    tab = string.upper(tostring(tab or "RECENT"))
    if tab ~= "RECENT" and tab ~= "ARCHIVE" and tab ~= "HISTORY" then tab = "RECENT" end
    self.fightBrowserTab = tab
    self.historyBrowserMode = "LIST"
    self:UpdateHistoryWindow()
end

function MT:ToggleFightBrowser(tab)
    if tab then
        tab = string.upper(tostring(tab))
        if tab == "RECENT" or tab == "ARCHIVE" or tab == "HISTORY" then self.fightBrowserTab = tab end
    end
    self.fightBrowserTab = self.fightBrowserTab or "RECENT"
    self.historyBrowserMode = "LIST"
    self.fightBrowserReturnActive = nil
    self:UpdateFightBrowserReturnButton()
    self:CreateHistoryWindow()
    self:ShowManagedPage("HISTORY", function(owner) owner:UpdateHistoryWindow() end)
end

-- Preserve old API/command callers: "History" now opens the History tab of
-- Fights instead of a separate product surface.
function MT:ToggleHistoryBrowser()
    self:ToggleFightBrowser("HISTORY")
end

function MT:UpdateFightBrowserReturnButton()
    local frame = self.frame
    if not frame or not frame.fightBrowserBackButton then return end
    if self.fightBrowserReturnActive and not self.miniMode and frame:IsVisible() then
        frame.fightBrowserBackButton:Show()
    else
        frame.fightBrowserBackButton:Hide()
    end
end

function MT:ReturnToFightBrowser()
    if not self.fightBrowserReturnActive then return end
    local tab = self.fightBrowserReturnTab or "RECENT"
    self.fightBrowserReturnActive = nil
    self:UpdateFightBrowserReturnButton()
    self:ToggleFightBrowser(tab)
end

function MT:OpenRecentFightFromBrowser(index)
    index = tonumber(index)
    if not index or not self.fights or not self.fights[index] then return end
    self.fightBrowserReturnTab = "RECENT"
    self.fightBrowserReturnActive = true
    self.fightBrowserOpeningView = true
    self:SetView(index)
    self.fightBrowserOpeningView = nil
    self:ShowManagedPage("MAIN")
    self.fightBrowserReturnActive = true
    self:UpdateFightBrowserReturnButton()
end

-- Selecting a different view by ordinary Main controls/slash command ends the
-- special browser-return context.  The browser's own saved-fight selection is
-- exempted by fightBrowserOpeningView.
local FB_OldSetView = MT.SetView
function MT:SetView(view)
    FB_OldSetView(self, view)
    if not self.fightBrowserOpeningView and self.fightBrowserReturnActive then
        self.fightBrowserReturnActive = nil
        self:UpdateFightBrowserReturnButton()
    end
end

-- Upgrade the existing Main-page History button into the single Fights entry
-- point and add a conditional Back button used only after opening Recent.
local FB_OldCreateUI = MT.CreateUI
function MT:CreateUI()
    FB_OldCreateUI(self)
    local frame = self.frame
    if not frame then return end

    if frame.historyButton then
        frame.historyButton:SetText("Fights")
        frame.historyButton:SetScript("OnClick", function() MT:ToggleFightBrowser() end)
        frame.historyButton:SetScript("OnEnter", function()
            local tip = MT:GetAnalysisTooltip()
            tip:SetOwner(this, "ANCHOR_CURSOR")
            tip:SetText("Fights", 1, 0.82, 0)
            tip:AddLine("Browse Recent, Archive, and History in one place.", 0.85, 0.85, 0.85)
            tip:AddLine("Recent/Archive keep detail; History keeps summaries.", 1, 0.82, 0)
            tip:Show()
        end)
        frame.fightsButton = frame.historyButton
    end

    if not frame.fightBrowserBackButton then
        local back = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        back:SetWidth(38)
        back:SetHeight(18)
        back:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -6)
        back:SetText("Back")
        back:SetScript("OnClick", function() MT:ReturnToFightBrowser() end)
        FB_Style(back)
        back:Hide()
        frame.fightBrowserBackButton = back
    end
    self:UpdateFightBrowserReturnButton()
end

-- Slash commands remain useful shortcuts/recovery tools, but their ordinary
-- browse commands now land on the same UI players can reach with the Fights
-- button.  Numeric /mt fight N and archive restore N remain fully compatible.
local FB_OldHandleSlash = MT.HandleSlash
function MT:HandleSlash(msg)
    local text = string.lower(tostring(msg or ""))
    text = string.gsub(text, "^%s+", "")
    text = string.gsub(text, "%s+$", "")

    if text == "fights" then
        self:ToggleFightBrowser("RECENT")
        return
    elseif text == "archive" or text == "archives" or text == "vault" then
        self:ToggleFightBrowser("ARCHIVE")
        return
    elseif text == "history" or text == "hist" then
        self:ToggleFightBrowser("HISTORY")
        return
    end

    local _, _, historyIndex = string.find(text, "^history%s+(%d+)$")
    if historyIndex then
        self.fightBrowserTab = "HISTORY"
        self.historySelectedIndex = tonumber(historyIndex)
        self.historyBrowserMode = "DETAIL"
        self:CreateHistoryWindow()
        self:ShowManagedPage("HISTORY", function(owner) owner:UpdateHistoryWindow() end)
        return
    end
    return FB_OldHandleSlash(self, msg)
end
