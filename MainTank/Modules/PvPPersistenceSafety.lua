-- MainTank v1.2.3 RELEASEGUARD1
-- PvP persistence hardening layered on top of PVPSAFETY2 + MAGICBLOCK1.
--
-- Fixes confirmed from the Khanvict Blessing of Sanctuary reflect specimen:
--   * confirmed PvP must not learn contextMemory or global ability schools;
--   * out-of-combat PvP retaliation/proc damage must never be allowed to mutate
--     Current/Overall without belonging to a finalized fight;
--   * a narrow preflight repairs the affected pure-PvP no-archive profile shape
--     before the established DC2/Pass-2B restore chain runs.
--
-- This module deliberately does NOT rebuild/alias Current or Overall during the
-- normal restore path.  Its recovery path edits only the raw SavedVariables
-- profile when it detects the exact bounded pure-PvP orphan condition.

if not MainTank then return end
local MT = MainTank

local P3_VERSION = 5
local P3_SYNTHETIC_IDLE = 2.0

local function P3_CopyTable(source)
    if type(source) ~= "table" then return source end
    local out = {}
    local k, v
    for k, v in pairs(source) do
        if type(v) == "table" then out[k] = P3_CopyTable(v) else out[k] = v end
    end
    return out
end

local function P3_TrimLower(text)
    text = tostring(text or "")
    text = string.gsub(text, "^%s+", "")
    text = string.gsub(text, "%s+$", "")
    return string.lower(text)
end

local function P3_Count(t)
    local n = 0
    local _
    for _ in pairs(t or {}) do n = n + 1 end
    return n
end

local function P3_IsPvPFight(fight)
    return type(fight) == "table" and (fight.combatType == "PVP" or fight.pvp == true)
end

local function P3_NoArchivedRecords(profile)
    if type(profile) ~= "table" then return true end
    if type(profile.archiveFights) == "table" and P3_Count(profile.archiveFights) > 0 then return false end
    if type(profile.archiveManifest) == "table" and P3_Count(profile.archiveManifest) > 0 then return false end
    if type(profile.historySummaries) == "table" and P3_Count(profile.historySummaries) > 0 then return false end
    return true
end

local P3_SUM_FIELDS = {
    "rawIncoming", "physicalRaw", "magicRaw", "damageTaken", "physicalTaken", "magicTaken",
    "armorReduced", "blocked", "physicalBlocked", "magicBlocked", "fullBlockedEstimated",
    "physicalFullBlockedEstimated", "magicFullBlockedEstimated", "absorbed", "physicalAbsorb",
    "magicAbsorb", "resistedPartial", "resistedFullEstimated", "dodgedEstimated",
    "parriedEstimated", "missedEstimated", "dodgeCount", "parryCount", "missCount",
    "blockCount", "totalPartialBlock", "fullBlockCount", "partialResistCount", "fullResistCount",
    "absorbCount", "meleeHitCount", "magicHitCount", "flatDR", "physicalFlatDR", "magicFlatDR",
    "physicalDR", "magicDR"
}

local function P3_NewAggregate()
    local d = {schools = {}, mobs = {}, minPartialBlock = nil, maxPartialBlock = 0}
    local i
    for i = 1, table.getn(P3_SUM_FIELDS) do d[P3_SUM_FIELDS[i]] = 0 end
    return d
end

local function P3_AddNumericTable(dst, src)
    if type(src) ~= "table" then return end
    local k, v
    for k, v in pairs(src) do
        if type(v) == "number" then dst[k] = (tonumber(dst[k]) or 0) + v end
    end
end

local function P3_AddFightData(dst, src)
    if type(src) ~= "table" then return end
    local i, field, v, name
    for i = 1, table.getn(P3_SUM_FIELDS) do
        field = P3_SUM_FIELDS[i]
        dst[field] = (tonumber(dst[field]) or 0) + (tonumber(src[field]) or 0)
    end
    v = tonumber(src.minPartialBlock)
    if v and (not dst.minPartialBlock or v < dst.minPartialBlock) then dst.minPartialBlock = v end
    v = tonumber(src.maxPartialBlock) or 0
    if v > (tonumber(dst.maxPartialBlock) or 0) then dst.maxPartialBlock = v end

    for name, v in pairs(src.schools or {}) do
        if type(v) == "table" then
            if not dst.schools[name] then dst.schools[name] = {} end
            P3_AddNumericTable(dst.schools[name], v)
        end
    end
    for name, v in pairs(src.mobs or {}) do
        if type(v) == "table" then
            if not dst.mobs[name] then dst.mobs[name] = {} end
            P3_AddNumericTable(dst.mobs[name], v)
            if tonumber(v.blockMin) then
                if not dst.mobs[name].blockMin or tonumber(v.blockMin) < dst.mobs[name].blockMin then
                    dst.mobs[name].blockMin = tonumber(v.blockMin)
                end
            end
            if tonumber(v.blockMax) and tonumber(v.blockMax) > (tonumber(dst.mobs[name].blockMax) or 0) then
                dst.mobs[name].blockMax = tonumber(v.blockMax)
            end
        end
    end
end

local function P3_NewTimelineBucket(second)
    return {second=second or 0, raw=0, armor=0, block=0, avoidance=0, resist=0, absorb=0,
            taken=0, physicalTaken=0, magicTaken=0, physicalRaw=0, magicRaw=0, events=0}
end

local function P3_AddTimelineEvent(root, eventData, absoluteTime)
    if type(eventData) ~= "table" then return end
    local second = math.floor(tonumber(absoluteTime) or 0)
    if second < 0 then second = 0 end
    if not root[second] then root[second] = P3_NewTimelineBucket(second) end
    local b = root[second]
    b.raw = b.raw + (tonumber(eventData.raw) or 0)
    b.armor = b.armor + (tonumber(eventData.armor) or 0)
    b.block = b.block + (tonumber(eventData.block) or 0)
    b.avoidance = b.avoidance + (tonumber(eventData.avoidance) or 0)
    b.resist = b.resist + (tonumber(eventData.resist) or 0)
    b.absorb = b.absorb + (tonumber(eventData.absorb) or 0)
    b.taken = b.taken + (tonumber(eventData.taken) or 0)
    if (eventData.school or "Physical") == "Physical" then
        b.physicalTaken = b.physicalTaken + (tonumber(eventData.taken) or 0)
    else
        b.magicTaken = b.magicTaken + (tonumber(eventData.taken) or 0)
    end
    b.physicalRaw = b.physicalRaw + (tonumber(eventData.physicalRaw) or 0)
    b.magicRaw = b.magicRaw + (tonumber(eventData.magicRaw) or 0)
    b.events = b.events + 1
end

local function P3_RebuildPurePvPOverall(profile)
    local fights = profile and profile.fights or {}
    local aggregate = P3_NewAggregate()
    local timeline = {}
    local fallbackOffset = 0
    local maxTime = 0
    local i, j, fight, offset, e, t

    -- Fights are newest-first. Rebuild in chronological order.
    for i = table.getn(fights), 1, -1 do
        fight = fights[i]
        if type(fight) == "table" then
            P3_AddFightData(aggregate, fight.data or {})
            offset = tonumber(fight.overallOffset)
            if offset == nil then offset = fallbackOffset end
            for j = 1, table.getn(fight.events or {}) do
                e = fight.events[j]
                t = offset + (tonumber(e and e.time) or 0)
                P3_AddTimelineEvent(timeline, e, t)
                if t > maxTime then maxTime = t end
            end
            fallbackOffset = math.max(fallbackOffset, offset + (tonumber(fight.duration) or 0))
        end
    end

    profile.overallData = aggregate
    profile.overallTimeline = timeline
    profile.overallElapsed = math.floor(maxTime)
    profile.overallCombatElapsed = fallbackOffset
    profile.overallCombatTimelineVersion = 1
end

local function P3_CollectPvPLearning(profile)
    local pvpSources, pvpAbilities, pveAbilities = {}, {}, {}
    local i, j, fight, e, key
    for i = 1, table.getn(profile and profile.fights or {}) do
        fight = profile.fights[i]
        for j = 1, table.getn(fight and fight.events or {}) do
            e = fight.events[j]
            if type(e) == "table" then
                key = P3_TrimLower(e.ability)
                if e.sourceType == "PVP" then
                    if e.source and e.source ~= "" then pvpSources[e.source] = true end
                    if key ~= "" then pvpAbilities[key] = true end
                elseif e.sourceType == "PVE" then
                    if key ~= "" then pveAbilities[key] = true end
                end
            end
        end
    end
    return pvpSources, pvpAbilities, pveAbilities
end

local function P3_ScrubPersistedPvPLearning(profile)
    if type(profile) ~= "table" then return false end
    local pvpSources, pvpAbilities, pveAbilities = P3_CollectPvPLearning(profile)
    if P3_Count(pvpSources) == 0 and P3_Count(pvpAbilities) == 0 then return false end

    local changed = false
    local contextID, perSource, source
    for contextID, perSource in pairs(profile.contextMemory or {}) do
        if type(perSource) == "table" then
            for source in pairs(pvpSources) do
                if perSource[source] ~= nil then perSource[source] = nil; changed = true end
            end
            if P3_Count(perSource) == 0 then profile.contextMemory[contextID] = nil end
        end
    end

    for source in pairs(pvpSources) do
        if profile.abilitySchoolMemory and profile.abilitySchoolMemory[source] ~= nil then
            profile.abilitySchoolMemory[source] = nil
            changed = true
        end
        if profile.encounterMemory and profile.encounterMemory[source] ~= nil then
            profile.encounterMemory[source] = nil
            changed = true
        end
        if profile.sessionMemory and profile.sessionMemory[source] ~= nil then
            profile.sessionMemory[source] = nil
            changed = true
        end
        if profile.targetDamageMemory and profile.targetDamageMemory[source] ~= nil then
            profile.targetDamageMemory[source] = nil
            changed = true
        end
    end

    local ability
    for ability in pairs(pvpAbilities) do
        if not pveAbilities[ability] and profile.globalAbilitySchoolMemory and profile.globalAbilitySchoolMemory[ability] ~= nil then
            profile.globalAbilitySchoolMemory[ability] = nil
            changed = true
        end
    end
    return changed
end

local function P3_PreflightProfile(owner)
    if type(MainTankDB) ~= "table" or type(MainTankDB.profiles) ~= "table" then return end
    local key = owner.profileKey or (owner.GetProfileKey and owner:GetProfileKey())
    local p = key and MainTankDB.profiles[key]
    if type(p) ~= "table" then return end
    -- SAFETY5: never skip the bounded consistency scan just because an earlier
    -- login already passed it.  A NEW PvP reflect tail can be created later.
    -- pvpSafetyPreflightVersion is diagnostic only, not a one-shot gate.
    P3_ScrubPersistedPvPLearning(p)

    -- Narrow recovery for the observed PVPSAFETY2 reflect bug only:
    -- no archived/history records, every finalized fight is PvP, and persisted
    -- Overall RAW exceeds the sum of finalized fight RAW.  That shape means
    -- out-of-combat PvP retaliation mutated Overall after a fight finalized.
    local fights = p.fights or {}
    local count = table.getn(fights)
    if count < 1 or not P3_NoArchivedRecords(p) then return end

    local allPvP = true
    local fightRaw = 0
    local i, f
    for i = 1, count do
        f = fights[i]
        if not P3_IsPvPFight(f) then allPvP = false; break end
        fightRaw = fightRaw + (tonumber(f and f.data and f.data.rawIncoming) or 0)
    end
    if not allPvP then return end

    local overallRaw = tonumber(p.overallData and p.overallData.rawIncoming) or 0
    if overallRaw > fightRaw + 0.01 then
        local orphanRaw = overallRaw - fightRaw
        P3_RebuildPurePvPOverall(p)
        p.pvpSafetyRecoveryVersion = P3_VERSION
        p.pvpSafetyRecoveryCount = (tonumber(p.pvpSafetyRecoveryCount) or 0) + 1
        p.pvpSafetyRecoveredRaw = orphanRaw
        p.sessionDirty = false
        p.sessionDirtyAt = nil
        p.currentEventsInProgress = nil
        p.currentEventOverallOffset = nil
        p.events = nil
        -- Hard-quarantine the exact poisonable transient/runtime fields from the
        -- observed reflect specimen.  The authoritative finalized fights remain.
        -- This is intentionally narrower than DC1 and only runs for the bounded
        -- all-PvP/no-archive Overall>fights mismatch shape.
        p.pending = {}
        p.encounterMemory = {}
        p.contextMemory = {}
        p.mitigationContexts = {}
        p.contextSnapshotPool = {}
        p.abilitySchoolMemory = {}
        p.globalAbilitySchoolMemory = {}
        p.sessionMemory = {}
        p.events = nil
        p.currentEventsInProgress = nil
        p.currentEventOverallOffset = nil
        if p.fights and p.fights[1] then
            p.data = P3_CopyTable(p.fights[1].data or {})
            p.timeline = P3_CopyTable(p.fights[1].timeline or {})
            p.enemyDeathCounts = P3_CopyTable(p.fights[1].enemyDeathCounts or {})
        end

        owner.pvpSafetyRecoveryPendingNotice = true
        owner.pvpSafetyRecoveredRaw = orphanRaw
    end
    p.pvpSafetyPreflightVersion = P3_VERSION
end

-- PVPSAFETY4: run the repair at ADDON_LOADED too. SavedVariables are available
-- at this point, which is earlier than VARIABLES_LOADED/Initialize. This avoids
-- asking the mature migration/restore chain to even inspect the known bad shape.
P3_PreflightFrame = P3_PreflightFrame or CreateFrame("Frame", "MainTankPVPSafety4PreflightFrame")
P3_PreflightFrame:RegisterEvent("ADDON_LOADED")
P3_PreflightFrame:SetScript("OnEvent", function()
    if event == "ADDON_LOADED" and arg1 == "MainTank" and MainTank then
        P3_PreflightProfile(MainTank)
    end
end)

-- Keep the Initialize wrapper as a second idempotent safety net.
local P3_OldInitialize = MT.Initialize
function MT:Initialize()
    P3_PreflightProfile(self)
    P3_OldInitialize(self)
end

-- Prevent PvP learning even though SchoolMemory.lua loads after PVPSAFETY2.
-- The outer RecordDamage wrapper sets this flag while the full mature engine
-- processes a confirmed PvP event.
local P3_OldLearnAbilitySchool = MT.LearnAbilitySchool
function MT:LearnAbilitySchool(mob, ability, school)
    if self._mtSuppressPvPLearning then return end
    return P3_OldLearnAbilitySchool(self, mob, ability, school)
end

-- A confirmed PvP hit that arrives after PLAYER_REGEN_ENABLED used to be added
-- to Current/Overall while MainTank.inCombat was false.  FR1X correctly strips
-- non-combat profile.events at logout, leaving those hits orphaned in Overall.
-- Open a tiny synthetic PvP combat instead, coalesce nearby retaliation ticks,
-- and finalize it after a short idle window.
local P3_OldRecordDamage = MT.RecordDamage
function MT:RecordDamage(mob, attack, amountTaken, blocked, resisted, absorbed, school, isCrit, hitType, ignoreArmor)
    local isPvP = self.IsConfirmedPvPSource and self:IsConfirmedPvPSource(mob)
    if isPvP and not self.inCombat then
        self:StartCombat()
        self._mtSyntheticPvPCombat = true
        self._mtSyntheticPvPDeadline = (GetTime and GetTime() or 0) + P3_SYNTHETIC_IDLE
    end

    if not isPvP then
        return P3_OldRecordDamage(self, mob, attack, amountTaken, blocked, resisted, absorbed, school, isCrit, hitType, ignoreArmor)
    end

    local oldContextMemory = self.contextMemory
    local oldSuppress = self._mtSuppressPvPLearning
    self.contextMemory = {}
    self._mtSuppressPvPLearning = true

    P3_OldRecordDamage(self, mob, attack, amountTaken, blocked, resisted, absorbed, school, isCrit, hitType, ignoreArmor)

    self.contextMemory = oldContextMemory
    self._mtSuppressPvPLearning = oldSuppress
    if self._mtSyntheticPvPCombat then
        self._mtSyntheticPvPDeadline = (GetTime and GetTime() or 0) + P3_SYNTHETIC_IDLE
    end
end

-- If a genuine PLAYER_REGEN_DISABLED arrives while a synthetic PvP tail is
-- open, convert that tail into the real combat instead of resetting it.
local P3_OldStartCombat = MT.StartCombat
function MT:StartCombat()
    if self._mtSyntheticPvPCombat then
        self._mtSyntheticPvPCombat = nil
        self._mtSyntheticPvPDeadline = nil
        self.inCombat = true
        return
    end
    return P3_OldStartCombat(self)
end

local P3_OldEndCombat = MT.EndCombat
function MT:EndCombat()
    self._mtSyntheticPvPCombat = nil
    self._mtSyntheticPvPDeadline = nil
    return P3_OldEndCombat(self)
end

-- Small independent timer; no changes to the mature eventFrame/DC2 chain.
P3_Frame = P3_Frame or CreateFrame("Frame", "MainTankPVPSafety3Frame")
P3_Frame:SetScript("OnUpdate", function()
    if not MainTank or not MainTank._mtSyntheticPvPCombat then return end
    local now = GetTime and GetTime() or 0
    if MainTank._mtSyntheticPvPDeadline and now >= MainTank._mtSyntheticPvPDeadline then
        if UnitAffectingCombat and UnitAffectingCombat("player") then
            MainTank._mtSyntheticPvPCombat = nil
            MainTank._mtSyntheticPvPDeadline = nil
        else
            MainTank:EndCombat()
        end
    end
end)





-- SAFETY6: pure PvP fights must never persist RC6 mitigation-context graphs.
-- The finalized event already stores its authoritative taken/raw/block/resist/
-- absorb/flatDR/physicalDR/magicDR numbers.  Keeping contextID snapshots for a
-- pure PvP fight is therefore unnecessary, and the Khanvict Sanctuary reflect
-- reproduction proved that those player-attributed context graphs can poison
-- startup even when Overall and finalized-fight totals are perfectly coherent.
local function P6_IsPvPFight(f)
    return type(f) == "table" and (f.combatType == "PVP" or f.pvp == true)
end

local function P6_StripEventContext(e)
    if type(e) ~= "table" then return end
    e.contextID = nil
    e.context = nil
    e.rc6ContextSnapshot = nil
end

local function P6_StripPurePvPFightContexts(fights)
    local i, j, f
    for i = 1, table.getn(fights or {}) do
        f = fights[i]
        if P6_IsPvPFight(f) then
            for j = 1, table.getn(f.events or {}) do
                P6_StripEventContext(f.events[j])
            end
            -- Consolidated archive copies may carry a fight-local pool.
            f.contextSnapshots = nil
        end
    end
end

local function P6_CollectPvEContextIDs(fights, used)
    local i, j, f, e, id
    for i = 1, table.getn(fights or {}) do
        f = fights[i]
        if type(f) == "table" and not P6_IsPvPFight(f) then
            for j = 1, table.getn(f.events or {}) do
                e = f.events[j]
                id = type(e) == "table" and (e.contextID or e.context) or nil
                if id ~= nil then used[id] = true end
            end
        end
    end
end

local function P6_PruneProfileContextPools(profile)
    if type(profile) ~= "table" then return end
    -- RELEASEGUARD1: quarantine pure-PvP context graphs everywhere a detailed
    -- fight can live, not only in Recent.  Archive is bounded too, and a public
    -- release should never leave an old pure-PvP graph hiding in the same
    -- MainTankDB SavedVariables file.
    P6_StripPurePvPFightContexts(profile.fights)
    P6_StripPurePvPFightContexts(profile.archiveFights)

    local used = {}
    P6_CollectPvEContextIDs(profile.fights, used)
    P6_CollectPvEContextIDs(profile.archiveFights, used)

    -- Preserve unfinished Current context only when it is not confirmed pure PvP.
    local currentIsPvP = false
    if profile.currentEventsInProgress and type(profile.events) == "table" and table.getn(profile.events) > 0 then
        currentIsPvP = true
        local i, e
        for i = 1, table.getn(profile.events) do
            e = profile.events[i]
            if type(e) ~= "table" or e.sourceType ~= "PVP" then currentIsPvP = false; break end
        end
        if currentIsPvP then
            local i
            for i = 1, table.getn(profile.events) do P6_StripEventContext(profile.events[i]) end
        else
            local i, e, id
            for i = 1, table.getn(profile.events) do
                e = profile.events[i]
                id = type(e) == "table" and (e.contextID or e.context) or nil
                if id ~= nil then used[id] = true end
            end
        end
    end

    local function filterPool(pool)
        if type(pool) ~= "table" then return {} end
        local out, k, v = {}
        for k, v in pairs(pool) do
            if used[k] then out[k] = v end
        end
        return out
    end

    profile.contextSnapshotPool = filterPool(profile.contextSnapshotPool)
    profile.mitigationContexts = filterPool(profile.mitigationContexts)
    profile.compactContextPool = filterPool(profile.compactContextPool)
    profile.pvpContextQuarantineVersion = 7
end

local function P6_PruneAllProfiles()
    if type(MainTankDB) ~= "table" or type(MainTankDB.profiles) ~= "table" then return end
    local _, profile
    for _, profile in pairs(MainTankDB.profiles) do
        if type(profile) == "table" then P6_PruneProfileContextPools(profile) end
    end
end


-- SAFETY6 runs independently of the older mismatch repair.  This is important:
-- the newest Khanvict specimen has Overall 1404 RAW / 39 hits and finalized
-- fights totaling exactly 1404 RAW / 39 hits, yet still freezes.  Therefore
-- context quarantine must run even when no accounting mismatch exists.
P6_PreflightFrame = P6_PreflightFrame or CreateFrame("Frame", "MainTankPVPSafety6ContextPreflightFrame")
P6_PreflightFrame:RegisterEvent("ADDON_LOADED")
P6_PreflightFrame:SetScript("OnEvent", function()
    if event == "ADDON_LOADED" and arg1 == "MainTank" and MainTankDB and MainTank then
        -- RELEASEGUARD1: SavedVariables is one file containing every MainTank
        -- profile.  Sanitize all profiles before the mature restore chain sees
        -- them so an alt's stale PvP context graph cannot remain latent.
        P6_PruneAllProfiles()
    end
end)
-- SAFETY5: PLAYER_LOGOUT reaches the mature Core event frame before this module's
-- own event frames, so a separate PLAYER_LOGOUT handler would be too late.
-- Instead, wrap SyncPersistentData at the outermost module layer.  If a short
-- synthetic PvP retaliation tail is still open, finalize it FIRST. EndCombat's
-- internal SyncPersistentData call re-enters this wrapper after the synthetic
-- flag has been cleared, so the guard prevents recursion and the finalized
-- fight is what gets written to SavedVariables.
local P5_OldSyncPersistentData = MT.SyncPersistentData
function MT:SyncPersistentData()
    if self._mtSyntheticPvPCombat and not self._mtPvPFinalizeForSync then
        self._mtPvPFinalizeForSync = true
        self:EndCombat()
        self._mtPvPFinalizeForSync = nil
        return
    end

    -- Strip pure-PvP event context references before FR1K compaction can copy
    -- them back into contextSnapshotPool.  Keep only contexts still referenced
    -- by PvE fights.
    P6_StripPurePvPFightContexts(self.fights)
    if self.profile then P6_PruneProfileContextPools(self.profile) end
    P6_PruneAllProfiles()

    local oldMitigationContexts = self.mitigationContexts
    local used, filtered = {}, {}
    P6_CollectPvEContextIDs(self.fights, used)
    if type(oldMitigationContexts) == "table" then
        local k, v
        for k, v in pairs(oldMitigationContexts) do
            if used[k] then filtered[k] = v end
        end
    end
    self.mitigationContexts = filtered
    local result = P5_OldSyncPersistentData(self)
    self.mitigationContexts = oldMitigationContexts
    if self.profile then P6_PruneProfileContextPools(self.profile) end
    P6_PruneAllProfiles()
    return result
end

-- Surface one recovery message only after the character reaches the world.
P3_NoticeFrame = P3_NoticeFrame or CreateFrame("Frame", "MainTankPVPSafety3NoticeFrame")
P3_NoticeFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
P3_NoticeFrame:SetScript("OnEvent", function()
    if MainTank and MainTank.pvpSafetyRecoveryPendingNotice then
        if MainTank.PrintMessage then
            MainTank:PrintMessage("PVPSAFETY5 repaired orphaned PvP reflect data before restore (" .. tostring(math.floor((MainTank.pvpSafetyRecoveredRaw or 0) + 0.5)) .. " RAW reconciled). Finalized fights were preserved.")
        end
        MainTank.pvpSafetyRecoveryPendingNotice = nil
        MainTank.pvpSafetyRecoveredRaw = nil
    end
end)
