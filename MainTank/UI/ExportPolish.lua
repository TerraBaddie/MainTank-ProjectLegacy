-- MainTank EXPORT1 - release-facing export formatter / presentation
--
-- HARD RULE: Export never owns combat math, Boss aggregation, or persistence.
-- Summary delegates to the proven RC2 export builder, Detailed reads the same
-- authoritative GetDisplayData aggregate used by Main, and Boss/Profile reads
-- BuildBossBreakdown.  This file is formatting/UI only.

if not MainTank then return end
local MT = MainTank
local E = MT._engine
local StyleLegacyButton = E and E.StyleLegacyButton
local format = string.format

local EXPORT_SUMMARY = "SUMMARY"
local EXPORT_DETAILED = "DETAILED"
local EXPORT_BOSS = "BOSS"

local ExportOldBuildLines = MT.BuildExportLines
local ExportOldCreateWindow = MT.CreateExportWindow
local ExportOldShare = MT.ShareExport

local function ExportFormatSavedAt(profile)
    local stamp = tonumber(profile and profile.savedAt)
    if stamp and stamp > 0 and type(date) == "function" then
        return date("%m/%d %H:%M", stamp)
    end
    return "time N/A"
end

local function ExportJoinLines(lines)
    local text = ""
    local i
    for i = 1, table.getn(lines or {}) do
        if i > 1 then text = text .. "\n" end
        text = text .. tostring(lines[i] or "")
    end
    return text
end

-- The 1.12 EditBox does not reliably clip/wrap long multiline text.  Keep the
-- authoritative export formatter untouched and create a display-only wrapped
-- representation for the compact 300x231 viewer.  Select All copies this same
-- complete wrapped report, so no data is lost merely to fit the window.
local EXPORT_WRAP_CHARS = 44
local EXPORT_PAGE_LINES = 10

local function ExportWrapOneLine(line, out)
    line = tostring(line or "")
    if string.len(line) <= EXPORT_WRAP_CHARS then
        table.insert(out, line)
        return
    end

    local continuation = ""
    if string.sub(line, 1, 2) == "- " then continuation = "  " end

    while string.len(line) > EXPORT_WRAP_CHARS do
        local cut = EXPORT_WRAP_CHARS
        while cut > 1 and string.sub(line, cut, cut) ~= " " do cut = cut - 1 end
        if cut <= 1 then cut = EXPORT_WRAP_CHARS + 1 end
        local piece = string.sub(line, 1, cut - 1)
        piece = string.gsub(piece, "%s+$", "")
        table.insert(out, piece)
        line = continuation .. string.gsub(string.sub(line, cut + 1), "^%s+", "")
    end
    table.insert(out, line)
end

local function ExportWrapLines(lines)
    local wrapped = {}
    local i
    for i = 1, table.getn(lines or {}) do
        ExportWrapOneLine(lines[i], wrapped)
    end
    return wrapped
end

local function ExportPageCount(lines)
    local count = table.getn(lines or {})
    if count <= 0 then return 1 end
    return math.floor((count - 1) / EXPORT_PAGE_LINES) + 1
end

local function ExportPageLines(lines, page)
    local result = {}
    local first = ((page - 1) * EXPORT_PAGE_LINES) + 1
    local last = first + EXPORT_PAGE_LINES - 1
    local count = table.getn(lines or {})
    if last > count then last = count end
    local i
    for i = first, last do table.insert(result, lines[i]) end
    return result
end


local function ExportSummaryLines(owner)
    -- Preserve the proven RC2/RC3 summary authority, then append only RC6 totals
    -- that did not exist when that formatter was originally written.
    local lines = ExportOldBuildLines(owner)
    local data = owner:GetDisplayData() or {}
    table.insert(lines,
        "DR Flat " .. owner:FormatNumber(data.flatDR or 0) ..
        " - Physical " .. owner:FormatNumber(data.physicalDR or 0) ..
        " - Magic " .. owner:FormatNumber(data.magicDR or 0)
    )
    return lines
end

local function ExportDetailedLines(owner)
    -- Start from the same human-readable Summary rather than rebuilding its
    -- enemy/biggest-hit logic.  Add technical fields directly from the exact
    -- authoritative display aggregate already used by Main/Timeline/Pie.
    local lines = ExportSummaryLines(owner)
    local data = owner:GetDisplayData() or {}
    local events = owner:GetDisplayEvents() or {}

    table.insert(lines, "--- Detailed ---")
    table.insert(lines,
        "Events " .. tostring(table.getn(events)) ..
        " - Melee Hits " .. tostring(data.meleeHitCount or 0) ..
        " - Magic Hits " .. tostring(data.magicHitCount or 0)
    )
    table.insert(lines,
        "Avoid Counts D/P/M " .. tostring(data.dodgeCount or 0) .. "/" ..
        tostring(data.parryCount or 0) .. "/" .. tostring(data.missCount or 0)
    )
    table.insert(lines,
        "Block Partial " .. owner:FormatNumber(data.blocked or 0) .. " (" .. tostring(data.blockCount or 0) .. ")" ..
        " - Full " .. owner:FormatNumber(data.fullBlockedEstimated or 0) .. " (" .. tostring(data.fullBlockCount or 0) .. ")"
    )
    table.insert(lines,
        "Resist Partial " .. owner:FormatNumber(data.resistedPartial or 0) .. " (" .. tostring(data.partialResistCount or 0) .. ")" ..
        " - Full " .. owner:FormatNumber(data.resistedFullEstimated or 0) .. " (" .. tostring(data.fullResistCount or 0) .. ")"
    )
    table.insert(lines,
        "Absorb " .. owner:FormatNumber(data.absorbed or 0) .. " (" .. tostring(data.absorbCount or 0) .. ")"
    )
    table.insert(lines,
        "Flat DR Physical/Magic " .. owner:FormatNumber(data.physicalFlatDR or 0) .. "/" .. owner:FormatNumber(data.magicFlatDR or 0)
    )
    table.insert(lines,
        "Damage Physical RAW/Taken " .. owner:FormatNumber(data.physicalRaw or 0) .. "/" .. owner:FormatNumber(data.physicalTaken or 0) ..
        " - Magic RAW/Taken " .. owner:FormatNumber(data.magicRaw or 0) .. "/" .. owner:FormatNumber(data.magicTaken or 0)
    )
    return lines
end

local function ExportBossLines(owner)
    -- Boss/Profile export is a pure view over the selected authoritative Boss
    -- Profile.  Do not rebuild the profile from events here.
    local profile = owner:BuildBossBreakdown()
    if not profile or profile.empty then
        return {
            "MainTank Boss Profile",
            "No skull-level Boss Profile is currently available.",
            "Open Boss after recording a legitimate ?? boss encounter."
        }
    end

    local count = table.getn(owner.bossHistory or {})
    local index = count > 0 and (owner.bossProfileIndex or 1) or 0
    local lines = {}
    table.insert(lines, "MainTank Boss Profile - " .. tostring(profile.name or "Unknown"))
    table.insert(lines,
        "Encounter " .. tostring(index) .. "/" .. tostring(count) ..
        " - Saved " .. ExportFormatSavedAt(profile) ..
        " - Duration " .. format("%.1fs", tonumber(profile.duration) or 0)
    )
    table.insert(lines,
        "RAW " .. owner:FormatNumber(profile.raw or 0) ..
        " - Taken " .. owner:FormatNumber(profile.taken or 0) ..
        " - Stopped " .. owner:FormatNumber(profile.stopped or 0) ..
        " - Mitigation " .. format("%.1f%%", tonumber(profile.mitigation) or 0)
    )
    table.insert(lines,
        "Boss RAW Share " .. format("%.1f%%", tonumber(profile.share) or 0) ..
        " - Other Enemies RAW " .. owner:FormatNumber(profile.addsRaw or 0)
    )
    table.insert(lines,
        "Events " .. tostring(profile.events or 0) ..
        " - Crit " .. tostring(profile.criticals or 0) ..
        " - Crush " .. tostring(profile.crushings or 0)
    )
    table.insert(lines,
        "Mitigation Armor " .. owner:FormatNumber(profile.armor or 0) ..
        " - Avoid " .. owner:FormatNumber(profile.avoidance or 0) ..
        " - Block " .. owner:FormatNumber(profile.block or 0) ..
        " - Resist " .. owner:FormatNumber(profile.resist or 0) ..
        " - Absorb " .. owner:FormatNumber(profile.absorb or 0)
    )
    table.insert(lines,
        "DR Flat " .. owner:FormatNumber(profile.flatDR or 0) ..
        " - Physical " .. owner:FormatNumber(profile.physicalDR or 0) ..
        " - Magic " .. owner:FormatNumber(profile.magicDR or 0)
    )

    table.insert(lines, "Damage Schools (RAW / Taken)")
    local i, row
    for i = 1, table.getn(profile.schools or {}) do
        row = profile.schools[i]
        table.insert(lines,
            "- " .. tostring(row.name or "Unknown") .. " " ..
            owner:FormatNumber(row.raw or 0) .. " / " .. owner:FormatNumber(row.taken or 0)
        )
    end

    table.insert(lines, "Boss Abilities (RAW / Taken)")
    for i = 1, table.getn(profile.abilities or {}) do
        row = profile.abilities[i]
        table.insert(lines,
            "- " .. tostring(row.name or "Unknown") .. " [" .. tostring(row.school or "Unknown") .. "] " ..
            owner:FormatNumber(row.raw or 0) .. " / " .. owner:FormatNumber(row.taken or 0)
        )
    end
    return lines
end

function MT:BuildExportLines(mode)
    mode = string.upper(tostring(mode or self.exportMode or EXPORT_SUMMARY))
    if mode == EXPORT_DETAILED then return ExportDetailedLines(self) end
    if mode == EXPORT_BOSS then return ExportBossLines(self) end
    return ExportSummaryLines(self)
end

function MT:BuildExportText(mode)
    return ExportJoinLines(self:BuildExportLines(mode))
end

-- Chat sharing intentionally remains compact Summary-only.  Detailed and Boss
-- exports are copy-oriented so one click cannot dump 20+ technical lines into
-- party/raid/guild chat by accident.
function MT:ShareExport(channel)
    local previous = self.exportMode
    self.exportMode = EXPORT_SUMMARY
    local result = ExportOldShare(self, channel)
    self.exportMode = previous
    return result
end

local function ExportStyleAction(button)
    if not button then return end
    -- Typography is owned by NavigationPolish's canonical Current-button pass.
    -- Do not call StyleLegacyButton here during every tab refresh or these late
    -- controls can grow back to the older pfUI/global legacy font size.
    if button.SetTextColor then button:SetTextColor(1, 1, 1) end
    if button.SetDisabledTextColor then button:SetDisabledTextColor(1, 1, 1) end
end

local function ExportInitButton(button)
    if not button then return end
    if StyleLegacyButton then StyleLegacyButton(button) end
    ExportStyleAction(button)
end

local function ExportStyleTab(button, selected)
    if not button then return end
    ExportStyleAction(button)
    local c = selected and 0.48 or 1.00
    if button.SetTextColor then button:SetTextColor(c, c, c) end
    if button.SetDisabledTextColor then button:SetDisabledTextColor(c, c, c) end
    local fs = button.GetFontString and button:GetFontString() or nil
    if fs and fs.SetTextColor then fs:SetTextColor(c, c, c) end
end

function MT:UpdateExportModeButtons()
    local frame = self.exportFrame or getglobal("MainTankExportFrame")
    if not frame or not frame.exportModeButtons then return end
    local mode = self.exportMode or EXPORT_SUMMARY
    ExportStyleTab(frame.exportModeButtons.SUMMARY, mode == EXPORT_SUMMARY)
    ExportStyleTab(frame.exportModeButtons.DETAILED, mode == EXPORT_DETAILED)
    ExportStyleTab(frame.exportModeButtons.BOSS, mode == EXPORT_BOSS)
    ExportStyleAction(frame.selectAllButton)
end

local function ExportSetMode(owner, mode)
    owner.exportMode = mode
    owner.exportPage = 1
    owner:UpdateExportWindow()
end

function MT:CreateExportWindow()
    local frame = ExportOldCreateWindow(self)
    if frame.export1Polished then return frame end

    -- Keep the established compact managed page, but add a clear mode strip.
    frame.help:ClearAllPoints()
    frame.help:SetPoint("TOP", frame, "TOP", 0, -50)
    frame.help:SetWidth(278)
    frame.help:SetJustifyH("CENTER")

    frame.exportModeButtons = {}
    local modes = {
        -- Keep the existing 300x231 Export window. Rebalance only the tab strip
        -- so the longer labels have enough breathing room on the 1.12 client.
        {key="SUMMARY", label="Summary", x=10, w=56},
        {key="DETAILED", label="Detailed", x=68, w=66},
        {key="BOSS", label="Boss/Profile", x=136, w=88},
    }
    local i, def, button
    for i = 1, table.getn(modes) do
        def = modes[i]
        button = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        button:SetWidth(def.w); button:SetHeight(17)
        button:SetPoint("TOPLEFT", frame, "TOPLEFT", def.x, -28)
        button:SetText(def.label)
        button.mode = def.key
        button:SetScript("OnClick", function() ExportSetMode(MT, this.mode) end)
        ExportInitButton(button)
        frame.exportModeButtons[def.key] = button
    end

    frame.selectAllButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.selectAllButton:SetWidth(58); frame.selectAllButton:SetHeight(17)
    frame.selectAllButton:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -10, -28)
    frame.selectAllButton:SetText("Select All")
    frame.selectAllButton:SetScript("OnClick", function()
        if frame.edit then
            -- Browsing is paged for readability, but Select All always exposes
            -- the entire report in one selection for Ctrl+C.  Losing focus
            -- restores the clean current page automatically.
            if frame.exportAllText then frame.edit:SetText(frame.exportAllText) end
            frame.exportShowingAll = true
            frame.edit:SetFocus()
            frame.edit:HighlightText()
        end
    end)
    ExportInitButton(frame.selectAllButton)

    frame.edit:ClearAllPoints()
    frame.edit:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, -65)
    frame.edit:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -10, 42)
    frame.edit:SetFont("Fonts\\FRIZQT__.TTF", 9, "")
    frame.edit:SetScript("OnEditFocusLost", function()
        if frame.exportShowingAll then
            frame.exportShowingAll = false
            MT:UpdateExportWindow()
        end
    end)
    frame.edit:SetScript("OnEscapePressed", function()
        frame.exportShowingAll = false
        this:ClearFocus()
        MT:UpdateExportWindow()
    end)

    -- Detailed and Boss/Profile keep the exact 300x231 window and page their
    -- wrapped report text inside it.  These controls occupy the same bottom
    -- strip used by chat buttons in Summary mode, so nothing grows or overlaps.
    frame.exportPrev = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.exportPrev:SetWidth(18); frame.exportPrev:SetHeight(17)
    frame.exportPrev:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 10, 12)
    frame.exportPrev:SetText("<")
    frame.exportPrev:SetScript("OnClick", function()
        if (MT.exportPage or 1) > 1 then
            MT.exportPage = MT.exportPage - 1
            MT:UpdateExportWindow()
        end
    end)
    ExportInitButton(frame.exportPrev)

    frame.exportPageText = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    frame.exportPageText:SetPoint("LEFT", frame.exportPrev, "RIGHT", 2, 0)
    frame.exportPageText:SetWidth(34)
    frame.exportPageText:SetJustifyH("CENTER")

    frame.exportNext = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.exportNext:SetWidth(18); frame.exportNext:SetHeight(17)
    frame.exportNext:SetPoint("LEFT", frame.exportPageText, "RIGHT", 2, 0)
    frame.exportNext:SetText(">")
    frame.exportNext:SetScript("OnClick", function()
        MT.exportPage = (MT.exportPage or 1) + 1
        MT:UpdateExportWindow()
    end)
    ExportInitButton(frame.exportNext)

    frame.exportCopyNote = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    frame.exportCopyNote:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -8, 16)
    frame.exportCopyNote:SetWidth(202)
    frame.exportCopyNote:SetJustifyH("RIGHT")
    frame.exportCopyNote:SetTextColor(0.75, 0.75, 0.75)
    frame.exportCopyNote:Hide()

    self.exportMode = self.exportMode or EXPORT_SUMMARY
    self.exportPage = self.exportPage or 1
    frame.exportPrev:Hide(); frame.exportPageText:Hide(); frame.exportNext:Hide()
    frame.export1Polished = true
    self:UpdateExportModeButtons()
    return frame
end

function MT:UpdateExportWindow()
    local frame = self:CreateExportWindow()
    local mode = self.exportMode or EXPORT_SUMMARY
    local label = self:GetViewLabel() or "Selected Fight"
    local lines = self:BuildExportLines(mode)
    frame.exportShowingAll = false

    if mode == EXPORT_BOSS then
        local profile = self:BuildBossBreakdown()
        frame.title:SetText("Export - " .. ((profile and not profile.empty and profile.name) or "Boss Profile"))
        frame.help:SetText("Selected Boss Profile - all schools and abilities")
    elseif mode == EXPORT_DETAILED then
        frame.title:SetText("Export - " .. label)
        frame.help:SetText("Technical totals and event/count breakdown")
    else
        frame.title:SetText("Export - " .. label)
        frame.help:SetText("Compact fight summary - safe for chat sharing")
    end

    local i
    if mode == EXPORT_SUMMARY then
        frame.exportAllText = ExportJoinLines(lines)
        frame.edit:SetText(frame.exportAllText)
        self.exportPage = 1
        for i = 1, table.getn(frame.shareButtons or {}) do frame.shareButtons[i]:Show() end
        frame.exportPrev:Hide(); frame.exportPageText:Hide(); frame.exportNext:Hide()
        frame.exportCopyNote:Hide()
    else
        local wrapped = ExportWrapLines(lines)
        local pages = ExportPageCount(wrapped)
        local page = tonumber(self.exportPage) or 1
        if page < 1 then page = 1 end
        if page > pages then page = pages end
        self.exportPage = page
        frame.exportAllText = ExportJoinLines(wrapped)
        frame.edit:SetText(ExportJoinLines(ExportPageLines(wrapped, page)))

        for i = 1, table.getn(frame.shareButtons or {}) do frame.shareButtons[i]:Hide() end
        frame.exportPrev:Show(); frame.exportPageText:Show(); frame.exportNext:Show()
        frame.exportPageText:SetText(tostring(page) .. "/" .. tostring(pages))
        if page <= 1 then frame.exportPrev:Disable() else frame.exportPrev:Enable() end
        if page >= pages then frame.exportNext:Disable() else frame.exportNext:Enable() end
        frame.exportCopyNote:SetText("Select All = full report  |  chat uses Summary")
        frame.exportCopyNote:Show()
    end

    frame.edit:ClearFocus()
    self:UpdateExportModeButtons()
end

-- NavigationPolish normalizes every button white after a managed page opens.
-- Reapply the selected-grey export tab after that global typography pass.
local ExportOldApplyUniform = MT.ApplyUniformButtonText
if ExportOldApplyUniform then
    function MT:ApplyUniformButtonText(frame)
        ExportOldApplyUniform(self, frame)
        local export = self.exportFrame or getglobal("MainTankExportFrame")
        if export and frame == export then self:UpdateExportModeButtons() end
    end
end

-- Public slash surface stays compatible. Optional mode suffixes are convenient
-- power-user shortcuts, but ordinary users can do everything from the UI.
local ExportOldHandleSlash = MT.HandleSlash
function MT:HandleSlash(msg)
    local text = string.lower(tostring(msg or ""))
    text = string.gsub(text, "^%s+", "")
    text = string.gsub(text, "%s+$", "")
    if text == "export summary" or text == "report summary" then
        self.exportMode = EXPORT_SUMMARY
        self:ToggleExport()
        return
    elseif text == "export detailed" or text == "report detailed" then
        self.exportMode = EXPORT_DETAILED
        self:ToggleExport()
        return
    elseif text == "export boss" or text == "export profile" or text == "report boss" then
        self.exportMode = EXPORT_BOSS
        self:ToggleExport()
        return
    end
    return ExportOldHandleSlash(self, msg)
end
