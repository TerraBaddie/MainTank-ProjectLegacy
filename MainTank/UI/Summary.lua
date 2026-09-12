-- MainTank REFACXML1 - Summary UI controller
-- Static geometry is declared in UI\MainFrame.xml; this file owns summary
-- presentation behavior, mini mode, row binding, and block-value interaction.

local MT = MainTank
local E = MT._engine
local format = string.format
local Round = E.Round
local GetBlockValueBreakdown = E.GetBlockValueBreakdown
local GetBaseBlockValue = E.GetBaseBlockValue
local GetArmorReduction = E.GetArmorReduction
local Print = E.Print
local FinalizeLegacyWindow = E.FinalizeLegacyWindow

function MT:FormatNumber(number)
    return tostring(Round(number or 0))
end

function MT:UpdateViewButtons()
    if not self.viewButtons then return end
    if self.currentView == "CURRENT" then
        self.viewButtons.CURRENT:Disable()
        self.viewButtons.OVERALL:Enable()
    elseif self.currentView == "OVERALL" then
        self.viewButtons.CURRENT:Enable()
        self.viewButtons.OVERALL:Disable()
    else
        self.viewButtons.CURRENT:Enable()
        self.viewButtons.OVERALL:Enable()
    end
end

function MT:SetView(view)
    if view ~= "CURRENT" and view ~= "OVERALL" and type(view) ~= "number" then return end
    self.currentView = view
    self:SyncPersistentData()
    self:UpdateViewButtons()
    self:UpdateDisplay()
    if self.timelineFrame and self.timelineFrame:IsVisible() then self:UpdateTimelineWindow() end
    if self.pieFrame and self.pieFrame:IsVisible() then self:UpdatePieWindow() end
    if self.detailsFrame and self.detailsFrame:IsVisible() then self:UpdateDetailsWindow() end
    if self.biggestFrame and self.biggestFrame:IsVisible() then self:UpdateBiggestWindow() end
end

function MT:SetPage(page)
    if page ~= "RAW" and page ~= "PHYSICAL" and page ~= "MAGIC" then return end
    self.currentPage = page
    if MainTankDB then MainTankDB.page = page end

    local key, button
    for key, button in pairs(self.pageButtons or {}) do
        if key == page then
            button:Disable()
        else
            button:Enable()
        end
    end
    self:UpdateDisplay()
end

function MT:SetRow(index, label, value)
    local row = self.rows[index]
    if not row then return end
    row.label:SetText(label or "")
    row.value:SetText(value or "")
    if label and label ~= "" then
        row.label:Show()
        row.value:Show()
        -- FR1d: row hit frames are hidden in Mini Mode.  Restore them whenever
        -- the full page is active so row-specific hover/click analysis (notably
        -- Physical row 8: Base Block Value) remains reachable after expanding.
        if row.hit and not self.miniMode then row.hit:Show() end
    else
        row.label:Hide()
        row.value:Hide()
        if row.hit then row.hit:Hide() end
    end
end

function MT:UpdateDisplay()
    if not self.frame then return end

    local originalData = self.data
    self.data = self:GetDisplayData()
    local mitigated, raw = self:GetTotals(self.data)
    local totalPct = 0
    if raw > 0 then totalPct = (mitigated / raw) * 100 end
    self:UpdateMiniDisplay(self.data, raw, mitigated, totalPct)

    local dpmEstimated = self.data.dodgedEstimated + self.data.parriedEstimated + self.data.missedEstimated
    local dpmCount = self.data.dodgeCount + self.data.parryCount + self.data.missCount
    local totalBlocks = self.data.blocked + self.data.fullBlockedEstimated
    local totalResists = self.data.resistedPartial + self.data.resistedFullEstimated
    local reduction, armorValue = GetArmorReduction(UnitName("target") or "")

    local physicalPrevented = self.data.armorReduced + dpmEstimated + totalBlocks
    local physicalAttempts = self.data.meleeHitCount + dpmCount + self.data.fullBlockCount
    local avoidancePct = 0
    if physicalAttempts > 0 then avoidancePct = (dpmCount / physicalAttempts) * 100 end

    local magicMitigated = totalResists
    local magicPct = 0
    if self.data.magicRaw > 0 then magicPct = (magicMitigated / self.data.magicRaw) * 100 end

    local magicAttempts = self.data.magicHitCount + self.data.fullResistCount
    local resistedEvents = self.data.partialResistCount + self.data.fullResistCount
    local resistEventPct = 0
    if magicAttempts > 0 then resistEventPct = (resistedEvents / magicAttempts) * 100 end

    local currentBlockValue = GetBaseBlockValue(self.data)

    local page = self.currentPage or "RAW"
    if page == "PHYSICAL" then
        self.frame.subtitle:SetText("Physical Avoidance Details")
        self:SetRow(1, "Dodged (est.)", self:FormatNumber(self.data.dodgedEstimated) .. "  (" .. self.data.dodgeCount .. ")")
        self:SetRow(2, "Parried (est.)", self:FormatNumber(self.data.parriedEstimated) .. "  (" .. self.data.parryCount .. ")")
        self:SetRow(3, "Missed (est.)", self:FormatNumber(self.data.missedEstimated) .. "  (" .. self.data.missCount .. ")")
        self:SetRow(4, "Full Blocks (est.)", self:FormatNumber(self.data.fullBlockedEstimated) .. "  (" .. self.data.fullBlockCount .. ")")
        self:SetRow(5, "Partial Blocks", self:FormatNumber(self.data.blocked) .. "  (" .. self.data.blockCount .. ")")
        self:SetRow(6, "Physical Prevented", self:FormatNumber(physicalPrevented))
        self:SetRow(7, "Active Avoidance", format("%.1f%%", avoidancePct))
        self:SetRow(8, "Base Block Value", self:FormatNumber(currentBlockValue))
    elseif page == "MAGIC" then
        self.frame.subtitle:SetText("Magic Resisted Details")
        self:SetRow(1, "Raw Magic Incoming", self:FormatNumber(self.data.magicRaw))
        self:SetRow(2, "Magic Damage Taken", self:FormatNumber(self.data.magicTaken))
        self:SetRow(3, "Full Resists (est.)", self:FormatNumber(self.data.resistedFullEstimated) .. "  (" .. self.data.fullResistCount .. ")")
        self:SetRow(4, "Partial Resists", self:FormatNumber(self.data.resistedPartial) .. "  (" .. self.data.partialResistCount .. ")")
        self:SetRow(5, "Total Resisted", self:FormatNumber(totalResists))
        self:SetRow(6, "Magic Mitigation", format("%.1f%%", magicPct))
        self:SetRow(7, "Resist Event Rate", format("%.1f%%", resistEventPct))
        self:SetRow(8, "Pending Estimates", tostring(self:GetPendingCount()))
    else
        self.frame.subtitle:SetText("RAW Damage In : RAW Damage Stopped")
        self:SetRow(1, "RAW Damage In", self:FormatNumber(raw))
        self:SetRow(2, "Actual Damage Taken", self:FormatNumber(self.data.damageTaken))
        self:SetRow(3, "RAW Damage Stopped", self:FormatNumber(mitigated))
        self:SetRow(4, "Mitigation", format("%.1f%%", totalPct))
        self:SetRow(5, "Reduced by Armor", self:FormatNumber(self.data.armorReduced))
        self:SetRow(6, "Absorbed", self:FormatNumber(self.data.absorbed) .. "  (" .. self.data.absorbCount .. ")")
        self:SetRow(7, "Physical : Magic In", self:FormatNumber(self.data.physicalRaw) .. " : " .. self:FormatNumber(self.data.magicRaw))
        self:SetRow(8, "Current Armor", self:FormatNumber(armorValue) .. "  (" .. format("%.1f%%", reduction * 100) .. ")")
    end

    if self.miniMode then
        local i
        for i = 1, 8 do
            self.rows[i].label:Hide(); self.rows[i].value:Hide(); self.rows[i].hit:Hide()
        end
    end

    if self.currentView == "OVERALL" then
        self.frame.title:SetText("MainTank - Overall")
    elseif type(self.currentView) == "number" and self.fights[self.currentView] then
        self.frame.title:SetText("MainTank - " .. self:GetViewLabel())
    elseif self.inCombat then
        self.frame.title:SetText("MainTank - " .. self:GetViewLabel())
    else
        self.frame.title:SetText("MainTank - " .. self:GetViewLabel())
    end
    self.data = originalData
    if self.detailsFrame and self.detailsFrame:IsVisible() then self:UpdateDetailsWindow() end
    if self.biggestFrame and self.biggestFrame:IsVisible() then self:UpdateBiggestWindow() end
end

function MT:ShowBlockValueTooltip(owner)
    if self.currentPage ~= "PHYSICAL" then return end

    local data = self:GetDisplayData()
    local details = GetBlockValueBreakdown(data)
    local tooltip = MT:GetAnalysisTooltip()

    tooltip:SetOwner(owner, "ANCHOR_RIGHT")
    tooltip:SetText("Block Analysis", 1, 0.82, 0)
    tooltip:AddDoubleLine("Base Block Value", self:FormatNumber(details.baseValue), 1, 0.82, 0, 1, 0.82, 0)
    tooltip:AddLine(" ")

    tooltip:AddLine("Calculated Sources", 0.55, 0.8, 1)
    tooltip:AddDoubleLine("Shield and gear", self:FormatNumber(details.gear), 0.82, 0.82, 0.82, 1, 1, 1)
    tooltip:AddDoubleLine("Strength (20 = 1)", self:FormatNumber(details.strength), 0.82, 0.82, 0.82, 1, 1, 1)
    tooltip:AddDoubleLine("Talent bonus", "+" .. self:FormatNumber(details.talentPct) .. "%", 0.82, 0.82, 0.82, 1, 1, 1)
    if details.api and details.api > 0 then
        tooltip:AddDoubleLine("Client API", self:FormatNumber(details.api), 0.82, 0.82, 0.82, 1, 1, 1)
    end
    if details.scanReady == false then
        tooltip:AddLine("Equipment scan retrying...", 1, 0.55, 0.2)
    end

    tooltip:AddLine(" ")
    tooltip:AddLine("Observed Partial Blocks", 0.55, 0.8, 1)
    if details.observedCount > 0 then
        tooltip:AddDoubleLine("Lowest", self:FormatNumber(details.observedMin), 0.82, 0.82, 0.82, 1, 1, 1)
        tooltip:AddDoubleLine("Average", self:FormatNumber(details.observedAverage), 0.82, 0.82, 0.82, 1, 1, 1)
        tooltip:AddDoubleLine("Highest", self:FormatNumber(details.observedMax), 0.82, 0.82, 0.82, 1, 1, 1)
        tooltip:AddDoubleLine("Samples", tostring(details.observedCount), 0.82, 0.82, 0.82, 1, 1, 1)
    else
        tooltip:AddLine("No exact samples in this view.", 0.68, 0.68, 0.68)
    end

    local targetName = UnitExists("target") and UnitName("target") or nil
    local mobData = targetName and data.mobs and data.mobs[targetName] or nil
    if mobData and (mobData.blockCount or 0) > 0 then
        local avg = (mobData.blockTotal or 0) / mobData.blockCount
        tooltip:AddLine(" ")
        tooltip:AddLine(targetName, 1, 0.82, 0)
        tooltip:AddDoubleLine("Low / Avg / High", self:FormatNumber(mobData.blockMin) .. " / " .. self:FormatNumber(avg) .. " / " .. self:FormatNumber(mobData.blockMax), 0.82, 0.82, 0.82, 1, 1, 1)
        tooltip:AddDoubleLine("Samples", tostring(mobData.blockCount), 0.82, 0.82, 0.82, 1, 1, 1)
    end

    tooltip:AddLine(" ")
    tooltip:AddLine("Project Legacy uses vanilla-style shield block calculation.", 0.7, 0.8, 1)
    tooltip:AddLine("Observed values do not replace the Base Block Value.", 0.7, 0.8, 1)
    tooltip:Show()
end

function MT:HideRowTooltip()
    self:HideAnalysisTooltip()
end


function MT:PrintBlockReport()
    local data = self:GetDisplayData()
    local details = GetBlockValueBreakdown(data)
    Print("Base Block Value: " .. self:FormatNumber(details.baseValue) .. ". Exact partial blocks: " .. tostring(details.observedCount) .. " samples, " .. self:FormatNumber(details.observedMin) .. " / " .. self:FormatNumber(details.observedAverage) .. " / " .. self:FormatNumber(details.observedMax) .. " low/avg/high.")

    local names = {}
    local mob, mobData
    for mob, mobData in pairs(data.mobs or {}) do
        if (mobData.blockCount or 0) > 0 then table.insert(names, mob) end
    end
    table.sort(names)
    local i
    for i = 1, table.getn(names) do
        mob = names[i]
        mobData = data.mobs[mob]
        local avg = (mobData.blockTotal or 0) / mobData.blockCount
        Print(mob .. ": " .. mobData.blockCount .. " blocks, " .. self:FormatNumber(mobData.blockMin) .. " / " .. self:FormatNumber(avg) .. " / " .. self:FormatNumber(mobData.blockMax) .. " low/avg/high.")
    end
end


-- REFACXML1: Timeline/Pie/Biggest/Details analysis core moved to
-- UI\AnalysisCore.lua. It loads immediately after this file so the historical
-- RC1+ override stack still sees the same methods in the same order.

-- UIFIX3: full-size controls must enforce their visibility when they are
-- registered, not only during SetMiniMode.  Historical CreateUI wrappers add
-- Reset/Export/Boss/Compare/History after the base CreateUI has already restored
-- saved Mini Mode on login/reload.  Registering through one gate removes that
-- ordering dependency completely.
function MT:RegisterFullControl(control)
    if not control then return nil end
    if not self.fullControls then self.fullControls = {} end

    local i
    for i = 1, table.getn(self.fullControls) do
        if self.fullControls[i] == control then
            control.mtMainTankFullOnly = true
            if self.miniMode then control:Hide() end
            return control
        end
    end

    table.insert(self.fullControls, control)
    control.mtMainTankFullOnly = true
    if self.miniMode then control:Hide() end
    return control
end

function MT:SetMiniMode(enabled, automatic)
    if not self.frame then return end
    enabled = enabled and true or false
    self.miniMode = enabled
    MainTankDB.miniMode = enabled

    if automatic then
        self.autoMiniApplied = enabled
    else
        self.autoMiniApplied = false
    end

    local i
    if enabled then
        self.frame:SetWidth(245)
        self.frame:SetHeight(112)
        if self.fullControls then
            for i = 1, table.getn(self.fullControls) do self.fullControls[i]:Hide() end
        end
        for i = 1, 8 do
            if self.rows[i] then
                self.rows[i].label:Hide()
                self.rows[i].value:Hide()
                self.rows[i].hit:Hide()
            end
        end
        if self.frame.subtitle then self.frame.subtitle:Hide() end
        if self.frame.miniRows then
            for i = 1, 4 do
                self.frame.miniRows[i].label:Show()
                self.frame.miniRows[i].value:Show()
            end
        end
        self.frame.shrinkButton:SetText("+")
        self.frame.shrinkButton:SetWidth(22)
        self.frame.shrinkButton:SetPoint("TOPRIGHT", self.frame, "TOPRIGHT", -27, -5)
    else
        self.frame:SetWidth(300)
        self.frame:SetHeight(231)
        if self.fullControls then
            for i = 1, table.getn(self.fullControls) do self.fullControls[i]:Show() end
        end
        if self.frame.subtitle then self.frame.subtitle:Show() end
        if self.frame.miniRows then
            for i = 1, 4 do
                self.frame.miniRows[i].label:Hide()
                self.frame.miniRows[i].value:Hide()
            end
        end
        self.frame.shrinkButton:SetText("-")
        self.frame.shrinkButton:SetWidth(22)
        self.frame.shrinkButton:SetPoint("TOPRIGHT", self.frame, "TOPRIGHT", -27, -5)
        self:SetPage(self.currentPage or "RAW")
    end
    self:UpdateDisplay()
end

function MT:ToggleMiniMode()
    self:SetMiniMode(not self.miniMode, false)
end

function MT:UpdateMiniDisplay(data, raw, mitigated, totalPct)
    if not self.frame or not self.frame.miniRows then return end
    local rows = self.frame.miniRows
    rows[1].label:SetText("RAW In")
    rows[1].value:SetText(self:FormatNumber(raw))
    rows[2].label:SetText("Taken")
    rows[2].value:SetText(self:FormatNumber(data.damageTaken or 0))
    rows[3].label:SetText("Stopped")
    rows[3].value:SetText(self:FormatNumber(mitigated))
    rows[4].label:SetText("Mitigation")
    rows[4].value:SetText(format("%.1f%%", totalPct))
end

function MT:CreateUI()
    -- REFACXML1: the static summary-window hierarchy and geometry live in
    -- UI\MainFrame.xml.  Lua owns behavior, SavedVariables state, data binding,
    -- dynamic visibility, and the pfUI-aware runtime skin.
    local frame = CreateFrame("Frame", "MainTankFrame", UIParent, "MainTankMainFrameTemplate")
    local prefix = frame:GetName()

    frame:SetPoint("CENTER", UIParent, "CENTER", 320, 0)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function() this:StartMoving() end)
    frame:SetScript("OnDragStop", function()
        this:StopMovingOrSizing()
        local point, _, relativePoint, x, y = this:GetPoint()
        MainTankDB.position = {point = point, relativePoint = relativePoint, x = x, y = y}
    end)
    -- Keep the historical pre-skin backdrop assignment. FinalizeLegacyWindow
    -- will replace it with the authoritative neutral/pfUI-aware presentation.
    frame:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = {left = 4, right = 4, top = 4, bottom = 4}
    })
    frame:SetBackdropColor(0.05, 0.05, 0.08, 0.92)

    frame.title = getglobal(prefix .. "Title")
    frame.title:SetJustifyH("CENTER")
    frame.title:SetText("MainTank - Current Fight")

    frame.subtitle = getglobal(prefix .. "Subtitle")
    frame.subtitle:SetWidth(250)
    frame.subtitle:SetJustifyH("CENTER")

    local close = getglobal(prefix .. "CloseButton")
    frame.closeButton = close

    local shrinkButton = getglobal(prefix .. "ShrinkButton")
    shrinkButton:SetText("-")
    shrinkButton:SetScript("OnClick", function() MT:ToggleMiniMode() end)
    frame.shrinkButton = shrinkButton

    self.fullControls = {}

    local timelineButton = getglobal(prefix .. "TimelineButton")
    timelineButton:SetText("Timeline")
    timelineButton:SetScript("OnClick", function() MT:ToggleTimeline() end)

    local biggestButton = getglobal(prefix .. "BiggestButton")
    biggestButton:SetText("Biggest")
    biggestButton:SetScript("OnClick", function() MT:ToggleBiggest() end)

    local detailsButton = getglobal(prefix .. "DetailsButton")
    detailsButton:SetText("Details")
    detailsButton:SetScript("OnClick", function() MT:ToggleDetails() end)

    local pieButton = getglobal(prefix .. "PieButton")
    pieButton:SetText("Pie")
    pieButton:SetScript("OnClick", function() MT:TogglePie() end)

    self:RegisterFullControl(timelineButton)
    self:RegisterFullControl(biggestButton)
    self:RegisterFullControl(detailsButton)
    self:RegisterFullControl(pieButton)

    self.viewButtons = {}
    local currentButton = getglobal(prefix .. "CurrentButton")
    currentButton:SetText("Current")
    currentButton:SetScript("OnClick", function() MT:SetView("CURRENT") end)
    self.viewButtons.CURRENT = currentButton
    self:RegisterFullControl(currentButton)

    local overallButton = getglobal(prefix .. "OverallButton")
    overallButton:SetText("Overall")
    overallButton:SetScript("OnClick", function() MT:SetView("OVERALL") end)
    self.viewButtons.OVERALL = overallButton
    self:RegisterFullControl(overallButton)

    self.pageButtons = {}
    local pageButtons = {
        {key = "RAW", text = "RAW", button = getglobal(prefix .. "RawButton")},
        {key = "PHYSICAL", text = "PHYSICAL", button = getglobal(prefix .. "PhysicalButton")},
        {key = "MAGIC", text = "MAGIC", button = getglobal(prefix .. "MagicButton")}
    }
    local i
    for i = 1, table.getn(pageButtons) do
        local info = pageButtons[i]
        local button = info.button
        button:SetText(info.text)
        button.pageKey = info.key
        button:SetScript("OnClick", function() MT:SetPage(this.pageKey) end)
        self.pageButtons[info.key] = button
        self:RegisterFullControl(button)
    end

    -- XML owns the fixed row geometry. Lua binds behavior and live values.
    for i = 1, 8 do
        local label = getglobal(prefix .. "Row" .. i .. "Label")
        local value = getglobal(prefix .. "Row" .. i .. "Value")
        local hit = getglobal(prefix .. "Row" .. i .. "Hit")
        value:SetJustifyH("RIGHT")
        hit:EnableMouse(true)
        hit.rowIndex = i
        hit:SetScript("OnEnter", function()
            if this.rowIndex == 8 and MT.currentPage == "PHYSICAL" then
                MT:ShowBlockValueTooltip(this)
            end
        end)
        hit:SetScript("OnLeave", function() MT:HideRowTooltip() end)
        hit:SetScript("OnMouseUp", function()
            if this.rowIndex == 8 and MT.currentPage == "PHYSICAL" then
                MT:PrintBlockReport()
            end
        end)

        self.rows[i] = {label = label, value = value, hit = hit}
    end

    frame.miniRows = {}
    for i = 1, 4 do
        local label = getglobal(prefix .. "Mini" .. i .. "Label")
        local value = getglobal(prefix .. "Mini" .. i .. "Value")
        label:SetJustifyH("LEFT")
        value:SetJustifyH("RIGHT")
        label:Hide()
        value:Hide()
        frame.miniRows[i] = {label = label, value = value}
    end

    FinalizeLegacyWindow(frame)
    self.frame = frame

    if MainTankDB.position then
        local p = MainTankDB.position
        frame:ClearAllPoints()
        frame:SetPoint(p.point or "CENTER", UIParent, p.relativePoint or "CENTER", p.x or 0, p.y or 0)
    end

    self.currentPage = MainTankDB.page or "RAW"
    self.currentView = self.currentView or "CURRENT"
    self:UpdateViewButtons()
    if MainTankDB.hidden then frame:Hide() else frame:Show() end
    self.miniMode = MainTankDB.miniMode and true or false
    if MainTankDB.autoMiniInCombat == nil then MainTankDB.autoMiniInCombat = false end
    self.autoMiniInCombat = MainTankDB.autoMiniInCombat
    self:SetPage(self.currentPage)
    self:SetMiniMode(self.miniMode, false)
end

