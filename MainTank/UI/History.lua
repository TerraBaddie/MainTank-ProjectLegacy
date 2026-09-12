-- MainTank v1.2.24 HIST64UI11
-- Read-only History browser for the final three-layer model:
--   8 MainTank detailed -> 8 Archive detailed -> 64 History summaries.
--
-- History is summary-only. It never reconstructs Events, Timeline, Details,
-- Pie data, or Restore behavior. This file is UI-only.

if not MainTank then return end
local MT = MainTank

local HISTORY_PAGE_SIZE = 7
local LIST_HEIGHT = 231
local DETAIL_HEIGHT = 231

local function HN(n)
    if MT.FormatNumber then return MT:FormatNumber(tonumber(n) or 0) end
    return tostring(math.floor((tonumber(n) or 0) + 0.5))
end

local function HTag(s)
    if not s then return "MINOR" end
    if s.combatType == "PVP" then return "PvP" end
    if s.isBoss then return "BOSS" end
    if (tonumber(s.raw) or 0) >= 50000 then return "MAJOR" end
    return "MINOR"
end

local function HStopped(s)
    local stopped = tonumber(s and s.stopped)
    if stopped ~= nil then return math.max(0, stopped) end
    return math.max(0, (tonumber(s and s.raw) or 0) - (tonumber(s and s.taken) or 0))
end

local function HPct(s)
    local raw = tonumber(s and s.raw) or 0
    if raw <= 0 then return 0 end
    return (HStopped(s) / raw) * 100
end

-- HIST64UI7: History keeps useful event counters beside the aggregate they
-- describe without reviving detailed events. Older sparse History entries
-- simply omit the parenthetical count instead of inventing a zero.
local function HCountValue(value, count)
    local text = HN(value)
    if count ~= nil then
        return text .. " (" .. HN(count) .. ")"
    end
    return text
end

local function HProfile(owner)
    if owner.GetExternalHistoryProfile then
        return owner:GetExternalHistoryProfile(true)
    end
    return nil
end

local function HSummaries(owner)
    local hp = HProfile(owner)
    if hp and type(hp.summaries) == "table" then return hp.summaries end
    return {}
end

local function HStyle(button)
    if button and MT.ApplyLegacyButtonStyle then MT:ApplyLegacyButtonStyle(button) end
end

local function HApplyWindowStyle(frame)
    if not frame then return end
    if MT.ApplyLegacyWindowStyle then MT:ApplyLegacyWindowStyle(frame) end
    if MT.BlackenButtonsDeep then MT.BlackenButtonsDeep(frame, 0, {}) end
    if frame.closeButton and frame.closeButton.mtCloseText then
        frame.closeButton.mtCloseText:SetTextColor(1.0, 0.10, 0.10)
    end
end

local function HCloseAll()
    MT.backNavHistory = {}
    MT.currentManagedPage = "MAIN"
    MT.activeRCPage = nil
    if MT.HideAllManagedPages then MT:HideAllManagedPages() end
    if MT.frame then MT.frame:Hide() end
    if MT.historyFrame then MT.historyFrame:Hide() end
    MT:HideAnalysisTooltip()
end

local function HCreateText(frame, x, y, width, justify, fontObject)
    local fs = frame:CreateFontString(nil, "OVERLAY", fontObject or "GameFontHighlightSmall")
    fs:SetPoint("TOPLEFT", frame, "TOPLEFT", x, y)
    fs:SetWidth(width)
    fs:SetJustifyH(justify or "LEFT")
    return fs
end

local function HPositionHeader(frame, detailMode)
    if not frame or not frame.title then return end
    frame.title:ClearAllPoints()
    if detailMode then
        -- BACK4 rule: establish Back visibility first, then anchor the title.
        frame.title:SetPoint("TOPLEFT", frame.backList, "TOPRIGHT", 10, -3)
        frame.title:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -25, -9)
        frame.title:SetJustifyH("LEFT")
    else
        frame.title:SetPoint("TOPLEFT", frame, "TOPLEFT", 68, -9)
        frame.title:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -25, -9)
        frame.title:SetJustifyH("CENTER")
    end
end

function MT:CreateHistoryWindow()
    if self.historyFrame then return self.historyFrame end

    local frame = CreateFrame("Frame", "MainTankHistoryFrame", UIParent)
    frame:SetWidth(300)
    frame:SetHeight(LIST_HEIGHT)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:SetBackdrop({
        bgFile="Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",
        tile=true, tileSize=16, edgeSize=16,
        insets={left=4,right=4,top=4,bottom=4}
    })
    frame:SetBackdropColor(0.05,0.05,0.08,0.92)

    frame.title = frame:CreateFontString(nil,"OVERLAY","GameFontNormal")
    frame.title:SetText("History")

    frame.closeButton = CreateFrame("Button",nil,frame,"UIPanelCloseButton")
    frame.closeButton:SetPoint("TOPRIGHT",frame,"TOPRIGHT",-3,-3)
    frame.closeButton:SetScript("OnClick",HCloseAll)

    frame.mainButton = CreateFrame("Button",nil,frame,"UIPanelButtonTemplate")
    frame.mainButton:SetWidth(52)
    frame.mainButton:SetHeight(16)
    frame.mainButton:SetPoint("TOPLEFT",frame,"TOPLEFT",8,-7)
    frame.mainButton:SetText("MT Main")
    frame.mainButton:SetScript("OnClick",function() MT:ShowManagedPage("MAIN") end)
    HStyle(frame.mainButton)

    frame.backList = CreateFrame("Button",nil,frame,"UIPanelButtonTemplate")
    frame.backList:SetWidth(38)
    frame.backList:SetHeight(18)
    frame.backList:SetPoint("TOPLEFT",frame,"TOPLEFT",67,-6)
    frame.backList:SetText("Back")
    frame.backList:SetScript("OnClick",function()
        if MT.historyBrowserMode == "COUNTS" then
            MT.historyBrowserMode="DETAIL"
        else
            MT.historyBrowserMode="LIST"
        end
        MT:UpdateHistoryWindow()
    end)
    HStyle(frame.backList)

    frame.capacity = HCreateText(frame, 15, -30, 270, "CENTER")

    frame.rows = {}
    local i
    for i=1,HISTORY_PAGE_SIZE do
        local row = CreateFrame("Button",nil,frame,"UIPanelButtonTemplate")
        row:SetWidth(270)
        row:SetHeight(18)
        row:SetPoint("TOPLEFT",frame,"TOPLEFT",15,-47-((i-1)*20))
        row:SetText("")
        row:SetScript("OnClick",function()
            if this.historyIndex then
                MT.historySelectedIndex = this.historyIndex
                MT.historyBrowserMode = "DETAIL"
                MT:UpdateHistoryWindow()
            end
        end)
        row:SetScript("OnEnter",function()
            if not this.historySummary then return end
            local s=this.historySummary
            local tip=MT:GetAnalysisTooltip()
            tip:SetOwner(this,"ANCHOR_CURSOR")
            tip:SetText(tostring(s.label or "History Summary"),1,0.82,0)
            tip:AddLine(HTag(s).."  |  SUMMARY ONLY",0.85,0.85,0.85)
            tip:AddLine("RAW "..HN(s.raw).."  Taken "..HN(s.taken).."  Prevented "..HN(HStopped(s)),1,1,1)
            tip:AddLine("Click to view retained aggregate totals.",0.65,0.85,1)
            tip:Show()
        end)
        row:SetScript("OnLeave",function() MT:HideAnalysisTooltip() end)
        HStyle(row)
        frame.rows[i]=row
    end

    frame.prev = CreateFrame("Button",nil,frame,"UIPanelButtonTemplate")
    frame.prev:SetWidth(32)
    frame.prev:SetHeight(16)
    frame.prev:SetPoint("BOTTOMLEFT",frame,"BOTTOMLEFT",15,14)
    frame.prev:SetText("<")
    frame.prev:SetScript("OnClick",function()
        MT.historyPage=math.max(1,(MT.historyPage or 1)-1)
        MT:UpdateHistoryWindow()
    end)
    HStyle(frame.prev)

    frame.pageText = frame:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    frame.pageText:SetPoint("BOTTOM",frame,"BOTTOM",0,18)
    frame.pageText:SetWidth(160)
    frame.pageText:SetJustifyH("CENTER")

    frame.next = CreateFrame("Button",nil,frame,"UIPanelButtonTemplate")
    frame.next:SetWidth(32)
    frame.next:SetHeight(16)
    frame.next:SetPoint("BOTTOMRIGHT",frame,"BOTTOMRIGHT",-15,14)
    frame.next:SetText(">")
    frame.next:SetScript("OnClick",function()
        MT.historyPage=(MT.historyPage or 1)+1
        MT:UpdateHistoryWindow()
    end)
    HStyle(frame.next)

    -- HIST64UI3: keep the existing 300x258 detail window, but move the report
    -- upward and use subtle gold guides with dedicated right-aligned values.
    frame.detailHeader = HCreateText(frame, 15, -33, 270, "CENTER", "GameFontNormalSmall")
    frame.detailMeta   = HCreateText(frame, 15, -47, 270, "CENTER")

    frame.grid = CreateFrame("Frame", nil, frame)
    frame.grid:SetWidth(270)
    frame.grid:SetHeight(154)
    frame.grid:SetPoint("TOPLEFT", frame, "TOPLEFT", 15, -62)

    local function HGridLine(parent, x1, y1, x2, y2, alpha)
        local t = parent:CreateTexture(nil, "BACKGROUND")
        t:SetTexture("Interface\\Buttons\\WHITE8X8")
        t:SetVertexColor(0.72, 0.56, 0.12, alpha or 0.20)
        if x1 == x2 then
            t:SetWidth(1)
            t:SetPoint("TOPLEFT", parent, "TOPLEFT", x1, y1)
            t:SetPoint("BOTTOMLEFT", parent, "TOPLEFT", x2, y2)
        else
            t:SetHeight(1)
            t:SetPoint("TOPLEFT", parent, "TOPLEFT", x1, y1)
            t:SetPoint("TOPRIGHT", parent, "TOPLEFT", x2, y2)
        end
        return t
    end

    frame.leftHeader = HCreateText(frame.grid, 4, -2, 126, "CENTER", "GameFontNormalSmall")
    frame.leftHeader:SetText("Overall")
    frame.rightHeader = HCreateText(frame.grid, 141, -2, 125, "CENTER", "GameFontNormalSmall")
    frame.rightHeader:SetText("Physical")
    frame.magicHeader = HCreateText(frame.grid, 141, -67, 125, "CENTER", "GameFontNormalSmall")
    frame.magicHeader:SetText("Magic")
    frame.estHeader = HCreateText(frame.grid, 4, -67, 126, "CENTER", "GameFontNormalSmall")
    frame.estHeader:SetText("EST.")

    -- HIST64UI14: deliberate Summary grid geometry.  The old generic 10-row
    -- grid drew guides through the EST./Magic section break and left the
    -- lower cells visually offset.  Keep a single center divider, then draw
    -- guides only where real data rows exist.
    HGridLine(frame.grid, 135, -1, 135, -153, 0.24)
    HGridLine(frame.grid, 0, -16, 270, -16, 0.13)
    HGridLine(frame.grid, 0, -30, 270, -30, 0.09)
    HGridLine(frame.grid, 0, -42, 270, -42, 0.09)
    HGridLine(frame.grid, 0, -54, 270, -54, 0.09)
    HGridLine(frame.grid, 0, -64, 270, -64, 0.18)
    HGridLine(frame.grid, 0, -82, 270, -82, 0.09)
    HGridLine(frame.grid, 0, -94, 270, -94, 0.09)
    HGridLine(frame.grid, 0, -106, 270, -106, 0.09)
    HGridLine(frame.grid, 0, -118, 270, -118, 0.09)
    HGridLine(frame.grid, 0, -130, 270, -130, 0.09)

    -- HIST64UI12+: Summary remains two-column. EST./Magic are true section
    -- headers, while the More Info button owns the unused lower-right cell.
    frame.detailRows = {}
    local summaryRowY = {-20,-32,-44,-56,-68,-80,-92,-104,-116,-128}
    for i = 1, table.getn(summaryRowY) do
        local y = summaryRowY[i]
        local lLabel = HCreateText(frame.grid, 4, y, 69, "LEFT")
        local lValue = HCreateText(frame.grid, 74, y, 57, "RIGHT")
        local rLabel = HCreateText(frame.grid, 141, y, 73, "LEFT")
        local rValue = HCreateText(frame.grid, 215, y, 51, "RIGHT")

        frame.detailRows[i] = {
            lLabel = lLabel, lValue = lValue,
            rLabel = rLabel, rValue = rValue
        }
    end

    -- HIST64UI10: More Info opens derived mitigation, avoidance breakdown,
    -- and compact landed/attempted counters without restoring event history.
    frame.countsButton = CreateFrame("Button", nil, frame.grid, "UIPanelButtonTemplate")
    frame.countsButton:SetWidth(76)
    frame.countsButton:SetHeight(16)
    frame.countsButton:SetPoint("BOTTOMRIGHT", frame.grid, "BOTTOMRIGHT", -4, 2)
    frame.countsButton:SetText("More Info")
    frame.countsButton:SetScript("OnClick", function()
        MT.historyBrowserMode = "COUNTS"
        MT:UpdateHistoryWindow()
    end)
    frame.countsButton:SetScript("OnEnter", function()
        local tip=MT:GetAnalysisTooltip()
        tip:SetOwner(this,"ANCHOR_CURSOR")
        tip:SetText("More Info",1,0.82,0)
        tip:AddLine("Mitigation, avoidance breakdown and attack totals.",0.85,0.85,0.85)
        tip:Show()
    end)
    frame.countsButton:SetScript("OnLeave", function() MT:HideAnalysisTooltip() end)
    HStyle(frame.countsButton)

    -- HIST64UI12 More Info drill-down.  Keep the standard 300x231 window and
    -- use the same compact two-column geometry as History Summary.
    frame.countsDetail = CreateFrame("Frame", nil, frame)
    frame.countsDetail:SetWidth(270)
    frame.countsDetail:SetHeight(154)
    frame.countsDetail:SetPoint("TOPLEFT", frame, "TOPLEFT", 15, -62)

    frame.countsHeader = HCreateText(frame.countsDetail, 4, -2, 262, "CENTER", "GameFontNormalSmall")
    frame.countsHeader:SetText("More Info")

    -- HIST64UI14: More Info now has four mitigation rows, so rebuild its
    -- guides around the actual two-by-two section geometry instead of the
    -- earlier 3-row mitigation grid.
    HGridLine(frame.countsDetail, 135, -16, 135, -148, 0.24)
    HGridLine(frame.countsDetail, 0, -16, 270, -16, 0.13)
    HGridLine(frame.countsDetail, 0, -86, 270, -86, 0.18)

    frame.countRows = {}
    -- name, y, labelX, labelWidth, valueX, valueWidth, header
    local infoRows = {
        {"MITIGATION", -20,   4, 124,   0,  0, true},
        {"Overall",    -34,  18,  62,  78, 50, false},
        {"Physical",   -46,  18,  62,  78, 50, false},
        {"Magic",      -58,  18,  62,  78, 50, false},
        {"DR",         -70,  18,  62,  78, 50, false},

        {"ATTACKS/CASTS", -20, 141, 125,   0,  0, true},
        {"Events",     -34, 152,  62, 214, 52, false},
        {"Absorbs",    -46, 152,  62, 214, 52, false},
        {"Physical Landed", -58, 152,  90, 224, 42, false},
        {"Magic Landed",    -70, 152,  90, 224, 42, false},

        {"AVOIDANCE",  -94,   4, 124,   0,  0, true},
        {"Dodge",      -108, 18,  48,  64, 64, false},
        {"Parry",      -120, 18,  48,  64, 64, false},
        {"Miss",       -132, 18,  48,  64, 64, false},

        {"MISC.",      -94, 141, 125,   0,  0, true},
        {"Absorbed",   -108,152,  62, 214, 52, false}
    }
    local ii, spec
    for ii=1,table.getn(infoRows) do
        spec=infoRows[ii]
        local label = HCreateText(frame.countsDetail, spec[3], spec[2], spec[4], "LEFT", spec[7] and "GameFontNormalSmall" or nil)
        local value = nil
        if not spec[7] then value = HCreateText(frame.countsDetail, spec[5], spec[2], spec[6], "RIGHT") end
        frame.countRows[ii] = {label=label,value=value,isHeader=spec[7]}
    end
    frame.countsDetail:Hide()

    self.historyFrame=frame
    self:RegisterManagedPage("HISTORY",frame)
    if self.InstallSafeDragging then self:InstallSafeDragging(frame) end

    HApplyWindowStyle(frame)
    HPositionHeader(frame,false)
    frame:Hide()
    return frame
end

local function HShowList(frame, show)
    local i
    for i=1,HISTORY_PAGE_SIZE do
        if show then frame.rows[i]:Show() else frame.rows[i]:Hide() end
    end
    local items={frame.capacity,frame.prev,frame.next,frame.pageText}
    for i=1,table.getn(items) do
        if show then items[i]:Show() else items[i]:Hide() end
    end
end

local function HShowDetail(frame, show)
    local items={
        frame.backList,frame.detailHeader,frame.detailMeta,
        frame.grid,frame.magicHeader,frame.estHeader,frame.countsButton
    }
    local i
    for i=1,table.getn(items) do
        if show then items[i]:Show() else items[i]:Hide() end
    end
end

local function HShowCountsDetail(frame, show)
    if not frame.countsDetail then return end
    if show then frame.countsDetail:Show() else frame.countsDetail:Hide() end
end

function MT:UpdateHistoryWindow()
    local frame=self:CreateHistoryWindow()
    local summaries=HSummaries(self)
    local count=table.getn(summaries)

    if self.historyBrowserMode == "COUNTS" then
        local index=tonumber(self.historySelectedIndex) or 1
        local s=summaries[index]
        if not s then
            self.historyBrowserMode="LIST"
        else
            frame:SetHeight(DETAIL_HEIGHT)
            HShowList(frame,false)
            HShowDetail(frame,false)
            frame.backList:Show()
            frame.detailHeader:Show()
            frame.detailMeta:Show()
            HShowCountsDetail(frame,true)
            frame.title:SetText("History More Info")
            HPositionHeader(frame,true)

            frame.detailHeader:SetText("["..HTag(s).."]  "..tostring(s.label or "Unknown"))
            local when=""
            if type(date)=="function" and (tonumber(s.summarizedAt) or 0)>0 then
                when=date("%Y-%m-%d %H:%M",tonumber(s.summarizedAt)) or ""
            end
            frame.detailMeta:SetText(
                "#"..index.."  |  "..tostring(math.floor((tonumber(s.duration) or 0)+0.5))..
                "s  |  "..tostring(s.enemyCount or 0).." enemies"..
                (when~="" and ("  |  "..when) or "")
            )

            local raw=tonumber(s.raw) or 0
            local taken=tonumber(s.taken or s.damageTaken) or 0
            local praw=tonumber(s.physicalRaw) or 0
            local ptaken=tonumber(s.physicalTaken) or 0
            local mraw=tonumber(s.magicRaw) or 0
            local mtaken=tonumber(s.magicTaken) or 0
            local overallPct = raw>0 and ((raw-taken)/raw)*100 or 0
            local physicalPct = praw>0 and ((praw-ptaken)/praw)*100 or 0
            local magicPct = mraw>0 and ((mraw-mtaken)/mraw)*100 or 0
            -- DR mitigation is intentionally scoped to the retained DR layers:
            -- DR / (Taken + DR).  Guard zero totals so empty/zero-DR summaries
            -- display 0.0% rather than producing an invalid division.
            local drAmount = (tonumber(s.physicalDR) or 0) + (tonumber(s.physicalFlatDR) or 0) +
                             (tonumber(s.magicDR) or 0) + (tonumber(s.magicFlatDR) or 0)
            local drBase = taken + drAmount
            local drPct = drBase>0 and (drAmount/drBase)*100 or 0
            local dcount=tonumber(s.dodgeCount) or 0
            local pcount=tonumber(s.parryCount) or 0
            local micount=tonumber(s.missCount) or 0
            local melee=tonumber(s.meleeHitCount) or 0
            local magic=tonumber(s.magicHitCount) or 0
            -- Physical attempts = landed + completely prevented physical
            -- outcomes. Full Blocks belong with Dodge/Parry/Miss here; Partial
            -- Blocks remain landed and are therefore NOT added separately.
            local physicalAttempts = melee + dcount + pcount + micount + (tonumber(s.fullBlockCount) or 0)
            local magicAttempts = magic + (tonumber(s.fullResistCount) or 0)
            local totalAttempts = physicalAttempts + magicAttempts
            local rows={
                {"MITIGATION", nil},
                {"Overall", format("%.1f%%",overallPct)},
                {"Physical", format("%.1f%%",physicalPct)},
                {"Magic", format("%.1f%%",magicPct)},
                {"DR", format("%.1f%%",drPct)},
                {"ATTACKS/CASTS", nil},
                {"Events", HN(tonumber(s.eventCount) or 0)},
                {"Absorbs", HN(tonumber(s.absorbCount) or 0).." / "..HN(totalAttempts)},
                {"Physical Landed", HN(melee).." / "..HN(physicalAttempts)},
                {"Magic Landed", HN(magic).." / "..HN(magicAttempts)},
                {"AVOIDANCE", nil},
                {"Dodge", HCountValue(s.dodgedEstimated,dcount)},
                {"Parry", HCountValue(s.parriedEstimated,pcount)},
                {"Miss", HCountValue(s.missedEstimated,micount)},
                {"MISC.", nil},
                {"Absorbed", HN(s.absorbed)}
            }
            local ri,row,item
            for ri=1,table.getn(frame.countRows or {}) do
                row=frame.countRows[ri]
                item=rows[ri]
                row.label:SetText(item and item[1] or "")
                if row.value then row.value:SetText(item and item[2] or "") end
            end

            HApplyWindowStyle(frame)
            return
        end
    end

    if self.historyBrowserMode == "DETAIL" then
        local index=tonumber(self.historySelectedIndex) or 1
        local s=summaries[index]
        if not s then
            self.historyBrowserMode="LIST"
        else
            frame:SetHeight(DETAIL_HEIGHT)
            HShowList(frame,false)
            HShowDetail(frame,true)
            HShowCountsDetail(frame,false)
            frame.title:SetText("History Summary")
            HPositionHeader(frame,true)

            frame.detailHeader:SetText("["..HTag(s).."]  "..tostring(s.label or "Unknown"))
            local when=""
            if type(date)=="function" and (tonumber(s.summarizedAt) or 0)>0 then
                when=date("%Y-%m-%d %H:%M",tonumber(s.summarizedAt)) or ""
            end
            frame.detailMeta:SetText(
                "#"..index.."  |  "..tostring(math.floor((tonumber(s.duration) or 0)+0.5))..
                "s  |  "..tostring(s.enemyCount or 0).." enemies"..
                (when~="" and ("  |  "..when) or "")
            )

            local leftRows={
                {"RAW", HN(s.raw)},
                {"Taken", HN(s.taken)},
                {"Prevented", HN(HStopped(s))},
                {"DR", HN((tonumber(s.physicalDR) or 0) + (tonumber(s.physicalFlatDR) or 0) + (tonumber(s.magicDR) or 0) + (tonumber(s.magicFlatDR) or 0))},
                nil, -- EST. section header
                {"Armor", HN(s.armorReduced)},
                {"Avoidance", HN(s.avoidance)},
                {"Full Block", HCountValue(s.fullBlockedEstimated, s.fullBlockCount)},
                {"Full Resist", HCountValue(s.resistedFullEstimated, s.fullResistCount)},
                nil
            }

            local rightRows={
                {"Physical RAW", HN(s.physicalRaw)},
                {"Physical Taken", HN(s.physicalTaken)},
                {"Physical DR", HN((tonumber(s.physicalDR) or 0) + (tonumber(s.physicalFlatDR) or 0))},
                {"Partial Block", HCountValue(s.blocked, s.blockCount)},
                nil, -- Magic section header
                {"Magic RAW", HN(s.magicRaw)},
                {"Magic Taken", HN(s.magicTaken)},
                {"Magic DR", HN((tonumber(s.magicDR) or 0) + (tonumber(s.magicFlatDR) or 0))},
                {"Partial Resists", HCountValue(s.resistedPartial, s.partialResistCount)},
                nil
            }

            local ri, row, left, right
            for ri = 1, table.getn(frame.detailRows or {}) do
                row = frame.detailRows[ri]
                left = leftRows[ri]
                right = rightRows[ri]
                row.lLabel:SetText(left and left[1] or "")
                row.lValue:SetText(left and left[2] or "")
                row.rLabel:SetText(right and right[1] or "")
                row.rValue:SetText(right and right[2] or "")
            end

            HApplyWindowStyle(frame)
            return
        end
    end

    self.historyBrowserMode="LIST"
    frame:SetHeight(LIST_HEIGHT)
    HShowDetail(frame,false)
    HShowCountsDetail(frame,false)
    HShowList(frame,true)
    frame.title:SetText("History")
    HPositionHeader(frame,false)
    frame.capacity:SetText("History "..count.." / 64  |  summary-only records")

    local pages=math.max(1,math.ceil(count/HISTORY_PAGE_SIZE))
    local page=tonumber(self.historyPage) or 1
    if page<1 then page=1 end
    if page>pages then page=pages end
    self.historyPage=page

    frame.pageText:SetText("Page "..page.." / "..pages)
    if page<=1 then frame.prev:Disable() else frame.prev:Enable() end
    if page>=pages then frame.next:Disable() else frame.next:Enable() end

    local i,index,s,label
    for i=1,HISTORY_PAGE_SIZE do
        index=((page-1)*HISTORY_PAGE_SIZE)+i
        s=summaries[index]
        local row=frame.rows[i]
        row.historyIndex=nil
        row.historySummary=nil
        if s then
            label=tostring(s.label or "Unknown")
            if string.len(label)>20 then label=string.sub(label,1,19).."~" end
            row:SetText(format("H%-2d  %-5s  %-20s  RAW %s  %4.1f%%",
                index,HTag(s),label,HN(s.raw),HPct(s)))
            row.historyIndex=index
            row.historySummary=s
            row:Enable()
            row:Show()
        else
            row:SetText("")
            row:Disable()
            row:Hide()
        end
    end
    HApplyWindowStyle(frame)
end

function MT:ToggleHistoryBrowser()
    self.historyBrowserMode="LIST"
    self.historyPage=self.historyPage or 1
    self:CreateHistoryWindow()
    self:ShowManagedPage("HISTORY",function(owner) owner:UpdateHistoryWindow() end)
end

local H_OldRefreshManagedPageRegistry=MT.RefreshManagedPageRegistry
function MT:RefreshManagedPageRegistry()
    H_OldRefreshManagedPageRegistry(self)
    local history=self.historyFrame or getglobal("MainTankHistoryFrame")
    if history then self:RegisterManagedPage("HISTORY",history) end
end

-- Final product navigation:
--   Timeline | Compare | History | Pie Chart
--   Biggest  | Export  | Boss    | Details
local H_OldCreateUI=MT.CreateUI
function MT:CreateUI()
    H_OldCreateUI(self)
    local frame=self.frame
    if not frame or frame.historyButton then return end

    local button=CreateFrame("Button",nil,frame,"UIPanelButtonTemplate")
    button:SetWidth(68)
    button:SetHeight(18)
    button:SetText("History")
    button:SetScript("OnClick",function() MT:ToggleHistoryBrowser() end)
    button:SetScript("OnEnter",function()
        local tip=MT:GetAnalysisTooltip()
        tip:SetOwner(this,"ANCHOR_CURSOR")
        tip:SetText("History",1,0.82,0)
        tip:AddLine("Browse up to 64 lightweight long-term summaries.",0.85,0.85,0.85)
        tip:AddLine("History stores summary totals only.",1,0.82,0)
        tip:Show()
    end)
    button:SetScript("OnLeave",function() MT:HideAnalysisTooltip() end)
    HStyle(button)
    frame.historyButton=button
    self:RegisterFullControl(button)

    local timeline=self.fullControls and self.fullControls[1]
    local biggest=self.fullControls and self.fullControls[2]
    local details=self.fullControls and self.fullControls[3]
    local pie=self.fullControls and self.fullControls[4]

    local function place(b,x,y,text)
        if not b then return end
        b:ClearAllPoints()
        b:SetWidth(68)
        b:SetHeight(18)
        b:SetPoint("TOPLEFT",frame,"TOPLEFT",x,y)
        if text then b:SetText(text) end
        HStyle(b)
    end

    place(timeline,8,-28,"Timeline")
    place(frame.compareButton,80,-28,"Compare")
    place(button,152,-28,"History")
    place(pie,224,-28,"Pie Chart")

    place(biggest,8,-49,"Biggest")
    place(frame.exportButton,80,-49,"Export")
    place(frame.bossButton,152,-49,"Boss")
    place(details,224,-49,"Details")
end

local H_OldHandleSlash=MT.HandleSlash
function MT:HandleSlash(msg)
    local raw=string.lower(tostring(msg or ""))
    raw=string.gsub(raw,"^%s+","")
    raw=string.gsub(raw,"%s+$","")

    if raw=="history" or raw=="hist" then
        self:ToggleHistoryBrowser()
        return
    end

    local _,_,n=string.find(raw,"^history%s+(%d+)$")
    if n then
        self.historySelectedIndex=tonumber(n)
        self.historyBrowserMode="DETAIL"
        self:CreateHistoryWindow()
        self:ShowManagedPage("HISTORY",function(owner) owner:UpdateHistoryWindow() end)
        return
    end

    return H_OldHandleSlash(self,msg)
end

-- Version ownership remains centralized in Core/Release.lua.
