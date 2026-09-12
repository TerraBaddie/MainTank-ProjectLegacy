-- MainTank REFAC1 - Analysis feature compatibility layer
-- Export, Boss Profiles/Breakdown, and Tank Compare historical override stack.
-- Kept together because RC3 mutates RC2 helpers captured by Export.

local MT = MainTank
local E = MT._engine
local floor = math.floor
local format = string.format
local find = string.find
local lower = string.lower
local NewData = E.NewData
local CopyTable = E.CopyTable
local GetLegacyFont = E.GetLegacyFont
local GetLegacyFontSize = E.GetLegacyFontSize
local StyleLegacyButton = E.StyleLegacyButton
local StyleLegacyWindow = E.StyleLegacyWindow
local Print = E.Print
local RC_PAGE_WIDTH = E.RC_PAGE_WIDTH
local RC_PAGE_HEIGHT = E.RC_PAGE_HEIGHT
local RC_CreatePageFrame = E.RC_CreatePageFrame

-- ============================================================================
-- v1.0.0 RC2bb - Export / Share Fight Summaries
-- Adds a managed, single-window export page with copyable report text and
-- optional Party/Raid/Guild/Say sharing. No external libraries required.
-- ============================================================================

local function RC2_MaxTimelineSecond(timeline)
    local maximum = 0
    local second
    for second in pairs(timeline or {}) do
        if type(second) == "number" and second > maximum then maximum = second end
    end
    return maximum
end

local function RC2_GetViewDuration(owner)
    if type(owner.currentView) == "number" and owner.fights[owner.currentView] then
        return owner.fights[owner.currentView].duration or 0
    end
    if owner.currentView == "CURRENT" and owner.inCombat and owner.fightStartTime then
        return GetTime() - owner.fightStartTime
    end
    if owner.currentView == "CURRENT" and owner.fights and owner.fights[1] then
        local currentEvents = owner:GetDisplayEvents() or {}
        local newestEvents = owner.fights[1].events or {}
        if table.getn(currentEvents) == table.getn(newestEvents) then
            return owner.fights[1].duration or 0
        end
    end
    local maximum = RC2_MaxTimelineSecond(owner:GetDisplayTimeline())
    if maximum > 0 then return maximum + 1 end
    return 0
end

local function RC2_GetTopEnemyAndBiggest(events)
    local enemyTotals = {}
    local topEnemy = "None"
    local topEnemyRaw = 0
    local biggestRaw = 0
    local biggestTaken = 0
    local biggestRawLabel = "None"
    local biggestTakenLabel = "None"
    local i, event, source, ability, raw, taken
    for i = 1, table.getn(events or {}) do
        event = events[i]
        source = event.source or "Unknown"
        ability = event.ability or event.kind or "Unknown"
        raw = event.raw or 0
        taken = event.taken or 0
        enemyTotals[source] = (enemyTotals[source] or 0) + raw
        if enemyTotals[source] > topEnemyRaw then
            topEnemyRaw = enemyTotals[source]
            topEnemy = source
        end
        if raw > biggestRaw then
            biggestRaw = raw
            biggestRawLabel = source .. " - " .. ability
        end
        if taken > biggestTaken then
            biggestTaken = taken
            biggestTakenLabel = source .. " - " .. ability
        end
    end
    return topEnemy, topEnemyRaw, biggestRaw, biggestRawLabel, biggestTaken, biggestTakenLabel
end

function MT:BuildExportLines()
    local data = self:GetDisplayData() or NewData()
    local events = self:GetDisplayEvents() or {}
    local mitigated, raw = self:GetTotals(data)
    local taken = data.damageTaken or 0
    local mitigation = raw > 0 and (mitigated / raw * 100) or 0
    local avoidance = (data.dodgedEstimated or 0) + (data.parriedEstimated or 0) + (data.missedEstimated or 0)
    local block = (data.blocked or 0) + (data.fullBlockedEstimated or 0)
    local resist = (data.resistedPartial or 0) + (data.resistedFullEstimated or 0)
    local duration = RC2_GetViewDuration(self)
    local topEnemy, _, biggestRaw, biggestRawLabel, biggestTaken, biggestTakenLabel = RC2_GetTopEnemyAndBiggest(events)
    local label = self:GetViewLabel() or "Selected Fight"
    local view = self.currentView == "OVERALL" and "Overall" or "Fight"

    local lines = {}
    table.insert(lines, "MainTank - " .. label)
    table.insert(lines, view .. " - Duration " .. (duration > 0 and format("%.1fs", duration) or "N/A"))
    table.insert(lines, "Raw " .. self:FormatNumber(raw) .. " - Taken " .. self:FormatNumber(taken) .. " - Stopped " .. self:FormatNumber(mitigated))
    table.insert(lines, "Mitigation " .. format("%.1f%%", mitigation) .. " - Armor " .. self:FormatNumber(data.armorReduced or 0))
    table.insert(lines, "Avoidance " .. self:FormatNumber(avoidance) .. " - Block " .. self:FormatNumber(block))
    table.insert(lines, "Resist " .. self:FormatNumber(resist) .. " - Absorb " .. self:FormatNumber(data.absorbed or 0))
    table.insert(lines, "Physical/Magic In " .. self:FormatNumber(data.physicalRaw or 0) .. "/" .. self:FormatNumber(data.magicRaw or 0))
    table.insert(lines, "Top Enemy: " .. topEnemy)
    table.insert(lines, "Biggest Raw: " .. self:FormatNumber(biggestRaw) .. " (" .. biggestRawLabel .. ")")
    table.insert(lines, "Biggest Taken: " .. self:FormatNumber(biggestTaken) .. " (" .. biggestTakenLabel .. ")")
    return lines
end

function MT:BuildExportText()
    local lines = self:BuildExportLines()
    local text = ""
    local i
    for i = 1, table.getn(lines) do
        if i > 1 then text = text .. "\n" end
        text = text .. lines[i]
    end
    return text
end

function MT:ShareExport(channel)
    channel = string.upper(channel or "SAY")
    if channel == "RAID" and GetNumRaidMembers() == 0 then
        Print("You are not currently in a raid.")
        return
    end
    if channel == "PARTY" and GetNumPartyMembers() == 0 and GetNumRaidMembers() == 0 then
        Print("You are not currently in a party.")
        return
    end
    if channel == "GUILD" and not IsInGuild() then
        Print("You are not currently in a guild.")
        return
    end

    local lines = self:BuildExportLines()
    local i
    for i = 1, table.getn(lines) do
        local message = tostring(lines[i] or "")
        message = string.gsub(message, "|", "-")
        message = string.gsub(message, "[\r\n]", " ")
        SendChatMessage(message, channel)
    end
    Print("Shared selected mitigation summary to " .. string.lower(channel) .. ".")
end

function MT:CreateExportWindow()
    if self.exportFrame then return self.exportFrame end

    local frame = CreateFrame("Frame", "MainTankExportFrame", UIParent)
    frame:SetWidth(RC_PAGE_WIDTH or 300)
    frame:SetHeight(RC_PAGE_HEIGHT or 231)
    frame:SetFrameStrata("DIALOG")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function() this:StartMoving() end)
    frame:SetScript("OnDragStop", function() this:StopMovingOrSizing() end)
    StyleLegacyWindow(frame, 0.86)
    frame:Hide()

    frame.mainButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.mainButton:SetWidth(58); frame.mainButton:SetHeight(18)
    frame.mainButton:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -8)
    frame.mainButton:SetText("MT Main")
    frame.mainButton:SetScript("OnClick", function() MT:ShowManagedPage("MAIN") end)
    StyleLegacyButton(frame.mainButton)

    frame.title = frame:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    frame.title:SetPoint("TOPLEFT", frame.mainButton, "TOPRIGHT", 5, 0)
    frame.title:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -27, -8)
    frame.title:SetJustifyH("CENTER")
    frame.title:SetText("Export Fight Summary")

    frame.close = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.close:SetWidth(18); frame.close:SetHeight(18)
    frame.close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -4, -4)
    frame.close:SetText("x")
    frame.close:SetScript("OnClick", function() MT:HideAllManagedPages(nil); MT.currentManagedPage = nil end)
    StyleLegacyButton(frame.close)

    frame.help = frame:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    frame.help:SetPoint("TOP", frame, "TOP", 0, -31)
    frame.help:SetText("Click text, then Ctrl+A and Ctrl+C to copy")
    frame.help:SetTextColor(0.85, 0.85, 0.85)

    frame.edit = CreateFrame("EditBox", nil, frame)
    frame.edit:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, -48)
    frame.edit:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -10, 42)
    frame.edit:SetMultiLine(true)
    frame.edit:SetAutoFocus(false)
    frame.edit:EnableMouse(true)
    frame.edit:SetFont("Fonts\\FRIZQT__.TTF", 10, "")
    frame.edit:SetTextInsets(5, 5, 5, 5)
    frame.edit:SetScript("OnEscapePressed", function() this:ClearFocus() end)
    frame.edit:SetScript("OnMouseUp", function() this:SetFocus() end)
    frame.edit:SetScript("OnEditFocusGained", function() this:HighlightText() end)
    frame.edit:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8", edgeFile="Interface\\Buttons\\WHITE8X8", tile=false, edgeSize=1, insets={left=1,right=1,top=1,bottom=1}})
    frame.edit:SetBackdropColor(0, 0, 0, 0.55)
    frame.edit:SetBackdropBorderColor(0.25, 0.25, 0.25, 1)

    local labels = {"Party", "Raid", "Guild", "Say"}
    local channels = {"PARTY", "RAID", "GUILD", "SAY"}
    frame.shareButtons = {}
    local i, button
    for i = 1, 4 do
        button = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        button:SetWidth(60); button:SetHeight(18)
        button:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 10 + ((i-1)*69), 12)
        button:SetText(labels[i])
        button.channel = channels[i]
        button:SetScript("OnClick", function() MT:ShareExport(this.channel) end)
        StyleLegacyButton(button)
        frame.shareButtons[i] = button
    end

    self.exportFrame = frame
    self:RegisterManagedPage("EXPORT", frame)
    return frame
end

function MT:UpdateExportWindow()
    local frame = self:CreateExportWindow()
    frame.title:SetText("Export - " .. (self:GetViewLabel() or "Selected Fight"))
    frame.edit:SetText(self:BuildExportText())
    frame.edit:ClearFocus()
end

function MT:ToggleExport()
    local frame = self:CreateExportWindow()
    self:ShowManagedPage("EXPORT", function(owner) owner:UpdateExportWindow() end)
end

local RC2_OldRefreshManagedPageRegistry = MT.RefreshManagedPageRegistry
function MT:RefreshManagedPageRegistry()
    RC2_OldRefreshManagedPageRegistry(self)
    local export = self.exportFrame or getglobal("MainTankExportFrame")
    if export then self:RegisterManagedPage("EXPORT", export) end
end

local RC2_OldCreateUI = MT.CreateUI
function MT:CreateUI()
    RC2_OldCreateUI(self)
    local frame = self.frame
    if not frame or frame.exportButton then return end

    local button = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    button:SetWidth(68); button:SetHeight(18)
    button:SetPoint("TOP", frame, "TOP", 0, -49)
    button:SetText("Export")
    button:SetScript("OnClick", function() MT:ToggleExport() end)
    button:SetScript("OnEnter", function()
        local tip = MT:GetAnalysisTooltip()
        tip:SetOwner(this, "ANCHOR_CURSOR")
        tip:SetText("Export fight summary", 1, 0.82, 0)
        tip:AddLine("Copy the selected report or share it", 0.85, 0.85, 0.85)
        tip:AddLine("to party, raid, guild, or say chat.", 0.85, 0.85, 0.85)
        tip:Show()
    end)
    button:SetScript("OnLeave", function() MT:HideAnalysisTooltip() end)
    StyleLegacyButton(button)
    frame.exportButton = button
    self:RegisterFullControl(button)
end

local RC2_OldHandleSlash = MT.HandleSlash
function MT:HandleSlash(msg)
    local raw = lower(msg or "")
    if raw == "export" or raw == "report" then
        self:ToggleExport()
        return
    elseif string.sub(raw, 1, 6) == "share " then
        local channel = string.sub(raw, 7)
        if channel == "party" or channel == "raid" or channel == "guild" or channel == "say" then
            self:ShareExport(channel)
        else
            Print("Usage: /mt share party|raid|guild|say")
        end
        return
    end
    RC2_OldHandleSlash(self, msg)
end



-- v1.0.0 RC2c - normalize Main navigation button visuals
local RC2c_OldCreateUI = MT.CreateUI
function MT:CreateUI()
    RC2c_OldCreateUI(self)
    local frame = self.frame
    if not frame then return end

    local children = {frame:GetChildren()}
    local i, child, text
    for i = 1, table.getn(children) do
        child = children[i]
        if child and child.GetObjectType and child:GetObjectType() == "Button" and child.GetText then
            text = child:GetText()
            if text == "Timeline" or text == "Biggest" or text == "Pie Chart" or text == "Pie" or text == "Details" or text == "Export" then
                -- Keep every primary navigation button on the exact same pfUI
                -- styling path and typography. Widths remain layout-specific.
                StyleLegacyButton(child)
                if child.SetFont then
                    local fontSize = GetLegacyFontSize(10)
                    local ok = child:SetFont(GetLegacyFont(), fontSize, "OUTLINE")
                    if not ok then child:SetFont("Fonts\\FRIZQT__.TTF", fontSize, "OUTLINE") end
                end
                if child.SetTextColor then child:SetTextColor(0.88, 0.88, 0.88) end
                if child.SetDisabledTextColor then child:SetDisabledTextColor(0.45, 0.45, 0.45) end
            end
        end
    end
end


-- ============================================================================
-- v1.0.0 RC3 - Boss / Encounter Mitigation Breakdown
-- Generic, server-independent encounter profile based on the primary enemy.
-- Also excludes environmental events from Export's Biggest Raw/Taken records.
-- ============================================================================

local function RC3_IsEnvironmentalEvent(event)
    if not event then return false end
    if event.environmental then return true end
    if event.source == "Environment" then return true end
    return false
end

-- Replace the RC2 helper so exported Biggest records represent enemy attacks,
-- while environmental damage remains included in all totals and event views.
RC2_GetTopEnemyAndBiggest = function(events)
    local enemyTotals = {}
    local topEnemy = "None"
    local topEnemyRaw = 0
    local biggestRaw = 0
    local biggestTaken = 0
    local biggestRawLabel = "None"
    local biggestTakenLabel = "None"
    local i, event, source, ability, raw, taken

    for i = 1, table.getn(events or {}) do
        event = events[i]
        source = event.source or "Unknown"
        ability = event.ability or event.kind or "Unknown"
        raw = event.raw or 0
        taken = event.taken or 0

        if not RC3_IsEnvironmentalEvent(event) then
            enemyTotals[source] = (enemyTotals[source] or 0) + raw
            if enemyTotals[source] > topEnemyRaw then
                topEnemyRaw = enemyTotals[source]
                topEnemy = source
            end
            if raw > biggestRaw then
                biggestRaw = raw
                biggestRawLabel = source .. " - " .. ability
            end
            if taken > biggestTaken then
                biggestTaken = taken
                biggestTakenLabel = source .. " - " .. ability
            end
        end
    end

    return topEnemy, topEnemyRaw, biggestRaw, biggestRawLabel, biggestTaken, biggestTakenLabel
end

local function RC3_SortRows(rows)
    table.sort(rows, function(a, b)
        if (a.raw or 0) == (b.raw or 0) then
            return tostring(a.name or "") < tostring(b.name or "")
        end
        return (a.raw or 0) > (b.raw or 0)
    end)
end

function MT:BuildBossBreakdown()
    local events = self:GetDisplayEvents() or {}
    local enemyTotals = {}
    local totalEnemyRaw = 0
    local primary = nil
    local primaryRaw = 0
    local i, event, source, raw

    -- Infer the primary encounter enemy by total non-environment raw damage.
    for i = 1, table.getn(events) do
        event = events[i]
        if not RC3_IsEnvironmentalEvent(event) then
            source = event.source or "Unknown"
            raw = event.raw or 0
            enemyTotals[source] = (enemyTotals[source] or 0) + raw
            totalEnemyRaw = totalEnemyRaw + raw
            if enemyTotals[source] > primaryRaw then
                primaryRaw = enemyTotals[source]
                primary = source
            end
        end
    end

    if not primary then
        return {
            name = "No enemy data",
            raw = 0, taken = 0, stopped = 0, mitigation = 0,
            share = 0, addsRaw = 0, schools = {}, abilities = {},
            criticals = 0, crushings = 0, events = 0
        }
    end

    local profile = {
        name = primary,
        raw = 0,
        taken = 0,
        armor = 0,
        avoidance = 0,
        block = 0,
        resist = 0,
        absorb = 0,
        schoolsMap = {},
        abilitiesMap = {},
        schools = {},
        abilities = {},
        criticals = 0,
        crushings = 0,
        events = 0,
        addsRaw = math.max(0, totalEnemyRaw - primaryRaw),
        share = totalEnemyRaw > 0 and (primaryRaw / totalEnemyRaw * 100) or 0
    }

    for i = 1, table.getn(events) do
        event = events[i]
        if not RC3_IsEnvironmentalEvent(event) and (event.source or "Unknown") == primary then
            local school = event.school or "Unknown"
            local ability = event.ability or event.kind or "Unknown"
            local schoolRow = profile.schoolsMap[school]
            local abilityRow = profile.abilitiesMap[ability]

            if not schoolRow then
                schoolRow = {name = school, raw = 0, taken = 0}
                profile.schoolsMap[school] = schoolRow
            end
            if not abilityRow then
                abilityRow = {name = ability, school = school, raw = 0, taken = 0}
                profile.abilitiesMap[ability] = abilityRow
            end

            raw = event.raw or 0
            local taken = event.taken or 0
            profile.raw = profile.raw + raw
            profile.taken = profile.taken + taken
            profile.armor = profile.armor + (event.armor or 0)
            profile.avoidance = profile.avoidance + (event.avoidance or 0)
            profile.block = profile.block + (event.block or 0)
            profile.resist = profile.resist + (event.resist or 0)
            profile.absorb = profile.absorb + (event.absorb or 0)
            profile.events = profile.events + 1
            if event.critical then profile.criticals = profile.criticals + 1 end
            if event.crushing then profile.crushings = profile.crushings + 1 end

            schoolRow.raw = schoolRow.raw + raw
            schoolRow.taken = schoolRow.taken + taken
            abilityRow.raw = abilityRow.raw + raw
            abilityRow.taken = abilityRow.taken + taken
        end
    end

    for _, event in pairs(profile.schoolsMap) do table.insert(profile.schools, event) end
    for _, event in pairs(profile.abilitiesMap) do table.insert(profile.abilities, event) end
    RC3_SortRows(profile.schools)
    RC3_SortRows(profile.abilities)

    profile.stopped = math.max(0, profile.raw - profile.taken)
    profile.mitigation = profile.raw > 0 and (profile.stopped / profile.raw * 100) or 0
    return profile
end

function MT:CreateBossWindow()
    if self.bossFrame then return self.bossFrame end

    local frame = CreateFrame("Frame", "MainTankBossFrame", UIParent)
    frame:SetWidth(RC_PAGE_WIDTH or 300)
    frame:SetHeight(RC_PAGE_HEIGHT or 231)
    frame:SetFrameStrata("DIALOG")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function() this:StartMoving() end)
    frame:SetScript("OnDragStop", function() this:StopMovingOrSizing() end)
    StyleLegacyWindow(frame, 0.86)
    frame:Hide()

    frame.mainButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.mainButton:SetWidth(58); frame.mainButton:SetHeight(18)
    frame.mainButton:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -8)
    frame.mainButton:SetText("MT Main")
    frame.mainButton:SetScript("OnClick", function() MT:ShowManagedPage("MAIN") end)
    StyleLegacyButton(frame.mainButton)

    frame.title = frame:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    frame.title:SetPoint("TOPLEFT", frame.mainButton, "TOPRIGHT", 4, 0)
    frame.title:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -26, -8)
    frame.title:SetJustifyH("CENTER")
    frame.title:SetText("Boss Breakdown")

    frame.close = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.close:SetWidth(18); frame.close:SetHeight(18)
    frame.close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -4, -4)
    frame.close:SetText("x")
    frame.close:SetScript("OnClick", function() MT:HideAllManagedPages(nil); MT.currentManagedPage = nil end)
    StyleLegacyButton(frame.close)

    frame.summary = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    frame.summary:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, -33)
    frame.summary:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -10, -33)
    frame.summary:SetJustifyH("LEFT")

    frame.schoolHeader = frame:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    frame.schoolHeader:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, -77)
    frame.schoolHeader:SetText("Damage Schools")

    frame.schoolRows = {}
    for i = 1, 3 do
        local row = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        row:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -77 - (i * 15))
        row:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -10, -77 - (i * 15))
        row:SetJustifyH("LEFT")
        frame.schoolRows[i] = row
    end

    frame.abilityHeader = frame:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    frame.abilityHeader:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, -130)
    frame.abilityHeader:SetText("Top Boss Abilities")

    frame.abilityRows = {}
    for i = 1, 3 do
        local row = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        row:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -130 - (i * 15))
        row:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -10, -130 - (i * 15))
        row:SetJustifyH("LEFT")
        frame.abilityRows[i] = row
    end

    frame.footer = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    frame.footer:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 10, 10)
    frame.footer:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -10, 10)
    frame.footer:SetJustifyH("LEFT")

    self.bossFrame = frame
    self:RegisterManagedPage("BOSS", frame)
    return frame
end

function MT:UpdateBossWindow()
    local frame = self:CreateBossWindow()
    local profile = self:BuildBossBreakdown()
    frame.title:SetText("Boss Breakdown - " .. (profile.name or "Unknown"))
    frame.summary:SetText(
        "Raw " .. self:FormatNumber(profile.raw or 0) ..
        "   Taken " .. self:FormatNumber(profile.taken or 0) ..
        "\nStopped " .. self:FormatNumber(profile.stopped or 0) ..
        "   Mitigation " .. format("%.1f%%", profile.mitigation or 0) ..
        "\nBoss share " .. format("%.1f%%", profile.share or 0) ..
        "   Events " .. tostring(profile.events or 0)
    )

    local i, row
    for i = 1, 3 do
        row = profile.schools[i]
        if row then
            frame.schoolRows[i]:SetText(row.name .. "   Raw " .. self:FormatNumber(row.raw) .. "   Taken " .. self:FormatNumber(row.taken))
        else
            frame.schoolRows[i]:SetText("")
        end

        row = profile.abilities[i]
        if row then
            frame.abilityRows[i]:SetText(row.name .. " [" .. (row.school or "Unknown") .. "]   " .. self:FormatNumber(row.raw) .. "/" .. self:FormatNumber(row.taken))
        else
            frame.abilityRows[i]:SetText("")
        end
    end

    frame.footer:SetText(
        "Armor " .. self:FormatNumber(profile.armor or 0) ..
        "  Avoid " .. self:FormatNumber(profile.avoidance or 0) ..
        "  Block " .. self:FormatNumber(profile.block or 0) ..
        "\nResist " .. self:FormatNumber(profile.resist or 0) ..
        "  Crit " .. tostring(profile.criticals or 0) ..
        "  Crush " .. tostring(profile.crushings or 0) ..
        "  Adds " .. self:FormatNumber(profile.addsRaw or 0)
    )
end

function MT:ToggleBossBreakdown()
    self:CreateBossWindow()
    self:ShowManagedPage("BOSS", function(owner) owner:UpdateBossWindow() end)
end

local RC3_OldRefreshManagedPageRegistry = MT.RefreshManagedPageRegistry
function MT:RefreshManagedPageRegistry()
    RC3_OldRefreshManagedPageRegistry(self)
    local boss = self.bossFrame or getglobal("MainTankBossFrame")
    if boss then self:RegisterManagedPage("BOSS", boss) end
end

local RC3_OldCreateUI = MT.CreateUI
function MT:CreateUI()
    RC3_OldCreateUI(self)
    local frame = self.frame
    if not frame or frame.bossButton then return end

    -- Keep Export and Boss balanced in the center row.
    if frame.exportButton then
        frame.exportButton:ClearAllPoints()
        frame.exportButton:SetWidth(62)
        frame.exportButton:SetPoint("TOP", frame, "TOP", -34, -49)
    end

    local button = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    button:SetWidth(62); button:SetHeight(18)
    button:SetPoint("TOP", frame, "TOP", 34, -49)
    button:SetText("Boss")
    button:SetScript("OnClick", function() MT:ToggleBossBreakdown() end)
    button:SetScript("OnEnter", function()
        local tip = MT:GetAnalysisTooltip()
        tip:SetOwner(this, "ANCHOR_CURSOR")
        tip:SetText("Boss mitigation breakdown", 1, 0.82, 0)
        tip:AddLine("Profiles the primary enemy by raw damage.", 0.85, 0.85, 0.85)
        tip:AddLine("Adds and environment remain separate.", 0.85, 0.85, 0.85)
        tip:Show()
    end)
    button:SetScript("OnLeave", function() MT:HideAnalysisTooltip() end)
    StyleLegacyButton(button)
    frame.bossButton = button
    self:RegisterFullControl(button)
end

local RC3_OldHandleSlash = MT.HandleSlash
function MT:HandleSlash(msg)
    local raw = lower(msg or "")
    if raw == "boss" or raw == "encounter" then
        self:ToggleBossBreakdown()
        return
    end
    RC3_OldHandleSlash(self, msg)
end


-- ============================================================================
-- v1.0.0 RC3b - Persistent skull-level Boss Profiles browser
-- Release policy: only true skull-level targets (UnitLevel == -1) are eligible.
-- The old Bloodsail Raider development override was retired in RELEASEPOLISH1.
-- ============================================================================

local RC3B_MAX_BOSS_PROFILES = 30

local function RC3B_IsEligibleBossName(name)
    if not name or name == "" or name == "Environment" or name == "Unknown" then return false end
    local memory = MT.targetDamageMemory and MT.targetDamageMemory[name]
    return memory and memory.isBoss and true or false
end

local function RC3B_BuildProfileFromEvents(events, bossName, duration, label, isDebug)
    local profile = {
        name = bossName or "Unknown Boss",
        label = label or bossName or "Unknown Boss",
        duration = duration or 0,
        raw = 0, taken = 0, armor = 0, avoidance = 0, block = 0,
        resist = 0, absorb = 0, flatDR = 0, physicalDR = 0, magicDR = 0,
        events = 0, criticals = 0, crushings = 0,
        addsRaw = 0, schoolsMap = {}, abilitiesMap = {}, schools = {}, abilities = {},
        isDebug = isDebug and true or false,
        bossProfileVersion = 2,
        savedAt = type(time) == "function" and time() or nil
    }

    local totalEnemyRaw = 0
    local i, event, source, raw, taken, school, ability, row
    for i = 1, table.getn(events or {}) do
        event = events[i]
        if not RC3_IsEnvironmentalEvent(event) then
            source = event.source or "Unknown"
            raw = event.raw or 0
            totalEnemyRaw = totalEnemyRaw + raw
            if source == bossName then
                taken = event.taken or 0
                school = event.school or "Unknown"
                ability = event.ability or event.kind or "Unknown"

                profile.raw = profile.raw + raw
                profile.taken = profile.taken + taken
                profile.armor = profile.armor + (event.armor or 0)
                profile.avoidance = profile.avoidance + (event.avoidance or 0)
                profile.block = profile.block + (event.block or 0)
                profile.resist = profile.resist + (event.resist or 0)
                profile.absorb = profile.absorb + (event.absorb or 0)
                -- RC6-complete Boss Profile attribution. These fields already
                -- live on the authoritative event stream; the Boss page should
                -- not silently omit them from its stopped-damage explanation.
                profile.flatDR = profile.flatDR + (event.flatDR or 0)
                profile.physicalDR = profile.physicalDR + (event.physicalDR or 0)
                profile.magicDR = profile.magicDR + (event.magicDR or 0)
                profile.events = profile.events + 1
                if event.critical then profile.criticals = profile.criticals + 1 end
                if event.crushing then profile.crushings = profile.crushings + 1 end

                row = profile.schoolsMap[school]
                if not row then
                    row = {name = school, raw = 0, taken = 0}
                    profile.schoolsMap[school] = row
                end
                row.raw = row.raw + raw
                row.taken = row.taken + taken

                row = profile.abilitiesMap[ability]
                if not row then
                    row = {name = ability, school = school, raw = 0, taken = 0}
                    profile.abilitiesMap[ability] = row
                end
                row.raw = row.raw + raw
                row.taken = row.taken + taken
            end
        end
    end

    for _, row in pairs(profile.schoolsMap) do table.insert(profile.schools, row) end
    for _, row in pairs(profile.abilitiesMap) do table.insert(profile.abilities, row) end
    RC3_SortRows(profile.schools)
    RC3_SortRows(profile.abilities)

    profile.stopped = math.max(0, profile.raw - profile.taken)
    profile.mitigation = profile.raw > 0 and (profile.stopped / profile.raw * 100) or 0
    profile.addsRaw = math.max(0, totalEnemyRaw - profile.raw)
    profile.share = totalEnemyRaw > 0 and (profile.raw / totalEnemyRaw * 100) or 0
    profile.schoolsMap = nil
    profile.abilitiesMap = nil
    return profile
end

-- Persist boss history with the existing character profile.
local RC3B_OldSyncPersistentData = MT.SyncPersistentData
function MT:SyncPersistentData()
    RC3B_OldSyncPersistentData(self)
    if self.profile then
        self.profile.bossHistory = self.bossHistory or {}
        self.profile.bossProfileIndex = self.bossProfileIndex or 1
    end
end

local RC3B_OldRestorePersistentData = MT.RestorePersistentData
function MT:RestorePersistentData()
    RC3B_OldRestorePersistentData(self)
    self.bossHistory = (self.profile and self.profile.bossHistory) or {}
    self.bossProfileIndex = tonumber(self.profile and self.profile.bossProfileIndex) or 1
    if self.bossProfileIndex < 1 then self.bossProfileIndex = 1 end
    if self.bossProfileIndex > table.getn(self.bossHistory) then self.bossProfileIndex = math.max(1, table.getn(self.bossHistory)) end
end

local RC3B_OldResetSession = MT.ResetSession
function MT:ResetSession()
    RC3B_OldResetSession(self)
    self.bossHistory = {}
    self.bossProfileIndex = 1
    if self.profile then
        self.profile.bossHistory = self.bossHistory
        self.profile.bossProfileIndex = 1
    end
    self:SyncPersistentData()
end

-- Mark targeted skull mobs immediately. UnitDamage capture already runs on
-- PLAYER_TARGET_CHANGED and repeatedly in combat.
local RC3B_OldCaptureTargetDamage = MT.CaptureTargetDamage
function MT:CaptureTargetDamage()
    RC3B_OldCaptureTargetDamage(self)
    if not UnitExists("target") or UnitIsFriend("player", "target") then return end
    local name = UnitName("target")
    if not name then return end
    local level = UnitLevel("target")
    if level == -1 then
        local memory = self.targetDamageMemory[name] or {}
        memory.level = level
        memory.isBoss = true
        memory.debugBoss = nil
        self.targetDamageMemory[name] = memory
        self.currentBossCandidates = self.currentBossCandidates or {}
        self.currentBossCandidates[name] = {isBoss = true}
    end
end

local RC3B_OldStartCombat = MT.StartCombat
function MT:StartCombat()
    self.currentBossCandidates = {}
    RC3B_OldStartCombat(self)
    -- Capture the current target again after the encounter tables reset.
    self:CaptureTargetDamage()
end

-- Save one profile for every eligible skull-level boss involved in the fight.
local RC3B_OldEndCombat = MT.EndCombat
function MT:EndCombat()
    local eventsSnapshot = CopyTable(self.events or {})
    local candidates = CopyTable(self.currentBossCandidates or {})
    local duration = self.fightStartTime and (GetTime() - self.fightStartTime) or 0
    local previousFightID = self.fights and self.fights[1] and self.fights[1].id
    RC3B_OldEndCombat(self)

    -- BOSSGUARD1: targeting/briefly touching a skull mob during another pull
    -- must never promote the whole pull to BOSS.  A detailed fight is a Boss
    -- encounter only when the authoritative skull candidate is also the
    -- finalized fight's primary incoming enemy.  GenerateFightMetadata derives
    -- primaryEnemy from actual incoming events, so target selection alone can
    -- never satisfy this identity check.
    local finalized = self.fights and self.fights[1]
    if finalized and finalized.id ~= previousFightID and finalized.combatType ~= "PVP" then
        local primary = finalized.primaryEnemy
        local info = primary and candidates[primary]
        if info and info.isBoss then
            finalized.isBoss = true
            finalized.bossName = primary
            finalized.bossSkull = true
            finalized.bossIdentityVersion = 1
            finalized.archivePriority = 4
        elseif finalized.isBoss == true and finalized.bossName and finalized.bossName ~= primary then
            -- Never carry a stale Boss stamp onto a non-boss primary enemy.
            finalized.isBoss = false
            finalized.bossName = nil
            finalized.bossSkull = nil
            finalized.bossIdentityVersion = nil
            finalized.archivePriority = nil
        end
    end

    self.bossHistory = self.bossHistory or {}
    local name, info, profile
    local finalizedDuration = finalized and tonumber(finalized.duration) or duration
    for name, info in pairs(candidates) do
        if RC3B_IsEligibleBossName(name) then
            profile = RC3B_BuildProfileFromEvents(eventsSnapshot, name, finalizedDuration, name, nil)
            if profile.raw > 0 then
                -- Tie new profiles to their authoritative detailed encounter.
                -- This makes profile recovery/deduplication exact after Archive
                -- restore without changing the existing bounded bossHistory store.
                profile.fightID = finalized and finalized.id or nil
                profile.primaryEnemy = finalized and finalized.primaryEnemy or nil
                -- One tiny timestamp on the detailed Boss record makes future
                -- profile recovery able to preserve the original saved time.
                -- It adds no event payload and is only written for boss fights.
                if finalized and not finalized.savedAt then finalized.savedAt = profile.savedAt end
                table.insert(self.bossHistory, 1, profile)
            end
        end
    end
    while table.getn(self.bossHistory) > RC3B_MAX_BOSS_PROFILES do table.remove(self.bossHistory) end
    self.bossProfileIndex = table.getn(self.bossHistory) > 0 and 1 or 1
    self.currentBossCandidates = {}
    self:SyncPersistentData()
end

-- Replace the old primary-enemy breakdown with the selected saved profile.
function MT:BuildBossBreakdown()
    self.bossHistory = self.bossHistory or {}
    local count = table.getn(self.bossHistory)
    if count == 0 then
        return {
            name = "No Boss Profiles",
            raw = 0, taken = 0, stopped = 0, mitigation = 0,
            share = 0, addsRaw = 0, schools = {}, abilities = {},
            armor = 0, avoidance = 0, block = 0, resist = 0, absorb = 0,
            flatDR = 0, physicalDR = 0, magicDR = 0,
            criticals = 0, crushings = 0, events = 0, duration = 0,
            empty = true
        }
    end
    if not self.bossProfileIndex or self.bossProfileIndex < 1 then self.bossProfileIndex = 1 end
    if self.bossProfileIndex > count then self.bossProfileIndex = count end
    return self.bossHistory[self.bossProfileIndex]
end

-- Add previous/next profile controls to the existing Boss frame.
local RC3B_OldCreateBossWindow = MT.CreateBossWindow
function MT:CreateBossWindow()
    local frame = RC3B_OldCreateBossWindow(self)
    if frame.profilePrev then return frame end

    frame.profilePrev = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.profilePrev:SetWidth(22); frame.profilePrev:SetHeight(17)
    frame.profilePrev:SetPoint("TOPLEFT", frame, "TOPLEFT", 78, -27)
    frame.profilePrev:SetText("<")
    frame.profilePrev:SetScript("OnClick", function()
        if (MT.bossProfileIndex or 1) > 1 then
            MT.bossProfileIndex = MT.bossProfileIndex - 1
            MT:UpdateBossWindow()
            MT:SyncPersistentData()
        end
    end)
    StyleLegacyButton(frame.profilePrev)

    frame.profileCount = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    frame.profileCount:SetPoint("LEFT", frame.profilePrev, "RIGHT", 6, 0)
    frame.profileCount:SetWidth(88)
    frame.profileCount:SetJustifyH("CENTER")
    frame.profileCount:SetText("0 / 0")

    frame.profileNext = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.profileNext:SetWidth(22); frame.profileNext:SetHeight(17)
    frame.profileNext:SetPoint("LEFT", frame.profileCount, "RIGHT", 6, 0)
    frame.profileNext:SetText(">")
    frame.profileNext:SetScript("OnClick", function()
        local count = table.getn(MT.bossHistory or {})
        if (MT.bossProfileIndex or 1) < count then
            MT.bossProfileIndex = MT.bossProfileIndex + 1
            MT:UpdateBossWindow()
            MT:SyncPersistentData()
        end
    end)
    StyleLegacyButton(frame.profileNext)

    -- Move the summary down slightly to make room for profile paging.
    frame.summary:ClearAllPoints()
    frame.summary:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, -48)
    frame.summary:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -10, -48)
    frame.schoolHeader:ClearAllPoints()
    frame.schoolHeader:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, -91)
    local i
    for i = 1, 3 do
        frame.schoolRows[i]:ClearAllPoints()
        frame.schoolRows[i]:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -91 - (i * 15))
        frame.schoolRows[i]:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -10, -91 - (i * 15))
    end
    frame.abilityHeader:ClearAllPoints()
    frame.abilityHeader:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, -144)
    for i = 1, 3 do
        frame.abilityRows[i]:ClearAllPoints()
        frame.abilityRows[i]:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -144 - (i * 15))
        frame.abilityRows[i]:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -10, -144 - (i * 15))
    end

    return frame
end

function MT:UpdateBossWindow()
    local frame = self:CreateBossWindow()
    local profile = self:BuildBossBreakdown()
    local count = table.getn(self.bossHistory or {})
    local index = count > 0 and (self.bossProfileIndex or 1) or 0

    frame.profileCount:SetText(tostring(index) .. " / " .. tostring(count))
    if index <= 1 then frame.profilePrev:Disable() else frame.profilePrev:Enable() end
    if index >= count then frame.profileNext:Disable() else frame.profileNext:Enable() end

    if profile.empty then
        frame.title:SetText("Boss Profiles")
        frame.summary:SetText("No skull-level boss encounters recorded.\nTarget a ?? boss during combat to create a profile.")
        local i
        for i = 1, 3 do frame.schoolRows[i]:SetText(""); frame.abilityRows[i]:SetText("") end
        frame.footer:SetText("")
        return
    end

    frame.title:SetText((profile.isDebug and "TEST Boss Profile - " or "Boss Profile - ") .. (profile.name or "Unknown"))
    frame.summary:SetText(
        "Duration " .. format("%.1fs", profile.duration or 0) ..
        "   Raw " .. self:FormatNumber(profile.raw or 0) ..
        "   Taken " .. self:FormatNumber(profile.taken or 0) ..
        "\nStopped " .. self:FormatNumber(profile.stopped or 0) ..
        "   Mitigation " .. format("%.1f%%", profile.mitigation or 0) ..
        "   Share " .. format("%.1f%%", profile.share or 0)
    )

    local i, row
    for i = 1, 3 do
        row = profile.schools and profile.schools[i]
        frame.schoolRows[i]:SetText(row and (row.name .. "   " .. self:FormatNumber(row.raw) .. "/" .. self:FormatNumber(row.taken)) or "")
        row = profile.abilities and profile.abilities[i]
        frame.abilityRows[i]:SetText(row and (row.name .. " [" .. (row.school or "Unknown") .. "]   " .. self:FormatNumber(row.raw) .. "/" .. self:FormatNumber(row.taken)) or "")
    end

    frame.footer:SetText(
        "Armor " .. self:FormatNumber(profile.armor or 0) ..
        "  Avoid " .. self:FormatNumber(profile.avoidance or 0) ..
        "  Block " .. self:FormatNumber(profile.block or 0) ..
        "\nResist " .. self:FormatNumber(profile.resist or 0) ..
        "  Crit " .. tostring(profile.criticals or 0) ..
        "  Crush " .. tostring(profile.crushings or 0) ..
        "  Adds " .. self:FormatNumber(profile.addsRaw or 0)
    )
end

-- Update the Boss button tooltip to describe persistent skull-only profiles.
local RC3B_OldCreateUI = MT.CreateUI
function MT:CreateUI()
    RC3B_OldCreateUI(self)
    local button = self.frame and self.frame.bossButton
    if button then
        button:SetScript("OnEnter", function()
            local tip = MT:GetAnalysisTooltip()
            tip:SetOwner(this, "ANCHOR_CURSOR")
            tip:SetText("Boss Profiles", 1, 0.82, 0)
            tip:AddLine("Stores one profile per ?? boss encounter.", 0.85, 0.85, 0.85)
            tip:AddLine("Use < and > to browse saved encounters.", 0.85, 0.85, 0.85)
            tip:Show()
        end)
    end
end


-- ============================================================================
-- v1.0.0 RC4 - Tank Comparison + Details event pager fix
-- Fixes the compact one-event Details pager being clamped by the older
-- two-events-per-page implementation, and adds compact group summary sync.
-- ============================================================================

-- DETAILS PAGER FIX -----------------------------------------------------------
-- RC1k intentionally shows one event per page. Older RC1f code still runs first
-- and clamps detailsEventPage to ceil(eventCount / 2). Preserve the page the
-- user actually requested and redraw the compact card after legacy refreshes.
local RC4_OldUpdateDetailsWindow = MT.UpdateDetailsWindow
function MT:UpdateDetailsWindow()
    local requestedPage = tonumber(self.detailsEventPage) or 1
    RC4_OldUpdateDetailsWindow(self)

    local frame = self.detailsFrame
    if not frame or not frame.rc1kEventRow then return end
    local events = self:GetFilteredDetailEvents() or {}
    local count = table.getn(events)
    local pages = math.max(1, count)

    if requestedPage < 1 then requestedPage = 1 end
    if requestedPage > pages then requestedPage = pages end
    self.detailsEventPage = requestedPage

    if frame.rc1jEventCount then frame.rc1jEventCount:SetText(count .. " events") end
    if frame.eventPageText then frame.eventPageText:SetText(requestedPage .. "/" .. pages) end
    if frame.eventPrev then
        if requestedPage > 1 then frame.eventPrev:Enable() else frame.eventPrev:Disable() end
    end
    if frame.eventNext then
        if requestedPage < pages then frame.eventNext:Enable() else frame.eventNext:Disable() end
    end

    local eventData = events[requestedPage]
    if eventData then
        self.detailsSelectedEvent = requestedPage
        local raw = eventData.raw or 0
        local taken = eventData.taken or 0
        local stopped = math.max(0, raw - taken)
        frame.rc1kEventRow.data = eventData
        frame.rc1kEventRow.eventIndex = requestedPage
        frame.rc1kEventRow.line1:SetText(format("%.1fs  %s - %s",
            eventData.time or 0,
            eventData.source or "Unknown",
            eventData.ability or eventData.kind or "Unknown"))
        frame.rc1kEventRow.line2:SetText(format("Raw %s   Stopped %s   Taken %s",
            self:FormatNumber(raw), self:FormatNumber(stopped), self:FormatNumber(taken)))
        frame.rc1kEventRow.highlight:Show()
        frame.rc1kEventRow:Show()
    else
        self.detailsSelectedEvent = nil
        frame.rc1kEventRow.data = nil
        frame.rc1kEventRow.eventIndex = nil
        frame.rc1kEventRow.line1:SetText("No matching events")
        frame.rc1kEventRow.line2:SetText("")
        frame.rc1kEventRow.highlight:Hide()
        frame.rc1kEventRow:Show()
    end
end

-- TANK SUMMARY SYNC -----------------------------------------------------------
local RC4_PREFIX = "MTANK1"
local RC4_MAX_ROWS = 4

local function RC4_SanitizeField(value)
    local text = tostring(value or "")
    text = string.gsub(text, ";", ",")
    text = string.gsub(text, "[\r\n]", " ")
    return text
end

local function RC4_Avoidance(data)
    return (data.dodgedEstimated or 0) + (data.parriedEstimated or 0) + (data.missedEstimated or 0)
end

local function RC4_Block(data)
    return (data.blocked or 0) + (data.fullBlockedEstimated or 0)
end

local function RC4_Resist(data)
    return (data.resistedPartial or 0) + (data.resistedFullEstimated or 0)
end

function MT:BuildTankSummaryFromFight(fight)
    if not fight or type(fight) ~= "table" then return nil end
    local data = fight.data or NewData()
    local stopped, raw = self:GetTotals(data)
    local taken = data.damageTaken or 0
    if raw <= 0 then return nil end
    local _, class = UnitClass("player")
    return {
        player = self.playerName or UnitName("player") or "Unknown",
        class = class or "UNKNOWN",
        label = fight.label or fight.primaryEnemy or "Fight",
        enemy = fight.primaryEnemy or "Unknown",
        duration = fight.duration or 0,
        raw = raw,
        taken = taken,
        stopped = stopped,
        armor = data.armorReduced or 0,
        avoidance = RC4_Avoidance(data),
        block = RC4_Block(data),
        resist = RC4_Resist(data),
        absorb = data.absorbed or 0,
        physical = data.physicalRaw or 0,
        magic = data.magicRaw or 0,
        receivedAt = GetTime(),
        savedAt = type(time) == "function" and time() or 0,
        localPlayer = true
    }
end

function MT:BuildTankSummaryFromDisplay()
    local data = self:GetDisplayData() or NewData()
    local stopped, raw = self:GetTotals(data)
    if raw <= 0 then return nil end
    local _, class = UnitClass("player")
    return {
        player = self.playerName or UnitName("player") or "Unknown",
        class = class or "UNKNOWN",
        label = self:GetViewLabel() or "Selected Fight",
        enemy = (self.currentView ~= "OVERALL" and self.fights and self.fights[1] and self.fights[1].primaryEnemy) or "Mixed",
        duration = RC2_GetViewDuration(self),
        raw = raw,
        taken = data.damageTaken or 0,
        stopped = stopped,
        armor = data.armorReduced or 0,
        avoidance = RC4_Avoidance(data),
        block = RC4_Block(data),
        resist = RC4_Resist(data),
        absorb = data.absorbed or 0,
        physical = data.physicalRaw or 0,
        magic = data.magicRaw or 0,
        receivedAt = GetTime(),
        savedAt = type(time) == "function" and time() or 0,
        localPlayer = true
    }
end

function MT:EncodeTankSummary(summary)
    if not summary then return nil end
    local fields = {
        "1",
        floor(summary.raw or 0), floor(summary.taken or 0), floor(summary.stopped or 0),
        floor(summary.armor or 0), floor(summary.avoidance or 0), floor(summary.block or 0),
        floor(summary.resist or 0), floor(summary.absorb or 0),
        format("%.1f", summary.duration or 0),
        floor(summary.physical or 0), floor(summary.magic or 0),
        RC4_SanitizeField(summary.class), RC4_SanitizeField(summary.enemy), RC4_SanitizeField(summary.label)
    }
    local message = ""
    local i
    for i = 1, table.getn(fields) do
        if i > 1 then message = message .. ";" end
        message = message .. tostring(fields[i])
    end
    return message
end

local function RC4_Split(message)
    local result = {}
    local start = 1
    local pos
    message = tostring(message or "")
    while true do
        pos = string.find(message, ";", start, true)
        if not pos then
            table.insert(result, string.sub(message, start))
            break
        end
        table.insert(result, string.sub(message, start, pos - 1))
        start = pos + 1
    end
    return result
end

function MT:DecodeTankSummary(message, sender)
    local f = RC4_Split(message)
    if f[1] ~= "1" or table.getn(f) < 15 then return nil end
    local summary = {
        player = sender or "Unknown",
        raw = tonumber(f[2]) or 0,
        taken = tonumber(f[3]) or 0,
        stopped = tonumber(f[4]) or 0,
        armor = tonumber(f[5]) or 0,
        avoidance = tonumber(f[6]) or 0,
        block = tonumber(f[7]) or 0,
        resist = tonumber(f[8]) or 0,
        absorb = tonumber(f[9]) or 0,
        duration = tonumber(f[10]) or 0,
        physical = tonumber(f[11]) or 0,
        magic = tonumber(f[12]) or 0,
        class = f[13] or "UNKNOWN",
        enemy = f[14] or "Unknown",
        label = f[15] or "Fight",
        receivedAt = GetTime(),
        savedAt = type(time) == "function" and time() or 0,
        localPlayer = false
    }
    if summary.raw <= 0 then return nil end
    return summary
end

function MT:StoreTankSummary(summary)
    if not summary or not summary.player then return end
    self.tankComparisonLatest = self.tankComparisonLatest or {}
    self.tankComparisonLatest[summary.player] = summary
    if self.compareFrame and self.compareFrame:IsVisible() then self:UpdateTankCompareWindow() end
end

function MT:SendTankSummary(summary, quiet)
    if not summary then return false end
    self:StoreTankSummary(summary)
    if type(SendAddonMessage) ~= "function" then
        if not quiet then Print("Addon-message sync is unavailable on this client.") end
        return false
    end

    local channel
    if GetNumRaidMembers() > 0 then channel = "RAID"
    elseif GetNumPartyMembers() > 0 then channel = "PARTY"
    else
        if not quiet then Print("Tank comparison sync requires a party or raid.") end
        return false
    end

    local message = self:EncodeTankSummary(summary)
    if not message then return false end
    SendAddonMessage(RC4_PREFIX, message, channel)
    if not quiet then Print("Shared mitigation summary with " .. string.lower(channel) .. " members running MainTank.") end
    return true
end

function MT:SyncLatestTankFight(quiet)
    local summary
    if self.fights and self.fights[1] then summary = self:BuildTankSummaryFromFight(self.fights[1]) end
    if not summary then summary = self:BuildTankSummaryFromDisplay() end
    if not summary then
        if not quiet then Print("No mitigation fight is available to sync.") end
        return false
    end
    return self:SendTankSummary(summary, quiet)
end

-- Receive compact summaries on a dedicated frame so the mature combat event
-- dispatcher does not need to be rewritten.
local rc4CommFrame = CreateFrame("Frame", "MainTankTankSyncFrame")
rc4CommFrame:RegisterEvent("CHAT_MSG_ADDON")
rc4CommFrame:SetScript("OnEvent", function()
    if event ~= "CHAT_MSG_ADDON" or arg1 ~= RC4_PREFIX then return end
    local sender = arg4 or "Unknown"
    if sender == (MT.playerName or UnitName("player")) then return end
    local summary = MT:DecodeTankSummary(arg2, sender)
    if summary then MT:StoreTankSummary(summary) end
end)

-- Automatically publish the just-finished fight. Only a compact summary is
-- sent; no events, timelines, or SavedVariables are transferred.
local RC4_OldEndCombat = MT.EndCombat
function MT:EndCombat()
    RC4_OldEndCombat(self)
    if self.fights and self.fights[1] then
        local summary = self:BuildTankSummaryFromFight(self.fights[1])
        if summary then self:SendTankSummary(summary, true) end
    end
end

-- COMPARISON PAGE -------------------------------------------------------------
local function RC4_GetCompareRows(owner)
    owner.tankComparisonLatest = owner.tankComparisonLatest or {}
    local rows = {}
    local _, summary
    for _, summary in pairs(owner.tankComparisonLatest) do
        if summary and (summary.raw or 0) > 0 then table.insert(rows, summary) end
    end
    table.sort(rows, function(a, b)
        local ma = (a.raw or 0) > 0 and ((a.stopped or 0) / (a.raw or 1)) or 0
        local mb = (b.raw or 0) > 0 and ((b.stopped or 0) / (b.raw or 1)) or 0
        if ma == mb then return (a.raw or 0) > (b.raw or 0) end
        return ma > mb
    end)
    return rows
end

function MT:CreateTankCompareWindow()
    if self.compareFrame then return self.compareFrame end
    local frame = RC_CreatePageFrame("MainTankTankCompareFrame", "Tank Comparison")

    frame.warning = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.warning:SetPoint("TOPLEFT", frame, "TOPLEFT", 9, -30)
    frame.warning:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -9, -30)
    frame.warning:SetJustifyH("CENTER")
    frame.warning:SetText("Latest synced fights; assignments and durations may differ.")
    frame.warning:SetTextColor(1, 0.82, 0)

    local headers = {"Tank", "Raw", "Taken", "Stopped", "Mit%"}
    local hx = {10, 88, 136, 181, 245}
    local hw = {76, 46, 43, 62, 43}
    local i
    frame.headers = {}
    for i = 1, 5 do
        local fs = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        fs:SetPoint("TOPLEFT", frame, "TOPLEFT", hx[i], -48)
        fs:SetWidth(hw[i]); fs:SetJustifyH(i == 1 and "LEFT" or "RIGHT")
        fs:SetText(headers[i])
        frame.headers[i] = fs
    end

    frame.rows = {}
    for i = 1, RC4_MAX_ROWS do
        local row = CreateFrame("Button", nil, frame)
        row:SetWidth(282); row:SetHeight(22)
        row:SetPoint("TOPLEFT", frame, "TOPLEFT", 9, -61 - ((i - 1) * 23))
        row:EnableMouse(true)
        row.highlight = row:CreateTexture(nil, "BACKGROUND")
        row.highlight:SetAllPoints(row); row.highlight:SetTexture(0.35, 0.08, 0.08, 0.55); row.highlight:Hide()
        row.hover = row:CreateTexture(nil, "BACKGROUND")
        row.hover:SetAllPoints(row); row.hover:SetTexture(1, 1, 1, 0.08); row.hover:Hide()
        row.cols = {}
        local c
        for c = 1, 5 do
            local fs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            fs:SetPoint("TOPLEFT", frame, "TOPLEFT", hx[c], -65 - ((i - 1) * 23))
            fs:SetWidth(hw[c]); fs:SetJustifyH(c == 1 and "LEFT" or "RIGHT")
            row.cols[c] = fs
        end
        row:SetScript("OnEnter", function()
            this.hover:Show()
            if this.data then
                local s = this.data
                local tip = MT:GetAnalysisTooltip(); tip:SetOwner(this, "ANCHOR_CURSOR")
                tip:SetText(s.player or "Tank", 1, 0.82, 0)
                tip:AddDoubleLine("Fight", s.label or s.enemy or "Unknown", 0.8,0.8,0.8, 1,1,1)
                tip:AddDoubleLine("Duration", format("%.1fs", s.duration or 0), 0.8,0.8,0.8, 1,1,1)
                tip:AddDoubleLine("Armor", MT:FormatNumber(s.armor or 0), 0.8,0.8,0.8, 0.35,1,0.35)
                tip:AddDoubleLine("Avoidance", MT:FormatNumber(s.avoidance or 0), 0.8,0.8,0.8, 0.35,1,0.35)
                tip:AddDoubleLine("Block", MT:FormatNumber(s.block or 0), 0.8,0.8,0.8, 0.35,1,0.35)
                tip:AddDoubleLine("Resist", MT:FormatNumber(s.resist or 0), 0.8,0.8,0.8, 0.35,1,0.35)
                tip:AddDoubleLine("Absorb", MT:FormatNumber(s.absorb or 0), 0.8,0.8,0.8, 0.35,1,0.35)
                tip:Show()
            end
        end)
        row:SetScript("OnLeave", function() this.hover:Hide(); MT:HideAnalysisTooltip() end)
        row:SetScript("OnClick", function()
            if this.data then MT.compareSelectedPlayer = this.data.player; MT:UpdateTankCompareWindow() end
        end)
        frame.rows[i] = row
    end

    frame.prev = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.prev:SetWidth(22); frame.prev:SetHeight(16); frame.prev:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 10, 8); frame.prev:SetText("<")
    frame.prev:SetScript("OnClick", function() if (MT.comparePage or 1) > 1 then MT.comparePage = MT.comparePage - 1; MT:UpdateTankCompareWindow() end end)
    StyleLegacyButton(frame.prev)

    frame.pageText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.pageText:SetPoint("LEFT", frame.prev, "RIGHT", 5, 0); frame.pageText:SetWidth(42); frame.pageText:SetJustifyH("CENTER")

    frame.next = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.next:SetWidth(22); frame.next:SetHeight(16); frame.next:SetPoint("LEFT", frame.pageText, "RIGHT", 5, 0); frame.next:SetText(">")
    frame.next:SetScript("OnClick", function() MT.comparePage = (MT.comparePage or 1) + 1; MT:UpdateTankCompareWindow() end)
    StyleLegacyButton(frame.next)

    frame.sync = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.sync:SetWidth(67); frame.sync:SetHeight(17); frame.sync:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -9, 7); frame.sync:SetText("Sync Now")
    frame.sync:SetScript("OnClick", function() MT:SyncLatestTankFight(false); MT:UpdateTankCompareWindow() end)
    StyleLegacyButton(frame.sync)

    frame.detail = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.detail:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 9, 31)
    frame.detail:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -9, 31)
    frame.detail:SetHeight(38); frame.detail:SetJustifyH("LEFT"); frame.detail:SetJustifyV("BOTTOM")
    frame.detail:SetText("Finish a fight with other MainTank users to compare summaries.")

    self.compareFrame = frame
    self:RegisterManagedPage("COMPARE", frame)
    return frame
end

function MT:UpdateTankCompareWindow()
    local frame = self:CreateTankCompareWindow()
    local rows = RC4_GetCompareRows(self)
    local count = table.getn(rows)
    local pages = math.max(1, math.ceil(count / RC4_MAX_ROWS))
    self.comparePage = math.max(1, math.min(self.comparePage or 1, pages))
    local start = ((self.comparePage - 1) * RC4_MAX_ROWS) + 1
    frame.pageText:SetText(self.comparePage .. "/" .. pages)
    if self.comparePage <= 1 then frame.prev:Disable() else frame.prev:Enable() end
    if self.comparePage >= pages then frame.next:Disable() else frame.next:Enable() end

    local selected
    local i
    for i = 1, RC4_MAX_ROWS do
        local row = frame.rows[i]
        local s = rows[start + i - 1]
        row.data = s
        if s then
            local mitigation = (s.raw or 0) > 0 and ((s.stopped or 0) / s.raw * 100) or 0
            row.cols[1]:SetText(s.player or "Unknown")
            row.cols[2]:SetText(self:FormatNumber(s.raw or 0))
            row.cols[3]:SetText(self:FormatNumber(s.taken or 0))
            row.cols[4]:SetText(self:FormatNumber(s.stopped or 0))
            row.cols[5]:SetText(format("%.1f", mitigation))
            if self.compareSelectedPlayer == s.player then row.highlight:Show(); selected = s else row.highlight:Hide() end
            row:Show()
        else
            local c; for c = 1, 5 do row.cols[c]:SetText("") end
            row.highlight:Hide(); row:Hide()
        end
    end

    if not selected and count > 0 then
        selected = rows[start]
        if selected then self.compareSelectedPlayer = selected.player; frame.rows[1].highlight:Show() end
    end

    if selected then
        frame.detail:SetText(
            (selected.enemy or selected.label or "Fight") .. "  " .. format("%.1fs", selected.duration or 0) ..
            "\nArmor " .. self:FormatNumber(selected.armor or 0) ..
            "  Avoid " .. self:FormatNumber(selected.avoidance or 0) ..
            "  Block " .. self:FormatNumber(selected.block or 0) ..
            "  Resist " .. self:FormatNumber(selected.resist or 0) ..
            "  Absorb " .. self:FormatNumber(selected.absorb or 0))
    else
        frame.detail:SetText("No synced summaries yet. Group members need MainTank RC4+.")
    end
end

function MT:ToggleTankCompare()
    self:CreateTankCompareWindow()
    self:ShowManagedPage("COMPARE", function(owner) owner:UpdateTankCompareWindow() end)
end

local RC4_OldRefreshManagedPageRegistry = MT.RefreshManagedPageRegistry
function MT:RefreshManagedPageRegistry()
    RC4_OldRefreshManagedPageRegistry(self)
    local compare = self.compareFrame or getglobal("MainTankTankCompareFrame")
    if compare then self:RegisterManagedPage("COMPARE", compare) end
end

-- Main-page Compare button. Fit Export/Boss/Compare on the existing center row.
local RC4_OldCreateUI = MT.CreateUI
function MT:CreateUI()
    RC4_OldCreateUI(self)
    local frame = self.frame
    if not frame or frame.compareButton then return end

    if frame.exportButton then
        frame.exportButton:ClearAllPoints(); frame.exportButton:SetWidth(56); frame.exportButton:SetPoint("TOP", frame, "TOP", -60, -49)
    end
    if frame.bossButton then
        frame.bossButton:ClearAllPoints(); frame.bossButton:SetWidth(56); frame.bossButton:SetPoint("TOP", frame, "TOP", 0, -49)
    end
    local button = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    button:SetWidth(56); button:SetHeight(18); button:SetPoint("TOP", frame, "TOP", 60, -49)
    button:SetText("Compare")
    button:SetScript("OnClick", function() MT:ToggleTankCompare() end)
    button:SetScript("OnEnter", function()
        local tip = MT:GetAnalysisTooltip(); tip:SetOwner(this, "ANCHOR_CURSOR")
        tip:SetText("Tank Comparison", 1, 0.82, 0)
        tip:AddLine("Compare synced tank mitigation summaries", 0.85,0.85,0.85)
        tip:AddLine("from group members running MainTank.", 0.85,0.85,0.85)
        tip:AddLine("Different tank assignments can make raw totals unequal.", 1,0.82,0)
        tip:Show()
    end)
    button:SetScript("OnLeave", function() MT:HideAnalysisTooltip() end)
    StyleLegacyButton(button)
    frame.compareButton = button
    self:RegisterFullControl(button)
end

local RC4_OldHandleSlash = MT.HandleSlash
function MT:HandleSlash(msg)
    local raw = lower(msg or "")
    if raw == "compare" or raw == "tanks" then self:ToggleTankCompare(); return end
    if raw == "sync" or raw == "sync tank" then self:SyncLatestTankFight(false); return end
    RC4_OldHandleSlash(self, msg)
end


-- ============================================================================
-- v1.0.0 RC4b - Main navigation layout polish + comparison test polish
-- Compare gets its own centered row; Export/Boss stay balanced beneath it.
-- This prevents Compare from colliding with Details and matches the compact
-- Main-page hierarchy used by Timeline/Pie Chart and Biggest/Details.
-- ============================================================================
local RC4B_OldCreateUI = MT.CreateUI
function MT:CreateUI()
    RC4B_OldCreateUI(self)
    local frame = self.frame
    if not frame then return end

    -- Compare centered on the upper navigation row.
    if frame.compareButton then
        frame.compareButton:ClearAllPoints()
        frame.compareButton:SetWidth(68)
        frame.compareButton:SetHeight(18)
        frame.compareButton:SetPoint("TOP", frame, "TOP", 0, -28)
        StyleLegacyButton(frame.compareButton)
    end

    -- Export and Boss form a balanced centered pair on the row below.
    if frame.exportButton then
        frame.exportButton:ClearAllPoints()
        frame.exportButton:SetWidth(68)
        frame.exportButton:SetHeight(18)
        frame.exportButton:SetPoint("TOP", frame, "TOP", -36, -49)
        StyleLegacyButton(frame.exportButton)
    end
    if frame.bossButton then
        frame.bossButton:ClearAllPoints()
        frame.bossButton:SetWidth(68)
        frame.bossButton:SetHeight(18)
        frame.bossButton:SetPoint("TOP", frame, "TOP", 36, -49)
        StyleLegacyButton(frame.bossButton)
    end

    -- Re-assert the outside navigation columns so future wrappers cannot
    -- accidentally let the centered controls overlap them.
    local timelineButton = self.fullControls and self.fullControls[1]
    local biggestButton  = self.fullControls and self.fullControls[2]
    local detailsButton  = self.fullControls and self.fullControls[3]
    local pieButton      = self.fullControls and self.fullControls[4]
    if timelineButton then
        timelineButton:ClearAllPoints(); timelineButton:SetWidth(68); timelineButton:SetHeight(18)
        timelineButton:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -28)
    end
    if biggestButton then
        biggestButton:ClearAllPoints(); biggestButton:SetWidth(68); biggestButton:SetHeight(18)
        biggestButton:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -49)
    end
    if pieButton then
        pieButton:ClearAllPoints(); pieButton:SetWidth(68); pieButton:SetHeight(18)
        pieButton:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -8, -28)
        pieButton:SetText("Pie Chart")
    end
    if detailsButton then
        detailsButton:ClearAllPoints(); detailsButton:SetWidth(68); detailsButton:SetHeight(18)
        detailsButton:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -8, -49)
    end
end

-- Add received-age context while testing tank sync. This does not affect the
-- comparison math; it only makes it obvious whether a row is fresh or stale.
local RC4B_OldUpdateTankCompareWindow = MT.UpdateTankCompareWindow
function MT:UpdateTankCompareWindow()
    RC4B_OldUpdateTankCompareWindow(self)
    local frame = self.compareFrame
    if not frame or not frame.rows then return end
    local i
    for i = 1, table.getn(frame.rows) do
        local row = frame.rows[i]
        if row and row.data then
            local s = row.data
            local age = 0
            if s.receivedAt and GetTime then age = math.max(0, GetTime() - s.receivedAt) end
            row.syncAge = age
        end
    end
end


-- ============================================================================


-- Private exports consumed by Core/Mitigation.lua.
E.RC2_GetViewDuration = RC2_GetViewDuration
E.RC4_SanitizeField = RC4_SanitizeField
E.RC4_Split = RC4_Split
