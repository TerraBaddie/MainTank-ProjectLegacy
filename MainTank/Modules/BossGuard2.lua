-- MainTank v1.2.63 BOSSGUARD2
--
-- Multi-phase / add-heavy Boss encounter classification hardening.
--
-- BOSSGUARD1 correctly stopped a trash pull from becoming BOSS merely because
-- the player targeted or briefly touched a nearby skull-level mob.  Its exact
-- `boss == primaryEnemy` rule was intentionally conservative, but real scripted
-- encounters such as Razorgore can keep combat active through long add phases.
-- In those fights the largest incoming RAW source can legitimately be an add
-- even though a skull-level Boss later deals substantial incoming damage.
--
-- BOSSGUARD2 keeps primaryEnemy as the truthful largest incoming-damage source
-- and adds a second, exact-fight identity path.  A non-primary Boss qualifies
-- only when an already-authoritative Boss Profile:
--   * carries the same finalized fightID,
--   * carries the same analytical primaryEnemy,
--   * contains actual Boss incoming RAW, and
--   * contains at least 3 Boss incoming events.
--
-- Exact fightID matching also safely repairs retained Recent/Archive/History
-- records created by BOSSGUARD1.  No RAW/Taken/mitigation/event/timeline value
-- is recalculated or replaced by this module.

if not MainTank then return end
local MT = MainTank
local abs = math.abs

local BG2_MIN_SECONDARY_BOSS_EVENTS = 3

local function BG2_ProfileKey(owner)
    if owner and owner.profileKey then return owner.profileKey end
    if owner and owner.GetProfileKey then return owner:GetProfileKey() end
    local realm = GetRealmName and GetRealmName() or "Unknown Realm"
    local player = UnitName and UnitName("player") or "Unknown Player"
    return realm .. " - " .. player
end

local function BG2_RecordID(record)
    if type(record) ~= "table" then return nil end
    return record.id or record.fightID
end

local function BG2_IsPvP(record)
    return type(record) == "table" and (record.combatType == "PVP" or record.pvp == true)
end

local function BG2_IsPrimedRecord(record, profile)
    if type(record) ~= "table" or type(profile) ~= "table" then return false end
    if record.primaryEnemy ~= profile.name then return false end
    if record.bossName ~= profile.name then return false end
    if record.bossSkull == true then return true end
    if record.bossEncounterSkull == true then return true end
    if tonumber(record.bossIdentityVersion) == 2 then return true end
    return false
end

local function BG2_ProfileMatchesRecord(profile, record)
    if type(profile) ~= "table" or type(record) ~= "table" then return false end
    if BG2_IsPvP(record) then return false end
    if profile.isDebug == true then return false end

    local recordID = BG2_RecordID(record)
    local profileID = profile.fightID
    if recordID == nil or profileID == nil then return false end
    if tostring(recordID) ~= tostring(profileID) then return false end

    local bossName = profile.name
    local bossRaw = tonumber(profile.raw) or 0
    if not bossName or bossName == "" or bossRaw <= 0 then return false end

    local recordPrimary = record.primaryEnemy
    local profilePrimary = profile.primaryEnemy
    local primaryIsBoss = recordPrimary == bossName

    if not primaryIsBoss then
        -- The secondary-Boss path is intentionally stricter than normal Boss
        -- identity.  Require the Boss Profile to remember this exact fight's
        -- analytical primary source so fightID alone can never promote an
        -- unrelated/stale record.
        if not profilePrimary or profilePrimary == "" then return false end
        if recordPrimary ~= profilePrimary and not BG2_IsPrimedRecord(record, profile) then
            return false
        end
        if (tonumber(profile.events) or 0) < BG2_MIN_SECONDARY_BOSS_EVENTS then
            return false
        end
    end

    local recordDuration = tonumber(record.duration) or 0
    local profileDuration = tonumber(profile.duration) or 0
    if recordDuration > 0 and profileDuration > 0 and abs(recordDuration - profileDuration) > 2.0 then
        return false
    end

    return true
end

local function BG2_FindExactBossProfile(owner, record)
    local history = owner and owner.bossHistory or nil
    if type(history) ~= "table" then return nil end

    local best = nil
    local bestRaw = -1
    local bestEvents = -1
    local i, profile, raw, events
    for i = 1, table.getn(history) do
        profile = history[i]
        if BG2_ProfileMatchesRecord(profile, record) then
            raw = tonumber(profile.raw) or 0
            events = tonumber(profile.events) or 0
            if not best or raw > bestRaw or (raw == bestRaw and events > bestEvents) or
               (raw == bestRaw and events == bestEvents and tostring(profile.name or "") < tostring(best.name or "")) then
                best = profile
                bestRaw = raw
                bestEvents = events
            end
        end
    end
    return best
end

local function BG2_BossLabel(record, bossName)
    local count = tonumber(record and record.enemyCount) or 0
    if count > 1 then return tostring(bossName) .. " +" .. tostring(count - 1) end
    return tostring(bossName)
end

local function BG2_RepairRecord(owner, record)
    if type(record) ~= "table" or BG2_IsPvP(record) then return false end
    local profile = BG2_FindExactBossProfile(owner, record)
    if not profile then return false end

    local bossName = profile.name
    local analyticalPrimary = profile.primaryEnemy or record.primaryEnemy
    local primaryIsBoss = analyticalPrimary == bossName
    local desiredLabel = BG2_BossLabel(record, bossName)
    local changed = false

    if analyticalPrimary and record.primaryEnemy ~= analyticalPrimary then
        record.primaryEnemy = analyticalPrimary
        changed = true
    end
    if record.isBoss ~= true then record.isBoss = true; changed = true end
    if record.bossName ~= bossName then record.bossName = bossName; changed = true end

    -- Preserve BOSSGUARD1's meaning of bossSkull for ordinary primary-Boss
    -- encounters.  Secondary Boss encounters carry a separate marker so older
    -- primary-only code cannot mistake an add for the skull Boss.
    if primaryIsBoss then
        if record.bossSkull ~= true then record.bossSkull = true; changed = true end
        if record.bossEncounterSkull ~= nil then record.bossEncounterSkull = nil; changed = true end
    else
        if record.bossSkull ~= false then record.bossSkull = false; changed = true end
        if record.bossEncounterSkull ~= true then record.bossEncounterSkull = true; changed = true end
    end

    if tonumber(record.bossIdentityVersion) ~= 2 then record.bossIdentityVersion = 2; changed = true end
    if record.label ~= desiredLabel then record.label = desiredLabel; changed = true end

    if record.summaryOnly == true then
        if tonumber(record.priority) ~= 4 then record.priority = 4; changed = true end
    else
        if tonumber(record.archivePriority) ~= 4 then record.archivePriority = 4; changed = true end
        if record.archiveKind ~= nil and record.archiveKind ~= "boss" then record.archiveKind = "boss"; changed = true end
    end

    return changed
end

local function BG2_GetArchiveProfile(owner)
    local key = BG2_ProfileKey(owner)
    local db = MainTankArchiveDB
    return key and type(db) == "table" and type(db.profiles) == "table" and db.profiles[key] or nil
end

local function BG2_GetHistoryProfile(owner)
    local key = BG2_ProfileKey(owner)
    local db = MainTankHistoryDB
    return key and type(db) == "table" and type(db.profiles) == "table" and db.profiles[key] or nil
end

local function BG2_RefreshManifests(owner)
    if owner and owner.RefreshStorageManifestsForUI then
        owner:RefreshStorageManifestsForUI()
    end
end

local function BG2_RepairAll(owner)
    if type(owner) ~= "table" then return 0 end
    local changed = 0
    local i

    for i = 1, table.getn(owner.fights or {}) do
        if BG2_RepairRecord(owner, owner.fights[i]) then changed = changed + 1 end
    end

    local ap = BG2_GetArchiveProfile(owner)
    if ap and type(ap.fights) == "table" then
        for i = 1, table.getn(ap.fights) do
            if BG2_RepairRecord(owner, ap.fights[i]) then changed = changed + 1 end
        end
    end

    local hp = BG2_GetHistoryProfile(owner)
    if hp and type(hp.summaries) == "table" then
        for i = 1, table.getn(hp.summaries) do
            if BG2_RepairRecord(owner, hp.summaries[i]) then changed = changed + 1 end
        end
    end

    if changed > 0 then BG2_RefreshManifests(owner) end
    return changed
end

-- Consolidation.lua owns the current Archive priority implementation with local
-- helpers, so its old primary-only C_IsBoss cannot be monkey-patched directly.
-- Before one archive transaction, temporarily present every exact secondary
-- Boss record as primary-Boss solely to that legacy retention pass.  The copy
-- receives BOSS priority 4, then the original analytical primaryEnemy is put
-- back immediately and BOSSGUARD2 repairs every exact record in all stores.
local function BG2_PrimeRecord(owner, record, saved)
    if type(record) ~= "table" or BG2_IsPvP(record) then return end
    local profile = BG2_FindExactBossProfile(owner, record)
    if not profile then return end
    if record.primaryEnemy == profile.name then return end

    table.insert(saved, {
        record = record,
        primaryEnemy = record.primaryEnemy,
        isBoss = record.isBoss,
        bossName = record.bossName,
        bossSkull = record.bossSkull,
        bossEncounterSkull = record.bossEncounterSkull,
        bossIdentityVersion = record.bossIdentityVersion,
        archivePriority = record.archivePriority,
        archiveKind = record.archiveKind,
    })

    record.primaryEnemy = profile.name
    record.isBoss = true
    record.bossName = profile.name
    record.bossSkull = true
    record.bossEncounterSkull = true
    record.bossIdentityVersion = 2
    record.archivePriority = 4
    record.archiveKind = "boss"
end

local function BG2_PrimeArchiveTransaction(owner, incoming)
    local saved = {}
    BG2_PrimeRecord(owner, incoming, saved)
    local ap = BG2_GetArchiveProfile(owner)
    local i
    if ap and type(ap.fights) == "table" then
        for i = 1, table.getn(ap.fights) do BG2_PrimeRecord(owner, ap.fights[i], saved) end
    end
    return saved
end

local function BG2_RestorePrimed(saved)
    local i, s, record
    for i = 1, table.getn(saved or {}) do
        s = saved[i]
        record = s and s.record
        if type(record) == "table" then
            record.primaryEnemy = s.primaryEnemy
            record.isBoss = s.isBoss
            record.bossName = s.bossName
            record.bossSkull = s.bossSkull
            record.bossEncounterSkull = s.bossEncounterSkull
            record.bossIdentityVersion = s.bossIdentityVersion
            record.archivePriority = s.archivePriority
            record.archiveKind = s.archiveKind
        end
    end
end

local BG2_PreviousArchiveFight = MT.ArchiveFight
if BG2_PreviousArchiveFight then
    function MT:ArchiveFight(fight, silent)
        local saved = BG2_PrimeArchiveTransaction(self, fight)
        local ok, result = pcall(BG2_PreviousArchiveFight, self, fight, silent)
        BG2_RestorePrimed(saved)
        BG2_RepairAll(self)
        if not ok then error(result) end
        return result
    end
end

-- The existing Boss Profile layer creates authoritative profiles only after its
-- wrapped EndCombat has finalized the fight and assigned fightID.  Running this
-- wrapper after that layer gives BOSSGUARD2 exact encounter identity without a
-- second parser or any new combat-event accounting.
local BG2_PreviousEndCombat = MT.EndCombat
if BG2_PreviousEndCombat then
    function MT:EndCombat()
        BG2_PreviousEndCombat(self)
        local changed = BG2_RepairAll(self)
        if changed > 0 and self.SyncPersistentData then self:SyncPersistentData() end
    end
end

-- Public diagnostic/repair hook.  Safe to run repeatedly; exact matches are
-- idempotent and do not modify combat totals.
function MT:RepairBossGuard2()
    local changed = BG2_RepairAll(self)
    if changed > 0 and self.SyncPersistentData then self:SyncPersistentData() end
    return changed
end

-- BossProfilePersistence.lua also performs an older primary-only repair at
-- PLAYER_ENTERING_WORLD.  Wait one frame after that event, then apply the newer
-- exact-fight rule so legacy records (including summary-only History) finish in
-- their BOSSGUARD2 state.  No timers/libraries beyond Vanilla 1.12 are required.
MainTankBossGuard2RepairFrame = MainTankBossGuard2RepairFrame or CreateFrame("Frame", "MainTankBossGuard2RepairFrame")
MainTankBossGuard2RepairFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
MainTankBossGuard2RepairFrame:SetScript("OnEvent", function()
    this.bg2Pending = true
    this.bg2At = GetTime() + 0.05
    this:Show()
end)
MainTankBossGuard2RepairFrame:SetScript("OnUpdate", function()
    if not this.bg2Pending then return end
    if GetTime() < (this.bg2At or 0) then return end
    this.bg2Pending = nil
    this:Hide()
    if not MainTank then return end
    local changed = BG2_RepairAll(MainTank)
    if changed > 0 and MainTank.SyncPersistentData then MainTank:SyncPersistentData() end
end)
MainTankBossGuard2RepairFrame:Hide()
