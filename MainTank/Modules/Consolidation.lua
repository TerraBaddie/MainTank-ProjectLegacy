-- MainTank v1.2.14 SVH3 - Three-file bounded persistence + enriched 64-entry History
--
-- Physical SavedVariables layout (three addon folders / three WTF files):
--   MainTank             = newest 8 detailed fights
--   MainTank_Archive     = 8 priority detailed fights
--   MainTank_History     = 64 enriched lightweight summaries
--
-- Archive priority: Boss > Major (50K+ RAW) > Minor > PvP. Within a tier, newer wins.
--
-- This module intentionally changes only storage/archive plumbing. The proven
-- SI2/DC2/Pass-2B Current/Overall restore chain and combat math remain untouched.

if not MainTank then return end

local MT = MainTank
local G = getfenv(0)

MTArchive = MTArchive or {}
MTArchive.VERSION = 8
MTArchive.LIVE_FIGHT_LIMIT = 8
MTArchive.ARCHIVE_FIGHT_LIMIT = 8
MTArchive.HISTORY_SUMMARY_LIMIT = 64
MTArchive.TOTAL_COMBAT_LIMIT = 80
MTArchive.PERSISTED_OVERALL_EVENT_LIMIT = 0

local ARCHIVE_ADDON = "MainTank_Archive"
local ARCHIVE_GLOBAL = "MainTankArchiveDB"
local HISTORY_ADDON = "MainTank_History"
local HISTORY_GLOBAL = "MainTankHistoryDB"

local function C_Print(msg, red)
    if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
        if red then
            DEFAULT_CHAT_FRAME:AddMessage("MainTank: " .. tostring(msg), 1.0, 0.12, 0.12)
        else
            DEFAULT_CHAT_FRAME:AddMessage("MainTank: " .. tostring(msg))
        end
    end
end

local function C_DeepCopy(src, seen)
    if type(src) ~= "table" then return src end
    seen = seen or {}
    if seen[src] then return seen[src] end
    local dst = {}
    seen[src] = dst
    local k, v
    for k, v in pairs(src) do dst[C_DeepCopy(k, seen)] = C_DeepCopy(v, seen) end
    return dst
end

local function C_ProfileKey(owner)
    if owner.profileKey then return owner.profileKey end
    if owner.GetProfileKey then return owner:GetProfileKey() end
    local realm = GetRealmName and GetRealmName() or "Unknown Realm"
    local player = UnitName and UnitName("player") or "Unknown Player"
    return realm .. " - " .. player
end

local function C_Profile(owner)
    if owner.profile then return owner.profile end
    if not MainTankDB then MainTankDB = {} end
    MainTankDB.profiles = MainTankDB.profiles or {}
    local key = C_ProfileKey(owner)
    owner.profileKey = key
    MainTankDB.profiles[key] = MainTankDB.profiles[key] or {}
    owner.profile = MainTankDB.profiles[key]
    return owner.profile
end

local function C_LoadDB(addonName, globalName, quiet)
    local db = G[globalName]
    if db then
        db.version = db.version or MTArchive.VERSION
        db.profiles = db.profiles or {}
        return db
    end

    -- RELEASEPOLISH1: MainTank_Archive/MainTank_History are no longer
    -- LoadOnDemand backends. They are required enabled companions and should
    -- already be loaded before VARIABLES_LOADED. Do not try to force-load a
    -- disabled/missing storage addon behind the user's AddOns configuration.
    if not quiet then
        if MT.WarnRequiredCompanion then
            MT:WarnRequiredCompanion(addonName)
        else
            C_Print(addonName .. " required storage companion is unavailable. Recent MainTank data remains usable.", true)
        end
    end
    return nil, "companion-unavailable"
end

local function C_StoreProfile(db, key, kind)
    if not db then return nil end
    db.profiles = db.profiles or {}
    local p = db.profiles[key]
    if not p then
        p = kind == "archive" and {fights = {}, nextArchiveID = 1} or {summaries = {}}
        db.profiles[key] = p
    end
    if kind == "archive" then
        p.fights = p.fights or {}
        p.nextArchiveID = tonumber(p.nextArchiveID) or 1
    else
        p.summaries = p.summaries or {}
    end
    return p
end

function MT:GetExternalArchiveProfile(quiet)
    local db = C_LoadDB(ARCHIVE_ADDON, ARCHIVE_GLOBAL, quiet)
    if not db then return nil end
    return C_StoreProfile(db, C_ProfileKey(self), "archive")
end

function MT:GetExternalHistoryProfile(quiet)
    local db = C_LoadDB(HISTORY_ADDON, HISTORY_GLOBAL, quiet)
    if not db then return nil end
    return C_StoreProfile(db, C_ProfileKey(self), "history")
end

local function C_Raw(fight)
    if type(fight) ~= "table" then return 0 end
    local data = fight.data or {}
    local raw = tonumber(data.rawIncoming) or tonumber(data.raw)
    if raw then return raw end
    raw = 0
    local i, e
    for i = 1, table.getn(fight.events or {}) do e = fight.events[i]; raw = raw + (tonumber(e and e.raw) or 0) end
    return raw
end

local function C_Taken(fight)
    if type(fight) ~= "table" then return 0 end
    local data = fight.data or {}
    local taken = tonumber(data.damageTaken) or tonumber(data.taken)
    if taken then return taken end
    taken = 0
    local i, e
    for i = 1, table.getn(fight.events or {}) do e = fight.events[i]; taken = taken + (tonumber(e and e.taken) or 0) end
    return taken
end

local function C_IsBoss(owner, fight)
    if type(fight) ~= "table" then return false end
    if fight.combatType == "PVP" or fight.pvp == true then return false end

    local primary = fight.primaryEnemy

    -- BOSSPROFILE1: only the fight-local bossSkull marker self-authenticates a
    -- persisted Boss record. The marker is written only from live UnitLevel -1
    -- evidence and must agree with the fight's own primary enemy. Plain legacy
    -- isBoss/bossName flags still require target-memory/profile confirmation.
    if fight.bossSkull == true and primary and fight.bossName == primary then
        fight.isBoss = true
        return true
    end

    local memory = owner and owner.targetDamageMemory or {}
    if primary and memory[primary] and memory[primary].isBoss then
        fight.isBoss = true
        fight.bossName = primary
        fight.bossSkull = true
        fight.bossIdentityVersion = 1
        return true
    end

    -- Persisted Boss Profiles are authoritative name evidence for legacy fights,
    -- but only for the PRIMARY enemy.  Never promote a fight merely because a
    -- known boss appears somewhere in its event stream.
    local _, profile
    for _, profile in ipairs(owner and owner.bossHistory or {}) do
        if profile and profile.name and primary == profile.name then
            fight.isBoss = true
            fight.bossName = primary
            fight.bossSkull = true
            fight.bossIdentityVersion = 1
            return true
        end
    end

    -- If we have an explicit primary enemy and it is not the stored bossName,
    -- clear a stale Boss stamp so priority can correctly fall back to Major/Minor.
    if primary and fight.isBoss == true then
        fight.isBoss = false
        fight.bossName = nil
        fight.bossSkull = nil
        fight.bossIdentityVersion = nil
        fight.archivePriority = nil
        if fight.archiveKind == "boss" then fight.archiveKind = nil end
    end
    return false
end

local function C_Priority(owner, fight)
    if type(fight) == "table" and (fight.combatType == "PVP" or fight.pvp == true) then return 1 end
    if C_IsBoss(owner, fight) then return 4 end
    if C_Raw(fight) >= 50000 then return 3 end
    return 2
end

local KEEP_KIND = {
    flatDR=true, percentDR=true, physicalDR=true, spellDR=true,
    enemyAP=true, enemyDamage=true, attackSpeed=true,
    armorBuff=true, resistanceBuff=true, auraBoost=true, sanctuaryBoost=true
}

local function C_CopyEffect(effect)
    if type(effect) ~= "table" then return nil end
    local kind = effect.kind
    if not effect.known and not KEEP_KIND[kind] then return nil end
    local out = {}
    local fields = {"name","kind","value","baseValue","rank","maxRank","maxLearnedRank","guardiansFavorRank","label","known","source","school","activationMode","vpRule","rankSource"}
    local i, k, v
    for i = 1, table.getn(fields) do k = fields[i]; v = effect[k]; if v ~= nil and v ~= "" then out[k] = v end end
    return out
end

local function C_CopyEffectList(list)
    local out, i, e = {}, nil, nil
    for i = 1, table.getn(list or {}) do e = C_CopyEffect(list[i]); if e then table.insert(out, e) end end
    return out
end

local function C_MinSnapshot(snapshot)
    if type(snapshot) ~= "table" then return nil end
    return {
        armor = tonumber(snapshot.armor) or 0,
        buffs = C_CopyEffectList(snapshot.buffs), talents = C_CopyEffectList(snapshot.talents),
        equipment = C_CopyEffectList(snapshot.equipment), debuffs = C_CopyEffectList(snapshot.debuffs),
        attackerDebuffsKnown = snapshot.attackerDebuffsKnown and true or false
    }
end

local function C_EffectSig(effect)
    if type(effect) ~= "table" then return "" end
    return tostring(effect.name or "")..":"..tostring(effect.kind or "")..":"..tostring(effect.value or "")..":"..tostring(effect.baseValue or "")..":"..tostring(effect.rank or "")..":"..tostring(effect.guardiansFavorRank or "")
end

local function C_ListSig(list)
    local parts, i = {}, nil
    for i = 1, table.getn(list or {}) do parts[i] = C_EffectSig(list[i]) end
    table.sort(parts)
    return table.concat(parts, ",")
end

local function C_SnapshotSig(snapshot)
    if type(snapshot) ~= "table" then return "" end
    return "A"..tostring(snapshot.armor or 0).."|B:"..C_ListSig(snapshot.buffs).."|T:"..C_ListSig(snapshot.talents).."|I:"..C_ListSig(snapshot.equipment).."|D:"..tostring(snapshot.attackerDebuffsKnown and 1 or 0)..":"..C_ListSig(snapshot.debuffs)
end

local TRANSIENT_FIELDS = {
    "rc6MathVersion","rc6BaseRaw","rc6ArmorRate","drRawAnchor","drSaturated","drEstimated","drPctListed","drPctEffective",
    "sanctuaryRankSource","sanctuaryFlatCap","rawHintSource","rawHintLow","rawHintHigh","rawHintMHLow","rawHintMHHigh","rawHintAverage","rawHintDualWield"
}

local function C_DietEvent(e)
    if type(e) ~= "table" then return end
    local i
    for i = 1, table.getn(TRANSIENT_FIELDS) do e[TRANSIENT_FIELDS[i]] = nil end
end

-- Archive-local SVH2 format: remap every event.context to a fight-local numeric
-- compactContextPool. This avoids re-expanding SVH1 contexts into old long-string
-- contextSnapshots and makes the archive cost comparable to Recent storage.
local function C_CompactFight(owner, fight)
    local out = C_DeepCopy(fight or {})
    if FR1X_GA2_FinalizeArchiveDR then FR1X_GA2_FinalizeArchiveDR(out) end

    local sourceCompact = owner and owner.profile and owner.profile.compactContextPool or {}
    local sourceLegacy = owner and owner.profile and owner.profile.contextSnapshotPool or {}
    local localPool, bySig, nextID = {}, {}, 1
    local isPVP = out.combatType == "PVP" or out.pvp == true
    local i, e, snapshot, minimal, sig, id
    for i = 1, table.getn(out.events or {}) do
        e = out.events[i]
        if type(e) == "table" then
            C_DietEvent(e)
            snapshot = nil
            if not isPVP then
                if type(e.rc6ContextSnapshot) == "table" then snapshot = e.rc6ContextSnapshot end
                if not snapshot and tonumber(e.context) then snapshot = sourceCompact[tonumber(e.context)] end
                if not snapshot and e.contextID then snapshot = sourceLegacy[e.contextID] end
                if type(snapshot) == "table" then
                    minimal = C_MinSnapshot(snapshot)
                    sig = C_SnapshotSig(minimal)
                    id = bySig[sig]
                    if not id then id = nextID; nextID = nextID + 1; bySig[sig] = id; localPool[id] = minimal end
                    e.context = id
                else
                    e.context = nil
                end
            else
                -- Pure PvP totals are authoritative; no RC6 context graph persists.
                e.context = nil
            end
            e.contextID = nil
            e.rc6ContextSnapshot = nil
        end
    end
    out.compactContextPool = localPool
    out.contextSnapshots = nil
    out.archivedAt = type(time) == "function" and time() or 0
    out.archiveFormat = MTArchive.VERSION
    out.archivePriority = C_Priority(owner, out)
    out.archiveKind = out.archivePriority == 4 and "boss" or (out.archivePriority == 3 and "50k" or (out.archivePriority == 1 and "pvp" or "minor"))
    return out
end

local function C_RehydrateFight(fight)
    local out = C_DeepCopy(fight)
    if type(out) ~= "table" then return out end
    local pool = out.compactContextPool or out.contextSnapshots
    local i, e, id
    if type(pool) == "table" then
        for i = 1, table.getn(out.events or {}) do
            e = out.events[i]
            if type(e) == "table" then
                id = tonumber(e.context) or e.contextID
                if not e.rc6ContextSnapshot and id and pool[id] then e.rc6ContextSnapshot = pool[id] end
                if e.rc6ContextSnapshot then e.rc6MathVersion = 11 end
            end
        end
    end
    return out
end

local function C_Summary(owner, fight, reason)
    local raw, taken = C_Raw(fight), C_Taken(fight)
    local stopped = raw - taken; if stopped < 0 then stopped = 0 end
    local d = (fight and fight.data) or {}
    local avoidance = (tonumber(d.missedEstimated) or 0) + (tonumber(d.dodgedEstimated) or 0) + (tonumber(d.parriedEstimated) or 0)
    return {
        -- Identity / retention metadata.
        id=fight and fight.id, label=fight and fight.label or "Unknown", primaryEnemy=fight and fight.primaryEnemy,
        enemyCount=fight and fight.enemyCount or 0, duration=fight and fight.duration or 0,
        isBoss=C_IsBoss(owner, fight) and true or false, bossName=fight and fight.bossName, bossSkull=fight and fight.bossSkull and true or false, priority=C_Priority(owner, fight),
        combatType=fight and fight.combatType or "PVE", eventCount=fight and fight.events and table.getn(fight.events) or 0,
        archivedAt=fight and fight.archivedAt or (type(time)=="function" and time() or 0), summarizedAt=type(time)=="function" and time() or 0,
        reason=reason or "archive-eviction", summaryOnly=true, summaryFormatVersion=2,

        -- Legacy headline fields retained for compatibility.
        raw=raw, taken=taken, stopped=stopped,

        -- Enriched aggregate-only History.  These are copied final totals only;
        -- no events, timelines, context pools, aura graphs, or per-second data.
        damageTaken=tonumber(d.damageTaken) or tonumber(d.taken) or 0,
        armorReduced=tonumber(d.armorReduced) or 0,
        avoidance=avoidance,
        missedEstimated=tonumber(d.missedEstimated) or 0,
        dodgedEstimated=tonumber(d.dodgedEstimated) or 0,
        parriedEstimated=tonumber(d.parriedEstimated) or 0,
        blocked=tonumber(d.blocked) or tonumber(d.totalPartialBlock) or 0,
        fullBlockedEstimated=tonumber(d.fullBlockedEstimated) or 0,
        flatDR=tonumber(d.flatDR) or 0,
        physicalDR=tonumber(d.physicalDR) or 0,
        magicDR=tonumber(d.magicDR) or 0,
        absorbed=tonumber(d.absorbed) or 0,
        resistedPartial=tonumber(d.resistedPartial) or 0,
        resistedFullEstimated=tonumber(d.resistedFullEstimated) or 0,
        physicalRaw=tonumber(d.physicalRaw) or 0,
        physicalTaken=tonumber(d.physicalTaken) or 0,
        magicRaw=tonumber(d.magicRaw) or 0,
        magicTaken=tonumber(d.magicTaken) or 0,
        physicalFlatDR=tonumber(d.physicalFlatDR) or 0,
        magicFlatDR=tonumber(d.magicFlatDR) or 0,
        physicalBlocked=tonumber(d.physicalBlocked) or 0,
        magicBlocked=tonumber(d.magicBlocked) or 0,
        physicalAbsorb=tonumber(d.physicalAbsorb) or 0,
        magicAbsorb=tonumber(d.magicAbsorb) or 0,
        missCount=tonumber(d.missCount) or 0,
        dodgeCount=tonumber(d.dodgeCount) or 0,
        parryCount=tonumber(d.parryCount) or 0,
        blockCount=tonumber(d.blockCount) or 0,
        fullBlockCount=tonumber(d.fullBlockCount) or 0,
        absorbCount=tonumber(d.absorbCount) or 0,
        fullResistCount=tonumber(d.fullResistCount) or 0,
        partialResistCount=tonumber(d.partialResistCount) or 0,
        meleeHitCount=tonumber(d.meleeHitCount) or 0,
        magicHitCount=tonumber(d.magicHitCount) or 0
    }
end

local function C_RebuildArchiveManifest(owner, ap)
    local p = C_Profile(owner)
    p.archiveManifest = {}
    local i, f
    for i = 1, table.getn((ap and ap.fights) or {}) do
        f = ap.fights[i]
        table.insert(p.archiveManifest, {kind=f.archiveKind, archiveID=f.archiveID, fightID=f.id, label=f.label or "Unknown", duration=f.duration or 0,
            archivedAt=f.archivedAt or 0, eventCount=f.events and table.getn(f.events) or 0, isBoss=f.isBoss and true or false, bossName=f.bossName,
            combatType=f.combatType or "PVE", raw=C_Raw(f), taken=C_Taken(f), priority=f.archivePriority or C_Priority(owner, f)})
    end
end

local function C_RebuildHistoryManifest(owner, hp)
    local p = C_Profile(owner)
    p.historyManifest = {}
    local i, s
    for i = 1, table.getn((hp and hp.summaries) or {}) do
        s = hp.summaries[i]
        table.insert(p.historyManifest, {id=s.id, label=s.label, raw=s.raw, taken=s.taken, isBoss=s.isBoss, combatType=s.combatType, summarizedAt=s.summarizedAt})
    end
end

-- FIGHTBROWSER1: lightweight public manifest refresh for the UI.  This reads
-- the two companion stores and rebuilds only MainTankDB's tiny manifests; it
-- never rehydrates Archive fights, changes retention, or touches combat state.
function MT:RefreshStorageManifestsForUI()
    local p = C_Profile(self)
    local adb = C_LoadDB(ARCHIVE_ADDON, ARCHIVE_GLOBAL, true)
    if adb then
        local ap = C_StoreProfile(adb, C_ProfileKey(self), "archive")
        C_RebuildArchiveManifest(self, ap)
    end
    local hdb = C_LoadDB(HISTORY_ADDON, HISTORY_GLOBAL, true)
    if hdb then
        local hp = C_StoreProfile(hdb, C_ProfileKey(self), "history")
        C_RebuildHistoryManifest(self, hp)
    end
    return p.archiveManifest or {}, p.historyManifest or {}
end

local function C_AddHistory(owner, fight, reason)
    if type(fight) ~= "table" then return false end
    local db = C_LoadDB(HISTORY_ADDON, HISTORY_GLOBAL, true)
    if not db then return false end
    local hp = C_StoreProfile(db, C_ProfileKey(owner), "history")
    table.insert(hp.summaries, 1, C_Summary(owner, fight, reason))
    while table.getn(hp.summaries) > MTArchive.HISTORY_SUMMARY_LIMIT do table.remove(hp.summaries) end
    C_RebuildHistoryManifest(owner, hp)
    return true
end

local function C_FindEvictionIndex(owner, fights, incoming)
    if table.getn(fights) < MTArchive.ARCHIVE_FIGHT_LIMIT then return nil, true end
    local incomingPriority = C_Priority(owner, incoming)
    local worstIndex, worstPriority, worstTime = nil, 999, 9999999999
    local i, f, pri, when
    for i = 1, table.getn(fights) do
        f=fights[i]; pri=tonumber(f.archivePriority) or C_Priority(owner,f); when=tonumber(f.archivedAt) or 0
        if pri < worstPriority or (pri == worstPriority and when < worstTime) then worstPriority=pri; worstTime=when; worstIndex=i end
    end
    if incomingPriority >= worstPriority then return worstIndex, true end
    return nil, false
end

function MT:ArchiveFight(fight, silent)
    if type(fight) ~= "table" then return false end
    local db = C_LoadDB(ARCHIVE_ADDON, ARCHIVE_GLOBAL, silent)
    if not db then return false end
    local ap = C_StoreProfile(db, C_ProfileKey(self), "archive")
    local compact = C_CompactFight(self, fight)
    compact.archiveID = ap.nextArchiveID; ap.nextArchiveID = ap.nextArchiveID + 1

    local evictIndex, admit = C_FindEvictionIndex(self, ap.fights, compact)
    if not admit then
        C_AddHistory(self, compact, "archive-priority")
        C_RebuildArchiveManifest(self, ap)
        if not silent then C_Print("Archive kept its higher-priority detailed fights; "..tostring(compact.label or "fight").." was retained as History summary.") end
        return true
    end
    if evictIndex then local displaced=table.remove(ap.fights, evictIndex); if displaced then C_AddHistory(self, displaced, "archive-eviction") end end
    table.insert(ap.fights, 1, compact)
    while table.getn(ap.fights) > MTArchive.ARCHIVE_FIGHT_LIMIT do local displaced=table.remove(ap.fights); if displaced then C_AddHistory(self, displaced, "archive-overflow") end end
    C_RebuildArchiveManifest(self, ap)
    if not silent then
        local tag=compact.archivePriority==4 and "BOSS" or (compact.archivePriority==3 and "MAJOR" or (compact.archivePriority==1 and "PvP" or "MINOR"))
        C_Print("Archived "..tostring(compact.label or "fight").." to MainTank_Archive ["..tag.."].")
    end
    return true
end

function MT:ArchiveExcessLiveFights(silent)
    if type(self.fights) ~= "table" then return 0 end
    local moved=0
    while table.getn(self.fights) > MTArchive.LIVE_FIGHT_LIMIT do
        local idx=table.getn(self.fights); local fight=self.fights[idx]
        if not self:ArchiveFight(fight, true) then break end
        table.remove(self.fights, idx); moved=moved+1
    end
    if moved>0 then if self.SyncPersistentData then self:SyncPersistentData() end; if not silent then C_Print("Moved "..tostring(moved).." older detailed fight(s) out of Recent into MainTank_Archive.") end end
    return moved
end

function MT:GetArchivedFight(index)
    index=tonumber(index)
    if not index then return nil, "archive-index" end
    local p=C_Profile(self); local entry=p.archiveManifest and p.archiveManifest[index]
    if not entry then return nil, "archive-index" end
    local db,reason=C_LoadDB(ARCHIVE_ADDON,ARCHIVE_GLOBAL,false); if not db then return nil,reason end
    local ap=C_StoreProfile(db,C_ProfileKey(self),"archive")
    local i,f
    for i=1,table.getn(ap.fights) do f=ap.fights[i]; if f.archiveID==entry.archiveID then return C_RehydrateFight(f) end end
    return nil,"not-found"
end

function MT:RestoreArchivedFight(index)
    index=tonumber(index)
    local p=C_Profile(self); local entry=index and p.archiveManifest and p.archiveManifest[index]
    if not entry then C_Print("Archived fight could not be restored (archive-index).") return false end
    local db,reason=C_LoadDB(ARCHIVE_ADDON,ARCHIVE_GLOBAL,false); if not db then C_Print("Archived fight could not be restored ("..tostring(reason)..").") return false end
    local ap=C_StoreProfile(db,C_ProfileKey(self),"archive")
    local i,stored
    for i=1,table.getn(ap.fights) do if ap.fights[i].archiveID==entry.archiveID then stored=table.remove(ap.fights,i); break end end
    if not stored then C_Print("Archived fight could not be restored (not-found).") return false end
    local fight=C_RehydrateFight(stored); fight.compactContextPool=nil; fight.contextSnapshots=nil
    table.insert(self.fights,1,fight)
    self:ArchiveExcessLiveFights(true)
    C_RebuildArchiveManifest(self,ap)
    self.currentView=1
    if self.SyncPersistentData then self:SyncPersistentData() end
    if self.UpdateDisplay then self:UpdateDisplay() end
    C_Print("Restored archived fight: "..tostring(fight.label or "Unknown")..".")
    return true
end

function MT:PrintArchiveStatus()
    local adb=C_LoadDB(ARCHIVE_ADDON,ARCHIVE_GLOBAL,true); local hdb=C_LoadDB(HISTORY_ADDON,HISTORY_GLOBAL,true)
    local ap=adb and C_StoreProfile(adb,C_ProfileKey(self),"archive") or {fights={}}
    local hp=hdb and C_StoreProfile(hdb,C_ProfileKey(self),"history") or {summaries={}}
    C_RebuildArchiveManifest(self,ap); C_RebuildHistoryManifest(self,hp)
    local recent,archive,history=table.getn(self.fights or {}),table.getn(ap.fights or {}),table.getn(hp.summaries or {})
    C_Print("Storage - Recent "..recent.."/8 | Archive "..archive.."/8 | History "..history.."/64 | total "..tostring(recent+archive+history).."/80.")
    local i,f,tag
    for i=1,archive do f=ap.fights[i]; local pri=tonumber(f.archivePriority) or C_Priority(self,f); tag=pri==4 and "BOSS" or (pri==3 and "MAJOR" or (pri==1 and "PvP" or "MINOR")); C_Print("  A"..i..". ["..tag.."] "..tostring(f.label or "Unknown").." | RAW "..tostring(math.floor(C_Raw(f)+0.5)).." | events "..tostring(f.events and table.getn(f.events) or 0)) end
    for i=1,history do f=hp.summaries[i]; tag=(f.combatType=="PVP") and "PvP" or (f.isBoss and "BOSS" or ((tonumber(f.raw) or 0)>=50000 and "MAJOR" or "MINOR")); C_Print("  H"..i..". ["..tag.."] "..tostring(f.label or "Unknown").." | RAW "..tostring(math.floor((tonumber(f.raw) or 0)+0.5)).." | summary") end
    if archive>0 then C_Print("Use /mt archive restore N to move Archive fight N back into Recent.") end
end

function MT:ClearArchivesConfirmed()
    local key=C_ProfileKey(self)
    local adb=C_LoadDB(ARCHIVE_ADDON,ARCHIVE_GLOBAL,true); if adb and adb.profiles then adb.profiles[key]=nil end
    local hdb=C_LoadDB(HISTORY_ADDON,HISTORY_GLOBAL,true); if hdb and hdb.profiles then hdb.profiles[key]=nil end
    local p=C_Profile(self); p.archiveManifest={}; p.historyManifest={}; p.nextArchiveID=nil; p.archiveFights=nil; p.historySummaries=nil
    if self.SyncPersistentData then self:SyncPersistentData() end
    C_Print("MainTank Archive and History cleared for this character.")
end

-- Migrate the v1.2.12 single-file Archive/History tables exactly once. Current
-- companions are loaded normally. If either required companion is unavailable,
-- preserve the corresponding legacy payload in MainTankDB and retry next login
-- rather than deleting data that could not be transferred.
local function C_MigrateSingleFolder(owner)
    local p=C_Profile(owner)
    if p.threeFileStorageVersion==1 then return 0,0,true end
    local movedA,movedH=0,0
    local archivePending=type(p.archiveFights)=="table" and table.getn(p.archiveFights)>0
    local historyPending=type(p.historySummaries)=="table" and table.getn(p.historySummaries)>0
    local archiveComplete=not archivePending
    local historyComplete=not historyPending

    if archivePending then
        local adb=C_LoadDB(ARCHIVE_ADDON,ARCHIVE_GLOBAL,false)
        if adb then
            local ap=C_StoreProfile(adb,C_ProfileKey(owner),"archive")
            local i,f
            for i=table.getn(p.archiveFights),1,-1 do
                f=p.archiveFights[i]
                if type(f)=="table" then
                    -- Old consolidated archive may contain expanded contextSnapshots;
                    -- rehydrate then re-compact into the SVH2 archive-local format.
                    local hydrated=C_RehydrateFight(f)
                    local compact=C_CompactFight(owner,hydrated)
                    compact.archiveID=tonumber(f.archiveID) or ap.nextArchiveID
                    if compact.archiveID>=ap.nextArchiveID then ap.nextArchiveID=compact.archiveID+1 end
                    table.insert(ap.fights,1,compact); movedA=movedA+1
                end
            end
            while table.getn(ap.fights)>MTArchive.ARCHIVE_FIGHT_LIMIT do local displaced=table.remove(ap.fights); if displaced then C_AddHistory(owner,displaced,"migration-overflow") end end
            C_RebuildArchiveManifest(owner,ap)
            archiveComplete=true
        end
    end

    if historyPending then
        local hdb=C_LoadDB(HISTORY_ADDON,HISTORY_GLOBAL,false)
        if hdb then
            local hp=C_StoreProfile(hdb,C_ProfileKey(owner),"history")
            local i
            for i=table.getn(p.historySummaries),1,-1 do table.insert(hp.summaries,1,C_DeepCopy(p.historySummaries[i])); movedH=movedH+1 end
            while table.getn(hp.summaries)>MTArchive.HISTORY_SUMMARY_LIMIT do table.remove(hp.summaries) end
            C_RebuildHistoryManifest(owner,hp)
            historyComplete=true
        end
    end

    if archiveComplete then p.archiveFights=nil end
    if historyComplete then p.historySummaries=nil end
    if archiveComplete and historyComplete then
        p.singleFolderStorageVersion=nil
        p.threeFileStorageVersion=1
        return movedA,movedH,true
    end

    -- Leave the migration marker unfinished so the retained payload retries.
    p.threeFileStorageVersion=nil
    return movedA,movedH,false
end

local C_PreviousRestorePersistentData=MT.RestorePersistentData
function MT:RestorePersistentData()
    C_PreviousRestorePersistentData(self)
    local p=C_Profile(self)
    local movedA,movedH,migrationComplete=C_MigrateSingleFolder(self)
    p.archiveManifest=p.archiveManifest or {}; p.historyManifest=p.historyManifest or {}
    if migrationComplete then
        p.threeFileStorageVersion=1
        -- Only remove legacy payloads after their external transfer succeeded.
        p.archiveFights=nil; p.historySummaries=nil
    end
    if movedA>0 or movedH>0 then C_Print("Migrated single-file storage: "..tostring(movedA).." Archive fight(s), "..tostring(movedH).." History summary(s) moved to separate SavedVariables files.") end
end

-- Preserve only lightweight manifests in the core profile. Archive/History data
-- themselves are owned by their companion SavedVariables files.
local C_PreviousSyncPersistentData=MT.SyncPersistentData
function MT:SyncPersistentData()
    local p=C_Profile(self)
    local archiveManifest=p.archiveManifest or {}; local historyManifest=p.historyManifest or {}
    local migrationPending=p.threeFileStorageVersion~=1
    local legacyArchiveFights=migrationPending and p.archiveFights or nil
    local legacyHistorySummaries=migrationPending and p.historySummaries or nil
    local bossHistory=self.bossHistory -- also carried here so storage sync cannot drop it
    local bossProfileIndex=self.bossProfileIndex
    C_PreviousSyncPersistentData(self)
    p=C_Profile(self)
    p.archiveManifest=archiveManifest; p.historyManifest=historyManifest
    if migrationPending then
        -- RELEASEPOLISH1: a missing companion must never turn an incomplete
        -- storage migration into silent data loss on the next Sync/Logout.
        p.archiveFights=legacyArchiveFights
        p.historySummaries=legacyHistorySummaries
        p.threeFileStorageVersion=nil
    else
        p.archiveFights=nil; p.historySummaries=nil; p.threeFileStorageVersion=1
    end
    p.nextArchiveID=nil
    if bossHistory then p.bossHistory=bossHistory end
    if bossProfileIndex then p.bossProfileIndex=bossProfileIndex end
end

-- Reset remains nuclear for combat data, including both physical companion DBs.
do
    local C_PreviousResetSession=MT.ResetSession
    function MT:ResetSession()
        C_PreviousResetSession(self)
        local key=C_ProfileKey(self)
        local adb=C_LoadDB(ARCHIVE_ADDON,ARCHIVE_GLOBAL,true); if adb and adb.profiles then adb.profiles[key]=nil end
        local hdb=C_LoadDB(HISTORY_ADDON,HISTORY_GLOBAL,true); if hdb and hdb.profiles then hdb.profiles[key]=nil end
        local p=C_Profile(self); p.archiveManifest={}; p.historyManifest={}; p.archiveFights=nil; p.historySummaries=nil; p.threeFileStorageVersion=1
        if self.SyncPersistentData then self:SyncPersistentData() end
    end
end

-- Storage/status commands. Legacy archive-context repair no longer applies to
-- the new archive-local compactContextPool format.
do
    local C_PreviousHandleSlash=MT.HandleSlash
    function MT:HandleSlash(msg)
        local text=string.lower(tostring(msg or "")); text=string.gsub(text,"^%s+",""); text=string.gsub(text,"%s+$","")
        if text=="archive contexts" or text=="archivecontext" then
            C_Print("Archive contexts now use the SVH2 fight-local compact format; no separate context repair is required.")
            return
        elseif text=="dbhealth" or text=="db" then
            local p=C_Profile(self); local pool=p.compactContextPool or {}; local poolCount=0; local k
            for k in pairs(pool) do poolCount=poolCount+1 end
            local ac=p.archiveManifest and table.getn(p.archiveManifest) or 0; local hc=p.historyManifest and table.getn(p.historyManifest) or 0
            C_Print("DB health - current events "..tostring(table.getn(self.events or {})).." | overall runtime events "..tostring(table.getn(self.overallEvents or {})).." | Recent "..tostring(table.getn(self.fights or {})).."/8 | Archive "..ac.."/8 | History "..hc.."/64 | compact context pool "..tostring(poolCount)..".")
            C_Print("Physical files: MainTank=Recent, MainTank_Archive=detailed Archive, MainTank_History=summary History.")
            return
        end
        return C_PreviousHandleSlash(self,msg)
    end
end

-- Keep legacy pre-consolidation importer available, but import directly into the
-- new external Archive. It is intentionally run only after the full Initialize
-- chain so the frozen Current/Overall restore order is not disturbed.
function MT:ImportLegacyArchiveFolders()
    local p=C_Profile(self)
    if p.legacyArchiveImportVersion==2 then return 0 end
    local imported=0
    local names={{addon="MainTank_BossArchiveData",global="MainTankBossArchiveDataDB"},{addon="MainTank_GeneralArchiveData",global="MainTankGeneralArchiveDB"}}
    local n,spec,db,oldp,i,f
    for n=1,table.getn(names) do
        spec=names[n]; db=G[spec.global]
        if not db and LoadAddOn then LoadAddOn(spec.addon); db=G[spec.global] end
        oldp=db and db.profiles and db.profiles[self.profileKey]
        if oldp and type(oldp.fights)=="table" then
            for i=table.getn(oldp.fights),1,-1 do f=oldp.fights[i]; if type(f)=="table" then self:ArchiveFight(C_RehydrateFight(f),true); imported=imported+1 end end
        end
    end
    p.legacyArchiveImportVersion=2
    return imported
end

do
    local C_PreviousInitialize=MT.Initialize
    function MT:Initialize()
        C_PreviousInitialize(self)
        if self.profile then
            local imported=self:ImportLegacyArchiveFolders()
            if imported>0 then C_Print("Imported "..tostring(imported).." legacy archive fight(s) into MainTank_Archive.") end
        end
    end
end
