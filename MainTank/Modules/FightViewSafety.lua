-- MainTank v1.2.11 FIGHTVIEWFIX1
-- Finalized saved-fight views must be read-only and authoritative.
--
-- HF5 already established this contract for completed CURRENT:
--   fights[1].data is authoritative; do not rebuild RAW/Taken/etc. from events.
--
-- Historical numbered views (/mt fight N) were intentionally left on the old
-- RC6 display-rebuild path. Modern compact fights can therefore be re-attributed
-- when merely viewed, causing /mt fight N to change between repeated selections
-- and allowing /mt fight 1 to disagree with completed Current.
--
-- FIGHTVIEWFIX1 extends the HF5 contract to every finalized numbered fight:
--   * headline data comes from fight.data, never an RC6 RAW rebuild;
--   * timeline comes from fight.timeline;
--   * display events are runtime copies frozen at final RC6 generation so old
--     tooltip/detail helpers cannot mutate authoritative fight.events;
--   * no SavedVariables payload is duplicated and no live-combat path changes.

if not MainTank then return end
local MT = MainTank

local FV1_PreviousGetDisplayData = MT.GetDisplayData
local FV1_PreviousGetDisplayTimeline = MT.GetDisplayTimeline
local FV1_PreviousGetDisplayEvents = MT.GetDisplayEvents
local FV1_PreviousSetView = MT.SetView

local function FV1_CopyAggregate(source)
    local out = {}
    local k, v, innerK, innerV, inner
    if type(source) ~= "table" then return out end

    -- Aggregate tables are small. Copy nested tables one additional level so
    -- schools/mobs cannot be altered through a display-only snapshot.
    for k, v in pairs(source) do
        if type(v) == "table" then
            inner = {}
            for innerK, innerV in pairs(v) do
                if type(innerV) == "table" then
                    local leaf = {}
                    local leafK, leafV
                    for leafK, leafV in pairs(innerV) do
                        leaf[leafK] = leafV
                    end
                    inner[innerK] = leaf
                else
                    inner[innerK] = innerV
                end
            end
            out[k] = inner
        else
            out[k] = v
        end
    end
    return out
end

local function FV1_CopyEventsFrozen(events)
    local out = {}
    local i, source, copy, k, v
    for i = 1, table.getn(events or {}) do
        source = events[i]
        if type(source) == "table" then
            copy = {}
            for k, v in pairs(source) do
                copy[k] = v
            end
            -- Historical event attribution is already finalized. This transient
            -- marker prevents legacy RC6 helpers from re-estimating the copy.
            copy.rc6MathVersion = 11
            out[i] = copy
        end
    end
    return out
end

local function FV1_CopyTimeline(timeline)
    local out = {}
    local k, bucket, copy, field, value
    for k, bucket in pairs(timeline or {}) do
        if type(bucket) == "table" then
            copy = {}
            for field, value in pairs(bucket) do copy[field] = value end
            out[k] = copy
        else
            out[k] = bucket
        end
    end
    return out
end

local function FV1_GetNumberedFight(owner)
    if not owner or owner.inCombat or type(owner.currentView) ~= "number" then return nil end
    return owner.fights and owner.fights[owner.currentView] or nil
end

local function FV1_EnsureSnapshot(owner, fight)
    if not owner or type(fight) ~= "table" then return nil end
    local id = fight.id or owner.currentView
    local eventCount = table.getn(fight.events or {})

    if owner.fv1SnapshotFight ~= fight or
       owner.fv1SnapshotID ~= id or
       owner.fv1SnapshotEventCount ~= eventCount then

        owner.fv1SnapshotFight = fight
        owner.fv1SnapshotID = id
        owner.fv1SnapshotEventCount = eventCount
        owner.fv1SnapshotData = FV1_CopyAggregate(fight.data or {})
        owner.fv1SnapshotTimeline = FV1_CopyTimeline(fight.timeline or {})
        owner.fv1SnapshotEvents = FV1_CopyEventsFrozen(fight.events or {})
    end
    return owner.fv1SnapshotData
end

local function FV1_ClearSnapshot(owner)
    if not owner then return end
    owner.fv1SnapshotFight = nil
    owner.fv1SnapshotID = nil
    owner.fv1SnapshotEventCount = nil
    owner.fv1SnapshotData = nil
    owner.fv1SnapshotTimeline = nil
    owner.fv1SnapshotEvents = nil
end

function MT:GetDisplayData()
    local fight = FV1_GetNumberedFight(self)
    if fight then
        FV1_EnsureSnapshot(self, fight)
        -- Return a fresh aggregate copy so even later presentation wrappers
        -- cannot mutate the cached authoritative display snapshot.
        return FV1_CopyAggregate(self.fv1SnapshotData or fight.data or {})
    end
    return FV1_PreviousGetDisplayData(self)
end

function MT:GetDisplayTimeline()
    local fight = FV1_GetNumberedFight(self)
    if fight then
        FV1_EnsureSnapshot(self, fight)
        return self.fv1SnapshotTimeline or {}
    end
    return FV1_PreviousGetDisplayTimeline(self)
end

function MT:GetDisplayEvents()
    local fight = FV1_GetNumberedFight(self)
    if fight then
        FV1_EnsureSnapshot(self, fight)
        return self.fv1SnapshotEvents or {}
    end
    return FV1_PreviousGetDisplayEvents(self)
end

function MT:SetView(view)
    -- Every explicit view selection starts from the immutable fight record again.
    -- Repeating "/mt fight 2" must therefore produce byte-for-byte identical
    -- display inputs instead of carrying mutations from the previous view.
    FV1_ClearSnapshot(self)
    return FV1_PreviousSetView(self, view)
end

-- Version ownership remains centralized in Core/Release.lua.
