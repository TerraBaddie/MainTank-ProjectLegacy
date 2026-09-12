-- MainTank COMPARE2 - readable Tank Compare presentation
--
-- IMPORTANT ARCHITECTURE NOTE:
-- RC4/RC5 Compare owns sync, encounter grouping, fight paging, row.data, and
-- the selected-player state.  Do not wrap CreateTankCompareWindow here.
-- COMPARE1 did that and made presentation initialization depend on the old
-- Create/Sync wrapper chain.  Instead, let the authoritative updater finish,
-- then lazily attach/reconcile the presentation against the completed frame.

if not MainTank then return end
local MT = MainTank
local E = MT._engine
local StyleLegacyButton = E and E.StyleLegacyButton

local COMPARE_METRIC_PAGES = {
    {
        name = "Core",
        {label="RAW", key="raw", kind="number"},
        {label="Taken", key="taken", kind="number"},
        {label="Stopped", key="stopped", kind="number"},
        {label="Mitigation", key="mitigation", kind="percent"},
        {label="Duration", key="duration", kind="duration"},
    },
    {
        name = "Mitigation",
        {label="Armor", key="armor", kind="number"},
        {label="Avoidance", key="avoidance", kind="number"},
        {label="Block", key="block", kind="number"},
        {label="Resist", key="resist", kind="number"},
        {label="Absorb", key="absorb", kind="number"},
    },
    {
        name = "DR / Damage",
        {label="Flat DR", key="flatDR", kind="number", rc6=true},
        {label="Phys DR", key="physicalDR", kind="number", rc6=true},
        {label="Magic DR", key="magicDR", kind="number", rc6=true},
        {label="Physical RAW", key="physical", kind="number"},
        {label="Magic RAW", key="magic", kind="number"},
    },
}

local function CompareStyleButton(button)
    if not button then return end
    if StyleLegacyButton then StyleLegacyButton(button) end
    if button.SetTextColor then button:SetTextColor(1,1,1) end
end

local function CompareNewText(frame, template, x, y, width, justify)
    local fs = frame:CreateFontString(nil, "OVERLAY", template or "GameFontHighlightSmall")
    fs:SetPoint("TOPLEFT", frame, "TOPLEFT", x, y)
    if width then fs:SetWidth(width) end
    if justify then fs:SetJustifyH(justify) end
    return fs
end

local function CompareMitigation(summary)
    local raw = tonumber(summary and summary.raw) or 0
    if raw <= 0 then return 0 end
    return ((tonumber(summary.stopped) or 0) / raw) * 100
end

local function CompareMetricValue(summary, metric)
    if not summary or not metric then return nil, false end
    if metric.rc6 and not summary.compareRC6 then return nil, false end
    if metric.key == "mitigation" then return CompareMitigation(summary), true end
    return tonumber(summary[metric.key]) or 0, true
end

local function CompareFormatValue(owner, value, kind)
    if kind == "percent" then return format("%.1f%%", value or 0) end
    if kind == "duration" then return format("%.1fs", value or 0) end
    return owner:FormatNumber(value or 0)
end

local function CompareFormatDelta(owner, delta, kind)
    delta = tonumber(delta) or 0
    local prefix = ""
    if delta > 0 then prefix = "+" elseif delta < 0 then prefix = "-" end
    local amount = math.abs(delta)
    if kind == "percent" then
        if amount < 0.05 then return "0.0pp" end
        return prefix .. format("%.1fpp", amount)
    elseif kind == "duration" then
        if amount < 0.05 then return "0.0s" end
        return prefix .. format("%.1fs", amount)
    end
    if amount < 0.5 then return "0" end
    return prefix .. owner:FormatNumber(amount)
end

local function CompareVisibleSummaries(frame)
    local rows = {}
    local i, row
    for i = 1, table.getn(frame.rows or {}) do
        row = frame.rows[i]
        if row and row.data then table.insert(rows, row.data) end
    end
    return rows
end

local function CompareReference(owner, rows)
    local localName = owner.playerName or UnitName("player") or ""
    local i, summary
    for i = 1, table.getn(rows) do
        summary = rows[i]
        if summary and (summary.localPlayer or tostring(summary.player or "") == tostring(localName)) then
            return summary
        end
    end
    return rows[1]
end

local function CompareSelected(owner, rows)
    local i, summary
    for i = 1, table.getn(rows) do
        summary = rows[i]
        if summary and tostring(summary.player or "") == tostring(owner.compareSelectedPlayer or "") then
            return summary
        end
    end
    return rows[1]
end

local function CompareBindRow(row)
    if not row or row.compare2ClickBound then return end
    row.compare2ClickBound = true
    if row.RegisterForClicks then row:RegisterForClicks("LeftButtonUp") end
    row:SetScript("OnClick", function()
        if this and this.data then
            MT.compareSelectedPlayer = this.data.player
            MT:UpdateTankCompareWindow()
        end
    end)
end

local function CompareEnsurePresentation(owner, frame)
    if not frame then return nil end

    -- Always bind the click contract, even if the visual layer already exists.
    -- This makes tank selection independent from whatever older row script was
    -- installed when the frame was originally created.
    local i, c, row
    for i = 1, table.getn(frame.rows or {}) do CompareBindRow(frame.rows[i]) end

    if frame.compare2Polished then return frame end

    -- Only set the initialized flag after all controls have been created.  A
    -- partial UI construction can therefore retry cleanly instead of leaving a
    -- permanently poisoned half-polished frame.
    if frame.title then frame.title:SetText("Tank Compare") end

    -- Move authoritative encounter pager to the top; RC5 still owns its scripts.
    frame.prev:ClearAllPoints(); frame.prev:SetWidth(18); frame.prev:SetHeight(15)
    frame.prev:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, -27)
    frame.pageText:ClearAllPoints(); frame.pageText:SetPoint("LEFT", frame.prev, "RIGHT", 3, 0)
    frame.pageText:SetWidth(34)
    frame.next:ClearAllPoints(); frame.next:SetWidth(18); frame.next:SetHeight(15)
    frame.next:SetPoint("LEFT", frame.pageText, "RIGHT", 3, 0)

    frame.sync:ClearAllPoints(); frame.sync:SetWidth(62); frame.sync:SetHeight(16)
    frame.sync:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -9, -27)
    frame.sync:SetText("Sync Now")
    CompareStyleButton(frame.prev); CompareStyleButton(frame.next); CompareStyleButton(frame.sync)

    frame.warning:ClearAllPoints()
    frame.warning:SetPoint("TOPLEFT", frame, "TOPLEFT", 86, -30)
    frame.warning:SetWidth(137); frame.warning:SetJustifyH("CENTER")
    frame.warning:SetTextColor(1,1,1)

    local headerY = -47
    local rowY = -60
    local hx = {10, 88, 136, 181, 245}
    local hw = {76, 46, 43, 62, 43}
    local headers = {"Tank", "RAW", "Taken", "Stopped", "MIT%"}
    for i = 1, 5 do
        frame.headers[i]:ClearAllPoints()
        frame.headers[i]:SetPoint("TOPLEFT", frame, "TOPLEFT", hx[i], headerY)
        frame.headers[i]:SetWidth(hw[i])
        frame.headers[i]:SetText(headers[i])
    end

    for i = 1, table.getn(frame.rows or {}) do
        row = frame.rows[i]
        row:ClearAllPoints(); row:SetPoint("TOPLEFT", frame, "TOPLEFT", 9, rowY - ((i - 1) * 18))
        row:SetWidth(282); row:SetHeight(17)
        if row.SetFrameLevel and frame.GetFrameLevel then row:SetFrameLevel(frame:GetFrameLevel() + 3) end
        for c = 1, 5 do
            row.cols[c]:ClearAllPoints()
            row.cols[c]:SetPoint("TOPLEFT", frame, "TOPLEFT", hx[c], rowY - 2 - ((i - 1) * 18))
            row.cols[c]:SetWidth(hw[c])
        end
    end

    frame.detail:Hide()

    frame.compareDeltaTitle = CompareNewText(frame, "GameFontNormalSmall", 10, -133, 205, "LEFT")
    frame.compareMetricPrev = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.compareMetricPrev:SetWidth(13); frame.compareMetricPrev:SetHeight(14)
    frame.compareMetricPrev:SetPoint("TOPLEFT", frame, "TOPLEFT", 221, -129)
    frame.compareMetricPrev:SetText("<")
    frame.compareMetricPageText = CompareNewText(frame, "GameFontHighlightSmall", 235, -133, 22, "CENTER")
    frame.compareMetricNext = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.compareMetricNext:SetWidth(13); frame.compareMetricNext:SetHeight(14)
    frame.compareMetricNext:SetPoint("TOPLEFT", frame, "TOPLEFT", 258, -129)
    frame.compareMetricNext:SetText(">")
    CompareStyleButton(frame.compareMetricPrev); CompareStyleButton(frame.compareMetricNext)
    frame.compareMetricPage = 1
    frame.compareMetricPrev:SetScript("OnClick", function()
        if (frame.compareMetricPage or 1) > 1 then
            frame.compareMetricPage = frame.compareMetricPage - 1
            MT:UpdateTankCompareWindow()
        end
    end)
    frame.compareMetricNext:SetScript("OnClick", function()
        if (frame.compareMetricPage or 1) < table.getn(COMPARE_METRIC_PAGES) then
            frame.compareMetricPage = frame.compareMetricPage + 1
            MT:UpdateTankCompareWindow()
        end
    end)

    frame.compareMetricHeaders = {}
    local mh = {10, 88, 151, 214}
    local mw = {75, 60, 60, 74}
    local mt = {"Metric", "Selected", "You", "+/-"}
    for i = 1, 4 do
        frame.compareMetricHeaders[i] = CompareNewText(frame, "GameFontNormalSmall", mh[i], -148, mw[i], i == 1 and "LEFT" or "RIGHT")
        frame.compareMetricHeaders[i]:SetText(mt[i])
    end

    frame.compareMetricRows = {}
    for i = 1, 5 do
        local y = -161 - ((i - 1) * 13)
        local metricRow = {}
        metricRow.label = CompareNewText(frame, "GameFontHighlightSmall", 10, y, 75, "LEFT")
        metricRow.selected = CompareNewText(frame, "GameFontHighlightSmall", 88, y, 60, "RIGHT")
        metricRow.reference = CompareNewText(frame, "GameFontHighlightSmall", 151, y, 60, "RIGHT")
        metricRow.delta = CompareNewText(frame, "GameFontHighlightSmall", 214, y, 74, "RIGHT")
        frame.compareMetricRows[i] = metricRow
    end

    frame.compare2Polished = true
    return frame
end

local CompareOldUpdate = MT.UpdateTankCompareWindow
function MT:UpdateTankCompareWindow()
    -- First let RC5 build/group the synced encounter and populate row.data.
    CompareOldUpdate(self)

    local frame = self.compareFrame or getglobal("MainTankTankCompareFrame")
    frame = CompareEnsurePresentation(self, frame)
    if not frame or not frame.compare2Polished then return end

    if frame.title then frame.title:SetText("Tank Compare") end
    frame.warning:SetText("Click tank - compare vs you")
    frame.warning:SetTextColor(1,1,1)
    frame.detail:Hide()

    local rows = CompareVisibleSummaries(frame)
    local selected = CompareSelected(self, rows)
    local reference = CompareReference(self, rows)
    local pages = table.getn(COMPARE_METRIC_PAGES)
    frame.compareMetricPage = math.max(1, math.min(frame.compareMetricPage or 1, pages))
    frame.compareMetricPageText:SetText(tostring(frame.compareMetricPage) .. "/" .. tostring(pages))
    if frame.compareMetricPage <= 1 then frame.compareMetricPrev:Disable() else frame.compareMetricPrev:Enable() end
    if frame.compareMetricPage >= pages then frame.compareMetricNext:Disable() else frame.compareMetricNext:Enable() end

    if not selected or not reference then
        frame.compareDeltaTitle:SetText("Delta: waiting for synced tank summaries")
        local i
        for i = 1, 5 do
            frame.compareMetricRows[i].label:SetText("")
            frame.compareMetricRows[i].selected:SetText("")
            frame.compareMetricRows[i].reference:SetText("")
            frame.compareMetricRows[i].delta:SetText("")
        end
        if self.ApplyUniformButtonText then self:ApplyUniformButtonText(frame) end
        return
    end

    local refName = tostring(reference.player or "You")
    local localName = self.playerName or UnitName("player") or ""
    local referenceIsYou = reference.localPlayer or refName == localName
    if referenceIsYou then refName = "You" end
    frame.compareMetricHeaders[3]:SetText(referenceIsYou and "You" or "Ref")
    frame.compareDeltaTitle:SetText(
        "Delta: " .. tostring(selected.player or "Selected") .. " - " .. refName ..
        "  (" .. tostring(COMPARE_METRIC_PAGES[frame.compareMetricPage].name) .. ")"
    )

    local metrics = COMPARE_METRIC_PAGES[frame.compareMetricPage]
    local i, metric, selectedValue, selectedOK, referenceValue, referenceOK, metricRow
    for i = 1, 5 do
        metric = metrics[i]
        metricRow = frame.compareMetricRows[i]
        if metric then
            selectedValue, selectedOK = CompareMetricValue(selected, metric)
            referenceValue, referenceOK = CompareMetricValue(reference, metric)
            metricRow.label:SetText(metric.label)
            metricRow.selected:SetText(selectedOK and CompareFormatValue(self, selectedValue, metric.kind) or "--")
            metricRow.reference:SetText(referenceOK and CompareFormatValue(self, referenceValue, metric.kind) or "--")
            if selectedOK and referenceOK then
                metricRow.delta:SetText(CompareFormatDelta(self, selectedValue - referenceValue, metric.kind))
            else
                metricRow.delta:SetText("--")
            end
        else
            metricRow.label:SetText(""); metricRow.selected:SetText(""); metricRow.reference:SetText(""); metricRow.delta:SetText("")
        end
    end

    -- Old updater owns the row highlight. Reassert it after presentation so
    -- the selected tank and the Delta title can never disagree visually.
    for i = 1, table.getn(frame.rows or {}) do
        row = frame.rows[i]
        if row and row.data and tostring(row.data.player or "") == tostring(self.compareSelectedPlayer or "") then
            row.highlight:Show()
        elseif row and row.highlight then
            row.highlight:Hide()
        end
    end

    if self.ApplyUniformButtonText then self:ApplyUniformButtonText(frame) end
end
