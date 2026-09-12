-- MainTank v1.0.0 FR1S
-- UI/Pie.lua
-- Pie-page presentation and category policy kept outside the combat/math core.
--
-- Release pie compatibility layer.
-- PIEBREAKDOWNPP1 / PixelPerfect1: RAW/PHYSICAL/MAGIC use one exact legend geometry.
-- 14px row height, 14px spacing, and one fixed -54px start removes the old
-- compact/non-compact mode shift when cycling between Pie views.
-- RC6 already owns the authoritative category math, including Full Block vs
-- Partial Block and Physical vs Magic absorbed damage. This late-loaded module
-- must only guarantee enough legend rows for those categories; it must never
-- filter or reinterpret RC6 pie data.

if not MainTank then return end
local MT = MainTank

local FR1N_PreviousCreatePieWindow = MT.CreatePieWindow
local FR1N_PreviousUpdatePieWindow = MT.UpdatePieWindow

local function FR1N_SetupLegendRow(row, frame, index)
    if not row or not frame then return end

    row:SetWidth(155)
    row:SetHeight(14)
    row:EnableMouse(true)
    row:ClearAllPoints()

    row:SetPoint("TOPLEFT", frame, "TOPLEFT", 134, -54 - ((index - 1) * 14))

    row:SetScript("OnEnter", function() MT:ShowPieTooltip(this) end)
    row:SetScript("OnLeave", function() MT:HideAnalysisTooltip() end)
    row:SetScript("OnMouseUp", function()
        if this.entry then MT:OpenPieDetails(this.entry) end
    end)
end

local function FR1N_CreateLegendRow(frame, index)
    local row = CreateFrame("Frame", nil, frame)
    FR1N_SetupLegendRow(row, frame, index)

    row.swatch = row:CreateTexture(nil, "ARTWORK")
    row.swatch:SetWidth(10)
    row.swatch:SetHeight(10)
    row.swatch:SetPoint("LEFT", row, "LEFT", 0, 0)

    row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.label:SetPoint("LEFT", row.swatch, "RIGHT", 4, 0)
    row.label:SetWidth(60)
    row.label:SetJustifyH("LEFT")

    row.value = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.value:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    row.value:SetWidth(80)
    row.value:SetJustifyH("RIGHT")

    return row
end

local function PIEBREAKDOWNPP1_PositionPieBody(frame)
    if not frame then return end
    -- PIEBREAKDOWNPP1: preserve the proven pie-disc position. Legend geometry
    -- is now identical in RAW, PHYSICAL, and MAGIC.
    if frame.ring then
        frame.ring:ClearAllPoints()
        frame.ring:SetPoint("TOPLEFT", frame, "TOPLEFT", 13, -50)
    end
end

local function FR1N_LayoutPieLegend(frame, entryCount)
    if not frame then return end
    PIEBREAKDOWNPP1_PositionPieBody(frame)
    local i
    for i = 1, table.getn(frame.legendRows or {}) do
        FR1N_SetupLegendRow(frame.legendRows[i], frame, i)
    end
    if frame.totalText then
        frame.totalText:ClearAllPoints()
        frame.totalText:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 15, 44)
    end
end

local function FR1N_ExpandPieLegend(frame)
    if not frame then return end
    PIEBREAKDOWNPP1_PositionPieBody(frame)
    frame.legendRows = frame.legendRows or {}

    local i = 1
    while i <= table.getn(frame.legendRows) do
        FR1N_SetupLegendRow(frame.legendRows[i], frame, i)
        i = i + 1
    end

    -- Eleven rows covers every legitimate RC6 specialized view.
    -- Physical max = Armor + Flat DR + Physical DR + Dodge + Parry + Miss +
    -- Full Block + Partial Block + Absorbs (9).
    -- Magic max = Flat DR + Magic DR + Block + seven resistance schools +
    -- Absorbs (11).
    i = table.getn(frame.legendRows) + 1
    while i <= 11 do
        frame.legendRows[i] = FR1N_CreateLegendRow(frame, i)
        i = i + 1
    end

    if frame.totalText then
        frame.totalText:ClearAllPoints()
        frame.totalText:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 15, 44)
    end

    frame.fr1nLegendExpanded = true
end

-- PIEBREAKDOWN2: keep RC6 as the authority, but repair two presentation gaps
-- that only show up after compact historical/Overall restore:
--   1) the aggregate can retain fullBlockedEstimated while the optional
--      physicalFullBlockedEstimated split is absent/zero; the detailed events
--      still retain kind=FullBlock, school and block, so recover the PHYSICAL
--      Full Block slice from those already-saved events without changing totals.
--   2) Physical/Magic Absorb legend values are already school-split by RC6, but
--      their Details click-through used the generic ABSORB filter. Tag each slice
--      with a school-specific filter so Physical never opens magical absorbs and
--      Magic never opens physical absorbs.
local PIEBREAKDOWN2_PreviousGetPieData = MT.GetPieData
local PIEBREAKDOWN2_PreviousEventMatchesDetailsFilter = MT.EventMatchesDetailsFilter

local function PIEBREAKDOWN2_PhysicalFullBlockFromEvents(owner)
    local events = owner:GetDisplayEvents() or {}
    local total = 0
    local i, e
    for i = 1, table.getn(events) do
        e = events[i]
        if type(e) == "table" and e.kind == "FullBlock" and
           (e.school or "Physical") == "Physical" then
            total = total + (tonumber(e.block) or 0)
        end
    end
    return total
end

-- PIEBREAKDOWN3 reload safety: physicalAbsorb/magicAbsorb are convenience
-- aggregate splits and older compact Current/Overall snapshots do not always
-- persist them. The authoritative finalized events still persist both absorb
-- amount and school, so recover only the Pie presentation split from events.
-- This never changes raw/taken/mitigation totals or combat parsing.
local function PIEBREAKDOWN3_AbsorbFromEvents(owner, wantPhysical)
    local events = owner:GetDisplayEvents() or {}
    local total = 0
    local i, e, school
    for i = 1, table.getn(events) do
        e = events[i]
        if type(e) == "table" then
            school = e.school or "Physical"
            if (wantPhysical and school == "Physical") or
               ((not wantPhysical) and school ~= "Physical") then
                total = total + (tonumber(e.absorb) or 0)
            end
        end
    end
    return total
end

local function PIEBREAKDOWN3_EnsureAbsorbEntry(entries, total, filterKind)
    local i, entry
    for i = 1, table.getn(entries) do
        entry = entries[i]
        if entry and entry.label == "Absorbs" then
            if total > 0 then entry.value = total end
            entry.filterKind = filterKind
            entry.filterValue = "Absorbs"
            return
        end
    end
    if total > 0 then
        table.insert(entries, {
            label = "Absorbs",
            value = total,
            color = {1.00, 0.35, 0.75},
            filterKind = filterKind,
            filterValue = "Absorbs"
        })
    end
end

function MT:GetPieData(mode)
    local entries = PIEBREAKDOWN2_PreviousGetPieData(self, mode) or {}
    local i, entry, hasFullBlock, insertAt

    if mode == "PHYSICAL" then
        hasFullBlock = false
        insertAt = table.getn(entries) + 1
        for i = 1, table.getn(entries) do
            entry = entries[i]
            if entry and entry.label == "Full Block" then hasFullBlock = true end
            if entry and (entry.label == "Partial Block" or entry.label == "Absorbs") and
               insertAt == table.getn(entries) + 1 then
                insertAt = i
            end
            if entry and entry.label == "Absorbs" then
                entry.filterKind = "PHYSICAL_ABSORB"
                entry.filterValue = "Absorbs"
            end
        end

        if not hasFullBlock then
            local fullBlock = PIEBREAKDOWN2_PhysicalFullBlockFromEvents(self)
            if fullBlock > 0 then
                table.insert(entries, insertAt, {
                    label = "Full Block",
                    value = fullBlock,
                    color = {1.00, 0.65, 0.15},
                    filterKind = "PHYSICAL_FULL_BLOCK",
                    filterValue = "FullBlock"
                })
            end
        end
        PIEBREAKDOWN3_EnsureAbsorbEntry(entries, PIEBREAKDOWN3_AbsorbFromEvents(self, true), "PHYSICAL_ABSORB")
    elseif mode == "MAGIC" then
        PIEBREAKDOWN3_EnsureAbsorbEntry(entries, PIEBREAKDOWN3_AbsorbFromEvents(self, false), "MAGIC_ABSORB")
    end

    return entries
end

function MT:EventMatchesDetailsFilter(event)
    local filter = self.detailsFilter
    if filter and filter.kind == "PHYSICAL_ABSORB" then
        return (tonumber(event and event.absorb) or 0) > 0 and
               ((event and event.school) or "Physical") == "Physical"
    end
    if filter and filter.kind == "MAGIC_ABSORB" then
        return (tonumber(event and event.absorb) or 0) > 0 and
               ((event and event.school) or "Physical") ~= "Physical"
    end
    return PIEBREAKDOWN2_PreviousEventMatchesDetailsFilter(self, event)
end

function MT:CreatePieWindow()
    local frame = FR1N_PreviousCreatePieWindow(self)
    FR1N_ExpandPieLegend(frame)
    return frame
end

-- Critical FR1N fix: the Pie frame is commonly created by the main UI before
-- UI/Pie.lua loads. Ensure the already-existing frame is expanded on module
-- load and again before every redraw, making the fix independent of creation
-- order and /reload state.
function MT:UpdatePieWindow()
    local frame = self.pieFrame or getglobal("MainTankPieFrame")
    if frame then
        FR1N_ExpandPieLegend(frame)
        local previewEntries = self:GetPieData(self.pieMode) or {}
        FR1N_LayoutPieLegend(frame, table.getn(previewEntries))
    end
    FR1N_PreviousUpdatePieWindow(self)
end

-- Patch an already-created frame immediately instead of waiting for a click,
-- mode change, or a new CreatePieWindow() call.
if MT.pieFrame then
    FR1N_ExpandPieLegend(MT.pieFrame)
end

-- Version ownership is centralized in Core/Release.lua.
