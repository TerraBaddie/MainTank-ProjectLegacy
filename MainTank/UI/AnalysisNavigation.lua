-- MainTank REFAC1 - Analysis navigation compatibility layer
-- Extracted verbatim from the historical Engine.lua override stack.
-- Load immediately after Core\Engine.lua.

local MT = MainTank
local E = MT._engine
local floor = math.floor
local format = string.format
local lower = string.lower
local MT_LEGACY_BACKDROP = E.MT_LEGACY_BACKDROP
local StyleLegacyButton = E.StyleLegacyButton
local FinalizeLegacyWindow = E.FinalizeLegacyWindow
local Print = E.Print
local TimelineValue = E.TimelineValue
local GetPieEntryUnderMouse = E.GetPieEntryUnderMouse

-- ============================================================================
-- v1.0.0 RC1 - Single-window navigation layer
-- Keeps the mature combat engine intact while presenting Summary, Pie,
-- Timeline, Details, and Biggest as mutually-exclusive pages at the exact
-- footprint and position of the main MainTank frame.
-- ============================================================================

local RC_PAGE_WIDTH, RC_PAGE_HEIGHT = 300, 231

local function RC_CopyMainAnchor(frame)
    if not MT.frame then return end
    local point, relativeTo, relativePoint, x, y = MT.frame:GetPoint()
    frame:ClearAllPoints()
    frame:SetPoint(point or "CENTER", relativeTo or UIParent, relativePoint or point or "CENTER", x or 0, y or 0)
end

local function RC_HideAnalysisPages(except)
    -- Hide both the current references and any globally-named legacy frames.
    -- This prevents an old popup instance from surviving underneath the RC page.
    local pages = {
        MT.pieFrame,
        MT.timelineFrame,
        MT.detailsFrame,
        MT.biggestFrame,
        getglobal("MainTankPieFrame"),
        getglobal("MainTankTimelineFrame"),
        getglobal("MainTankDetailsFrame"),
        getglobal("MainTankBiggestFrame")
    }
    local seen = {}
    local i, page
    for i = 1, table.getn(pages) do
        page = pages[i]
        if page and not seen[page] then
            seen[page] = true
            if page ~= except then page:Hide() end
        end
    end
    MT:HideAnalysisTooltip()
end

function MT:ReturnToMain()
    -- One authoritative transition: nothing else may remain visible.
    self.activeRCPage = nil
    RC_HideAnalysisPages(nil)
    if self.frame then
        self.frame:SetWidth(300)
        self.frame:SetHeight(231)
        self.miniMode = false
        if MainTankDB then MainTankDB.miniMode = false end
        self.frame:Show()
        -- Restore the main controls directly. Calling SetMiniMode here used to
        -- trigger nested page updates during the transition.
        local i
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
        if self.frame.shrinkButton then
            self.frame.shrinkButton:SetText("-")
            self.frame.shrinkButton:SetWidth(22)
            self.frame.shrinkButton:ClearAllPoints()
            self.frame.shrinkButton:SetPoint("TOPRIGHT", self.frame, "TOPRIGHT", -27, -5)
        end
        self:SetPage(self.currentPage or "RAW")
        self:UpdateDisplay()
    end
    -- Defensive second pass for OnShow handlers from migrated builds.
    RC_HideAnalysisPages(nil)
end

local function RC_CreatePageFrame(name, title)
    -- REFACXML1: common static analysis-page geometry is declared in
    -- UI\AnalysisFrames.xml; Lua keeps movement, state, scripts, and skinning.
    local frame = CreateFrame("Frame", name, UIParent, "MainTankAnalysisPageTemplate")
    local prefix = frame:GetName()
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function() this:StartMoving() end)
    frame:SetScript("OnDragStop", function()
        this:StopMovingOrSizing()
        if MT.frame then
            local point, relativeTo, relativePoint, x, y = this:GetPoint()
            -- Vanilla 1.12 can return a nil/invalid relative frame here for a
            -- dynamically-created page.  Passing that five-argument tuple back
            -- into SetPoint triggers the generic "Usage: SetPoint" error.
            point = point or "CENTER"
            relativePoint = relativePoint or point
            x = tonumber(x) or 0
            y = tonumber(y) or 0
            MT.frame:ClearAllPoints()
            if relativeTo and type(relativeTo) == "table" and relativeTo.GetObjectType then
                MT.frame:SetPoint(point, relativeTo, relativePoint, x, y)
            else
                MT.frame:SetPoint(point, UIParent, relativePoint, x, y)
            end
            MainTankDB.position = {point=point, relativePoint=relativePoint, x=x, y=y}
        end
    end)
    frame:SetBackdrop(MT_LEGACY_BACKDROP)
    frame:SetBackdropColor(0.015, 0.015, 0.015, 0.86)
    frame:SetBackdropBorderColor(0, 0, 0, 1)

    frame.title = getglobal(prefix .. "Title")
    frame.title:SetJustifyH("CENTER")
    frame.title:SetText(title)

    local main = getglobal(prefix .. "MainButton")
    main:SetText("MT Main")
    main:SetScript("OnClick", function() MT:ReturnToMain() end)
    frame.mainButton = main

    FinalizeLegacyWindow(frame)
    frame:Hide()
    return frame
end

function MT:ShowRCPage(frame, updater)
    if not frame then return end
    self.activeRCPage = frame
    RC_HideAnalysisPages(frame)
    if self.frame then self.frame:Hide() end
    RC_CopyMainAnchor(frame)
    frame:Show()
    if updater then updater(self) end
    -- Some old page OnShow paths can attempt to reopen another frame.
    RC_HideAnalysisPages(frame)
    if self.frame then self.frame:Hide() end
end

-- PIE PAGE -------------------------------------------------------------------
function MT:CreatePieWindow()
    if self.pieFrame then return self.pieFrame end
    local frame = RC_CreatePageFrame("MainTankPieFrame", "Mitigation Pie")

    frame.modeButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.modeButton:SetWidth(92); frame.modeButton:SetHeight(18)
    frame.modeButton:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -31)
    frame.modeButton:SetText("View: RAW")
    frame.modeButton:SetScript("OnClick", function() MT:CyclePieMode() end)

    frame.ring = CreateFrame("Frame", nil, frame)
    frame.ring:SetWidth(112); frame.ring:SetHeight(112)
    frame.ring:SetPoint("TOPLEFT", frame, "TOPLEFT", 13, -58)
    frame.ring:EnableMouse(true)
    frame.ring:SetFrameLevel(frame:GetFrameLevel() + 2)
    frame.pieTextures, frame.entryEnds, frame.entries = {}, {}, {}
    frame.pieUsed = 0
    frame.ring:SetScript("OnUpdate", function()
        local entry = GetPieEntryUnderMouse(frame)
        if entry ~= frame.hoverEntry then
            frame.hoverEntry = entry
            MT:HideAnalysisTooltip()
            if entry then this.entry = entry; MT:ShowPieTooltip(this) else this.entry = nil end
        end
    end)
    frame.ring:SetScript("OnMouseUp", function()
        local entry = GetPieEntryUnderMouse(frame)
        if entry then MT:OpenPieDetails(entry) end
    end)
    frame.ring:SetScript("OnLeave", function() frame.hoverEntry=nil; this.entry=nil; MT:HideAnalysisTooltip() end)

    frame.legendRows = {}
    local i
    for i = 1, 7 do
        local row = CreateFrame("Frame", nil, frame)
        row:SetWidth(155); row:SetHeight(18); row:EnableMouse(true)
        row:SetPoint("TOPLEFT", frame, "TOPLEFT", 134, -55 - ((i-1)*20))
        row:SetScript("OnEnter", function() MT:ShowPieTooltip(this) end)
        row:SetScript("OnLeave", function() MT:HideAnalysisTooltip() end)
        row:SetScript("OnMouseUp", function() if this.entry then MT:OpenPieDetails(this.entry) end end)
        row.swatch = row:CreateTexture(nil, "ARTWORK")
        row.swatch:SetWidth(10); row.swatch:SetHeight(10); row.swatch:SetPoint("LEFT", row, "LEFT", 0, 0)
        row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.label:SetPoint("LEFT", row.swatch, "RIGHT", 4, 0); row.label:SetWidth(60); row.label:SetJustifyH("LEFT")
        row.value = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.value:SetPoint("RIGHT", row, "RIGHT", 0, 0); row.value:SetWidth(80); row.value:SetJustifyH("RIGHT")
        frame.legendRows[i] = row
    end
    frame.totalText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.totalText:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 15, 31)
    frame.totalText:SetText("Prevented: 0")
    local note = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    note:SetPoint("BOTTOM", frame, "BOTTOM", 0, 11)
    note:SetText("Click a slice or legend row for Details")

    self.pieFrame = frame
    return frame
end

function MT:TogglePie()
    local frame = self:CreatePieWindow()
    self:ShowRCPage(frame, function(owner) owner:UpdatePieWindow() end)
end

-- TIMELINE PAGE --------------------------------------------------------------
function MT:CreateTimelineWindow()
    if self.timelineFrame then return self.timelineFrame end
    local frame = RC_CreatePageFrame("MainTankTimelineFrame", "Mitigation Timeline")

    frame.modeButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.modeButton:SetWidth(88); frame.modeButton:SetHeight(18)
    frame.modeButton:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, -31)
    frame.modeButton:SetText("View: RAW")
    frame.modeButton:SetScript("OnClick", function() MT:CycleTimelineMode() end)

    frame.rangeText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.rangeText:SetPoint("TOP", frame, "TOP", 22, -35)

    frame.graph = CreateFrame("Frame", nil, frame)
    frame.graph:SetPoint("TOPLEFT", frame, "TOPLEFT", 26, -56)
    frame.graph:SetWidth(264); frame.graph:SetHeight(132)
    frame.graph:SetBackdrop(MT_LEGACY_BACKDROP)
    frame.graph:SetBackdropColor(0.01,0.01,0.01,0.85); frame.graph:SetBackdropBorderColor(0,0,0,1)
    frame.cursor = frame.graph:CreateTexture(nil, "OVERLAY")
    frame.cursor:SetWidth(2); frame.cursor:SetTexture(1,0.82,0.1,0.95); frame.cursor:Hide()
    frame.maxText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.maxText:SetPoint("TOPRIGHT", frame.graph, "TOPLEFT", -3, 0)
    frame.midText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.midText:SetPoint("RIGHT", frame.graph, "LEFT", -3, 0)
    local zero = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    zero:SetPoint("BOTTOMRIGHT", frame.graph, "BOTTOMLEFT", -3, 0); zero:SetText("0")

    frame.bars = {}
    local i
    for i = 1, 60 do
        local bar = CreateFrame("Frame", nil, frame.graph)
        bar:SetWidth(3); bar:SetHeight(1); bar:EnableMouse(true)
        bar.texture = bar:CreateTexture(nil, "ARTWORK"); bar.texture:SetTexture(0.2,0.85,0.3,0.9)
        bar.taken = bar:CreateTexture(nil, "OVERLAY"); bar.taken:SetTexture(1,0.22,0.18,0.95); bar.taken:Hide()
        bar:SetScript("OnEnter", function() if this.bucket then MT:ShowTimelineTooltip(this, this.bucket) end end)
        bar:SetScript("OnLeave", function() MT:HideAnalysisTooltip() end)
        bar:SetScript("OnMouseUp", function() if this.bucket then MT:OpenTimelineDetails(this.bucket) end end)
        frame.bars[i] = bar
    end

    frame.prevMinute = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.prevMinute:SetWidth(38); frame.prevMinute:SetHeight(18)
    frame.prevMinute:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 67, 10); frame.prevMinute:SetText("<")
    frame.prevMinute:SetScript("OnClick", function() MT.timelinePage = math.max(0,(MT.timelinePage or 0)-1); MT:UpdateTimelineWindow() end)
    StyleLegacyButton(frame.prevMinute)
    frame.nextMinute = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.nextMinute:SetWidth(38); frame.nextMinute:SetHeight(18)
    frame.nextMinute:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -67, 10); frame.nextMinute:SetText(">")
    frame.nextMinute:SetScript("OnClick", function() MT.timelinePage = (MT.timelinePage or 0)+1; MT:UpdateTimelineWindow() end)
    StyleLegacyButton(frame.nextMinute)
    frame.legend = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.legend:SetPoint("BOTTOM", frame, "BOTTOM", 0, 32); frame.legend:SetText("Green stopped | Red taken")

    self.timelineFrame = frame
    self.timelinePage = self.timelinePage or 0
    return frame
end

function MT:UpdateTimelineWindow()
    local frame = self.timelineFrame
    if not frame then return end
    local timeline = self:GetDisplayTimeline() or {}
    local _, maxSecond = self:GetTimelineRange(timeline)
    local maxPage = math.max(0, math.floor(maxSecond / 60))
    self.timelinePage = math.max(0, math.min(self.timelinePage or 0, maxPage))
    local pageStart = self.timelinePage * 60
    local pageEnd = pageStart + 59
    local buckets, maxValue = {}, 1
    local i
    for i = 1, 60 do
        local sec = pageStart + i - 1
        local bucket = self:AggregateTimelineBucket(timeline, sec, sec)
        local details = self:GetTimelineDetails(sec, sec)
        if details and details.events and details.events > 0 then
            bucket.raw=details.raw or bucket.raw; bucket.physicalRaw=details.physicalRaw or bucket.physicalRaw
            bucket.magicRaw=details.magicRaw or bucket.magicRaw; bucket.taken=details.taken or bucket.taken
            bucket.physicalTaken=details.physicalTaken or bucket.physicalTaken; bucket.magicTaken=details.magicTaken or bucket.magicTaken
            bucket.armor=details.armor or bucket.armor; bucket.block=details.block or bucket.block
            bucket.avoidance=details.avoidance or bucket.avoidance; bucket.resist=details.resist or bucket.resist
            bucket.absorb=details.absorb or bucket.absorb; bucket.events=details.events or bucket.events
        end
        buckets[i]=bucket
        local value=TimelineValue(bucket,self.timelineMode)
        if value>maxValue then maxValue=value end
    end
    frame.modeButton:SetText("View: "..(self.timelineMode or "RAW"))
    frame.rangeText:SetText(format("%ds - %ds",pageStart,pageEnd+1))
    frame.maxText:SetText(self:FormatNumber(maxValue)); frame.midText:SetText(self:FormatNumber(maxValue/2))
    local graphHeight, graphWidth, spacing = 128, 260, 1
    local barWidth = math.max(2, math.floor((graphWidth-59*spacing)/60))
    local used = barWidth*60+59*spacing; local leftPad=math.floor((graphWidth-used)/2)+2
    for i=1,60 do
        local bar,bucket=frame.bars[i],buckets[i]
        local value=TimelineValue(bucket,self.timelineMode)
        local height=math.floor((value/maxValue)*graphHeight); if value>0 and height<1 then height=1 end
        local taken=0
        if self.timelineMode=="PHYSICAL" then taken=bucket.physicalTaken or 0
        elseif self.timelineMode=="MAGIC" then taken=bucket.magicTaken or 0
        else taken=bucket.taken or 0 end
        if taken>value then taken=value end
        local stopped=value-taken
        local stoppedH=math.floor((stopped/maxValue)*graphHeight)
        local takenH=height-stoppedH
        if stopped>0 and stoppedH<1 then stoppedH=1 end
        if taken>0 and takenH<1 then takenH=1 end
        bar:SetWidth(barWidth); bar:SetHeight(math.max(1,height)); bar:ClearAllPoints()
        bar:SetPoint("BOTTOMLEFT",frame.graph,"BOTTOMLEFT",leftPad+(i-1)*(barWidth+spacing),1)
        bar.bucket=bucket; bar.second=pageStart+i-1
        bar.texture:ClearAllPoints(); bar.texture:SetPoint("BOTTOMLEFT",bar,"BOTTOMLEFT",0,0)
        bar.texture:SetWidth(barWidth); bar.texture:SetHeight(math.max(1,stoppedH))
        if stoppedH>0 then bar.texture:Show() else bar.texture:Hide() end
        bar.taken:ClearAllPoints(); bar.taken:SetPoint("BOTTOMLEFT",bar,"BOTTOMLEFT",0,stoppedH)
        bar.taken:SetWidth(barWidth); bar.taken:SetHeight(math.max(1,takenH))
        if takenH>0 then bar.taken:Show() else bar.taken:Hide() end
        if value>0 then bar:Show() else bar:Hide() end
    end
    frame.cursor:Hide()
    if self.timelineSelection then
        local sec=self.timelineSelection.firstSecond or 0
        if sec>=pageStart and sec<=pageEnd then
            local bar=frame.bars[(sec-pageStart)+1]
            frame.cursor:ClearAllPoints(); frame.cursor:SetPoint("BOTTOM",bar,"BOTTOM",0,-1)
            frame.cursor:SetHeight(graphHeight+4); frame.cursor:Show()
        end
    end
    if self.timelinePage > 0 then
        frame.prevMinute:Enable()
    else
        frame.prevMinute:Disable()
    end
    if self.timelinePage < maxPage then
        frame.nextMinute:Enable()
    else
        frame.nextMinute:Disable()
    end
    frame.title:SetText("Timeline - "..self:GetViewLabel())
end

function MT:ToggleTimeline()
    local frame=self:CreateTimelineWindow()
    self:ShowRCPage(frame,function(owner) owner:UpdateTimelineWindow() end)
end

-- DETAILS PAGE ---------------------------------------------------------------
function MT:CreateDetailsWindow()
    if self.detailsFrame then return self.detailsFrame end
    local frame=RC_CreatePageFrame("MainTankDetailsFrame","Mitigation Details")
    frame.clearFilter=CreateFrame("Button",nil,frame,"UIPanelButtonTemplate")
    frame.clearFilter:SetWidth(52); frame.clearFilter:SetHeight(18); frame.clearFilter:SetPoint("TOPRIGHT",frame,"TOPRIGHT",-27,-29)
    frame.clearFilter:SetText("All"); frame.clearFilter:SetScript("OnClick",function() MT:ClearDetailsFilter() end); frame.clearFilter:Hide()

    local eh=frame:CreateFontString(nil,"OVERLAY","GameFontNormalSmall"); eh:SetPoint("TOPLEFT",frame,"TOPLEFT",12,-33); eh:SetText("Enemies")
    frame.enemyRows={}
    local i
    for i=1,4 do
        local row=CreateFrame("Button",nil,frame); row:SetWidth(132); row:SetHeight(17); row:SetPoint("TOPLEFT",frame,"TOPLEFT",10,-48-(i-1)*18)
        row.highlight=row:CreateTexture(nil,"BACKGROUND"); row.highlight:SetAllPoints(row); row.highlight:SetTexture(0.35,0.12,0.12,0.65); row.highlight:Hide()
        row.name=row:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall"); row.name:SetPoint("LEFT",row,"LEFT",2,0); row.name:SetWidth(76); row.name:SetJustifyH("LEFT")
        row.value=row:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall"); row.value:SetPoint("RIGHT",row,"RIGHT",-2,0); row.value:SetJustifyH("RIGHT")
        row:SetScript("OnClick",function() if this.data then MT.detailsSelectedEnemy=this.data.name; MT.detailsAbilityPage=1; MT:UpdateDetailsWindow() end end)
        row:SetScript("OnEnter",function() if this.data then MT:ShowDetailTooltip(this,this.data,"Enemy totals") end end)
        row:SetScript("OnLeave",function() MT:HideAnalysisTooltip() end)
        frame.enemyRows[i]=row
    end
    frame.enemyPrev=CreateFrame("Button",nil,frame,"UIPanelButtonTemplate"); frame.enemyPrev:SetWidth(26); frame.enemyPrev:SetHeight(16); frame.enemyPrev:SetPoint("TOPLEFT",frame,"TOPLEFT",12,-123); frame.enemyPrev:SetText("<"); frame.enemyPrev:SetScript("OnClick",function() MT.detailsEnemyPage=MT.detailsEnemyPage-1; MT:UpdateDetailsWindow() end)
    frame.enemyNext=CreateFrame("Button",nil,frame,"UIPanelButtonTemplate"); frame.enemyNext:SetWidth(26); frame.enemyNext:SetHeight(16); frame.enemyNext:SetPoint("TOPLEFT",frame,"TOPLEFT",108,-123); frame.enemyNext:SetText(">"); frame.enemyNext:SetScript("OnClick",function() MT.detailsEnemyPage=MT.detailsEnemyPage+1; MT:UpdateDetailsWindow() end)
    frame.enemyPageText=frame:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall"); frame.enemyPageText:SetPoint("TOP",frame,"TOPLEFT",73,-126)

    frame.selectedName=frame:CreateFontString(nil,"OVERLAY","GameFontNormal"); frame.selectedName:SetPoint("TOPLEFT",frame,"TOPLEFT",151,-33); frame.selectedName:SetWidth(137); frame.selectedName:SetJustifyH("LEFT")
    frame.summary=frame:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall"); frame.summary:SetPoint("TOPLEFT",frame,"TOPLEFT",151,-48); frame.summary:SetWidth(137); frame.summary:SetJustifyH("LEFT")
    frame.abilityRows={}
    for i=1,4 do
        local row=CreateFrame("Frame",nil,frame); row:SetWidth(140); row:SetHeight(17); row:SetPoint("TOPLEFT",frame,"TOPLEFT",149,-74-(i-1)*18); row:EnableMouse(true)
        row.name=row:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall"); row.name:SetPoint("LEFT",row,"LEFT",2,0); row.name:SetWidth(70); row.name:SetJustifyH("LEFT")
        row.school=row:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall"); row.school:SetPoint("LEFT",row,"LEFT",72,0); row.school:SetWidth(38); row.school:SetJustifyH("LEFT")
        row.raw=row:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall"); row.raw:SetPoint("RIGHT",row,"RIGHT",-30,0); row.raw:SetJustifyH("RIGHT")
        row.taken=row:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall"); row.taken:SetPoint("RIGHT",row,"RIGHT",-1,0); row.taken:SetJustifyH("RIGHT")
        row:SetScript("OnEnter",function() if this.data then MT:ShowDetailTooltip(this,this.data,"Ability details") end end); row:SetScript("OnLeave",function() MT:HideAnalysisTooltip() end)
        frame.abilityRows[i]=row
    end
    frame.abilityPrev=CreateFrame("Button",nil,frame,"UIPanelButtonTemplate"); frame.abilityPrev:SetWidth(26); frame.abilityPrev:SetHeight(16); frame.abilityPrev:SetPoint("TOPLEFT",frame,"TOPLEFT",151,-148); frame.abilityPrev:SetText("<"); frame.abilityPrev:SetScript("OnClick",function() MT.detailsAbilityPage=MT.detailsAbilityPage-1; MT:UpdateDetailsWindow() end)
    frame.abilityNext=CreateFrame("Button",nil,frame,"UIPanelButtonTemplate"); frame.abilityNext:SetWidth(26); frame.abilityNext:SetHeight(16); frame.abilityNext:SetPoint("TOPLEFT",frame,"TOPLEFT",263,-148); frame.abilityNext:SetText(">"); frame.abilityNext:SetScript("OnClick",function() MT.detailsAbilityPage=MT.detailsAbilityPage+1; MT:UpdateDetailsWindow() end)
    frame.abilityPageText=frame:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall"); frame.abilityPageText:SetPoint("TOP",frame,"TOPLEFT",220,-151)

    frame.replayCount=frame:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall"); frame.replayCount:SetPoint("TOPRIGHT",frame,"TOPRIGHT",-12,-171)
    frame.replayText=frame:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall"); frame.replayText:SetPoint("TOPLEFT",frame,"TOPLEFT",12,-171); frame.replayText:SetWidth(276); frame.replayText:SetHeight(30); frame.replayText:SetJustifyH("LEFT"); frame.replayText:SetJustifyV("TOP")
    frame.replayPrev=CreateFrame("Button",nil,frame,"UIPanelButtonTemplate"); frame.replayPrev:SetWidth(52); frame.replayPrev:SetHeight(16); frame.replayPrev:SetPoint("BOTTOMLEFT",frame,"BOTTOMLEFT",12,11); frame.replayPrev:SetText("Previous"); frame.replayPrev:SetScript("OnClick",function() MT:SelectReplayEvent((MT.detailsSelectedEvent or 1)-1) end)
    frame.replayNext=CreateFrame("Button",nil,frame,"UIPanelButtonTemplate"); frame.replayNext:SetWidth(42); frame.replayNext:SetHeight(16); frame.replayNext:SetPoint("LEFT",frame.replayPrev,"RIGHT",4,0); frame.replayNext:SetText("Next"); frame.replayNext:SetScript("OnClick",function() MT:SelectReplayEvent((MT.detailsSelectedEvent or 0)+1) end)
    frame.eventRows={}
    local row=CreateFrame("Button",nil,frame); row:SetWidth(168); row:SetHeight(16); row:SetPoint("BOTTOMRIGHT",frame,"BOTTOMRIGHT",-10,11)
    row.highlight=row:CreateTexture(nil,"BACKGROUND"); row.highlight:SetAllPoints(row); row.highlight:SetTexture(0.25,0.45,0.75,0.45); row.highlight:Hide()
    row.time=row:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall"); row.time:SetPoint("LEFT",row,"LEFT",1,0); row.time:SetWidth(28); row.time:SetJustifyH("LEFT")
    row.source=row:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall"); row.source:SetPoint("LEFT",row,"LEFT",30,0); row.source:SetWidth(58); row.source:SetJustifyH("LEFT")
    row.ability=row:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall"); row.ability:SetPoint("LEFT",row,"LEFT",89,0); row.ability:SetWidth(46); row.ability:SetJustifyH("LEFT")
    row.outcome=row:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall"); row.outcome:SetPoint("RIGHT",row,"RIGHT",-1,0); row.outcome:SetWidth(32); row.outcome:SetJustifyH("RIGHT")
    row:SetScript("OnClick",function() if this.eventIndex then MT:SelectReplayEvent(this.eventIndex) end end); frame.eventRows[1]=row
    frame.eventPrev=CreateFrame("Button",nil,frame,"UIPanelButtonTemplate"); frame.eventPrev:SetWidth(1); frame.eventPrev:SetHeight(1); frame.eventPrev:Hide()
    frame.eventNext=CreateFrame("Button",nil,frame,"UIPanelButtonTemplate"); frame.eventNext:SetWidth(1); frame.eventNext:SetHeight(1); frame.eventNext:Hide()
    frame.eventPageText=frame:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall"); frame.eventPageText:SetPoint("BOTTOMRIGHT",frame,"BOTTOMRIGHT",-10,29)

    self.detailsFrame=frame
    return frame
end

function MT:ToggleDetails()
    local frame=self:CreateDetailsWindow()
    self.detailsFilter=nil; self.detailsSelectedEnemy=nil; self.detailsEnemyPage=1; self.detailsAbilityPage=1; self.detailsEventPage=1
    self:ShowRCPage(frame,function(owner) owner:UpdateDetailsWindow() end)
end

-- BIGGEST PAGE ---------------------------------------------------------------
function MT:CreateBiggestWindow()
    if self.biggestFrame then return self.biggestFrame end
    local frame=RC_CreatePageFrame("MainTankBiggestFrame","Biggest Hits")
    frame.rows={}
    local i
    for i=1,6 do
        local row=CreateFrame("Button",nil,frame); row:SetWidth(272); row:SetHeight(27); row:SetPoint("TOPLEFT",frame,"TOPLEFT",14,-34-(i-1)*29); row:EnableMouse(true)
        row.label=row:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall"); row.label:SetPoint("TOPLEFT",row,"TOPLEFT",2,-1); row.label:SetWidth(150); row.label:SetJustifyH("LEFT")
        row.value=row:CreateFontString(nil,"OVERLAY","GameFontNormal"); row.value:SetPoint("TOPRIGHT",row,"TOPRIGHT",-2,-1); row.value:SetJustifyH("RIGHT")
        row.source=row:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall"); row.source:SetPoint("BOTTOMLEFT",row,"BOTTOMLEFT",2,1); row.source:SetWidth(265); row.source:SetJustifyH("LEFT")
        row:SetScript("OnClick",function() if this.entry and this.entry.event then MT:JumpToEvent(this.entry.event) end end)
        frame.rows[i]=row
    end
    local note=frame:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall"); note:SetPoint("BOTTOM",frame,"BOTTOM",0,8); note:SetText("Click a record to open Details")
    self.biggestFrame=frame
    return frame
end

function MT:ToggleBiggest()
    local frame=self:CreateBiggestWindow()
    self:ShowRCPage(frame,function(owner) owner:UpdateBiggestWindow() end)
end

-- Analysis clicks must stay inside the single-window navigator.
function MT:OpenPieDetails(entry)
    if not entry then return end
    self.detailsFilter={kind=entry.filterKind,value=entry.filterValue,label=entry.label}
    self.detailsSelectedEnemy=nil; self.detailsEnemyPage=1; self.detailsAbilityPage=1; self.detailsEventPage=1
    local frame=self:CreateDetailsWindow()
    self:ShowRCPage(frame,function(owner) owner:UpdateDetailsWindow() end)
end

function MT:OpenTimelineDetails(bucket)
    if not bucket then return end
    self:SelectTimelineBucket(bucket)
    local firstSecond=bucket.firstSecond or 0; local lastSecond=bucket.lastSecond or firstSecond; local mode=self.timelineMode or "RAW"
    local label=(lastSecond>firstSecond) and format("%s %ds-%ds",mode,firstSecond,lastSecond) or format("%s %ds",mode,firstSecond)
    self.detailsFilter={kind="TIMELINE",firstSecond=firstSecond,lastSecond=lastSecond,mode=mode,label=label}
    self.detailsSelectedEnemy=nil; self.detailsEnemyPage=1; self.detailsAbilityPage=1; self.detailsEventPage=1
    local frame=self:CreateDetailsWindow()
    self:ShowRCPage(frame,function(owner) owner:UpdateDetailsWindow() end)
end

-- Slash command-compatible explicit automation setting.
local RC_OldHandleSlash = MT.HandleSlash
function MT:HandleSlash(msg)
    msg=string.lower(msg or "")
    if msg=="automini on" then self.autoMiniInCombat=true; MainTankDB.autoMiniInCombat=true; Print("Automatic combat mini-mode enabled."); return end
    if msg=="automini off" then self.autoMiniInCombat=false; MainTankDB.autoMiniInCombat=false; Print("Automatic combat mini-mode disabled."); return end
    RC_OldHandleSlash(self,msg)
end

-- ============================================================================
-- v1.0.0 RC1c - Final UI polish pass
-- Main restructure, compact Details/Event Inspector, Biggest interaction,
-- and restored one-second Timeline tooltips.
-- ============================================================================

local RC1C_OldCreateUI = MT.CreateUI
function MT:CreateUI()
    RC1C_OldCreateUI(self)
    local frame = self.frame
    if not frame then return end

    local timelineButton = self.fullControls and self.fullControls[1]
    local biggestButton  = self.fullControls and self.fullControls[2]
    local detailsButton  = self.fullControls and self.fullControls[3]
    local pieButton      = self.fullControls and self.fullControls[4]

    -- Give the fight title the whole top line.
    frame.title:ClearAllPoints()
    frame.title:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -8)
    frame.title:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -27, -8)
    frame.title:SetJustifyH("CENTER")

    -- Navigation: two balanced columns below the title.
    if timelineButton then
        timelineButton:ClearAllPoints(); timelineButton:SetWidth(68); timelineButton:SetHeight(18)
        timelineButton:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -28)
    end
    if biggestButton then
        biggestButton:ClearAllPoints(); biggestButton:SetWidth(68); biggestButton:SetHeight(18)
        biggestButton:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -49)
    end
    if detailsButton then
        detailsButton:ClearAllPoints(); detailsButton:SetWidth(68); detailsButton:SetHeight(18)
        detailsButton:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -8, -49)
    end
    if pieButton then
        pieButton:ClearAllPoints(); pieButton:SetWidth(68); pieButton:SetHeight(18)
        pieButton:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -8, -28)
        pieButton:SetText("Pie Chart")
    end

    -- Subtitle belongs beneath the navigation, not beneath the title.
    if frame.subtitle then
        frame.subtitle:ClearAllPoints()
        frame.subtitle:SetPoint("TOP", frame, "TOP", 0, -70)
        frame.subtitle:SetWidth(276)
    end

    -- Re-center view and category controls below the navigation.
    if self.viewButtons then
        local current = self.viewButtons.CURRENT
        local overall = self.viewButtons.OVERALL
        if current then current:ClearAllPoints(); current:SetWidth(88); current:SetPoint("TOPLEFT", frame, "TOPLEFT", 57, -84) end
        if overall then overall:ClearAllPoints(); overall:SetWidth(88); overall:SetPoint("LEFT", current, "RIGHT", 10, 0) end
    end
    if self.pageButtons then
        local raw = self.pageButtons.RAW
        local physical = self.pageButtons.PHYSICAL
        local magic = self.pageButtons.MAGIC
        if raw then raw:ClearAllPoints(); raw:SetWidth(84); raw:SetPoint("TOPLEFT", frame, "TOPLEFT", 18, -108) end
        if physical then physical:ClearAllPoints(); physical:SetWidth(84); physical:SetPoint("LEFT", raw, "RIGHT", 6, 0) end
        if magic then magic:ClearAllPoints(); magic:SetWidth(84); magic:SetPoint("LEFT", physical, "RIGHT", 6, 0) end
    end

    -- Move the eight summary rows down to make room for the new header.
    if self.rows then
        local i
        for i = 1, 8 do
            local row = self.rows[i]
            if row and row.label and row.value then
                row.label:ClearAllPoints(); row.label:SetPoint("TOPLEFT", frame, "TOPLEFT", 17, -135 - ((i-1)*12))
                row.value:ClearAllPoints(); row.value:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -17, -135 - ((i-1)*12))
                if row.hit then
                    row.hit:ClearAllPoints(); row.hit:SetPoint("RIGHT", row.value, "LEFT", -3, 0)
                end
            end
        end
    end

    -- Minimize lives alone in the bottom-right corner.
    if frame.shrinkButton then
        frame.shrinkButton:ClearAllPoints()
        frame.shrinkButton:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -6, 6)
        frame.shrinkButton:SetWidth(22); frame.shrinkButton:SetHeight(18)
    end
end

local RC1C_OldSetMiniMode = MT.SetMiniMode
function MT:SetMiniMode(enabled, automatic)
    RC1C_OldSetMiniMode(self, enabled, automatic)
    if not self.frame or not self.frame.shrinkButton then return end
    self.frame.shrinkButton:ClearAllPoints()
    self.frame.shrinkButton:SetPoint("BOTTOMRIGHT", self.frame, "BOTTOMRIGHT", -6, 6)
end

-- Correct the RC Timeline callback to match ShowTimelineTooltip(owner, second, bucket).
local RC1C_OldCreateTimelineWindow = MT.CreateTimelineWindow
function MT:CreateTimelineWindow()
    local frame = RC1C_OldCreateTimelineWindow(self)
    if frame and frame.bars and not frame.rc1cTooltipFixed then
        local i
        for i = 1, table.getn(frame.bars) do
            local bar = frame.bars[i]
            bar:SetScript("OnEnter", function()
                if this.bucket then MT:ShowTimelineTooltip(this, this.second, this.bucket) end
            end)
            bar:SetScript("OnLeave", function() MT:HideAnalysisTooltip() end)
        end
        frame.rc1cTooltipFixed = true
    end
    return frame
end

-- Biggest is now self-contained: hover highlight + compact inspector.
function MT:CreateBiggestWindow()
    if self.biggestFrame then return self.biggestFrame end
    local frame = RC_CreatePageFrame("MainTankBiggestFrame", "Biggest Hits")
    frame.rows = {}
    local i
    for i = 1, 7 do
        local row = CreateFrame("Button", nil, frame)
        row:SetWidth(272); row:SetHeight(21)
        row:SetPoint("TOPLEFT", frame, "TOPLEFT", 14, -32 - ((i-1)*22))
        row:EnableMouse(true)
        row.highlight = row:CreateTexture(nil, "BACKGROUND")
        row.highlight:SetAllPoints(row); row.highlight:SetTexture(0.65,0.48,0.12,0.22); row.highlight:Hide()
        row.selected = row:CreateTexture(nil, "BACKGROUND")
        row.selected:SetAllPoints(row); row.selected:SetTexture(0.45,0.18,0.08,0.48); row.selected:Hide()
        row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.label:SetPoint("TOPLEFT", row, "TOPLEFT", 3, -1); row.label:SetWidth(155); row.label:SetJustifyH("LEFT")
        row.value = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        row.value:SetPoint("TOPRIGHT", row, "TOPRIGHT", -3, -1); row.value:SetJustifyH("RIGHT")
        row.source = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.source:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 3, 1); row.source:SetWidth(260); row.source:SetJustifyH("LEFT")
        row:SetScript("OnEnter", function() if this.entry then this.highlight:Show() end end)
        row:SetScript("OnLeave", function() this.highlight:Hide() end)
        row:SetScript("OnClick", function() if this.entry and this.entry.event then MT:JumpToEvent(this.entry.event) end end)
        frame.rows[i] = row
    end
    frame.inspectorHeader = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    frame.inspectorHeader:SetPoint("TOPLEFT", frame, "TOPLEFT", 14, -167)
    frame.inspectorHeader:SetText("Event Inspector")
    frame.inspector = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.inspector:SetPoint("TOPLEFT", frame, "TOPLEFT", 14, -181)
    frame.inspector:SetWidth(272); frame.inspector:SetHeight(40)
    frame.inspector:SetJustifyH("LEFT"); frame.inspector:SetJustifyV("TOP")
    frame.inspector:SetText("Select a Biggest Hits record to inspect it here.")
    self.biggestFrame = frame
    return frame
end

local RC1C_OldUpdateBiggestWindow = MT.UpdateBiggestWindow
function MT:UpdateBiggestWindow()
    RC1C_OldUpdateBiggestWindow(self)
    local frame = self.biggestFrame
    if not frame then return end
    local i
    for i = 1, table.getn(frame.rows or {}) do
        local row = frame.rows[i]
        if row.selected then
            if self.biggestSelectedEvent and row.entry and row.entry.event == self.biggestSelectedEvent then row.selected:Show() else row.selected:Hide() end
        end
    end
    if frame.inspector then
        if self.biggestSelectedEvent then frame.inspector:SetText(self:FormatEventInspector(self.biggestSelectedEvent))
        else frame.inspector:SetText("Select a Biggest Hits record to inspect it here.") end
    end
end

-- Clicking Biggest updates the page-local inspector; it opens no other frame.
function MT:JumpToEvent(event)
    if not event then return end
    self.biggestSelectedEvent = event
    local second = floor(event.time or 0)
    self.timelineSelection = {firstSecond=second, lastSecond=second, mode=self.timelineMode or "RAW"}
    self.detailsFilter = nil
    self.detailsSelectedEnemy = event.source or "Unknown"
    local sourceEvents = self:GetDisplayEvents() or {}
    local filteredIndex = 0
    local i
    self.detailsSelectedEvent = nil
    for i = 1, table.getn(sourceEvents) do
        local candidate = sourceEvents[i]
        if (candidate.source or "Unknown") == self.detailsSelectedEnemy then
            filteredIndex = filteredIndex + 1
            if candidate == event then self.detailsSelectedEvent = filteredIndex; break end
        end
    end
    self:UpdateBiggestWindow()
end

-- Compact vertical Details page designed for the 300x231 single-window frame.
function MT:CreateDetailsWindow()
    if self.detailsFrame then return self.detailsFrame end
    local frame = RC_CreatePageFrame("MainTankDetailsFrame", "Mitigation Details")
    frame.clearFilter = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.clearFilter:SetWidth(36); frame.clearFilter:SetHeight(16)
    frame.clearFilter:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -27, -28)
    frame.clearFilter:SetText("All"); frame.clearFilter:SetScript("OnClick", function() MT:ClearDetailsFilter() end); frame.clearFilter:Hide()

    local enemiesHeader = frame:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    enemiesHeader:SetPoint("TOPLEFT",frame,"TOPLEFT",10,-31); enemiesHeader:SetText("Enemies")
    frame.enemyRows = {}
    local i
    for i = 1, 2 do
        local row = CreateFrame("Button",nil,frame)
        row:SetWidth(278); row:SetHeight(15); row:SetPoint("TOPLEFT",frame,"TOPLEFT",10,-44-(i-1)*16)
        row.highlight=row:CreateTexture(nil,"BACKGROUND"); row.highlight:SetAllPoints(row); row.highlight:SetTexture(0.35,0.12,0.12,0.65); row.highlight:Hide()
        row.name=row:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall"); row.name:SetPoint("LEFT",row,"LEFT",2,0); row.name:SetWidth(170); row.name:SetJustifyH("LEFT")
        row.value=row:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall"); row.value:SetPoint("RIGHT",row,"RIGHT",-2,0); row.value:SetJustifyH("RIGHT")
        row:SetScript("OnClick",function() if this.data then MT.detailsSelectedEnemy=this.data.name; MT.detailsAbilityPage=1; MT.detailsSelectedEvent=nil; MT:UpdateDetailsWindow() end end)
        row:SetScript("OnEnter",function() if this.data then MT:ShowDetailTooltip(this,this.data,"Enemy totals") end end)
        row:SetScript("OnLeave",function() MT:HideAnalysisTooltip() end)
        frame.enemyRows[i]=row
    end
    frame.enemyPrev=CreateFrame("Button",nil,frame,"UIPanelButtonTemplate"); frame.enemyPrev:SetWidth(24); frame.enemyPrev:SetHeight(14); frame.enemyPrev:SetPoint("TOPLEFT",frame,"TOPLEFT",10,-77); frame.enemyPrev:SetText("<"); frame.enemyPrev:SetScript("OnClick",function() MT.detailsEnemyPage=MT.detailsEnemyPage-1; MT:UpdateDetailsWindow() end)
    frame.enemyNext=CreateFrame("Button",nil,frame,"UIPanelButtonTemplate"); frame.enemyNext:SetWidth(24); frame.enemyNext:SetHeight(14); frame.enemyNext:SetPoint("TOPRIGHT",frame,"TOPRIGHT",-10,-77); frame.enemyNext:SetText(">"); frame.enemyNext:SetScript("OnClick",function() MT.detailsEnemyPage=MT.detailsEnemyPage+1; MT:UpdateDetailsWindow() end)
    frame.enemyPageText=frame:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall"); frame.enemyPageText:SetPoint("TOP",frame,"TOP",0,-79)

    frame.selectedName=frame:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    frame.selectedName:SetPoint("TOPLEFT",frame,"TOPLEFT",10,-94); frame.selectedName:SetWidth(278); frame.selectedName:SetJustifyH("LEFT")
    frame.summary=frame:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    frame.summary:SetPoint("TOPLEFT",frame,"TOPLEFT",10,-107); frame.summary:SetWidth(278); frame.summary:SetJustifyH("LEFT")

    local abilityHeader=frame:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    abilityHeader:SetPoint("TOPLEFT",frame,"TOPLEFT",10,-123); abilityHeader:SetText("Abilities")
    frame.abilityRows={}
    for i=1,2 do
        local row=CreateFrame("Frame",nil,frame); row:SetWidth(278); row:SetHeight(15); row:SetPoint("TOPLEFT",frame,"TOPLEFT",10,-136-(i-1)*16); row:EnableMouse(true)
        row.name=row:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall"); row.name:SetPoint("LEFT",row,"LEFT",2,0); row.name:SetWidth(125); row.name:SetJustifyH("LEFT")
        row.school=row:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall"); row.school:SetPoint("LEFT",row,"LEFT",128,0); row.school:SetWidth(60); row.school:SetJustifyH("LEFT")
        row.raw=row:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall"); row.raw:SetPoint("RIGHT",row,"RIGHT",-45,0); row.raw:SetWidth(42); row.raw:SetJustifyH("RIGHT")
        row.taken=row:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall"); row.taken:SetPoint("RIGHT",row,"RIGHT",-2,0); row.taken:SetWidth(40); row.taken:SetJustifyH("RIGHT")
        row:SetScript("OnEnter",function() if this.data then MT:ShowDetailTooltip(this,this.data,"Ability details") end end)
        row:SetScript("OnLeave",function() MT:HideAnalysisTooltip() end)
        frame.abilityRows[i]=row
    end
    frame.abilityPrev=CreateFrame("Button",nil,frame,"UIPanelButtonTemplate"); frame.abilityPrev:SetWidth(22); frame.abilityPrev:SetHeight(14); frame.abilityPrev:SetPoint("TOPLEFT",frame,"TOPLEFT",10,-169); frame.abilityPrev:SetText("<"); frame.abilityPrev:SetScript("OnClick",function() MT.detailsAbilityPage=MT.detailsAbilityPage-1; MT:UpdateDetailsWindow() end)
    frame.abilityNext=CreateFrame("Button",nil,frame,"UIPanelButtonTemplate"); frame.abilityNext:SetWidth(22); frame.abilityNext:SetHeight(14); frame.abilityNext:SetPoint("TOPRIGHT",frame,"TOPRIGHT",-10,-169); frame.abilityNext:SetText(">"); frame.abilityNext:SetScript("OnClick",function() MT.detailsAbilityPage=MT.detailsAbilityPage+1; MT:UpdateDetailsWindow() end)
    frame.abilityPageText=frame:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall"); frame.abilityPageText:SetPoint("TOP",frame,"TOP",0,-171)

    frame.replayCount=frame:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall"); frame.replayCount:SetPoint("TOPRIGHT",frame,"TOPRIGHT",-10,-187)
    local inspectorHeader=frame:CreateFontString(nil,"OVERLAY","GameFontNormalSmall"); inspectorHeader:SetPoint("TOPLEFT",frame,"TOPLEFT",10,-187); inspectorHeader:SetText("Event Inspector")
    frame.replayText=frame:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    frame.replayText:SetPoint("TOPLEFT",frame,"TOPLEFT",10,-199); frame.replayText:SetWidth(278); frame.replayText:SetHeight(27); frame.replayText:SetJustifyH("LEFT"); frame.replayText:SetJustifyV("TOP")
    frame.replayPrev=CreateFrame("Button",nil,frame,"UIPanelButtonTemplate"); frame.replayPrev:SetWidth(48); frame.replayPrev:SetHeight(14); frame.replayPrev:SetPoint("BOTTOMLEFT",frame,"BOTTOMLEFT",10,7); frame.replayPrev:SetText("Previous"); frame.replayPrev:SetScript("OnClick",function() MT:SelectReplayEvent((MT.detailsSelectedEvent or 1)-1) end)
    frame.replayNext=CreateFrame("Button",nil,frame,"UIPanelButtonTemplate"); frame.replayNext:SetWidth(38); frame.replayNext:SetHeight(14); frame.replayNext:SetPoint("LEFT",frame.replayPrev,"RIGHT",4,0); frame.replayNext:SetText("Next"); frame.replayNext:SetScript("OnClick",function() MT:SelectReplayEvent((MT.detailsSelectedEvent or 0)+1) end)

    -- Hidden compatibility row: preserves existing event pagination logic while
    -- navigation is handled by Previous/Next in this compact layout.
    frame.eventRows={}
    local row=CreateFrame("Button",nil,frame); row:SetWidth(1); row:SetHeight(1); row:SetPoint("BOTTOMRIGHT",frame,"BOTTOMRIGHT",-1,1); row:Hide()
    row.highlight=row:CreateTexture(nil,"BACKGROUND"); row.highlight:SetAllPoints(row); row.highlight:Hide()
    row.time=row:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    row.source=row:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    row.ability=row:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    row.outcome=row:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    row:SetScript("OnClick",function() if this.eventIndex then MT:SelectReplayEvent(this.eventIndex) end end)
    frame.eventRows[1]=row
    frame.eventPrev=CreateFrame("Button",nil,frame,"UIPanelButtonTemplate"); frame.eventPrev:SetWidth(1); frame.eventPrev:SetHeight(1); frame.eventPrev:Hide()
    frame.eventNext=CreateFrame("Button",nil,frame,"UIPanelButtonTemplate"); frame.eventNext:SetWidth(1); frame.eventNext:SetHeight(1); frame.eventNext:Hide()
    frame.eventPageText=frame:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall"); frame.eventPageText:Hide()

    self.detailsFrame=frame
    return frame
end


-- ============================================================================
-- v1.0.0 RC1d - safe page anchors + bottom-right mini behavior
-- ============================================================================

local function RC1D_GetBottomRight(frame)
    if not frame then return nil, nil end
    local right = frame:GetRight()
    local bottom = frame:GetBottom()
    if right and bottom then return right, bottom end
    if MainTankDB and MainTankDB.position then
        local p = MainTankDB.position
        if p.point == "BOTTOMRIGHT" and p.relativePoint == "BOTTOMLEFT" then
            return p.x or 0, p.y or 0
        end
    end
    return nil, nil
end

local function RC1D_AnchorBottomRight(frame, right, bottom)
    if not frame then return end
    if not right or not bottom then
        frame:ClearAllPoints()
        frame:SetPoint("CENTER", UIParent, "CENTER", 320, 0)
        return
    end
    frame:ClearAllPoints()
    frame:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMLEFT", right, bottom)
end

local function RC1D_SaveMainPosition(right, bottom)
    if not MainTankDB or not right or not bottom then return end
    MainTankDB.position = {
        point = "BOTTOMRIGHT",
        relativePoint = "BOTTOMLEFT",
        x = right,
        y = bottom
    }
end

-- Replace the RC page transition with a UIParent-relative anchor. This avoids
-- every possible self-anchor chain from older popup frames and migrated saves.
function MT:ShowRCPage(frame, updater)
    if not frame then return end
    local right, bottom = RC1D_GetBottomRight(self.frame)
    self.activeRCPage = frame
    RC_HideAnalysisPages(frame)
    if self.frame then self.frame:Hide() end
    RC1D_AnchorBottomRight(frame, right, bottom)
    frame:SetWidth(RC_PAGE_WIDTH)
    frame:SetHeight(RC_PAGE_HEIGHT)
    frame:Show()
    if updater then updater(self) end
    RC_HideAnalysisPages(frame)
    if self.frame then self.frame:Hide() end

    if not frame.rc1dDragFixed then
        frame:SetScript("OnDragStart", function() this:StartMoving() end)
        frame:SetScript("OnDragStop", function()
            this:StopMovingOrSizing()
            local newRight, newBottom = RC1D_GetBottomRight(this)
            RC1D_AnchorBottomRight(this, newRight, newBottom)
            if MT.frame then RC1D_AnchorBottomRight(MT.frame, newRight, newBottom) end
            RC1D_SaveMainPosition(newRight, newBottom)
        end)
        frame.rc1dDragFixed = true
    end
end

-- Keep MT Main on the same bottom-right corner as the analysis page.
local RC1D_OldReturnToMain = MT.ReturnToMain
function MT:ReturnToMain()
    local source = self.activeRCPage
    local right, bottom = RC1D_GetBottomRight(source or self.frame)
    RC1D_OldReturnToMain(self)
    if self.frame then
        RC1D_AnchorBottomRight(self.frame, right, bottom)
        RC1D_SaveMainPosition(right, bottom)
    end
    if self.frame and self.frame.shrinkButton then
        self.frame.shrinkButton:ClearAllPoints()
        self.frame.shrinkButton:SetPoint("BOTTOMRIGHT", self.frame, "BOTTOMRIGHT", -2, 2)
        self.frame.shrinkButton:SetWidth(14)
        self.frame.shrinkButton:SetHeight(13)
    end
end

-- Preserve the frame's bottom-right corner while shrinking or expanding. The
-- upper-left corner moves, so mini mode collapses toward the button itself.
local RC1D_OldSetMiniMode = MT.SetMiniMode
function MT:SetMiniMode(enabled, automatic)
    local right, bottom = RC1D_GetBottomRight(self.frame)
    RC1D_OldSetMiniMode(self, enabled, automatic)
    if self.frame then
        RC1D_AnchorBottomRight(self.frame, right, bottom)
        RC1D_SaveMainPosition(right, bottom)
    end
    if self.frame and self.frame.shrinkButton then
        self.frame.shrinkButton:ClearAllPoints()
        self.frame.shrinkButton:SetPoint("BOTTOMRIGHT", self.frame, "BOTTOMRIGHT", -2, 2)
        self.frame.shrinkButton:SetWidth(14)
        self.frame.shrinkButton:SetHeight(13)
    end
end

-- Final main-layout adjustment: reserve a little more space above the tiny
-- bottom-right minimize control so it cannot cover RAW/Physical/Magic values.
local RC1D_OldCreateUI = MT.CreateUI
function MT:CreateUI()
    RC1D_OldCreateUI(self)
    local frame = self.frame
    if not frame then return end

    if frame.shrinkButton then
        frame.shrinkButton:ClearAllPoints()
        frame.shrinkButton:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -2, 2)
        frame.shrinkButton:SetWidth(14)
        frame.shrinkButton:SetHeight(13)
    end

    -- Slightly tighten the summary rows, leaving a clean footer for minimize.
    if self.rows then
        local i
        for i = 1, 8 do
            local row = self.rows[i]
            if row and row.label and row.value then
                local y = -133 - ((i - 1) * 11)
                row.label:ClearAllPoints()
                row.label:SetPoint("TOPLEFT", frame, "TOPLEFT", 17, y)
                row.value:ClearAllPoints()
                row.value:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -17, y)
                if row.hit then
                    row.hit:ClearAllPoints()
                    row.hit:SetPoint("RIGHT", row.value, "LEFT", -3, 0)
                end
            end
        end
    end
end

-- ============================================================================
-- v1.0.0 RC1f - authoritative page manager
-- All navigation is routed through one controller. Inactive legacy/RC frames
-- are guarded against reopening themselves during refresh callbacks.
-- ============================================================================

MT.managedPages = MT.managedPages or {}
MT.currentManagedPage = MT.currentManagedPage or "MAIN"

local function RC1E_PageNameForFrame(frame)
    if not frame then return nil end
    local name = frame:GetName()
    if frame == MT.frame or name == "MainTankFrame" then return "MAIN" end
    if frame == MT.timelineFrame or name == "MainTankTimelineFrame" then return "TIMELINE" end
    if frame == MT.pieFrame or name == "MainTankPieFrame" then return "PIE" end
    if frame == MT.detailsFrame or name == "MainTankDetailsFrame" then return "DETAILS" end
    if frame == MT.biggestFrame or name == "MainTankBiggestFrame" then return "BIGGEST" end
    return nil
end

function MT:RegisterManagedPage(name, frame)
    if not name or not frame then return end
    self.managedPages[name] = frame
    frame.mtManagedPageName = name

    if not frame.mtPageGuardInstalled then
        local oldOnShow = frame:GetScript("OnShow")
        frame:SetScript("OnShow", function()
            local pageFrame = this
            local pageName = pageFrame.mtManagedPageName
            if pageName and MT.currentManagedPage ~= pageName then
                pageFrame:Hide()
                return
            end
            if oldOnShow then oldOnShow() end
        end)
        frame.mtPageGuardInstalled = true
    end
end

function MT:RefreshManagedPageRegistry()
    if self.frame then self:RegisterManagedPage("MAIN", self.frame) end
    local timeline = self.timelineFrame or getglobal("MainTankTimelineFrame")
    local pie = self.pieFrame or getglobal("MainTankPieFrame")
    local details = self.detailsFrame or getglobal("MainTankDetailsFrame")
    local biggest = self.biggestFrame or getglobal("MainTankBiggestFrame")
    if timeline then self:RegisterManagedPage("TIMELINE", timeline) end
    if pie then self:RegisterManagedPage("PIE", pie) end
    if details then self:RegisterManagedPage("DETAILS", details) end
    if biggest then self:RegisterManagedPage("BIGGEST", biggest) end
end

function MT:HideAllManagedPages(exceptName)
    self:RefreshManagedPageRegistry()
    local name, frame
    for name, frame in pairs(self.managedPages) do
        if frame and name ~= exceptName then frame:Hide() end
    end

    -- Defensive cleanup for stale named frames that may not be current refs.
    local legacyNames = {
        "MainTankTimelineFrame",
        "MainTankPieFrame",
        "MainTankDetailsFrame",
        "MainTankBiggestFrame"
    }
    local i, legacy
    for i = 1, table.getn(legacyNames) do
        legacy = getglobal(legacyNames[i])
        if legacy and RC1E_PageNameForFrame(legacy) ~= exceptName then legacy:Hide() end
    end
    self:HideAnalysisTooltip()
end

function MT:ShowManagedPage(name, updater)
    if not name then name = "MAIN" end
    self:RefreshManagedPageRegistry()

    local target = self.managedPages[name]
    if name ~= "MAIN" and not target then return end

    local source = self.managedPages[self.currentManagedPage]
    local right, bottom = RC1D_GetBottomRight(source or self.frame)

    -- Set state before showing anything so OnShow guards know the destination.
    self.currentManagedPage = name
    self.activeRCPage = (name ~= "MAIN") and target or nil
    self:HideAllManagedPages(name)

    if name == "MAIN" then
        target = self.frame
        if not target then return end
        target:SetWidth(RC_PAGE_WIDTH)
        target:SetHeight(RC_PAGE_HEIGHT)
        self.miniMode = false
        if MainTankDB then MainTankDB.miniMode = false end

        local i
        if self.fullControls then
            for i = 1, table.getn(self.fullControls) do self.fullControls[i]:Show() end
        end
        if target.subtitle then target.subtitle:Show() end
        if target.miniRows then
            for i = 1, 4 do
                target.miniRows[i].label:Hide()
                target.miniRows[i].value:Hide()
            end
        end
        if target.shrinkButton then
            target.shrinkButton:SetText("-")
            target.shrinkButton:ClearAllPoints()
            target.shrinkButton:SetPoint("BOTTOMRIGHT", target, "BOTTOMRIGHT", -2, 2)
            target.shrinkButton:SetWidth(14)
            target.shrinkButton:SetHeight(13)
        end

        RC1D_AnchorBottomRight(target, right, bottom)
        target:Show()
        self:SetPage(self.currentPage or "RAW")
        self:UpdateDisplay()
    else
        if self.frame then self.frame:Hide() end
        RC1D_AnchorBottomRight(target, right, bottom)
        target:SetWidth(RC_PAGE_WIDTH)
        target:SetHeight(RC_PAGE_HEIGHT)
        target:Show()
        if updater then updater(self) end
    end

    -- A second pass catches old refresh functions that try to show a popup.
    self:HideAllManagedPages(name)
    if target and not target:IsVisible() then target:Show() end
    RC1D_SaveMainPosition(right, bottom)
end

-- Existing page buttons route here through ShowRCPage.
function MT:ShowRCPage(frame, updater)
    if not frame then return end
    local name = RC1E_PageNameForFrame(frame)
    if not name then return end
    self:RegisterManagedPage(name, frame)
    self:ShowManagedPage(name, updater)
end

function MT:ReturnToMain()
    self:ShowManagedPage("MAIN")
end

-- Register lazily-created frames immediately and ensure their MT Main buttons
-- always use the manager instead of any earlier transition closure.
local RC1E_OldCreatePageFrame = RC_CreatePageFrame
RC_CreatePageFrame = function(name, title)
    local frame = RC1E_OldCreatePageFrame(name, title)
    local pageName = RC1E_PageNameForFrame(frame)
    if pageName then MT:RegisterManagedPage(pageName, frame) end
    if frame.mainButton then
        frame.mainButton:SetScript("OnClick", function() MT:ShowManagedPage("MAIN") end)
    StyleLegacyButton(frame.mainButton)
    end
    return frame
end

-- Periodic low-cost safety check. Some migrated builds retain old OnUpdate or
-- refresh paths; this makes overlap impossible even if one fires later.
if not MT.pageManagerGuard then
    MT.pageManagerGuard = CreateFrame("Frame", nil, UIParent)
    MT.pageManagerGuard.elapsed = 0
    MT.pageManagerGuard:SetScript("OnUpdate", function()
        this.elapsed = (this.elapsed or 0) + arg1
        if this.elapsed < 0.20 then return end
        this.elapsed = 0
        MT:RefreshManagedPageRegistry()
        local active = MT.currentManagedPage or "MAIN"
        local name, frame
        for name, frame in pairs(MT.managedPages) do
            if frame and name ~= active and frame:IsVisible() then frame:Hide() end
        end
    end)
end

-- Register the main page after UI creation and default to MAIN on fresh load.
local RC1E_OldCreateUI = MT.CreateUI
function MT:CreateUI()
    RC1E_OldCreateUI(self)
    if self.frame then self:RegisterManagedPage("MAIN", self.frame) end
    if not self.currentManagedPage then self.currentManagedPage = "MAIN" end
end

-- ============================================================================
-- v1.0.0 RC1f - Details / Event Inspector interaction polish
-- ============================================================================

-- Rebuild the compact Details page with real, clickable event rows. The RC1c
-- compatibility row was intentionally hidden, which made the event count valid
-- while leaving no event available to select. RC1f restores an actual list.
function MT:CreateDetailsWindow()
    if self.detailsFrame then return self.detailsFrame end

    local frame = RC_CreatePageFrame("MainTankDetailsFrame", "Mitigation Details")

    frame.clearFilter = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.clearFilter:SetWidth(28); frame.clearFilter:SetHeight(14)
    frame.clearFilter:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -25, -27)
    frame.clearFilter:SetText("All")
    frame.clearFilter:SetScript("OnClick", function() MT:ClearDetailsFilter() end)
    frame.clearFilter:Hide()

    local enemiesHeader = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    enemiesHeader:SetPoint("TOPLEFT", frame, "TOPLEFT", 9, -29)
    enemiesHeader:SetText("Enemies")

    frame.enemyRows = {}
    local i
    for i = 1, 2 do
        local row = CreateFrame("Button", nil, frame)
        row:SetWidth(282); row:SetHeight(13)
        row:SetPoint("TOPLEFT", frame, "TOPLEFT", 9, -41 - (i - 1) * 14)
        row.highlight = row:CreateTexture(nil, "BACKGROUND")
        row.highlight:SetAllPoints(row)
        row.highlight:SetTexture(0.35, 0.12, 0.12, 0.70)
        row.highlight:Hide()
        row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.name:SetPoint("LEFT", row, "LEFT", 2, 0)
        row.name:SetWidth(175); row.name:SetJustifyH("LEFT")
        row.value = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.value:SetPoint("RIGHT", row, "RIGHT", -2, 0)
        row.value:SetWidth(98); row.value:SetJustifyH("RIGHT")
        row:SetScript("OnClick", function()
            if this.data then
                MT.detailsSelectedEnemy = this.data.name
                MT.detailsAbilityPage = 1
                MT.detailsEventPage = 1
                MT.detailsSelectedEvent = nil
                MT:UpdateDetailsWindow()
            end
        end)
        row:SetScript("OnEnter", function()
            if this.data then MT:ShowDetailTooltip(this, this.data, "Enemy totals") end
        end)
        row:SetScript("OnLeave", function() MT:HideAnalysisTooltip() end)
        frame.enemyRows[i] = row
    end

    frame.enemyPrev = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.enemyPrev:SetWidth(21); frame.enemyPrev:SetHeight(12)
    frame.enemyPrev:SetPoint("TOPLEFT", frame, "TOPLEFT", 9, -70)
    frame.enemyPrev:SetText("<")
    frame.enemyPrev:SetScript("OnClick", function() MT.detailsEnemyPage = MT.detailsEnemyPage - 1; MT:UpdateDetailsWindow() end)
    frame.enemyNext = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.enemyNext:SetWidth(21); frame.enemyNext:SetHeight(12)
    frame.enemyNext:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -9, -70)
    frame.enemyNext:SetText(">")
    frame.enemyNext:SetScript("OnClick", function() MT.detailsEnemyPage = MT.detailsEnemyPage + 1; MT:UpdateDetailsWindow() end)
    frame.enemyPageText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.enemyPageText:SetPoint("TOP", frame, "TOP", 0, -71)

    frame.selectedName = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    frame.selectedName:SetPoint("TOPLEFT", frame, "TOPLEFT", 9, -84)
    frame.selectedName:SetWidth(282); frame.selectedName:SetJustifyH("LEFT")
    frame.summary = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.summary:SetPoint("TOPLEFT", frame, "TOPLEFT", 9, -96)
    frame.summary:SetWidth(282); frame.summary:SetJustifyH("LEFT")

    local abilityHeader = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    abilityHeader:SetPoint("TOPLEFT", frame, "TOPLEFT", 9, -109)
    abilityHeader:SetText("Abilities")
    frame.abilityRows = {}
    for i = 1, 2 do
        local row = CreateFrame("Frame", nil, frame)
        row:SetWidth(282); row:SetHeight(13)
        row:SetPoint("TOPLEFT", frame, "TOPLEFT", 9, -121 - (i - 1) * 14)
        row:EnableMouse(true)
        row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.name:SetPoint("LEFT", row, "LEFT", 2, 0)
        row.name:SetWidth(132); row.name:SetJustifyH("LEFT")
        row.school = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.school:SetPoint("LEFT", row, "LEFT", 135, 0)
        row.school:SetWidth(55); row.school:SetJustifyH("LEFT")
        row.raw = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.raw:SetPoint("RIGHT", row, "RIGHT", -43, 0)
        row.raw:SetWidth(42); row.raw:SetJustifyH("RIGHT")
        row.taken = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.taken:SetPoint("RIGHT", row, "RIGHT", -2, 0)
        row.taken:SetWidth(39); row.taken:SetJustifyH("RIGHT")
        row:SetScript("OnEnter", function()
            if this.data then MT:ShowDetailTooltip(this, this.data, "Ability details") end
        end)
        row:SetScript("OnLeave", function() MT:HideAnalysisTooltip() end)
        frame.abilityRows[i] = row
    end

    frame.abilityPrev = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.abilityPrev:SetWidth(21); frame.abilityPrev:SetHeight(12)
    frame.abilityPrev:SetPoint("TOPLEFT", frame, "TOPLEFT", 9, -150)
    frame.abilityPrev:SetText("<")
    frame.abilityPrev:SetScript("OnClick", function() MT.detailsAbilityPage = MT.detailsAbilityPage - 1; MT:UpdateDetailsWindow() end)
    frame.abilityNext = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.abilityNext:SetWidth(21); frame.abilityNext:SetHeight(12)
    frame.abilityNext:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -9, -150)
    frame.abilityNext:SetText(">")
    frame.abilityNext:SetScript("OnClick", function() MT.detailsAbilityPage = MT.detailsAbilityPage + 1; MT:UpdateDetailsWindow() end)
    frame.abilityPageText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.abilityPageText:SetPoint("TOP", frame, "TOP", 0, -151)

    local eventsHeader = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    eventsHeader:SetPoint("TOPLEFT", frame, "TOPLEFT", 9, -164)
    eventsHeader:SetText("Events")
    frame.replayCount = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.replayCount:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -9, -164)

    frame.eventRows = {}
    for i = 1, 2 do
        local row = CreateFrame("Button", nil, frame)
        row:SetWidth(282); row:SetHeight(13)
        row:SetPoint("TOPLEFT", frame, "TOPLEFT", 9, -176 - (i - 1) * 14)
        row.highlight = row:CreateTexture(nil, "BACKGROUND")
        row.highlight:SetAllPoints(row)
        row.highlight:SetTexture(0.20, 0.30, 0.45, 0.70)
        row.highlight:Hide()
        row.time = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.time:SetPoint("LEFT", row, "LEFT", 2, 0)
        row.time:SetWidth(38); row.time:SetJustifyH("LEFT")
        row.source = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.source:SetPoint("LEFT", row, "LEFT", 41, 0)
        row.source:SetWidth(82); row.source:SetJustifyH("LEFT")
        row.ability = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.ability:SetPoint("LEFT", row, "LEFT", 126, 0)
        row.ability:SetWidth(78); row.ability:SetJustifyH("LEFT")
        row.outcome = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.outcome:SetPoint("RIGHT", row, "RIGHT", -2, 0)
        row.outcome:SetWidth(74); row.outcome:SetJustifyH("RIGHT")
        row:SetScript("OnClick", function()
            if this.eventIndex then MT:SelectReplayEvent(this.eventIndex) end
        end)
        row:SetScript("OnEnter", function()
            if this.data then
                this.highlight:Show()
                local tip = MT:GetAnalysisTooltip()
                tip:SetOwner(this, "ANCHOR_LEFT")
                tip:SetText(MT:FormatEventInspector(this.data), 1, 0.82, 0, 1, true)
                tip:Show()
            end
        end)
        row:SetScript("OnLeave", function()
            if not (this.eventIndex and MT.detailsSelectedEvent == this.eventIndex) then this.highlight:Hide() end
            MT:HideAnalysisTooltip()
        end)
        frame.eventRows[i] = row
    end

    frame.eventPrev = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.eventPrev:SetWidth(20); frame.eventPrev:SetHeight(12)
    frame.eventPrev:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 9, 5)
    frame.eventPrev:SetText("<")
    frame.eventPrev:SetScript("OnClick", function() MT.detailsEventPage = MT.detailsEventPage - 1; MT:UpdateDetailsWindow() end)
    frame.eventNext = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.eventNext:SetWidth(20); frame.eventNext:SetHeight(12)
    frame.eventNext:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -9, 5)
    frame.eventNext:SetText(">")
    frame.eventNext:SetScript("OnClick", function() MT.detailsEventPage = MT.detailsEventPage + 1; MT:UpdateDetailsWindow() end)
    frame.eventPageText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.eventPageText:SetPoint("BOTTOM", frame, "BOTTOM", 0, 7)

    -- The compact selected-event readout stays above the pager. Full details are
    -- also available immediately by hovering either visible event row.
    frame.replayText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.replayText:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 34, 19)
    frame.replayText:SetWidth(232); frame.replayText:SetHeight(17)
    frame.replayText:SetJustifyH("CENTER"); frame.replayText:SetJustifyV("MIDDLE")
    frame.replayText:SetText("Select an event")

    -- Previous/Next selected-event controls remain available through the visible
    -- event-page arrows and row selection. Keep compatibility handles for older
    -- update code without placing duplicate buttons on the compact page.
    frame.replayPrev = CreateFrame("Button", nil, frame); frame.replayPrev:Hide()
    frame.replayNext = CreateFrame("Button", nil, frame); frame.replayNext:Hide()

    self.detailsFrame = frame
    return frame
end

local RC1F_OldUpdateDetailsWindow = MT.UpdateDetailsWindow
function MT:UpdateDetailsWindow()
    RC1F_OldUpdateDetailsWindow(self)
    local frame = self.detailsFrame
    if not frame then return end

    local detailEvents = self:GetFilteredDetailEvents()
    local count = table.getn(detailEvents)

    -- Opening Details should never present a dead inspector when events exist.
    if count > 0 then
        if not self.detailsSelectedEvent or self.detailsSelectedEvent < 1 or self.detailsSelectedEvent > count then
            self.detailsSelectedEvent = 1
            self.detailsEventPage = 1
        end
    else
        self.detailsSelectedEvent = nil
        self.detailsEventPage = 1
    end

    local pageSize = math.max(1, table.getn(frame.eventRows or {}))
    local pages = math.max(1, math.ceil(count / pageSize))
    if self.detailsEventPage < 1 then self.detailsEventPage = 1 end
    if self.detailsEventPage > pages then self.detailsEventPage = pages end

    local startIndex = ((self.detailsEventPage - 1) * pageSize) + 1
    local i
    for i = 1, pageSize do
        local row = frame.eventRows[i]
        local index = startIndex + i - 1
        local event = detailEvents[index]
        row.eventIndex = event and index or nil
        row.data = event
        if event then
            row.time:SetText(format("%.1f", event.time or 0))
            row.source:SetText(event.source or "Unknown")
            row.ability:SetText(event.ability or event.kind or "Unknown")
            local outcome = self:FormatEventOutcome(event)
            if string.len(outcome) > 16 then outcome = string.sub(outcome, 1, 15) .. "..." end
            row.outcome:SetText(outcome)
            if self.detailsSelectedEvent == index then row.highlight:Show() else row.highlight:Hide() end
            row:Show()
        else
            row.highlight:Hide()
            row:Hide()
        end
    end

    frame.replayCount:SetText(count .. " events")
    frame.eventPageText:SetText(self.detailsEventPage .. "/" .. pages)
    if self.detailsEventPage <= 1 then frame.eventPrev:Disable() else frame.eventPrev:Enable() end
    if self.detailsEventPage >= pages then frame.eventNext:Disable() else frame.eventNext:Enable() end

    local selected = self.detailsSelectedEvent and detailEvents[self.detailsSelectedEvent]
    if selected then
        local stopped = (selected.raw or 0) - (selected.taken or 0)
        if stopped < 0 then stopped = 0 end
        frame.replayText:SetText(format("%.1fs  %s  Raw %s / Taken %s / Stopped %s",
            selected.time or 0,
            selected.ability or selected.kind or "Unknown",
            self:FormatNumber(selected.raw or 0),
            self:FormatNumber(selected.taken or 0),
            self:FormatNumber(stopped)))
    else
        frame.replayText:SetText("No matching events")
    end
end



-- ============================================================================
-- v1.0.0 RC1h - Main-page reset control and SavedVariables size warnings
-- ============================================================================

local RC1H_WARN_50 = 50 * 1024 * 1024
local RC1H_WARN_100 = 100 * 1024 * 1024
local RC1H_SIZE_CUTOFF = 110 * 1024 * 1024

-- Approximate the serialized SavedVariables size without constructing a giant
-- temporary string. The scan stops after the critical threshold is exceeded.
local function RC1H_EstimateTableBytes(value, seen, total)
    total = total or 0
    if total >= RC1H_SIZE_CUTOFF then return total end

    local valueType = type(value)
    if valueType == "nil" then return total + 3 end
    if valueType == "boolean" then return total + (value and 4 or 5) end
    if valueType == "number" then return total + string.len(tostring(value)) end
    if valueType == "string" then return total + string.len(value) + 2 end
    if valueType ~= "table" then return total end

    seen = seen or {}
    if seen[value] then return total end
    seen[value] = true
    total = total + 2

    local key, item
    for key, item in pairs(value) do
        total = RC1H_EstimateTableBytes(key, seen, total) + 3
        if total >= RC1H_SIZE_CUTOFF then return total end
        total = RC1H_EstimateTableBytes(item, seen, total) + 2
        if total >= RC1H_SIZE_CUTOFF then return total end
    end
    return total
end

function MT:GetApproximateStoredBytes()
    if not MainTankDB then return 0 end
    return RC1H_EstimateTableBytes(MainTankDB, {}, 0)
end

function MT:CheckStoredDataSize(force)
    local now = GetTime and GetTime() or 0
    if not force and self.lastStorageCheck and (now - self.lastStorageCheck) < 60 then return end
    self.lastStorageCheck = now

    local bytes = self:GetApproximateStoredBytes()
    self.approxStoredBytes = bytes
    local megabytes = bytes / 1048576

    if bytes >= RC1H_WARN_100 then
        if force or not self.warnedStorage100 then
            self.warnedStorage100 = true
            Print(format("Stored data is about %.1f MB. Reset is strongly recommended to protect the Vanilla client.", megabytes))
        end
    elseif bytes >= RC1H_WARN_50 then
        if force or not self.warnedStorage50 then
            self.warnedStorage50 = true
            Print(format("Stored data is about %.1f MB. Consider using the Reset button soon.", megabytes))
        end
    end
end

function MT:ConfirmResetAllData()
    if StaticPopup_Show then
        StaticPopup_Show("MAINTANK_RESET_ALL")
    else
        -- Extremely defensive fallback for clients that replace StaticPopup.
        self:ResetSession()
    end
end

if StaticPopupDialogs then
    StaticPopupDialogs["MAINTANK_RESET_ALL"] = {
        text = "Delete all stored combat data?\nThis cannot be undone.",
        button1 = "Delete",
        button2 = "Cancel",
        OnAccept = function()
            MT:ResetSession()
            MT.warnedStorage50 = nil
            MT.warnedStorage100 = nil
            MT.approxStoredBytes = 0
        end,
        timeout = 0,
        whileDead = 1,
        hideOnEscape = 1
    }
end

local RC1H_OldCreateUI = MT.CreateUI
function MT:CreateUI()
    RC1H_OldCreateUI(self)
    local frame = self.frame
    if not frame or frame.resetDataButton then return end

    local reset = CreateFrame("Button", nil, frame)
    reset:SetWidth(18)
    reset:SetHeight(18)
    reset:SetPoint("LEFT", self.viewButtons.OVERALL, "RIGHT", 5, 0)
    reset:SetNormalTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Up")
    reset:SetPushedTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Down")
    reset:SetHighlightTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Highlight", "ADD")
    reset:SetScript("OnClick", function() MT:ConfirmResetAllData() end)
    reset:SetScript("OnEnter", function()
        local tip = MT:GetAnalysisTooltip()
        tip:SetOwner(this, "ANCHOR_CURSOR")
        tip:SetText("Reset stored data", 1, 0.82, 0)
        tip:AddLine("Deletes current, overall, saved fights,", 0.85, 0.85, 0.85)
        tip:AddLine("timelines, and learned enemy data.", 0.85, 0.85, 0.85)
        tip:AddLine("A confirmation is required.", 0.35, 0.75, 1)
        tip:AddLine("Regular cleanup keeps SavedVariables small.", 0.35, 0.85, 0.35)
        tip:Show()
    end)
    reset:SetScript("OnLeave", function() MT:HideAnalysisTooltip() end)
    frame.resetDataButton = reset
    self:RegisterFullControl(reset)

    -- Keep it on the same row even if another UI patch repositions Overall.
    reset:ClearAllPoints()
    reset:SetPoint("LEFT", self.viewButtons.OVERALL, "RIGHT", 5, 0)

    -- Check once after the profile has been restored and linked.
    self:CheckStoredDataSize(true)
end

local RC1H_OldEndCombat = MT.EndCombat
function MT:EndCombat()
    RC1H_OldEndCombat(self)
    self:CheckStoredDataSize(false)
end

local RC1H_OldResetSession = MT.ResetSession
function MT:ResetSession()
    RC1H_OldResetSession(self)
    self.warnedStorage50 = nil
    self.warnedStorage100 = nil
    self.approxStoredBytes = 0
end

-- ============================================================================
-- v1.0.0 RC1i - Final UI polish candidate
-- Main spacing, compact Details interaction, Biggest readability, and
-- consistent bottom-right minimization.
-- ============================================================================

-- Keep the minimize control out of all summary text and always collapse toward
-- the same bottom-right corner, including after returning from another page.
local RC1I_OldReturnToMain = MT.ReturnToMain
function MT:ReturnToMain()
    RC1I_OldReturnToMain(self)
    if self.frame and self.frame.shrinkButton then
        self.frame.shrinkButton:ClearAllPoints()
        self.frame.shrinkButton:SetPoint("BOTTOMRIGHT", self.frame, "BOTTOMRIGHT", -3, 3)
        self.frame.shrinkButton:SetWidth(13)
        self.frame.shrinkButton:SetHeight(12)
        self.frame.shrinkButton:SetText("-")
    end
end

local RC1I_OldSetMiniMode = MT.SetMiniMode
function MT:SetMiniMode(enabled, automatic)
    local frame = self.frame
    local right, bottom
    if frame then
        right = frame:GetRight()
        bottom = frame:GetBottom()
    end

    RC1I_OldSetMiniMode(self, enabled, automatic)

    frame = self.frame
    if not frame then return end
    if right and bottom then
        frame:ClearAllPoints()
        frame:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMLEFT", right, bottom)
    end
    if frame.shrinkButton then
        frame.shrinkButton:ClearAllPoints()
        frame.shrinkButton:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -3, 3)
        frame.shrinkButton:SetWidth(13)
        frame.shrinkButton:SetHeight(12)
    end
end

-- Add restrained separators to the main page. They improve scanability without
-- changing the compact 300x231 footprint or the existing navigation layout.
local RC1I_OldCreateUI = MT.CreateUI
function MT:CreateUI()
    RC1I_OldCreateUI(self)
    local frame = self.frame
    if not frame or frame.rc1iPolished then return end

    if frame.shrinkButton then
        frame.shrinkButton:ClearAllPoints()
        frame.shrinkButton:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -3, 3)
        frame.shrinkButton:SetWidth(13)
        frame.shrinkButton:SetHeight(12)
    end

    frame.headerRule = frame:CreateTexture(nil, "ARTWORK")
    frame.headerRule:SetTexture(1, 1, 1, 0.10)
    frame.headerRule:SetHeight(1)
    frame.headerRule:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -74)
    frame.headerRule:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -8, -74)

    frame.statsRule = frame:CreateTexture(nil, "ARTWORK")
    frame.statsRule:SetTexture(1, 1, 1, 0.08)
    frame.statsRule:SetHeight(1)
    frame.statsRule:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -128)
    frame.statsRule:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -12, -128)

    frame.rc1iPolished = true
end

-- Make Timeline bucket interaction explicit after all page-manager wrappers have
-- run. Each visible second keeps its own data and receives the dedicated tooltip.
local RC1I_OldCreateTimelineWindow = MT.CreateTimelineWindow
function MT:CreateTimelineWindow()
    local frame = RC1I_OldCreateTimelineWindow(self)
    if frame and frame.bars and not frame.rc1iTooltipBound then
        local i
        for i = 1, table.getn(frame.bars) do
            local bar = frame.bars[i]
            bar:EnableMouse(true)
            bar:SetScript("OnEnter", function()
                if this.bucket and this.second then
                    MT:ShowTimelineTooltip(this, this.second, this.bucket)
                end
            end)
            bar:SetScript("OnLeave", function() MT:HideAnalysisTooltip() end)
        end
        frame.rc1iTooltipBound = true
    end
    return frame
end

-- Details remains compact, but the selected event now has a clear two-line
-- damage-flow readout. One visible event row avoids the overlap that occurred
-- when two rows and the inspector occupied the same bottom area.
local RC1I_OldCreateDetailsWindow = MT.CreateDetailsWindow
function MT:CreateDetailsWindow()
    local frame = RC1I_OldCreateDetailsWindow(self)
    if not frame or frame.rc1iPolished then return frame end

    if frame.eventRows and frame.eventRows[2] then
        frame.eventRows[2]:Hide()
        frame.eventRows[2] = nil
    end

    if frame.eventRows and frame.eventRows[1] then
        local row = frame.eventRows[1]
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", frame, "TOPLEFT", 9, -176)
        row:SetHeight(14)
    end

    if frame.replayText then
        frame.replayText:ClearAllPoints()
        frame.replayText:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 31, 20)
        frame.replayText:SetWidth(238)
        frame.replayText:SetHeight(25)
        frame.replayText:SetJustifyH("CENTER")
        frame.replayText:SetJustifyV("MIDDLE")
    end

    frame.selectedEventLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    frame.selectedEventLabel:SetPoint("BOTTOM", frame, "BOTTOM", 0, 45)
    frame.selectedEventLabel:SetText("Selected Event")

    frame.eventRule = frame:CreateTexture(nil, "ARTWORK")
    frame.eventRule:SetTexture(1, 1, 1, 0.10)
    frame.eventRule:SetHeight(1)
    frame.eventRule:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 9, 47)
    frame.eventRule:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -9, 47)

    frame.rc1iPolished = true
    return frame
end

local RC1I_OldUpdateDetailsWindow = MT.UpdateDetailsWindow
function MT:UpdateDetailsWindow()
    RC1I_OldUpdateDetailsWindow(self)
    local frame = self.detailsFrame
    if not frame or not frame.replayText then return end

    local events = self:GetFilteredDetailEvents() or {}
    local selected = self.detailsSelectedEvent and events[self.detailsSelectedEvent]
    if selected then
        local raw = selected.raw or 0
        local taken = selected.taken or 0
        local stopped = raw - taken
        if stopped < 0 then stopped = 0 end
        local source = selected.source or "Unknown"
        local ability = selected.ability or selected.kind or "Unknown"
        frame.replayText:SetText(format("%.1fs  %s - %s\nRaw %s   Stopped %s   Taken %s",
            selected.time or 0,
            source,
            ability,
            self:FormatNumber(raw),
            self:FormatNumber(stopped),
            self:FormatNumber(taken)))
    else
        frame.replayText:SetText("No matching events")
    end
end

-- Biggest rows now advertise their interactivity and expose the full selected
-- event in the compact tooltip while preserving the page-local inspector.
local RC1I_OldCreateBiggestWindow = MT.CreateBiggestWindow
function MT:CreateBiggestWindow()
    local frame = RC1I_OldCreateBiggestWindow(self)
    if not frame or frame.rc1iPolished then return frame end

    local i
    for i = 1, table.getn(frame.rows or {}) do
        local row = frame.rows[i]
        row:SetScript("OnEnter", function()
            if not this.entry then return end
            this.highlight:Show()
            if this.entry.event then
                local tip = MT:GetAnalysisTooltip()
                tip:SetOwner(this, "ANCHOR_LEFT")
                tip:SetText(MT:FormatEventInspector(this.entry.event), 1, 0.82, 0, 1, true)
                tip:Show()
            end
        end)
        row:SetScript("OnLeave", function()
            this.highlight:Hide()
            MT:HideAnalysisTooltip()
        end)
    end

    if frame.inspectorHeader then frame.inspectorHeader:SetText("Selected Event") end
    frame.rc1iPolished = true
    return frame
end

local RC1I_OldUpdateBiggestWindow = MT.UpdateBiggestWindow
function MT:UpdateBiggestWindow()
    RC1I_OldUpdateBiggestWindow(self)
    local frame = self.biggestFrame
    if not frame or not frame.inspector then return end
    local event = self.biggestSelectedEvent
    if event then
        local raw = event.raw or 0
        local taken = event.taken or 0
        local stopped = raw - taken
        if stopped < 0 then stopped = 0 end
        frame.inspector:SetText(format("%.1fs  %s - %s\nRaw %s   Stopped %s   Taken %s",
            event.time or 0,
            event.source or "Unknown",
            event.ability or event.kind or "Unknown",
            self:FormatNumber(raw),
            self:FormatNumber(stopped),
            self:FormatNumber(taken)))
    else
        frame.inspector:SetText("Select a record above to inspect its damage flow.")
    end
end

-- ============================================================================
-- v1.0.0 RC1j - Details cleanup and mini-mode visual safety
-- ============================================================================

-- Replace the layered RC1f/RC1i event area with one clean compact section.
local RC1J_OldCreateDetailsWindow = MT.CreateDetailsWindow
function MT:CreateDetailsWindow()
    local frame = RC1J_OldCreateDetailsWindow(self)
    if not frame or frame.rc1jClean then return frame end

    -- Hide compatibility/legacy elements that occupied the same lower area.
    if frame.eventRows then
        local i
        for i = 1, table.getn(frame.eventRows) do
            if frame.eventRows[i] then frame.eventRows[i]:Hide() end
        end
    end
    if frame.replayText then frame.replayText:Hide() end
    if frame.selectedEventLabel then frame.selectedEventLabel:Hide() end
    if frame.eventRule then frame.eventRule:Hide() end
    if frame.inspectorHeader then frame.inspectorHeader:Hide() end
    if frame.inspector then frame.inspector:Hide() end

    -- A subtle divider contained safely inside the Details frame.
    frame.rc1jEventDivider = frame:CreateTexture(nil, "ARTWORK")
    frame.rc1jEventDivider:SetTexture(1, 1, 1, 0.09)
    frame.rc1jEventDivider:SetHeight(1)
    frame.rc1jEventDivider:SetPoint("TOPLEFT", frame, "TOPLEFT", 9, -161)
    frame.rc1jEventDivider:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -9, -161)

    frame.rc1jEventsHeader = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    frame.rc1jEventsHeader:SetPoint("TOPLEFT", frame, "TOPLEFT", 9, -165)
    frame.rc1jEventsHeader:SetText("Events")

    frame.rc1jEventCount = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.rc1jEventCount:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -9, -165)

    frame.rc1jEventRows = {}
    local i
    for i = 1, 2 do
        local row = CreateFrame("Button", nil, frame)
        row:SetWidth(282); row:SetHeight(13)
        row:SetPoint("TOPLEFT", frame, "TOPLEFT", 9, -177 - ((i - 1) * 14))
        row:EnableMouse(true)

        row.highlight = row:CreateTexture(nil, "BACKGROUND")
        row.highlight:SetAllPoints(row)
        row.highlight:SetTexture(0.20, 0.34, 0.52, 0.58)
        row.highlight:Hide()

        row.time = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.time:SetPoint("LEFT", row, "LEFT", 2, 0)
        row.time:SetWidth(35); row.time:SetJustifyH("LEFT")

        row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.text:SetPoint("LEFT", row, "LEFT", 39, 0)
        row.text:SetWidth(169); row.text:SetJustifyH("LEFT")

        row.outcome = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.outcome:SetPoint("RIGHT", row, "RIGHT", -2, 0)
        row.outcome:SetWidth(70); row.outcome:SetJustifyH("RIGHT")

        row:SetScript("OnClick", function()
            if this.eventIndex then
                MT.detailsSelectedEvent = this.eventIndex
                MT:UpdateDetailsWindow()
            end
        end)
        row:SetScript("OnEnter", function()
            if this.data then
                this.highlight:Show()
                local tip = MT:GetAnalysisTooltip()
                tip:SetOwner(this, "ANCHOR_LEFT")
                tip:SetText(MT:FormatEventInspector(this.data), 1, 0.82, 0, 1, true)
                tip:Show()
            end
        end)
        row:SetScript("OnLeave", function()
            if not (this.eventIndex and MT.detailsSelectedEvent == this.eventIndex) then
                this.highlight:Hide()
            end
            MT:HideAnalysisTooltip()
        end)
        frame.rc1jEventRows[i] = row
    end

    frame.rc1jInspector = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.rc1jInspector:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 31, 19)
    frame.rc1jInspector:SetWidth(238); frame.rc1jInspector:SetHeight(24)
    frame.rc1jInspector:SetJustifyH("CENTER"); frame.rc1jInspector:SetJustifyV("MIDDLE")
    frame.rc1jInspector:SetText("Select an event")

    -- Keep the existing pager, but make it visually compact and contained.
    if frame.eventPrev then
        frame.eventPrev:ClearAllPoints(); frame.eventPrev:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 9, 5)
    end
    if frame.eventNext then
        frame.eventNext:ClearAllPoints(); frame.eventNext:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -9, 5)
    end
    if frame.eventPageText then
        frame.eventPageText:ClearAllPoints(); frame.eventPageText:SetPoint("BOTTOM", frame, "BOTTOM", 0, 7)
    end

    frame.rc1jClean = true
    return frame
end

local RC1J_OldUpdateDetailsWindow = MT.UpdateDetailsWindow
function MT:UpdateDetailsWindow()
    RC1J_OldUpdateDetailsWindow(self)
    local frame = self.detailsFrame
    if not frame or not frame.rc1jEventRows then return end

    local events = self:GetFilteredDetailEvents() or {}
    local count = table.getn(events)
    local pageSize = 2
    local pages = math.max(1, math.ceil(count / pageSize))
    self.detailsEventPage = math.max(1, math.min(self.detailsEventPage or 1, pages))
    local startIndex = ((self.detailsEventPage - 1) * pageSize) + 1

    frame.rc1jEventCount:SetText(count .. " events")

    local i
    for i = 1, pageSize do
        local row = frame.rc1jEventRows[i]
        local index = startIndex + i - 1
        local event = events[index]
        if event then
            local source = event.source or "Unknown"
            local ability = event.ability or event.kind or "Unknown"
            local taken = event.taken or 0
            local raw = event.raw or 0
            row.data = event
            row.eventIndex = index
            row.time:SetText(format("%.1f", event.time or 0))
            row.text:SetText(source .. " - " .. ability)
            row.outcome:SetText(self:FormatNumber(taken) .. "/" .. self:FormatNumber(raw))
            if self.detailsSelectedEvent == index then row.highlight:Show() else row.highlight:Hide() end
            row:Show()
        else
            row.data = nil; row.eventIndex = nil
            row:Hide()
        end
    end

    local selected = self.detailsSelectedEvent and events[self.detailsSelectedEvent]
    if selected then
        local raw = selected.raw or 0
        local taken = selected.taken or 0
        local stopped = raw - taken
        if stopped < 0 then stopped = 0 end
        frame.rc1jInspector:SetText(format("%.1fs  %s - %s\nRaw %s   Stopped %s   Taken %s",
            selected.time or 0,
            selected.source or "Unknown",
            selected.ability or selected.kind or "Unknown",
            self:FormatNumber(raw), self:FormatNumber(stopped), self:FormatNumber(taken)))
    elseif count > 0 then
        self.detailsSelectedEvent = startIndex
        local first = events[startIndex]
        if first then
            local raw = first.raw or 0
            local taken = first.taken or 0
            local stopped = raw - taken
            if stopped < 0 then stopped = 0 end
            frame.rc1jEventRows[1].highlight:Show()
            frame.rc1jInspector:SetText(format("%.1fs  %s - %s\nRaw %s   Stopped %s   Taken %s",
                first.time or 0,
                first.source or "Unknown",
                first.ability or first.kind or "Unknown",
                self:FormatNumber(raw), self:FormatNumber(stopped), self:FormatNumber(taken)))
        end
    else
        frame.rc1jInspector:SetText("No matching events")
    end
end

-- Decorative main-page rules must never remain visible after the frame shrinks.
local RC1J_OldSetMiniMode = MT.SetMiniMode
function MT:SetMiniMode(enabled, automatic)
    RC1J_OldSetMiniMode(self, enabled, automatic)
    local frame = self.frame
    if not frame then return end

    local showRules = not enabled
    if frame.headerRule then if showRules then frame.headerRule:Show() else frame.headerRule:Hide() end end
    if frame.statsRule then if showRules then frame.statsRule:Show() else frame.statsRule:Hide() end end

    -- Safety: no page-local divider should remain visible while the main frame is mini.
    if self.detailsFrame and self.detailsFrame.rc1jEventDivider then
        if enabled then self.detailsFrame.rc1jEventDivider:Hide()
        elseif self.currentManagedPage == "DETAILS" then self.detailsFrame.rc1jEventDivider:Show() end
    end
end

local RC1J_OldReturnToMain = MT.ReturnToMain
function MT:ReturnToMain()
    RC1J_OldReturnToMain(self)
    local frame = self.frame
    if frame and not self.isMini then
        if frame.headerRule then frame.headerRule:Show() end
        if frame.statsRule then frame.statsRule:Show() end
    end
end

-- ============================================================================
-- v1.0.0 RC1k - Final Details event-area de-layering
-- ============================================================================

local RC1K_OldCreateDetailsWindow = MT.CreateDetailsWindow
function MT:CreateDetailsWindow()
    local frame = RC1K_OldCreateDetailsWindow(self)
    if not frame or frame.rc1kClean then return frame end

    -- RC1j proved the remaining overlap came from older controls being refreshed
    -- after they had been hidden. Keep them permanently unused and replace the
    -- whole event area with one readable two-line event card.
    if frame.rc1jEventRows then
        local i
        for i = 1, table.getn(frame.rc1jEventRows) do
            if frame.rc1jEventRows[i] then frame.rc1jEventRows[i]:Hide() end
        end
    end
    if frame.rc1jInspector then frame.rc1jInspector:Hide() end

    frame.rc1kEventRow = CreateFrame("Button", nil, frame)
    frame.rc1kEventRow:SetWidth(282)
    frame.rc1kEventRow:SetHeight(30)
    frame.rc1kEventRow:SetPoint("TOPLEFT", frame, "TOPLEFT", 9, -177)
    frame.rc1kEventRow:EnableMouse(true)

    frame.rc1kEventRow.highlight = frame.rc1kEventRow:CreateTexture(nil, "BACKGROUND")
    frame.rc1kEventRow.highlight:SetAllPoints(frame.rc1kEventRow)
    frame.rc1kEventRow.highlight:SetTexture(0.20, 0.34, 0.52, 0.58)
    frame.rc1kEventRow.highlight:Hide()

    frame.rc1kEventRow.line1 = frame.rc1kEventRow:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.rc1kEventRow.line1:SetPoint("TOPLEFT", frame.rc1kEventRow, "TOPLEFT", 3, -2)
    frame.rc1kEventRow.line1:SetWidth(276)
    frame.rc1kEventRow.line1:SetJustifyH("LEFT")

    frame.rc1kEventRow.line2 = frame.rc1kEventRow:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.rc1kEventRow.line2:SetPoint("BOTTOMLEFT", frame.rc1kEventRow, "BOTTOMLEFT", 3, 2)
    frame.rc1kEventRow.line2:SetWidth(276)
    frame.rc1kEventRow.line2:SetJustifyH("LEFT")
    frame.rc1kEventRow.line2:SetTextColor(0.78, 0.78, 0.78)

    frame.rc1kEventRow:SetScript("OnClick", function()
        if this.eventIndex then
            MT.detailsSelectedEvent = this.eventIndex
            MT:UpdateDetailsWindow()
        end
    end)
    frame.rc1kEventRow:SetScript("OnEnter", function()
        if this.data then
            this.highlight:Show()
            local tip = MT:GetAnalysisTooltip()
            tip:SetOwner(this, "ANCHOR_LEFT")
            tip:SetText(MT:FormatEventInspector(this.data), 1, 0.82, 0, 1, true)
            tip:Show()
        end
    end)
    frame.rc1kEventRow:SetScript("OnLeave", function()
        if not (this.eventIndex and MT.detailsSelectedEvent == this.eventIndex) then
            this.highlight:Hide()
        end
        MT:HideAnalysisTooltip()
    end)

    frame.rc1kClean = true
    return frame
end

local RC1K_OldUpdateDetailsWindow = MT.UpdateDetailsWindow
function MT:UpdateDetailsWindow()
    RC1K_OldUpdateDetailsWindow(self)
    local frame = self.detailsFrame
    if not frame or not frame.rc1kEventRow then return end

    -- Older update layers can Show() these again; suppress them after every
    -- refresh so only the RC1k event card is visible.
    local function HideLegacyEventControls()
        local i
        if frame.eventRows then
            for i = 1, table.getn(frame.eventRows) do
                if frame.eventRows[i] then frame.eventRows[i]:Hide() end
            end
        end
        if frame.rc1jEventRows then
            for i = 1, table.getn(frame.rc1jEventRows) do
                if frame.rc1jEventRows[i] then frame.rc1jEventRows[i]:Hide() end
            end
        end
        if frame.replayText then frame.replayText:Hide() end
        if frame.selectedEventLabel then frame.selectedEventLabel:Hide() end
        if frame.eventRule then frame.eventRule:Hide() end
        if frame.inspectorHeader then frame.inspectorHeader:Hide() end
        if frame.inspector then frame.inspector:Hide() end
        if frame.rc1jInspector then frame.rc1jInspector:Hide() end
    end
    HideLegacyEventControls()

    local events = self:GetFilteredDetailEvents() or {}
    local count = table.getn(events)
    local pages = math.max(1, count)
    self.detailsEventPage = math.max(1, math.min(self.detailsEventPage or 1, pages))

    if frame.rc1jEventCount then frame.rc1jEventCount:SetText(count .. " events") end
    if frame.eventPageText then frame.eventPageText:SetText(self.detailsEventPage .. "/" .. pages) end

    if frame.eventPrev then
        if self.detailsEventPage > 1 then frame.eventPrev:Enable() else frame.eventPrev:Disable() end
    end
    if frame.eventNext then
        if self.detailsEventPage < pages then frame.eventNext:Enable() else frame.eventNext:Disable() end
    end

    local event = events[self.detailsEventPage]
    if event then
        self.detailsSelectedEvent = self.detailsEventPage
        local raw = event.raw or 0
        local taken = event.taken or 0
        local stopped = raw - taken
        if stopped < 0 then stopped = 0 end
        local source = event.source or "Unknown"
        local ability = event.ability or event.kind or "Unknown"

        frame.rc1kEventRow.data = event
        frame.rc1kEventRow.eventIndex = self.detailsEventPage
        frame.rc1kEventRow.line1:SetText(format("%.1fs  %s - %s", event.time or 0, source, ability))
        frame.rc1kEventRow.line2:SetText(format("Raw %s   Stopped %s   Taken %s",
            self:FormatNumber(raw), self:FormatNumber(stopped), self:FormatNumber(taken)))
        frame.rc1kEventRow.highlight:Show()
        frame.rc1kEventRow:Show()
    else
        frame.rc1kEventRow.data = nil
        frame.rc1kEventRow.eventIndex = nil
        frame.rc1kEventRow.line1:SetText("No matching events")
        frame.rc1kEventRow.line2:SetText("")
        frame.rc1kEventRow.highlight:Hide()
        frame.rc1kEventRow:Show()
    end
end




-- Private exports consumed by the later analysis-feature layer.
-- These are the finalized values after all RC1 navigation wrappers above.
E.RC_PAGE_WIDTH = RC_PAGE_WIDTH
E.RC_PAGE_HEIGHT = RC_PAGE_HEIGHT
E.RC_CreatePageFrame = RC_CreatePageFrame
