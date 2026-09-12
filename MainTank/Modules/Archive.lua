-- MainTank legacy FR1X archive/restore compatibility layer
--
-- IMPORTANT: the GeneralArchiveData/BossArchiveData names below describe the
-- retired pre-v1.2 storage architecture. They are retained for migration and
-- for the proven SI2/DC2 restore-wrapper chain; they are NOT the current
-- MainTank_Archive/MainTank_History package design. Current storage ownership
-- lives in Modules/Consolidation.lua, and the two current companions load
-- normally with `## Dependencies: MainTank` rather than LoadOnDemand.

if not MainTank then return end

MTArchive = MTArchive or {}
MTArchive.VERSION = 5
MTArchive.LIVE_FIGHT_LIMIT = 8
MTArchive.GENERAL_FIGHT_LIMIT = 8
MTArchive.BOSS_FIGHT_LIMIT = 8
MTArchive.PERSISTED_OVERALL_EVENT_LIMIT = 0 -- FR1X: rebuilt at runtime, never persisted

local MT = MainTank
local _G = getfenv(0)

local function FR1K_Print(msg)
    if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
        DEFAULT_CHAT_FRAME:AddMessage("MainTank: " .. tostring(msg))
    end
end

local function FR1P_RedWarning(msg)
    if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
        DEFAULT_CHAT_FRAME:AddMessage("MainTank: " .. tostring(msg), 1.0, 0.12, 0.12)
    end
end

local function FR1XHF_ArchiveLimit(kind)
    if kind == "boss" then return MTArchive.BOSS_FIGHT_LIMIT end
    return MTArchive.GENERAL_FIGHT_LIMIT
end

local function FR1XHF_AddonName(kind)
    if kind == "boss" then return "MainTank_BossArchiveData" end
    return "MainTank_GeneralArchiveData"
end

local function FR1XHF_GlobalName(kind)
    if kind == "boss" then return "MainTankBossArchiveDataDB" end
    return "MainTankGeneralArchiveDB"
end

local function FR1XHF_TotalDetailedCapacity()
    return MTArchive.LIVE_FIGHT_LIMIT + MTArchive.GENERAL_FIGHT_LIMIT + MTArchive.BOSS_FIGHT_LIMIT
end

local function FR1K_DeepCopy(src, seen)
    if type(src) ~= "table" then return src end
    seen = seen or {}
    if seen[src] then return seen[src] end
    local dst = {}
    seen[src] = dst
    local k, v
    for k, v in pairs(src) do
        dst[FR1K_DeepCopy(k, seen)] = FR1K_DeepCopy(v, seen)
    end
    return dst
end

local function FR1K_ProfileKey(owner)
    if owner.profileKey then return owner.profileKey end
    if owner.GetProfileKey then return owner:GetProfileKey() end
    local realm = GetRealmName and GetRealmName() or "Unknown Realm"
    local player = UnitName and UnitName("player") or "Unknown Player"
    return realm .. " - " .. player
end

local function FR1XHF_LoadArchive(kind, quiet)
    local globalName = FR1XHF_GlobalName(kind)
    local db = _G[globalName]
    if db then
        db.version = db.version or MTArchive.VERSION
        db.profiles = db.profiles or {}
        return db
    end
    if not LoadAddOn then return nil, "LoadAddOn unavailable" end

    local ok, reason = LoadAddOn(FR1XHF_AddonName(kind))
    db = _G[globalName]
    if not db then
        if not quiet then
            FR1K_Print(FR1XHF_AddonName(kind).." could not be loaded ("..tostring(reason or ok or "unknown").."). Core MainTank remains usable.")
        end
        return nil, reason or "load-failed"
    end
    db.version = db.version or MTArchive.VERSION
    db.profiles = db.profiles or {}
    return db
end

local function FR1K_GetArchiveProfile(db, profileKey)
    db.profiles = db.profiles or {}
    local p = db.profiles[profileKey]
    if not p then
        p = { fights = {}, nextArchiveID = 1 }
        db.profiles[profileKey] = p
    end
    p.fights = p.fights or {}
    p.nextArchiveID = p.nextArchiveID or 1
    return p
end

-- Legacy BossData is deliberately skull-level only. MainTank's target memory
-- marks a mob as isBoss only when UnitLevel("target") == -1. RELEASEPOLISH1
-- removed the last active non-skull test-boss override from Boss Profiles.
local function FR1XHF_IsBossFight(owner, fight)
    if type(fight) ~= "table" then return false end
    if fight.combatType == "PVP" or fight.pvp == true then return false end

    local primary = fight.primaryEnemy
    if fight.bossSkull == true and primary and fight.bossName == primary then fight.isBoss = true; return true end

    local memory = owner and owner.targetDamageMemory or {}
    if primary and memory[primary] and memory[primary].isBoss then
        fight.isBoss = true
        fight.bossName = primary
        fight.bossSkull = true
        fight.bossIdentityVersion = 1
        return true
    end

    -- BOSSGUARD1: persisted Boss Profiles may repair an older fight only when
    -- the known skull boss is that fight's PRIMARY enemy.  Event-stream presence
    -- alone is intentionally insufficient because a boss can be targeted or
    -- briefly touch the player during an adjacent trash pull.
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

-- GA1-SAFE: General Archive context handoff.
-- IMPORTANT: use the persisted Pass 2B pool (contextSnapshotPool), not a
-- runtime-only/nonexistent compactContextPool. Keep this entirely in the
-- rollover path; nothing here runs during startup just because the addon loads.
local function FR1X_GA_CopyContexts(owner, fight, pool)
    if type(fight) ~= "table" or type(fight.events) ~= "table" then return 0 end

    -- Pass 2B has two context representations in historical databases:
    --   event.context   -> profile.compactContextPool[numericID]
    --   event.contextID -> profile.contextSnapshotPool[stringID]
    -- General Archive must preserve whichever representation the fight uses.
    local compactPool = owner and owner.profile and owner.profile.compactContextPool
    local snapshotPool = owner and owner.profile and owner.profile.contextSnapshotPool
    local copied, i, e, id, source = 0, 1, nil, nil, nil
    for i = 1, table.getn(fight.events) do
        e = fight.events[i]
        if type(e) == "table" then
            id = e.context
            source = nil
            if id and type(compactPool) == "table" then source = compactPool[id] end

            if not source then
                id = e.contextID
                if id and type(snapshotPool) == "table" then source = snapshotPool[id] end
            end

            if id and not pool[id] and type(source) == "table" then
                pool[id] = FR1K_DeepCopy(source)
                copied = copied + 1
            end
        end
    end
    return copied
end

-- GA2: finalized DR persistence at the live -> archive boundary.
--
-- Archive rollover can run before the later Pass-2B EndCombat wrappers refresh
-- historical DR presentation fields.  The authoritative raw/taken/armor/block/
-- resist/absorb values are already final at this point, and the fight-local
-- context pool has just been copied by GA1-SAFE.  Recover only the DR remainder
-- that is already implied by those finalized values and the saved mitigation
-- context.  This runs ONLY while a newly-finalized fight is being archived; it
-- never backfills old archive records on load/open.
function FR1X_GA2_FinalizeArchiveDR(fight)
    if type(fight) ~= "table" or type(fight.events) ~= "table" then return 0 end

    local pool = fight.contextSnapshots or {}
    local repaired = 0
    local i, e, id, context, raw, taken, armor, block, resist, absorb
    local residual, school, model, flatCap, effectivePct, maxFlat, flatUsed, pctUsed
    local flat, physical, magic, physicalFlat, magicFlat = 0, 0, 0, 0, 0

    for i = 1, table.getn(fight.events) do
        e = fight.events[i]
        if type(e) == "table" then
            -- Reattach the fight-local context only in this compact copy.
            context = e.rc6ContextSnapshot
            if type(context) ~= "table" then
                id = e.contextID or e.context
                if id and type(pool[id]) == "table" then context = pool[id] end
            end

            -- Preserve already-final attribution.  Otherwise recover only the
            -- residual that the finalized event math already proves existed.
            if e.kind == "DAMAGE" and not e.environmental and
               ((tonumber(e.flatDR) or 0) + (tonumber(e.physicalDR) or 0) +
                (tonumber(e.magicDR) or 0)) <= 0.0001 then
                raw = tonumber(e.raw) or 0
                taken = tonumber(e.taken) or 0
                armor = tonumber(e.armor) or 0
                block = tonumber(e.block) or 0
                resist = tonumber(e.resist) or 0
                absorb = tonumber(e.absorb) or 0
                residual = raw - taken - armor - block - resist - absorb

                if raw > 0 and residual > 0.0001 and type(context) == "table" and RC6B_GetDRModel then
                    school = e.school or "Physical"
                    model = RC6B_GetDRModel(context, school)
                    if type(model) == "table" then
                        flatCap = tonumber(model.flatCap) or 0
                        effectivePct = tonumber(model.effectivePct) or 0
                        if flatCap > 0 or effectivePct > 0 then
                            maxFlat = raw - 1
                            if maxFlat < 0 then maxFlat = 0 end
                            flatUsed = flatCap
                            if flatUsed > maxFlat then flatUsed = maxFlat end
                            if flatUsed > residual then flatUsed = residual end
                            if flatUsed < 0 then flatUsed = 0 end

                            pctUsed = residual - flatUsed
                            if pctUsed < 0 then pctUsed = 0 end
                            if effectivePct <= 0 then pctUsed = 0 end

                            e.flatDR = flatUsed
                            if school == "Physical" then
                                e.physicalDR = pctUsed
                                e.magicDR = 0
                            else
                                e.magicDR = pctUsed
                                e.physicalDR = 0
                            end
                            if (flatUsed + pctUsed) > 0.0001 then repaired = repaired + 1 end
                        end
                    end
                end
            end

            -- Archive records persist the attribution itself, not the transient
            -- RC6 generation marker.  Rehydrate marks archived events final in
            -- RAM so display-time estimators cannot erase these saved values.
            e.rc6MathVersion = nil

            flatUsed = tonumber(e.flatDR) or 0
            flat = flat + flatUsed
            physical = physical + (tonumber(e.physicalDR) or 0)
            magic = magic + (tonumber(e.magicDR) or 0)
            if (e.school or "Physical") == "Physical" then
                physicalFlat = physicalFlat + flatUsed
            else
                magicFlat = magicFlat + flatUsed
            end
        end
    end

    fight.data = fight.data or {}
    fight.data.flatDR = flat
    fight.data.physicalDR = physical
    fight.data.magicDR = magic
    fight.data.physicalFlatDR = physicalFlat
    fight.data.magicFlatDR = magicFlat
    fight.archiveDRVersion = 1
    return repaired
end

local function FR1K_CompactFight(owner, fight)
    local out = FR1K_DeepCopy(fight or {})
    local pool = out.contextSnapshots or {}
    local i, e, id

    -- Make numeric compact context references self-contained before the fight
    -- leaves MainTank's 8-fight live window.
    FR1X_GA_CopyContexts(owner, out, pool)
    out.contextSnapshots = pool

    -- GA2: archive the already-implied finalized DR attribution now, before the
    -- fight leaves the live 8-fight window.  Old archives are never synthesized.
    FR1X_GA2_FinalizeArchiveDR(out)

    if type(out.events) == "table" then
        for i = 1, table.getn(out.events) do
            e = out.events[i]
            if type(e) == "table" and type(e.rc6ContextSnapshot) == "table" then
                id = e.contextID or e.rc6ContextSnapshot.id
                if id then
                    if not pool[id] then pool[id] = e.rc6ContextSnapshot end
                    e.rc6ContextSnapshot = nil
                end
            end
        end
    end
    out.contextSnapshots = pool
    out.archivedAt = type(time) == "function" and time() or 0
    out.archiveFormat = MTArchive.VERSION
    return out
end

local function FR1K_RehydrateFight(fight)
    if type(fight) ~= "table" then return fight end
    local pool = fight.contextSnapshots
    if type(pool) ~= "table" or type(fight.events) ~= "table" then return fight end
    local i, e, id
    for i = 1, table.getn(fight.events) do
        e = fight.events[i]
        if type(e) == "table" then
            if not e.rc6ContextSnapshot then
                id = e.contextID or e.context
                if id and pool[id] then e.rc6ContextSnapshot = pool[id] end
            end
            -- Archived attribution is authoritative.  For legacy archives with
            -- no DR fields this intentionally preserves zero/nil; GA2 never
            -- invents historical DR while merely opening an old archived fight.
            e.rc6MathVersion = 11
        end
    end
    return fight
end

local function FR1K_Manifest(owner)
    if not owner.profile then return {} end
    owner.profile.archiveManifest = owner.profile.archiveManifest or {}
    return owner.profile.archiveManifest
end

local function FR1XHF_CountManifest(owner, kind)
    local manifest = FR1K_Manifest(owner)
    local count, i = 0, 1
    for i = 1, table.getn(manifest) do
        if manifest[i] and manifest[i].kind == kind then count = count + 1 end
    end
    return count
end

local function FR1K_AddManifest(owner, kind, archiveID, fight)
    local manifest = FR1K_Manifest(owner)
    table.insert(manifest, 1, {
        kind = kind,
        archiveID = archiveID,
        fightID = fight and fight.id,
        label = fight and fight.label or "Unknown",
        duration = fight and fight.duration or 0,
        archivedAt = type(time) == "function" and time() or 0,
        eventCount = fight and fight.events and table.getn(fight.events) or 0,
        isBoss = kind == "boss" and true or false,
        bossName = fight and fight.bossName,
    })
    while table.getn(manifest) > (MTArchive.GENERAL_FIGHT_LIMIT + MTArchive.BOSS_FIGHT_LIMIT) do
        table.remove(manifest)
    end
end

local function FR1K_RemoveManifestEntry(owner, kind, archiveID)
    local manifest = FR1K_Manifest(owner)
    local i = table.getn(manifest)
    while i >= 1 do
        if manifest[i] and manifest[i].kind == kind and manifest[i].archiveID == archiveID then
            table.remove(manifest, i)
            return
        end
        i = i - 1
    end
end

local function FR1XHF_SelectArchive(owner, kind)
    local db = FR1XHF_LoadArchive(kind, true)
    if not db then return nil, nil end
    local p = FR1K_GetArchiveProfile(db, FR1K_ProfileKey(owner))
    local limit = FR1XHF_ArchiveLimit(kind)

    if table.getn(p.fights) >= limit then
        local old = table.remove(p.fights)
        if old and old.archiveID then FR1K_RemoveManifestEntry(owner, kind, old.archiveID) end
        if kind == "boss" then
            FR1P_RedWarning("BossData reached its "..tostring(limit).." detailed boss-fight limit. The oldest detailed boss fight was discarded before saving the new one.")
        else
            FR1P_RedWarning("GeneralArchiveData reached its "..tostring(limit).." detailed fight limit. The oldest general fight was discarded before saving the new one.")
        end
    end
    return db, p
end

function MT:ArchiveFight(fight, silent)
    if type(fight) ~= "table" then return false end

    -- IMPORTANT: classify first, then choose the destination. A skull-level
    -- boss evicted from MainTank can never fall through into GeneralArchiveData.
    local kind = FR1XHF_IsBossFight(self, fight) and "boss" or "general"
    local db, p = FR1XHF_SelectArchive(self, kind)
    if not db or not p then
        if not silent then FR1K_Print("No readable "..FR1XHF_AddonName(kind).." archive is available; fight kept live.") end
        return false
    end

    local compact = FR1K_CompactFight(self, fight)
    compact.archiveKind = kind
    compact.archiveID = p.nextArchiveID
    p.nextArchiveID = p.nextArchiveID + 1
    table.insert(p.fights, 1, compact)
    FR1K_AddManifest(self, kind, compact.archiveID, fight)

    if not silent then
        if kind == "boss" then
            FR1K_Print("Archived "..tostring(fight.label or "boss fight").." to MainTank_BossArchiveData.")
        else
            FR1K_Print("Archived "..tostring(fight.label or "fight").." to MainTank_GeneralArchiveData.")
        end
    end
    return true
end

function MT:ArchiveExcessLiveFights(silent)
    if type(self.fights) ~= "table" then return 0 end
    local moved = 0
    while table.getn(self.fights) > MTArchive.LIVE_FIGHT_LIMIT do
        local idx = table.getn(self.fights)
        local fight = self.fights[idx]
        if not self:ArchiveFight(fight, true) then break end
        table.remove(self.fights, idx)
        moved = moved + 1
    end
    if moved > 0 then
        self:SyncPersistentData()
        if not silent then FR1K_Print("Moved "..tostring(moved).." older detailed fight(s) out of MainTank's 8-fight live window.") end
    end
    return moved
end

function MT:GetArchivedFight(manifestIndex)
    local manifest = FR1K_Manifest(self)
    local entry = manifest[manifestIndex]
    if not entry then return nil, "manifest-index" end
    local kind = entry.kind or "general"
    local db, reason = FR1XHF_LoadArchive(kind, false)
    if not db then return nil, reason end
    local p = FR1K_GetArchiveProfile(db, FR1K_ProfileKey(self))
    local i, f
    for i = 1, table.getn(p.fights) do
        f = p.fights[i]
        if f.archiveID == entry.archiveID then
            return FR1K_RehydrateFight(FR1K_DeepCopy(f))
        end
    end
    return nil, "not-found"
end

function MT:RestoreArchivedFight(manifestIndex)
    local fight, reason = self:GetArchivedFight(manifestIndex)
    if not fight then
        FR1K_Print("Archived fight could not be restored ("..tostring(reason)..").")
        return false
    end
    fight.contextSnapshots = nil
    table.insert(self.fights, 1, fight)
    self:ArchiveExcessLiveFights(true)
    self.currentView = 1
    self:SyncPersistentData()
    self:UpdateDisplay()
    FR1K_Print("Restored archived fight: "..tostring(fight.label or "Unknown")..".")
    return true
end

function MT:PrintArchiveStatus()
    local manifest = FR1K_Manifest(self)
    local general = FR1XHF_CountManifest(self, "general")
    local boss = FR1XHF_CountManifest(self, "boss")
    FR1K_Print("FR1X-HF1 archive status - MainTank "..tostring(table.getn(self.fights or {})).."/"..tostring(MTArchive.LIVE_FIGHT_LIMIT).." | General "..tostring(general).."/"..tostring(MTArchive.GENERAL_FIGHT_LIMIT).." | Boss "..tostring(boss).."/"..tostring(MTArchive.BOSS_FIGHT_LIMIT).." | detailed capacity "..tostring(FR1XHF_TotalDetailedCapacity())..".")
    local limit = math.min(table.getn(manifest), 16)
    local i, e, tag
    for i = 1, limit do
        e = manifest[i]
        tag = e.kind == "boss" and "BOSS" or "GENERAL"
        FR1K_Print("  "..tostring(i)..". ["..tag.."] "..tostring(e.label or "Unknown").." | events "..tostring(e.eventCount or 0))
    end
    if table.getn(manifest) > 0 then FR1K_Print("Use /mt archive restore N to return one archived fight to the live list.") end
end

function MT:ClearArchivesConfirmed()
    local key = FR1K_ProfileKey(self)
    local kinds = {"general", "boss"}
    local i, db
    for i = 1, table.getn(kinds) do
        db = FR1XHF_LoadArchive(kinds[i], true)
        if db and db.profiles then db.profiles[key] = nil end
    end
    if self.profile then self.profile.archiveManifest = {} end
    self:SyncPersistentData()
    FR1K_Print("All MainTank GeneralArchiveData and BossData fights for this character cleared.")
end

-- Main-file snapshot compaction ------------------------------------------------
-- The same mitigation context can appear in current events, overall events and
-- fight events.  Before WoW serializes SavedVariables, strip those bulky copies
-- and retain one profile-level context pool.  On the next load/reload they are
-- reattached before the existing RC6 migration/restore chain runs.
local function FR1K_CompactEventList(list, pool)
    if type(list) ~= "table" then return end
    local i, e, id
    for i = 1, table.getn(list) do
        e = list[i]
        if type(e) == "table" and type(e.rc6ContextSnapshot) == "table" then
            id = e.contextID or e.rc6ContextSnapshot.id
            if id then
                if not pool[id] then pool[id] = e.rc6ContextSnapshot end
                e.rc6ContextSnapshot = nil
            end
        end
    end
end

local function FR1K_RehydrateEventList(list, pool, compactPool)
    if type(list) ~= "table" then return end
    local i, e, snapshot
    for i = 1, table.getn(list) do
        e = list[i]
        if type(e) == "table" and not e.rc6ContextSnapshot then
            snapshot = nil
            if e.contextID and type(pool) == "table" then snapshot = pool[e.contextID] end
            if not snapshot and tonumber(e.context) and type(compactPool) == "table" then
                snapshot = compactPool[tonumber(e.context)]
            end
            if type(snapshot) == "table" then
                e.rc6ContextSnapshot = snapshot
            end
        end
    end
end

-- SVH1: finalized events already contain authoritative raw/taken/stopped/DR
-- values.  Persisting the full RC6 context identity string on every event and
-- every irrelevant aura inside every snapshot made large PvE pulls grow by
-- roughly a megabyte per fight.  The disk format below keeps only mitigation-
-- relevant context state and indexes those snapshots numerically. Runtime
-- events are unchanged until PLAYER_LOGOUT, and the compact snapshots are
-- reattached before the frozen DC2/Core restore chain runs on the next login.
local FR1K_SVH1_KEEP_KIND = {
    flatDR=true, percentDR=true, physicalDR=true, spellDR=true,
    enemyAP=true, enemyDamage=true, attackSpeed=true,
    armorBuff=true, resistanceBuff=true, auraBoost=true, sanctuaryBoost=true
}

local function FR1K_SVH1_CopyEffect(effect)
    if type(effect) ~= "table" then return nil end
    local kind = effect.kind
    if not effect.known and not FR1K_SVH1_KEEP_KIND[kind] then return nil end
    local out = {}
    local fields = {"name","kind","value","baseValue","rank","maxRank","maxLearnedRank",
                    "guardiansFavorRank","label","known","source","school","activationMode",
                    "vpRule","rankSource"}
    local i, k, v
    for i = 1, table.getn(fields) do
        k = fields[i]; v = effect[k]
        if v ~= nil and v ~= "" then out[k] = v end
    end
    return out
end

local function FR1K_SVH1_CopyEffectList(list)
    local out = {}
    local i, e
    for i = 1, table.getn(list or {}) do
        e = FR1K_SVH1_CopyEffect(list[i])
        if e then table.insert(out, e) end
    end
    return out
end

local function FR1K_SVH1_MinSnapshot(snapshot)
    if type(snapshot) ~= "table" then return nil end
    return {
        armor = tonumber(snapshot.armor) or 0,
        buffs = FR1K_SVH1_CopyEffectList(snapshot.buffs),
        talents = FR1K_SVH1_CopyEffectList(snapshot.talents),
        equipment = FR1K_SVH1_CopyEffectList(snapshot.equipment),
        debuffs = FR1K_SVH1_CopyEffectList(snapshot.debuffs),
        attackerDebuffsKnown = snapshot.attackerDebuffsKnown and true or false
    }
end

local function FR1K_SVH1_EffectSignature(effect)
    if type(effect) ~= "table" then return "" end
    return tostring(effect.name or "")..":"..tostring(effect.kind or "")..":"..
           tostring(effect.value or "")..":"..tostring(effect.baseValue or "")..":"..
           tostring(effect.rank or "")..":"..tostring(effect.guardiansFavorRank or "")
end

local function FR1K_SVH1_ListSignature(list)
    local parts = {}
    local i
    for i = 1, table.getn(list or {}) do parts[i] = FR1K_SVH1_EffectSignature(list[i]) end
    table.sort(parts)
    return table.concat(parts, ",")
end

local function FR1K_SVH1_SnapshotSignature(snapshot)
    if type(snapshot) ~= "table" then return "" end
    return "A"..tostring(snapshot.armor or 0).."|B:"..FR1K_SVH1_ListSignature(snapshot.buffs)..
           "|T:"..FR1K_SVH1_ListSignature(snapshot.talents)..
           "|I:"..FR1K_SVH1_ListSignature(snapshot.equipment)..
           "|D:"..tostring(snapshot.attackerDebuffsKnown and 1 or 0)..":"..FR1K_SVH1_ListSignature(snapshot.debuffs)
end

local FR1K_SVH1_TRANSIENT_FIELDS = {
    "rc6MathVersion","rc6BaseRaw","rc6ArmorRate","drRawAnchor","drSaturated",
    "drEstimated","drPctListed","drPctEffective","sanctuaryRankSource",
    "sanctuaryFlatCap","rawHintSource","rawHintLow","rawHintHigh",
    "rawHintMHLow","rawHintMHHigh","rawHintOHLow","rawHintOHHigh","rawHintAverage","rawHintDualWield",
    "rc6PreOutcomeEstimate","rc6BlockValue","outcomeEstimateSource"
}

local function FR1K_SVH1_DietList(list)
    local i, j, e
    for i = 1, table.getn(list or {}) do
        e = list[i]
        if type(e) == "table" then
            for j = 1, table.getn(FR1K_SVH1_TRANSIENT_FIELDS) do e[FR1K_SVH1_TRANSIENT_FIELDS[j]] = nil end
        end
    end
end

local function FR1K_SVH1_CompactContexts(profile, lists)
    if type(profile) ~= "table" then return end
    local oldPool = profile.contextSnapshotPool or {}
    local compactPool, bySignature = {}, {}
    local nextID = 1
    local li, list, i, e, snapshot, minimal, sig, id
    for li = 1, table.getn(lists or {}) do
        list = lists[li]
        for i = 1, table.getn(list or {}) do
            e = list[i]
            if type(e) == "table" then
                snapshot = e.rc6ContextSnapshot
                if type(snapshot) ~= "table" and e.contextID then snapshot = oldPool[e.contextID] end
                if type(snapshot) == "table" then
                    minimal = FR1K_SVH1_MinSnapshot(snapshot)
                    sig = FR1K_SVH1_SnapshotSignature(minimal)
                    id = bySignature[sig]
                    if not id then
                        id = nextID; nextID = nextID + 1
                        bySignature[sig] = id
                        compactPool[id] = minimal
                    end
                    e.context = id
                end
                -- The numeric context plus compactContextPool is the complete
                -- persisted reference. Long string IDs and RAM snapshots are
                -- intentionally runtime-only from this point onward.
                e.contextID = nil
                e.rc6ContextSnapshot = nil
            end
        end
    end
    profile.compactContextPool = compactPool
    profile.contextSnapshotPool = {}
    profile.mitigationContexts = {}
    profile.svHardeningVersion = 1
end

local function FR1X_CopyEventForOverall(eventData, offset)
    if type(eventData) ~= "table" then return nil end
    local out = {}
    local k, v
    for k, v in pairs(eventData) do out[k] = v end
    out.time = (tonumber(eventData.time) or 0) + (tonumber(offset) or 0)
    return out
end

-- Rebuild the runtime-only OVERALL event stream from the one authoritative
-- event copy stored inside each live fight.  Fights are stored newest-first, so
-- walk them oldest-first to preserve chronological display order.  New FR1X
-- fights carry an exact session-relative offset; older fights fall back to a
-- cumulative duration offset, which affects only the displayed OVERALL event
-- timestamps and never mitigation totals/timeline math.
local function FR1X_RebuildOverallEvents(profile)
    local rebuilt = {}
    local fights = profile and profile.fights or {}
    local fallbackOffset = 0
    local i, j, f, e, offset
    for i = table.getn(fights), 1, -1 do
        f = fights[i]
        if type(f) == "table" then
            offset = tonumber(f.overallOffset)
            if offset == nil then offset = fallbackOffset end
            for j = 1, table.getn(f.events or {}) do
                e = FR1X_CopyEventForOverall(f.events[j], offset)
                if e then table.insert(rebuilt, e) end
            end
            fallbackOffset = math.max(fallbackOffset, offset + (tonumber(f.duration) or 0))
        end
    end

    -- A reload/logoff can happen with a not-yet-finalized current stream. Keep
    -- that stream only when FR1X explicitly marked it as in progress at save.
    if profile and profile.currentEventsInProgress and type(profile.events) == "table" then
        offset = tonumber(profile.currentEventOverallOffset) or fallbackOffset
        for j = 1, table.getn(profile.events) do
            e = FR1X_CopyEventForOverall(profile.events[j], offset)
            if e then table.insert(rebuilt, e) end
        end
    end
    return rebuilt
end

local function FR1K_PrepareProfileForDisk(owner)
    if not owner.profile then return end
    local pool = owner.profile.contextSnapshotPool or {}
    owner.profile.contextSnapshotPool = pool

    -- Compact only the authoritative event streams that can actually reach
    -- disk. Completed combat lives in fight.events. profile.events is retained
    -- only for an unfinished combat crossing a reload/logout boundary.
    local i, f
    for i = 1, table.getn(owner.fights or {}) do
        f = owner.fights[i]
        if f then FR1K_CompactEventList(f.events, pool) end
    end

    if owner.inCombat and table.getn(owner.events or {}) > 0 then
        FR1K_CompactEventList(owner.events, pool)
        owner.profile.events = owner.events
        owner.profile.currentEventsInProgress = true
        owner.profile.currentEventOverallOffset = tonumber(owner.overallCombatElapsed) or 0
    else
        -- Completed current events already exist as fights[1].events. Persisting
        -- profile.events as well was one of the ~800 KB duplicate copies in the
        -- reference DB.
        owner.profile.events = nil
        owner.profile.currentEventsInProgress = nil
        owner.profile.currentEventOverallOffset = nil
    end

    -- SVH1 final disk pass. Re-diet every persisted event because later Pass-2B
    -- display guards intentionally restore rc6MathVersion in RAM after the
    -- one-time EndCombat diet. Then replace long string context IDs/full aura
    -- graphs with a deduplicated numeric compactContextPool.
    local svhLists = {}
    for i = 1, table.getn(owner.fights or {}) do
        f = owner.fights[i]
        if f and type(f.events) == "table" then
            FR1K_SVH1_DietList(f.events)
            table.insert(svhLists, f.events)
        end
    end
    if owner.profile.currentEventsInProgress and type(owner.profile.events) == "table" then
        FR1K_SVH1_DietList(owner.profile.events)
        table.insert(svhLists, owner.profile.events)
    end
    FR1K_SVH1_CompactContexts(owner.profile, svhLists)

    -- OVERALL totals and the OVERALL timeline remain authoritative persisted
    -- aggregates. The fat overallEvents payload duplicated every combat event,
    -- so FR1X intentionally never writes it. It is reconstructed in memory from
    -- live fight events on load, preserving Current/Overall UI functionality
    -- without another SavedVariables copy.
    owner.profile.overallEvents = nil
    owner.profile.overallEventsTrimmed = nil
    owner.profile.archiveFormatVersion = MTArchive.VERSION
end

local function FR1K_RehydrateProfileBeforeRestore(owner)
    if not MainTankDB or not MainTankDB.profiles then return end
    local key = FR1K_ProfileKey(owner)
    local p = MainTankDB.profiles[key]
    if not p then return end
    local pool = p.contextSnapshotPool
    local compactPool = p.compactContextPool

    -- DC2 startup safety: the FR1K pre-restore hook must do ONE job only:
    -- restore compacted context snapshots on the authoritative persisted event
    -- streams.  Do not synthesize Current/Overall runtime aliases here.
    --
    -- The preserved crash specimen proved that doing those runtime rebuilds
    -- before the Core RC6 restore wrappers execute can wedge the 1.12 client at
    -- roughly 50% loading.  Later Pass-2B restore wrappers already rebuild
    -- Current and Overall from fights[] after the Core chain has completed.
    if type(pool) == "table" or type(compactPool) == "table" then
        FR1K_RehydrateEventList(p.events, pool, compactPool)
        local i, f
        for i = 1, table.getn(p.fights or {}) do
            f = p.fights[i]
            if f then FR1K_RehydrateEventList(f.events, pool, compactPool) end
        end
    end
end

-- Restore compacted snapshots before the existing Core chain so RC6 migration
-- sees self-contained events, but defer Current/Overall runtime reconstruction
-- to the later Pass-2B wrappers.  This keeps persistence compact without
-- mutating the profile topology immediately before Core RestorePersistentData.
local FR1K_PreviousRestorePersistentData = MT.RestorePersistentData
function MT:RestorePersistentData()
    FR1K_RehydrateProfileBeforeRestore(self)
    FR1K_PreviousRestorePersistentData(self)
end

-- Pass 2A: completed-fight event diet -----------------------------------------
-- These fields are RC6 development/audit scaffolding. They are useful while an
-- event is being calculated, but the finalized event already contains the
-- user-facing raw/taken/mitigation results. Strip them ONCE from the newly
-- finalized saved-fight copy. Never touch self.events or self.overallEvents here:
-- Current and Overall stay on their full runtime event streams until reload.
local FR1X_P2A_EVENT_FIELDS = {
    "rc6MathVersion",
    "rc6BaseRaw",
    "rc6ArmorRate",
    "drRawAnchor",
    "drSaturated",
    "drEstimated",
    "drPctListed",
    "drPctEffective",
    "sanctuaryRankSource",
    "sanctuaryFlatCap",
    "rawHintSource",
    "rawHintLow",
    "rawHintHigh",
    "rawHintMHLow",
    "rawHintMHHigh",
    "rawHintOHLow",
    "rawHintOHHigh",
    "rawHintAverage",
    "rawHintDualWield",
    "rc6PreOutcomeEstimate",
    "rc6BlockValue",
    "outcomeEstimateSource"
}

local function FR1X_P2A_DietCompletedFight(fight)
    if type(fight) ~= "table" or fight.pass2AEventDiet then return end
    local events = fight.events
    if type(events) ~= "table" then return end
    local i, j, e
    for i = 1, table.getn(events) do
        e = events[i]
        if type(e) == "table" then
            for j = 1, table.getn(FR1X_P2A_EVENT_FIELDS) do
                e[FR1X_P2A_EVENT_FIELDS[j]] = nil
            end
        end
    end
    fight.pass2AEventDiet = true
end

-- Archive rollover after a completed fight. This happens after combat, never
-- in the combat-log hot path and never as a repeating OnUpdate scan. The core
-- EndCombat first creates the independent fight.events copy; only that copy is
-- dieted, then normal archive rollover runs.
local FR1K_PreviousEndCombat = MT.EndCombat
function MT:EndCombat()
    FR1K_PreviousEndCombat(self)
    if self.fights and self.fights[1] then
        FR1X_P2A_DietCompletedFight(self.fights[1])
    end
    self:ArchiveExcessLiveFights(true)
end

-- /mt reset and the red reset button share ResetSession.  The user's reset
-- contract is intentionally nuclear for MainTank combat data: current,
-- overall, saved fights, learned data AND Data Vault archives are cleared. UI
-- preferences remain owned by the core DB and are preserved.
local FR1K_PreviousResetSession = MT.ResetSession
function MT:ResetSession()
    FR1K_PreviousResetSession(self)
    if self.profile then
        self.profile.contextSnapshotPool = {}
        self.profile.overallEventsTrimmed = 0
        self.profile.archiveManifest = {}
    end
    -- v1.2.0 consolidation: retired General/Boss companion addons are no longer
    -- loaded from ResetSession. Modules/Consolidation.lua owns Archive/History.
    self:SyncPersistentData()
end

-- Slash extensions live here rather than adding more branches to the monolith.
local FR1K_PreviousHandleSlash = MT.HandleSlash
function MT:HandleSlash(msg)
    local text = string.lower(msg or "")
    text = string.gsub(text, "^%s+", "")
    text = string.gsub(text, "%s+$", "")

    if text == "archive contexts" or text == "archivecontext" then
        local db = FR1XHF_LoadArchive("general", false)
        local copied, refs, missing = 0, 0, 0
        if db then
            local p = FR1K_GetArchiveProfile(db, FR1K_ProfileKey(self))
            local i, j, f, e, id
            for i = 1, table.getn(p.fights or {}) do
                f = p.fights[i]
                f.contextSnapshots = f.contextSnapshots or {}
                copied = copied + FR1X_GA_CopyContexts(self, f, f.contextSnapshots)
                for j = 1, table.getn(f.events or {}) do
                    e = f.events[j]
                    id = e and (e.contextID or e.context)
                    if id then
                        refs = refs + 1
                        if not f.contextSnapshots[id] then missing = missing + 1 end
                    end
                end
            end
        end
        FR1K_Print("General archive context audit: copied "..tostring(copied).." | refs "..tostring(refs).." | missing "..tostring(missing)..".")
        return
    end

    if text == "archive" or text == "archives" or text == "vault" then
        self:ArchiveExcessLiveFights(false)
        self:PrintArchiveStatus()
        return
    end

    local _, _, restoreIndex = string.find(text, "^archive%s+restore%s+(%d+)$")
    if restoreIndex then
        self:RestoreArchivedFight(tonumber(restoreIndex))
        return
    end

    if text == "archive now" or text == "vault now" then
        self:ArchiveExcessLiveFights(false)
        self:PrintArchiveStatus()
        return
    end

    if text == "cleararchives" or text == "cleararchives confirm" then
        if text ~= "cleararchives confirm" then
            FR1K_Print("This permanently deletes Data Vault history. Use /mt cleararchives confirm")
        else
            self:ClearArchivesConfirmed()
        end
        return
    end

    if text == "dbhealth" or text == "db" then
        local live = table.getn(self.fights or {})
        local cur = table.getn(self.events or {})
        local overall = table.getn(self.overallEvents or {})
        local manifest = self.profile and self.profile.archiveManifest or {}
        local pool = self.profile and self.profile.contextSnapshotPool or {}
        local poolCount = 0
        local k
        for k in pairs(pool or {}) do poolCount = poolCount + 1 end
        FR1K_Print("FR1X-HF2-P2A DB health: current events "..tostring(cur).." | overall events "..tostring(overall).." | live fights "..tostring(live).."/"..tostring(MTArchive.LIVE_FIGHT_LIMIT).." | archived "..tostring(table.getn(manifest or {})).." | context pool "..tostring(poolCount)..".")
        FR1K_Print("FR1X disk policy: completed Current and OVERALL event payload duplicates are not persisted; they are rebuilt from live fight events after reload. Aggregate Overall totals/timeline remain persisted.")
        return
    end

    FR1K_PreviousHandleSlash(self, msg)
end

-- Prepare the small core DB only at the moment WoW is about to serialize it.
-- A separate frame avoids changing the existing core event dispatcher.
FR1K_SaveFrame = FR1K_SaveFrame or CreateFrame("Frame", "MainTankFR1KSaveFrame")
FR1K_SaveFrame:RegisterEvent("PLAYER_LOGOUT")
FR1K_SaveFrame:SetScript("OnEvent", function()
    if MainTank and MainTank.SyncPersistentData then
        -- PVPSAFETY3: a retaliation/proc-only PvP tail can be held briefly as a
        -- synthetic combat so nearby hits finalize together.  PLAYER_LOGOUT
        -- must finalize that bounded tail before FR1K decides whether profile.events
        -- is an unfinished stream; otherwise the clean shutdown itself could
        -- reproduce the orphan-Overall shape PVPSAFETY3 is designed to prevent.
        if MainTank._mtSyntheticPvPCombat and MainTank.EndCombat then
            MainTank:EndCombat()
        end
        MainTank:ArchiveExcessLiveFights(true)
        MainTank:SyncPersistentData()
        FR1K_PrepareProfileForDisk(MainTank)
    end
end)



-- Pass 2A HF2: authoritative Overall totals ----------------------------------
-- The RC6 display layer normally rebuilds totals from event records. That is
-- correct for full live events, but after Pass 2A those historical records are
-- intentionally compact and no longer carry every reconstruction hint. The
-- persisted Overall timeline, however, already contains the exact finalized
-- combat totals that were displayed before logout. Use it to repair/preserve
-- the authoritative aggregate and never let compact historical events rewrite
-- those headline totals after a reload.
local function FR1XHF2_RepairOverallAggregate(owner)
    if not owner then return end
    local data = owner.overallData or {}
    local timeline = owner.overallTimeline or {}
    local raw, taken, armor = 0, 0, 0
    local physicalRaw, magicRaw = 0, 0
    local physicalTaken, magicTaken, absorbed = 0, 0, 0
    local sawBucket = false
    local _, bucket
    for _, bucket in pairs(timeline) do
        if type(bucket) == "table" then
            sawBucket = true
            raw = raw + (tonumber(bucket.raw) or 0)
            taken = taken + (tonumber(bucket.taken) or 0)
            armor = armor + (tonumber(bucket.armor) or 0)
            physicalRaw = physicalRaw + (tonumber(bucket.physicalRaw) or 0)
            magicRaw = magicRaw + (tonumber(bucket.magicRaw) or 0)
            physicalTaken = physicalTaken + (tonumber(bucket.physicalTaken) or 0)
            magicTaken = magicTaken + (tonumber(bucket.magicTaken) or 0)
            absorbed = absorbed + (tonumber(bucket.absorb) or 0)
        end
    end

    if sawBucket then
        data.rawIncoming = raw
        data.damageTaken = taken
        data.armorReduced = armor
        data.physicalRaw = physicalRaw
        data.magicRaw = magicRaw
        data.physicalTaken = physicalTaken
        data.magicTaken = magicTaken
        data.absorbed = absorbed
    end

    -- DR amounts are final values on compact events and therefore remain safe
    -- to sum. Rebuild only these fields; raw/armor/physical totals come from the
    -- lossless Overall timeline above.
    local flatDR, physicalDR, magicDR = 0, 0, 0
    local physicalFlatDR, magicFlatDR = 0, 0
    local physicalAbsorb, magicAbsorb = 0, 0
    local events = owner.overallEvents or {}
    local i, e, school
    for i = 1, table.getn(events) do
        e = events[i]
        if type(e) == "table" then
            flatDR = flatDR + (tonumber(e.flatDR) or 0)
            physicalDR = physicalDR + (tonumber(e.physicalDR) or 0)
            magicDR = magicDR + (tonumber(e.magicDR) or 0)
            school = e.school or "Physical"
            if school == "Physical" then
                physicalFlatDR = physicalFlatDR + (tonumber(e.flatDR) or 0)
                physicalAbsorb = physicalAbsorb + (tonumber(e.absorb) or 0)
            else
                magicFlatDR = magicFlatDR + (tonumber(e.flatDR) or 0)
                magicAbsorb = magicAbsorb + (tonumber(e.absorb) or 0)
            end
        end
    end
    data.flatDR = flatDR
    data.physicalDR = physicalDR
    data.magicDR = magicDR
    data.physicalFlatDR = physicalFlatDR
    data.magicFlatDR = magicFlatDR
    data.physicalAbsorb = physicalAbsorb
    data.magicAbsorb = magicAbsorb

    owner.overallData = data
    if owner.profile then owner.profile.overallData = data end
end

-- Out of combat, Overall aggregate totals are authoritative persisted data.
-- Details/Biggest can still read the rebuilt compact event stream, while the
-- headline totals never get recomputed from lossy historical hints.
local FR1XHF2_PreviousGetDisplayData = MT.GetDisplayData
function MT:GetDisplayData()
    if self.currentView == "OVERALL" and not self.inCombat then
        return self.overallData or (self.profile and self.profile.overallData)
    end
    return FR1XHF2_PreviousGetDisplayData(self)
end

-- Same rule for Overall Timeline: the persisted/concatenated timeline is the
-- exact finalized chart and should not be regenerated from compact events.
local FR1XHF2_PreviousGetDisplayTimeline = MT.GetDisplayTimeline
function MT:GetDisplayTimeline()
    if self.currentView == "OVERALL" and not self.inCombat then
        return self.overallTimeline or {}
    end
    return FR1XHF2_PreviousGetDisplayTimeline(self)
end

-- Repair old HF1 profiles immediately after rehydration. This recovers the
-- exact pre-logout headline totals from the already-persisted Overall timeline
-- (e.g. 603,756 raw in the three-Scarlet test) without hard-coded fight data.
local FR1XHF2_PreviousRestorePersistentData = MT.RestorePersistentData
function MT:RestorePersistentData()
    FR1XHF2_PreviousRestorePersistentData(self)
    FR1XHF2_RepairOverallAggregate(self)
end

-- After every finalized fight, refresh the authoritative aggregate once. This
-- stays completely outside the combat-log hot path.
local FR1XHF2_PreviousEndCombat = MT.EndCombat
function MT:EndCombat()
    FR1XHF2_PreviousEndCombat(self)
    FR1XHF2_RepairOverallAggregate(self)
    if self.profile then self.profile.overallData = self.overallData end
end


-- Pass 2B HF2: restore historical Timeline DR without touching raw totals -----
--
-- Live testing isolated the remaining Pass 2B regression to older completed
-- fights.  Current Timeline still had Flat/Physical/Magic DR, while the first
-- two fights inside Overall had finalized raw/taken/armor/block/resist/absorb
-- values but zeroed DR fields.  Their missing DR can be recovered losslessly:
--
--   residual = raw - taken - armor - block - resist - absorb
--
-- For a landed DAMAGE event, that residual is exactly the already-accounted
-- Flat + percent-DR budget.  We restore Flat DR first (up to the historical
-- context's flat cap), then assign the remaining DR budget to Physical or Magic
-- according to the event school.  Raw/taken/armor/etc. are NEVER recalculated,
-- so authoritative Main/Overall totals cannot move.
--
-- This is a one-time historical repair. New Pass 2A/2B fights already persist
-- their final DR values and are simply left alone.
local FR1X_P2BHF2_DR_VERSION = 1

local function FR1X_P2BHF2_ContextForEvent(profile, eventData)
    if type(eventData) ~= "table" then return nil end
    if type(eventData.rc6ContextSnapshot) == "table" then
        return eventData.rc6ContextSnapshot
    end
    if tonumber(eventData.context) and profile and type(profile.compactContextPool) == "table" then
        return profile.compactContextPool[tonumber(eventData.context)]
    end
    return nil
end

local function FR1X_P2BHF2_RepairEvent(profile, eventData)
    if type(eventData) ~= "table" then return false end
    if eventData.kind ~= "DAMAGE" or eventData.environmental then return false end

    local existingFlat = tonumber(eventData.flatDR) or 0
    local existingPhysical = tonumber(eventData.physicalDR) or 0
    local existingMagic = tonumber(eventData.magicDR) or 0
    if (existingFlat + existingPhysical + existingMagic) > 0.0001 then
        -- Pass 2A intentionally strips rc6MathVersion from finalized saved
        -- events.  RC6t's display-time attribution wrapper interprets that
        -- missing version as "recalculate me" and can zero otherwise-valid
        -- compact historical DR when the dieted event no longer carries every
        -- old RC6 reconstruction hint.  HF4 marks already-final attribution as
        -- the current RC6t generation in RAM so Current Pie/Timeline consume
        -- the preserved values instead of destructively re-running the old
        -- inverse estimator.  This marker is transient: Pass 2A still omits it
        -- from finalized disk records, preserving the storage win.
        eventData.rc6MathVersion = 11
        return false
    end

    local raw = tonumber(eventData.raw) or 0
    local taken = tonumber(eventData.taken) or 0
    local armor = tonumber(eventData.armor) or 0
    local block = tonumber(eventData.block) or 0
    local resist = tonumber(eventData.resist) or 0
    local absorb = tonumber(eventData.absorb) or 0
    if raw <= 0 then return false end

    local residual = raw - taken - armor - block - resist - absorb
    if residual <= 0.0001 then return false end

    local context = FR1X_P2BHF2_ContextForEvent(profile, eventData)
    if type(context) ~= "table" or not RC6B_GetDRModel then return false end

    local school = eventData.school or "Physical"
    local model = RC6B_GetDRModel(context, school)
    if type(model) ~= "table" then return false end

    local flatCap = tonumber(model.flatCap) or 0
    local effectivePct = tonumber(model.effectivePct) or 0
    if flatCap <= 0 and effectivePct <= 0 then return false end

    -- Sanctuary/flat DR is spent first in the Project Legacy ordering. Never let
    -- the repair consume more than the event's already-observed residual or
    -- more than raw-1 (the server's one-damage floor).
    local maxFlatUsable = raw - 1
    if maxFlatUsable < 0 then maxFlatUsable = 0 end
    local flatUsed = flatCap
    if flatUsed > maxFlatUsable then flatUsed = maxFlatUsable end
    if flatUsed > residual then flatUsed = residual end
    if flatUsed < 0 then flatUsed = 0 end

    local pctUsed = residual - flatUsed
    if pctUsed < 0 then pctUsed = 0 end

    -- Only classify the residual remainder as percent DR when the saved context
    -- actually contained percent DR for this school. Otherwise leave it
    -- unclassified instead of inventing attribution for another mechanic.
    if effectivePct <= 0 then pctUsed = 0 end

    eventData.flatDR = flatUsed
    if school == "Physical" then
        eventData.physicalDR = pctUsed
        eventData.magicDR = 0
    else
        eventData.magicDR = pctUsed
        eventData.physicalDR = 0
    end
    -- Same guard for reconstructed historical attribution.  Current's display
    -- helpers call RC6B_EnsureEventAttribution while rendering; without this
    -- generation marker they immediately erase the DR we just recovered.
    eventData.rc6MathVersion = 11
    return (flatUsed + pctUsed) > 0.0001
end

local function FR1X_P2BHF2_RepairEventList(profile, events)
    if type(events) ~= "table" then return 0 end
    local repaired = 0
    local i
    for i = 1, table.getn(events) do
        if FR1X_P2BHF2_RepairEvent(profile, events[i]) then
            repaired = repaired + 1
        end
    end
    return repaired
end

local function FR1X_P2BHF2_RepairHistoricalDR(owner)
    if not owner or not owner.profile then return 0 end
    local repaired = 0
    local i, fight

    -- Repair authoritative completed-fight copies first so the correction is
    -- persistent and archive-safe.
    for i = 1, table.getn(owner.fights or {}) do
        fight = owner.fights[i]
        if fight and fight.events then
            repaired = repaired + FR1X_P2BHF2_RepairEventList(owner.profile, fight.events)
        end
    end

    -- Current may alias fights[1], so this is normally a no-op after the pass.
    repaired = repaired + FR1X_P2BHF2_RepairEventList(owner.profile, owner.events)

    -- Overall is runtime-only and consists of timestamp-shifted copies. Repair
    -- those copies too so Timeline tooltips update immediately this login.
    repaired = repaired + FR1X_P2BHF2_RepairEventList(owner.profile, owner.overallEvents)

    owner.profile.pass2BTimelineDRVersion = FR1X_P2BHF2_DR_VERSION
    return repaired
end

local FR1X_P2BHF2_PreviousRestorePersistentData = MT.RestorePersistentData
function MT:RestorePersistentData()
    FR1X_P2BHF2_PreviousRestorePersistentData(self)
    if self.profile and tonumber(self.profile.pass2BTimelineDRVersion) ~= FR1X_P2BHF2_DR_VERSION then
        FR1X_P2BHF2_RepairHistoricalDR(self)
        -- Persist only repaired fight events. SyncPersistentData deliberately
        -- keeps overallEvents runtime-only, preserving the Pass 1 size win.
        self:SyncPersistentData()
    else
        -- FR2 startup cleanup: the version marker means authoritative fight
        -- events were already repaired persistently. Later Overall runtime
        -- copies inherit those finalized DR fields directly; another full
        -- repair pass here is redundant.
    end
end


-- Pass 2B HF3: make CURRENT a faithful view of the newest completed fight ----
--
-- FR1X intentionally stopped persisting duplicate profile.data/profile.timeline/
-- profile.events payloads for completed combat.  On reload, however, CURRENT
-- still expected those legacy profile-level tables.  That left CURRENT with a
-- zero/empty data+timeline shell, and its title was regenerated from an empty
-- profile.enemyDeathCounts table (three unique Scarlet names => +2) instead of
-- the newest fight's preserved 11-mob death counts (+10).
--
-- The authoritative completed CURRENT dataset is fights[1].  Bind CURRENT's
-- runtime aliases to that fight after restore, just as OVERALL is rebuilt from
-- authoritative fight records.  This adds no duplicate SavedVariables data and
-- runs only during restore, never in the combat-log hot path.
local FR1X_P2BHF3_VERSION = 1

local function FR1X_P2BHF3_BindCurrentToNewestFight(owner)
    if not owner or owner.inCombat then return false end
    local fight = owner.fights and owner.fights[1]
    if type(fight) ~= "table" then return false end

    -- Legacy-only safety. Modern FR2 fights are already covered by the
    -- persistent Pass-2B DR generation marker.
    if owner.profile and FR1X_P2BHF2_RepairEventList and type(fight.events) == "table" and
       tonumber(owner.profile.pass2BTimelineDRVersion) ~= FR1X_P2BHF2_DR_VERSION then
        FR1X_P2BHF2_RepairEventList(owner.profile, fight.events)
    end

    -- CURRENT is a runtime view. Point it at the authoritative newest fight
    -- instead of persisting another copy of these large tables.
    owner.events = fight.events or {}
    owner.data = fight.data or owner.data or {}
    owner.timeline = fight.timeline or {}
    owner.enemyDeathCounts = fight.enemyDeathCounts or {}

    -- Preserve the stored metadata. Do not regenerate an 11-mob fight from
    -- unique source names when exact death counts are already available.
    if fight.label and fight.label ~= "" then
        owner.currentHistoricalLabel = fight.label
    else
        owner.currentHistoricalLabel = nil
    end

    if owner.profile then
        owner.profile.pass2BCurrentRestoreVersion = FR1X_P2BHF3_VERSION
    end
    return true
end

-- CURRENT's label after a reload should come from the authoritative newest
-- fight. During live combat we keep the normal dynamic metadata generator.
local FR1X_P2BHF3_PreviousGetCurrentFightLabel = MT.GetCurrentFightLabel
function MT:GetCurrentFightLabel()
    if not self.inCombat and self.currentView == "CURRENT" and self.fights and self.fights[1] then
        return self.fights[1].label or FR1X_P2BHF3_PreviousGetCurrentFightLabel(self)
    end
    return FR1X_P2BHF3_PreviousGetCurrentFightLabel(self)
end

-- Run after the entire existing restore chain so later RC6 compatibility
-- wrappers cannot replace CURRENT with empty profile-level legacy tables.
local FR1X_P2BHF3_PreviousRestorePersistentData = MT.RestorePersistentData
function MT:RestorePersistentData()
    FR1X_P2BHF3_PreviousRestorePersistentData(self)

    -- FR2 startup cleanup: HF2's persistent generation marker means all
    -- authoritative saved-fight events already contain finalized DR. Only a
    -- legacy/unmarked profile needs another historical repair pass.
    if not self.profile or tonumber(self.profile.pass2BTimelineDRVersion) ~= FR1X_P2BHF2_DR_VERSION then
        local i, fight
        for i = 1, table.getn(self.fights or {}) do
            fight = self.fights[i]
            if fight and fight.events and self.profile and FR1X_P2BHF2_RepairEventList then
                FR1X_P2BHF2_RepairEventList(self.profile, fight.events)
            end
        end
    end

    FR1X_P2BHF3_BindCurrentToNewestFight(self)

    -- Rebuild Overall runtime copies after authoritative fight repair so both
    -- CURRENT and OVERALL consume the same repaired event attribution.
    if self.profile and FR1X_RebuildOverallEvents then
        self.overallEvents = FR1X_RebuildOverallEvents(self.profile)
        self.profile.overallEvents = self.overallEvents
        FR1XHF2_RepairOverallAggregate(self)
        -- Keep the duplicate stream runtime-only on the next disk preparation.
    end
end

-- EndCombat already leaves the live just-finished Current dataset in memory.
-- Update the newest fight's aggregate DR fields once from its final event list
-- so saved-fight selection and Current agree without changing raw/taken math.
local FR1X_P2BHF3_PreviousEndCombat = MT.EndCombat
function MT:EndCombat()
    FR1X_P2BHF3_PreviousEndCombat(self)
    local fight = self.fights and self.fights[1]
    if fight and fight.events and fight.data and self.profile then
        FR1X_P2BHF2_RepairEventList(self.profile, fight.events)
        local flat, physical, magic, physicalFlat, magicFlat = 0, 0, 0, 0, 0
        local i, e, school
        for i = 1, table.getn(fight.events) do
            e = fight.events[i]
            if type(e) == "table" then
                flat = flat + (tonumber(e.flatDR) or 0)
                physical = physical + (tonumber(e.physicalDR) or 0)
                magic = magic + (tonumber(e.magicDR) or 0)
                school = e.school or "Physical"
                if school == "Physical" then
                    physicalFlat = physicalFlat + (tonumber(e.flatDR) or 0)
                else
                    magicFlat = magicFlat + (tonumber(e.flatDR) or 0)
                end
            end
        end
        fight.data.flatDR = flat
        fight.data.physicalDR = physical
        fight.data.magicDR = magic
        fight.data.physicalFlatDR = physicalFlat
        fight.data.magicFlatDR = magicFlat
    end
end


-- Pass 2B HF5: one authoritative reconstructed CURRENT view ------------------
-- HF3 restored CURRENT's identity/metadata, but Pie/Timeline still travelled
-- through RC6's live-event rebuild path while OVERALL used its authoritative
-- restored aggregate representation.  That split is why OVERALL retained
-- Flat/Physical/Magic DR while CURRENT could lose all three after reload.
--
-- HF5 makes completed CURRENT mirror OVERALL's architecture:
--   * newest saved fight is authoritative;
--   * headline/pie data starts from fight.data (never recompute raw/taken);
--   * only DR display fields are summed from the already-repaired compact events;
--   * timeline bars come from fight.timeline;
--   * compact historical events are frozen at the final RC6t generation in RAM
--     so Details/tooltip readers cannot destructively re-run legacy estimation.
-- No duplicate SavedVariables payload is created: these are runtime references/
-- snapshots only and Pass 2A still strips rc6MathVersion at serialization time.
local FR1X_P2BHF5_VERSION = 1

local function FR1X_P2BHF5_CopyShallow(source)
    local out = {}
    local k, v
    if type(source) == "table" then
        for k, v in pairs(source) do out[k] = v end
    end
    return out
end

local function FR1X_P2BHF5_RebuildCurrentHistoricalView(owner)
    if not owner or owner.inCombat then return false end
    local fight = owner.fights and owner.fights[1]
    if type(fight) ~= "table" then return false end

    -- FR2 startup cleanup:
    -- fight.data already contains the finalized DR presentation totals written
    -- at EndCombat. Pie/headline Current can therefore bind directly without a
    -- second O(events) summation on every login.
    owner.currentHistoricalData = FR1X_P2BHF5_CopyShallow(fight.data or {})
    owner.currentHistoricalTimeline = fight.timeline or {}
    owner.currentHistoricalEvents = fight.events or {}
    owner.currentHistoricalEventsFrozen = nil

    owner.events = fight.events or {}
    owner.data = fight.data or owner.data or {}
    owner.timeline = fight.timeline or {}
    owner.enemyDeathCounts = fight.enemyDeathCounts or owner.enemyDeathCounts or {}
    owner.currentHistoricalLabel = fight.label or owner.currentHistoricalLabel

    if owner.profile then owner.profile.pass2BCurrentViewVersion = FR1X_P2BHF5_VERSION end
    return true
end

local function FR1X_P2BHF5_FreezeCurrentHistoricalEvents(owner)
    if not owner or owner.currentHistoricalEventsFrozen then return end
    local events = owner.currentHistoricalEvents or {}
    local i, e
    for i = 1, table.getn(events) do
        e = events[i]
        if type(e) == "table" then
            -- Details/Inspector may invoke old RC6 attribution helpers. Freeze
            -- compact historical events lazily only when event detail is
            -- actually requested, rather than during login.
            e.rc6MathVersion = 11
        end
    end
    owner.currentHistoricalEventsFrozen = true
end

-- Install these wrappers last in Archive.lua so completed CURRENT cannot fall
-- back into the older RC6 live rebuild chain.  Live combat and numbered saved
-- fight views keep their existing behavior.
local FR1X_P2BHF5_PreviousGetDisplayData = MT.GetDisplayData
function MT:GetDisplayData()
    if self.currentView == "CURRENT" and not self.inCombat and self.fights and self.fights[1] then
        FR1X_P2BHF5_RebuildCurrentHistoricalView(self)
        return self.currentHistoricalData or self.fights[1].data
    end
    return FR1X_P2BHF5_PreviousGetDisplayData(self)
end

local FR1X_P2BHF5_PreviousGetDisplayTimeline = MT.GetDisplayTimeline
function MT:GetDisplayTimeline()
    if self.currentView == "CURRENT" and not self.inCombat and self.fights and self.fights[1] then
        if not self.currentHistoricalTimeline then FR1X_P2BHF5_RebuildCurrentHistoricalView(self) end
        return self.currentHistoricalTimeline or self.fights[1].timeline or {}
    end
    return FR1X_P2BHF5_PreviousGetDisplayTimeline(self)
end

local FR1X_P2BHF5_PreviousGetDisplayEvents = MT.GetDisplayEvents
function MT:GetDisplayEvents()
    if self.currentView == "CURRENT" and not self.inCombat and self.fights and self.fights[1] then
        if not self.currentHistoricalEvents then FR1X_P2BHF5_RebuildCurrentHistoricalView(self) end
        FR1X_P2BHF5_FreezeCurrentHistoricalEvents(self)
        return self.currentHistoricalEvents or self.fights[1].events or {}
    end
    return FR1X_P2BHF5_PreviousGetDisplayEvents(self)
end

local FR1X_P2BHF5_PreviousRestorePersistentData = MT.RestorePersistentData
function MT:RestorePersistentData()
    FR1X_P2BHF5_PreviousRestorePersistentData(self)
    self.currentHistoricalData = nil
    self.currentHistoricalTimeline = nil
    self.currentHistoricalEvents = nil
    self.currentHistoricalEventsFrozen = nil
    FR1X_P2BHF5_RebuildCurrentHistoricalView(self)
end

local FR1X_P2BHF5_PreviousEndCombat = MT.EndCombat
function MT:EndCombat()
    FR1X_P2BHF5_PreviousEndCombat(self)
    self.currentHistoricalData = nil
    self.currentHistoricalTimeline = nil
    self.currentHistoricalEvents = nil
    self.currentHistoricalEventsFrozen = nil
    FR1X_P2BHF5_RebuildCurrentHistoricalView(self)
end



-- DC1: interrupted-combat / disconnect protection ----------------------------
--
-- Contract: ONLY finalized fights[] are historical records.  If WoW exits,
-- disconnects or crashes while a combat is live, the unfinished profile-level
-- stream is disposable.  Never migrate, rebuild, archive or merge that partial
-- stream into completed history on the next login.
--
-- This preflight is deliberately wrapped around Initialize (not merely Restore)
-- because the core calls MigrateDatabase BEFORE RestorePersistentData.  Clearing
-- an interrupted event stream after migration would be too late for a damaged or
-- very large partial fight and could stall the loading screen.
local FR1X_DC1_VERSION = 1

local function FR1X_DC1_Profile(owner)
    if not MainTankDB or type(MainTankDB.profiles) ~= "table" then return nil end
    local key = FR1K_ProfileKey(owner)
    return MainTankDB.profiles[key]
end

local function FR1X_DC1_HasPersistedEvents(p)
    return p and type(p.events) == "table" and table.getn(p.events) > 0
end

local function FR1X_DC1_IsInterrupted(p)
    if type(p) ~= "table" then return false end
    if p.sessionDirty == true then return true end
    if p.currentEventsInProgress == true then return true end
    if p.currentEventOverallOffset ~= nil then return true end

    -- Legacy recovery heuristic for builds that predate sessionDirty.  FR1X's
    -- disk policy never persists profile.events for a completed Current fight,
    -- so a non-empty root event stream on a cold load can only be unfinished
    -- combat state left across an abnormal save boundary.
    if FR1X_DC1_HasPersistedEvents(p) then return true end
    return false
end

local function FR1X_DC1_DiscardInterruptedState(owner)
    local p = FR1X_DC1_Profile(owner)
    if not FR1X_DC1_IsInterrupted(p) then return false end

    local abandonedEvents = type(p.events) == "table" and table.getn(p.events) or 0
    local newest = p.fights and p.fights[1]

    -- Throw away ONLY transient current-combat state.  Authoritative Overall
    -- totals/timeline, finalized fights, learned memories and archive manifest
    -- are intentionally untouched.
    p.events = nil
    p.pending = {}
    p.encounterMemory = {}
    p.currentEventsInProgress = nil
    p.currentEventOverallOffset = nil
    p.sessionDirty = false

    -- Restore the profile-level Current shell from the newest finalized fight so
    -- old migration/display code never sees a half-written fight. HF5 later
    -- aliases Current to this same authoritative fights[1] representation.
    if type(newest) == "table" then
        p.data = newest.data or {}
        p.timeline = newest.timeline or {}
        p.enemyDeathCounts = newest.enemyDeathCounts or {}
    else
        p.data = {}
        p.timeline = {}
        p.enemyDeathCounts = {}
    end

    p.dcRecoveryVersion = FR1X_DC1_VERSION
    p.dcRecoveryCount = (tonumber(p.dcRecoveryCount) or 0) + 1
    p.dcRecoveryAbandonedEvents = abandonedEvents
    if type(time) == "function" then p.dcRecoveryAt = time() end

    owner.dcRecoveryPendingNotice = true
    owner.dcRecoveryAbandonedEvents = abandonedEvents
    return true
end

-- Run the recovery BEFORE MigrateDatabase touches a possible partial stream.
local FR1X_DC1_PreviousInitialize = MT.Initialize
function MT:Initialize()
    FR1X_DC1_DiscardInterruptedState(self)
    FR1X_DC1_PreviousInitialize(self)
end

-- Mark the session dirty before the core starts a new combat. StartCombat's
-- normal SyncPersistentData call then carries this tiny marker into the live DB.
local FR1X_DC1_PreviousStartCombat = MT.StartCombat
function MT:StartCombat()
    if self.profile then
        self.profile.sessionDirty = true
        self.profile.sessionDirtyVersion = FR1X_DC1_VERSION
        if type(time) == "function" then self.profile.sessionDirtyAt = time() end
    end
    FR1X_DC1_PreviousStartCombat(self)
end

-- Clear the marker ONLY after the complete existing EndCombat chain returns.
-- If finalization/archive code errors or the client disappears midway through,
-- sessionDirty remains true and the next login safely abandons the partial state.
local FR1X_DC1_PreviousEndCombat = MT.EndCombat
function MT:EndCombat()
    FR1X_DC1_PreviousEndCombat(self)
    if self.profile then
        self.profile.sessionDirty = false
        self.profile.sessionDirtyAt = nil
        self.profile.lastFinalizedFightID = self.fights and self.fights[1] and self.fights[1].id or self.profile.lastFinalizedFightID
    end
    self:SyncPersistentData()
end

-- Normal logout outside combat is explicitly clean.  Do not alter the in-combat
-- marker here: FR1K_PrepareProfileForDisk intentionally records an unfinished
-- stream when the user reloads/logs out while combat is genuinely active.
FR1X_DC1_SaveFrame = FR1X_DC1_SaveFrame or CreateFrame("Frame", "MainTankDC1SaveFrame")
FR1X_DC1_SaveFrame:RegisterEvent("PLAYER_LOGOUT")
FR1X_DC1_SaveFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
FR1X_DC1_SaveFrame:SetScript("OnEvent", function()
    if event == "PLAYER_LOGOUT" then
        if MainTank and MainTank.profile and not MainTank.inCombat then
            MainTank.profile.sessionDirty = false
        end
    elseif event == "PLAYER_ENTERING_WORLD" then
        if MainTank and MainTank.dcRecoveryPendingNotice then
            FR1P_RedWarning("Recovered from an interrupted combat session. Discarded "..tostring(MainTank.dcRecoveryAbandonedEvents or 0).." unfinished event(s); finalized fights and Overall history were preserved.")
            MainTank.dcRecoveryPendingNotice = nil
            MainTank.dcRecoveryAbandonedEvents = nil
        end
    end
end)



-- GA2 archive DR persistence marker
