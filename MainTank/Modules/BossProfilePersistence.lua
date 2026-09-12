-- MainTank v1.2.47 BOSSPROFILE2 - Boss Profile persistence hardening
--
-- Loaded late on purpose. Historical MainTank/MT modules wrap SyncPersistentData
-- and RestorePersistentData in several layers. This final coordinator guarantees
-- bossHistory survives any profile rebind performed by an earlier wrapper.

if not MainTank then return end
local MT = MainTank

local function BP_Profile(owner)
    if owner.profile then return owner.profile end
    if not MainTankDB then MainTankDB = {} end
    MainTankDB.profiles = MainTankDB.profiles or {}
    local key = owner.profileKey or (owner.GetProfileKey and owner:GetProfileKey())
    if not key then return nil end
    MainTankDB.profiles[key] = MainTankDB.profiles[key] or {}
    owner.profile = MainTankDB.profiles[key]
    return owner.profile
end


local function BP_BossNameSet(owner)
    local names, _, profile, name, memory, i, fight = {}, nil, nil, nil, nil, nil, nil
    for _, profile in ipairs(owner and owner.bossHistory or {}) do
        if profile and profile.name then names[profile.name] = true end
    end
    -- targetDamageMemory.isBoss is set only from UnitLevel("target") == -1.
    -- Keep it as an independent authoritative skull-level identity source so
    -- Boss Profile recovery still works if bossHistory itself was clobbered by
    -- an older restore-order bug.
    for name, memory in pairs(owner and owner.targetDamageMemory or {}) do
        if type(memory) == "table" and memory.isBoss == true then names[name] = true end
    end
    -- BOSSPROFILE1 adds a fight-local skull marker only at the exact live
    -- UnitLevel == -1 finalization boundary. Unlike old isBoss flags, this
    -- marker can safely authenticate retained detailed encounters even if both
    -- target memory and the standalone profile table were later lost.
    for i = 1, table.getn(owner and owner.fights or {}) do
        fight = owner.fights[i]
        if fight and fight.bossSkull == true and fight.primaryEnemy and fight.bossName == fight.primaryEnemy then
            names[fight.primaryEnemy] = true
        end
    end
    local key = owner and (owner.profileKey or (owner.GetProfileKey and owner:GetProfileKey()))
    local ap = key and MainTankArchiveDB and MainTankArchiveDB.profiles and MainTankArchiveDB.profiles[key]
    if ap and type(ap.fights) == "table" then
        for i = 1, table.getn(ap.fights) do
            fight = ap.fights[i]
            if fight and fight.bossSkull == true and fight.primaryEnemy and fight.bossName == fight.primaryEnemy then
                names[fight.primaryEnemy] = true
            end
        end
    end
    return names
end

local function BP_FightRaw(fight)
    if type(fight) ~= "table" then return 0 end
    local data = fight.data or {}
    local raw = tonumber(data.rawIncoming) or tonumber(data.raw) or tonumber(fight.raw)
    if raw ~= nil then return raw end
    raw = 0
    local i, e
    for i = 1, table.getn(fight.events or {}) do
        e = fight.events[i]
        raw = raw + (tonumber(e and e.raw) or 0)
    end
    return raw
end


local function BP_PeekStoredProfile(owner)
    if type(MainTankDB) ~= "table" or type(MainTankDB.profiles) ~= "table" then return nil end
    local key = owner and (owner.profileKey or (owner.GetProfileKey and owner:GetProfileKey()))
    if not key then return nil end
    return MainTankDB.profiles[key]
end

local function BP_IsEnvironmentalEvent(event)
    if type(event) ~= "table" then return false end
    if event.environmental then return true end
    if event.source == "Environment" then return true end
    return false
end

local function BP_SortRows(rows)
    table.sort(rows, function(a, b)
        if (a.raw or 0) == (b.raw or 0) then
            return tostring(a.name or "") < tostring(b.name or "")
        end
        return (a.raw or 0) > (b.raw or 0)
    end)
end

-- Rebuild a Boss Profile exclusively from authoritative detailed encounter
-- events. This is a recovery path, not a second combat-accounting engine: every
-- number is summed from the same finalized event fields already used by RC6.
local function BP_BuildProfileFromFight(fight, bossName)
    if type(fight) ~= "table" or type(fight.events) ~= "table" then return nil end
    bossName = bossName or fight.bossName or fight.primaryEnemy
    if not bossName or bossName == "" then return nil end

    local profile = {
        name = bossName,
        label = bossName,
        duration = tonumber(fight.duration) or 0,
        raw = 0, taken = 0, armor = 0, avoidance = 0, block = 0,
        resist = 0, absorb = 0, flatDR = 0, physicalDR = 0, magicDR = 0,
        events = 0, criticals = 0, crushings = 0, addsRaw = 0,
        schoolsMap = {}, abilitiesMap = {}, schools = {}, abilities = {},
        fightID = fight.id,
        primaryEnemy = fight.primaryEnemy,
        savedAt = tonumber(fight.savedAt),
        recovered = true,
        bossProfileVersion = 2
    }

    local totalEnemyRaw = 0
    local i, event, source, raw, taken, school, ability, row
    for i = 1, table.getn(fight.events or {}) do
        event = fight.events[i]
        if not BP_IsEnvironmentalEvent(event) then
            source = event.source or "Unknown"
            raw = tonumber(event.raw) or 0
            totalEnemyRaw = totalEnemyRaw + raw
            if source == bossName then
                taken = tonumber(event.taken) or 0
                school = event.school or "Unknown"
                ability = event.ability or event.kind or "Unknown"

                profile.raw = profile.raw + raw
                profile.taken = profile.taken + taken
                profile.armor = profile.armor + (tonumber(event.armor) or 0)
                profile.avoidance = profile.avoidance + (tonumber(event.avoidance) or 0)
                profile.block = profile.block + (tonumber(event.block) or 0)
                profile.resist = profile.resist + (tonumber(event.resist) or 0)
                profile.absorb = profile.absorb + (tonumber(event.absorb) or 0)
                profile.flatDR = profile.flatDR + (tonumber(event.flatDR) or 0)
                profile.physicalDR = profile.physicalDR + (tonumber(event.physicalDR) or 0)
                profile.magicDR = profile.magicDR + (tonumber(event.magicDR) or 0)
                profile.events = profile.events + 1
                if event.critical then profile.criticals = profile.criticals + 1 end
                if event.crushing then profile.crushings = profile.crushings + 1 end

                row = profile.schoolsMap[school]
                if not row then row = {name=school, raw=0, taken=0}; profile.schoolsMap[school] = row end
                row.raw = row.raw + raw; row.taken = row.taken + taken

                row = profile.abilitiesMap[ability]
                if not row then
                    row = {name=ability, school=school, raw=0, taken=0}
                    profile.abilitiesMap[ability] = row
                end
                row.raw = row.raw + raw; row.taken = row.taken + taken
            end
        end
    end

    if profile.raw <= 0 then return nil end
    for _, row in pairs(profile.schoolsMap) do table.insert(profile.schools, row) end
    for _, row in pairs(profile.abilitiesMap) do table.insert(profile.abilities, row) end
    BP_SortRows(profile.schools); BP_SortRows(profile.abilities)
    profile.schoolsMap = nil; profile.abilitiesMap = nil
    profile.stopped = math.max(0, profile.raw - profile.taken)
    profile.mitigation = profile.raw > 0 and (profile.stopped / profile.raw * 100) or 0
    profile.addsRaw = math.max(0, totalEnemyRaw - profile.raw)
    profile.share = totalEnemyRaw > 0 and (profile.raw / totalEnemyRaw * 100) or 0
    return profile
end

local function BP_ProfileEquivalent(profile, candidate)
    if type(profile) ~= "table" or type(candidate) ~= "table" then return false end
    if profile.name ~= candidate.name then return false end
    if profile.fightID ~= nil and candidate.fightID ~= nil then
        return tostring(profile.fightID) == tostring(candidate.fightID)
    end
    -- Pre-fightID profiles can still be matched losslessly by the finalized
    -- boss-only headline totals; include duration when both sides have it.
    if math.abs((tonumber(profile.raw) or 0) - (tonumber(candidate.raw) or 0)) > 0.5 then return false end
    if math.abs((tonumber(profile.taken) or 0) - (tonumber(candidate.taken) or 0)) > 0.5 then return false end
    local a, b = tonumber(profile.duration) or 0, tonumber(candidate.duration) or 0
    if a > 0 and b > 0 and math.abs(a - b) > 1.0 then return false end
    return true
end

local function BP_EnrichProfileFromCandidate(profile, candidate)
    if type(profile) ~= "table" or type(candidate) ~= "table" then return false end
    local changed = false
    local oldVersion = tonumber(profile.bossProfileVersion)
    local fields = {"fightID","primaryEnemy","savedAt"}
    local i, field
    for i = 1, table.getn(fields) do
        field = fields[i]
        if profile[field] == nil and candidate[field] ~= nil then profile[field] = candidate[field]; changed = true end
    end
    -- Old RC3b profiles already have schools/abilities but no RC6 DR. If the
    -- exact detailed encounter still exists, refresh those profile-only totals.
    if oldVersion ~= 2 then
        profile.flatDR = candidate.flatDR or 0
        profile.physicalDR = candidate.physicalDR or 0
        profile.magicDR = candidate.magicDR or 0
        profile.absorb = candidate.absorb or profile.absorb or 0
        if (tonumber(candidate.duration) or 0) > 0 then profile.duration = candidate.duration end
        profile.addsRaw = candidate.addsRaw or profile.addsRaw or 0
        profile.share = candidate.share or profile.share or 0
        profile.schools = candidate.schools or profile.schools
        profile.abilities = candidate.abilities or profile.abilities
        profile.bossProfileVersion = 2
        changed = true
    end
    return changed
end

local function BP_AddProfileFromFight(owner, fight, bossNames)
    if type(fight) ~= "table" or fight.combatType == "PVP" or fight.pvp == true then return 0 end
    local primary = fight.primaryEnemy
    if not primary or not bossNames[primary] then return 0 end
    -- BOSSGUARD invariant: only the actual primary skull enemy may recover a
    -- Boss Profile. Merely targeting or touching another skull mob is ignored.
    local candidate = BP_BuildProfileFromFight(fight, primary)
    if not candidate then return 0 end
    owner.bossHistory = owner.bossHistory or {}
    local i, existing
    for i = 1, table.getn(owner.bossHistory) do
        existing = owner.bossHistory[i]
        if BP_ProfileEquivalent(existing, candidate) then
            return BP_EnrichProfileFromCandidate(existing, candidate) and 1 or 0
        end
    end
    table.insert(owner.bossHistory, candidate)
    return 1
end

local function BP_RecoverBossProfiles(owner, includeArchive)
    if type(owner) ~= "table" then return 0 end
    owner.bossHistory = owner.bossHistory or {}
    local bossNames = BP_BossNameSet(owner)
    if not next(bossNames) then return 0 end
    local changed, i = 0, nil
    for i = 1, table.getn(owner.fights or {}) do
        changed = changed + BP_AddProfileFromFight(owner, owner.fights[i], bossNames)
    end

    if includeArchive then
        local key = owner.profileKey or (owner.GetProfileKey and owner:GetProfileKey())
        local ap = key and MainTankArchiveDB and MainTankArchiveDB.profiles and MainTankArchiveDB.profiles[key]
        if ap and type(ap.fights) == "table" then
            for i = 1, table.getn(ap.fights) do
                changed = changed + BP_AddProfileFromFight(owner, ap.fights[i], bossNames)
            end
        end
    end

    while table.getn(owner.bossHistory) > 30 do table.remove(owner.bossHistory) end
    if changed > 0 then
        local count = table.getn(owner.bossHistory)
        owner.bossProfileIndex = tonumber(owner.bossProfileIndex) or 1
        if owner.bossProfileIndex < 1 then owner.bossProfileIndex = 1 end
        if count > 0 and owner.bossProfileIndex > count then owner.bossProfileIndex = count end
    end
    return changed
end

function MT:RecoverBossProfilesFromDetailedStorage(includeArchive)
    return BP_RecoverBossProfiles(self, includeArchive and true or false)
end

local function BP_RepairDetailedFight(fight, bossNames)
    if type(fight) ~= "table" or fight.combatType == "PVP" or fight.pvp == true then return false end

    local primary = fight.primaryEnemy
    if not primary then return false end

    -- BOSS means the known skull boss is the PRIMARY enemy of this fight.
    -- Never infer Boss merely from any boss event/source appearing in the pull.
    local shouldBoss = (fight.bossSkull == true and fight.bossName == primary) or (bossNames[primary] and true or false)
    -- Do not trust an old persisted isBoss/bossName stamp by itself here.
    -- BOSSPRIORITY1 briefly allowed a false primary stamp to survive; the
    -- authoritative skull identity must come from live/persisted UnitLevel -1
    -- memory or a real Boss Profile name. Detailed storage is bounded well
    -- below the 30-profile Boss history, so legitimate retained Boss fights
    -- remain covered by one of those sources.

    if shouldBoss then
        local changed = fight.isBoss ~= true or fight.bossName ~= primary or fight.archivePriority ~= 4
        fight.isBoss = true
        fight.bossName = primary
        fight.bossSkull = true
        fight.bossIdentityVersion = 1
        fight.archivePriority = 4
        if fight.archiveKind and fight.archiveKind ~= "boss" then
            fight.archiveKind = "boss"
            changed = true
        end
        return changed
    end

    -- Repair false-positive Boss stamps from v1.2.44.  Reclassify by the normal
    -- non-boss threshold without altering any fight totals/events.
    if fight.isBoss == true or fight.archivePriority == 4 or fight.archiveKind == "boss" then
        local raw = BP_FightRaw(fight)
        fight.isBoss = false
        fight.bossName = nil
        fight.bossSkull = nil
        fight.bossIdentityVersion = nil
        fight.archivePriority = raw >= 50000 and 3 or 2
        if fight.archiveKind then fight.archiveKind = raw >= 50000 and "50k" or "minor" end
        return true
    end
    return false
end

local function BP_RepairAllBossClassification(owner)
    if type(owner) ~= "table" or type(owner.bossHistory) ~= "table" then return 0 end
    local bossNames = BP_BossNameSet(owner)
    if not next(bossNames) then return 0 end

    local repaired, i, fight, summary = 0, nil, nil, nil
    for i = 1, table.getn(owner.fights or {}) do
        if BP_RepairDetailedFight(owner.fights[i], bossNames) then repaired = repaired + 1 end
    end

    local key = owner.profileKey or (owner.GetProfileKey and owner:GetProfileKey())
    local archiveProfile = key and MainTankArchiveDB and MainTankArchiveDB.profiles and MainTankArchiveDB.profiles[key]
    if archiveProfile and type(archiveProfile.fights) == "table" then
        for i = 1, table.getn(archiveProfile.fights) do
            if BP_RepairDetailedFight(archiveProfile.fights[i], bossNames) then repaired = repaired + 1 end
        end
    end

    -- History is summary-only, so repair only when its persisted identity is
    -- exact; never infer Boss from a fuzzy label after detailed events are gone.
    local historyProfile = key and MainTankHistoryDB and MainTankHistoryDB.profiles and MainTankHistoryDB.profiles[key]
    if historyProfile and type(historyProfile.summaries) == "table" then
        for i = 1, table.getn(historyProfile.summaries) do
            summary = historyProfile.summaries[i]
            if type(summary) == "table" and summary.combatType ~= "PVP" then
                local primary = summary.primaryEnemy
                if primary and (summary.bossSkull == true or bossNames[primary]) then
                    if summary.isBoss ~= true or summary.bossName ~= primary or summary.priority ~= 4 then
                        summary.isBoss = true
                        summary.bossName = primary
                        summary.bossSkull = true
                        summary.priority = 4
                        repaired = repaired + 1
                    end
                elseif primary and (summary.isBoss == true or summary.priority == 4) then
                    summary.isBoss = false
                    summary.bossName = nil
                    summary.bossSkull = nil
                    summary.priority = (tonumber(summary.raw) or 0) >= 50000 and 3 or 2
                    repaired = repaired + 1
                end
            end
        end
    end

    if repaired > 0 and owner.RefreshStorageManifestsForUI then owner:RefreshStorageManifestsForUI() end
    return repaired
end

function MT:RepairBossFightClassification()
    return BP_RepairAllBossClassification(self)
end

local BP_PreviousSyncPersistentData = MT.SyncPersistentData
function MT:SyncPersistentData()
    -- Snapshot the runtime owner before any older wrapper can rebind self.profile.
    local history = self.bossHistory
    local index = self.bossProfileIndex
    BP_PreviousSyncPersistentData(self)
    local p = BP_Profile(self)
    if p then
        if type(history) == "table" then
            p.bossHistory = history
            self.bossHistory = history
        elseif type(p.bossHistory) == "table" then
            self.bossHistory = p.bossHistory
        else
            p.bossHistory = {}
            self.bossHistory = p.bossHistory
        end
        local count = table.getn(self.bossHistory or {})
        index = tonumber(index) or tonumber(p.bossProfileIndex) or 1
        if index < 1 then index = 1 end
        if count > 0 and index > count then index = count end
        p.bossProfileIndex = index
        self.bossProfileIndex = index
        p.bossPersistenceVersion = 2
    end
end

local BP_PreviousRestorePersistentData = MT.RestorePersistentData
function MT:RestorePersistentData()
    -- BOSSPROFILE1: seed the persisted Boss state BEFORE entering the historical
    -- restore chain. Several older Restore wrappers legitimately call Sync as
    -- part of one-time repairs. Without this seed, those nested Sync calls see
    -- self.bossHistory == nil and can overwrite a valid saved history with {}
    -- before the old RC3b restore layer gets a chance to reattach it.
    local stored = BP_PeekStoredProfile(self)
    local savedHistory = stored and type(stored.bossHistory) == "table" and stored.bossHistory or nil
    local savedIndex = stored and tonumber(stored.bossProfileIndex) or nil
    if savedHistory then
        self.bossHistory = savedHistory
        self.bossProfileIndex = savedIndex or 1
    end

    BP_PreviousRestorePersistentData(self)
    local p = BP_Profile(self)
    if p then
        -- Prefer the pre-chain snapshot because an older nested Sync may have
        -- rebound p.bossHistory while restore repairs were executing.
        if savedHistory then
            self.bossHistory = savedHistory
        else
            self.bossHistory = type(p.bossHistory) == "table" and p.bossHistory or {}
        end
        local count = table.getn(self.bossHistory)
        self.bossProfileIndex = savedIndex or tonumber(p.bossProfileIndex) or 1
        if self.bossProfileIndex < 1 then self.bossProfileIndex = 1 end
        if count > 0 and self.bossProfileIndex > count then self.bossProfileIndex = count end

        -- Repair/clothe any old profile whose detailed Recent encounter still
        -- exists. This also recovers Boss Profiles already lost to the old bug.
        BP_RecoverBossProfiles(self, false)
        count = table.getn(self.bossHistory)
        if count > 0 and self.bossProfileIndex > count then self.bossProfileIndex = count end

        p.bossHistory = self.bossHistory
        p.bossProfileIndex = self.bossProfileIndex
        p.bossPersistenceVersion = 2
        if BP_RepairAllBossClassification(self) > 0 then p.fights = self.fights end
    end
end

-- Companions depend on MainTank and therefore finish loading after the core's
-- ADDON_LOADED restore. PLAYER_ENTERING_WORLD is the first safe point where
-- legacy Archive/History records can be repaired in-place too.
MainTankBossPriorityRepairFrame = MainTankBossPriorityRepairFrame or CreateFrame("Frame", "MainTankBossPriorityRepairFrame")
MainTankBossPriorityRepairFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
MainTankBossPriorityRepairFrame:SetScript("OnEvent", function()
    if not MainTank then return end
    local changed = 0
    if MainTank.RecoverBossProfilesFromDetailedStorage then
        changed = changed + (MainTank:RecoverBossProfilesFromDetailedStorage(true) or 0)
    end
    if MainTank.RepairBossFightClassification then
        changed = changed + (MainTank:RepairBossFightClassification() or 0)
    end
    if changed > 0 and MainTank.SyncPersistentData then MainTank:SyncPersistentData() end
end)

-- Restoring an old detailed Boss encounter should make it available to the Boss
-- Profile browser immediately if its standalone profile was ever lost. The
-- authoritative Archive restore behavior itself remains unchanged.
local BP_PreviousRestoreArchivedFight = MT.RestoreArchivedFight
if BP_PreviousRestoreArchivedFight then
    function MT:RestoreArchivedFight(index)
        local ok = BP_PreviousRestoreArchivedFight(self, index)
        if ok and self.RecoverBossProfilesFromDetailedStorage then
            local changed = self:RecoverBossProfilesFromDetailedStorage(true) or 0
            if changed > 0 and self.SyncPersistentData then self:SyncPersistentData() end
            if self.bossFrame and self.bossFrame:IsVisible() and self.UpdateBossWindow then self:UpdateBossWindow() end
        end
        return ok
    end
end
