-- MainTank REFACXML1 - Session, view-state, and persistence foundation
-- Extracted from Core\Engine.lua without changing method order.

local MT = MainTank
local E = MT._engine
local find = string.find
local NewData = E.NewData
local CopyTable = E.CopyTable
local Print = E.Print
local AddToTimelineBucket = E.AddToTimelineBucket
local DB_SCHEMA_VERSION = E.DB_SCHEMA_VERSION

local function SaveWindowPosition(frame, key)
    if not frame or not key or not MainTankDB then return end
    local point, _, relativePoint, x, y = frame:GetPoint()
    if not MainTankDB.windowPositions then MainTankDB.windowPositions = {} end
    MainTankDB.windowPositions[key] = {point = point, relativePoint = relativePoint, x = x, y = y}
end

local function RestoreWindowPosition(frame, key, defaultPoint, defaultRelativePoint, defaultX, defaultY)
    local saved = MainTankDB and MainTankDB.windowPositions and MainTankDB.windowPositions[key]
    frame:ClearAllPoints()
    if saved then
        frame:SetPoint(saved.point or defaultPoint, UIParent, saved.relativePoint or defaultRelativePoint, saved.x or 0, saved.y or 0)
    else
        frame:SetPoint(defaultPoint, UIParent, defaultRelativePoint, defaultX or 0, defaultY or 0)
    end
end

function MT:GenerateFightMetadata(events, deathCounts)
    local enemies = {}
    local i, event, name, data
    for i = 1, table.getn(events or {}) do
        event = events[i]
        name = event.source or "Unknown"
        if name ~= self.playerName and name ~= "Environment" and name ~= "Unknown" then
            if not enemies[name] then enemies[name] = {name = name, taken = 0, raw = 0, events = 0} end
            data = enemies[name]
            data.taken = data.taken + (event.taken or 0)
            data.raw = data.raw + (event.raw or 0)
            data.events = data.events + 1
        end
    end
    local list = {}
    for name, data in pairs(enemies) do table.insert(list, data) end
    table.sort(list, function(a, b)
        if a.taken ~= b.taken then return a.taken > b.taken end
        if a.raw ~= b.raw then return a.raw > b.raw end
        if a.events ~= b.events then return a.events > b.events end
        return a.name < b.name
    end)
    local primary = list[1] and list[1].name or "Unknown enemies"
    local count = 0
    for i = 1, table.getn(list) do
        name = list[i].name
        local instances = deathCounts and tonumber(deathCounts[name]) or 0
        if instances < 1 then instances = 1 end
        count = count + instances
    end
    local label = primary
    if count > 1 then label = label .. " +" .. (count - 1) end
    return {label = label, primaryEnemy = primary, enemyCount = count}
end

function MT:IsEnemyPresentInCurrentFight(name)
    if not name or name == "" then return false end
    local i, eventData
    for i = 1, table.getn(self.events or {}) do
        eventData = self.events[i]
        if eventData and eventData.source == name then return true end
    end
    return false
end

function MT:RecordHostileDeath(message)
    if not self.inCombat or not message then return false end
    local _, _, name = find(message, "^(.+) dies%.$")
    if not name then _, _, name = find(message, "^(.+) dies$") end
    if not name or not self:IsEnemyPresentInCurrentFight(name) then return false end
    self.enemyDeathCounts[name] = (self.enemyDeathCounts[name] or 0) + 1
    self:SyncPersistentData()
    self:UpdateDisplay()
    return true
end

function MT:GetCurrentFightLabel()
    local meta = self:GenerateFightMetadata(self.events, self.enemyDeathCounts)
    return meta.label
end

function MT:GetViewLabel()
    if self.currentView == "OVERALL" then return "Overall" end
    if type(self.currentView) == "number" and self.fights[self.currentView] then
        return self.fights[self.currentView].label or ("Fight " .. self.currentView)
    end
    local label = self:GetCurrentFightLabel()
    if label == "Unknown enemies" then
        return self.inCombat and "Current Fight" or "Last Fight"
    end
    return label
end

function MT:GetDisplayData()
    if self.currentView == "OVERALL" then return self.overallData end
    if type(self.currentView) == "number" and self.fights[self.currentView] then
        return self.fights[self.currentView].data
    end
    return self.data
end


function MT:GetDisplayTimeline()
    if self.currentView == "OVERALL" then return self.overallTimeline end
    if type(self.currentView) == "number" and self.fights[self.currentView] then
        return self.fights[self.currentView].timeline or {}
    end
    return self.timeline
end

function MT:GetDisplayEvents()
    if self.currentView == "OVERALL" then return self.overallEvents end
    if type(self.currentView) == "number" and self.fights[self.currentView] then
        return self.fights[self.currentView].events or {}
    end
    return self.events
end


local function GetMaximumTimelineSecond(timeline)
    local maximum = 0
    local second
    for second in pairs(timeline or {}) do
        if type(second) == "number" and second > maximum then maximum = second end
    end
    return maximum
end

local function MergeDefaults(target, defaults)
    if type(target) ~= "table" then target = {} end
    local key, value
    for key, value in pairs(defaults) do
        if target[key] == nil then
            target[key] = type(value) == "table" and CopyTable(value) or value
        elseif type(value) == "table" and type(target[key]) == "table" then
            MergeDefaults(target[key], value)
        end
    end
    return target
end

local function NormalizeEvent(eventData)
    if type(eventData) ~= "table" then eventData = {} end
    local fields = {"time", "raw", "armor", "block", "avoidance", "resist", "absorb", "taken", "physicalRaw", "magicRaw"}
    local i
    for i = 1, table.getn(fields) do
        local field = fields[i]
        if type(eventData[field]) ~= "number" then eventData[field] = 0 end
    end
    eventData.source = eventData.source or "Unknown"
    eventData.ability = eventData.ability or "Unknown"
    eventData.school = eventData.school or "Physical"
    eventData.kind = eventData.kind or "DAMAGE"
    eventData.critical = eventData.critical and true or false
    eventData.crushing = eventData.crushing and true or false
    eventData.environmental = eventData.environmental and true or false
    eventData.estimated = eventData.estimated and true or false
    return eventData
end

local function NormalizeEventList(events)
    if type(events) ~= "table" then return {} end
    local i
    for i = 1, table.getn(events) do events[i] = NormalizeEvent(events[i]) end
    return events
end

function MT:MigrateDatabase()
    if not MainTankDB then MainTankDB = {} end
    local oldVersion = tonumber(MainTankDB.version) or 0
    if not MainTankDB.profiles then MainTankDB.profiles = {} end
    if not MainTankDB.windowPositions then MainTankDB.windowPositions = {} end

    -- FR2 startup cleanup: a DB already at the current schema has already had
    -- every persisted event normalized. Repeating that full historical walk on
    -- every login is pure startup cost. Future schema bumps still fall through
    -- to the original migration below.
    if oldVersion == DB_SCHEMA_VERSION then
        return
    end

    local _, profile, i, fight
    for _, profile in pairs(MainTankDB.profiles) do
        profile.data = MergeDefaults(profile.data or {}, NewData())
        profile.overallData = MergeDefaults(profile.overallData or {}, NewData())
        profile.events = NormalizeEventList(profile.events or {})
        profile.overallEvents = NormalizeEventList(profile.overallEvents or {})
        profile.timeline = profile.timeline or {}
        profile.overallTimeline = profile.overallTimeline or {}
        profile.fights = profile.fights or {}
        profile.sessionMemory = profile.sessionMemory or {}
        profile.targetDamageMemory = profile.targetDamageMemory or {}
        profile.abilitySchoolMemory = profile.abilitySchoolMemory or {}
        profile.encounterMemory = profile.encounterMemory or {}
        profile.pending = profile.pending or {}
        profile.enemyDeathCounts = profile.enemyDeathCounts or {}
        for i = 1, table.getn(profile.fights) do
            fight = profile.fights[i]
            if type(fight) == "table" then
                fight.data = MergeDefaults(fight.data or {}, NewData())
                fight.events = NormalizeEventList(fight.events or {})
                fight.timeline = fight.timeline or {}
                fight.enemyDeathCounts = fight.enemyDeathCounts or {}
            end
        end
        profile.schemaVersion = DB_SCHEMA_VERSION
    end

    MainTankDB.version = DB_SCHEMA_VERSION
    if oldVersion < DB_SCHEMA_VERSION then
        Print("SavedVariables upgraded to database schema " .. DB_SCHEMA_VERSION .. ".")
    end
end

function MT:GetProfileKey()
    local realm = GetRealmName and GetRealmName() or "Unknown Realm"
    local player = self.playerName or UnitName("player") or "Unknown Player"
    return realm .. " - " .. player
end

function MT:SyncPersistentData()
    if not MainTankDB then return end
    if not MainTankDB.profiles then MainTankDB.profiles = {} end
    MainTankDB.version = DB_SCHEMA_VERSION

    local key = self.profileKey or self:GetProfileKey()
    self.profileKey = key
    local profile = MainTankDB.profiles[key]
    if not profile then
        profile = {}
        MainTankDB.profiles[key] = profile
    end
    self.profile = profile

    -- These are intentionally live table references. WoW writes the complete
    -- SavedVariables table into WTF when the UI reloads, the character logs
    -- out, or the client exits.
    profile.data = self.data
    profile.overallData = self.overallData
    profile.events = self.events
    -- Runtime-only. Persisting this duplicates every combat event and was the
    -- source of the multi-megabyte regression. Overall events are rebuilt from
    -- the authoritative saved fights after reload.
    profile.overallEvents = nil
    profile.timeline = self.timeline
    profile.overallTimeline = self.overallTimeline
    profile.fights = self.fights
    profile.sessionMemory = self.sessionMemory
    profile.targetDamageMemory = self.targetDamageMemory
    profile.abilitySchoolMemory = self.abilitySchoolMemory
    profile.encounterMemory = self.encounterMemory
    profile.pending = self.pending
    profile.enemyDeathCounts = self.enemyDeathCounts
    profile.currentView = self.currentView
    profile.timelineMode = self.timelineMode
    profile.pieMode = self.pieMode
    profile.timelineSelection = self.timelineSelection
    profile.overallElapsed = GetMaximumTimelineSecond(self.overallTimeline)
    profile.overallCombatElapsed = tonumber(self.overallCombatElapsed) or 0
    profile.overallCombatTimelineVersion = 1
    profile.version = self.version
    if type(time) == "function" then profile.savedAt = time() end
end

function MT:RestorePersistentData()
    if not MainTankDB.profiles then MainTankDB.profiles = {} end
    self.profileKey = self:GetProfileKey()
    local profile = MainTankDB.profiles[self.profileKey]
    if not profile then
        profile = {}
        MainTankDB.profiles[self.profileKey] = profile
    end
    self.profile = profile

    self.data = profile.data or NewData()
    self.overallData = profile.overallData or NewData()
    self.events = profile.events or {}
    self.overallEvents = profile.overallEvents or {}
    self.timeline = profile.timeline or {}
    self.overallTimeline = profile.overallTimeline or {}
    self.fights = profile.fights or {}
    self.sessionMemory = profile.sessionMemory or {}
    self.targetDamageMemory = profile.targetDamageMemory or {}
    self.abilitySchoolMemory = profile.abilitySchoolMemory or {}
    self.encounterMemory = profile.encounterMemory or {}
    self.pending = profile.pending or {}
    self.enemyDeathCounts = profile.enemyDeathCounts or {}
    self.timelineMode = profile.timelineMode or "RAW"
    if self.timelineMode ~= "RAW" and self.timelineMode ~= "PHYSICAL" and self.timelineMode ~= "MAGIC" then
        self.timelineMode = "RAW"
    end
    self.pieMode = profile.pieMode or "RAW"
    self.timelineSelection = profile.timelineSelection

    local fightIndex, fight, meta
    for fightIndex = 1, table.getn(self.fights) do
        fight = self.fights[fightIndex]
        if fight then
            -- FR2 startup cleanup: modern saved fights already persist exact
            -- label/primaryEnemy/enemyCount. Only legacy/incomplete records need
            -- an event scan to regenerate metadata.
            if fight.events and (not fight.label or fight.label == "" or
               not fight.primaryEnemy or fight.enemyCount == nil) then
                meta = self:GenerateFightMetadata(fight.events, fight.enemyDeathCounts)
                fight.label = meta.label
                fight.primaryEnemy = meta.primaryEnemy
                fight.enemyCount = meta.enemyCount
            end
            fight.id = fight.id or fightIndex
        end
    end
    while table.getn(self.fights) > 20 do table.remove(self.fights) end

    -- HF1 migration: older builds used wall-clock session timestamps for the
    -- Overall timeline, so waiting between pulls created huge blank regions.
    -- Normalize the retained fights to contiguous combat time once.
    if tonumber(profile.overallCombatTimelineVersion) ~= 1 then
        self.overallEvents = {}
        self.overallTimeline = {}
        local combatOffset = 0
        local i, j, f, src, copy
        for i = table.getn(self.fights), 1, -1 do
            f = self.fights[i]
            if type(f) == "table" then
                f.overallOffset = combatOffset
                for j = 1, table.getn(f.events or {}) do
                    src = f.events[j]
                    if type(src) == "table" then
                        copy = CopyTable(src)
                        copy.time = combatOffset + (tonumber(src.time) or 0)
                        table.insert(self.overallEvents, copy)
                        AddToTimelineBucket(self.overallTimeline, copy)
                    end
                end
                combatOffset = combatOffset + (tonumber(f.duration) or 0)
            end
        end
        self.overallCombatElapsed = combatOffset
        profile.overallCombatElapsed = combatOffset
        profile.overallCombatTimelineVersion = 1
    else
        self.overallCombatElapsed = tonumber(profile.overallCombatElapsed) or 0
    end

    local elapsed = tonumber(profile.overallElapsed) or GetMaximumTimelineSecond(self.overallTimeline)
    self.sessionStartTime = GetTime() - elapsed

    local savedView = profile.currentView
    if savedView == "OVERALL" then
        self.currentView = "OVERALL"
    elseif type(savedView) == "number" and self.fights[savedView] then
        self.currentView = savedView
    else
        self.currentView = "CURRENT"
    end

    self:SyncPersistentData()
end

function MT:ResetEncounter(silent)
    self.data = NewData()
    self.events = {}
    self.timeline = {}
    self.encounterMemory = {}
    self.pending = {}
    self.enemyDeathCounts = {}
    self.fightStartTime = self.inCombat and GetTime() or nil
    self:SyncPersistentData()
    self:UpdateDisplay()
    if not silent then Print("Current fight reset.") end
end

function MT:ResetSession()
    self:ResetEncounter(true)
    self.overallData = NewData()
    self.overallEvents = {}
    self.overallTimeline = {}
    self.overallCombatElapsed = 0
    self.fights = {}
    self.sessionStartTime = GetTime()
    self.sessionMemory = {}
    self.targetDamageMemory = {}
    self.currentView = "CURRENT"
    self:SyncPersistentData()
    Print("All current, overall, saved-fight, timeline, and learned data reset.")
    self:UpdateDisplay()
end

function MT:StartCombat()
    self.inCombat = true
    self.preCombatMiniMode = self.miniMode and true or false
    if self.autoMiniInCombat and not self.miniMode and self.frame and self.frame:IsVisible() then
        self:SetMiniMode(true, true)
    end
    self.data = NewData()
    self.events = {}
    self.timeline = {}
    self.encounterMemory = {}
    self.pending = {}
    self.enemyDeathCounts = {}
    self.fightStartTime = GetTime()
    self.currentView = "CURRENT"
    self:SyncPersistentData()
    self:UpdateViewButtons()
    self:UpdateDisplay()
end

function MT:EndCombat()
    self.inCombat = false
    if self.autoMiniApplied and not self.preCombatMiniMode then
        self:SetMiniMode(false, true)
        self.autoMiniApplied = false
    end
    local duration = 0
    if self.fightStartTime then duration = GetTime() - self.fightStartTime end

    -- FINALAGG1: self.data is the legacy hot-path accumulator. It intentionally
    -- does not model RC6 Flat/Physical/Magic DR, while self.events does. Before
    -- ANY EndCombat wrapper (Compare, Boss, Archive, History, etc.) can consume
    -- the new fight, replace the aggregate with one authoritative rebuild from
    -- the already-attributed event stream. This preserves the invariant:
    --     RAW - Taken == all stopped-damage categories
    -- and keeps Main, Pie, Timeline, Details, Compare, and persistence aligned.
    local finalizedData = self.data
    if type(self.BuildFinalizedAggregateFromEvents) == "function" and
       self.events and table.getn(self.events) > 0 then
        local rebuilt = self:BuildFinalizedAggregateFromEvents(self.data, self.events)
        if type(rebuilt) == "table" then
            finalizedData = rebuilt
            self.data = rebuilt
        end
    end

    local _, raw = self:GetTotals(finalizedData)
    if raw > 0 then
        local meta = self:GenerateFightMetadata(self.events, self.enemyDeathCounts)
        table.insert(self.fights, 1, {
            id = (self.profile and self.profile.nextFightID) or 1,
            data = CopyTable(finalizedData),
            events = CopyTable(self.events),
            timeline = CopyTable(self.timeline),
            duration = duration,
            finalAggregateVersion = 1,
            -- FR1X: tiny metadata used to rebuild runtime OVERALL event times
            -- from the one authoritative saved-fight event stream after reload.
            overallOffset = tonumber(self.overallCombatElapsed) or 0,
            label = meta.label,
            primaryEnemy = meta.primaryEnemy,
            enemyCount = meta.enemyCount,
            enemyDeathCounts = CopyTable(self.enemyDeathCounts)
        })
        if self.profile then self.profile.nextFightID = ((self.profile.nextFightID or 1) + 1) end
        while table.getn(self.fights) > 20 do table.remove(self.fights) end
        self.overallCombatElapsed = (tonumber(self.overallCombatElapsed) or 0) + duration
    end
    self.fightStartTime = nil
    self:SyncPersistentData()
    self:UpdateDisplay()
end


-- Window-position helpers are consumed by UI\AnalysisCore.lua.
E.SaveWindowPosition = SaveWindowPosition
E.RestoreWindowPosition = RestoreWindowPosition
