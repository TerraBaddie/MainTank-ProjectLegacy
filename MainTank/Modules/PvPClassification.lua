-- MainTank v1.2.1 - PvP/PvE encounter classification safety
--
-- Goals:
--   * Keep PvP usable instead of deleting it.
--   * PvP is the lowest archive-retention priority.
--   * Never learn NPC damage ranges / ability schools from confirmed PvP sources.
--   * Preserve player-attributed damage inside PvE encounters (Mind Control,
--     Conflagration-style raid mechanics, etc.). Mixed NPC+player fights remain PvE.
--   * Recognize targeted player-controlled pets/guardians as PvP sources when the
--     1.12 client exposes them through UnitPlayerControlled.

if not MainTank then return end
local MT = MainTank

MT.pvpSourceCache = MT.pvpSourceCache or {}

local function IsHostilePlayerEvent(eventName)
    return eventName == "CHAT_MSG_COMBAT_HOSTILEPLAYER_HITS" or
           eventName == "CHAT_MSG_COMBAT_HOSTILEPLAYER_MISSES" or
           eventName == "CHAT_MSG_SPELL_HOSTILEPLAYER_DAMAGE"
end

function MT:RememberPvPTarget()
    if not UnitExists or not UnitExists("target") then return end
    if UnitIsFriend and UnitIsFriend("player", "target") then return end
    local name = UnitName and UnitName("target")
    if not name or name == "" then return end

    local controlled = false
    if UnitIsPlayer and UnitIsPlayer("target") then controlled = true end
    if not controlled and UnitPlayerControlled then
        controlled = UnitPlayerControlled("target") and true or false
    end
    if controlled then self.pvpSourceCache[name] = true end
end

function MT:IsConfirmedPvPSource(name)
    if self._mtCombatEvent and IsHostilePlayerEvent(self._mtCombatEvent) then
        if name and name ~= "" then self.pvpSourceCache[name] = true end
        return true
    end
    return name and self.pvpSourceCache and self.pvpSourceCache[name] and true or false
end

function MT:ClassifyFightEvents(events)
    local hasPvE, hasPvP = false, false
    local i, e
    for i = 1, table.getn(events or {}) do
        e = events[i]
        if e and e.sourceType == "PVP" then
            hasPvP = true
        elseif e and e.sourceType == "PVE" then
            hasPvE = true
        end
    end
    -- Any positively identified PvE source makes a mixed fight PvE. This is
    -- deliberate for Mind Control / player-delivered boss mechanics.
    if hasPvE then return "PVE" end
    if hasPvP then return "PVP" end
    return "PVE"
end

-- Capture the 1.12 combat-message family before the mature parser runs.
local PVP_OldParseCombatMessage = MT.ParseCombatMessage
function MT:ParseCombatMessage(message)
    self._mtCombatEvent = event
    self:RememberPvPTarget()
    PVP_OldParseCombatMessage(self, message)
    self._mtCombatEvent = nil
end

-- Never persist UnitDamage(target) weapon-range learning for players or their
-- player-controlled pets/guardians. NPC/boss targets retain the proven path.
local PVP_OldCaptureTargetDamage = MT.CaptureTargetDamage
function MT:CaptureTargetDamage()
    self:RememberPvPTarget()
    if UnitExists and UnitExists("target") then
        if UnitIsPlayer and UnitIsPlayer("target") then return end
        if UnitPlayerControlled and UnitPlayerControlled("target") then return end
    end
    return PVP_OldCaptureTargetDamage(self)
end

-- Stamp each event with its source authority. Creature-vs-self families are PvE
-- unless that exact source was positively seen as player-controlled (pet case).
local PVP_OldBuildDamageEvent = MT.BuildDamageEvent
function MT:BuildDamageEvent(mob, attack, amountTaken, blocked, resisted, absorbed, school, isCrit, hitType, ignoreArmor)
    local e = PVP_OldBuildDamageEvent(self, mob, attack, amountTaken, blocked, resisted, absorbed, school, isCrit, hitType, ignoreArmor)
    if e then
        if self:IsConfirmedPvPSource(mob) then e.sourceType = "PVP"
        elseif self._mtCombatEvent == "CHAT_MSG_COMBAT_CREATURE_VS_SELF_HITS" or
               self._mtCombatEvent == "CHAT_MSG_SPELL_CREATURE_VS_SELF_DAMAGE" then e.sourceType = "PVE"
        else e.sourceType = "UNKNOWN" end
    end
    return e
end

local PVP_OldBuildAvoidanceEvent = MT.BuildAvoidanceEvent
function MT:BuildAvoidanceEvent(kind, mob, attack, postArmorAmount, school)
    local e = PVP_OldBuildAvoidanceEvent(self, kind, mob, attack, postArmorAmount, school)
    if e then
        if self:IsConfirmedPvPSource(mob) then e.sourceType = "PVP"
        elseif self._mtCombatEvent == "CHAT_MSG_COMBAT_CREATURE_VS_SELF_MISSES" then e.sourceType = "PVE"
        else e.sourceType = "UNKNOWN" end
    end
    return e
end

-- Keep landed PvP damage in totals/events, but route all learning tables to
-- temporary throw-away tables while the mature damage engine runs.
local PVP_OldRecordDamage = MT.RecordDamage
function MT:RecordDamage(mob, attack, amountTaken, blocked, resisted, absorbed, school, isCrit, hitType, ignoreArmor)
    if not self:IsConfirmedPvPSource(mob) then
        return PVP_OldRecordDamage(self, mob, attack, amountTaken, blocked, resisted, absorbed, school, isCrit, hitType, ignoreArmor)
    end

    local encounterMemory = self.encounterMemory
    local sessionMemory = self.sessionMemory
    local abilitySchoolMemory = self.abilitySchoolMemory
    local pending = self.pending
    self.encounterMemory = {}
    self.sessionMemory = {}
    self.abilitySchoolMemory = {}
    self.pending = {}
    PVP_OldRecordDamage(self, mob, attack, amountTaken, blocked, resisted, absorbed, school, isCrit, hitType, ignoreArmor)
    self.encounterMemory = encounterMemory
    self.sessionMemory = sessionMemory
    self.abilitySchoolMemory = abilitySchoolMemory
    self.pending = pending
end

-- PvP avoidance is retained as an event/count but is not guessed from learned
-- weapon ranges and is never queued into persistent pending-estimate memory.
local PVP_OldRecordAvoidance = MT.RecordAvoidance
function MT:RecordAvoidance(kind, mob, attack, school)
    if self:IsConfirmedPvPSource(mob) then
        self:ApplyAvoidance(kind, mob, 0, school or "Physical", attack or "Melee")
        self:UpdateDisplay()
        return
    end
    return PVP_OldRecordAvoidance(self, kind, mob, attack, school)
end

-- In mixed fights, explicit PvP sources cannot steal the PvE encounter label.
-- Pure PvP fights keep the player/pet label normally.
local PVP_OldGenerateFightMetadata = MT.GenerateFightMetadata
function MT:GenerateFightMetadata(events, deathCounts)
    local combatType = self:ClassifyFightEvents(events)
    if combatType ~= "PVE" then return PVP_OldGenerateFightMetadata(self, events, deathCounts) end

    local filtered, i, e = {}, nil, nil
    for i = 1, table.getn(events or {}) do
        e = events[i]
        if not e or e.sourceType ~= "PVP" then table.insert(filtered, e) end
    end
    if table.getn(filtered) == 0 then filtered = events or {} end
    return PVP_OldGenerateFightMetadata(self, filtered, deathCounts)
end

-- Tag the newly finalized fight after the complete established EndCombat chain.
local PVP_OldEndCombat = MT.EndCombat
function MT:EndCombat()
    local beforeID = self.fights and self.fights[1] and self.fights[1].id
    PVP_OldEndCombat(self)
    local fight = self.fights and self.fights[1]
    if fight and fight.id ~= beforeID then
        fight.combatType = self:ClassifyFightEvents(fight.events)
        fight.pvp = fight.combatType == "PVP" and true or nil
        if self.SyncPersistentData then self:SyncPersistentData() end
    end
    self._mtCombatEvent = nil
end

-- Runtime cache only: never put player/pet identity caches into SavedVariables.
local PVP_OldStartCombat = MT.StartCombat
function MT:StartCombat()
    self._mtCombatEvent = nil
    return PVP_OldStartCombat(self)
end
