-- MainTank REFACXML1 - Analysis core
-- Extracted from the historical Engine.lua foundation.
-- Load immediately after Core\Engine.lua and before UI\AnalysisNavigation.lua.

local MT = MainTank
local E = MT._engine
local floor = math.floor
local format = string.format
local NewData = E.NewData
local NewTimelineBucket = E.NewTimelineBucket
local MT_LEGACY_BACKDROP = E.MT_LEGACY_BACKDROP
local StyleLegacyButton = E.StyleLegacyButton
local FinalizeLegacyWindow = E.FinalizeLegacyWindow
local SaveWindowPosition = E.SaveWindowPosition
local RestoreWindowPosition = E.RestoreWindowPosition

local TIMELINE_MODES = {"RAW", "PHYSICAL", "MAGIC"}

local function TimelineValue(bucket, mode)
    if not bucket then return 0 end
    if mode == "PHYSICAL" then return bucket.physicalRaw or 0 end
    if mode == "MAGIC" then return bucket.magicRaw or 0 end
    return bucket.raw or 0
end

function MT:CycleTimelineMode()
    local index = 1
    local i
    for i = 1, table.getn(TIMELINE_MODES) do
        if TIMELINE_MODES[i] == self.timelineMode then index = i break end
    end
    index = index + 1
    if index > table.getn(TIMELINE_MODES) then index = 1 end
    self.timelineMode = TIMELINE_MODES[index]
    self:UpdateTimelineWindow()
end

function MT:GetTimelineRange(timeline)
    local maxSecond = 0
    local second
    for second in pairs(timeline or {}) do
        if type(second) == "number" and second > maxSecond then maxSecond = second end
    end
    return 0, maxSecond
end

local function AddBucketValues(target, bucket)
    if not bucket then return end
    target.raw = target.raw + (bucket.raw or 0)
    target.armor = target.armor + (bucket.armor or 0)
    target.block = target.block + (bucket.block or 0)
    target.avoidance = target.avoidance + (bucket.avoidance or 0)
    target.resist = target.resist + (bucket.resist or 0)
    target.absorb = target.absorb + (bucket.absorb or 0)
    target.taken = target.taken + (bucket.taken or 0)
    target.physicalTaken = (target.physicalTaken or 0) + (bucket.physicalTaken or 0)
    target.magicTaken = (target.magicTaken or 0) + (bucket.magicTaken or 0)
    target.physicalRaw = target.physicalRaw + (bucket.physicalRaw or 0)
    target.magicRaw = target.magicRaw + (bucket.magicRaw or 0)
    target.events = target.events + (bucket.events or 0)
end

function MT:AggregateTimelineBucket(timeline, firstSecond, lastSecond)
    local bucket = NewTimelineBucket(firstSecond)
    local second
    for second = firstSecond, lastSecond do
        AddBucketValues(bucket, timeline[second])
    end
    bucket.firstSecond = firstSecond
    bucket.lastSecond = lastSecond
    return bucket
end

local function NewTimelineDetails()
    return {
        raw = 0, physicalRaw = 0, magicRaw = 0,
        armor = 0, block = 0, avoidance = 0, resist = 0, absorb = 0,
        taken = 0, physicalTaken = 0, magicTaken = 0,
        physicalAbsorb = 0, magicAbsorb = 0,
        dodge = 0, parry = 0, miss = 0,
        dodgeCount = 0, parryCount = 0, missCount = 0,
        partialBlock = 0, fullBlock = 0, partialBlockCount = 0, fullBlockCount = 0,
        damageEvents = 0, events = 0, schools = {}
    }
end

function MT:GetTimelineDetails(firstSecond, lastSecond)
    local details = NewTimelineDetails()
    local events = self:GetDisplayEvents() or {}
    local i, event, eventSecond, school, schoolData
    for i = 1, table.getn(events) do
        event = events[i]
        eventSecond = floor(event.time or 0)
        if eventSecond >= firstSecond and eventSecond <= lastSecond then
            details.events = details.events + 1
            details.raw = details.raw + (event.raw or 0)
            details.physicalRaw = details.physicalRaw + (event.physicalRaw or 0)
            details.magicRaw = details.magicRaw + (event.magicRaw or 0)
            details.armor = details.armor + (event.armor or 0)
            details.block = details.block + (event.block or 0)
            details.avoidance = details.avoidance + (event.avoidance or 0)
            details.resist = details.resist + (event.resist or 0)
            details.absorb = details.absorb + (event.absorb or 0)
            details.taken = details.taken + (event.taken or 0)
            if (event.taken or 0) > 0 then details.damageEvents = details.damageEvents + 1 end

            if event.school == "Physical" then
                details.physicalTaken = details.physicalTaken + (event.taken or 0)
                details.physicalAbsorb = details.physicalAbsorb + (event.absorb or 0)
            else
                details.magicTaken = details.magicTaken + (event.taken or 0)
                details.magicAbsorb = details.magicAbsorb + (event.absorb or 0)
            end

            if event.kind == "Dodge" then
                details.dodge = details.dodge + (event.avoidance or 0)
                details.dodgeCount = details.dodgeCount + 1
            elseif event.kind == "Parry" then
                details.parry = details.parry + (event.avoidance or 0)
                details.parryCount = details.parryCount + 1
            elseif event.kind == "Miss" then
                details.miss = details.miss + (event.avoidance or 0)
                details.missCount = details.missCount + 1
            elseif event.kind == "FullBlock" then
                details.fullBlock = details.fullBlock + (event.block or 0)
                details.fullBlockCount = details.fullBlockCount + 1
            elseif (event.block or 0) > 0 then
                details.partialBlock = details.partialBlock + (event.block or 0)
                details.partialBlockCount = details.partialBlockCount + 1
            end

            if event.school and event.school ~= "Physical" then
                school = event.school
                if not details.schools[school] then
                    details.schools[school] = {raw = 0, taken = 0, resisted = 0, events = 0}
                end
                schoolData = details.schools[school]
                schoolData.raw = schoolData.raw + (event.magicRaw or event.raw or 0)
                schoolData.taken = schoolData.taken + (event.taken or 0)
                schoolData.resisted = schoolData.resisted + (event.resist or 0)
                schoolData.events = schoolData.events + 1
            end
        end
    end
    return details
end

local function AddTimelineHeader(firstSecond, lastSecond, mode)
    if lastSecond > firstSecond then
        MT:GetAnalysisTooltip():SetText(format("%s Timeline - %ds to %ds", mode, firstSecond, lastSecond), 1, 0.82, 0)
    else
        MT:GetAnalysisTooltip():SetText(format("%s Timeline - %ds", mode, firstSecond), 1, 0.82, 0)
    end
end

function MT:ShowTimelineTooltip(owner, second, bucket)
    if not bucket then return end
    MT:GetAnalysisTooltip():SetOwner(owner, "ANCHOR_CURSOR")
    local firstSecond = bucket.firstSecond or second or 0
    local lastSecond = bucket.lastSecond or firstSecond
    local mode = self.timelineMode or "RAW"
    local d = self:GetTimelineDetails(firstSecond, lastSecond)
    local names, i, school, sd, physicalStopped, magicStopped

    AddTimelineHeader(firstSecond, lastSecond, mode)

    if mode == "PHYSICAL" then
        physicalStopped = d.physicalRaw - d.physicalTaken
        if physicalStopped < 0 then physicalStopped = 0 end
        MT:GetAnalysisTooltip():AddDoubleLine("Raw physical incoming", self:FormatNumber(d.physicalRaw), 0.85,0.85,0.85, 1,1,1)
        MT:GetAnalysisTooltip():AddDoubleLine("Reduced by armor", self:FormatNumber(d.armor), 0.35,0.85,0.35, 1,1,1)
        MT:GetAnalysisTooltip():AddDoubleLine("Dodged (estimated)", self:FormatNumber(d.dodge) .. "  (" .. d.dodgeCount .. ")", 0.35,0.85,0.35, 1,1,1)
        MT:GetAnalysisTooltip():AddDoubleLine("Parried (estimated)", self:FormatNumber(d.parry) .. "  (" .. d.parryCount .. ")", 0.35,0.85,0.35, 1,1,1)
        MT:GetAnalysisTooltip():AddDoubleLine("Missed (estimated)", self:FormatNumber(d.miss) .. "  (" .. d.missCount .. ")", 0.35,0.85,0.35, 1,1,1)
        MT:GetAnalysisTooltip():AddDoubleLine("Partial blocks", self:FormatNumber(d.partialBlock) .. "  (" .. d.partialBlockCount .. ")", 0.35,0.85,0.35, 1,1,1)
        MT:GetAnalysisTooltip():AddDoubleLine("Full blocks (estimated)", self:FormatNumber(d.fullBlock) .. "  (" .. d.fullBlockCount .. ")", 0.35,0.85,0.35, 1,1,1)
        if d.physicalAbsorb > 0 then
            MT:GetAnalysisTooltip():AddDoubleLine("Physical absorbed", self:FormatNumber(d.physicalAbsorb), 0.35,0.85,0.35, 1,1,1)
        end
        MT:GetAnalysisTooltip():AddLine(" ")
        MT:GetAnalysisTooltip():AddDoubleLine("Physical stopped", self:FormatNumber(physicalStopped), 0.35,0.85,0.35, 1,1,1)
        MT:GetAnalysisTooltip():AddDoubleLine("Physical damage taken", self:FormatNumber(d.physicalTaken), 1,0.35,0.3, 1,1,1)

    elseif mode == "MAGIC" then
        magicStopped = d.magicRaw - d.magicTaken
        if magicStopped < 0 then magicStopped = 0 end
        MT:GetAnalysisTooltip():AddDoubleLine("Raw magic incoming", self:FormatNumber(d.magicRaw), 0.75,0.45,1, 1,1,1)
        MT:GetAnalysisTooltip():AddDoubleLine("Magic resisted", self:FormatNumber(d.resist), 0.35,0.85,0.35, 1,1,1)
        if d.magicAbsorb > 0 then
            MT:GetAnalysisTooltip():AddDoubleLine("Magic absorbed", self:FormatNumber(d.magicAbsorb), 0.35,0.85,0.35, 1,1,1)
        end
        MT:GetAnalysisTooltip():AddDoubleLine("Magic damage taken", self:FormatNumber(d.magicTaken), 1,0.35,0.3, 1,1,1)
        names = {}
        for school in pairs(d.schools) do table.insert(names, school) end
        table.sort(names)
        if table.getn(names) > 0 then MT:GetAnalysisTooltip():AddLine(" ") end
        for i = 1, table.getn(names) do
            school = names[i]
            sd = d.schools[school]
            MT:GetAnalysisTooltip():AddDoubleLine(school, self:FormatNumber(sd.taken) .. " taken / " .. self:FormatNumber(sd.resisted) .. " resisted", 0.85,0.85,0.85, 1,1,1)
        end
        MT:GetAnalysisTooltip():AddLine(" ")
        MT:GetAnalysisTooltip():AddDoubleLine("Magic stopped", self:FormatNumber(magicStopped), 0.35,0.85,0.35, 1,1,1)

    else
        MT:GetAnalysisTooltip():AddDoubleLine("Raw incoming", self:FormatNumber(d.raw), 0.35,0.75,1, 1,1,1)
        MT:GetAnalysisTooltip():AddDoubleLine("Raw physical", self:FormatNumber(d.physicalRaw), 0.85,0.85,0.85, 1,1,1)
        MT:GetAnalysisTooltip():AddDoubleLine("Raw magic", self:FormatNumber(d.magicRaw), 0.85,0.85,0.85, 1,1,1)
        MT:GetAnalysisTooltip():AddLine(" ")
        MT:GetAnalysisTooltip():AddDoubleLine("Armor", self:FormatNumber(d.armor), 0.35,0.85,0.35, 1,1,1)
        MT:GetAnalysisTooltip():AddDoubleLine("Avoidance", self:FormatNumber(d.avoidance), 0.35,0.85,0.35, 1,1,1)
        MT:GetAnalysisTooltip():AddDoubleLine("Block", self:FormatNumber(d.block), 0.35,0.85,0.35, 1,1,1)
        MT:GetAnalysisTooltip():AddDoubleLine("Resisted", self:FormatNumber(d.resist), 0.35,0.85,0.35, 1,1,1)
        MT:GetAnalysisTooltip():AddDoubleLine("Absorbed", self:FormatNumber(d.absorb), 0.35,0.85,0.35, 1,1,1)
        MT:GetAnalysisTooltip():AddLine(" ")
        MT:GetAnalysisTooltip():AddDoubleLine("Damage stopped", self:FormatNumber(d.raw - d.taken), 0.35,0.85,0.35, 1,1,1)
        MT:GetAnalysisTooltip():AddDoubleLine("Damage taken", self:FormatNumber(d.taken), 1,0.35,0.3, 1,1,1)
        MT:GetAnalysisTooltip():AddDoubleLine("Events", tostring(d.events), 0.85,0.85,0.85, 1,1,1)
    end
    MT:GetAnalysisTooltip():Show()
end

function MT:SelectTimelineBucket(bucket)
    if not bucket then return end
    self.timelineSelection = {
        firstSecond = bucket.firstSecond or 0,
        lastSecond = bucket.lastSecond or bucket.firstSecond or 0,
        mode = self.timelineMode or "RAW"
    }
    self:SyncPersistentData()
    self:UpdateTimelineWindow()
end

function MT:OpenTimelineDetails(bucket)
    if not bucket then return end
    self:SelectTimelineBucket(bucket)
    local firstSecond = bucket.firstSecond or 0
    local lastSecond = bucket.lastSecond or firstSecond
    local mode = self.timelineMode or "RAW"
    local label
    if lastSecond > firstSecond then
        label = format("%s %ds-%ds", mode, firstSecond, lastSecond)
    else
        label = format("%s %ds", mode, firstSecond)
    end
    self.detailsFilter = {
        kind = "TIMELINE",
        firstSecond = firstSecond,
        lastSecond = lastSecond,
        mode = mode,
        label = label
    }
    self.detailsSelectedEnemy = nil
    self.detailsEnemyPage = 1
    self.detailsAbilityPage = 1
    local frame = self:CreateDetailsWindow()
    frame:Show()
    self:UpdateDetailsWindow()
end

function MT:UpdateTimelineWindow()
    local frame = self.timelineFrame
    if not frame then return end
    local timeline = self:GetDisplayTimeline() or {}
    local startSecond, maxSecond = self:GetTimelineRange(timeline)
    local totalSeconds = maxSecond - startSecond + 1
    if totalSeconds < 1 then totalSeconds = 1 end

    local availableBars = table.getn(frame.bars)
    local barCount = totalSeconds
    if barCount > availableBars then barCount = availableBars end
    local secondsPerBar = math.ceil(totalSeconds / barCount)
    if secondsPerBar < 1 then secondsPerBar = 1 end

    local displayBuckets = {}
    local i, firstSecond, lastSecond, bucket, value
    for i = 1, barCount do
        firstSecond = startSecond + ((i - 1) * secondsPerBar)
        lastSecond = firstSecond + secondsPerBar - 1
        if lastSecond > maxSecond then lastSecond = maxSecond end
        bucket = self:AggregateTimelineBucket(timeline, firstSecond, lastSecond)

        -- Rebuild the outcome split from the saved event stream.  Older saved
        -- timeline buckets may not contain physicalTaken/magicTaken, and those
        -- missing fields made PHYSICAL and MAGIC appear entirely green even
        -- though the generic RAW bucket still knew the total damage taken.
        -- Events are the authoritative source for mode-specific outcomes.
        local details = self:GetTimelineDetails(firstSecond, lastSecond)
        if details and details.events and details.events > 0 then
            bucket.raw = details.raw or bucket.raw
            bucket.physicalRaw = details.physicalRaw or bucket.physicalRaw
            bucket.magicRaw = details.magicRaw or bucket.magicRaw
            bucket.taken = details.taken or bucket.taken
            bucket.physicalTaken = details.physicalTaken or bucket.physicalTaken
            bucket.magicTaken = details.magicTaken or bucket.magicTaken
            bucket.armor = details.armor or bucket.armor
            bucket.block = details.block or bucket.block
            bucket.avoidance = details.avoidance or bucket.avoidance
            bucket.resist = details.resist or bucket.resist
            bucket.absorb = details.absorb or bucket.absorb
            bucket.events = details.events or bucket.events
        end

        displayBuckets[i] = bucket
    end

    local maxValue = 1
    for i = 1, barCount do
        bucket = displayBuckets[i]
        value = TimelineValue(bucket, self.timelineMode)
        if value > maxValue then
            maxValue = value
        end
    end

    frame.modeButton:SetText("View: " .. self.timelineMode)
    if secondsPerBar > 1 then
        frame.rangeText:SetText(format("%ds - %ds  (%ds/bar)", startSecond, maxSecond, secondsPerBar))
    else
        frame.rangeText:SetText(format("%ds - %ds", startSecond, maxSecond))
    end
    frame.maxText:SetText(self:FormatNumber(maxValue))
    frame.midText:SetText(self:FormatNumber(maxValue / 2))

    local graphHeight = 177
    local graphWidth = 359
    local spacing = 1
    local barWidth = floor((graphWidth - ((barCount - 1) * spacing)) / barCount)
    if barWidth < 1 then barWidth = 1 end
    local usedWidth = (barWidth * barCount) + ((barCount - 1) * spacing)
    local leftPad = floor((graphWidth - usedWidth) / 2) + 3

    for i = 1, table.getn(frame.bars) do
        local bar = frame.bars[i]
        if i <= barCount then
            bucket = displayBuckets[i]
            value = TimelineValue(bucket, self.timelineMode)
            local height = floor((value / maxValue) * graphHeight)
            if height < 1 and value > 0 then height = 1 end
            bar:SetWidth(barWidth)
            bar:SetHeight(height > 0 and height or 1)
            bar:ClearAllPoints()
            bar:SetPoint("BOTTOMLEFT", frame.graph, "BOTTOMLEFT", leftPad + ((i - 1) * (barWidth + spacing)), 1)
            bar.second = bucket.firstSecond
            bar.bucket = bucket

            -- True stacked outcome bar:
            -- green is the portion stopped; red is the portion that reached health.
            local mode = self.timelineMode or "RAW"
            local overlayTaken = 0
            if mode == "PHYSICAL" then
                overlayTaken = bucket.physicalTaken or 0
            elseif mode == "MAGIC" then
                overlayTaken = bucket.magicTaken or 0
            else
                overlayTaken = bucket.taken or 0
            end
            if overlayTaken < 0 then overlayTaken = 0 end
            if overlayTaken > value then overlayTaken = value end

            local stoppedValue = value - overlayTaken
            local stoppedHeight = floor((stoppedValue / maxValue) * graphHeight)
            local takenHeight = height - stoppedHeight
            if stoppedValue > 0 and stoppedHeight < 1 then stoppedHeight = 1 end
            if overlayTaken > 0 and takenHeight < 1 then takenHeight = 1 end
            if stoppedHeight + takenHeight > height then
                if takenHeight > 0 then
                    stoppedHeight = height - takenHeight
                else
                    stoppedHeight = height
                end
            end
            if stoppedHeight < 0 then stoppedHeight = 0 end

            bar.texture:ClearAllPoints()
            bar.texture:SetWidth(barWidth)
            bar.texture:SetHeight(stoppedHeight > 0 and stoppedHeight or 1)
            bar.texture:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 0, 0)
            bar.texture:SetTexture(0.20, 0.85, 0.30, 0.88)
            if stoppedHeight > 0 then bar.texture:Show() else bar.texture:Hide() end

            if value > 0 then bar:Show() else bar:Hide() end

            if overlayTaken > 0 then
                bar.taken:SetWidth(barWidth)
                bar.taken:SetHeight(takenHeight)
                bar.taken:ClearAllPoints()
                bar.taken:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 0, stoppedHeight)
                bar.taken:Show()
            else
                bar.taken:Hide()
            end
        else
            bar:Hide()
            bar.taken:Hide()
            bar.bucket = nil
        end
    end

    if frame.cursor then
        frame.cursor:Hide()
        local selection = self.timelineSelection
        if selection then
            for i = 1, barCount do
                bucket = displayBuckets[i]
                if bucket and selection.firstSecond <= (bucket.lastSecond or bucket.firstSecond) and selection.lastSecond >= (bucket.firstSecond or 0) then
                    local bar = frame.bars[i]
                    frame.cursor:ClearAllPoints()
                    frame.cursor:SetPoint("BOTTOM", bar, "BOTTOM", 0, -1)
                    frame.cursor:SetHeight(graphHeight + 5)
                    frame.cursor:Show()
                    break
                end
            end
        end
    end

    local legends = {
        RAW = "RAW: green was stopped; red reached your health",
        PHYSICAL = "PHYSICAL: armor, avoidance and blocks are green; physical damage taken is red",
        MAGIC = "MAGIC: resisted or absorbed damage is green; magic damage taken is red"
    }
    frame.legend:SetText((legends[self.timelineMode] or legends.RAW) .. "  |  Click a bar for details")

    if self.currentView == "OVERALL" then
        frame.title:SetText("Mitigation Timeline - Overall")
    elseif type(self.currentView) == "number" then
        frame.title:SetText("Mitigation Timeline - " .. self:GetViewLabel())
    elseif self.inCombat then
        frame.title:SetText("Mitigation Timeline - " .. self:GetViewLabel())
    else
        frame.title:SetText("Mitigation Timeline - " .. self:GetViewLabel())
    end
end

function MT:CreateTimelineWindow()
    if self.timelineFrame then return self.timelineFrame end
    local frame = CreateFrame("Frame", "MainTankTimelineFrame", UIParent)
    frame:SetWidth(420)
    frame:SetHeight(275)
    RestoreWindowPosition(frame, "timeline", "CENTER", "CENTER", -40, -190)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function() this:StartMoving() end)
    frame:SetScript("OnDragStop", function() this:StopMovingOrSizing(); SaveWindowPosition(this, "timeline") end)
    frame:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = {left = 4, right = 4, top = 4, bottom = 4}
    })
    frame:SetBackdropColor(0.04, 0.04, 0.07, 0.95)

    frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.title:SetPoint("TOP", frame, "TOP", 0, -10)
    frame.title:SetText("Mitigation Timeline")

    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -3, -3)

    frame.modeButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.modeButton:SetWidth(105)
    frame.modeButton:SetHeight(20)
    frame.modeButton:SetPoint("TOPLEFT", frame, "TOPLEFT", 14, -35)
    frame.modeButton:SetText("View: RAW")
    frame.modeButton:SetScript("OnClick", function() MT:CycleTimelineMode() end)
    -- FR1b: ensure the initial View button never exposes UIPanelButtonTemplate artwork.
    StyleLegacyButton(frame.modeButton)

    frame.rangeText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.rangeText:SetPoint("TOP", frame, "TOP", 0, -40)

    local live = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    live:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -16, -40)
    live:SetText("1 sec data")

    frame.graph = CreateFrame("Frame", nil, frame)
    frame.graph:SetPoint("TOPLEFT", frame, "TOPLEFT", 35, -68)
    frame.graph:SetWidth(365)
    frame.graph:SetHeight(180)
    frame.graph:SetBackdrop({bgFile = "Interface\\Tooltips\\UI-Tooltip-Background"})
    frame.graph:SetBackdrop(MT_LEGACY_BACKDROP)
    frame.graph:SetBackdropColor(0.015, 0.015, 0.015, 0.85)
    frame.graph:SetBackdropBorderColor(0, 0, 0, 1)

    frame.cursor = frame.graph:CreateTexture(nil, "OVERLAY")
    frame.cursor:SetWidth(2)
    frame.cursor:SetTexture(1.00, 0.82, 0.10, 0.95)
    frame.cursor:Hide()

    frame.maxText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.maxText:SetPoint("TOPRIGHT", frame.graph, "TOPLEFT", -4, 0)
    frame.midText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.midText:SetPoint("RIGHT", frame.graph, "LEFT", -4, 0)
    local zero = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    zero:SetPoint("BOTTOMRIGHT", frame.graph, "BOTTOMLEFT", -4, 0)
    zero:SetText("0")

    frame.legend = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.legend:SetPoint("BOTTOM", frame, "BOTTOM", 0, 9)
    frame.legend:SetText("RAW: green was stopped; red reached your health  |  Click a bar for details")

    frame.bars = {}
    local i
    for i = 1, 60 do
        local hit = CreateFrame("Frame", nil, frame.graph)
        hit:SetWidth(5)
        hit:SetHeight(1)
        hit:EnableMouse(true)
        hit.texture = hit:CreateTexture(nil, "ARTWORK")
        hit.texture:SetAllPoints(hit)
        hit.texture:SetTexture(0.20, 0.85, 0.30, 0.88)
        hit:SetScript("OnEnter", function()
            if this.bucket then MT:ShowTimelineTooltip(this, this.second, this.bucket) end
        end)
        hit:SetScript("OnLeave", function() MT:HideAnalysisTooltip() end)
        hit:SetScript("OnMouseUp", function()
            if this.bucket then
                MT:HideAnalysisTooltip()
                MT:OpenTimelineDetails(this.bucket)
            end
        end)

        -- Keep the red segment on the same child frame as the green segment.
        -- In the Vanilla renderer, child frames draw above textures owned by
        -- their parent, so a parent-owned red texture was being hidden by the
        -- green bar even though its height was calculated correctly.
        hit.taken = hit:CreateTexture(nil, "OVERLAY")
        hit.taken:SetTexture(1.00, 0.20, 0.16, 0.94)
        hit.taken:Hide()
        frame.bars[i] = hit
    end

    FinalizeLegacyWindow(frame)
    self.timelineFrame = frame
    frame:Hide()
    return frame
end

function MT:ToggleTimeline()
    local frame = self:CreateTimelineWindow()
    if frame:IsVisible() then
        frame:Hide()
    else
        frame:Show()
        self:UpdateTimelineWindow()
    end
end



local PIE_MODES = {"RAW", "PHYSICAL", "MAGIC"}
local PIE_COLORS = {
    -- High-contrast semantic palette (RC6l). These colors are intentionally
    -- far apart so adjacent mitigation slices stay readable on pfUI's dark skin.
    Armor = {0.20, 0.55, 1.00},
    ["Flat DR"] = {1.00, 0.82, 0.10},
    ["Physical DR"] = {1.00, 0.38, 0.08},
    ["Magic DR"] = {0.72, 0.30, 1.00},
    Avoidance = {0.20, 0.90, 0.30},
    Blocks = {0.10, 0.90, 0.90},
    Resists = {0.70, 0.30, 1.00},
    Absorbs = {1.00, 0.35, 0.75},
    Dodge = {0.20, 0.85, 1.00},
    Parry = {0.30, 0.65, 1.00},
    Miss = {0.55, 0.80, 1.00},
    ["Full Block"] = {1.00, 0.65, 0.15},
    ["Partial Block"] = {0.90, 0.45, 0.10},
    Holy = {1.00, 0.90, 0.45},
    Fire = {1.00, 0.30, 0.10},
    Nature = {0.30, 0.90, 0.30},
    Frost = {0.35, 0.70, 1.00},
    Shadow = {0.65, 0.30, 0.90},
    Arcane = {0.85, 0.45, 1.00},
    Unknown = {0.72, 0.72, 0.78},
    Other = {0.65, 0.65, 0.65}
}

local function AddPieEntry(entries, label, value, filterKind, filterValue)
    value = value or 0
    if value <= 0 then return end
    table.insert(entries, {
        label = label,
        value = value,
        color = PIE_COLORS[label] or PIE_COLORS.Other,
        filterKind = filterKind,
        filterValue = filterValue or label
    })
end

function MT:GetPieData(mode)
    local data = self:GetDisplayData() or NewData()
    local entries = {}
    if mode == "PHYSICAL" then
        AddPieEntry(entries, "Dodge", data.dodgedEstimated, "KIND", "Dodge")
        AddPieEntry(entries, "Parry", data.parriedEstimated, "KIND", "Parry")
        AddPieEntry(entries, "Miss", data.missedEstimated, "KIND", "Miss")
        AddPieEntry(entries, "Full Block", data.fullBlockedEstimated, "KIND", "FullBlock")
        AddPieEntry(entries, "Partial Block", data.blocked, "PARTIAL_BLOCK", "Partial Block")
    elseif mode == "MAGIC" then
        local school, bucket
        local order = {"Holy", "Fire", "Nature", "Frost", "Shadow", "Arcane", "Unknown"}
        local i
        for i = 1, table.getn(order) do
            school = order[i]
            bucket = data.schools and data.schools[school]
            if bucket then
                AddPieEntry(entries, school, (bucket.partial or 0) + (bucket.fullEstimated or 0), "SCHOOL", school)
            end
        end
    else
        AddPieEntry(entries, "Armor", data.armorReduced, "ARMOR", "Armor")
        AddPieEntry(entries, "Avoidance", (data.dodgedEstimated or 0) + (data.parriedEstimated or 0) + (data.missedEstimated or 0), "AVOIDANCE", "Avoidance")
        AddPieEntry(entries, "Blocks", (data.blocked or 0) + (data.fullBlockedEstimated or 0), "BLOCK", "Blocks")
        AddPieEntry(entries, "Resists", (data.resistedPartial or 0) + (data.resistedFullEstimated or 0), "RESIST", "Resists")
        AddPieEntry(entries, "Absorbs", data.absorbed, "ABSORB", "Absorbs")
    end
    return entries
end

function MT:CyclePieMode()
    local index = 1
    local i
    for i = 1, table.getn(PIE_MODES) do
        if PIE_MODES[i] == self.pieMode then index = i break end
    end
    index = index + 1
    if index > table.getn(PIE_MODES) then index = 1 end
    self.pieMode = PIE_MODES[index]
    self:UpdatePieWindow()
end

function MT:ShowPieTooltip(owner)
    if not owner or not owner.entry then return end
    local frame = self.pieFrame
    local total = frame and frame.totalValue or 0
    local entry = owner.entry
    local pct = total > 0 and ((entry.value / total) * 100) or 0
    MT:GetAnalysisTooltip():SetOwner(owner, "ANCHOR_CURSOR")
    MT:GetAnalysisTooltip():SetText(entry.label, entry.color[1], entry.color[2], entry.color[3])
    MT:GetAnalysisTooltip():AddDoubleLine("Damage prevented", self:FormatNumber(entry.value), 0.85,0.85,0.85, 1,1,1)
    MT:GetAnalysisTooltip():AddDoubleLine("Share", format("%.1f%%", pct), 0.85,0.85,0.85, 1,1,1)
    MT:GetAnalysisTooltip():Show()
end

function MT:OpenPieDetails(entry)
    if not entry then return end
    self.detailsFilter = {
        kind = entry.filterKind,
        value = entry.filterValue,
        label = entry.label
    }
    self.detailsSelectedEnemy = nil
    self.detailsEnemyPage = 1
    self.detailsAbilityPage = 1
    local frame = self:CreateDetailsWindow()
    frame:Show()
    self:UpdateDetailsWindow()
end

function MT:ClearDetailsFilter()
    self.detailsFilter = nil
    self.detailsSelectedEnemy = nil
    self.detailsEnemyPage = 1
    self.detailsAbilityPage = 1
    self.detailsEventPage = 1
    self.detailsSelectedEvent = nil
    self:UpdateDetailsWindow()
end

function MT:EventMatchesDetailsFilter(event)
    local filter = self.detailsFilter
    if not filter or not filter.kind then return true end
    if filter.kind == "TIMELINE" then
        local eventSecond = floor(event.time or 0)
        if eventSecond < (filter.firstSecond or 0) or eventSecond > (filter.lastSecond or filter.firstSecond or 0) then
            return false
        end
        if filter.mode == "PHYSICAL" then
            return (event.school or "Physical") == "Physical"
        elseif filter.mode == "MAGIC" then
            return (event.school or "Physical") ~= "Physical"
        end
        return true
    end
    if filter.kind == "ARMOR" then return (event.armor or 0) > 0 end
    if filter.kind == "AVOIDANCE" then return (event.avoidance or 0) > 0 end
    if filter.kind == "BLOCK" then return (event.block or 0) > 0 end
    if filter.kind == "RESIST" then return (event.resist or 0) > 0 end
    if filter.kind == "ABSORB" then return (event.absorb or 0) > 0 end
    if filter.kind == "CRIT_CRUSH" then return event.critical or event.crushing end
    if filter.kind == "KIND" then return event.kind == filter.value end
    if filter.kind == "PARTIAL_BLOCK" then
        return (event.block or 0) > 0 and event.kind ~= "FullBlock"
    end
    if filter.kind == "PHYSICAL_PARTIAL_BLOCK" then
        return (event.block or 0) > 0 and event.kind ~= "FullBlock" and (event.school or "Physical") == "Physical"
    end
    if filter.kind == "PHYSICAL_FULL_BLOCK" then
        return event.kind == "FullBlock" and (event.school or "Physical") == "Physical"
    end
    if filter.kind == "MAGIC_BLOCK" then
        return (event.block or 0) > 0 and (event.school or "Physical") ~= "Physical"
    end
    if filter.kind == "SCHOOL" then return (event.school or "Unknown") == filter.value end
    return true
end


local function ResetFilledPie(frame)
    if frame.pieGraph and MTPie then MTPie:Reset(frame.pieGraph) end
    frame.entryEnds = {}
    frame.hoverEntry = nil
end

local function DrawFilledPie(frame, entries, total)
    ResetFilledPie(frame)
    if not frame.pieGraph then
        frame.pieGraph = MTPie:Create(frame.ring, frame.ring:GetWidth(), frame.ring:GetHeight())
        frame.pieGraph:SetPoint("CENTER", frame.ring, "CENTER", 0, 0)
    end
    MTPie:Draw(frame.pieGraph, entries, total)
    local i
    for i = 1, table.getn(frame.pieGraph.sections or {}) do
        frame.entryEnds[i] = frame.pieGraph.sections[i].endAngle or 360
    end
end

local function GetPieEntryUnderMouse(frame)
    if not MouseIsOver(frame.ring) or not frame.entryEnds then return nil end
    local cx, cy = frame.ring:GetCenter()
    if not cx or not cy then return nil end
    local scale = frame.ring:GetEffectiveScale()
    local mx, my = GetCursorPosition()
    mx = mx / scale
    my = my / scale
    local dx = mx - cx
    local dy = my - cy
    local radius = frame.ring:GetWidth() / 2
    if (dx * dx + dy * dy) > (radius * radius) then return nil end

    local angle
    if dx == 0 then
        if dy >= 0 then angle = 0 else angle = 180 end
    else
        angle = 90 - math.deg(math.atan(dy / dx))
        if dx < 0 then angle = angle + 180 end
    end
    if angle < 0 then angle = angle + 360 end
    if angle >= 360 then angle = angle - 360 end

    local i
    for i = 1, table.getn(frame.entryEnds) do
        if angle <= frame.entryEnds[i] then return frame.entries and frame.entries[i] or nil end
    end
    return nil
end

function MT:UpdatePieWindow()
    local frame = self.pieFrame
    if not frame then return end
    local entries = self:GetPieData(self.pieMode)
    local total = 0
    local i
    for i = 1, table.getn(entries) do total = total + entries[i].value end
    frame.totalValue = total
    frame.entries = entries
    frame.modeButton:SetText("View: " .. self.pieMode)

    -- Standalone GraphLib-derived pie renderer. This deliberately avoids
    -- AceLibrary registration and uses only the fractional pie textures.
    DrawFilledPie(frame, entries, total)

    local entry
    for i = 1, table.getn(frame.legendRows) do
        local row = frame.legendRows[i]
        entry = entries[i]
        if entry then
            row.entry = entry
            local pct = total > 0 and ((entry.value / total) * 100) or 0
            row.swatch:SetTexture(entry.color[1], entry.color[2], entry.color[3], 1)
            row.label:SetText(entry.label)
            row.value:SetText(self:FormatNumber(entry.value) .. format("  %.1f%%", pct))
            row:Show()
        else
            row.entry = nil
            row:Hide()
        end
    end

    frame.totalText:SetText("Prevented: " .. self:FormatNumber(total))
    frame.title:SetText("Mitigation Pie - " .. self:GetViewLabel())
end

function MT:CreatePieWindow()
    if self.pieFrame then return self.pieFrame end
    local frame = CreateFrame("Frame", "MainTankPieFrame", UIParent)
    frame:SetWidth(385)
    frame:SetHeight(285)
    RestoreWindowPosition(frame, "pie", "CENTER", "CENTER", 400, -190)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function() this:StartMoving() end)
    frame:SetScript("OnDragStop", function() this:StopMovingOrSizing(); SaveWindowPosition(this, "pie") end)
    frame:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = {left = 4, right = 4, top = 4, bottom = 4}
    })
    frame:SetBackdropColor(0.04, 0.04, 0.07, 0.95)

    frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.title:SetPoint("TOP", frame, "TOP", 0, -10)
    frame.title:SetText("Mitigation Pie")
    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -3, -3)

    frame.modeButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.modeButton:SetWidth(110)
    frame.modeButton:SetHeight(20)
    frame.modeButton:SetPoint("TOPLEFT", frame, "TOPLEFT", 14, -35)
    frame.modeButton:SetText("View: RAW")
    frame.modeButton:SetScript("OnClick", function() MT:CyclePieMode() end)
    -- FR1b: RC_CreatePageFrame is finalized before page-specific controls exist.
    -- Style this immediately so its first render matches subsequent refreshed states.
    StyleLegacyButton(frame.modeButton)

    frame.ring = CreateFrame("Frame", nil, frame)
    frame.ring:SetWidth(150)
    frame.ring:SetHeight(150)
    frame.ring:SetPoint("TOPLEFT", frame, "TOPLEFT", 15, -66)
    frame.ring:EnableMouse(true)
    frame.ring:SetFrameLevel(frame:GetFrameLevel() + 2)

    frame.pieTextures = {}
    frame.pieUsed = 0
    frame.entryEnds = {}
    frame.entries = {}
    frame.hoverEntry = nil

    -- GraphLib's pie hit testing, adapted to a plain frame. Hovering changes
    -- only the tooltip; the texture colors remain stable and crisp.
    frame.ring:SetScript("OnUpdate", function()
        local entry = GetPieEntryUnderMouse(frame)
        if entry ~= frame.hoverEntry then
            frame.hoverEntry = entry
            MT:HideAnalysisTooltip()
            if entry then
                this.entry = entry
                MT:ShowPieTooltip(this)
            else
                this.entry = nil
            end
        end
    end)
    frame.ring:SetScript("OnMouseUp", function()
        local entry = GetPieEntryUnderMouse(frame)
        if entry then MT:OpenPieDetails(entry) end
    end)
    frame.ring:SetScript("OnLeave", function()
        frame.hoverEntry = nil
        this.entry = nil
        MT:HideAnalysisTooltip()
    end)

    frame.legendRows = {}
    local i
    for i = 1, 7 do
        local row = CreateFrame("Frame", nil, frame)
        row:SetWidth(195)
        row:SetHeight(22)
        row:EnableMouse(true)
        row:SetScript("OnEnter", function() MT:ShowPieTooltip(this) end)
        row:SetScript("OnLeave", function() MT:HideAnalysisTooltip() end)
        row:SetScript("OnMouseUp", function() if this.entry then MT:OpenPieDetails(this.entry) end end)
        row:SetPoint("TOPLEFT", frame, "TOPLEFT", 177, -64 - ((i - 1) * 27))
        row.swatch = row:CreateTexture(nil, "ARTWORK")
        row.swatch:SetWidth(12)
        row.swatch:SetHeight(12)
        row.swatch:SetPoint("LEFT", row, "LEFT", 0, 0)
        row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.label:SetPoint("LEFT", row.swatch, "RIGHT", 6, 0)
        row.label:SetWidth(78)
        row.label:SetJustifyH("LEFT")
        row.value = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.value:SetPoint("RIGHT", row, "RIGHT", 0, 0)
        row.value:SetWidth(95)
        row.value:SetJustifyH("RIGHT")
        frame.legendRows[i] = row
    end

    frame.totalText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.totalText:SetPoint("TOP", frame.ring, "BOTTOM", 0, -7)
    frame.totalText:SetText("Prevented: 0")

    local note = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    note:SetPoint("BOTTOM", frame, "BOTTOM", 0, 10)
    note:SetText("Click a slice or legend row for enemy and ability details")

    FinalizeLegacyWindow(frame)
    self.pieFrame = frame
    frame:Hide()
    return frame
end

function MT:TogglePie()
    local frame = self:CreatePieWindow()
    if frame:IsVisible() then
        frame:Hide()
    else
        frame:Show()
        self:UpdatePieWindow()
    end
end


local function NewDetailAggregate(name)
    return {
        name = name or "Unknown",
        raw = 0,
        physicalRaw = 0,
        magicRaw = 0,
        armor = 0,
        block = 0,
        avoidance = 0,
        resist = 0,
        absorb = 0,
        taken = 0,
        physicalTaken = 0,
        magicTaken = 0,
        events = 0,
        estimatedEvents = 0,
        schools = {},
        abilities = {}
    }
end

local function AddDetailEvent(aggregate, event)
    aggregate.raw = aggregate.raw + (event.raw or 0)
    aggregate.physicalRaw = aggregate.physicalRaw + (event.physicalRaw or 0)
    aggregate.magicRaw = aggregate.magicRaw + (event.magicRaw or 0)
    aggregate.armor = aggregate.armor + (event.armor or 0)
    aggregate.block = aggregate.block + (event.block or 0)
    aggregate.avoidance = aggregate.avoidance + (event.avoidance or 0)
    aggregate.resist = aggregate.resist + (event.resist or 0)
    aggregate.absorb = aggregate.absorb + (event.absorb or 0)
    aggregate.taken = aggregate.taken + (event.taken or 0)
    if event.school == "Physical" then
        aggregate.physicalTaken = aggregate.physicalTaken + (event.taken or 0)
    else
        aggregate.magicTaken = aggregate.magicTaken + (event.taken or 0)
    end
    aggregate.events = aggregate.events + 1
    if event.estimated then aggregate.estimatedEvents = aggregate.estimatedEvents + 1 end

    local school = event.school or "Unknown"
    if not aggregate.schools[school] then
        aggregate.schools[school] = {raw = 0, taken = 0, resisted = 0, absorbed = 0, events = 0}
    end
    local schoolData = aggregate.schools[school]
    schoolData.raw = schoolData.raw + (event.raw or 0)
    schoolData.taken = schoolData.taken + (event.taken or 0)
    schoolData.resisted = schoolData.resisted + (event.resist or 0)
    schoolData.absorbed = schoolData.absorbed + (event.absorb or 0)
    schoolData.events = schoolData.events + 1
end

function MT:BuildEnemyAbilityDetails()
    local events = self:GetDisplayEvents() or {}
    local enemyMap = {}
    local i, event, enemyName, abilityName, enemy, ability
    for i = 1, table.getn(events) do
        event = events[i]
        if self:EventMatchesDetailsFilter(event) then
        enemyName = event.source or "Unknown"
        abilityName = event.ability or "Unknown"
        if not enemyMap[enemyName] then enemyMap[enemyName] = NewDetailAggregate(enemyName) end
        enemy = enemyMap[enemyName]
        AddDetailEvent(enemy, event)
        if not enemy.abilities[abilityName] then
            enemy.abilities[abilityName] = NewDetailAggregate(abilityName)
            enemy.abilities[abilityName].school = event.school or "Unknown"
        end
        ability = enemy.abilities[abilityName]
        if ability.school == "Unknown" and event.school then ability.school = event.school end
        AddDetailEvent(ability, event)
        end
    end

    local enemies = {}
    local name, data
    for name, data in pairs(enemyMap) do table.insert(enemies, data) end
    table.sort(enemies, function(a, b)
        if a.raw == b.raw then return a.name < b.name end
        return a.raw > b.raw
    end)
    return enemies, enemyMap
end

function MT:GetSelectedDetailEnemy(enemies, enemyMap)
    local selected = self.detailsSelectedEnemy and enemyMap[self.detailsSelectedEnemy] or nil
    -- Highlights can open Events as an encounter-wide Critical/Crushing filter.
    -- Keep no enemy selected initially so the event list truly contains every
    -- matching event in the fight; clicking an enemy still narrows normally.
    if not selected and self.detailsFilter and self.detailsFilter.kind == "CRIT_CRUSH" and not self.detailsSelectedEnemy then
        return nil
    end
    if not selected and table.getn(enemies) > 0 then
        selected = enemies[1]
        self.detailsSelectedEnemy = selected.name
    end
    return selected
end

function MT:GetDetailAbilities(enemy)
    local abilities = {}
    if not enemy then return abilities end
    local name, data
    for name, data in pairs(enemy.abilities or {}) do table.insert(abilities, data) end
    table.sort(abilities, function(a, b)
        if a.raw == b.raw then return a.name < b.name end
        return a.raw > b.raw
    end)
    return abilities
end

function MT:ShowDetailTooltip(owner, data, kind)
    if not data then return end
    local stopped = (data.raw or 0) - (data.taken or 0)
    if stopped < 0 then stopped = 0 end
    local pct = 0
    if (data.raw or 0) > 0 then pct = stopped / data.raw * 100 end
    MT:GetAnalysisTooltip():SetOwner(owner, "ANCHOR_RIGHT")
    MT:GetAnalysisTooltip():SetText(data.name or kind or "Details", 1, 0.82, 0)
    if kind then MT:GetAnalysisTooltip():AddLine(kind, 0.75, 0.85, 1) end
    if data.school then MT:GetAnalysisTooltip():AddDoubleLine("School", data.school, 0.8, 0.8, 0.8, 1, 1, 1) end
    MT:GetAnalysisTooltip():AddLine(" ")
    MT:GetAnalysisTooltip():AddDoubleLine("Raw incoming", self:FormatNumber(data.raw), 0.8, 0.8, 0.8, 1, 1, 1)
    MT:GetAnalysisTooltip():AddDoubleLine("Damage stopped", self:FormatNumber(stopped), 0.2, 1, 0.2, 0.2, 1, 0.2)
    MT:GetAnalysisTooltip():AddDoubleLine("Damage taken", self:FormatNumber(data.taken), 1, 0.3, 0.3, 1, 0.3, 0.3)
    MT:GetAnalysisTooltip():AddDoubleLine("Mitigation", format("%.1f%%", pct), 0.8, 0.8, 0.8, 1, 1, 1)
    MT:GetAnalysisTooltip():AddLine(" ")
    if (data.armor or 0) > 0 then MT:GetAnalysisTooltip():AddDoubleLine("Armor", self:FormatNumber(data.armor), 0.5, 1, 0.5, 1, 1, 1) end
    if (data.avoidance or 0) > 0 then MT:GetAnalysisTooltip():AddDoubleLine("Avoidance", self:FormatNumber(data.avoidance), 0.5, 1, 0.5, 1, 1, 1) end
    if (data.block or 0) > 0 then MT:GetAnalysisTooltip():AddDoubleLine("Block", self:FormatNumber(data.block), 0.5, 1, 0.5, 1, 1, 1) end
    if (data.resist or 0) > 0 then MT:GetAnalysisTooltip():AddDoubleLine("Resisted", self:FormatNumber(data.resist), 0.5, 1, 0.5, 1, 1, 1) end
    if (data.absorb or 0) > 0 then MT:GetAnalysisTooltip():AddDoubleLine("Absorbed", self:FormatNumber(data.absorb), 0.5, 1, 0.5, 1, 1, 1) end
    MT:GetAnalysisTooltip():AddDoubleLine("Events", tostring(data.events or 0), 0.8, 0.8, 0.8, 1, 1, 1)
    if (data.estimatedEvents or 0) > 0 then
        MT:GetAnalysisTooltip():AddDoubleLine("Estimated events", tostring(data.estimatedEvents), 0.8, 0.8, 0.8, 1, 0.82, 0)
    end
    MT:GetAnalysisTooltip():Show()
end


function MT:GetFilteredDetailEvents()
    local source = self:GetDisplayEvents() or {}
    local result = {}
    local i, event
    for i = 1, table.getn(source) do
        event = source[i]
        if self:EventMatchesDetailsFilter(event) and (not self.detailsSelectedEnemy or (event.source or "Unknown") == self.detailsSelectedEnemy) then
            table.insert(result, event)
        end
    end
    table.sort(result, function(a, b) return (a.time or 0) < (b.time or 0) end)
    return result
end

function MT:FormatEventOutcome(event)
    local parts = {}
    if event.crushing then table.insert(parts, "CRUSHING")
    elseif event.critical then table.insert(parts, "CRITICAL")
    elseif event.environmental then table.insert(parts, "ENVIRONMENT") end
    if (event.armor or 0) > 0 then table.insert(parts, "Armor " .. self:FormatNumber(event.armor)) end
    if (event.avoidance or 0) > 0 then table.insert(parts, (event.kind or "Avoid") .. " " .. self:FormatNumber(event.avoidance)) end
    if (event.block or 0) > 0 then table.insert(parts, "Block " .. self:FormatNumber(event.block)) end
    if (event.resist or 0) > 0 then table.insert(parts, "Resist " .. self:FormatNumber(event.resist)) end
    if (event.absorb or 0) > 0 then table.insert(parts, "Absorb " .. self:FormatNumber(event.absorb)) end
    if (event.taken or 0) > 0 then table.insert(parts, "Taken " .. self:FormatNumber(event.taken)) end
    if table.getn(parts) == 0 then table.insert(parts, event.kind or "No damage") end
    return table.concat(parts, "  ")
end

function MT:SelectReplayEvent(index)
    local events = self:GetFilteredDetailEvents()
    if table.getn(events) == 0 then self.detailsSelectedEvent = nil; return end
    if index < 1 then index = 1 end
    if index > table.getn(events) then index = table.getn(events) end
    self.detailsSelectedEvent = index
    local pageSize = self.detailsFrame and table.getn(self.detailsFrame.eventRows) or 6
    self.detailsEventPage = math.floor((index - 1) / pageSize) + 1
    self:UpdateDetailsWindow()
end

function MT:FormatEventInspector(event)
    if not event then return "Select an event below to inspect it." end
    local stopped = (event.raw or 0) - (event.taken or 0)
    if stopped < 0 then stopped = 0 end
    local pct = (event.raw or 0) > 0 and (stopped / event.raw * 100) or 0
    local flags = {}
    if event.critical then table.insert(flags, "CRITICAL") end
    if event.crushing then table.insert(flags, "CRUSHING") end
    if event.environmental then table.insert(flags, "ENVIRONMENT") end
    if event.estimated then table.insert(flags, "ESTIMATED") end
    if table.getn(flags) == 0 then table.insert(flags, "Exact combat event") end
    local line1 = format("%.2fs  %s - %s  [%s]", event.time or 0, event.source or "Unknown", event.ability or event.kind or "Unknown", event.school or "Unknown")
    local line2 = format("Raw %s   Taken %s   Stopped %s   Mitigation %.1f%%", self:FormatNumber(event.raw or 0), self:FormatNumber(event.taken or 0), self:FormatNumber(stopped), pct)
    local line3 = format("Armor %s   Avoid %s   Block %s   Resist %s   Absorb %s", self:FormatNumber(event.armor or 0), self:FormatNumber(event.avoidance or 0), self:FormatNumber(event.block or 0), self:FormatNumber(event.resist or 0), self:FormatNumber(event.absorb or 0))
    return line1 .. "\n" .. line2 .. "\n" .. line3 .. "\n" .. table.concat(flags, ", ")

end

function MT:JumpToEvent(event)
    if not event then return end
    local second = floor(event.time or 0)
    self.timelineSelection = {firstSecond = second, lastSecond = second, mode = self.timelineMode or "RAW"}
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
    local timeline = self:CreateTimelineWindow()
    timeline:Show()
    self:UpdateTimelineWindow()
    local details = self:CreateDetailsWindow()
    details:Show()
    self:UpdateDetailsWindow()
end

local function BiggestEntry(label, value, event)
    return {label = label, value = value or 0, event = event}
end

function MT:GetBiggestHits()
    local events = self:GetDisplayEvents() or {}
    local best = {raw=nil, taken=nil, armor=nil, block=nil, resist=nil, avoidance=nil, critical=nil, crushing=nil}
    local i, e
    for i = 1, table.getn(events) do
        e = events[i]
        if not best.raw or (e.raw or 0) > (best.raw.raw or 0) then best.raw = e end
        if not best.taken or (e.taken or 0) > (best.taken.taken or 0) then best.taken = e end
        if not best.armor or (e.armor or 0) > (best.armor.armor or 0) then best.armor = e end
        if not best.block or (e.block or 0) > (best.block.block or 0) then best.block = e end
        if not best.resist or (e.resist or 0) > (best.resist.resist or 0) then best.resist = e end
        if not best.avoidance or (e.avoidance or 0) > (best.avoidance.avoidance or 0) then best.avoidance = e end
        if e.critical and (not best.critical or (e.taken or 0) > (best.critical.taken or 0)) then best.critical = e end
        if e.crushing and (not best.crushing or (e.taken or 0) > (best.crushing.taken or 0)) then best.crushing = e end
    end
    local critValue = best.critical and (best.critical.taken or 0) or 0
    local crushValue = best.crushing and (best.crushing.taken or 0) or 0
    local flagEvent = best.critical
    if not flagEvent or (best.crushing and crushValue > critValue) then flagEvent = best.crushing end
    local flagEntry = BiggestEntry("Largest crit / crush hit", math.max(critValue, crushValue), flagEvent)
    flagEntry.filterKind = "CRIT_CRUSH"
    flagEntry.critValue = critValue
    flagEntry.crushValue = crushValue
    flagEntry.sourceText = "All Critical / Crushing events"

    return {
        BiggestEntry("Largest raw hit", best.raw and best.raw.raw, best.raw),
        BiggestEntry("Largest hit taken", best.taken and best.taken.taken, best.taken),
        BiggestEntry("Largest armor reduction", best.armor and best.armor.armor, best.armor),
        BiggestEntry("Largest block", best.block and best.block.block, best.block),
        BiggestEntry("Largest resist", best.resist and best.resist.resist, best.resist),
        BiggestEntry("Largest avoided hit", best.avoidance and best.avoidance.avoidance, best.avoidance),
        flagEntry
    }
end

function MT:UpdateBiggestWindow()
    local frame = self.biggestFrame
    if not frame then return end
    frame.title:SetText("Biggest Hits - " .. self:GetViewLabel())
    local entries = self:GetBiggestHits()
    local i, row, entry
    for i = 1, table.getn(frame.rows) do
        row = frame.rows[i]
        entry = entries[i]
        row.entry = entry
        if entry and entry.event and entry.value > 0 then
            row.label:SetText(entry.label)
            if entry.filterKind == "CRIT_CRUSH" then
                row.value:SetText(self:FormatNumber(entry.critValue or 0) .. " / " .. self:FormatNumber(entry.crushValue or 0))
                row.source:SetText(entry.sourceText or "Critical / Crushing events")
            else
                row.value:SetText(self:FormatNumber(entry.value))
                row.source:SetText(format("%.1fs  %s - %s", entry.event.time or 0, entry.event.source or "Unknown", entry.event.ability or entry.event.kind or "Unknown"))
            end
            row:Show()
        else
            row:Hide()
        end
    end
end

function MT:CreateBiggestWindow()
    if self.biggestFrame then return self.biggestFrame end
    local frame = CreateFrame("Frame", "MainTankBiggestFrame", UIParent)
    frame:SetWidth(390)
    frame:SetHeight(245)
    RestoreWindowPosition(frame, "biggest", "CENTER", "CENTER", 390, 120)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function() this:StartMoving() end)
    frame:SetScript("OnDragStop", function() this:StopMovingOrSizing(); SaveWindowPosition(this, "biggest") end)
    frame:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = {left = 4, right = 4, top = 4, bottom = 4}
    })
    frame:SetBackdropColor(0.04, 0.04, 0.07, 0.95)
    frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.title:SetPoint("TOP", frame, "TOP", 0, -10)
    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -3, -3)
    frame.rows = {}
    local i
    for i = 1, 7 do
        local row = CreateFrame("Button", nil, frame)
        row:SetWidth(354)
        row:SetHeight(29)
        row:SetPoint("TOPLEFT", frame, "TOPLEFT", 18, -38 - ((i - 1) * 31))
        row:EnableMouse(true)
        row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.label:SetPoint("TOPLEFT", row, "TOPLEFT", 2, -2)
        row.label:SetWidth(180)
        row.label:SetJustifyH("LEFT")
        row.value = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        row.value:SetPoint("TOPRIGHT", row, "TOPRIGHT", -2, -2)
        row.value:SetJustifyH("RIGHT")
        row.source = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.source:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 2, 1)
        row.source:SetWidth(345)
        row.source:SetJustifyH("LEFT")
        row:SetScript("OnClick", function() if this.entry and this.entry.event then MT:JumpToEvent(this.entry.event) end end)
        frame.rows[i] = row
    end
    local note = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    note:SetPoint("BOTTOM", frame, "BOTTOM", 0, 9)
    note:SetText("Click a record to jump to its Timeline second and Event Inspector")
    FinalizeLegacyWindow(frame)
    self.biggestFrame = frame
    frame:Hide()
    return frame
end

function MT:ToggleBiggest()
    local frame = self:CreateBiggestWindow()
    if frame:IsVisible() then
        frame:Hide()
    else
        frame:Show()
        self:UpdateBiggestWindow()
    end
end

function MT:UpdateDetailsWindow()
    local frame = self.detailsFrame
    if not frame then return end
    local enemies, enemyMap = self:BuildEnemyAbilityDetails()
    local selected = self:GetSelectedDetailEnemy(enemies, enemyMap)
    local abilities = self:GetDetailAbilities(selected)

    local enemyPageSize = table.getn(frame.enemyRows)
    local abilityPageSize = table.getn(frame.abilityRows)
    local enemyPages = math.max(1, math.ceil(table.getn(enemies) / enemyPageSize))
    local abilityPages = math.max(1, math.ceil(table.getn(abilities) / abilityPageSize))
    if self.detailsEnemyPage > enemyPages then self.detailsEnemyPage = enemyPages end
    if self.detailsEnemyPage < 1 then self.detailsEnemyPage = 1 end
    if self.detailsAbilityPage > abilityPages then self.detailsAbilityPage = abilityPages end
    if self.detailsAbilityPage < 1 then self.detailsAbilityPage = 1 end

    local titleView = "Last Fight"
    if self.currentView == "OVERALL" then titleView = "Overall"
    elseif type(self.currentView) == "number" then titleView = self:GetViewLabel()
    elseif self.inCombat then titleView = self:GetViewLabel()
    else titleView = self:GetViewLabel() end
    local filterText = ""
    if self.detailsFilter and self.detailsFilter.label then
        filterText = " - " .. self.detailsFilter.label
    end
    frame.title:SetText("Mitigation Details - " .. titleView .. filterText)
    if frame.clearFilter then
        if self.detailsFilter then frame.clearFilter:Show() else frame.clearFilter:Hide() end
    end

    local i, index, row, data
    local enemyStart = ((self.detailsEnemyPage - 1) * enemyPageSize) + 1
    for i = 1, enemyPageSize do
        row = frame.enemyRows[i]
        index = enemyStart + i - 1
        data = enemies[index]
        row.data = data
        if data then
            row.name:SetText(data.name)
            row.value:SetText(self:FormatNumber(data.raw) .. " / " .. self:FormatNumber(data.taken))
            row:Show()
            if selected and data.name == selected.name then row.highlight:Show() else row.highlight:Hide() end
        else
            row:Hide()
        end
    end
    frame.enemyPageText:SetText(self.detailsEnemyPage .. "/" .. enemyPages)
    if self.detailsEnemyPage <= 1 then frame.enemyPrev:Disable() else frame.enemyPrev:Enable() end
    if self.detailsEnemyPage >= enemyPages then frame.enemyNext:Disable() else frame.enemyNext:Enable() end

    if selected then
        local stopped = selected.raw - selected.taken
        if stopped < 0 then stopped = 0 end
        local pct = selected.raw > 0 and (stopped / selected.raw * 100) or 0
        frame.selectedName:SetText(selected.name)
        frame.summary:SetText("Raw " .. self:FormatNumber(selected.raw) .. "   Stopped " .. self:FormatNumber(stopped) .. "   Taken " .. self:FormatNumber(selected.taken) .. "   " .. format("%.1f%%", pct))
    else
        if self.detailsFilter and self.detailsFilter.kind == "CRIT_CRUSH" then
            frame.selectedName:SetText("All Critical / Crushing Events")
            frame.summary:SetText("All matching events in this fight. Select an enemy to narrow the list.")
        else
            frame.selectedName:SetText("No enemy data")
            frame.summary:SetText("Fight an enemy to populate details.")
        end
    end

    local abilityStart = ((self.detailsAbilityPage - 1) * abilityPageSize) + 1
    for i = 1, abilityPageSize do
        row = frame.abilityRows[i]
        index = abilityStart + i - 1
        data = abilities[index]
        row.data = data
        if data then
            row.name:SetText(data.name)
            row.school:SetText(data.school or "Unknown")
            row.raw:SetText(self:FormatNumber(data.raw))
            row.taken:SetText(self:FormatNumber(data.taken))
            row:Show()
        else
            row:Hide()
        end
    end
    frame.abilityPageText:SetText(self.detailsAbilityPage .. "/" .. abilityPages)
    if self.detailsAbilityPage <= 1 then frame.abilityPrev:Disable() else frame.abilityPrev:Enable() end
    if self.detailsAbilityPage >= abilityPages then frame.abilityNext:Disable() else frame.abilityNext:Enable() end

    local detailEvents = self:GetFilteredDetailEvents()
    local eventPageSize = table.getn(frame.eventRows or {})
    local eventPages = math.max(1, math.ceil(table.getn(detailEvents) / math.max(1, eventPageSize)))
    if self.detailsEventPage > eventPages then self.detailsEventPage = eventPages end
    if self.detailsEventPage < 1 then self.detailsEventPage = 1 end
    local eventStart = ((self.detailsEventPage - 1) * eventPageSize) + 1
    for i = 1, eventPageSize do
        local row = frame.eventRows[i]
        local eventIndex = eventStart + i - 1
        local event = detailEvents[eventIndex]
        row.eventIndex = eventIndex
        row.data = event
        if event then
            row.time:SetText(format("%.1f", event.time or 0))
            row.source:SetText(event.source or "Unknown")
            row.ability:SetText(event.ability or event.kind or "Unknown")
            row.outcome:SetText(self:FormatEventOutcome(event))
            if self.detailsSelectedEvent == eventIndex then row.highlight:Show() else row.highlight:Hide() end
            row:Show()
        else
            row.highlight:Hide(); row:Hide()
        end
    end
    frame.eventPageText:SetText(self.detailsEventPage .. "/" .. eventPages)
    if self.detailsEventPage <= 1 then frame.eventPrev:Disable() else frame.eventPrev:Enable() end
    if self.detailsEventPage >= eventPages then frame.eventNext:Disable() else frame.eventNext:Enable() end
    frame.replayCount:SetText(table.getn(detailEvents) .. " events")
    if self.detailsSelectedEvent and detailEvents[self.detailsSelectedEvent] then
        local e = detailEvents[self.detailsSelectedEvent]
        frame.replayText:SetText(self:FormatEventInspector(e))
        local second = floor(e.time or 0)
        self.timelineSelection = {firstSecond = second, lastSecond = second, mode = self.timelineMode or "RAW"}
        if self.timelineFrame and self.timelineFrame:IsVisible() then self:UpdateTimelineWindow() end
    else
        frame.replayText:SetText("Select an event below to inspect its complete damage flow.")
    end
    if not self.detailsSelectedEvent or self.detailsSelectedEvent <= 1 then frame.replayPrev:Disable() else frame.replayPrev:Enable() end
    if not self.detailsSelectedEvent or self.detailsSelectedEvent >= table.getn(detailEvents) then frame.replayNext:Disable() else frame.replayNext:Enable() end
end

function MT:CreateDetailsWindow()
    if self.detailsFrame then return self.detailsFrame end
    local frame = CreateFrame("Frame", "MainTankDetailsFrame", UIParent)
    frame:SetWidth(620)
    frame:SetHeight(570)
    RestoreWindowPosition(frame, "details", "CENTER", "CENTER", -40, 20)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function() this:StartMoving() end)
    frame:SetScript("OnDragStop", function() this:StopMovingOrSizing(); SaveWindowPosition(this, "details") end)
    frame:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = {left = 4, right = 4, top = 4, bottom = 4}
    })
    frame:SetBackdropColor(0.04, 0.04, 0.06, 0.95)

    frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.title:SetPoint("TOP", frame, "TOP", 0, -11)
    frame.title:SetText("Mitigation Details")
    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -3, -3)
    frame.clearFilter = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.clearFilter:SetWidth(76)
    frame.clearFilter:SetHeight(18)
    frame.clearFilter:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -31, -7)
    frame.clearFilter:SetText("Show All")
    frame.clearFilter:SetScript("OnClick", function() MT:ClearDetailsFilter() end)
    frame.clearFilter:Hide()

    local enemyHeader = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    enemyHeader:SetPoint("TOPLEFT", frame, "TOPLEFT", 18, -37)
    enemyHeader:SetText("Enemies")
    local enemyCols = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    enemyCols:SetPoint("TOPRIGHT", frame, "TOPLEFT", 230, -37)
    enemyCols:SetText("Raw / Taken")

    frame.enemyRows = {}
    local i
    for i = 1, 13 do
        local row = CreateFrame("Button", nil, frame)
        row:SetWidth(218)
        row:SetHeight(20)
        row:SetPoint("TOPLEFT", frame, "TOPLEFT", 14, -54 - ((i - 1) * 22))
        row.highlight = row:CreateTexture(nil, "BACKGROUND")
        row.highlight:SetAllPoints(row)
        row.highlight:SetTexture(0.35, 0.12, 0.12, 0.65)
        row.highlight:Hide()
        row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.name:SetPoint("LEFT", row, "LEFT", 4, 0)
        row.name:SetWidth(135)
        row.name:SetJustifyH("LEFT")
        row.value = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.value:SetPoint("RIGHT", row, "RIGHT", -4, 0)
        row.value:SetJustifyH("RIGHT")
        row:SetScript("OnClick", function()
            if this.data then
                MT.detailsSelectedEnemy = this.data.name
                MT.detailsAbilityPage = 1
                MT:UpdateDetailsWindow()
            end
        end)
        row:SetScript("OnEnter", function() if this.data then MT:ShowDetailTooltip(this, this.data, "Enemy totals") end end)
        row:SetScript("OnLeave", function() MT:HideAnalysisTooltip() end)
        frame.enemyRows[i] = row
    end

    frame.enemyPrev = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.enemyPrev:SetWidth(48); frame.enemyPrev:SetHeight(18)
    frame.enemyPrev:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 20, 196)
    frame.enemyPrev:SetText("<")
    frame.enemyPrev:SetScript("OnClick", function() MT.detailsEnemyPage = MT.detailsEnemyPage - 1; MT:UpdateDetailsWindow() end)
    frame.enemyNext = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.enemyNext:SetWidth(48); frame.enemyNext:SetHeight(18)
    frame.enemyNext:SetPoint("LEFT", frame.enemyPrev, "RIGHT", 92, 0)
    frame.enemyNext:SetText(">")
    frame.enemyNext:SetScript("OnClick", function() MT.detailsEnemyPage = MT.detailsEnemyPage + 1; MT:UpdateDetailsWindow() end)
    frame.enemyPageText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.enemyPageText:SetPoint("CENTER", frame.enemyPrev, "CENTER", 70, 0)

    local divider = frame:CreateTexture(nil, "ARTWORK")
    divider:SetTexture(0.35, 0.35, 0.4, 0.8)
    divider:SetWidth(1); divider:SetHeight(320)
    divider:SetPoint("TOPLEFT", frame, "TOPLEFT", 244, -40)

    frame.selectedName = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.selectedName:SetPoint("TOPLEFT", frame, "TOPLEFT", 260, -38)
    frame.selectedName:SetWidth(330); frame.selectedName:SetJustifyH("LEFT")
    frame.summary = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.summary:SetPoint("TOPLEFT", frame.selectedName, "BOTTOMLEFT", 0, -5)
    frame.summary:SetWidth(335); frame.summary:SetJustifyH("LEFT")

    local abilityHeader = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    abilityHeader:SetPoint("TOPLEFT", frame, "TOPLEFT", 260, -78)
    abilityHeader:SetText("Ability")
    local schoolHeader = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    schoolHeader:SetPoint("TOPLEFT", frame, "TOPLEFT", 410, -78)
    schoolHeader:SetText("School")
    local rawHeader = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    rawHeader:SetPoint("TOPRIGHT", frame, "TOPLEFT", 548, -78)
    rawHeader:SetText("Raw")
    local takenHeader = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    takenHeader:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -18, -78)
    takenHeader:SetText("Taken")

    frame.abilityRows = {}
    for i = 1, 11 do
        local row = CreateFrame("Frame", nil, frame)
        row:SetWidth(342); row:SetHeight(22)
        row:SetPoint("TOPLEFT", frame, "TOPLEFT", 256, -96 - ((i - 1) * 23))
        row:EnableMouse(true)
        row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.name:SetPoint("LEFT", row, "LEFT", 4, 0); row.name:SetWidth(145); row.name:SetJustifyH("LEFT")
        row.school = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.school:SetPoint("LEFT", row, "LEFT", 154, 0); row.school:SetWidth(70); row.school:SetJustifyH("LEFT")
        row.raw = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.raw:SetPoint("RIGHT", row, "RIGHT", -58, 0); row.raw:SetJustifyH("RIGHT")
        row.taken = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.taken:SetPoint("RIGHT", row, "RIGHT", -4, 0); row.taken:SetJustifyH("RIGHT")
        row:SetScript("OnEnter", function() if this.data then MT:ShowDetailTooltip(this, this.data, "Ability details") end end)
        row:SetScript("OnLeave", function() MT:HideAnalysisTooltip() end)
        frame.abilityRows[i] = row
    end

    frame.abilityPrev = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.abilityPrev:SetWidth(48); frame.abilityPrev:SetHeight(18)
    frame.abilityPrev:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 330, 196)
    frame.abilityPrev:SetText("<")
    frame.abilityPrev:SetScript("OnClick", function() MT.detailsAbilityPage = MT.detailsAbilityPage - 1; MT:UpdateDetailsWindow() end)
    frame.abilityNext = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.abilityNext:SetWidth(48); frame.abilityNext:SetHeight(18)
    frame.abilityNext:SetPoint("LEFT", frame.abilityPrev, "RIGHT", 92, 0)
    frame.abilityNext:SetText(">")
    frame.abilityNext:SetScript("OnClick", function() MT.detailsAbilityPage = MT.detailsAbilityPage + 1; MT:UpdateDetailsWindow() end)
    frame.abilityPageText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.abilityPageText:SetPoint("CENTER", frame.abilityPrev, "CENTER", 70, 0)


    local eventDivider = frame:CreateTexture(nil, "ARTWORK")
    eventDivider:SetTexture(0.35, 0.35, 0.4, 0.8)
    eventDivider:SetHeight(1); eventDivider:SetWidth(584)
    eventDivider:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 18, 178)

    local eventHeader = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    eventHeader:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 18, 157)
    eventHeader:SetText("Event Inspector")
    frame.replayCount = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.replayCount:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -18, 157)
    frame.replayText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.replayText:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 18, 112)
    frame.replayText:SetWidth(584); frame.replayText:SetHeight(42); frame.replayText:SetJustifyH("LEFT"); frame.replayText:SetJustifyV("TOP")

    frame.replayPrev = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.replayPrev:SetWidth(72); frame.replayPrev:SetHeight(18)
    frame.replayPrev:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 18, 88)
    frame.replayPrev:SetText("Previous")
    frame.replayPrev:SetScript("OnClick", function() MT:SelectReplayEvent((MT.detailsSelectedEvent or 1) - 1) end)
    frame.replayNext = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.replayNext:SetWidth(72); frame.replayNext:SetHeight(18)
    frame.replayNext:SetPoint("LEFT", frame.replayPrev, "RIGHT", 6, 0)
    frame.replayNext:SetText("Next")
    frame.replayNext:SetScript("OnClick", function() MT:SelectReplayEvent((MT.detailsSelectedEvent or 0) + 1) end)

    frame.eventRows = {}
    for i = 1, 3 do
        local row = CreateFrame("Button", nil, frame)
        row:SetWidth(584); row:SetHeight(18)
        row:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 18, 63 - ((i - 1) * 20))
        row.highlight = row:CreateTexture(nil, "BACKGROUND")
        row.highlight:SetAllPoints(row); row.highlight:SetTexture(0.25, 0.45, 0.75, 0.45); row.highlight:Hide()
        row.time = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.time:SetPoint("LEFT", row, "LEFT", 2, 0); row.time:SetWidth(36); row.time:SetJustifyH("LEFT")
        row.source = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.source:SetPoint("LEFT", row, "LEFT", 42, 0); row.source:SetWidth(110); row.source:SetJustifyH("LEFT")
        row.ability = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.ability:SetPoint("LEFT", row, "LEFT", 156, 0); row.ability:SetWidth(120); row.ability:SetJustifyH("LEFT")
        row.outcome = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.outcome:SetPoint("LEFT", row, "LEFT", 280, 0); row.outcome:SetWidth(300); row.outcome:SetJustifyH("LEFT")
        row:SetScript("OnClick", function() if this.eventIndex then MT:SelectReplayEvent(this.eventIndex) end end)
        frame.eventRows[i] = row
    end
    frame.eventPrev = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.eventPrev:SetWidth(42); frame.eventPrev:SetHeight(18)
    frame.eventPrev:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -116, 15)
    frame.eventPrev:SetText("<")
    frame.eventPrev:SetScript("OnClick", function() MT.detailsEventPage = MT.detailsEventPage - 1; MT:UpdateDetailsWindow() end)
    frame.eventNext = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.eventNext:SetWidth(42); frame.eventNext:SetHeight(18)
    frame.eventNext:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -18, 15)
    frame.eventNext:SetText(">")
    frame.eventNext:SetScript("OnClick", function() MT.detailsEventPage = MT.detailsEventPage + 1; MT:UpdateDetailsWindow() end)
    frame.eventPageText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.eventPageText:SetPoint("CENTER", frame.eventPrev, "CENTER", 49, 0)

    FinalizeLegacyWindow(frame)
    self.detailsFrame = frame
    frame:Hide()
    return frame
end

function MT:ToggleDetails()
    local frame = self:CreateDetailsWindow()
    if frame:IsVisible() then
        frame:Hide()
    else
        self.detailsFilter = nil
        self.detailsSelectedEnemy = nil
        self.detailsEnemyPage = 1
        self.detailsAbilityPage = 1
        frame:Show()
        self:UpdateDetailsWindow()
    end
end


-- Export only the small compatibility surface consumed by later historical
-- override layers. These are runtime helpers, never SavedVariables data.
E.TimelineValue = TimelineValue
E.GetPieEntryUnderMouse = GetPieEntryUnderMouse
E.AddPieEntry = AddPieEntry
