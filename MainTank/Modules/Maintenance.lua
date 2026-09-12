-- MainTank v1.0.0 FR1S
-- Modules/Maintenance.lua
-- First-release runtime/database hygiene, reset safety, navigation repair, and
-- lightweight diagnostics extracted from the historical engine.

if not MainTank then return end
local MT = MainTank

local function Print(msg)
    if MT.PrintMessage then MT:PrintMessage(msg) end
end

local function CountTable(root)
    local count = 0
    if type(root) ~= "table" then return 0 end
    local k, v
    for k, v in pairs(root) do count = count + 1 end
    return count
end

local function MarkUnsnapshottedContexts(events, keep)
    local i, eventData
    for i = 1, table.getn(events or {}) do
        eventData = events[i]
        if eventData and type(eventData.rc6ContextSnapshot) ~= "table" and eventData.contextID then
            keep[eventData.contextID] = true
        end
    end
end

local function PruneMitigationContexts(owner)
    if not owner or type(owner.mitigationContexts) ~= "table" then return 0 end
    local keep = {}
    MarkUnsnapshottedContexts(owner.events, keep)
    MarkUnsnapshottedContexts(owner.overallEvents, keep)
    local i, fight
    for i = 1, table.getn(owner.fights or {}) do
        fight = owner.fights[i]
        if fight and fight.events then MarkUnsnapshottedContexts(fight.events, keep) end
    end
    if owner.rc5ActiveContext and owner.rc5ActiveContext.id then keep[owner.rc5ActiveContext.id] = true end

    local removed = 0
    local id, context
    for id, context in pairs(owner.mitigationContexts) do
        if not keep[id] then
            owner.mitigationContexts[id] = nil
            removed = removed + 1
        end
    end
    return removed
end


local PreviousSyncPersistentData = MT.SyncPersistentData
function MT:SyncPersistentData()
    PruneMitigationContexts(self)
    return PreviousSyncPersistentData(self)
end

-- Full-data reset semantics: reset learned spell classifications and local
-- fight identity in addition to the historical session/history tables.
local PreviousResetSession = MT.ResetSession
function MT:ResetSession()
    PreviousResetSession(self)
    self.abilitySchoolMemory = {}
    if self.profile then
        self.profile.abilitySchoolMemory = self.abilitySchoolMemory
        self.profile.nextFightID = 1
        self.profile.timelineSelection = nil
        self.profile.currentView = "CURRENT"
        self.profile.overallElapsed = 0
    end
    self.timelineSelection = nil
    self.currentView = "CURRENT"
    self:SyncPersistentData()
end

if StaticPopupDialogs and StaticPopupDialogs["MAINTANK_RESET_ALL"] then
    StaticPopupDialogs["MAINTANK_RESET_ALL"].text =
        "Delete all MainTank combat, history, timeline, and learned data for this character?\nUI settings are preserved. This cannot be undone."
end

-- Navigation repair and lightweight diagnostics stay in one command wrapper;
-- Core/Commands.lua loads later and only intercepts help aliases.
local PreviousHandleSlash = MT.HandleSlash
function MT:HandleSlash(msg)
    local cmd = string.lower(tostring(msg or ""))
    cmd = string.gsub(cmd, "^%s+", "")
    cmd = string.gsub(cmd, "%s+$", "")

    if cmd == "show" then
        if self.ShowManagedPage then self:ShowManagedPage("MAIN") elseif self.frame then self.frame:Show() end
        return
    elseif cmd == "hide" then
        if self.HideAllManagedPages then self:HideAllManagedPages(nil) end
        if self.frame then self.frame:Hide() end
        return
    elseif cmd == "perf" or cmd == "health" then
        local eventCount = table.getn(self.events or {})
        local overallCount = table.getn(self.overallEvents or {})
        local fightCount = table.getn(self.fights or {})
        local contextCount = CountTable(self.mitigationContexts)
        local memoryCount = CountTable(self.contextMemory)
        local pieTextures = 0
        if self.pieFrame and self.pieFrame.pieTextures then pieTextures = table.getn(self.pieFrame.pieTextures) end
        Print("Runtime health: events "..tostring(eventCount).." | overall "..tostring(overallCount).." | fights "..tostring(fightCount))
        Print("Runtime health: contexts "..tostring(contextCount).." | learned-context sets "..tostring(memoryCount).." | pie textures "..tostring(pieTextures))
        Print("Pie textures are pooled/reused; contextMemory is retained intentionally for avoidance learning.")
        return
    end

    return PreviousHandleSlash(self, msg)
end
