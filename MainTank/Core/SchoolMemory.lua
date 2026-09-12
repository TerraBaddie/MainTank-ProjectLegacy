-- MainTank v1.0.0 FR1L
-- Core/SchoolMemory.lua
--
-- Cross-source spell-school learning and full-resist recovery.
-- Vanilla combat text can omit a damage school when a spell is completely
-- resisted. The original MT school cache was keyed by attacker + ability, so a
-- first-ever full resist from a new attacker (for example Scarlet Cleric's Mind
-- Blast) could remain Unknown even when MT had already learned Mind Blast from
-- another source. FR1L adds a small global ability cache plus conservative
-- canonical fallbacks for unambiguous spell names.

if not MainTank then return end
local MT = MainTank

local SCHOOL_CANONICAL = {
    ["mind blast"] = "Shadow",
    ["mind flay"] = "Shadow",
    ["shadow bolt"] = "Shadow",
    ["shadow word: pain"] = "Shadow",
    ["shadow word pain"] = "Shadow",
    ["fireball"] = "Fire",
    ["fire blast"] = "Fire",
    ["blast wave"] = "Fire",
    ["flamestrike"] = "Fire",
    ["rain of fire"] = "Fire",
    ["frostbolt"] = "Frost",
    ["frost shock"] = "Frost",
    ["arcane explosion"] = "Arcane",
    ["arcane missiles"] = "Arcane",
    ["arcane volley"] = "Arcane",
    ["chain lightning"] = "Nature",
    ["lightning bolt"] = "Nature",
    ["earth shock"] = "Nature",
    ["flame shock"] = "Fire",
    ["holy fire"] = "Holy",
    ["holy shock"] = "Holy"
}

local function ValidMagicSchool(school)
    return school == "Holy" or school == "Fire" or school == "Nature" or
           school == "Frost" or school == "Shadow" or school == "Arcane"
end

local function TrimLower(text)
    text = tostring(text or "")
    text = string.gsub(text, "^%s+", "")
    text = string.gsub(text, "%s+$", "")
    return string.lower(text)
end

local function LearnGlobal(self, ability, school)
    if not ability or not ValidMagicSchool(school) then return end
    self.globalAbilitySchoolMemory = self.globalAbilitySchoolMemory or {}
    local key = TrimLower(ability)
    if key ~= "" then self.globalAbilitySchoolMemory[key] = school end
end

local function FoldMobSchoolMemory(self)
    self.globalAbilitySchoolMemory = self.globalAbilitySchoolMemory or {}
    local mob, abilities, ability, school
    for mob, abilities in pairs(self.abilitySchoolMemory or {}) do
        if type(abilities) == "table" then
            for ability, school in pairs(abilities) do
                if ValidMagicSchool(school) then LearnGlobal(self, ability, school) end
            end
        end
    end
end

local FR1L_PreviousLearnAbilitySchool = MT.LearnAbilitySchool
function MT:LearnAbilitySchool(mob, ability, school)
    if self._mtSuppressPvPLearning then return end
    FR1L_PreviousLearnAbilitySchool(self, mob, ability, school)
    LearnGlobal(self, ability, school)
end

local FR1L_PreviousGetAbilitySchool = MT.GetAbilitySchool
function MT:GetAbilitySchool(mob, ability)
    local exact = FR1L_PreviousGetAbilitySchool(self, mob, ability)
    if ValidMagicSchool(exact) then return exact end

    local key = TrimLower(ability)
    local learned = self.globalAbilitySchoolMemory and self.globalAbilitySchoolMemory[key]
    if ValidMagicSchool(learned) then return learned end

    return SCHOOL_CANONICAL[key]
end

local function RepairEventSchool(self, eventData)
    if type(eventData) ~= "table" then return false end
    local school = eventData.school
    if school and school ~= "Unknown" and school ~= "Physical" then
        if eventData.sourceType ~= "PVP" then LearnGlobal(self, eventData.ability, school) end
        return false
    end

    -- Never reinterpret ordinary physical damage just because an ability name
    -- happens to collide. Only repair events that already look magical: full
    -- resists, resisted damage, or records stored in the magic raw channel.
    local looksMagical = (eventData.kind == "FullResist") or
        ((tonumber(eventData.resist) or 0) > 0 and (tonumber(eventData.magicRaw) or 0) > 0) or
        ((eventData.school == "Unknown") and (tonumber(eventData.magicRaw) or 0) > 0)
    if not looksMagical then return false end

    local resolved = self:GetAbilitySchool(eventData.source, eventData.ability)
    if not ValidMagicSchool(resolved) then return false end

    eventData.school = resolved
    if (tonumber(eventData.raw) or 0) > 0 then
        eventData.magicRaw = tonumber(eventData.raw) or 0
        eventData.physicalRaw = 0
    end
    if eventData.sourceType ~= "PVP" then LearnGlobal(self, eventData.ability, resolved) end
    return true
end

local function RepairEventList(self, events)
    local repaired = 0
    local i
    for i = 1, table.getn(events or {}) do
        if RepairEventSchool(self, events[i]) then repaired = repaired + 1 end
    end
    return repaired
end

function MT:RepairUnknownSpellSchools()
    FoldMobSchoolMemory(self)
    local repaired = 0
    repaired = repaired + RepairEventList(self, self.events)
    repaired = repaired + RepairEventList(self, self.overallEvents)

    local i, fight
    for i = 1, table.getn(self.fights or {}) do
        fight = self.fights[i]
        if fight and fight.events then repaired = repaired + RepairEventList(self, fight.events) end
    end
    return repaired
end

-- Restore/persist the cross-source cache with the profile. This wrapper is
-- installed before VARIABLES_LOADED, so it participates in normal startup.
local FR1L_PreviousRestorePersistentData = MT.RestorePersistentData
function MT:RestorePersistentData()
    FR1L_PreviousRestorePersistentData(self)
    self.globalAbilitySchoolMemory = (self.profile and self.profile.globalAbilitySchoolMemory) or {}
    FoldMobSchoolMemory(self)

    -- FR2 startup cleanup: FR1L's historical Unknown-school repair is a
    -- migration, not normal startup work. Existing FR2/FR1X format-5 profiles
    -- have already been through this repair on prior logins. Preserve the full
    -- scan only for legacy profiles, then mark it complete.
    if self.profile then
        if tonumber(self.profile.schoolMemoryRepairVersion) ~= 1 then
            if (tonumber(self.profile.archiveFormatVersion) or 0) >= 5 and
               type(self.profile.globalAbilitySchoolMemory) == "table" then
                self.profile.schoolMemoryRepairVersion = 1
            else
                self:RepairUnknownSpellSchools()
                self.profile.schoolMemoryRepairVersion = 1
            end
        end
        self.profile.globalAbilitySchoolMemory = self.globalAbilitySchoolMemory
    end
end

local FR1L_PreviousSyncPersistentData = MT.SyncPersistentData
function MT:SyncPersistentData()
    if self.profile then self.profile.globalAbilitySchoolMemory = self.globalAbilitySchoolMemory or {} end
    FR1L_PreviousSyncPersistentData(self)
    if self.profile then self.profile.globalAbilitySchoolMemory = self.globalAbilitySchoolMemory or {} end
end

-- Rebuild school buckets from authoritative events. RC6 rebuilds the main DR
-- totals from events but historically retained the older aggregate schools
-- table, which could leave a repaired FullResist displayed under Unknown.
local FR1L_PreviousGetDisplayData = MT.GetDisplayData
function MT:GetDisplayData()
    local data = FR1L_PreviousGetDisplayData(self)
    if not data then return data end

    local events = self:GetDisplayEvents() or {}
    if table.getn(events) == 0 then return data end

    local schools = {}
    local i, eventData, school, bucket
    for i = 1, table.getn(events) do
        eventData = events[i]
        RepairEventSchool(self, eventData)
        school = eventData and eventData.school or nil
        if school and school ~= "Physical" then
            bucket = schools[school]
            if not bucket then
                bucket = {partial = 0, taken = 0, fullEstimated = 0, fullCount = 0}
                schools[school] = bucket
            end
            bucket.taken = bucket.taken + (tonumber(eventData.taken) or 0)
            if eventData.kind == "FullResist" then
                bucket.fullCount = bucket.fullCount + 1
                bucket.fullEstimated = bucket.fullEstimated + (tonumber(eventData.resist) or 0)
            else
                bucket.partial = bucket.partial + (tonumber(eventData.resist) or 0)
            end
        end
    end
    data.schools = schools
    return data
end

-- Archive.lua is loaded before this module in FR1L, so restored archived fights
-- can be repaired immediately as they re-enter the live list.
if MT.RestoreArchivedFight then
    local FR1L_PreviousRestoreArchivedFight = MT.RestoreArchivedFight
    function MT:RestoreArchivedFight(index)
        local result = FR1L_PreviousRestoreArchivedFight(self, index)
        self:RepairUnknownSpellSchools()
        return result
    end
end


-- Keep FR1h/FR1k reset semantics exact: learned school memory is combat/learned
-- data and must be cleared by the same reset path as abilitySchoolMemory.
local FR1L_PreviousResetSession = MT.ResetSession
function MT:ResetSession()
    FR1L_PreviousResetSession(self)
    self.globalAbilitySchoolMemory = {}
    if self.profile then self.profile.globalAbilitySchoolMemory = self.globalAbilitySchoolMemory end
end

