-- MainTank BOSSPROFILE3 - compact Boss Profile presentation
--
-- Loaded after BossProfilePersistence so this file is presentation-only. The
-- existing Boss frame, managed-page identity, profile store, and combat capture
-- remain authoritative; this layer only replaces the crowded legacy text rows
-- with fixed columns and RC6-complete encounter metadata.

if not MainTank then return end
local MT = MainTank
local E = MT._engine
local StyleLegacyButton = E and E.StyleLegacyButton

local function BPUI_NewText(frame, template, x, y, width, justify)
    local fs = frame:CreateFontString(nil, "ARTWORK", template or "GameFontHighlightSmall")
    fs:SetPoint("TOPLEFT", frame, "TOPLEFT", x, y)
    if width then fs:SetWidth(width) end
    if justify then fs:SetJustifyH(justify) end
    return fs
end

local function BPUI_FormatSavedAt(profile)
    local stamp = tonumber(profile and profile.savedAt)
    if stamp and stamp > 0 and type(date) == "function" then
        return date("%m/%d %H:%M", stamp)
    end
    return "time N/A"
end

local function BPUI_HideLegacy(frame)
    if frame.summary then frame.summary:Hide() end
    if frame.schoolHeader then frame.schoolHeader:Hide() end
    if frame.abilityHeader then frame.abilityHeader:Hide() end
    if frame.footer then frame.footer:Hide() end
    local i
    for i = 1, 3 do
        if frame.schoolRows and frame.schoolRows[i] then frame.schoolRows[i]:Hide() end
        if frame.abilityRows and frame.abilityRows[i] then frame.abilityRows[i]:Hide() end
    end
end

local function BPUI_ClearRows(frame)
    local i
    for i = 1, 3 do
        frame.bpSchoolName[i]:SetText("")
        frame.bpSchoolRaw[i]:SetText("")
        frame.bpSchoolTaken[i]:SetText("")
        frame.bpAbilityName[i]:SetText("")
        frame.bpAbilityRaw[i]:SetText("")
        frame.bpAbilityTaken[i]:SetText("")
    end
end

local BPUI_PAGE_SIZE = 3

local function BPUI_PageCount(rows)
    local count = type(rows) == "table" and table.getn(rows) or 0
    if count <= 0 then return 1 end
    return math.floor((count - 1) / BPUI_PAGE_SIZE) + 1
end

local function BPUI_ClampPage(page, pages)
    page = tonumber(page) or 1
    if page < 1 then page = 1 end
    if page > pages then page = pages end
    return page
end

local function BPUI_UpdateSectionPager(prev, pageText, nextButton, page, pages)
    if pages <= 1 then
        prev:Hide(); pageText:Hide(); nextButton:Hide()
        return
    end
    prev:Show(); pageText:Show(); nextButton:Show()
    pageText:SetText(tostring(page) .. "/" .. tostring(pages))
    if page <= 1 then prev:Disable() else prev:Enable() end
    if page >= pages then nextButton:Disable() else nextButton:Enable() end
end

local BPUI_OldCreateBossWindow = MT.CreateBossWindow
function MT:CreateBossWindow()
    local frame = BPUI_OldCreateBossWindow(self)
    if frame.bpProfilePolished then return frame end
    frame.bpProfilePolished = true

    BPUI_HideLegacy(frame)

    -- Encounter pager + saved timestamp. Keep the established 300x231 window.
    if frame.profilePrev then
        frame.profilePrev:ClearAllPoints()
        frame.profilePrev:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -27)
    end
    if frame.profileCount then
        frame.profileCount:ClearAllPoints()
        frame.profileCount:SetPoint("LEFT", frame.profilePrev, "RIGHT", 4, 0)
        frame.profileCount:SetWidth(220)
    end
    if frame.profileNext then
        frame.profileNext:ClearAllPoints()
        frame.profileNext:SetPoint("LEFT", frame.profileCount, "RIGHT", 4, 0)
    end

    frame.bpMeta = BPUI_NewText(frame, "GameFontHighlightSmall", 10, -47, 280, "CENTER")
    frame.bpHeadlineLeft = BPUI_NewText(frame, "GameFontHighlightSmall", 12, -60, 132, "LEFT")
    frame.bpHeadlineRight = BPUI_NewText(frame, "GameFontHighlightSmall", 156, -60, 132, "RIGHT")
    frame.bpStoppedLeft = BPUI_NewText(frame, "GameFontHighlightSmall", 12, -73, 132, "LEFT")
    frame.bpStoppedRight = BPUI_NewText(frame, "GameFontHighlightSmall", 156, -73, 132, "RIGHT")
    frame.bpShareLeft = BPUI_NewText(frame, "GameFontHighlightSmall", 12, -86, 150, "LEFT")
    frame.bpShareRight = BPUI_NewText(frame, "GameFontHighlightSmall", 164, -86, 124, "RIGHT")

    -- Fixed columns. Proportional glyph widths can no longer push RAW/TAKEN.
    frame.bpSchoolHeader = BPUI_NewText(frame, "GameFontNormalSmall", 10, -101, 145, "LEFT")
    frame.bpSchoolHeader:SetText("Damage Schools")
    frame.bpSchoolRawHeader = BPUI_NewText(frame, "GameFontNormalSmall", 158, -101, 60, "RIGHT")
    frame.bpSchoolRawHeader:SetText("RAW")
    frame.bpSchoolTakenHeader = BPUI_NewText(frame, "GameFontNormalSmall", 222, -101, 66, "RIGHT")
    frame.bpSchoolTakenHeader:SetText("TAKEN")

    -- Independent paging for bosses that use more than three damage schools.
    -- The pager uses slightly narrower arrow buttons and a wider page readout
    -- so values like 1/3 and 1/4 stay on one line without crowding RAW/TAKEN.
    -- Controls still live inside the name-column header and the 300px window
    -- never grows.
    frame.bpSchoolPrev = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.bpSchoolPrev:SetWidth(13); frame.bpSchoolPrev:SetHeight(14)
    frame.bpSchoolPrev:SetPoint("TOPLEFT", frame, "TOPLEFT", 111, -97)
    frame.bpSchoolPrev:SetText("<")
    frame.bpSchoolPageText = BPUI_NewText(frame, "GameFontHighlightSmall", 125, -101, 19, "CENTER")
    frame.bpSchoolNext = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.bpSchoolNext:SetWidth(13); frame.bpSchoolNext:SetHeight(14)
    frame.bpSchoolNext:SetPoint("TOPLEFT", frame, "TOPLEFT", 145, -97)
    frame.bpSchoolNext:SetText(">")
    if StyleLegacyButton then StyleLegacyButton(frame.bpSchoolPrev); StyleLegacyButton(frame.bpSchoolNext) end
    frame.bpSchoolPage = 1
    frame.bpSchoolPrev:SetScript("OnClick", function()
        if (frame.bpSchoolPage or 1) > 1 then
            frame.bpSchoolPage = frame.bpSchoolPage - 1
            MT:UpdateBossWindow()
        end
    end)
    frame.bpSchoolNext:SetScript("OnClick", function()
        frame.bpSchoolPage = (frame.bpSchoolPage or 1) + 1
        MT:UpdateBossWindow()
    end)

    frame.bpSchoolName, frame.bpSchoolRaw, frame.bpSchoolTaken = {}, {}, {}
    local i, y
    for i = 1, 3 do
        y = -101 - (i * 13)
        frame.bpSchoolName[i] = BPUI_NewText(frame, "GameFontHighlightSmall", 12, y, 143, "LEFT")
        frame.bpSchoolRaw[i] = BPUI_NewText(frame, "GameFontHighlightSmall", 158, y, 60, "RIGHT")
        frame.bpSchoolTaken[i] = BPUI_NewText(frame, "GameFontHighlightSmall", 222, y, 66, "RIGHT")
        frame.bpSchoolName[i]:SetHeight(12); frame.bpSchoolRaw[i]:SetHeight(12); frame.bpSchoolTaken[i]:SetHeight(12)
    end

    frame.bpAbilityHeader = BPUI_NewText(frame, "GameFontNormalSmall", 10, -153, 145, "LEFT")
    frame.bpAbilityHeader:SetText("Top Boss Abilities")
    frame.bpAbilityRawHeader = BPUI_NewText(frame, "GameFontNormalSmall", 158, -153, 60, "RIGHT")
    frame.bpAbilityRawHeader:SetText("RAW")
    frame.bpAbilityTakenHeader = BPUI_NewText(frame, "GameFontNormalSmall", 222, -153, 66, "RIGHT")
    frame.bpAbilityTakenHeader:SetText("TAKEN")

    -- Abilities page independently from schools. A boss can therefore expose
    -- every learned ability without forcing the compact profile window taller.
    -- Match the widened readout used by the schools pager for cleaner 1/4+ UI.
    frame.bpAbilityPrev = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.bpAbilityPrev:SetWidth(13); frame.bpAbilityPrev:SetHeight(14)
    frame.bpAbilityPrev:SetPoint("TOPLEFT", frame, "TOPLEFT", 111, -149)
    frame.bpAbilityPrev:SetText("<")
    frame.bpAbilityPageText = BPUI_NewText(frame, "GameFontHighlightSmall", 125, -153, 19, "CENTER")
    frame.bpAbilityNext = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.bpAbilityNext:SetWidth(13); frame.bpAbilityNext:SetHeight(14)
    frame.bpAbilityNext:SetPoint("TOPLEFT", frame, "TOPLEFT", 145, -149)
    frame.bpAbilityNext:SetText(">")
    if StyleLegacyButton then StyleLegacyButton(frame.bpAbilityPrev); StyleLegacyButton(frame.bpAbilityNext) end
    frame.bpAbilityPage = 1
    frame.bpAbilityPrev:SetScript("OnClick", function()
        if (frame.bpAbilityPage or 1) > 1 then
            frame.bpAbilityPage = frame.bpAbilityPage - 1
            MT:UpdateBossWindow()
        end
    end)
    frame.bpAbilityNext:SetScript("OnClick", function()
        frame.bpAbilityPage = (frame.bpAbilityPage or 1) + 1
        MT:UpdateBossWindow()
    end)

    frame.bpAbilityName, frame.bpAbilityRaw, frame.bpAbilityTaken = {}, {}, {}
    for i = 1, 3 do
        y = -153 - (i * 13)
        frame.bpAbilityName[i] = BPUI_NewText(frame, "GameFontHighlightSmall", 12, y, 143, "LEFT")
        frame.bpAbilityRaw[i] = BPUI_NewText(frame, "GameFontHighlightSmall", 158, y, 60, "RIGHT")
        frame.bpAbilityTaken[i] = BPUI_NewText(frame, "GameFontHighlightSmall", 222, y, 66, "RIGHT")
        frame.bpAbilityName[i]:SetHeight(12); frame.bpAbilityRaw[i]:SetHeight(12); frame.bpAbilityTaken[i]:SetHeight(12)
    end

    -- Two compact lines account for every RC6 stopped-damage bucket.
    frame.bpMit1 = BPUI_NewText(frame, "GameFontHighlightSmall", 10, -205, 280, "LEFT")
    frame.bpMit2 = BPUI_NewText(frame, "GameFontHighlightSmall", 10, -218, 280, "LEFT")

    frame.bpEmpty = BPUI_NewText(frame, "GameFontHighlightSmall", 20, -75, 260, "CENTER")
    frame.bpEmpty:SetText("")

    return frame
end

local function BPUI_SetRow(owner, nameFS, rawFS, takenFS, row, withSchool)
    if not row then
        nameFS:SetText(""); rawFS:SetText(""); takenFS:SetText("")
        return
    end
    local label = tostring(row.name or "Unknown")
    if withSchool then label = label .. " [" .. tostring(row.school or "Unknown") .. "]" end
    nameFS:SetText(label)
    rawFS:SetText(owner:FormatNumber(tonumber(row.raw) or 0))
    takenFS:SetText(owner:FormatNumber(tonumber(row.taken) or 0))
end

function MT:UpdateBossWindow()
    local frame = self:CreateBossWindow()
    local profile = self:BuildBossBreakdown()
    local count = table.getn(self.bossHistory or {})
    local index = count > 0 and (self.bossProfileIndex or 1) or 0

    -- Section paging is encounter-local UI state only. Switching Boss Profiles
    -- always returns both lists to page 1; paging is never persisted.
    if frame.bpProfileToken ~= profile then
        frame.bpProfileToken = profile
        frame.bpSchoolPage = 1
        frame.bpAbilityPage = 1
    end

    if index <= 1 then frame.profilePrev:Disable() else frame.profilePrev:Enable() end
    if index >= count then frame.profileNext:Disable() else frame.profileNext:Enable() end

    if profile.empty then
        frame.title:SetText("Boss Profiles")
        frame.profileCount:SetText("Encounter 0 / 0")
        frame.bpMeta:SetText("")
        frame.bpHeadlineLeft:SetText(""); frame.bpHeadlineRight:SetText("")
        frame.bpStoppedLeft:SetText(""); frame.bpStoppedRight:SetText("")
        frame.bpShareLeft:SetText(""); frame.bpShareRight:SetText("")
        frame.bpMit1:SetText(""); frame.bpMit2:SetText("")
        BPUI_ClearRows(frame)
        frame.bpSchoolPrev:Hide(); frame.bpSchoolPageText:Hide(); frame.bpSchoolNext:Hide()
        frame.bpAbilityPrev:Hide(); frame.bpAbilityPageText:Hide(); frame.bpAbilityNext:Hide()
        frame.bpEmpty:SetText("No skull-level boss encounters recorded.\nTarget a ?? boss during combat to create a profile.")
        return
    end

    frame.bpEmpty:SetText("")
    frame.title:SetText("Boss Profile - " .. tostring(profile.name or "Unknown"))
    frame.profileCount:SetText("Encounter " .. tostring(index) .. " / " .. tostring(count) .. "   Saved " .. BPUI_FormatSavedAt(profile))

    frame.bpMeta:SetText(
        format("%.1fs", tonumber(profile.duration) or 0) ..
        "   |   " .. tostring(profile.events or 0) .. " events" ..
        "   |   Crit " .. tostring(profile.criticals or 0) ..
        "   Crush " .. tostring(profile.crushings or 0)
    )
    frame.bpHeadlineLeft:SetText("RAW " .. self:FormatNumber(profile.raw or 0))
    frame.bpHeadlineRight:SetText("TAKEN " .. self:FormatNumber(profile.taken or 0))
    frame.bpStoppedLeft:SetText("STOPPED " .. self:FormatNumber(profile.stopped or 0))
    frame.bpStoppedRight:SetText("MITIGATION " .. format("%.1f%%", profile.mitigation or 0))
    frame.bpShareLeft:SetText("Boss RAW Share " .. format("%.1f%%", profile.share or 0))
    frame.bpShareRight:SetText("Adds RAW " .. self:FormatNumber(profile.addsRaw or 0))

    local schoolPages = BPUI_PageCount(profile.schools)
    local abilityPages = BPUI_PageCount(profile.abilities)
    frame.bpSchoolPage = BPUI_ClampPage(frame.bpSchoolPage, schoolPages)
    frame.bpAbilityPage = BPUI_ClampPage(frame.bpAbilityPage, abilityPages)
    BPUI_UpdateSectionPager(frame.bpSchoolPrev, frame.bpSchoolPageText, frame.bpSchoolNext, frame.bpSchoolPage, schoolPages)
    BPUI_UpdateSectionPager(frame.bpAbilityPrev, frame.bpAbilityPageText, frame.bpAbilityNext, frame.bpAbilityPage, abilityPages)

    local schoolStart = ((frame.bpSchoolPage - 1) * BPUI_PAGE_SIZE) + 1
    local abilityStart = ((frame.bpAbilityPage - 1) * BPUI_PAGE_SIZE) + 1
    local i
    for i = 1, BPUI_PAGE_SIZE do
        BPUI_SetRow(self, frame.bpSchoolName[i], frame.bpSchoolRaw[i], frame.bpSchoolTaken[i], profile.schools and profile.schools[schoolStart + i - 1], false)
        BPUI_SetRow(self, frame.bpAbilityName[i], frame.bpAbilityRaw[i], frame.bpAbilityTaken[i], profile.abilities and profile.abilities[abilityStart + i - 1], true)
    end

    frame.bpMit1:SetText(
        "Armor " .. self:FormatNumber(profile.armor or 0) ..
        "   Avoid " .. self:FormatNumber(profile.avoidance or 0) ..
        "   Block " .. self:FormatNumber(profile.block or 0) ..
        "   Resist " .. self:FormatNumber(profile.resist or 0)
    )
    frame.bpMit2:SetText(
        "Absorb " .. self:FormatNumber(profile.absorb or 0) ..
        "   Flat DR " .. self:FormatNumber(profile.flatDR or 0) ..
        "   Phys DR " .. self:FormatNumber(profile.physicalDR or 0) ..
        "   Magic DR " .. self:FormatNumber(profile.magicDR or 0)
    )
end
