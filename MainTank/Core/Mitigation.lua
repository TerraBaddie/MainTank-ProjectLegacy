-- MainTank REFAC1 - Mitigation context and DR attribution stack
-- RC5 through RC6t remain in one lexical chunk intentionally. Later RC6 layers
-- reassign RC5-local classifier functions that earlier closures must continue
-- to observe; splitting those locals would change combat behavior.

local MT = MainTank
local E = MT._engine
local floor = math.floor
local format = string.format
local find = string.find
local lower = string.lower
local NewData = E.NewData
local CopyTable = E.CopyTable
local Round = E.Round
local MT_LEGACY_BACKDROP = E.MT_LEGACY_BACKDROP
local GetLegacyBorderColor = E.GetLegacyBorderColor
local StyleLegacyButton = E.StyleLegacyButton
local AddToTimelineBucket = E.AddToTimelineBucket
local Print = E.Print
local GetArmorReduction = E.GetArmorReduction
local GetScanTooltip = E.GetScanTooltip
local PrepareInventoryTooltip = E.PrepareInventoryTooltip
local AddPieEntry = E.AddPieEntry
local eventFrame = E.eventFrame
local RC_CreatePageFrame = E.RC_CreatePageFrame
local RC2_GetViewDuration = E.RC2_GetViewDuration
local RC4_SanitizeField = E.RC4_SanitizeField
local RC4_Split = E.RC4_Split

-- v1.0.0 RC5 - Mitigation Context + Compare Fight History
-- Tracks defensive player buffs/talents and attacker debuffs as context for
-- incoming events. Matching-context landed hits are preferred for avoidance
-- estimates. Tank comparison now retains/syncs fight history and pages by fight.
-- ============================================================================

local RC5_SYNC_HISTORY_MAX = 20
local RC5_GROUP_GRACE = 8

local function RC5_TrimText(text)
    text = tostring(text or "")
    text = string.gsub(text, "^%s+", "")
    text = string.gsub(text, "%s+$", "")
    return text
end

local function RC5_SafeTooltipCall(callback)
    if type(pcall) == "function" then
        local ok = pcall(callback)
        return ok and true or false
    end
    callback()
    return true
end

local function RC5_ReadTooltipText(tip)
    if not tip then return "", "" end
    local name = ""
    local lines = {}
    local count = tip.NumLines and tip:NumLines() or 0
    local i, leftFS, rightFS, leftText, rightText
    for i = 1, count do
        leftFS = getglobal("MainTankScanTooltipTextLeft" .. i)
        rightFS = getglobal("MainTankScanTooltipTextRight" .. i)
        leftText = leftFS and leftFS:GetText() or nil
        rightText = rightFS and rightFS:GetText() or nil
        if leftText and leftText ~= "" then
            if i == 1 and name == "" then name = RC5_TrimText(leftText) else table.insert(lines, RC5_TrimText(leftText)) end
        end
        -- Some Vanilla/Turtle-derived tooltip templates put useful text on the
        -- right-hand font string.  Include it so green equip effects and aura
        -- details cannot silently disappear from the mitigation scanner.
        if rightText and rightText ~= "" then
            table.insert(lines, RC5_TrimText(rightText))
        end
    end
    local desc = ""
    for i = 1, table.getn(lines) do
        if desc ~= "" then desc = desc .. " " end
        desc = desc .. lines[i]
    end
    return name, desc
end

local function RC5_FirstPercent(text)
    local _, _, value = string.find(tostring(text or ""), "([%d%.]+)%%")
    return tonumber(value)
end

local function RC5_FirstNumber(text)
    local _, _, value = string.find(tostring(text or ""), "([%d]+)")
    return tonumber(value)
end

local function RC5_ClassifyEffect(name, description, isDebuff)
    local n = lower(name or "")
    local d = lower(description or "")
    local effect = {name = name or "Unknown", description = description or "", kind = "context", known = false}

    if find(n, "blessing of sanctuary", 1, true) then
        effect.kind = "flatDR"
        effect.known = true
        effect.value = RC5_FirstNumber(description)
        effect.label = "Sanctuary / flat damage reduction"
    elseif find(n, "demoralizing shout", 1, true) or find(n, "demoralizing roar", 1, true) then
        effect.kind = "enemyAP"
        effect.known = true
        effect.value = RC5_FirstNumber(description)
        effect.label = "Enemy attack-power suppression"
    elseif find(n, "curse of weakness", 1, true) then
        effect.kind = "enemyDamage"
        effect.known = true
        effect.value = RC5_FirstNumber(description)
        effect.label = "Enemy physical-damage suppression"
    elseif find(n, "thunder clap", 1, true) then
        effect.kind = "attackSpeed"
        effect.known = true
        effect.value = RC5_FirstPercent(description)
        effect.label = "Enemy attack-speed reduction"
    elseif (find(d, "damage taken", 1, true) and (find(d, "reduc", 1, true) or find(d, "less", 1, true))) or
           (find(d, "damage you take", 1, true) and find(d, "reduc", 1, true)) then
        effect.kind = "percentDR"
        effect.value = RC5_FirstPercent(description)
        if not effect.value then effect.kind = "flatDR"; effect.value = RC5_FirstNumber(description) end
        effect.label = "Damage reduction"
    elseif isDebuff and find(d, "attack power", 1, true) and (find(d, "reduc", 1, true) or find(d, "decreas", 1, true)) then
        effect.kind = "enemyAP"
        effect.value = RC5_FirstNumber(description)
        effect.label = "Enemy attack-power suppression"
    elseif isDebuff and find(d, "damage", 1, true) and (find(d, "reduc", 1, true) or find(d, "less", 1, true)) then
        effect.kind = "enemyDamage"
        effect.value = RC5_FirstPercent(description) or RC5_FirstNumber(description)
        effect.label = "Enemy damage suppression"
    elseif find(d, "armor", 1, true) then
        effect.kind = "armorBuff"
        effect.label = "Armor modifier (already reflected in current armor)"
    elseif find(d, "resistance", 1, true) or find(d, "resistances", 1, true) then
        effect.kind = "resistanceBuff"
        effect.label = "Resistance modifier"
    end
    return effect
end

local function RC5_ScanUnitAuras(unit, isDebuff)
    local results = {}
    if not unit or not UnitExists(unit) then return results end
    local tip = GetScanTooltip()
    local i, texture, ok, name, desc, effect
    for i = 1, 32 do
        if isDebuff then texture = UnitDebuff(unit, i) else texture = UnitBuff(unit, i) end
        if not texture then break end
        tip:Hide(); tip:ClearLines()
        ok = false
        if isDebuff and tip.SetUnitDebuff then
            ok = RC5_SafeTooltipCall(function() tip:SetUnitDebuff(unit, i) end)
        elseif (not isDebuff) and tip.SetUnitBuff then
            ok = RC5_SafeTooltipCall(function() tip:SetUnitBuff(unit, i) end)
        end
        if ok then name, desc = RC5_ReadTooltipText(tip) end
        if not name or name == "" then name = tostring(texture or (isDebuff and "Debuff" or "Buff")) end
        effect = RC5_ClassifyEffect(name, desc, isDebuff)
        effect.texture = texture
        table.insert(results, effect)
    end
    tip:Hide()
    return results
end

local function RC5_ScanDefensiveTalents()
    local results = {}
    if type(GetNumTalentTabs) ~= "function" or type(GetNumTalents) ~= "function" or type(GetTalentInfo) ~= "function" then return results end
    local tip = GetScanTooltip()
    local tabs = GetNumTalentTabs() or 0
    local tab, index, count, name, rank, maxRank, desc, effect, ok
    for tab = 1, tabs do
        count = GetNumTalents(tab) or 0
        for index = 1, count do
            name, _, _, _, rank, maxRank = GetTalentInfo(tab, index)
            rank = tonumber(rank) or 0
            if name and rank > 0 then
                desc = ""
                if tip.SetTalent then
                    tip:Hide(); tip:ClearLines()
                    ok = RC5_SafeTooltipCall(function() tip:SetTalent(tab, index) end)
                    if ok then _, desc = RC5_ReadTooltipText(tip) end
                end
                effect = RC5_ClassifyEffect(name, desc, false)
                if effect.kind == "percentDR" or effect.kind == "flatDR" or effect.kind == "armorBuff" or effect.kind == "resistanceBuff" then
                    effect.rank = rank
                    effect.maxRank = tonumber(maxRank) or rank
                    table.insert(results, effect)
                end
            end
        end
    end
    tip:Hide()
    return results
end

local function RC5_EffectKey(effects)
    local keys = {}
    local i, effect, key
    for i = 1, table.getn(effects or {}) do
        effect = effects[i]
        if effect and effect.name then
            key = lower(effect.name) .. ":" .. tostring(effect.rank or "") .. ":" .. tostring(effect.kind or "")
            table.insert(keys, key)
        end
    end
    table.sort(keys)
    local out = ""
    for i = 1, table.getn(keys) do
        if i > 1 then out = out .. "," end
        out = out .. keys[i]
    end
    return out
end

function MT:RefreshMitigationContextCache(force)
    local now = GetTime()
    if not force and self.rc5ContextCacheAt and (now - self.rc5ContextCacheAt) < 0.25 then return end
    self.rc5ContextCacheAt = now
    self.rc5PlayerBuffs = RC5_ScanUnitAuras("player", false)
    self.rc5DefensiveTalents = RC5_ScanDefensiveTalents()
    if UnitExists("target") and not UnitIsFriend("player", "target") then
        self.rc5TargetName = UnitName("target")
        self.rc5TargetDebuffs = RC5_ScanUnitAuras("target", true)
    else
        self.rc5TargetName = nil
        self.rc5TargetDebuffs = {}
    end
end

function MT:CaptureMitigationContext(attacker)
    self:RefreshMitigationContextCache(false)
    local _, armor = UnitArmor("player")
    armor = tonumber(armor) or 0
    local debuffs = {}
    local attackerDebuffsKnown = false
    if attacker and self.rc5TargetName and attacker == self.rc5TargetName then
        debuffs = CopyTable(self.rc5TargetDebuffs or {})
        attackerDebuffsKnown = true
    end
    local context = {
        armor = armor,
        buffs = CopyTable(self.rc5PlayerBuffs or {}),
        talents = CopyTable(self.rc5DefensiveTalents or {}),
        debuffs = debuffs,
        attackerDebuffsKnown = attackerDebuffsKnown,
        attacker = attacker or "Unknown"
    }
    local key = "A" .. tostring(floor(armor + 0.5)) .. "|B:" .. RC5_EffectKey(context.buffs) ..
        "|T:" .. RC5_EffectKey(context.talents) .. "|D:" .. (attackerDebuffsKnown and RC5_EffectKey(context.debuffs) or "?")
    context.id = key
    self.mitigationContexts = self.mitigationContexts or {}
    if not self.mitigationContexts[key] then self.mitigationContexts[key] = CopyTable(context) end
    self.rc5ActiveContext = context
    return context
end

local function RC5_EnsureContextMemory(root, contextID, mob, attack)
    if not root[contextID] then root[contextID] = {} end
    if not root[contextID][mob] then root[contextID][mob] = {} end
    if not root[contextID][mob][attack] then
        root[contextID][mob][attack] = {minHit=nil, maxHit=nil, total=0, samples=0}
    end
    return root[contextID][mob][attack]
end

function MT:ObserveContextHit(contextID, mob, attack, amount)
    if not contextID or not mob or not attack or not amount or amount <= 0 then return end
    self.contextMemory = self.contextMemory or {}
    local memory = RC5_EnsureContextMemory(self.contextMemory, contextID, mob, attack)
    if not memory.minHit or amount < memory.minHit then memory.minHit = amount end
    if not memory.maxHit or amount > memory.maxHit then memory.maxHit = amount end
    memory.total = (memory.total or 0) + amount
    memory.samples = (memory.samples or 0) + 1
end

function MT:GetContextEstimate(contextID, mob, attack)
    local memory = self.contextMemory and self.contextMemory[contextID]
    memory = memory and memory[mob] and memory[mob][attack] or nil
    if not memory or (memory.samples or 0) < 1 then return nil end
    local estimate
    if (memory.total or 0) > 0 then estimate = memory.total / memory.samples
    elseif memory.minHit and memory.maxHit then estimate = (memory.minHit + memory.maxHit) / 2 end
    if not estimate then return nil end
    local confidence = "LOW"
    if memory.samples >= 15 then confidence = "HIGH" elseif memory.samples >= 5 then confidence = "MEDIUM" end
    return estimate, memory, confidence
end

-- Attach context to all newly built combat events.
local RC5_OldBuildDamageEvent = MT.BuildDamageEvent
function MT:BuildDamageEvent(mob, attack, amountTaken, blocked, resisted, absorbed, school, isCrit, hitType, ignoreArmor)
    local eventData = RC5_OldBuildDamageEvent(self, mob, attack, amountTaken, blocked, resisted, absorbed, school, isCrit, hitType, ignoreArmor)
    local context = self.rc5ActiveContext or self:CaptureMitigationContext(mob)
    if context then eventData.contextID = context.id end
    return eventData
end

local RC5_OldBuildAvoidanceEvent = MT.BuildAvoidanceEvent
function MT:BuildAvoidanceEvent(kind, mob, attack, postArmorAmount, school)
    local eventData = RC5_OldBuildAvoidanceEvent(self, kind, mob, attack, postArmorAmount, school)
    local context = self.rc5ActiveContext or self:CaptureMitigationContext(mob)
    if context then eventData.contextID = context.id end
    if self.rc5EstimateSource then eventData.estimateSource = self.rc5EstimateSource end
    if self.rc5EstimateConfidence then eventData.estimateConfidence = self.rc5EstimateConfidence end
    if self.rc5EstimateSamples then eventData.estimateSamples = self.rc5EstimateSamples end
    return eventData
end

local RC5_OldRecordDamage = MT.RecordDamage
function MT:RecordDamage(mob, attack, amountTaken, blocked, resisted, absorbed, school, isCrit, hitType, ignoreArmor)
    local context = self:CaptureMitigationContext(mob)
    RC5_OldRecordDamage(self, mob, attack, amountTaken, blocked, resisted, absorbed, school, isCrit, hitType, ignoreArmor)
    if context and not isCrit and hitType ~= "CRUSHING" and hitType ~= "ENVIRONMENTAL" then
        local postArmor = (amountTaken or 0) + (blocked or 0) + (resisted or 0) + (absorbed or 0)
        self:ObserveContextHit(context.id, mob, attack, postArmor)
    end
    self.rc5ActiveContext = nil
end

local RC5_OldRecordAvoidance = MT.RecordAvoidance
function MT:RecordAvoidance(kind, mob, attack, school)
    local context = self:CaptureMitigationContext(mob)
    local estimate, memory, confidence = context and self:GetContextEstimate(context.id, mob, attack)
    if estimate and memory then
        self.rc5EstimateSource = "Matching mitigation context"
        self.rc5EstimateConfidence = confidence
        self.rc5EstimateSamples = memory.samples or 0
        self:ApplyAvoidance(kind, mob, estimate, school, attack)
        self.rc5EstimateSource = nil; self.rc5EstimateConfidence = nil; self.rc5EstimateSamples = nil
        self.rc5ActiveContext = nil
        self:UpdateDisplay()
        return
    end
    self.rc5EstimateSource = nil; self.rc5EstimateConfidence = nil; self.rc5EstimateSamples = nil
    RC5_OldRecordAvoidance(self, kind, mob, attack, school)
    self.rc5ActiveContext = nil
end

-- Persist RC5 mitigation context data and tank-summary history.
local RC5_OldSyncPersistentData = MT.SyncPersistentData
function MT:SyncPersistentData()
    RC5_OldSyncPersistentData(self)
    if self.profile then
        self.profile.mitigationContexts = self.mitigationContexts or {}
        self.profile.contextMemory = self.contextMemory or {}
        self.profile.tankComparisonHistory = self.tankComparisonHistory or {}
    end
end

local RC5_OldRestorePersistentData = MT.RestorePersistentData
function MT:RestorePersistentData()
    RC5_OldRestorePersistentData(self)
    self.mitigationContexts = (self.profile and self.profile.mitigationContexts) or {}
    self.contextMemory = (self.profile and self.profile.contextMemory) or {}
    self.tankComparisonHistory = (self.profile and self.profile.tankComparisonHistory) or {}
    self.compareFightPage = 1
end

local RC5_OldResetSession = MT.ResetSession
function MT:ResetSession()
    RC5_OldResetSession(self)
    self.mitigationContexts = {}
    self.contextMemory = {}
    self.tankComparisonHistory = {}
    self.tankComparisonLatest = {}
    self.compareFightPage = 1
    self:SyncPersistentData()
end

-- Refresh aura/talent context when its underlying state can change.
local RC5_OldEventOnEvent = eventFrame:GetScript("OnEvent")
eventFrame:SetScript("OnEvent", function()
    if event == "CHARACTER_POINTS_CHANGED" then
        MT.rc5TalentCacheDirty = true
    end
    if event == "PLAYER_AURAS_CHANGED" or event == "CHARACTER_POINTS_CHANGED" or event == "PLAYER_TARGET_CHANGED" then
        MT:RefreshMitigationContextCache(true)
    end
    RC5_OldEventOnEvent()
end)

local RC5_OldEventOnUpdate = eventFrame:GetScript("OnUpdate")
eventFrame:SetScript("OnUpdate", function()
    if RC5_OldEventOnUpdate then RC5_OldEventOnUpdate() end
    if MT.inCombat and (not MT.rc5NextAuraRefresh or GetTime() >= MT.rc5NextAuraRefresh) then
        MT.rc5NextAuraRefresh = GetTime() + 0.75
        MT:RefreshMitigationContextCache(true)
    end
end)

-- Event Inspector now exposes mitigation state and estimate provenance.
local RC5_OldFormatEventInspector = MT.FormatEventInspector
function MT:FormatEventInspector(eventData)
    local text = RC5_OldFormatEventInspector(self, eventData)
    if not eventData then return text end
    local context = eventData.contextID and self.mitigationContexts and self.mitigationContexts[eventData.contextID]
    if context then
        text = text .. "\nContext: Armor " .. self:FormatNumber(context.armor or 0)
        local names = {}
        local i, effect
        for i = 1, table.getn(context.buffs or {}) do
            effect = context.buffs[i]
            if effect and (effect.known or effect.kind == "percentDR" or effect.kind == "flatDR") then table.insert(names, effect.name) end
        end
        for i = 1, table.getn(context.talents or {}) do
            effect = context.talents[i]
            if effect and effect.name then table.insert(names, effect.name .. " " .. tostring(effect.rank or "")) end
        end
        if table.getn(names) > 0 then
            text = text .. "\nDefensive: "
            for i = 1, table.getn(names) do if i > 1 then text = text .. ", " end; text = text .. names[i] end
        end
        names = {}
        for i = 1, table.getn(context.debuffs or {}) do
            effect = context.debuffs[i]
            if effect and (effect.known or effect.kind == "enemyAP" or effect.kind == "enemyDamage") then table.insert(names, effect.name) end
        end
        if table.getn(names) > 0 then
            text = text .. "\nAttacker debuffs: "
            for i = 1, table.getn(names) do if i > 1 then text = text .. ", " end; text = text .. names[i] end
        elseif not context.attackerDebuffsKnown then
            text = text .. "\nAttacker debuffs: unknown (attacker was not current target)"
        end
    end
    if eventData.estimateSource then
        text = text .. "\nEstimate: " .. tostring(eventData.estimateSource)
        if eventData.estimateConfidence then text = text .. " / " .. tostring(eventData.estimateConfidence) end
        if eventData.estimateSamples then text = text .. " / " .. tostring(eventData.estimateSamples) .. " hits" end
    end
    return text
end

-- ------------------------------ Compare history ------------------------------
local RC5_OldBuildTankSummaryFromFight = MT.BuildTankSummaryFromFight
function MT:BuildTankSummaryFromFight(fight)
    local summary = RC5_OldBuildTankSummaryFromFight(self, fight)
    if summary and fight then
        summary.fightID = fight.id or 0
        if not fight.endedAt then fight.endedAt = type(time) == "function" and time() or 0 end
        summary.endedAt = fight.endedAt or 0
    end
    return summary
end

local RC5_OldBuildTankSummaryFromDisplay = MT.BuildTankSummaryFromDisplay
function MT:BuildTankSummaryFromDisplay()
    local summary = RC5_OldBuildTankSummaryFromDisplay(self)
    if summary then
        local fight = type(self.currentView) == "number" and self.fights[self.currentView] or self.fights and self.fights[1]
        summary.fightID = fight and fight.id or 0
        summary.endedAt = fight and fight.endedAt or (type(time) == "function" and time() or 0)
    end
    return summary
end

-- Protocol v2 adds per-player fight ID and end timestamp. Decoder still accepts RC4 v1.
function MT:EncodeTankSummary(summary)
    if not summary then return nil end
    local fields = {
        "2",
        floor(summary.raw or 0), floor(summary.taken or 0), floor(summary.stopped or 0),
        floor(summary.armor or 0), floor(summary.avoidance or 0), floor(summary.block or 0),
        floor(summary.resist or 0), floor(summary.absorb or 0),
        format("%.1f", summary.duration or 0),
        floor(summary.physical or 0), floor(summary.magic or 0),
        RC4_SanitizeField(summary.class), RC4_SanitizeField(summary.enemy), RC4_SanitizeField(summary.label),
        floor(summary.fightID or 0), floor(summary.endedAt or 0)
    }
    local message = ""
    local i
    for i = 1, table.getn(fields) do if i > 1 then message = message .. ";" end; message = message .. tostring(fields[i]) end
    return message
end

local RC5_OldDecodeTankSummary = MT.DecodeTankSummary
function MT:DecodeTankSummary(message, sender)
    local f = RC4_Split(message)
    if f[1] == "1" then return RC5_OldDecodeTankSummary(self, message, sender) end
    if f[1] ~= "2" or table.getn(f) < 17 then return nil end
    local summary = {
        player = sender or "Unknown", raw=tonumber(f[2]) or 0, taken=tonumber(f[3]) or 0,
        stopped=tonumber(f[4]) or 0, armor=tonumber(f[5]) or 0, avoidance=tonumber(f[6]) or 0,
        block=tonumber(f[7]) or 0, resist=tonumber(f[8]) or 0, absorb=tonumber(f[9]) or 0,
        duration=tonumber(f[10]) or 0, physical=tonumber(f[11]) or 0, magic=tonumber(f[12]) or 0,
        class=f[13] or "UNKNOWN", enemy=f[14] or "Unknown", label=f[15] or "Fight",
        fightID=tonumber(f[16]) or 0, endedAt=tonumber(f[17]) or 0,
        receivedAt=GetTime(), savedAt=type(time) == "function" and time() or 0, localPlayer=false
    }
    if summary.raw <= 0 then return nil end
    return summary
end

local function RC5_SummaryIdentity(summary)
    if not summary then return nil end
    if (summary.fightID or 0) > 0 then return tostring(summary.player or "Unknown") .. "#" .. tostring(summary.fightID) end
    local stamp = summary.endedAt or summary.savedAt or 0
    return tostring(summary.player or "Unknown") .. "#" .. tostring(summary.enemy or "Unknown") .. "#" .. tostring(floor(stamp or 0))
end

local RC5_OldStoreTankSummary = MT.StoreTankSummary
function MT:StoreTankSummary(summary)
    if not summary or not summary.player then return end
    self.tankComparisonHistory = self.tankComparisonHistory or {}
    local identity = RC5_SummaryIdentity(summary)
    local i, existing, replaced
    for i = 1, table.getn(self.tankComparisonHistory) do
        existing = self.tankComparisonHistory[i]
        if RC5_SummaryIdentity(existing) == identity then
            self.tankComparisonHistory[i] = summary
            replaced = true
            break
        end
    end
    if not replaced then table.insert(self.tankComparisonHistory, summary) end
    while table.getn(self.tankComparisonHistory) > 200 do table.remove(self.tankComparisonHistory, 1) end
    RC5_OldStoreTankSummary(self, summary)
    self:SyncPersistentData()
end

-- Manual Sync Now recovers history missed during a disconnect, not just latest fight.
function MT:SyncLatestTankFight(quiet)
    if not self.fights or table.getn(self.fights) == 0 then
        local summary = self:BuildTankSummaryFromDisplay()
        if not summary then if not quiet then Print("No mitigation fight is available to sync.") end; return false end
        return self:SendTankSummary(summary, quiet)
    end
    local count = math.min(table.getn(self.fights), RC5_SYNC_HISTORY_MAX)
    local sent = 0
    local i, summary
    for i = count, 1, -1 do
        summary = self:BuildTankSummaryFromFight(self.fights[i])
        if summary and self:SendTankSummary(summary, true) then sent = sent + 1 end
    end
    if not quiet then Print("Shared " .. tostring(sent) .. " saved mitigation fight summaries with group members.") end
    return sent > 0
end

local function RC5_SummaryEnd(summary)
    local value = tonumber(summary and summary.endedAt) or 0
    if value > 0 then return value end
    return tonumber(summary and summary.savedAt) or 0
end

local function RC5_SummaryStart(summary)
    return RC5_SummaryEnd(summary) - (tonumber(summary and summary.duration) or 0)
end

local function RC5_GroupCanAccept(group, summary)
    if not group or not summary then return false end
    if lower(group.enemy or "") ~= lower(summary.enemy or "") then return false end
    if group.players and group.players[summary.player or "Unknown"] then return false end
    local s1, e1 = RC5_SummaryStart(summary), RC5_SummaryEnd(summary)
    local s2, e2 = group.startAt or 0, group.endAt or 0
    if e1 <= 0 or e2 <= 0 then return false end
    return s1 <= (e2 + RC5_GROUP_GRACE) and e1 >= (s2 - RC5_GROUP_GRACE)
end

local function RC5_BuildCompareGroups(owner)
    local all = {}
    local i, s
    for i = 1, table.getn(owner.tankComparisonHistory or {}) do
        s = owner.tankComparisonHistory[i]
        if s and (s.raw or 0) > 0 then table.insert(all, s) end
    end
    -- Ensure local saved fights are represented even if they predate RC5 sync history.
    for i = 1, table.getn(owner.fights or {}) do
        s = owner:BuildTankSummaryFromFight(owner.fights[i])
        if s then
            local id = RC5_SummaryIdentity(s)
            local found, j = false, 1
            while j <= table.getn(all) do if RC5_SummaryIdentity(all[j]) == id then found = true; break end; j = j + 1 end
            if not found then table.insert(all, s) end
        end
    end
    table.sort(all, function(a,b) return RC5_SummaryEnd(a) > RC5_SummaryEnd(b) end)

    local groups = {}
    local g, placed
    for i = 1, table.getn(all) do
        s = all[i]; placed = false
        for _, g in ipairs(groups) do
            if RC5_GroupCanAccept(g, s) then
                table.insert(g.rows, s); g.players[s.player or "Unknown"] = true
                g.startAt = math.min(g.startAt, RC5_SummaryStart(s)); g.endAt = math.max(g.endAt, RC5_SummaryEnd(s))
                placed = true; break
            end
        end
        if not placed then
            table.insert(groups, {enemy=s.enemy or s.label or "Fight", label=s.label or s.enemy or "Fight",
                startAt=RC5_SummaryStart(s), endAt=RC5_SummaryEnd(s), rows={s}, players={[s.player or "Unknown"]=true}})
        end
    end
    return groups
end

-- Replace row-pagination semantics with fight-pagination semantics.
function MT:UpdateTankCompareWindow()
    local frame = self:CreateTankCompareWindow()
    if frame.warning then frame.warning:SetText("Synced fight history; < and > change encounters. Sync Now recovers saved history.") end
    local groups = RC5_BuildCompareGroups(self)
    local pages = math.max(1, table.getn(groups))
    self.compareFightPage = math.max(1, math.min(self.compareFightPage or 1, pages))
    local group = groups[self.compareFightPage]
    frame.pageText:SetText(self.compareFightPage .. "/" .. pages)
    if self.compareFightPage <= 1 then frame.prev:Disable() else frame.prev:Enable() end
    if self.compareFightPage >= pages then frame.next:Disable() else frame.next:Enable() end

    local rows = group and group.rows or {}
    table.sort(rows, function(a,b)
        local ma = (a.raw or 0) > 0 and ((a.stopped or 0)/(a.raw or 1)) or 0
        local mb = (b.raw or 0) > 0 and ((b.stopped or 0)/(b.raw or 1)) or 0
        if ma == mb then return (a.raw or 0) > (b.raw or 0) end
        return ma > mb
    end)
    local selected, i, row, summary
    local visibleRows = table.getn(frame.rows or {})
    for i = 1, visibleRows do
        row = frame.rows[i]; summary = rows[i]
        if row then row.data = summary end
        if summary then
            local mitigation = (summary.raw or 0) > 0 and ((summary.stopped or 0)/(summary.raw or 1)*100) or 0
            row.cols[1]:SetText(summary.player or "Unknown"); row.cols[2]:SetText(self:FormatNumber(summary.raw or 0))
            row.cols[3]:SetText(self:FormatNumber(summary.taken or 0)); row.cols[4]:SetText(self:FormatNumber(summary.stopped or 0)); row.cols[5]:SetText(format("%.1f", mitigation))
            if self.compareSelectedPlayer == summary.player then row.highlight:Show(); selected = summary else row.highlight:Hide() end
            row:Show()
        else
            local c; for c=1,5 do row.cols[c]:SetText("") end; row.highlight:Hide(); row:Hide()
        end
    end
    if not selected and table.getn(rows) > 0 then selected = rows[1]; self.compareSelectedPlayer = selected.player; frame.rows[1].highlight:Show() end
    if selected then
        frame.detail:SetText((group and group.label or selected.enemy or selected.label or "Fight") .. "  " .. format("%.1fs", selected.duration or 0) ..
            "\nArmor " .. self:FormatNumber(selected.armor or 0) .. "  Avoid " .. self:FormatNumber(selected.avoidance or 0) ..
            "  Block " .. self:FormatNumber(selected.block or 0) .. "  Resist " .. self:FormatNumber(selected.resist or 0) .. "  Absorb " .. self:FormatNumber(selected.absorb or 0))
    else
        frame.detail:SetText("No synced summaries yet. Finish a fight with another MainTank user.")
    end
end

-- Rebind existing Compare arrows to fight history after the frame is created.
RC5_OldCreateTankCompareWindow = MT.CreateTankCompareWindow
function MT:CreateTankCompareWindow()
    local frame = RC5_OldCreateTankCompareWindow(self)
    if not frame.rc5FightPagerBound then
        frame.prev:SetScript("OnClick", function()
            if (MT.compareFightPage or 1) > 1 then MT.compareFightPage = MT.compareFightPage - 1; MT.compareSelectedPlayer=nil; MT:UpdateTankCompareWindow() end
        end)
        frame.next:SetScript("OnClick", function()
            local groups = RC5_BuildCompareGroups(MT)
            if (MT.compareFightPage or 1) < table.getn(groups) then MT.compareFightPage = MT.compareFightPage + 1; MT.compareSelectedPlayer=nil; MT:UpdateTankCompareWindow() end
        end)
        frame.sync:SetScript("OnClick", function() MT:SyncLatestTankFight(false); MT.compareFightPage=1; MT:UpdateTankCompareWindow() end)
        frame.rc5FightPagerBound = true
    end
    return frame
end

-- A compact slash report helps verify exactly what RC5 detected without adding
-- another crowded top-level button to the mature main-window layout.
RC5_OldHandleSlash = MT.HandleSlash
function MT:HandleSlash(msg)
    local raw = lower(msg or "")
    if raw == "context" or raw == "dr" then
        local context = self:CaptureMitigationContext(UnitExists("target") and UnitName("target") or nil)
        Print("Mitigation context: Armor " .. self:FormatNumber(context.armor or 0))
        local i, e
        for i=1,table.getn(context.buffs or {}) do e=context.buffs[i]; if e.known or e.kind=="percentDR" or e.kind=="flatDR" then Print("Buff: " .. e.name .. " - " .. (e.label or e.kind)) end end
        for i=1,table.getn(context.talents or {}) do e=context.talents[i]; Print("Talent: " .. e.name .. " " .. tostring(e.rank or "") .. " - " .. (e.label or e.kind)) end
        for i=1,table.getn(context.debuffs or {}) do e=context.debuffs[i]; if e.known or e.kind=="enemyAP" or e.kind=="enemyDamage" then Print("Target debuff: " .. e.name .. " - " .. (e.label or e.kind)) end end
        if not context.attackerDebuffsKnown then Print("Target debuffs unavailable for this attacker unless it is your current target.") end
        return
    end
    RC5_OldHandleSlash(self, msg)
end


-- ============================================================================
-- v1.0.0 RC5b - Vanilla/Project Legacy defensive-effect scanner hardening
-- Player auras in the 1.12 API are most reliably scanned through GetPlayerBuff
-- + GameTooltip:SetPlayerBuff.  Known Project Legacy talents are also resolved by
-- talent name/rank so custom tooltip wording does not make passive DR disappear.
-- ============================================================================

RC5B_SANCTUARY_BASE = { [1]=10, [2]=15, [3]=20, [4]=30 }

function RC5B_FindNumberAfter(text, pattern)
    local _, _, value = string.find(lower(tostring(text or "")), pattern)
    return tonumber(value)
end

function RC5B_GetTalentRankByName(wanted)
    if type(GetNumTalentTabs) ~= "function" or type(GetNumTalents) ~= "function" or type(GetTalentInfo) ~= "function" then return 0 end
    local tab, index, name, rank
    local wantedLower = lower(wanted or "")
    for tab = 1, (GetNumTalentTabs() or 0) do
        for index = 1, (GetNumTalents(tab) or 0) do
            name, _, _, _, rank = GetTalentInfo(tab, index)
            if name and lower(name) == wantedLower then return tonumber(rank) or 0 end
        end
    end
    return 0
end

function RC5B_ApplyKnownTalent(effect, name, rank)
    -- Project Legacy: no named private-server talent formulas.
    -- Defensive talents are classified from their actual tooltip wording.
    return false
end

-- More exact wording support, including Project Legacy talents/items.
RC5B_OldClassifyEffect = RC5_ClassifyEffect
RC5_ClassifyEffect = function(name, description, isDebuff)
    local effect = RC5B_OldClassifyEffect(name, description, isDebuff)
    local n = lower(name or "")
    local d = lower(description or "")

    -- Explicit talent names first when they arrive through tooltip scanning.
    if n == "guardian's favor" or n == "guardians favor" then
        -- Project Legacy Guardian's Favor is not mitigation; leave it as context.
        effect.kind = "context"
        effect.known = true
        effect.value = 0
        effect.label = "Taunt cooldown talent (no Sanctuary bonus)"
    elseif n == "improved defensive auras" then
        effect.kind = "auraBoost"; effect.known = true
    end

    -- Generic wording seen on Project Legacy talents and green item text.
    local pct = RC5B_FindNumberAfter(d, "decreases damage taken by ([%d%.]+)%%")
    if not pct then pct = RC5B_FindNumberAfter(d, "reduces all damage taken by ([%d%.]+)%%") end
    if not pct then pct = RC5B_FindNumberAfter(d, "reduces damage taken by ([%d%.]+)%%") end
    if pct then
        effect.kind = "percentDR"; effect.known = true; effect.value = pct; effect.school = "all"
        effect.label = "All damage taken -" .. tostring(pct) .. "%"
    end

    local spellPct = RC5B_FindNumberAfter(d, "reduces all spell damage taken by ([%d%.]+)%%")
    if not spellPct then spellPct = RC5B_FindNumberAfter(d, "decreases all spell damage taken by ([%d%.]+)%%") end
    if spellPct then
        effect.kind = "spellDR"; effect.known = true; effect.value = spellPct; effect.school = "spell"
        effect.label = "Spell damage taken -" .. tostring(spellPct) .. "%"
    end

    if find(n, "blessing of sanctuary", 1, true) or
       find(d, "reducing damage taken by up to", 1, true) or
       find(d, "reduces damage taken by up to", 1, true) or
       find(d, "damage taken reduced by up to", 1, true) then
        local flat = RC5B_FindNumberAfter(d, "reducing damage taken by up to ([%d]+)")
        if not flat then flat = RC5B_FindNumberAfter(d, "reduces damage taken by up to ([%d]+)") end
        if not flat then flat = RC5B_FindNumberAfter(d, "damage taken reduced by up to ([%d]+)") end
        if flat then effect.value = flat end
        if not effect.name or effect.name == "" or find(effect.name, "Interface", 1, true) then effect.name = "Blessing of Sanctuary" end
        effect.kind = "flatDR"; effect.known = true; effect.label = "Sanctuary / flat damage reduction"
    end
    return effect
end

-- Find the learned Sanctuary icon/rank as a Vanilla-safe fallback.  Aura
-- tooltips on some private-server clients expose only the texture even though
-- the buff is active, so matching the active texture to the learned spellbook
-- lets us still recognize Sanctuary.
function RC5B_GetSanctuarySpellInfo()
    if type(GetSpellName) ~= "function" or type(GetSpellTexture) ~= "function" then return nil, 0 end
    local i, name, rankText, texture, rank, bestTexture, bestRank
    bestRank = 0
    for i = 1, 500 do
        name, rankText = GetSpellName(i, BOOKTYPE_SPELL or "spell")
        if not name then break end
        if lower(name) == "blessing of sanctuary" then
            local _, _, rankValue = string.find(rankText or "", "(%d+)")
            rank = tonumber(rankValue) or 0
            texture = GetSpellTexture(i, BOOKTYPE_SPELL or "spell")
            if rank >= bestRank then bestRank = rank; bestTexture = texture end
        end
    end
    return bestTexture, bestRank
end

function RC5B_IsSanctuaryTexture(texture, learnedTexture)
    if not texture then return false end
    if learnedTexture and lower(tostring(texture)) == lower(tostring(learnedTexture)) then return true end
    -- Classic Blessing of Sanctuary icon.
    return find(lower(tostring(texture)), "spell_nature_lightningshield", 1, true) and true or false
end

-- 1.12 player-buff scanner.  SetUnitBuff is not dependable on every Vanilla
-- client build; SetPlayerBuff is the native fallback and gives us real text.
function RC5B_ScanPlayerBuffs()
    local results = {}
    local tip = GetScanTooltip()
    local slot, buffIndex, texture, ok, name, desc, effect
    local sanctuaryTexture, sanctuaryRank = RC5B_GetSanctuarySpellInfo()

    if type(GetPlayerBuff) == "function" and type(GetPlayerBuffTexture) == "function" and tip.SetPlayerBuff then
        for slot = 0, 31 do
            buffIndex = GetPlayerBuff(slot, "HELPFUL")
            if buffIndex and buffIndex >= 0 then
                texture = GetPlayerBuffTexture(buffIndex)
                if texture then
                    tip:Hide(); tip:ClearLines()
                    ok = RC5_SafeTooltipCall(function() tip:SetPlayerBuff(buffIndex) end)
                    name, desc = "", ""
                    if ok then name, desc = RC5_ReadTooltipText(tip) end
                    effect = RC5_ClassifyEffect(name or "", desc or "", false)

                    -- RC5c: certain Project Legacy clients give us the active aura
                    -- texture but no useful SetPlayerBuff text.  Sanctuary has a
                    -- stable spell texture, so recover it from the spellbook.
                    if RC5B_IsSanctuaryTexture(texture, sanctuaryTexture) and
                       not (effect and effect.kind == "flatDR" and effect.value and effect.value > 0) then
                        effect = effect or {}
                        effect.name = "Blessing of Sanctuary"
                        effect.description = desc or ""
                        effect.kind = "flatDR"
                        effect.known = true
                        -- RC6d: the aura texture is shared by every rank.  The
                        -- old fallback incorrectly treated the HIGHEST LEARNED
                        -- spellbook rank as the ACTIVE rank, so casting Rank 1
                        -- while Rank 4 was learned became 30/36 Flat DR.  Never
                        -- make that assumption.  A later RC6d pass resolves the
                        -- active rank from the aura tooltip, the exact spell/action
                        -- the player cast, or (last resort) the observed raw range.
                        effect.rank = 0
                        effect.value = 0
                        effect.sanctuaryRankUnknown = true
                        effect.maxLearnedRank = sanctuaryRank
                        effect.label = "Sanctuary / active rank unresolved"
                    end

                    if not effect.name or effect.name == "" then effect.name = tostring(texture) end
                    effect.texture = texture
                    effect.buffIndex = buffIndex
                    table.insert(results, effect)
                end
            end
        end
    else
        results = RC5_ScanUnitAuras("player", false)
    end

    -- Project Legacy fallback: its 1.12 client can expose the visible aura
    -- correctly through UnitBuff/SetUnitBuff while SetPlayerBuff yields no
    -- useful Sanctuary text.  If the native player-buff pass did not resolve
    -- Sanctuary, make one bounded UnitBuff tooltip pass and merge only a
    -- positively identified Sanctuary effect.
    local sanctuaryFound = false
    local i, fallback, candidate, cn, cd
    for i = 1, table.getn(results) do
        candidate = results[i]
        if candidate and candidate.kind == "flatDR" and candidate.name and
           find(lower(candidate.name), "blessing of sanctuary", 1, true) then
            sanctuaryFound = true
            break
        end
    end
    if not sanctuaryFound then
        fallback = RC5_ScanUnitAuras("player", false)
        for i = 1, table.getn(fallback or {}) do
            candidate = fallback[i]
            cn = lower(tostring(candidate and candidate.name or ""))
            cd = lower(tostring(candidate and candidate.description or ""))
            if candidate and (find(cn, "blessing of sanctuary", 1, true) or
               find(cd, "damage taken reduced by up to", 1, true) or
               find(cd, "reduces damage taken by up to", 1, true) or
               find(cd, "reducing damage taken by up to", 1, true)) then
                candidate.name = "Blessing of Sanctuary"
                candidate.kind = "flatDR"
                candidate.known = true
                candidate.school = "all"
                candidate.value = RC5B_FindNumberAfter(cd, "damage taken reduced by up to ([%d]+)") or
                                  RC5B_FindNumberAfter(cd, "reduces damage taken by up to ([%d]+)") or
                                  RC5B_FindNumberAfter(cd, "reducing damage taken by up to ([%d]+)") or
                                  candidate.value
                candidate.label = "Sanctuary / flat damage reduction"
                table.insert(results, candidate)
                break
            end
        end
    end

    tip:Hide()
    return results
end

-- Explicit known-talent pass.  This guarantees the two actual DR talents are
-- represented even if SetTalent tooltip text differs on Project Legacy.
function RC5B_ScanDefensiveTalents()
    local results = {}
    if type(GetNumTalentTabs) ~= "function" or type(GetNumTalents) ~= "function" or type(GetTalentInfo) ~= "function" then return results end
    local tip = GetScanTooltip()
    local tab, index, count, name, rank, maxRank, desc, effect, ok
    for tab = 1, (GetNumTalentTabs() or 0) do
        count = GetNumTalents(tab) or 0
        for index = 1, count do
            name, _, _, _, rank, maxRank = GetTalentInfo(tab, index)
            rank = tonumber(rank) or 0
            if name and rank > 0 then
                desc = ""
                if tip.SetTalent then
                    tip:Hide(); tip:ClearLines()
                    ok = RC5_SafeTooltipCall(function() tip:SetTalent(tab, index) end)
                    if ok then _, desc = RC5_ReadTooltipText(tip) end
                end
                effect = RC5_ClassifyEffect(name, desc, false)
                if RC5B_ApplyKnownTalent(effect, name, rank) or effect.kind == "percentDR" or effect.kind == "spellDR" or effect.kind == "flatDR" or effect.kind == "armorBuff" or effect.kind == "resistanceBuff" then
                    effect.rank = rank
                    effect.maxRank = tonumber(maxRank) or rank
                    table.insert(results, effect)
                end
            end
        end
    end
    tip:Hide()
    return results
end

-- Green equipped-item effects can provide DR too.  These are context effects,
-- not added directly to stopped damage; the landed-hit learner observes them.
function RC5B_ScanEquippedDR()
    local results = {}
    local tip = GetScanTooltip()
    local slot, name, desc, effect
    for slot = 1, 19 do
        if GetInventoryItemLink("player", slot) and PrepareInventoryTooltip(tip, slot) then
            name, desc = RC5_ReadTooltipText(tip)
            effect = RC5_ClassifyEffect(name, desc, false)
            if effect.kind == "percentDR" or effect.kind == "spellDR" or effect.kind == "flatDR" then
                effect.source = "item"
                effect.slot = slot
                table.insert(results, effect)
            end
        end
    end
    tip:Hide()
    return results
end

function MT:RefreshMitigationContextCache(force)
    local now = GetTime()
    if not force and self.rc5ContextCacheAt and (now - self.rc5ContextCacheAt) < 0.25 then return end
    self.rc5ContextCacheAt = now
    self.rc5PlayerBuffs = RC5B_ScanPlayerBuffs()

    -- Project Legacy: scan learned talents once, then keep the snapshot until
    -- CHARACTER_POINTS_CHANGED tells us the build actually changed.
    if self.rc5DefensiveTalents == nil or self.rc5TalentCacheDirty then
        self.rc5DefensiveTalents = RC5B_ScanDefensiveTalents()
        self.rc5TalentCacheDirty = false
    end

    self.rc5EquipmentDR = RC5B_ScanEquippedDR()
    if UnitExists("target") and not UnitIsFriend("player", "target") then
        self.rc5TargetName = UnitName("target")
        self.rc5TargetDebuffs = RC5_ScanUnitAuras("target", true)
    else
        self.rc5TargetName = nil
        self.rc5TargetDebuffs = {}
    end
end

function MT:CaptureMitigationContext(attacker)
    self:RefreshMitigationContextCache(false)
    local _, armor = UnitArmor("player")
    armor = tonumber(armor) or 0
    local debuffs = {}
    local attackerDebuffsKnown = false
    if attacker and self.rc5TargetName and attacker == self.rc5TargetName then
        debuffs = CopyTable(self.rc5TargetDebuffs or {})
        attackerDebuffsKnown = true
    end

    local buffs = CopyTable(self.rc5PlayerBuffs or {})
    local talents = CopyTable(self.rc5DefensiveTalents or {})
    local equipment = CopyTable(self.rc5EquipmentDR or {})

    -- Project Legacy Sanctuary is fixed vanilla-style Flat DR:
    -- Rank 1/2/3/4 = 10/15/20/30. Guardian's Favor is only a taunt-cooldown
    -- talent here and must never modify Sanctuary.
    local i, e, rank, base
    for i = 1, table.getn(buffs) do
        e = buffs[i]
        if e and e.name and find(lower(e.name), "blessing of sanctuary", 1, true) then
            rank = RC5B_FindNumberAfter(e.description or "", "rank ([%d]+)") or tonumber(e.rank)
            base = tonumber(e.baseValue) or tonumber(e.value)
            if (not base or base <= 0) and rank and RC5B_SANCTUARY_BASE[rank] then
                base = RC5B_SANCTUARY_BASE[rank]
            end
            if base and base > 0 then
                -- Normalize resolved values back to the exact Project Legacy rank.
                if rank and RC5B_SANCTUARY_BASE[rank] then base = RC5B_SANCTUARY_BASE[rank] end
                e.baseValue = base
                e.guardiansFavorRank = nil
                e.value = base
                e.label = "Sanctuary " .. tostring(base) .. " flat"
            end
        end
    end

    local context = {
        armor = armor,
        buffs = buffs,
        talents = talents,
        equipment = equipment,
        debuffs = debuffs,
        attackerDebuffsKnown = attackerDebuffsKnown,
        attacker = attacker or "Unknown"
    }
    local key = "A" .. tostring(floor(armor + 0.5)) .. "|B:" .. RC5_EffectKey(context.buffs) ..
        "|T:" .. RC5_EffectKey(context.talents) .. "|I:" .. RC5_EffectKey(context.equipment) ..
        "|D:" .. (attackerDebuffsKnown and RC5_EffectKey(context.debuffs) or "?")
    context.id = key
    self.mitigationContexts = self.mitigationContexts or {}
    if not self.mitigationContexts[key] then self.mitigationContexts[key] = CopyTable(context) end
    self.rc5ActiveContext = context
    return context
end

function RC5B_EffectTotals(context)
    local totals = { allPct=0, spellPct=0, flat=0 }
    local lists = {context.buffs or {}, context.talents or {}, context.equipment or {}}
    local li, i, e
    for li = 1, table.getn(lists) do
        for i = 1, table.getn(lists[li]) do
            e = lists[li][i]
            if e and e.value then
                if e.kind == "percentDR" then totals.allPct = totals.allPct + (tonumber(e.value) or 0)
                elseif e.kind == "spellDR" then totals.spellPct = totals.spellPct + (tonumber(e.value) or 0)
                elseif e.kind == "flatDR" then totals.flat = totals.flat + (tonumber(e.value) or 0) end
            end
        end
    end
    return totals
end

-- Replace the RC5 slash-report wrapper with a more useful diagnostic.  It also
-- prints every detected defensive effect and the combined nominal DR context.
RC5B_OldHandleSlash = MT.HandleSlash
function MT:HandleSlash(msg)
    local raw = lower(msg or "")
    if raw == "context" or raw == "dr" then
        self:RefreshMitigationContextCache(true)
        local context = self:CaptureMitigationContext(UnitExists("target") and UnitName("target") or nil)
        local totals = RC5B_EffectTotals(context)
        Print("Mitigation context: Armor " .. self:FormatNumber(context.armor or 0) ..
            " | Physical DR " .. tostring(totals.allPct) .. "% | Magic DR " .. tostring(totals.allPct + totals.spellPct) ..
            "% (" .. tostring(totals.allPct) .. "% all + " .. tostring(totals.spellPct) .. "% spell) | Flat DR " .. tostring(totals.flat))
        local i, e
        for i=1,table.getn(context.buffs or {}) do
            e=context.buffs[i]
            if e.known or e.kind=="percentDR" or e.kind=="spellDR" or e.kind=="flatDR" then
                Print("Buff: " .. e.name .. " - " .. (e.label or e.kind) .. (e.value and (" ["..tostring(e.value).."]") or ""))
            end
        end
        for i=1,table.getn(context.talents or {}) do
            e=context.talents[i]
            Print("Talent: " .. e.name .. " " .. tostring(e.rank or "") .. " - " .. (e.label or e.kind) .. (e.value and (" ["..tostring(e.value).."]") or ""))
        end
        for i=1,table.getn(context.equipment or {}) do
            e=context.equipment[i]
            Print("Item: " .. e.name .. " - " .. (e.label or e.kind) .. (e.value and (" ["..tostring(e.value).."]") or ""))
        end
        for i=1,table.getn(context.debuffs or {}) do
            e=context.debuffs[i]
            if e.known or e.kind=="enemyAP" or e.kind=="enemyDamage" or e.kind=="attackSpeed" then
                Print("Target debuff: " .. e.name .. " - " .. (e.label or e.kind) .. (e.value and (" ["..tostring(e.value).."]") or ""))
            end
        end
        if not context.attackerDebuffsKnown then Print("Target debuffs unavailable for this attacker unless it is your current target.") end
        return
    end
    RC5B_OldHandleSlash(self, msg)
end



-- ============================================================================
-- RC5d - Mitigation DR page + stronger equipped-item DR scanner
-- ============================================================================

-- Keep the original inventory tooltip intact first. Some Project Legacy items carry
-- server-added green Equip text which can disappear if an old four-field item
-- hyperlink is reconstructed. Only fall back to the full hyperlink if needed.
RC5B_ScanEquippedDR = function()
    local results = {}
    local tip = GetScanTooltip()
    local slot, link, name, desc, effect, found, itemString
    for slot = 1, 19 do
        link = GetInventoryItemLink("player", slot)
        if link then
            tip:Hide(); tip:ClearLines()
            found = tip:SetInventoryItem("player", slot)
            if found and tip:NumLines() > 0 then
                name, desc = RC5_ReadTooltipText(tip)
                effect = RC5_ClassifyEffect(name, desc, false)
            else
                effect = nil
            end

            -- Full modern/private-server link fallback, preserving every field.
            if (not effect or not (effect.kind == "percentDR" or effect.kind == "spellDR" or effect.kind == "flatDR")) and link then
                _, _, itemString = string.find(link, "|H(item:[^|]+)|h")
                if itemString then
                    tip:Hide(); tip:ClearLines()
                    RC5_SafeTooltipCall(function() tip:SetHyperlink(itemString) end)
                    name, desc = RC5_ReadTooltipText(tip)
                    effect = RC5_ClassifyEffect(name, desc, false)
                end
            end

            if effect and (effect.kind == "percentDR" or effect.kind == "spellDR" or effect.kind == "flatDR") then
                effect.source = "item"
                effect.slot = slot
                if (not effect.name or effect.name == "") and link then
                    local _, _, linkedName = string.find(link, "%[(.-)%]")
                    effect.name = linkedName or ("Inventory Slot " .. tostring(slot))
                end
                table.insert(results, effect)
            end
        end
    end
    tip:Hide()
    return results
end

function RC5D_AddLine(frame, index, text, value, y, header)
    local row = frame.drRows[index]
    if not row then
        row = {}
        row.label = frame:CreateFontString(nil, "OVERLAY", header and "GameFontNormal" or "GameFontHighlightSmall")
        row.label:SetJustifyH("LEFT")
        row.value = frame:CreateFontString(nil, "OVERLAY", header and "GameFontNormal" or "GameFontHighlightSmall")
        row.value:SetJustifyH("RIGHT")
        frame.drRows[index] = row
    end
    row.label:ClearAllPoints(); row.value:ClearAllPoints()
    row.label:SetPoint("TOPLEFT", frame, "TOPLEFT", header and 11 or 18, y)
    row.label:SetWidth(178)
    row.value:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -26, y)
    row.value:SetWidth(92)
    -- Use the native GameFontNormal / GameFontHighlightSmall sizes so the DR
    -- page matches the rest of MainTank instead of forcing tiny text.
    row.label:SetText(text or "")
    row.value:SetText(value or "")
    row.label:Show(); row.value:Show()
end

function MT:CreateDRWindow()
    if self.drFrame then return self.drFrame end
    local frame = RC_CreatePageFrame("MainTankDRFrame", "Mitigation DR")
    frame.drRows = {}
    frame.note = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.note:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 12, 9)
    frame.note:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -12, 9)
    frame.note:SetJustifyH("LEFT")
    frame.note:SetText("/mt dr refreshes this page. Enemy effects require the attacker as your target.")
    self.drFrame = frame
    return frame
end

function MT:UpdateDRWindow()
    local frame = self:CreateDRWindow()
    self:RefreshMitigationContextCache(true)
    local attacker = UnitExists("target") and UnitName("target") or nil
    local context = self:CaptureMitigationContext(attacker)
    local totals = RC5B_EffectTotals(context)
    local mob = attacker or ""
    local armorReduction = GetArmorReduction(mob)
    local physicalTotal = totals.allPct or 0
    local magicTotal = (totals.allPct or 0) + (totals.spellPct or 0)

    for i=1,table.getn(frame.drRows or {}) do
        frame.drRows[i].label:Hide(); frame.drRows[i].value:Hide()
    end

    local row, y = 1, -36
    RC5D_AddLine(frame,row,"Armor",self:FormatNumber(context.armor or 0).." ("..string.format("%.1f",(armorReduction or 0)*100).."%)",y,true); row=row+1; y=y-19

    RC5D_AddLine(frame,row,"Flat Damage Reduction","",y,true); row=row+1; y=y-17
    local shown = false
    for i=1,table.getn(context.buffs or {}) do
        local e=context.buffs[i]
        if e and e.kind=="flatDR" and (tonumber(e.value) or 0)>0 then
            RC5D_AddLine(frame,row,e.name or "Buff","+"..tostring(e.value),y,false); row=row+1; y=y-15; shown=true
        end
    end
    for i=1,table.getn(context.equipment or {}) do
        local e=context.equipment[i]
        if e and e.kind=="flatDR" and (tonumber(e.value) or 0)>0 then
            RC5D_AddLine(frame,row,e.name or "Item","+"..tostring(e.value),y,false); row=row+1; y=y-15; shown=true
        end
    end
    if not shown then RC5D_AddLine(frame,row,"None detected","",y,false); row=row+1; y=y-15 end
    y=y-3

    RC5D_AddLine(frame,row,"Physical Damage Reduction","",y,true); row=row+1; y=y-17
    for i=1,table.getn(context.talents or {}) do
        local e=context.talents[i]
        if e and e.kind=="percentDR" and (tonumber(e.value) or 0)>0 then RC5D_AddLine(frame,row,e.name or "Talent",tostring(e.value).."%",y,false); row=row+1; y=y-15 end
    end
    for i=1,table.getn(context.equipment or {}) do
        local e=context.equipment[i]
        if e and e.kind=="percentDR" and (tonumber(e.value) or 0)>0 then RC5D_AddLine(frame,row,e.name or "Item",tostring(e.value).."%",y,false); row=row+1; y=y-15 end
    end
    RC5D_AddLine(frame,row,"Total",tostring(physicalTotal).."%",y,false); row=row+1; y=y-18

    RC5D_AddLine(frame,row,"Spell Damage Reduction","",y,true); row=row+1; y=y-17
    for i=1,table.getn(context.talents or {}) do
        local e=context.talents[i]
        if e and e.kind=="spellDR" and (tonumber(e.value) or 0)>0 then RC5D_AddLine(frame,row,e.name or "Talent",tostring(e.value).."%",y,false); row=row+1; y=y-15 end
    end
    for i=1,table.getn(context.equipment or {}) do
        local e=context.equipment[i]
        if e and e.kind=="spellDR" and (tonumber(e.value) or 0)>0 then RC5D_AddLine(frame,row,e.name or "Item",tostring(e.value).."%",y,false); row=row+1; y=y-15 end
    end
    RC5D_AddLine(frame,row,"Total (including all DR)",tostring(magicTotal).."%",y,false); row=row+1; y=y-18

    RC5D_AddLine(frame,row,"Enemy Damage Reduction","",y,true); row=row+1; y=y-17
    local debuffShown=false
    for i=1,table.getn(context.debuffs or {}) do
        local e=context.debuffs[i]
        if e and (e.known or e.kind=="enemyAP" or e.kind=="enemyDamage" or e.kind=="attackSpeed") then
            RC5D_AddLine(frame,row,e.name or "Debuff",e.label or "Detected",y,false); row=row+1; y=y-15; debuffShown=true
        end
    end
    if not debuffShown then RC5D_AddLine(frame,row,"None detected","",y,false) end
end

function MT:ShowDRPage()
    local frame = self:CreateDRWindow()
    self:ShowRCPage(frame, function(owner) owner:UpdateDRWindow() end)
end

RC5D_OldHandleSlash = MT.HandleSlash
function MT:HandleSlash(msg)
    local raw = lower(msg or "")
    if raw == "dr" then
        self:ShowDRPage()
        return
    end
    RC5D_OldHandleSlash(self, msg)
end



-- ============================================================================
-- RC5e - Class-agnostic defensive talent text scanner
-- Scans every learned talent on every class and recognizes common tanking
-- wording instead of relying on Paladin talent names.
-- ============================================================================

RC5E_OldClassifyEffect = RC5_ClassifyEffect

function RC5E_FindPct(text, pattern)
    local _, _, value = string.find(lower(text or ""), pattern)
    return tonumber(value)
end

function RC5E_FindFlat(text, pattern)
    local _, _, value = string.find(lower(text or ""), pattern)
    return tonumber(value)
end

RC5_ClassifyEffect = function(name, description, isDebuff)
    local effect = RC5E_OldClassifyEffect(name, description, isDebuff)
    local d = lower(description or "")
    local pct, flat

    -- All-damage percentage reduction. Covers wording used by many custom
    -- server talents/items: decreases/reduces damage taken, or damage taken is
    -- reduced, with either "all damage" or generic "damage" wording.
    pct = RC5E_FindPct(d, "decreases all damage taken by ([%d%.]+)%%")
    if not pct then pct = RC5E_FindPct(d, "decreases damage taken by ([%d%.]+)%%") end
    if not pct then pct = RC5E_FindPct(d, "reduces all damage taken by ([%d%.]+)%%") end
    if not pct then pct = RC5E_FindPct(d, "reduces damage taken by ([%d%.]+)%%") end
    if not pct then pct = RC5E_FindPct(d, "damage taken is reduced by ([%d%.]+)%%") end
    if not pct then pct = RC5E_FindPct(d, "all damage taken is reduced by ([%d%.]+)%%") end
    if pct then
        effect.kind = "percentDR"; effect.known = true; effect.value = pct; effect.school = "all"
        effect.label = "All damage taken -" .. tostring(pct) .. "%"
    end

    -- Physical-only DR.
    pct = RC5E_FindPct(d, "reduces physical damage taken by ([%d%.]+)%%")
    if not pct then pct = RC5E_FindPct(d, "decreases physical damage taken by ([%d%.]+)%%") end
    if not pct then pct = RC5E_FindPct(d, "physical damage taken is reduced by ([%d%.]+)%%") end
    if not pct then pct = RC5E_FindPct(d, "reduces melee damage taken by ([%d%.]+)%%") end
    if not pct then pct = RC5E_FindPct(d, "decreases melee damage taken by ([%d%.]+)%%") end
    if pct then
        effect.kind = "physicalDR"; effect.known = true; effect.value = pct; effect.school = "physical"
        effect.label = "Physical damage taken -" .. tostring(pct) .. "%"
    end

    -- Spell/magic-only DR, including generic magic wording.
    pct = RC5E_FindPct(d, "reduces all spell damage taken by ([%d%.]+)%%")
    if not pct then pct = RC5E_FindPct(d, "decreases all spell damage taken by ([%d%.]+)%%") end
    if not pct then pct = RC5E_FindPct(d, "reduces spell damage taken by ([%d%.]+)%%") end
    if not pct then pct = RC5E_FindPct(d, "decreases spell damage taken by ([%d%.]+)%%") end
    if not pct then pct = RC5E_FindPct(d, "reduces magic damage taken by ([%d%.]+)%%") end
    if not pct then pct = RC5E_FindPct(d, "decreases magic damage taken by ([%d%.]+)%%") end
    if not pct then pct = RC5E_FindPct(d, "spell damage taken is reduced by ([%d%.]+)%%") end
    if not pct then pct = RC5E_FindPct(d, "magic damage taken is reduced by ([%d%.]+)%%") end
    if pct then
        effect.kind = "spellDR"; effect.known = true; effect.value = pct; effect.school = "spell"
        effect.label = "Spell damage taken -" .. tostring(pct) .. "%"
    end

    -- Flat damage reduction. Avoid Sanctuary "up to" here because the older
    -- classifier already handles its rank-aware value separately.
    if not find(d, "up to", 1, true) then
        flat = RC5E_FindFlat(d, "decreases all damage taken by ([%d]+)")
        if not flat then flat = RC5E_FindFlat(d, "decreases damage taken by ([%d]+)") end
        if not flat then flat = RC5E_FindFlat(d, "reduces all damage taken by ([%d]+)") end
        if not flat then flat = RC5E_FindFlat(d, "reduces damage taken by ([%d]+)") end
        if not flat then flat = RC5E_FindFlat(d, "damage taken is reduced by ([%d]+)") end
        if flat and not string.find(d, tostring(flat) .. "%%", 1, true) then
            effect.kind = "flatDR"; effect.known = true; effect.value = flat; effect.school = "all"
            effect.label = "Flat damage taken -" .. tostring(flat)
        end
    end

    -- Other common tanking/defensive talent effects. These remain context-only
    -- and are not incorrectly folded into the direct DR total.
    pct = RC5E_FindPct(d, "increases your armor value from items by ([%d%.]+)%%")
    if not pct then pct = RC5E_FindPct(d, "increases armor value from items by ([%d%.]+)%%") end
    if not pct then pct = RC5E_FindPct(d, "increases your armor by ([%d%.]+)%%") end
    if not pct then pct = RC5E_FindPct(d, "increases armor by ([%d%.]+)%%") end
    if pct and not (effect.kind == "percentDR" or effect.kind == "physicalDR" or effect.kind == "spellDR") then
        effect.kind = "armorBuff"; effect.known = true; effect.value = pct
        effect.label = "Armor +" .. tostring(pct) .. "%"
    end

    pct = RC5E_FindPct(d, "reduces your chance to be critically hit by ([%d%.]+)%%")
    if not pct then pct = RC5E_FindPct(d, "reduces the chance you will be critically hit by ([%d%.]+)%%") end
    if not pct then pct = RC5E_FindPct(d, "chance to be critically hit by melee attacks reduced by ([%d%.]+)%%") end
    if pct then
        effect.kind = "critReduction"; effect.known = true; effect.value = pct
        effect.label = "Chance to be critically hit -" .. tostring(pct) .. "%"
    end

    pct = RC5E_FindPct(d, "increases your chance to dodge by ([%d%.]+)%%")
    if not pct then pct = RC5E_FindPct(d, "increases dodge chance by ([%d%.]+)%%") end
    if pct then effect.kind="dodgeBonus"; effect.known=true; effect.value=pct; effect.label="Dodge +"..tostring(pct).."%" end

    pct = RC5E_FindPct(d, "increases your chance to parry by ([%d%.]+)%%")
    if not pct then pct = RC5E_FindPct(d, "increases parry chance by ([%d%.]+)%%") end
    if pct then effect.kind="parryBonus"; effect.known=true; effect.value=pct; effect.label="Parry +"..tostring(pct).."%" end

    pct = RC5E_FindPct(d, "increases your chance to block by ([%d%.]+)%%")
    if not pct then pct = RC5E_FindPct(d, "increases block chance by ([%d%.]+)%%") end
    if pct then effect.kind="blockChanceBonus"; effect.known=true; effect.value=pct; effect.label="Block chance +"..tostring(pct).."%" end

    pct = RC5E_FindPct(d, "increases the amount your shield blocks by ([%d%.]+)%%")
    if not pct then pct = RC5E_FindPct(d, "increases your block value by ([%d%.]+)%%") end
    if not pct then pct = RC5E_FindPct(d, "increases shield block value by ([%d%.]+)%%") end
    if pct then effect.kind="blockValueBonus"; effect.known=true; effect.value=pct; effect.label="Block value +"..tostring(pct).."%" end

    return effect
end

-- Scan ALL learned talents for ALL classes.  A talent is included whenever its
-- tooltip matches a recognized defensive phrase; Paladin name-specific handling
-- remains as a fallback, not the main system.
RC5B_ScanDefensiveTalents = function()
    local results = {}
    if type(GetNumTalentTabs) ~= "function" or type(GetNumTalents) ~= "function" or type(GetTalentInfo) ~= "function" then return results end
    local tip = GetScanTooltip()
    local tab, index, count, name, rank, maxRank, desc, effect, ok
    for tab = 1, (GetNumTalentTabs() or 0) do
        count = GetNumTalents(tab) or 0
        for index = 1, count do
            name, _, _, _, rank, maxRank = GetTalentInfo(tab, index)
            rank = tonumber(rank) or 0
            if name and rank > 0 then
                desc = ""
                if tip.SetTalent then
                    tip:Hide(); tip:ClearLines()
                    ok = RC5_SafeTooltipCall(function() tip:SetTalent(tab, index) end)
                    if ok then _, desc = RC5_ReadTooltipText(tip) end
                end
                effect = RC5_ClassifyEffect(name, desc, false)
                RC5B_ApplyKnownTalent(effect, name, rank)
                if effect and (effect.kind == "percentDR" or effect.kind == "physicalDR" or effect.kind == "spellDR" or effect.kind == "flatDR" or effect.kind == "armorBuff" or effect.kind == "resistanceBuff" or effect.kind == "critReduction" or effect.kind == "dodgeBonus" or effect.kind == "parryBonus" or effect.kind == "blockChanceBonus" or effect.kind == "blockValueBonus" or effect.kind == "sanctuaryBoost" or effect.kind == "auraBoost") then
                    effect.rank = rank
                    effect.maxRank = tonumber(maxRank) or rank
                    effect.source = "talent"
                    table.insert(results, effect)
                end
            end
        end
    end
    tip:Hide()
    return results
end

-- Extend totals with physical-only DR while preserving previous fields.
RC5E_OldEffectTotals = RC5B_EffectTotals
RC5B_EffectTotals = function(context)
    local totals = RC5E_OldEffectTotals(context)
    totals.physicalPct = totals.physicalPct or 0
    local lists = {context.buffs or {}, context.talents or {}, context.equipment or {}}
    local li, i, e
    for li=1,table.getn(lists) do
        for i=1,table.getn(lists[li]) do
            e=lists[li][i]
            if e and e.kind=="physicalDR" then totals.physicalPct = totals.physicalPct + (tonumber(e.value) or 0) end
        end
    end
    return totals
end

-- Add class-agnostic talent rows and an Other Defensive Talents section to the
-- DR page.  This intentionally reports armor/avoidance/crit/block talent effects
-- without pretending they are direct percentage DR.
function MT:UpdateDRWindow()
    local frame = self:CreateDRWindow()
    self:RefreshMitigationContextCache(true)
    local attacker = UnitExists("target") and UnitName("target") or nil
    local context = self:CaptureMitigationContext(attacker)
    local totals = RC5B_EffectTotals(context)
    local mob = attacker or ""
    local armorReduction = GetArmorReduction(mob)
    local physicalTotal = (totals.allPct or 0) + (totals.physicalPct or 0)
    local magicTotal = (totals.allPct or 0) + (totals.spellPct or 0)
    local i, e, row, y, shown, li

    if frame.note then frame.note:Hide() end
    for i=1,table.getn(frame.drRows or {}) do
        frame.drRows[i].label:Hide()
        frame.drRows[i].value:Hide()
    end

    row=1; y=-38
    RC5D_AddLine(frame,row,"Armor",self:FormatNumber(context.armor or 0).." ("..string.format("%.1f",(armorReduction or 0)*100).."%)",y,true)
    row=row+1; y=y-24

    RC5D_AddLine(frame,row,"Flat DR","",y,true)
    row=row+1; y=y-17
    shown=false
    local flatLists={context.buffs or {},context.talents or {},context.equipment or {}}
    for li=1,table.getn(flatLists) do
        for i=1,table.getn(flatLists[li]) do
            e=flatLists[li][i]
            if e and e.kind=="flatDR" and (tonumber(e.value) or 0)>0 then
                RC5D_AddLine(frame,row,e.name or "Effect","+"..tostring(e.value),y,false)
                row=row+1; y=y-14; shown=true
            end
        end
    end
    if not shown then
        RC5D_AddLine(frame,row,"None detected","",y,false)
        row=row+1; y=y-14
    end
    y=y-5

    RC5D_AddLine(frame,row,"Physical DR","",y,true)
    row=row+1; y=y-17
    local physLists={context.talents or {},context.equipment or {},context.buffs or {}}
    for li=1,table.getn(physLists) do
        for i=1,table.getn(physLists[li]) do
            e=physLists[li][i]
            if e and (e.kind=="percentDR" or e.kind=="physicalDR") and (tonumber(e.value) or 0)>0 then
                RC5D_AddLine(frame,row,e.name or "Effect",tostring(e.value).."%",y,false)
                row=row+1; y=y-14
            end
        end
    end
    RC5D_AddLine(frame,row,"Total",tostring(physicalTotal).."%",y,false)
    row=row+1; y=y-20

    RC5D_AddLine(frame,row,"Magic DR","",y,true)
    row=row+1; y=y-17
    for i=1,table.getn(context.talents or {}) do
        e=context.talents[i]
        if e and e.kind=="spellDR" and (tonumber(e.value) or 0)>0 then
            RC5D_AddLine(frame,row,e.name or "Talent",tostring(e.value).."%",y,false)
            row=row+1; y=y-14
        end
    end
    for i=1,table.getn(context.equipment or {}) do
        e=context.equipment[i]
        if e and e.kind=="spellDR" and (tonumber(e.value) or 0)>0 then
            RC5D_AddLine(frame,row,e.name or "Item",tostring(e.value).."%",y,false)
            row=row+1; y=y-14
        end
    end
    RC5D_AddLine(frame,row,"Total",tostring(magicTotal).."%",y,false)
end




-- ============================================================================
-- RC5f - Register Mitigation DR as a real managed MT page
-- ============================================================================
-- RC5d created the DR frame, but the RC1f page manager predates that page and
-- therefore did not know the name MainTankDRFrame. ShowRCPage silently
-- rejected it. Register DR explicitly with the manager instead.

RC5F_OldRefreshManagedPageRegistry = MT.RefreshManagedPageRegistry
function MT:RefreshManagedPageRegistry()
    RC5F_OldRefreshManagedPageRegistry(self)
    if self.drFrame then
        self:RegisterManagedPage("DR", self.drFrame)
    else
        RC5F_DRFrame = getglobal("MainTankDRFrame")
        if RC5F_DRFrame then self:RegisterManagedPage("DR", RC5F_DRFrame) end
    end
end

function MT:ShowDRPage()
    RC5F_DRFrame = self:CreateDRWindow()
    if not RC5F_DRFrame then return end
    self:RegisterManagedPage("DR", RC5F_DRFrame)
    if RC5F_DRFrame.mainButton then
        RC5F_DRFrame.mainButton:SetText("MT Main")
        RC5F_DRFrame.mainButton:SetScript("OnClick", function() MT:ShowManagedPage("MAIN") end)
    end
    if RC5F_DRFrame.title then RC5F_DRFrame.title:SetText("Mitigation DR") end
    self:ShowManagedPage("DR", function(owner) owner:UpdateDRWindow() end)
end


-- ============================================================================
-- v1.0.0 RC6 - DR Attribution (reworked)
--
-- Vanilla-style target damage-taken ordering used here:
--   raw -> flat damage taken mod -> percent damage taken mod -> armor
--       -> block -> resist/absorb -> final damage
--
-- This follows the ordering used by vanilla emulation cores for melee damage:
-- target flat + percent damage-taken modifiers are applied before armor, then
-- block occurs after armor.  Project Legacy-specific DR talents are detected by
-- RC5 and are folded into the flat/percent stages.  Blessing of Sanctuary is
-- treated as all-damage flat DR on Project Legacy, per live testing.
--
-- Critical safety rules:
--   * Flat DR is NEVER more than its nominal per-event cap.
--   * A saturated low hit is never reconstructed below 1 damage.
--   * Dodge/parry/miss are pure avoidance: their entire hypothetical RAW hit
--     belongs to Avoidance and receives no Armor/DR credit.
--   * Full block/full resist are landed terminal outcomes. Earlier mitigation
--     layers keep their real share; the terminal outcome consumes the remainder.
--   * Existing observed block/resist/absorb values are never altered.
--   * For every landed event, Raw ~= Taken + Flat + %DR + Armor + Block
--     + Resist + Absorb (rounding tolerance only).
-- ============================================================================

RC6_BaseBuildDamageEvent = MT.BuildDamageEvent
RC6_BaseBuildAvoidanceEvent = MT.BuildAvoidanceEvent
RC6_BaseGetDisplayData = MT.GetDisplayData
RC6_BaseGetTimelineDetails = MT.GetTimelineDetails
RC6_BaseShowTimelineTooltip = MT.ShowTimelineTooltip
RC6_BaseGetPieData = MT.GetPieData
RC6_BaseEventMatchesDetailsFilter = MT.EventMatchesDetailsFilter
RC6_BaseFormatEventOutcome = MT.FormatEventOutcome
RC6_BaseFormatEventInspector = MT.FormatEventInspector
RC6_BaseBuildTankSummaryFromFight = MT.BuildTankSummaryFromFight
RC6_BaseBuildTankSummaryFromDisplay = MT.BuildTankSummaryFromDisplay

function RC6_ContextForEvent(eventData)
    if not eventData then return nil end
    if eventData.contextID and MT.mitigationContexts then
        return MT.mitigationContexts[eventData.contextID]
    end
    return MT.rc5ActiveContext
end

function RC6_GetDRTotals(context, school)
    if not context or not RC5B_EffectTotals then return 0, 0 end
    local totals = RC5B_EffectTotals(context)
    local pct = tonumber(totals.allPct) or 0
    if school == "Physical" then
        pct = pct + (tonumber(totals.physicalPct) or 0)
    else
        pct = pct + (tonumber(totals.spellPct) or 0)
    end
    if pct < 0 then pct = 0 end
    -- Keep a little numerical headroom for inverse reconstruction.
    if pct > 95 then pct = 95 end
    local flat = tonumber(totals.flat) or 0
    if flat < 0 then flat = 0 end
    return pct, flat
end

function RC6_RestoreLegacyBase(eventData)
    if not eventData then return end
    -- RC6 first-pass builds saved the pre-RC6 raw value here.  Restoring it
    -- lets this corrected math safely reprocess already-recorded RC6 fights.
    if eventData.rc6BaseRaw then
        local base = tonumber(eventData.rc6BaseRaw) or tonumber(eventData.raw) or 0
        eventData.raw = base
        if (eventData.school or "Physical") == "Physical" then
            eventData.physicalRaw = base
            eventData.magicRaw = 0
        else
            eventData.magicRaw = base
            eventData.physicalRaw = 0
        end
    end
    eventData.rc6Attributed = nil
    eventData.rc6MathVersion = nil
    eventData.flatDR = 0
    eventData.physicalDR = 0
    eventData.magicDR = 0
end

function RC6_GetArmorRateFromBaseEvent(eventData, baseRaw)
    if not eventData or (eventData.school or "Physical") ~= "Physical" then return 0 end
    local armor = tonumber(eventData.armor) or 0
    baseRaw = tonumber(baseRaw) or 0
    if baseRaw <= 0 or armor <= 0 then return 0 end
    local rate = armor / baseRaw
    if rate < 0 then rate = 0 end
    if rate > 0.75 then rate = 0.75 end
    return rate
end

function RC6_GetWhiteSwingRawHint(eventData)
    if not eventData or (eventData.school or "Physical") ~= "Physical" or eventData.ability ~= "Melee" then
        return nil, nil, nil
    end
    local memory = MT.targetDamageMemory and MT.targetDamageMemory[eventData.source]
    if not memory or not memory.minHit or not memory.maxHit then return nil, nil, nil end
    local low = tonumber(memory.minHit) or 0
    local high = tonumber(memory.maxHit) or 0
    if low <= 0 or high < low then return nil, nil, nil end
    return (low + high) / 2, low, high
end

function RC6_IsLandedDamageEvent(eventData)
    if not eventData or eventData.kind ~= "DAMAGE" then return false end
    if eventData.environmental then return false end
    local observed = (tonumber(eventData.taken) or 0) + (tonumber(eventData.block) or 0) +
        (tonumber(eventData.resist) or 0) + (tonumber(eventData.absorb) or 0)
    return observed > 0
end

function RC6_EnsureEventAttribution(eventData)
    if not eventData then return eventData end
    -- LAYEREDSTOP3 safety: this first-generation RC6 helper predates outcome-aware
    -- attribution.  Old RC6q/summary/display code can still call it indirectly.
    -- Never let it restore base RAW / zero DR on an already-finalized outcome.
    if tonumber(eventData.layeredOutcomeVersion) then return eventData end
    if eventData.rc6MathVersion == 2 then return eventData end

    -- Undo the earlier RC6 pass if this event came from that build.
    if eventData.rc6BaseRaw then RC6_RestoreLegacyBase(eventData) end

    eventData.flatDR = 0
    eventData.physicalDR = 0
    eventData.magicDR = 0
    eventData.drEstimated = false
    eventData.drSaturated = false
    eventData.drMathNote = nil

    -- Avoided/full-block/full-resist outcomes do not receive DR slices.  This
    -- prevents double crediting a hit that never actually landed.
    if not RC6_IsLandedDamageEvent(eventData) then
        eventData.rc6BaseRaw = tonumber(eventData.raw) or 0
        eventData.rc6MathVersion = 2
        return eventData
    end

    local context = RC6_ContextForEvent(eventData)
    if not context then
        eventData.rc6BaseRaw = tonumber(eventData.raw) or 0
        eventData.rc6MathVersion = 2
        return eventData
    end

    local school = eventData.school or "Physical"
    local pct, flatCap = RC6_GetDRTotals(context, school)
    if pct <= 0 and flatCap <= 0 then
        eventData.rc6BaseRaw = tonumber(eventData.raw) or 0
        eventData.rc6MathVersion = 2
        return eventData
    end

    local taken = tonumber(eventData.taken) or 0
    local blocked = tonumber(eventData.block) or 0
    local resisted = tonumber(eventData.resist) or 0
    local absorbed = tonumber(eventData.absorb) or 0
    local afterArmorObserved = taken + blocked + resisted + absorbed
    if afterArmorObserved < 0 then afterArmorObserved = 0 end

    local baseRaw = tonumber(eventData.raw) or 0
    eventData.rc6BaseRaw = baseRaw
    local armorRate = RC6_GetArmorRateFromBaseEvent(eventData, baseRaw)
    local pctRate = pct / 100
    local pctFactor = 1 - pctRate
    if pctFactor < 0.05 then pctFactor = 0.05 end

    -- A one-damage white swing with no later mitigation is the ambiguous
    -- saturation case.  UnitDamage(target) is our best independent raw hint.
    -- If the mob's raw swing is below the flat cap, Sanctuary can only remove
    -- raw-1, never the full cap.  Once the hit is floored to 1, later percent
    -- DR and armor cannot be meaningfully attributed from the client log.
    local rawHint, rawLow, rawHigh = RC6_GetWhiteSwingRawHint(eventData)
    if flatCap > 0 and taken <= 1 and blocked <= 0 and resisted <= 0 and absorbed <= 0 and rawHint and rawHint > 0 then
        local hinted = rawHint
        if rawLow and hinted < rawLow then hinted = rawLow end
        if rawHigh and hinted > rawHigh then hinted = rawHigh end
        local flatUsed = flatCap
        if hinted - 1 < flatUsed then flatUsed = hinted - 1 end
        if flatUsed < 0 then flatUsed = 0 end

        eventData.flatDR = flatUsed
        eventData.physicalDR = 0
        eventData.magicDR = 0
        eventData.armor = 0
        eventData.raw = taken + flatUsed
        eventData.physicalRaw = eventData.raw
        eventData.magicRaw = 0
        eventData.drEstimated = flatUsed > 0
        eventData.drSaturated = true
        eventData.drMathNote = "1-damage floor; raw estimated from UnitDamage(target)"
        eventData.rc6MathVersion = 2
        return eventData
    end

    -- Reverse the known downstream layers.  Block/resist/absorb are observed,
    -- so adding them back yields damage at the output of armor/DR.
    local afterPct = afterArmorObserved
    local armorStopped = 0
    if school == "Physical" and armorRate > 0 and armorRate < 0.999 then
        afterPct = afterArmorObserved / (1 - armorRate)
        armorStopped = afterPct - afterArmorObserved
        if armorStopped < 0 then armorStopped = 0 end
    end

    -- Vanilla target-taken math applies flat first, then percent.  Reverse the
    -- percentage multiplier to recover the damage immediately after flat DR.
    local afterFlat = afterPct
    local pctStopped = 0
    if pct > 0 then
        afterFlat = afterPct / pctFactor
        pctStopped = afterFlat - afterPct
        if pctStopped < 0 then pctStopped = 0 end
    end

    local flatUsed = flatCap
    if flatUsed < 0 then flatUsed = 0 end

    -- If an independent melee raw range proves that full Flat DR would require
    -- an impossible raw swing, cap the flat attribution to the range instead
    -- of inventing damage.  This is most relevant for very low-level mobs.
    if flatUsed > 0 and rawHint and rawHigh then
        local fullCandidate = afterFlat + flatUsed
        if fullCandidate > rawHigh + 1 then
            local boundedRaw = rawHint
            if boundedRaw < afterFlat then boundedRaw = afterFlat end
            if boundedRaw > rawHigh then boundedRaw = rawHigh end
            flatUsed = boundedRaw - afterFlat
            if flatUsed < 0 then flatUsed = 0 end
            if flatUsed > flatCap then flatUsed = flatCap end
            eventData.drMathNote = "Flat DR bounded by UnitDamage(target) swing range"
        end
    end

    local reconstructedRaw = afterFlat + flatUsed
    if reconstructedRaw < 1 then reconstructedRaw = 1 end

    -- Keep additive accounting exact.  Recompute armor from the reconstructed
    -- stages rather than trusting rounded historical differences.
    eventData.armor = armorStopped
    eventData.flatDR = flatUsed
    if school == "Physical" then
        eventData.physicalDR = pctStopped
        eventData.magicDR = 0
        eventData.physicalRaw = reconstructedRaw
        eventData.magicRaw = 0
    else
        eventData.magicDR = pctStopped
        eventData.physicalDR = 0
        eventData.magicRaw = reconstructedRaw
        eventData.physicalRaw = 0
    end
    eventData.raw = reconstructedRaw
    eventData.drEstimated = (flatUsed + pctStopped) > 0
    eventData.rc6MathVersion = 2
    return eventData
end

function MT:BuildDamageEvent(mob, attack, amountTaken, blocked, resisted, absorbed, school, isCrit, hitType, ignoreArmor)
    local eventData = RC6_BaseBuildDamageEvent(self, mob, attack, amountTaken, blocked, resisted, absorbed, school, isCrit, hitType, ignoreArmor)
    return RC6B_EnsureEventAttribution(eventData)
end

function MT:BuildAvoidanceEvent(kind, mob, attack, postArmorAmount, school)
    local eventData = RC6_BaseBuildAvoidanceEvent(self, kind, mob, attack, postArmorAmount, school)
    eventData.flatDR = 0
    eventData.physicalDR = 0
    eventData.magicDR = 0
    eventData.rc6BaseRaw = tonumber(eventData.raw) or 0
    eventData.rc6MathVersion = 2
    return eventData
end

function RC6_SumEventDR(events)
    local sums = {flat=0, physical=0, magic=0, physicalFlat=0, magicFlat=0, added=0, physicalAdded=0, magicAdded=0}
    local i, e, flat, phys, magic
    for i=1,table.getn(events or {}) do
        -- LAYEREDSTOP3: always use the final attribution gate.  RC6q still calls
        -- this legacy summation helper, and using the first-generation RC6 helper
        -- here could mutate FullBlock events after they had already been finalized.
        e = RC6B_EnsureEventAttribution(events[i])
        flat = tonumber(e.flatDR) or 0
        phys = tonumber(e.physicalDR) or 0
        magic = tonumber(e.magicDR) or 0
        sums.flat = sums.flat + flat
        sums.physical = sums.physical + phys
        sums.magic = sums.magic + magic
        sums.added = sums.added + flat + phys + magic
        if (e.school or "Physical") == "Physical" then
            sums.physicalFlat = sums.physicalFlat + flat
            sums.physicalAdded = sums.physicalAdded + flat + phys
        else
            sums.magicFlat = sums.magicFlat + flat
            sums.magicAdded = sums.magicAdded + flat + magic
        end
    end
    return sums
end

function MT:GetDisplayData()
    local base = RC6_BaseGetDisplayData(self)
    if not base then return base end
    local data = CopyTable(base)
    local sums = RC6_SumEventDR(self:GetDisplayEvents() or {})
    data.flatDR = sums.flat
    data.physicalDR = sums.physical
    data.magicDR = sums.magic
    data.rawIncoming = (tonumber(data.rawIncoming) or 0) + sums.added
    data.physicalRaw = (tonumber(data.physicalRaw) or 0) + sums.physicalAdded
    data.magicRaw = (tonumber(data.magicRaw) or 0) + sums.magicAdded
    return data
end

function MT:GetTimelineDetails(firstSecond, lastSecond)
    local d = RC6_BaseGetTimelineDetails(self, firstSecond, lastSecond)
    d.flatDR = 0; d.physicalDR = 0; d.magicDR = 0
    d.physicalFlatDR = 0; d.magicFlatDR = 0
    local events = self:GetDisplayEvents() or {}
    local i, e, sec
    for i=1,table.getn(events) do
        e = RC6B_EnsureEventAttribution(events[i])
        sec = floor(e.time or 0)
        if sec >= firstSecond and sec <= lastSecond then
            d.flatDR = d.flatDR + (e.flatDR or 0)
            d.physicalDR = d.physicalDR + (e.physicalDR or 0)
            d.magicDR = d.magicDR + (e.magicDR or 0)
            if (e.school or "Physical") == "Physical" then
                d.physicalFlatDR = d.physicalFlatDR + (e.flatDR or 0)
            else
                d.magicFlatDR = d.magicFlatDR + (e.flatDR or 0)
            end
        end
    end
    return d
end

function MT:ShowTimelineTooltip(owner, second, bucket)
    RC6_BaseShowTimelineTooltip(self, owner, second, bucket)
    if not bucket then return end
    local firstSecond = bucket.firstSecond or second or 0
    local lastSecond = bucket.lastSecond or firstSecond
    local d = self:GetTimelineDetails(firstSecond, lastSecond)
    local mode = self.timelineMode or "RAW"
    local tip = self:GetAnalysisTooltip()
    local flat = d.flatDR or 0
    local phys = d.physicalDR or 0
    local magic = d.magicDR or 0
    if mode == "PHYSICAL" then flat = d.physicalFlatDR or 0; magic = 0 end
    if mode == "MAGIC" then flat = d.magicFlatDR or 0; phys = 0 end
    if flat > 0 or phys > 0 or magic > 0 then
        tip:AddLine(" ")
        tip:AddLine("Estimated DR attribution", 1,0.82,0)
        if flat > 0 then tip:AddDoubleLine("Flat DR", self:FormatNumber(flat), 0.35,0.85,0.35, 1,1,1) end
        if phys > 0 then tip:AddDoubleLine("Physical DR", self:FormatNumber(phys), 0.35,0.85,0.35, 1,1,1) end
        if magic > 0 then tip:AddDoubleLine("Magic DR", self:FormatNumber(magic), 0.35,0.85,0.35, 1,1,1) end
        tip:Show()
    end
end

function RC6_AddPieEntry(entries, label, value, kind, rgb)
    value = tonumber(value) or 0
    if value <= 0 then return end
    table.insert(entries, {label=label, value=value, color=rgb, filterKind=kind, filterValue=label})
end

function MT:GetPieData(mode)
    local entries = RC6_BaseGetPieData(self, mode) or {}
    local sums = RC6_SumEventDR(self:GetDisplayEvents() or {})
    if mode == "PHYSICAL" then
        RC6_AddPieEntry(entries, "Flat DR", sums.physicalFlat, "FLAT_DR", {1.00,0.82,0.10})
        RC6_AddPieEntry(entries, "Physical DR", sums.physical, "PHYSICAL_DR", {1.00,0.38,0.08})
    elseif mode == "MAGIC" then
        RC6_AddPieEntry(entries, "Flat DR", sums.magicFlat, "FLAT_DR", {1.00,0.82,0.10})
        RC6_AddPieEntry(entries, "Magic DR", sums.magic, "MAGIC_DR", {0.72,0.30,1.00})
    else
        RC6_AddPieEntry(entries, "Flat DR", sums.flat, "FLAT_DR", {1.00,0.82,0.10})
        RC6_AddPieEntry(entries, "Physical DR", sums.physical, "PHYSICAL_DR", {1.00,0.38,0.08})
        RC6_AddPieEntry(entries, "Magic DR", sums.magic, "MAGIC_DR", {0.72,0.30,1.00})
    end
    return entries
end

function MT:EventMatchesDetailsFilter(event)
    local filter = self.detailsFilter
    if filter and filter.kind == "FLAT_DR" then return (event.flatDR or 0) > 0 end
    if filter and filter.kind == "PHYSICAL_DR" then return (event.physicalDR or 0) > 0 end
    if filter and filter.kind == "MAGIC_DR" then return (event.magicDR or 0) > 0 end
    return RC6_BaseEventMatchesDetailsFilter(self, event)
end

function MT:FormatEventOutcome(event)
    RC6B_EnsureEventAttribution(event)
    local text = RC6_BaseFormatEventOutcome(self, event)
    if (event.flatDR or 0) > 0 then text = text .. "  Flat DR " .. self:FormatNumber(event.flatDR) end
    if (event.physicalDR or 0) > 0 then text = text .. "  Physical DR " .. self:FormatNumber(event.physicalDR) end
    if (event.magicDR or 0) > 0 then text = text .. "  Magic DR " .. self:FormatNumber(event.magicDR) end
    return text
end

function MT:FormatEventInspector(event)
    if not event then return RC6_BaseFormatEventInspector(self, event) end
    RC6B_EnsureEventAttribution(event)
    local text = RC6_BaseFormatEventInspector(self, event)
    if (event.flatDR or 0) > 0 or (event.physicalDR or 0) > 0 or (event.magicDR or 0) > 0 then
        text = text .. "\nDR(est.) Flat " .. self:FormatNumber(event.flatDR or 0) ..
            "   Physical " .. self:FormatNumber(event.physicalDR or 0) ..
            "   Magic " .. self:FormatNumber(event.magicDR or 0)
        if event.drSaturated then text = text .. "\nFlat DR capped by 1-damage floor" end
        if event.drMathNote then text = text .. "\n" .. event.drMathNote end
    end
    return text
end

function MT:BuildTankSummaryFromFight(fight)
    local summary = RC6_BaseBuildTankSummaryFromFight(self, fight)
    if not summary or not fight then return summary end
    local sums = RC6_SumEventDR(fight.events or {})
    summary.raw = (summary.raw or 0) + sums.added
    summary.stopped = (summary.stopped or 0) + sums.added
    summary.physical = (summary.physical or 0) + sums.physicalAdded
    summary.magic = (summary.magic or 0) + sums.magicAdded
    summary.flatDR = sums.flat
    summary.physicalDR = sums.physical
    summary.magicDR = sums.magic
    return summary
end

function MT:BuildTankSummaryFromDisplay()
    local summary = RC6_BaseBuildTankSummaryFromDisplay(self)
    if not summary then return summary end
    local sums = RC6_SumEventDR(self:GetDisplayEvents() or {})
    summary.flatDR = sums.flat
    summary.physicalDR = sums.physical
    summary.magicDR = sums.magic
    return summary
end


-- ============================================================================
-- v1.0.0 RC6c - Crit-aware constrained DR attribution
--
-- Goals:
--   * Use the mob's live UnitDamage(target) range as the strongest white-swing
--     anchor whenever available.
--   * Never invent a normal white swing outside that observed range just to
--     make mitigation formulas balance.
--   * Treat Flat DR as a per-event CAP, not an automatic amount spent.
--   * Respect Project Legacy's observed 1-damage landed-hit floor.
--   * Stack separate percentage damage-taken effects multiplicatively, matching
--     vanilla core behavior (0.85 * 0.85, not 1 - 0.30).
--   * Make event records authoritative for RAW/Taken/Stopped, pie, timeline and
--     tank summaries so every view uses the same math.
-- ============================================================================

function RC6B_GetDRModel(context, school)
    RC6B_Model = {flatCap=0, pctFactor=1, listedPct=0, effectCount=0}
    if not context then return RC6B_Model end
    RC6B_Lists = {context.buffs or {}, context.talents or {}, context.equipment or {}}
    RC6B_Li = 1
    while RC6B_Li <= table.getn(RC6B_Lists) do
        RC6B_I = 1
        while RC6B_I <= table.getn(RC6B_Lists[RC6B_Li]) do
            RC6B_E = RC6B_Lists[RC6B_Li][RC6B_I]
            if RC6B_E and RC6B_E.value then
                RC6B_V = tonumber(RC6B_E.value) or 0
                if RC6B_E.kind == "flatDR" and RC6B_V > 0 then
                    RC6B_Model.flatCap = RC6B_Model.flatCap + RC6B_V
                elseif RC6B_E.kind == "percentDR" and RC6B_V > 0 then
                    if RC6B_V > 95 then RC6B_V = 95 end
                    RC6B_Model.listedPct = RC6B_Model.listedPct + RC6B_V
                    RC6B_Model.pctFactor = RC6B_Model.pctFactor * (1 - (RC6B_V / 100))
                    RC6B_Model.effectCount = RC6B_Model.effectCount + 1
                elseif school == "Physical" and RC6B_E.kind == "physicalDR" and RC6B_V > 0 then
                    if RC6B_V > 95 then RC6B_V = 95 end
                    RC6B_Model.listedPct = RC6B_Model.listedPct + RC6B_V
                    RC6B_Model.pctFactor = RC6B_Model.pctFactor * (1 - (RC6B_V / 100))
                    RC6B_Model.effectCount = RC6B_Model.effectCount + 1
                elseif school ~= "Physical" and RC6B_E.kind == "spellDR" and RC6B_V > 0 then
                    if RC6B_V > 95 then RC6B_V = 95 end
                    RC6B_Model.listedPct = RC6B_Model.listedPct + RC6B_V
                    RC6B_Model.pctFactor = RC6B_Model.pctFactor * (1 - (RC6B_V / 100))
                    RC6B_Model.effectCount = RC6B_Model.effectCount + 1
                end
            end
            RC6B_I = RC6B_I + 1
        end
        RC6B_Li = RC6B_Li + 1
    end
    if RC6B_Model.pctFactor < 0.01 then RC6B_Model.pctFactor = 0.01 end
    if RC6B_Model.pctFactor > 1 then RC6B_Model.pctFactor = 1 end
    RC6B_Model.effectivePct = (1 - RC6B_Model.pctFactor) * 100
    return RC6B_Model
end

function RC6B_SnapshotWhiteSwingRange(eventData)
    if not eventData or (eventData.school or "Physical") ~= "Physical" or eventData.ability ~= "Melee" then return end
    RC6B_Memory = MT.targetDamageMemory and MT.targetDamageMemory[eventData.source]
    if not RC6B_Memory then return end
    RC6B_Low = tonumber(RC6B_Memory.minHit) or 0
    RC6B_High = tonumber(RC6B_Memory.maxHit) or 0
    if RC6B_Low > 0 and RC6B_High >= RC6B_Low then
        eventData.rawHintLow = RC6B_Low
        eventData.rawHintHigh = RC6B_High
        eventData.rawHintAverage = (RC6B_Low + RC6B_High) / 2
        eventData.rawHintSource = RC6B_Memory.source or "UnitDamage(target)"
    end
end

function RC6B_GetWhiteSwingRange(eventData)
    if not eventData or (eventData.school or "Physical") ~= "Physical" or eventData.ability ~= "Melee" then return nil,nil,nil end
    -- Critical/crushing white swings keep the base UnitDamage snapshot for
    -- diagnostics/sample separation, but are deliberately NOT hard-clamped to
    -- a multiplied range. Live Project Legacy testing showed that the hidden
    -- ordering of Flat DR vs critical multiplication cannot be inferred safely
    -- from the client combat log while preserving Flat DR's per-event cap.
    if eventData.critical or eventData.crushing then return nil,nil,nil end
    RC6B_Low = tonumber(eventData.rawHintLow)
    RC6B_High = tonumber(eventData.rawHintHigh)
    RC6B_Avg = tonumber(eventData.rawHintAverage)
    if RC6B_Low and RC6B_High and RC6B_Low > 0 and RC6B_High >= RC6B_Low then
        if not RC6B_Avg then RC6B_Avg = (RC6B_Low + RC6B_High) / 2 end
        return RC6B_Avg, RC6B_Low, RC6B_High
    end
    RC6B_Memory = MT.targetDamageMemory and MT.targetDamageMemory[eventData.source]
    if not RC6B_Memory then return nil,nil,nil end
    RC6B_Low = tonumber(RC6B_Memory.minHit) or 0
    RC6B_High = tonumber(RC6B_Memory.maxHit) or 0
    if RC6B_Low <= 0 or RC6B_High < RC6B_Low then return nil,nil,nil end
    return (RC6B_Low + RC6B_High) / 2, RC6B_Low, RC6B_High
end

function RC6B_GetArmorRate(eventData)
    if not eventData or (eventData.school or "Physical") ~= "Physical" then return 0 end
    RC6B_Rate = tonumber(eventData.rc6ArmorRate)
    if RC6B_Rate then
        if RC6B_Rate < 0 then RC6B_Rate = 0 end
        if RC6B_Rate > 0.75 then RC6B_Rate = 0.75 end
        return RC6B_Rate
    end
    RC6B_BaseRaw = tonumber(eventData.rc6BaseRaw) or tonumber(eventData.raw) or 0
    RC6B_BaseArmor = tonumber(eventData.armor) or 0
    if RC6B_BaseRaw > 0 and RC6B_BaseArmor > 0 then
        RC6B_Rate = RC6B_BaseArmor / RC6B_BaseRaw
        if RC6B_Rate < 0 then RC6B_Rate = 0 end
        if RC6B_Rate > 0.75 then RC6B_Rate = 0.75 end
        return RC6B_Rate
    end
    return 0
end

function RC6B_ResetAttribution(eventData)
    if not eventData then return end
    if eventData.rc6BaseRaw then
        RC6_RestoreLegacyBase(eventData)
    end
    eventData.flatDR = 0
    eventData.physicalDR = 0
    eventData.magicDR = 0
    eventData.drEstimated = false
    eventData.drSaturated = false
    eventData.drMathNote = nil
    eventData.drRawAnchor = nil
    eventData.drPctEffective = 0
    eventData.drPctListed = 0
end

function RC6B_EnsureEventAttribution(eventData)
    if not eventData then return eventData end
    if eventData.rc6MathVersion == 4 then return eventData end

    RC6B_ResetAttribution(eventData)
    eventData.rc6BaseRaw = tonumber(eventData.raw) or 0

    if eventData.kind ~= "DAMAGE" or eventData.environmental then
        eventData.flatDR = 0; eventData.physicalDR = 0; eventData.magicDR = 0
        eventData.rc6MathVersion = 4
        return eventData
    end

    RC6B_Context = RC6_ContextForEvent(eventData)
    if not RC6B_Context then
        eventData.rc6MathVersion = 4
        return eventData
    end

    RC6B_School = eventData.school or "Physical"
    RC6B_Model = RC6B_GetDRModel(RC6B_Context, RC6B_School)
    eventData.drPctEffective = RC6B_Model.effectivePct or 0
    eventData.drPctListed = RC6B_Model.listedPct or 0

    -- Normal white swings should still be constrained by UnitDamage even when
    -- the player has no Flat/% DR. This fixes edge rounding cases such as a
    -- known 72-93 swing being reverse-reported as Raw 71 after armor.
    RC6B_Hint, RC6B_Low, RC6B_High = RC6B_GetWhiteSwingRange(eventData)
    RC6B_HasDR = ((RC6B_Model.flatCap or 0) > 0 or (RC6B_Model.effectivePct or 0) > 0)
    if not RC6B_HasDR and not RC6B_Hint then
        eventData.rc6MathVersion = 4
        return eventData
    end

    RC6B_Taken = tonumber(eventData.taken) or 0
    RC6B_Block = tonumber(eventData.block) or 0
    RC6B_Resist = tonumber(eventData.resist) or 0
    RC6B_Absorb = tonumber(eventData.absorb) or 0
    RC6B_Downstream = RC6B_Taken + RC6B_Block + RC6B_Resist + RC6B_Absorb
    if RC6B_Downstream < 0 then RC6B_Downstream = 0 end

    RC6B_ArmorRate = RC6B_GetArmorRate(eventData)
    RC6B_PctFactor = tonumber(RC6B_Model.pctFactor) or 1
    if RC6B_PctFactor < 0.01 then RC6B_PctFactor = 0.01 end
    RC6B_FlatCap = tonumber(RC6B_Model.flatCap) or 0
    if RC6B_FlatCap < 0 then RC6B_FlatCap = 0 end


    -- Special saturation case proven by live Project Legacy testing: a landed
    -- white swing whose raw range is entirely below Flat DR still lands for 1.
    -- Flat DR spends raw-1, and later %DR/armor receive no attribution.
    if RC6B_FlatCap > 0 and RC6B_Taken <= 1 and RC6B_Block <= 0 and RC6B_Resist <= 0 and RC6B_Absorb <= 0 and
       RC6B_Hint and RC6B_High and RC6B_High <= (RC6B_FlatCap + 1) then
        RC6B_Raw = RC6B_Hint
        if RC6B_Raw < 1 then RC6B_Raw = 1 end
        RC6B_FlatUsed = RC6B_Raw - 1
        if RC6B_FlatUsed < 0 then RC6B_FlatUsed = 0 end
        if RC6B_FlatUsed > RC6B_FlatCap then RC6B_FlatUsed = RC6B_FlatCap end
        eventData.raw = RC6B_Taken + RC6B_FlatUsed
        if eventData.raw < 1 then eventData.raw = 1 end
        eventData.flatDR = RC6B_FlatUsed
        eventData.physicalDR = 0
        eventData.magicDR = 0
        eventData.armor = 0
        eventData.physicalRaw = eventData.raw
        eventData.magicRaw = 0
        eventData.drEstimated = RC6B_FlatUsed > 0
        eventData.drSaturated = true
        eventData.drRawAnchor = "UnitDamage " .. tostring(Round(RC6B_Low)) .. "-" .. tostring(Round(RC6B_High))
        eventData.drMathNote = "Flat DR saturated the landed hit at 1"
        eventData.rc6MathVersion = 4
        return eventData
    end

    -- Reverse the passive layers to get the raw roll that best explains the
    -- observed post-armor/pre-block amount. Then clamp normal white swings to
    -- the independently observed UnitDamage range.
    RC6B_ArmorFactor = 1 - RC6B_ArmorRate
    if RC6B_ArmorFactor < 0.25 then RC6B_ArmorFactor = 0.25 end
    RC6B_CandidateAfterFlat = RC6B_Downstream / RC6B_ArmorFactor / RC6B_PctFactor
    RC6B_CandidateRaw = RC6B_CandidateAfterFlat + RC6B_FlatCap
    if RC6B_CandidateRaw < RC6B_Downstream then RC6B_CandidateRaw = RC6B_Downstream end

    if RC6B_Hint and RC6B_Low and RC6B_High then
        RC6B_Raw = RC6B_CandidateRaw
        if RC6B_Raw < RC6B_Low then RC6B_Raw = RC6B_Low end
        if RC6B_Raw > RC6B_High then RC6B_Raw = RC6B_High end
        if RC6B_Raw < RC6B_Downstream then RC6B_Raw = RC6B_Downstream end
        eventData.drRawAnchor = "UnitDamage " .. tostring(Round(RC6B_Low)) .. "-" .. tostring(Round(RC6B_High))
        if RC6B_CandidateRaw < RC6B_Low - 0.5 or RC6B_CandidateRaw > RC6B_High + 0.5 then
            eventData.drMathNote = "Inverse result clamped to observed white-swing range"
        end
    else
        RC6B_Raw = RC6B_CandidateRaw
        eventData.drRawAnchor = "inverse estimate"
    end

    if RC6B_Raw < 1 then RC6B_Raw = 1 end

    -- Spend Flat DR first, but never spend enough to push its stage below 1.
    RC6B_MaxFlatUsable = RC6B_Raw - 1
    if RC6B_MaxFlatUsable < 0 then RC6B_MaxFlatUsable = 0 end
    RC6B_FlatUsed = RC6B_FlatCap
    if RC6B_FlatUsed > RC6B_MaxFlatUsable then RC6B_FlatUsed = RC6B_MaxFlatUsable end
    RC6B_AfterFlat = RC6B_Raw - RC6B_FlatUsed

    -- If Flat DR alone reaches the 1-damage floor, do not manufacture later
    -- armor/%DR credit. This is the key low-mob constraint.
    if RC6B_AfterFlat <= 1.0001 and RC6B_Downstream <= 1.0001 and RC6B_Block <= 0 and RC6B_Resist <= 0 and RC6B_Absorb <= 0 then
        eventData.raw = RC6B_Raw
        eventData.flatDR = RC6B_Raw - RC6B_Taken
        if eventData.flatDR < 0 then eventData.flatDR = 0 end
        if eventData.flatDR > RC6B_FlatCap then eventData.flatDR = RC6B_FlatCap end
        eventData.physicalDR = 0; eventData.magicDR = 0; eventData.armor = 0
        if RC6B_School == "Physical" then eventData.physicalRaw = RC6B_Raw; eventData.magicRaw = 0
        else eventData.magicRaw = RC6B_Raw; eventData.physicalRaw = 0 end
        eventData.drEstimated = eventData.flatDR > 0
        eventData.drSaturated = true
        eventData.drMathNote = eventData.drMathNote or "Flat DR reached the 1-damage floor before later layers"
        eventData.rc6MathVersion = 4
        return eventData
    end

    -- Allocate the remaining pre-block mitigation budget between %DR and armor
    -- in the same proportions predicted by the forward vanilla ordering. This
    -- preserves the observed/raw anchor exactly even when server integer
    -- rounding differs by a point from the floating-point model.
    RC6B_PassiveBudget = RC6B_AfterFlat - RC6B_Downstream
    if RC6B_PassiveBudget < 0 then
        -- RC6d: a live UnitDamage range is a HARD constraint for a normal white
        -- swing.  Never inflate a known 39-48 swing into 60+ merely because an
        -- incorrectly-large/unknown Flat DR cap was present.  Reduce Flat DR
        -- first; only inverse-only events are allowed to raise raw to reconcile.
        if RC6B_Hint and RC6B_Low and RC6B_High then
            RC6B_FlatUsed = RC6B_Raw - RC6B_Downstream
            if RC6B_FlatUsed < 0 then RC6B_FlatUsed = 0 end
            if RC6B_FlatUsed > RC6B_FlatCap then RC6B_FlatUsed = RC6B_FlatCap end
            RC6B_AfterFlat = RC6B_Raw - RC6B_FlatUsed
            RC6B_PassiveBudget = RC6B_AfterFlat - RC6B_Downstream
            if RC6B_PassiveBudget < 0 then RC6B_PassiveBudget = 0 end
            eventData.drMathNote = "Flat DR reduced to preserve observed white-swing range"
        else
            RC6B_Raw = RC6B_Raw - RC6B_PassiveBudget
            RC6B_AfterFlat = RC6B_Raw - RC6B_FlatUsed
            RC6B_PassiveBudget = 0
            eventData.drMathNote = "Observed damage exceeded inverse raw estimate; raw raised to reconcile"
        end
    end

    RC6B_TheoPct = RC6B_AfterFlat * (1 - RC6B_PctFactor)
    RC6B_AfterPct = RC6B_AfterFlat * RC6B_PctFactor
    RC6B_TheoArmor = 0
    if RC6B_School == "Physical" then RC6B_TheoArmor = RC6B_AfterPct * RC6B_ArmorRate end
    RC6B_TheoTotal = RC6B_TheoPct + RC6B_TheoArmor

    RC6B_PctStopped = 0
    RC6B_ArmorStopped = 0
    if RC6B_PassiveBudget > 0 and RC6B_TheoTotal > 0 then
        RC6B_PctStopped = RC6B_PassiveBudget * (RC6B_TheoPct / RC6B_TheoTotal)
        RC6B_ArmorStopped = RC6B_PassiveBudget - RC6B_PctStopped
    elseif RC6B_PassiveBudget > 0 then
        if RC6B_School == "Physical" and RC6B_ArmorRate > 0 then RC6B_ArmorStopped = RC6B_PassiveBudget
        else RC6B_PctStopped = RC6B_PassiveBudget end
    end

    eventData.raw = RC6B_Raw
    eventData.flatDR = RC6B_FlatUsed
    eventData.armor = RC6B_ArmorStopped
    if RC6B_School == "Physical" then
        eventData.physicalDR = RC6B_PctStopped
        eventData.magicDR = 0
        eventData.physicalRaw = RC6B_Raw
        eventData.magicRaw = 0
    else
        eventData.magicDR = RC6B_PctStopped
        eventData.physicalDR = 0
        eventData.magicRaw = RC6B_Raw
        eventData.physicalRaw = 0
    end
    eventData.drEstimated = (RC6B_FlatUsed + RC6B_PctStopped) > 0
    eventData.rc6MathVersion = 4
    return eventData
end

-- Build new events with a snapshot of the mob raw white-swing range and the
-- armor reduction that existed at event time. Both are important because the
-- target, gear and debuffs can change before a saved fight is inspected.
function MT:BuildDamageEvent(mob, attack, amountTaken, blocked, resisted, absorbed, school, isCrit, hitType, ignoreArmor)
    RC6B_Event = RC6_BaseBuildDamageEvent(self, mob, attack, amountTaken, blocked, resisted, absorbed, school, isCrit, hitType, ignoreArmor)
    RC6B_ContextNow = self.rc5ActiveContext or self:CaptureMitigationContext(mob)
    if RC6B_ContextNow then RC6B_Event.contextID = RC6B_ContextNow.id end
    RC6B_SnapshotWhiteSwingRange(RC6B_Event)
    if (school or "Physical") == "Physical" and not ignoreArmor then
        RC6B_Reduction = GetArmorReduction(mob)
        RC6B_Event.rc6ArmorRate = RC6B_Reduction or 0
    else
        RC6B_Event.rc6ArmorRate = 0
    end
    RC6B_Event.rc6MathVersion = nil
    return RC6B_EnsureEventAttribution(RC6B_Event)
end

RC6B_PreviousBuildAvoidanceEvent = MT.BuildAvoidanceEvent
function MT:BuildAvoidanceEvent(kind, mob, attack, postArmorAmount, school)
    RC6B_Event = RC6B_PreviousBuildAvoidanceEvent(self, kind, mob, attack, postArmorAmount, school)
    RC6B_SnapshotWhiteSwingRange(RC6B_Event)

    -- LAYEREDSTOP1 snapshots the exact event-time inputs needed to explain a
    -- terminal Full Block/Full Resist after reload without consulting current
    -- gear, armor, target or buffs.  For matching-context estimates this value
    -- is the estimated amount immediately before the terminal outcome.
    RC6B_Event.rc6PreOutcomeEstimate = tonumber(postArmorAmount) or 0
    if (school or "Physical") == "Physical" then
        RC6B_Reduction = GetArmorReduction(mob)
        RC6B_Event.rc6ArmorRate = RC6B_Reduction or 0
    else
        RC6B_Event.rc6ArmorRate = 0
    end
    if kind == "FullBlock" and E.GetBlockValueBreakdown then
        RC6B_BlockSnapshot = E.GetBlockValueBreakdown(self.data or {})
        RC6B_Event.rc6BlockValue = tonumber(RC6B_BlockSnapshot and RC6B_BlockSnapshot.baseValue) or 0
    end

    RC6B_Event.rc6MathVersion = 4
    RC6B_Event.flatDR = 0; RC6B_Event.physicalDR = 0; RC6B_Event.magicDR = 0
    return RC6B_Event
end

-- Authoritative event accumulator. The combat parser still maintains the old
-- aggregate structures for compatibility, but every visible RC6c total is now
-- rebuilt from the same event records used by Details and the inspector.
function RC6B_RebuildData(baseData, events)
    RC6B_Data = CopyTable(baseData or NewData())
    RC6B_Data.rawIncoming = 0; RC6B_Data.physicalRaw = 0; RC6B_Data.magicRaw = 0
    RC6B_Data.damageTaken = 0; RC6B_Data.physicalTaken = 0; RC6B_Data.magicTaken = 0
    RC6B_Data.armorReduced = 0; RC6B_Data.blocked = 0; RC6B_Data.fullBlockedEstimated = 0
    RC6B_Data.physicalBlocked = 0; RC6B_Data.magicBlocked = 0
    RC6B_Data.physicalFullBlockedEstimated = 0; RC6B_Data.magicFullBlockedEstimated = 0
    RC6B_Data.absorbed = 0; RC6B_Data.resistedPartial = 0; RC6B_Data.resistedFullEstimated = 0
    RC6B_Data.dodgedEstimated = 0; RC6B_Data.parriedEstimated = 0; RC6B_Data.missedEstimated = 0
    RC6B_Data.flatDR = 0; RC6B_Data.physicalDR = 0; RC6B_Data.magicDR = 0
    RC6B_Data.physicalFlatDR = 0; RC6B_Data.magicFlatDR = 0
    RC6B_Data.physicalAbsorb = 0; RC6B_Data.magicAbsorb = 0

    RC6B_I = 1
    while RC6B_I <= table.getn(events or {}) do
        RC6B_E = RC6B_EnsureEventAttribution(events[RC6B_I])
        RC6B_Data.rawIncoming = RC6B_Data.rawIncoming + (tonumber(RC6B_E.raw) or 0)
        RC6B_Data.damageTaken = RC6B_Data.damageTaken + (tonumber(RC6B_E.taken) or 0)
        RC6B_Data.armorReduced = RC6B_Data.armorReduced + (tonumber(RC6B_E.armor) or 0)
        RC6B_Data.absorbed = RC6B_Data.absorbed + (tonumber(RC6B_E.absorb) or 0)
        RC6B_Data.flatDR = RC6B_Data.flatDR + (tonumber(RC6B_E.flatDR) or 0)
        RC6B_Data.physicalDR = RC6B_Data.physicalDR + (tonumber(RC6B_E.physicalDR) or 0)
        RC6B_Data.magicDR = RC6B_Data.magicDR + (tonumber(RC6B_E.magicDR) or 0)

        if (RC6B_E.school or "Physical") == "Physical" then
            RC6B_Data.physicalRaw = RC6B_Data.physicalRaw + (tonumber(RC6B_E.raw) or 0)
            RC6B_Data.physicalTaken = RC6B_Data.physicalTaken + (tonumber(RC6B_E.taken) or 0)
            RC6B_Data.physicalFlatDR = RC6B_Data.physicalFlatDR + (tonumber(RC6B_E.flatDR) or 0)
            RC6B_Data.physicalAbsorb = RC6B_Data.physicalAbsorb + (tonumber(RC6B_E.absorb) or 0)
        else
            RC6B_Data.magicRaw = RC6B_Data.magicRaw + (tonumber(RC6B_E.raw) or 0)
            RC6B_Data.magicTaken = RC6B_Data.magicTaken + (tonumber(RC6B_E.taken) or 0)
            RC6B_Data.magicFlatDR = RC6B_Data.magicFlatDR + (tonumber(RC6B_E.flatDR) or 0)
            RC6B_Data.magicAbsorb = RC6B_Data.magicAbsorb + (tonumber(RC6B_E.absorb) or 0)
        end

        if RC6B_E.kind == "Dodge" then
            RC6B_Data.dodgedEstimated = RC6B_Data.dodgedEstimated + (tonumber(RC6B_E.avoidance) or 0)
        elseif RC6B_E.kind == "Parry" then
            RC6B_Data.parriedEstimated = RC6B_Data.parriedEstimated + (tonumber(RC6B_E.avoidance) or 0)
        elseif RC6B_E.kind == "Miss" then
            RC6B_Data.missedEstimated = RC6B_Data.missedEstimated + (tonumber(RC6B_E.avoidance) or 0)
        elseif RC6B_E.kind == "FullBlock" then
            RC6B_BlockAmount = tonumber(RC6B_E.block) or 0
            RC6B_Data.fullBlockedEstimated = RC6B_Data.fullBlockedEstimated + RC6B_BlockAmount
            if (RC6B_E.school or "Physical") == "Physical" then
                RC6B_Data.physicalFullBlockedEstimated = RC6B_Data.physicalFullBlockedEstimated + RC6B_BlockAmount
            else
                RC6B_Data.magicFullBlockedEstimated = RC6B_Data.magicFullBlockedEstimated + RC6B_BlockAmount
            end
        elseif RC6B_E.kind == "FullResist" then
            RC6B_Data.resistedFullEstimated = RC6B_Data.resistedFullEstimated + (tonumber(RC6B_E.resist) or 0)
        else
            RC6B_BlockAmount = tonumber(RC6B_E.block) or 0
            RC6B_Data.blocked = RC6B_Data.blocked + RC6B_BlockAmount
            if (RC6B_E.school or "Physical") == "Physical" then
                RC6B_Data.physicalBlocked = RC6B_Data.physicalBlocked + RC6B_BlockAmount
            else
                RC6B_Data.magicBlocked = RC6B_Data.magicBlocked + RC6B_BlockAmount
            end
            RC6B_Data.resistedPartial = RC6B_Data.resistedPartial + (tonumber(RC6B_E.resist) or 0)
        end
        RC6B_I = RC6B_I + 1
    end
    return RC6B_Data
end

-- FINALAGG1: expose the authoritative RC6 event accumulator to the core
-- EndCombat boundary.  Live display has rebuilt from events for years, but the
-- legacy self.data accumulator does not know about Flat/Physical/Magic DR.
-- Finalized fight.data must therefore be built from the same attributed event
-- stream used by Pie, Timeline, Details, and the Inspector.
function MT:BuildFinalizedAggregateFromEvents(baseData, events)
    return RC6B_RebuildData(baseData or self.data or NewData(), events or self.events or {})
end

function MT:GetDisplayData()
    RC6B_BaseData = RC6_BaseGetDisplayData(self)
    RC6B_DisplayEvents = self:GetDisplayEvents() or {}
    if table.getn(RC6B_DisplayEvents) == 0 then return RC6B_BaseData end
    return RC6B_RebuildData(RC6B_BaseData, RC6B_DisplayEvents)
end

-- RAW Damage Stopped is deliberately derived from the invariant Raw - Taken.
-- This makes it impossible for the headline totals to disagree even if a new
-- server-specific mitigation mechanic has not yet received its own slice.
function MT:GetTotals(data)
    data = data or self:GetDisplayData() or self.data
    RC6B_Raw = tonumber(data.rawIncoming) or 0
    RC6B_Taken = tonumber(data.damageTaken) or 0
    RC6B_Stopped = RC6B_Raw - RC6B_Taken
    if RC6B_Stopped < 0 then RC6B_Stopped = 0 end
    return RC6B_Stopped, RC6B_Raw
end

-- Rebuild visual timeline buckets from attributed events so bar heights and
-- hover details cannot disagree with RAW/Details after an attribution change.
function MT:GetDisplayTimeline()
    RC6B_Root = {}
    RC6B_Events = self:GetDisplayEvents() or {}
    RC6B_I = 1
    while RC6B_I <= table.getn(RC6B_Events) do
        RC6B_E = RC6B_EnsureEventAttribution(RC6B_Events[RC6B_I])
        AddToTimelineBucket(RC6B_Root, RC6B_E)
        RC6B_I = RC6B_I + 1
    end
    return RC6B_Root
end

function MT:GetTimelineDetails(firstSecond, lastSecond)
    RC6B_Events = self:GetDisplayEvents() or {}
    RC6B_I = 1
    while RC6B_I <= table.getn(RC6B_Events) do
        RC6B_EnsureEventAttribution(RC6B_Events[RC6B_I])
        RC6B_I = RC6B_I + 1
    end
    RC6B_D = RC6_BaseGetTimelineDetails(self, firstSecond, lastSecond)
    RC6B_D.flatDR = 0; RC6B_D.physicalDR = 0; RC6B_D.magicDR = 0
    RC6B_D.physicalFlatDR = 0; RC6B_D.magicFlatDR = 0
    RC6B_I = 1
    while RC6B_I <= table.getn(RC6B_Events) do
        RC6B_E = RC6B_Events[RC6B_I]
        RC6B_Sec = floor(RC6B_E.time or 0)
        if RC6B_Sec >= firstSecond and RC6B_Sec <= lastSecond then
            RC6B_D.flatDR = RC6B_D.flatDR + (RC6B_E.flatDR or 0)
            RC6B_D.physicalDR = RC6B_D.physicalDR + (RC6B_E.physicalDR or 0)
            RC6B_D.magicDR = RC6B_D.magicDR + (RC6B_E.magicDR or 0)
            if (RC6B_E.school or "Physical") == "Physical" then
                RC6B_D.physicalFlatDR = RC6B_D.physicalFlatDR + (RC6B_E.flatDR or 0)
            else
                RC6B_D.magicFlatDR = RC6B_D.magicFlatDR + (RC6B_E.flatDR or 0)
            end
        end
        RC6B_I = RC6B_I + 1
    end
    return RC6B_D
end

-- Pie data is rebuilt from one authoritative display snapshot. This also adds
-- armor/absorbs to the specialized Physical/Magic pies so those pages explain
-- the complete stopped-damage budget instead of only avoidance/resistance.
function MT:GetPieData(mode)
    RC6B_Data = self:GetDisplayData() or NewData()
    RC6B_Entries = {}
    if mode == "PHYSICAL" then
        AddPieEntry(RC6B_Entries, "Armor", RC6B_Data.armorReduced, "ARMOR", "Armor")
        AddPieEntry(RC6B_Entries, "Flat DR", RC6B_Data.physicalFlatDR, "FLAT_DR", "Flat DR")
        AddPieEntry(RC6B_Entries, "Physical DR", RC6B_Data.physicalDR, "PHYSICAL_DR", "Physical DR")
        AddPieEntry(RC6B_Entries, "Dodge", RC6B_Data.dodgedEstimated, "KIND", "Dodge")
        AddPieEntry(RC6B_Entries, "Parry", RC6B_Data.parriedEstimated, "KIND", "Parry")
        AddPieEntry(RC6B_Entries, "Miss", RC6B_Data.missedEstimated, "KIND", "Miss")
        AddPieEntry(RC6B_Entries, "Full Block", RC6B_Data.physicalFullBlockedEstimated, "PHYSICAL_FULL_BLOCK", "FullBlock")
        AddPieEntry(RC6B_Entries, "Partial Block", RC6B_Data.physicalBlocked, "PHYSICAL_PARTIAL_BLOCK", "Partial Block")
        AddPieEntry(RC6B_Entries, "Absorbs", RC6B_Data.physicalAbsorb, "ABSORB", "Absorbs")
    elseif mode == "MAGIC" then
        AddPieEntry(RC6B_Entries, "Flat DR", RC6B_Data.magicFlatDR, "FLAT_DR", "Flat DR")
        AddPieEntry(RC6B_Entries, "Magic DR", RC6B_Data.magicDR, "MAGIC_DR", "Magic DR")
        AddPieEntry(RC6B_Entries, "Block", (RC6B_Data.magicBlocked or 0) + (RC6B_Data.magicFullBlockedEstimated or 0), "MAGIC_BLOCK", "Block")
        RC6B_Order = {"Holy", "Fire", "Nature", "Frost", "Shadow", "Arcane", "Unknown"}
        RC6B_I = 1
        while RC6B_I <= table.getn(RC6B_Order) do
            RC6B_SchoolName = RC6B_Order[RC6B_I]
            RC6B_Bucket = RC6B_Data.schools and RC6B_Data.schools[RC6B_SchoolName]
            if RC6B_Bucket then AddPieEntry(RC6B_Entries, RC6B_SchoolName, (RC6B_Bucket.partial or 0) + (RC6B_Bucket.fullEstimated or 0), "SCHOOL", RC6B_SchoolName) end
            RC6B_I = RC6B_I + 1
        end
        AddPieEntry(RC6B_Entries, "Absorbs", RC6B_Data.magicAbsorb, "ABSORB", "Absorbs")
    else
        AddPieEntry(RC6B_Entries, "Armor", RC6B_Data.armorReduced, "ARMOR", "Armor")
        AddPieEntry(RC6B_Entries, "Flat DR", RC6B_Data.flatDR, "FLAT_DR", "Flat DR")
        AddPieEntry(RC6B_Entries, "Physical DR", RC6B_Data.physicalDR, "PHYSICAL_DR", "Physical DR")
        AddPieEntry(RC6B_Entries, "Magic DR", RC6B_Data.magicDR, "MAGIC_DR", "Magic DR")
        AddPieEntry(RC6B_Entries, "Avoidance", (RC6B_Data.dodgedEstimated or 0)+(RC6B_Data.parriedEstimated or 0)+(RC6B_Data.missedEstimated or 0), "AVOIDANCE", "Avoidance")
        AddPieEntry(RC6B_Entries, "Blocks", (RC6B_Data.blocked or 0)+(RC6B_Data.fullBlockedEstimated or 0), "BLOCK", "Blocks")
        AddPieEntry(RC6B_Entries, "Resists", (RC6B_Data.resistedPartial or 0)+(RC6B_Data.resistedFullEstimated or 0), "RESIST", "Resists")
        AddPieEntry(RC6B_Entries, "Absorbs", RC6B_Data.absorbed, "ABSORB", "Absorbs")
    end
    return RC6B_Entries
end

-- Keep the main Physical summary honest about DR as well.
RC6B_PreviousUpdateDisplay = MT.UpdateDisplay
function MT:UpdateDisplay()
    RC6B_PreviousUpdateDisplay(self)
    if not self.frame or self.miniMode then return end
    RC6B_Data = self:GetDisplayData() or NewData()
    if (self.currentPage or "RAW") == "PHYSICAL" then
        RC6B_PhysPrevented = (RC6B_Data.armorReduced or 0) + (RC6B_Data.physicalFlatDR or 0) + (RC6B_Data.physicalDR or 0) +
            (RC6B_Data.dodgedEstimated or 0) + (RC6B_Data.parriedEstimated or 0) + (RC6B_Data.missedEstimated or 0) +
            (RC6B_Data.physicalBlocked or 0) + (RC6B_Data.physicalFullBlockedEstimated or 0) + (RC6B_Data.physicalAbsorb or 0)
        self:SetRow(6, "Physical Prevented", self:FormatNumber(RC6B_PhysPrevented))
    elseif (self.currentPage or "RAW") == "MAGIC" then
        RC6B_MagicPrevented = (RC6B_Data.magicFlatDR or 0) + (RC6B_Data.magicDR or 0) +
            (RC6B_Data.resistedPartial or 0) + (RC6B_Data.resistedFullEstimated or 0) + (RC6B_Data.magicBlocked or 0) + (RC6B_Data.magicFullBlockedEstimated or 0) + (RC6B_Data.magicAbsorb or 0)
        self:SetRow(5, "Magic Prevented", self:FormatNumber(RC6B_MagicPrevented))
        RC6B_MagicPct = 0
        if (RC6B_Data.magicRaw or 0) > 0 then RC6B_MagicPct = RC6B_MagicPrevented / RC6B_Data.magicRaw * 100 end
        self:SetRow(6, "Magic Mitigation", format("%.1f%%", RC6B_MagicPct))
    end
end

-- Replace the RC6 inspector text so it explains the anchor and effective
-- multiplicative DR without duplicating the old first-pass DR line.
function MT:FormatEventInspector(event)
    if not event then return RC6_BaseFormatEventInspector(self, event) end
    RC6B_EnsureEventAttribution(event)
    RC6B_Text = RC6_BaseFormatEventInspector(self, event)
    if (event.flatDR or 0) > 0 or (event.physicalDR or 0) > 0 or (event.magicDR or 0) > 0 then
        RC6B_Text = RC6B_Text .. "\nDR(est.) Flat " .. self:FormatNumber(event.flatDR or 0) ..
            "   Physical " .. self:FormatNumber(event.physicalDR or 0) ..
            "   Magic " .. self:FormatNumber(event.magicDR or 0)
        if (event.drPctEffective or 0) > 0 then
            RC6B_Text = RC6B_Text .. "\n%DR effective: " .. format("%.1f%%", event.drPctEffective or 0)
            if (event.drPctListed or 0) > (event.drPctEffective or 0) + 0.05 then
                RC6B_Text = RC6B_Text .. " (listed effects sum " .. format("%.1f%%", event.drPctListed or 0) .. ")"
            end
        end
        if event.drRawAnchor then RC6B_Text = RC6B_Text .. "\nRaw anchor: " .. event.drRawAnchor end
        if event.drSaturated then RC6B_Text = RC6B_Text .. "\nFlat DR capped by 1-damage floor" end
        if event.drMathNote then RC6B_Text = RC6B_Text .. "\n" .. event.drMathNote end
        RC6B_Check = (tonumber(event.taken) or 0)+(tonumber(event.flatDR) or 0)+(tonumber(event.physicalDR) or 0)+
            (tonumber(event.magicDR) or 0)+(tonumber(event.armor) or 0)+(tonumber(event.block) or 0)+
            (tonumber(event.resist) or 0)+(tonumber(event.absorb) or 0)
        RC6B_Text = RC6B_Text .. "\nCheck: " .. self:FormatNumber(event.raw or 0) .. " raw = " .. self:FormatNumber(RC6B_Check) .. " accounted"
    end
    return RC6B_Text
end

function MT:FormatEventOutcome(event)
    RC6B_EnsureEventAttribution(event)
    RC6B_Text = RC6_BaseFormatEventOutcome(self, event)
    if (event.flatDR or 0) > 0 then RC6B_Text = RC6B_Text .. "  Flat DR " .. self:FormatNumber(event.flatDR) end
    if (event.physicalDR or 0) > 0 then RC6B_Text = RC6B_Text .. "  Physical DR " .. self:FormatNumber(event.physicalDR) end
    if (event.magicDR or 0) > 0 then RC6B_Text = RC6B_Text .. "  Magic DR " .. self:FormatNumber(event.magicDR) end
    return RC6B_Text
end

function RC6B_BuildSummaryFromData(data, label, enemy, duration)
    if not data then return nil end
    RC6B_Stopped, RC6B_Raw = MT:GetTotals(data)
    if RC6B_Raw <= 0 then return nil end
    _, RC6B_Class = UnitClass("player")
    return {
        player = MT.playerName or UnitName("player") or "Unknown",
        class = RC6B_Class or "UNKNOWN",
        label = label or "Fight",
        enemy = enemy or "Unknown",
        duration = duration or 0,
        raw = RC6B_Raw,
        taken = data.damageTaken or 0,
        stopped = RC6B_Stopped,
        armor = data.armorReduced or 0,
        avoidance = (data.dodgedEstimated or 0)+(data.parriedEstimated or 0)+(data.missedEstimated or 0),
        block = (data.blocked or 0)+(data.fullBlockedEstimated or 0),
        resist = (data.resistedPartial or 0)+(data.resistedFullEstimated or 0),
        absorb = data.absorbed or 0,
        physical = data.physicalRaw or 0,
        magic = data.magicRaw or 0,
        flatDR = data.flatDR or 0,
        physicalDR = data.physicalDR or 0,
        magicDR = data.magicDR or 0,
        receivedAt = GetTime(),
        savedAt = type(time) == "function" and time() or 0,
        localPlayer = true
    }
end

function MT:BuildTankSummaryFromFight(fight)
    if not fight or type(fight) ~= "table" then return nil end
    RC6B_Data = RC6B_RebuildData(fight.data or NewData(), fight.events or {})
    return RC6B_BuildSummaryFromData(RC6B_Data, fight.label or fight.primaryEnemy or "Fight", fight.primaryEnemy or "Unknown", fight.duration or 0)
end

function MT:BuildTankSummaryFromDisplay()
    RC6B_Data = self:GetDisplayData() or NewData()
    RC6B_Enemy = "Mixed"
    if type(self.currentView) == "number" and self.fights and self.fights[self.currentView] then
        RC6B_Enemy = self.fights[self.currentView].primaryEnemy or "Unknown"
    elseif self.currentView ~= "OVERALL" and self.fights and self.fights[1] then
        RC6B_Enemy = self.fights[1].primaryEnemy or "Unknown"
    end
    return RC6B_BuildSummaryFromData(RC6B_Data, self:GetViewLabel() or "Selected Fight", RC6B_Enemy, RC2_GetViewDuration(self))
end

-- DR page: individual tooltip percentages remain visible, but the displayed
-- total uses multiplicative stacking because vanilla combines separate
-- SPELL_AURA_MOD_DAMAGE_PERCENT_TAKEN effects multiplicatively.
RC6B_PreviousUpdateDRWindow = MT.UpdateDRWindow
function MT:UpdateDRWindow()
    RC6B_PreviousUpdateDRWindow(self)
    if not self.drFrame then return end
    self:RefreshMitigationContextCache(true)
    RC6B_Context = self:CaptureMitigationContext(UnitExists("target") and UnitName("target") or nil)
    RC6B_PhysModel = RC6B_GetDRModel(RC6B_Context, "Physical")
    RC6B_MagicModel = RC6B_GetDRModel(RC6B_Context, "Magic")
    -- Find the two Total rows created by the existing compact page and relabel
    -- them Effective when stacking changes the arithmetic sum.
    RC6B_I = 1
    while RC6B_I <= table.getn(self.drFrame.drRows or {}) do
        RC6B_Row = self.drFrame.drRows[RC6B_I]
        if RC6B_Row and RC6B_Row.label and RC6B_Row.label:GetText() == "Total" then
            if not RC6B_FirstTotalDone then
                RC6B_Row.label:SetText("Effective")
                RC6B_Row.value:SetText(format("%.1f%%", RC6B_PhysModel.effectivePct or 0))
                RC6B_FirstTotalDone = true
            else
                RC6B_Row.label:SetText("Effective")
                RC6B_Row.value:SetText(format("%.1f%%", RC6B_MagicModel.effectivePct or 0))
            end
        end
        RC6B_I = RC6B_I + 1
    end
    RC6B_FirstTotalDone = nil
end


-- RC6c field diagnostic: prints the most recent landed events using the same
-- authoritative attribution shown by the UI. Useful for validating a mob's
-- UnitDamage range and the 1-damage floor without opening the inspector.
RC6B_PreviousHandleSlash = MT.HandleSlash
function MT:HandleSlash(msg)
    RC6B_Command = lower(msg or "")
    if RC6B_Command == "math" or RC6B_Command == "drmath" then
        RC6B_Events = self:GetDisplayEvents() or {}
        Print("FR1d math audit - most recent landed events")
        RC6B_Shown = 0
        RC6B_I = table.getn(RC6B_Events)
        while RC6B_I >= 1 and RC6B_Shown < 10 do
            RC6B_E = RC6B_EnsureEventAttribution(RC6B_Events[RC6B_I])
            if RC6B_E and RC6B_E.kind == "DAMAGE" and not RC6B_E.environmental then
                RC6B_Check = (tonumber(RC6B_E.taken) or 0)+(tonumber(RC6B_E.flatDR) or 0)+(tonumber(RC6B_E.physicalDR) or 0)+
                    (tonumber(RC6B_E.magicDR) or 0)+(tonumber(RC6B_E.armor) or 0)+(tonumber(RC6B_E.block) or 0)+
                    (tonumber(RC6B_E.resist) or 0)+(tonumber(RC6B_E.absorb) or 0)
                Print((RC6B_E.source or "Unknown") .. " / " .. (RC6B_E.ability or "Unknown") ..
                    " | Raw " .. self:FormatNumber(RC6B_E.raw or 0) ..
                    " = Taken " .. self:FormatNumber(RC6B_E.taken or 0) ..
                    " + Flat " .. self:FormatNumber(RC6B_E.flatDR or 0) ..
                    " + %DR " .. self:FormatNumber((RC6B_E.physicalDR or 0)+(RC6B_E.magicDR or 0)) ..
                    " + Armor " .. self:FormatNumber(RC6B_E.armor or 0) ..
                    " + Block " .. self:FormatNumber(RC6B_E.block or 0) ..
                    " + Resist " .. self:FormatNumber(RC6B_E.resist or 0) ..
                    " + Absorb " .. self:FormatNumber(RC6B_E.absorb or 0) ..
                    " | check " .. self:FormatNumber(RC6B_Check) ..
                    (RC6B_E.critical and " | CRITICAL" or (RC6B_E.crushing and " | CRUSHING" or " | NORMAL")) ..
                    (RC6B_E.drRawAnchor and (" | " .. RC6B_E.drRawAnchor) or "") ..
                    ((RC6B_E.critical or RC6B_E.crushing) and RC6B_E.rawHintLow and RC6B_E.rawHintHigh and
                        (" | base UnitDamage " .. tostring(Round(RC6B_E.rawHintLow)) .. "-" .. tostring(Round(RC6B_E.rawHintHigh))) or ""))
                RC6B_Shown = RC6B_Shown + 1
            end
            RC6B_I = RC6B_I - 1
        end
        if RC6B_Shown == 0 then Print("No landed damage events in this view yet.") end
        return
    end
    RC6B_PreviousHandleSlash(self, msg)
end



-- ============================================================================
-- v1.0.0 RC6d - Rank-aware Sanctuary + hard raw-range safety
--
-- Vanilla 1.12 exposes player buffs to FrameXML through GetPlayerBuff() and
-- GameTooltip:SetPlayerBuff().  The aura texture itself does NOT identify rank.
-- RC6d therefore resolves Sanctuary in this order:
--   1) active aura tooltip amount/rank,
--   2) exact spellbook/action rank the local player just cast,
--   3) constrained inference from a known UnitDamage white-swing range.
-- It never substitutes "highest learned rank" for "active rank".
-- ============================================================================

RC6D_SANCTUARY_RANK_BY_BASE = { [10]=1, [15]=2, [20]=3, [30]=4 }

function RC6D_ParseRankText(text)
    RC6D_T = lower(tostring(text or ""))
    RC6D_A, RC6D_B, RC6D_R = string.find(RC6D_T, "rank%s*([%d]+)")
    if RC6D_R then return tonumber(RC6D_R) end
    return nil
end

function RC6D_ParseSanctuaryBase(name, desc)
    RC6D_Text = lower(tostring(name or "") .. " " .. tostring(desc or ""))
    RC6D_Base = RC5B_FindNumberAfter(RC6D_Text, "reducing damage taken by up to ([%d]+)")
    if not RC6D_Base then RC6D_Base = RC5B_FindNumberAfter(RC6D_Text, "reduces damage taken by up to ([%d]+)") end
    if not RC6D_Base then RC6D_Base = RC5B_FindNumberAfter(RC6D_Text, "damage taken[^%d]*by up to ([%d]+)") end
    if RC6D_Base and RC6D_SANCTUARY_RANK_BY_BASE[RC6D_Base] then return RC6D_Base end
    return nil
end

function RC6D_RecordSanctuaryCast(rank, source)
    rank = tonumber(rank) or 0
    if rank < 1 or rank > 4 then return end
    MT.rc6dLastSanctuaryRank = rank
    MT.rc6dLastSanctuaryCastAt = GetTime and GetTime() or 0
    MT.rc6dLastSanctuaryCastSource = source or "cast"
    -- Force the next combat event/page refresh to rescan the active aura.
    MT.rc5ContextCacheAt = nil
end

function RC6D_GetRecentSanctuaryCastRank()
    RC6D_Rank = tonumber(MT.rc6dLastSanctuaryRank) or 0
    if RC6D_Rank < 1 or RC6D_Rank > 4 then return nil end
    RC6D_Now = GetTime and GetTime() or 0
    RC6D_At = tonumber(MT.rc6dLastSanctuaryCastAt) or 0
    -- Enough time for PLAYER_AURAS_CHANGED / latency, short enough not to
    -- mistake a later externally-applied lower/higher rank for our old cast.
    if RC6D_Now - RC6D_At <= 8 then return RC6D_Rank end
    return nil
end

-- Hook direct spellbook/macro casts.  These APIs carry the exact rank.
if type(CastSpell) == "function" and not RC6D_OriginalCastSpell then
    RC6D_OriginalCastSpell = CastSpell
    CastSpell = function(spellId, bookType)
        RC6D_Name, RC6D_RankText = GetSpellName(spellId, bookType or BOOKTYPE_SPELL or "spell")
        if RC6D_Name and lower(RC6D_Name) == "blessing of sanctuary" then
            RC6D_RecordSanctuaryCast(RC6D_ParseRankText(RC6D_RankText), "CastSpell")
        end
        return RC6D_OriginalCastSpell(spellId, bookType)
    end
end

if type(CastSpellByName) == "function" and not RC6D_OriginalCastSpellByName then
    RC6D_OriginalCastSpellByName = CastSpellByName
    CastSpellByName = function(spellName, onSelf)
        RC6D_LowerName = lower(tostring(spellName or ""))
        if find(RC6D_LowerName, "blessing of sanctuary", 1, true) then
            RC6D_Rank = RC6D_ParseRankText(RC6D_LowerName)
            if not RC6D_Rank then
                RC6D_Tex, RC6D_Rank = RC5B_GetSanctuarySpellInfo()
            end
            RC6D_RecordSanctuaryCast(RC6D_Rank, "CastSpellByName")
        end
        return RC6D_OriginalCastSpellByName(spellName, onSelf)
    end
end

-- Action-bar casts are common in Vanilla.  SetAction() exposes the action's
-- spell tooltip, so capture rank/value before UseAction executes when possible.
if type(UseAction) == "function" and not RC6D_OriginalUseAction then
    RC6D_OriginalUseAction = UseAction
    UseAction = function(slot, checkCursor, onSelf)
        RC6D_Tip = GetScanTooltip()
        if RC6D_Tip and RC6D_Tip.SetAction then
            RC6D_Tip:Hide(); RC6D_Tip:ClearLines()
            RC6D_OK = RC5_SafeTooltipCall(function() RC6D_Tip:SetAction(slot) end)
            if RC6D_OK then
                RC6D_Name, RC6D_Desc = RC5_ReadTooltipText(RC6D_Tip)
                if RC6D_Name and find(lower(RC6D_Name), "blessing of sanctuary", 1, true) then
                    RC6D_Rank = RC6D_ParseRankText(RC6D_Name .. " " .. (RC6D_Desc or ""))
                    RC6D_Base = RC6D_ParseSanctuaryBase(RC6D_Name, RC6D_Desc)
                    if not RC6D_Rank and RC6D_Base then RC6D_Rank = RC6D_SANCTUARY_RANK_BY_BASE[RC6D_Base] end
                    RC6D_RecordSanctuaryCast(RC6D_Rank, "UseAction")
                end
            end
            RC6D_Tip:Hide()
        end
        return RC6D_OriginalUseAction(slot, checkCursor, onSelf)
    end
end

-- Replace the player-buff scanner with rank-aware Sanctuary handling.
function RC5B_ScanPlayerBuffs()
    RC6D_Results = {}
    RC6D_Tip = GetScanTooltip()
    RC6D_SanctuaryTexture, RC6D_MaxLearnedRank = RC5B_GetSanctuarySpellInfo()
    if type(GetPlayerBuff) == "function" and type(GetPlayerBuffTexture) == "function" and RC6D_Tip.SetPlayerBuff then
        RC6D_Slot = 0
        while RC6D_Slot <= 31 do
            RC6D_BuffIndex = GetPlayerBuff(RC6D_Slot, "HELPFUL")
            if RC6D_BuffIndex and RC6D_BuffIndex >= 0 then
                RC6D_Texture = GetPlayerBuffTexture(RC6D_BuffIndex)
                if RC6D_Texture then
                    RC6D_Tip:Hide(); RC6D_Tip:ClearLines()
                    RC6D_OK = RC5_SafeTooltipCall(function() RC6D_Tip:SetPlayerBuff(RC6D_BuffIndex) end)
                    RC6D_Name, RC6D_Desc = "", ""
                    if RC6D_OK then RC6D_Name, RC6D_Desc = RC5_ReadTooltipText(RC6D_Tip) end
                    RC6D_Effect = RC5_ClassifyEffect(RC6D_Name or "", RC6D_Desc or "", false)

                    if RC5B_IsSanctuaryTexture(RC6D_Texture, RC6D_SanctuaryTexture) or
                       (RC6D_Name and find(lower(RC6D_Name), "blessing of sanctuary", 1, true)) then
                        RC6D_Effect = RC6D_Effect or {}
                        RC6D_Effect.name = "Blessing of Sanctuary"
                        RC6D_Effect.description = RC6D_Desc or ""
                        RC6D_Effect.kind = "flatDR"
                        RC6D_Effect.known = true
                        RC6D_Base = RC6D_ParseSanctuaryBase(RC6D_Name, RC6D_Desc)
                        RC6D_Rank = RC6D_ParseRankText((RC6D_Name or "") .. " " .. (RC6D_Desc or ""))
                        if not RC6D_Rank and RC6D_Base then RC6D_Rank = RC6D_SANCTUARY_RANK_BY_BASE[RC6D_Base] end
                        RC6D_Source = "aura tooltip"

                        if not RC6D_Rank then
                            RC6D_Rank = RC6D_GetRecentSanctuaryCastRank()
                            if RC6D_Rank then RC6D_Source = MT.rc6dLastSanctuaryCastSource or "recent cast" end
                        end
                        if RC6D_Rank and not RC6D_Base then RC6D_Base = RC5B_SANCTUARY_BASE[RC6D_Rank] end

                        if RC6D_Rank and RC6D_Base then
                            RC6D_Effect.rank = RC6D_Rank
                            RC6D_Effect.value = RC6D_Base
                            RC6D_Effect.baseValue = RC6D_Base
                            RC6D_Effect.sanctuaryRankUnknown = nil
                            RC6D_Effect.rankSource = RC6D_Source
                            RC6D_Effect.label = "Sanctuary Rank " .. tostring(RC6D_Rank) .. " / " .. tostring(RC6D_Base) .. " base flat"
                        else
                            RC6D_Effect.rank = 0
                            RC6D_Effect.value = 0
                            RC6D_Effect.sanctuaryRankUnknown = true
                            RC6D_Effect.maxLearnedRank = RC6D_MaxLearnedRank
                            RC6D_Effect.rankSource = "unresolved"
                            RC6D_Effect.label = "Sanctuary active / rank unresolved"
                        end
                    end

                    if not RC6D_Effect.name or RC6D_Effect.name == "" then RC6D_Effect.name = tostring(RC6D_Texture) end
                    RC6D_Effect.texture = RC6D_Texture
                    RC6D_Effect.buffIndex = RC6D_BuffIndex
                    table.insert(RC6D_Results, RC6D_Effect)
                end
            end
            RC6D_Slot = RC6D_Slot + 1
        end
    else
        RC6D_Results = RC5_ScanUnitAuras("player", false)
    end
    RC6D_Tip:Hide()
    return RC6D_Results
end

-- Add unknown-rank metadata/candidates to the DR model.
-- Project Legacy has exact Sanctuary caps 10/15/20/30; Guardian's Favor does
-- not modify them.
RC6D_PreviousGetDRModel = RC6B_GetDRModel
function RC6B_GetDRModel(context, school)
    RC6D_Model = RC6D_PreviousGetDRModel(context, school)
    RC6D_Model.sanctuaryUnknown = false
    RC6D_Model.sanctuaryCandidates = nil
    if not context then return RC6D_Model end
    RC6D_I = 1
    while RC6D_I <= table.getn(context.buffs or {}) do
        RC6D_E = context.buffs[RC6D_I]
        if RC6D_E and RC6D_E.kind == "flatDR" and RC6D_E.sanctuaryRankUnknown then
            RC6D_Model.sanctuaryUnknown = true
            RC6D_Model.sanctuaryCandidates = {10, 15, 20, 30}
            RC6D_Model.sanctuaryGFMultiplier = 1
            break
        end
        RC6D_I = RC6D_I + 1
    end
    return RC6D_Model
end

function RC6D_InferUnknownSanctuaryCap(eventData, model, low, high, armorRate, pctFactor, downstream)
    if not model or not model.sanctuaryUnknown or not model.sanctuaryCandidates then return nil,nil end
    if not low or not high or low <= 0 or high < low then return nil,nil end
    RC6D_AF = 1 - (tonumber(armorRate) or 0)
    if RC6D_AF < 0.25 then RC6D_AF = 0.25 end
    RC6D_PF = tonumber(pctFactor) or 1
    if RC6D_PF < 0.01 then RC6D_PF = 0.01 end
    RC6D_Mid = (low + high) / 2
    RC6D_BestCap, RC6D_BestScore, RC6D_BestRank = nil, nil, nil
    RC6D_I = 1
    while RC6D_I <= table.getn(model.sanctuaryCandidates) do
        RC6D_Cap = tonumber(model.sanctuaryCandidates[RC6D_I]) or 0
        -- Reverse only the known downstream passive layers.  If this candidate
        -- rank can produce a raw roll inside UnitDamage, its score is simply
        -- distance from the range midpoint; outside candidates are penalized.
        RC6D_RequiredRaw = (downstream / RC6D_AF / RC6D_PF) + RC6D_Cap
        RC6D_Dist = math.abs(RC6D_RequiredRaw - RC6D_Mid)
        if RC6D_RequiredRaw < low then RC6D_Dist = RC6D_Dist + (low - RC6D_RequiredRaw) * 10 end
        if RC6D_RequiredRaw > high then RC6D_Dist = RC6D_Dist + (RC6D_RequiredRaw - high) * 10 end
        if not RC6D_BestScore or RC6D_Dist < RC6D_BestScore then
            RC6D_BestScore = RC6D_Dist
            RC6D_BestCap = RC6D_Cap
            RC6D_BestRank = RC6D_I
        end
        RC6D_I = RC6D_I + 1
    end
    return RC6D_BestCap, RC6D_BestRank
end

-- Patch the RC6c attribution at entry: if Sanctuary rank could not be obtained
-- from the client, infer a rank-specific cap from the hard white-swing range.
-- A temporary per-event context is used so shared context history is untouched.
RC6D_PreviousEnsureEventAttribution = RC6B_EnsureEventAttribution
function RC6B_EnsureEventAttribution(eventData)
    if not eventData then return eventData end
    if eventData.rc6MathVersion == 5 then return eventData end

    -- Let RC6c rebuild first when the active rank is already known.
    RC6D_Context = RC6_ContextForEvent(eventData)
    RC6D_Model = RC6B_GetDRModel(RC6D_Context, eventData.school or "Physical")
    if RC6D_Model and RC6D_Model.sanctuaryUnknown and eventData.ability == "Melee" and not eventData.critical and not eventData.crushing then
        RC6D_Hint, RC6D_Low, RC6D_High = RC6B_GetWhiteSwingRange(eventData)
        RC6D_Downstream = (tonumber(eventData.taken) or 0)+(tonumber(eventData.block) or 0)+(tonumber(eventData.resist) or 0)+(tonumber(eventData.absorb) or 0)
        RC6D_ArmorRate = RC6B_GetArmorRate(eventData)
        RC6D_Cap, RC6D_Rank = RC6D_InferUnknownSanctuaryCap(eventData, RC6D_Model, RC6D_Low, RC6D_High, RC6D_ArmorRate, RC6D_Model.pctFactor, RC6D_Downstream)
        if RC6D_Cap and RC6D_Rank then
            RC6D_ContextCopy = CopyTable(RC6D_Context)
            RC6D_ContextCopy.buffs = CopyTable(RC6D_Context.buffs or {})
            RC6D_I = 1
            while RC6D_I <= table.getn(RC6D_ContextCopy.buffs) do
                RC6D_E = RC6D_ContextCopy.buffs[RC6D_I]
                if RC6D_E and RC6D_E.kind == "flatDR" and RC6D_E.sanctuaryRankUnknown then
                    RC6D_E = CopyTable(RC6D_E)
                    RC6D_E.sanctuaryRankUnknown = nil
                    RC6D_E.rank = RC6D_Rank
                    RC6D_E.value = RC6D_Cap
                    RC6D_E.baseValue = RC5B_SANCTUARY_BASE[RC6D_Rank]
                    RC6D_E.rankSource = "combat inference"
                    RC6D_ContextCopy.buffs[RC6D_I] = RC6D_E
                    break
                end
                RC6D_I = RC6D_I + 1
            end
            RC6D_OldContextID = eventData.contextID
            RC6D_TempKey = "RC6D:" .. tostring(RC6D_OldContextID or "") .. ":S" .. tostring(RC6D_Rank)
            MT.mitigationContexts = MT.mitigationContexts or {}
            MT.mitigationContexts[RC6D_TempKey] = RC6D_ContextCopy
            eventData.contextID = RC6D_TempKey
            eventData.rc6MathVersion = nil
            RC6D_Result = RC6D_PreviousEnsureEventAttribution(eventData)
            eventData.contextID = RC6D_OldContextID
            eventData.sanctuaryRank = RC6D_Rank
            eventData.sanctuaryFlatCap = RC6D_Cap
            eventData.sanctuaryRankSource = "combat inference"
            eventData.rc6MathVersion = 5
            return RC6D_Result
        end
    end

    eventData.rc6MathVersion = nil
    RC6D_Result = RC6D_PreviousEnsureEventAttribution(eventData)
    if RC6D_Context then
        RC6D_I = 1
        while RC6D_I <= table.getn(RC6D_Context.buffs or {}) do
            RC6D_E = RC6D_Context.buffs[RC6D_I]
            if RC6D_E and RC6D_E.kind == "flatDR" and find(lower(RC6D_E.name or ""), "blessing of sanctuary", 1, true) then
                if tonumber(RC6D_E.rank) and tonumber(RC6D_E.rank) > 0 then
                    eventData.sanctuaryRank = tonumber(RC6D_E.rank)
                    eventData.sanctuaryFlatCap = tonumber(RC6D_E.value) or 0
                    eventData.sanctuaryRankSource = RC6D_E.rankSource or "aura"
                end
                break
            end
            RC6D_I = RC6D_I + 1
        end
    end
    eventData.rc6MathVersion = 5
    return RC6D_Result
end

-- RC6d audit adds active Sanctuary rank/cap so rank mistakes are visible at a glance.
RC6D_PreviousHandleSlash = MT.HandleSlash
function MT:HandleSlash(msg)
    RC6D_Command = lower(msg or "")
    if RC6D_Command == "sanc" or RC6D_Command == "sanctuary" then
        self:RefreshMitigationContextCache(true)
        RC6D_Context = self:CaptureMitigationContext(UnitExists("target") and UnitName("target") or nil)
        RC6D_Found = false
        RC6D_I = 1
        while RC6D_I <= table.getn(RC6D_Context.buffs or {}) do
            RC6D_E = RC6D_Context.buffs[RC6D_I]
            if RC6D_E and RC6D_E.kind == "flatDR" and find(lower(RC6D_E.name or ""), "blessing of sanctuary", 1, true) then
                RC6D_Found = true
                if RC6D_E.sanctuaryRankUnknown then
                    Print("Sanctuary active | rank unresolved from aura | highest learned rank " .. tostring(RC6D_E.maxLearnedRank or "?") .. " (NOT used as active rank)")
                else
                    Print("Sanctuary active | Rank " .. tostring(RC6D_E.rank or "?") .. " | base " .. tostring(RC6D_E.baseValue or "?") .. " | effective Flat DR " .. tostring(RC6D_E.value or 0) .. " | source " .. tostring(RC6D_E.rankSource or "aura"))
                end
            end
            RC6D_I = RC6D_I + 1
        end
        if not RC6D_Found then Print("Blessing of Sanctuary is not currently detected.") end
        return
    end
    RC6D_PreviousHandleSlash(self, msg)
end

-- Replace the RC6c math command wrapper only to append rank/cap info to each
-- event after the existing audit.  The existing /mt math output remains intact.
RC6D_PreviousMathHandleSlash = MT.HandleSlash
function MT:HandleSlash(msg)
    RC6D_Command = lower(msg or "")
    if RC6D_Command == "mathrank" then
        RC6D_Events = self:GetDisplayEvents() or {}
        Print("RC6d Sanctuary rank audit - most recent landed events")
        RC6D_Shown = 0
        RC6D_I = table.getn(RC6D_Events)
        while RC6D_I >= 1 and RC6D_Shown < 10 do
            RC6D_E = RC6B_EnsureEventAttribution(RC6D_Events[RC6D_I])
            if RC6D_E and RC6D_E.kind == "DAMAGE" and not RC6D_E.environmental then
                Print((RC6D_E.source or "Unknown") .. " / " .. (RC6D_E.ability or "Unknown") ..
                    " | Raw " .. self:FormatNumber(RC6D_E.raw or 0) ..
                    " | Taken " .. self:FormatNumber(RC6D_E.taken or 0) ..
                    " | Flat " .. self:FormatNumber(RC6D_E.flatDR or 0) ..
                    (RC6D_E.sanctuaryRank and (" | Sanc Rank " .. tostring(RC6D_E.sanctuaryRank) .. " cap " .. self:FormatNumber(RC6D_E.sanctuaryFlatCap or 0) .. " [" .. tostring(RC6D_E.sanctuaryRankSource or "?") .. "]") or "" ) ..
                    (RC6D_E.drRawAnchor and (" | " .. RC6D_E.drRawAnchor) or ""))
                RC6D_Shown = RC6D_Shown + 1
            end
            RC6D_I = RC6D_I - 1
        end
        if RC6D_Shown == 0 then Print("No landed damage events in this view yet.") end
        return
    end
    RC6D_PreviousMathHandleSlash(self, msg)
end


-- ============================================================================
-- v1.0.0 RC6e - Current Project Legacy DR talent pass
--
-- Talent discovery remains tooltip-driven so future PL wording changes can be
-- picked up without a code release.  The registry below supplies verified
-- current-calculator semantics for cases generic text cannot safely infer:
-- school-specific DR, mixed beneficial/harmful effects, and talents whose DR
-- is only active while a stance/buff/pet condition exists.
-- ============================================================================

RC6E_TALENT_RULES = {
    -- Project Legacy: intentionally empty; tooltip-driven DR is authoritative.
}

function RC6E_CopySchools(src)
    RC6E_Out = {}
    if not src then return RC6E_Out end
    for RC6E_K,RC6E_V in pairs(src) do if RC6E_V then RC6E_Out[RC6E_K]=true end end
    return RC6E_Out
end

function RC6E_SchoolListText(schools)
    RC6E_Order={"Arcane","Fire","Frost","Holy","Nature","Shadow"}
    RC6E_Text=""
    for RC6E_I=1,table.getn(RC6E_Order) do
        RC6E_S=RC6E_Order[RC6E_I]
        if schools and schools[RC6E_S] then
            if RC6E_Text~="" then RC6E_Text=RC6E_Text.."/" end
            RC6E_Text=RC6E_Text..RC6E_S
        end
    end
    return RC6E_Text
end

function RC6E_ApplyTalentRule(effect, name, rank)
    RC6E_Rule=RC6E_TALENT_RULES[lower(tostring(name or ""))]
    if not RC6E_Rule then return effect,nil end
    effect=effect or {name=name or "Unknown",description="",known=false,kind="context"}
    effect.vpRule=true
    effect.activationMode=RC6E_Rule.mode
    effect.rank=tonumber(rank) or 0

    if RC6E_Rule.mode=="passive" then
        effect.kind=RC6E_Rule.kind or effect.kind
        effect.value=(tonumber(RC6E_Rule.value) or ((tonumber(RC6E_Rule.perRank) or 0)*effect.rank))
        effect.known=true
        if RC6E_Rule.schools then effect.schools=RC6E_CopySchools(RC6E_Rule.schools) end
        if RC6E_Rule.physicalTakenIncreasePerRank then
            effect.physicalTakenIncrease=(tonumber(RC6E_Rule.physicalTakenIncreasePerRank) or 0)*effect.rank
        end
        if effect.kind=="schoolDR" then
            effect.label=RC6E_SchoolListText(effect.schools).." damage taken -"..tostring(effect.value).."%"
        elseif effect.kind=="spellDR" then
            effect.label="Spell damage taken -"..tostring(effect.value).."%"
        elseif effect.kind=="percentDR" then
            effect.label="All damage taken -"..tostring(effect.value).."%"
        end
        return effect,true
    end
    return effect,false
end

-- Extend the phrase scanner with school-specific DR and damage-taken increases.
-- This applies to buffs/items too, not just talents.
RC6E_PreviousClassifyEffect = RC5_ClassifyEffect
RC5_ClassifyEffect = function(name, description, isDebuff)
    RC6E_Effect=RC6E_PreviousClassifyEffect(name,description,isDebuff)
    RC6E_D=lower(tostring(description or ""))
    RC6E_N=lower(tostring(name or ""))

    -- Known mixed/passive talent semantics first. Rank-specific values are
    -- applied later by the talent scanner; here we only prevent false generic
    -- classification of conditional/pet-only talents as always-on DR.
    RC6E_Rule=RC6E_TALENT_RULES[RC6E_N]
    if RC6E_Rule and (RC6E_Rule.mode=="conditional" or RC6E_Rule.mode=="conditionalPet" or
       RC6E_Rule.mode=="transfer" or RC6E_Rule.mode=="petOnly") then
        RC6E_Effect.activationMode=RC6E_Rule.mode
    end

    -- Generic "damage taken from X/Y effects by N%" school parser.  It only
    -- becomes schoolDR when at least one named magic school is present.
    RC6E_Pct=RC5E_FindPct and RC5E_FindPct(RC6E_D,"damage taken from.-by ([%d%.]+)%%") or nil
    if not RC6E_Pct then RC6E_Pct=RC5E_FindPct and RC5E_FindPct(RC6E_D,"reduces damage taken from.-by ([%d%.]+)%%") or nil end
    if RC6E_Pct then
        RC6E_Schools={}
        if find(RC6E_D,"arcane",1,true) then RC6E_Schools.Arcane=true end
        if find(RC6E_D,"fire",1,true) then RC6E_Schools.Fire=true end
        if find(RC6E_D,"frost",1,true) then RC6E_Schools.Frost=true end
        if find(RC6E_D,"holy",1,true) then RC6E_Schools.Holy=true end
        if find(RC6E_D,"nature",1,true) then RC6E_Schools.Nature=true end
        if find(RC6E_D,"shadow",1,true) then RC6E_Schools.Shadow=true end
        RC6E_HasSchool=false
        for RC6E_K,RC6E_V in pairs(RC6E_Schools) do if RC6E_V then RC6E_HasSchool=true end end
        if RC6E_HasSchool then
            RC6E_Effect.kind="schoolDR"
            RC6E_Effect.value=RC6E_Pct
            RC6E_Effect.schools=RC6E_Schools
            RC6E_Effect.known=true
            RC6E_Effect.label=RC6E_SchoolListText(RC6E_Schools).." damage taken -"..tostring(RC6E_Pct).."%"
            if find(RC6E_D,"physical",1,true) then RC6E_Effect.alsoPhysical=true end
        end
    end

    RC6E_Inc=RC5E_FindPct and RC5E_FindPct(RC6E_D,"increases physical damage taken by ([%d%.]+)%%") or nil
    if not RC6E_Inc then RC6E_Inc=RC5E_FindPct and RC5E_FindPct(RC6E_D,"physical damage taken.-increased by ([%d%.]+)%%") or nil end
    if RC6E_Inc then RC6E_Effect.physicalTakenIncrease=RC6E_Inc end

    return RC6E_Effect
end

-- Current-calculator-aware learned talent scanner.  Conditional talents are
-- intentionally NOT placed in context.talents as permanent DR.  If their aura
-- is active, RC5B_ScanPlayerBuffs/RC5_ClassifyEffect can still recognize it.
RC5B_ScanDefensiveTalents = function()
    RC6E_Results={}
    if type(GetNumTalentTabs)~="function" or type(GetNumTalents)~="function" or type(GetTalentInfo)~="function" then return RC6E_Results end
    RC6E_Tip=GetScanTooltip()
    for RC6E_Tab=1,(GetNumTalentTabs() or 0) do
        RC6E_Count=GetNumTalents(RC6E_Tab) or 0
        for RC6E_Index=1,RC6E_Count do
            RC6E_Name,_,_,_,RC6E_Rank,RC6E_MaxRank=GetTalentInfo(RC6E_Tab,RC6E_Index)
            RC6E_Rank=tonumber(RC6E_Rank) or 0
            if RC6E_Name and RC6E_Rank>0 then
                RC6E_Desc=""
                if RC6E_Tip.SetTalent then
                    RC6E_Tip:Hide(); RC6E_Tip:ClearLines()
                    RC6E_OK=RC5_SafeTooltipCall(function() RC6E_Tip:SetTalent(RC6E_Tab,RC6E_Index) end)
                    if RC6E_OK then _,RC6E_Desc=RC5_ReadTooltipText(RC6E_Tip) end
                end
                RC6E_E=RC5_ClassifyEffect(RC6E_Name,RC6E_Desc,false)
                RC6E_E,RC6E_Passive=RC6E_ApplyTalentRule(RC6E_E,RC6E_Name,RC6E_Rank)
                RC6E_Rule=RC6E_TALENT_RULES[lower(RC6E_Name)]

                if not RC6E_Rule or RC6E_Rule.mode=="passive" or RC6E_Rule.mode=="support" then
                    RC5B_ApplyKnownTalent(RC6E_E,RC6E_Name,RC6E_Rank)
                    if RC6E_E and (RC6E_E.kind=="percentDR" or RC6E_E.kind=="physicalDR" or RC6E_E.kind=="spellDR" or
                       RC6E_E.kind=="schoolDR" or RC6E_E.kind=="multiDR" or RC6E_E.kind=="flatDR" or
                       RC6E_E.kind=="armorBuff" or RC6E_E.kind=="resistanceBuff" or RC6E_E.kind=="critReduction" or
                       RC6E_E.kind=="dodgeBonus" or RC6E_E.kind=="parryBonus" or RC6E_E.kind=="blockChanceBonus" or
                       RC6E_E.kind=="blockValueBonus" or RC6E_E.kind=="sanctuaryBoost" or RC6E_E.kind=="auraBoost") then
                        RC6E_E.rank=RC6E_Rank
                        RC6E_E.maxRank=tonumber(RC6E_MaxRank) or RC6E_Rank
                        RC6E_E.source="talent"
                        table.insert(RC6E_Results,RC6E_E)
                    end
                end
            end
        end
    end
    RC6E_Tip:Hide()
    return RC6E_Results
end

function RC6E_EffectAppliesToSchool(effect, school)
    if not effect then return false end
    if effect.kind=="percentDR" then return true end
    if school=="Physical" then
        if effect.kind=="physicalDR" then return true end
        if effect.kind=="multiDR" and effect.alsoPhysical then return true end
        return false
    end
    if effect.kind=="spellDR" then return true end
    if effect.kind=="schoolDR" or effect.kind=="multiDR" then
        return effect.schools and effect.schools[school] and true or false
    end
    return false
end

-- School-aware multiplicative model.  The event's actual damage school now
-- chooses which school-specific talent participates; school DR is never folded
-- into unrelated magic schools.
function RC6B_GetDRModel(context, school)
    RC6E_Model={flatCap=0,pctFactor=1,listedPct=0,effectCount=0,effects={},physicalTakenIncrease=0}
    if not context then return RC6E_Model end
    RC6E_Lists={context.buffs or {},context.talents or {},context.equipment or {}}
    for RC6E_LI=1,table.getn(RC6E_Lists) do
        for RC6E_I=1,table.getn(RC6E_Lists[RC6E_LI]) do
            RC6E_E=RC6E_Lists[RC6E_LI][RC6E_I]
            RC6E_V=RC6E_E and tonumber(RC6E_E.value) or 0
            if RC6E_E and RC6E_E.kind=="flatDR" and RC6E_V>0 then
                RC6E_Model.flatCap=RC6E_Model.flatCap+RC6E_V
            elseif RC6E_E and RC6E_V>0 and RC6E_EffectAppliesToSchool(RC6E_E,school) then
                if RC6E_V>95 then RC6E_V=95 end
                RC6E_Model.listedPct=RC6E_Model.listedPct+RC6E_V
                RC6E_Model.pctFactor=RC6E_Model.pctFactor*(1-(RC6E_V/100))
                RC6E_Model.effectCount=RC6E_Model.effectCount+1
                table.insert(RC6E_Model.effects,RC6E_E)
            end
            if RC6E_E and school=="Physical" and (tonumber(RC6E_E.physicalTakenIncrease) or 0)>0 then
                -- Record the vulnerability for diagnostics.  RC6e deliberately
                -- does not convert increased damage into a negative mitigation
                -- slice; it simply prevents a mixed defensive talent from being misreported as
                -- physical DR.
                RC6E_Model.physicalTakenIncrease=RC6E_Model.physicalTakenIncrease+(tonumber(RC6E_E.physicalTakenIncrease) or 0)
            end
        end
    end
    if RC6E_Model.pctFactor<0.01 then RC6E_Model.pctFactor=0.01 end
    if RC6E_Model.pctFactor>1 then RC6E_Model.pctFactor=1 end
    RC6E_Model.effectivePct=(1-RC6E_Model.pctFactor)*100

    -- Preserve RC6d's unknown Sanctuary rank inference metadata.
    -- Project Legacy Sanctuary candidates are exact and receive no
    -- Guardian's Favor multiplier.
    for RC6E_I=1,table.getn(context.buffs or {}) do
        RC6E_E=context.buffs[RC6E_I]
        if RC6E_E and RC6E_E.kind=="flatDR" and RC6E_E.sanctuaryRankUnknown then
            RC6E_Model.sanctuaryUnknown=true
            RC6E_Model.sanctuaryCandidates={10,15,20,30}
            RC6E_Model.sanctuaryGFMultiplier=1
            break
        end
    end
    return RC6E_Model
end

-- Totals are retained for older UI paths, now with school-specific buckets.
RC6E_PreviousEffectTotals = RC5B_EffectTotals
RC5B_EffectTotals = function(context)
    RC6E_Tot=RC6E_PreviousEffectTotals(context)
    RC6E_Tot.schoolPct=RC6E_Tot.schoolPct or {Arcane=0,Fire=0,Frost=0,Holy=0,Nature=0,Shadow=0}
    RC6E_Lists={context and context.buffs or {},context and context.talents or {},context and context.equipment or {}}
    for RC6E_LI=1,table.getn(RC6E_Lists) do
        for RC6E_I=1,table.getn(RC6E_Lists[RC6E_LI]) do
            RC6E_E=RC6E_Lists[RC6E_LI][RC6E_I]
            if RC6E_E and (RC6E_E.kind=="schoolDR" or RC6E_E.kind=="multiDR") and RC6E_E.schools then
                for RC6E_S,_ in pairs(RC6E_Tot.schoolPct) do
                    if RC6E_E.schools[RC6E_S] then RC6E_Tot.schoolPct[RC6E_S]=RC6E_Tot.schoolPct[RC6E_S]+(tonumber(RC6E_E.value) or 0) end
                end
            end
        end
    end
    return RC6E_Tot
end

-- Keep the compact DR page, but include school-specific sources beneath Magic
-- DR rather than pretending they apply to every spell school.
RC6E_PreviousUpdateDRWindow = MT.UpdateDRWindow
function MT:UpdateDRWindow()
    RC6E_PreviousUpdateDRWindow(self)
    if not self.drFrame then return end
    self:RefreshMitigationContextCache(true)
    RC6E_Context=self:CaptureMitigationContext(UnitExists("target") and UnitName("target") or nil)
    RC6E_RowIndex=1
    while RC6E_RowIndex<=table.getn(self.drFrame.drRows or {}) do
        RC6E_Row=self.drFrame.drRows[RC6E_RowIndex]
        if RC6E_Row and RC6E_Row.label and RC6E_Row.label:GetText()=="Magic DR" then
            RC6E_MagicHeaderIndex=RC6E_RowIndex
            break
        end
        RC6E_RowIndex=RC6E_RowIndex+1
    end
    -- Existing compact page may not have room to insert rows safely.  Add
    -- school-specific source text only into currently-unused rows immediately
    -- after the Magic DR block when available.
    if RC6E_MagicHeaderIndex then
        RC6E_Insert=RC6E_MagicHeaderIndex+1
        for RC6E_I=1,table.getn(RC6E_Context.talents or {}) do
            RC6E_E=RC6E_Context.talents[RC6E_I]
            if RC6E_E and RC6E_E.kind=="schoolDR" and RC6E_Insert<=table.getn(self.drFrame.drRows or {}) then
                RC6E_Row=self.drFrame.drRows[RC6E_Insert]
                if RC6E_Row and not RC6E_Row.label:IsShown() then
                    RC6E_Row.label:SetText(RC6E_E.name or "Talent")
                    RC6E_Row.value:SetText(tostring(RC6E_E.value or 0).."% "..RC6E_SchoolListText(RC6E_E.schools))
                    RC6E_Row.label:Show(); RC6E_Row.value:Show()
                    RC6E_Insert=RC6E_Insert+1
                end
            end
        end
    end
end

-- Diagnostic for cross-class testing.  This makes it obvious which learned
-- talents are treated as passive, which are school-specific, and which current
-- PL talents are deliberately excluded until their active condition is seen.
RC6E_PreviousHandleSlash = MT.HandleSlash
function MT:HandleSlash(msg)
    RC6E_Cmd=lower(tostring(msg or ""))
    if RC6E_Cmd=="drscan" or RC6E_Cmd=="talentdr" then
        self:RefreshMitigationContextCache(true)
        Print("RC6e DR talent scan - learned passive effects")
        RC6E_Shown=0
        for RC6E_I=1,table.getn(self.rc5DefensiveTalents or {}) do
            RC6E_E=self.rc5DefensiveTalents[RC6E_I]
            if RC6E_E and (RC6E_E.kind=="percentDR" or RC6E_E.kind=="physicalDR" or RC6E_E.kind=="spellDR" or RC6E_E.kind=="schoolDR") then
                RC6E_Extra=""
                if RC6E_E.schools then RC6E_Extra=" ["..RC6E_SchoolListText(RC6E_E.schools).."]" end
                if (tonumber(RC6E_E.physicalTakenIncrease) or 0)>0 then RC6E_Extra=RC6E_Extra.."; physical taken +"..tostring(RC6E_E.physicalTakenIncrease).."%" end
                Print((RC6E_E.name or "Unknown").." R"..tostring(RC6E_E.rank or "?").." = "..tostring(RC6E_E.value or 0).."% "..tostring(RC6E_E.kind)..RC6E_Extra)
                RC6E_Shown=RC6E_Shown+1
            end
        end
        if RC6E_Shown==0 then Print("No learned passive direct-DR talents detected.") end
        Print("Conditional DR is counted only while its active aura/condition is detected.")
        return
    end
    RC6E_PreviousHandleSlash(self,msg)
end


-- RC6e follow-up safety: known conditional talents get their effect semantics
-- when they are seen as an ACTIVE aura, while the learned-talent scanner above
-- still excludes them from permanent context.
RC6E_ClassifierWithSchools = RC5_ClassifyEffect
RC5_ClassifyEffect = function(name, description, isDebuff)
    RC6E_E=RC6E_ClassifierWithSchools(name,description,isDebuff)
    RC6E_Rule=RC6E_TALENT_RULES[lower(tostring(name or ""))]
    if RC6E_Rule and RC6E_Rule.mode=="conditional" then
        RC6E_E.activationMode="conditional"
        RC6E_E.kind=RC6E_Rule.kind or RC6E_E.kind
        RC6E_E.value=tonumber(RC6E_Rule.value) or tonumber(RC6E_E.value) or 0
        RC6E_E.schools=RC6E_CopySchools(RC6E_Rule.schools)
        RC6E_E.alsoPhysical=RC6E_Rule.physical and true or RC6E_E.alsoPhysical
        RC6E_E.known=true
    end
    return RC6E_E
end

RC6E_OriginalAppliesToSchool = RC6E_EffectAppliesToSchool
function RC6E_EffectAppliesToSchool(effect, school)
    if school=="Physical" and effect and effect.alsoPhysical then return true end
    return RC6E_OriginalAppliesToSchool(effect,school)
end

-- Make RC6e's school-aware model reprocess RC6d-era saved events on demand.
-- This is especially important when opening an older fight after installing
-- RC6e: its event math should not remain frozen at mathVersion 5.
RC6E_PreviousEnsureEventAttribution = RC6B_EnsureEventAttribution
function RC6B_EnsureEventAttribution(eventData)
    if not eventData then return eventData end
    if eventData.rc6MathVersion==6 then return eventData end
    eventData.rc6MathVersion=nil
    RC6E_Result=RC6E_PreviousEnsureEventAttribution(eventData)
    if RC6E_Result then RC6E_Result.rc6MathVersion=6 end
    return RC6E_Result
end


-- Final RC6e compact DR page: same four sections the user already approved,
-- with school-specific magic sources annotated instead of folded into every
-- magic event.
function MT:UpdateDRWindow()
    local frame = self:CreateDRWindow()
    self:RefreshMitigationContextCache(true)
    local attacker = UnitExists("target") and UnitName("target") or nil
    local context = self:CaptureMitigationContext(attacker)
    local armorReduction = GetArmorReduction(attacker or "") or 0
    local physicalModel = RC6B_GetDRModel(context,"Physical")
    local magicBaseModel = RC6B_GetDRModel(context,"Magic")
    local i, li, e, row, y, shown
    local lists = {context.buffs or {},context.talents or {},context.equipment or {}}

    if frame.note then frame.note:Hide() end
    for i=1,table.getn(frame.drRows or {}) do
        frame.drRows[i].label:Hide(); frame.drRows[i].value:Hide()
    end

    row=1; y=-31
    RC5D_AddLine(frame,row,"Armor",self:FormatNumber(context.armor or 0).." ("..string.format("%.1f",armorReduction*100).."%)",y,true)
    row=row+1; y=y-20

    RC5D_AddLine(frame,row,"Flat DR","",y,true); row=row+1; y=y-17; shown=false
    for li=1,table.getn(lists) do
        for i=1,table.getn(lists[li]) do
            e=lists[li][i]
            if e and e.kind=="flatDR" and (tonumber(e.value) or 0)>0 then
                RC5D_AddLine(frame,row,e.name or "Effect","+"..self:FormatNumber(e.value),y,false)
                row=row+1; y=y-15; shown=true
            end
        end
    end
    if not shown then RC5D_AddLine(frame,row,"None detected","",y,false); row=row+1; y=y-15 end
    y=y-4

    RC5D_AddLine(frame,row,"Physical DR","",y,true); row=row+1; y=y-17; shown=false
    for li=1,table.getn(lists) do
        for i=1,table.getn(lists[li]) do
            e=lists[li][i]
            if e and (e.kind=="percentDR" or e.kind=="physicalDR" or e.alsoPhysical) and (tonumber(e.value) or 0)>0 then
                RC5D_AddLine(frame,row,e.name or "Effect",tostring(e.value).."%",y,false)
                row=row+1; y=y-15; shown=true
            end
            if e and (tonumber(e.physicalTakenIncrease) or 0)>0 then
                RC5D_AddLine(frame,row,e.name or "Effect","+"..tostring(e.physicalTakenIncrease).."% taken",y,false)
                row=row+1; y=y-15; shown=true
            end
        end
    end
    if not shown then RC5D_AddLine(frame,row,"None detected","",y,false); row=row+1; y=y-15 end
    RC5D_AddLine(frame,row,"Effective",string.format("%.1f%%",physicalModel.effectivePct or 0),y,false); row=row+1; y=y-16

    RC5D_AddLine(frame,row,"Magic DR","",y,true); row=row+1; y=y-17; shown=false
    for li=1,table.getn(lists) do
        for i=1,table.getn(lists[li]) do
            e=lists[li][i]
            if e and (e.kind=="percentDR" or e.kind=="spellDR") and (tonumber(e.value) or 0)>0 then
                RC5D_AddLine(frame,row,e.name or "Effect",tostring(e.value).."%",y,false)
                row=row+1; y=y-15; shown=true
            elseif e and (e.kind=="schoolDR" or e.kind=="multiDR") and e.schools and (tonumber(e.value) or 0)>0 then
                RC5D_AddLine(frame,row,e.name or "Effect",tostring(e.value).."% "..RC6E_SchoolListText(e.schools),y,false)
                row=row+1; y=y-15; shown=true
            end
        end
    end
    if not shown then RC5D_AddLine(frame,row,"None detected","",y,false); row=row+1; y=y-15 end
    RC5D_AddLine(frame,row,"Base Effective",string.format("%.1f%%",magicBaseModel.effectivePct or 0),y,false)
end


-- ============================================================================
-- RC6f - active DR cooldowns + item DR + corrected PL talent values
-- ============================================================================

-- Project Legacy: no named talent-value overrides are injected here.

-- Extend the aura/item classifier rather than adding these cooldowns as passive
-- talents.  The live aura snapshot is the authority for active DR windows.
RC6F_PreviousClassifier = RC5_ClassifyEffect
RC5_ClassifyEffect = function(name, description, isDebuff)
    RC6F_E = RC6F_PreviousClassifier(name, description, isDebuff)
    RC6F_N = lower(tostring(name or ""))
    RC6F_D = lower(tostring(description or ""))
    RC6F_Pct = RC5_FirstPercent and RC5_FirstPercent(description or "") or nil

    -- Project Legacy: generic tooltip wording is the only authority here.
    if find(RC6F_D,"damage taken",1,true) and
       (find(RC6F_D,"decreas",1,true) or find(RC6F_D,"reduc",1,true) or find(RC6F_D,"less",1,true)) and RC6F_Pct then
        if find(RC6F_D,"physical damage taken",1,true) then
            RC6F_E.kind="physicalDR"
            RC6F_E.label="Physical damage reduction"
        elseif find(RC6F_D,"spell damage taken",1,true) or find(RC6F_D,"magic damage taken",1,true) then
            RC6F_E.kind="spellDR"
            RC6F_E.label="Magic damage reduction"
        else
            RC6F_E.kind="percentDR"
            RC6F_E.label="All damage reduction"
        end
        RC6F_E.value=RC6F_Pct
        RC6F_E.known=true
        RC6F_E.activationMode="activeAura"
    end
    return RC6F_E
end

-- Rebuild equipped-item DR scanning with the corrected classifier.  Scan both
-- the native inventory tooltip and the exact item hyperlink, but insert at most
-- one effect per equipped slot so private-server green text cannot double count.
RC5B_ScanEquippedDR = function()
    RC6F_Results={}
    RC6F_Tip=GetScanTooltip()
    for RC6F_Slot=1,19 do
        RC6F_Link=GetInventoryItemLink("player",RC6F_Slot)
        if RC6F_Link then
            RC6F_Effect=nil
            RC6F_Name=""
            RC6F_Desc=""

            RC6F_Tip:Hide(); RC6F_Tip:ClearLines()
            RC6F_Found=RC6F_Tip:SetInventoryItem("player",RC6F_Slot)
            if RC6F_Found and RC6F_Tip:NumLines()>0 then
                RC6F_Name,RC6F_Desc=RC5_ReadTooltipText(RC6F_Tip)
                RC6F_Try=RC5_ClassifyEffect(RC6F_Name,RC6F_Desc,false)
                if RC6F_Try and (RC6F_Try.kind=="percentDR" or RC6F_Try.kind=="physicalDR" or
                   RC6F_Try.kind=="spellDR" or RC6F_Try.kind=="schoolDR" or RC6F_Try.kind=="flatDR") then
                    RC6F_Effect=RC6F_Try
                end
            end

            if not RC6F_Effect then
                _,_,RC6F_ItemString=string.find(RC6F_Link,"|H(item:[^|]+)|h")
                if RC6F_ItemString then
                    RC6F_Tip:Hide(); RC6F_Tip:ClearLines()
                    RC5_SafeTooltipCall(function() RC6F_Tip:SetHyperlink(RC6F_ItemString) end)
                    RC6F_Name,RC6F_Desc=RC5_ReadTooltipText(RC6F_Tip)
                    RC6F_Try=RC5_ClassifyEffect(RC6F_Name,RC6F_Desc,false)
                    if RC6F_Try and (RC6F_Try.kind=="percentDR" or RC6F_Try.kind=="physicalDR" or
                       RC6F_Try.kind=="spellDR" or RC6F_Try.kind=="schoolDR" or RC6F_Try.kind=="flatDR") then
                        RC6F_Effect=RC6F_Try
                    end
                end
            end

            if RC6F_Effect then
                RC6F_Effect.source="item"
                RC6F_Effect.slot=RC6F_Slot
                if not RC6F_Effect.name or RC6F_Effect.name=="" then
                    _,_,RC6F_LinkedName=string.find(RC6F_Link,"%[(.-)%]")
                    RC6F_Effect.name=RC6F_LinkedName or ("Inventory Slot "..tostring(RC6F_Slot))
                end
                table.insert(RC6F_Results,RC6F_Effect)
            end
        end
    end
    RC6F_Tip:Hide()
    return RC6F_Results
end

-- The event math version changes because item DR and active cooldown semantics
-- can change a saved event's percentage model.  Reprocess older RC6 events when
-- they are viewed so Pie/Timeline/Details all use the same RC6f attribution.
RC6F_PreviousEnsureEventAttribution = RC6B_EnsureEventAttribution
function RC6B_EnsureEventAttribution(eventData)
    if not eventData then return eventData end
    if eventData.rc6MathVersion==7 then return eventData end
    eventData.rc6MathVersion=nil
    RC6F_Result=RC6F_PreviousEnsureEventAttribution(eventData)
    if RC6F_Result then RC6F_Result.rc6MathVersion=7 end
    return RC6F_Result
end

-- Diagnostics for the two pieces added in this pass: equipped item DR and
-- currently active cooldown/aura DR.  These commands deliberately report the
-- exact effects seen by the same context snapshot used by combat events.
RC6F_PreviousHandleSlash = MT.HandleSlash
function MT:HandleSlash(msg)
    RC6F_Cmd=lower(tostring(msg or ""))
    if RC6F_Cmd=="itemdr" then
        self:RefreshMitigationContextCache(true)
        Print("RC6f equipped item DR")
        RC6F_Shown=0
        for RC6F_I=1,table.getn(self.rc5EquipmentDR or {}) do
            RC6F_E=self.rc5EquipmentDR[RC6F_I]
            if RC6F_E then
                RC6F_Suffix=""
                if RC6F_E.kind=="physicalDR" then RC6F_Suffix=" Physical DR"
                elseif RC6F_E.kind=="spellDR" then RC6F_Suffix=" Magic DR"
                elseif RC6F_E.kind=="percentDR" then RC6F_Suffix=" All DR"
                elseif RC6F_E.kind=="flatDR" then RC6F_Suffix=" Flat DR" end
                Print((RC6F_E.name or "Unknown item").." = "..tostring(RC6F_E.value or 0)..(RC6F_E.kind=="flatDR" and "" or "%")..RC6F_Suffix)
                RC6F_Shown=RC6F_Shown+1
            end
        end
        if RC6F_Shown==0 then Print("No equipped direct-DR items detected.") end
        return
    elseif RC6F_Cmd=="activedr" or RC6F_Cmd=="cooldowndr" then
        self:RefreshMitigationContextCache(true)
        Print("RC6f active DR auras")
        RC6F_Shown=0
        for RC6F_I=1,table.getn(self.rc5PlayerBuffs or {}) do
            RC6F_E=self.rc5PlayerBuffs[RC6F_I]
            if RC6F_E and (RC6F_E.kind=="percentDR" or RC6F_E.kind=="physicalDR" or RC6F_E.kind=="spellDR" or RC6F_E.kind=="schoolDR" or RC6F_E.kind=="flatDR") then
                Print((RC6F_E.name or "Unknown aura").." = "..tostring(RC6F_E.value or 0)..(RC6F_E.kind=="flatDR" and " flat" or "% "..tostring(RC6F_E.kind)))
                RC6F_Shown=RC6F_Shown+1
            end
        end
        if RC6F_Shown==0 then Print("No active direct-DR auras detected.") end
        return
    elseif RC6F_Cmd=="drscan" or RC6F_Cmd=="talentdr" then
        -- Keep RC6e's detailed scan, but correct its version/help wording.
        self:RefreshMitigationContextCache(true)
        Print("RC6f DR talent scan - learned passive effects")
        RC6F_Shown=0
        for RC6F_I=1,table.getn(self.rc5DefensiveTalents or {}) do
            RC6F_E=self.rc5DefensiveTalents[RC6F_I]
            if RC6F_E and (RC6F_E.kind=="percentDR" or RC6F_E.kind=="physicalDR" or RC6F_E.kind=="spellDR" or RC6F_E.kind=="schoolDR") then
                RC6F_Extra=""
                if RC6F_E.schools then RC6F_Extra=" ["..RC6E_SchoolListText(RC6F_E.schools).."]" end
                Print((RC6F_E.name or "Unknown").." R"..tostring(RC6F_E.rank or "?").." = "..tostring(RC6F_E.value or 0).."% "..tostring(RC6F_E.kind)..RC6F_Extra)
                RC6F_Shown=RC6F_Shown+1
            end
        end
        if RC6F_Shown==0 then Print("No learned passive direct-DR talents detected.") end
        Print("Active/conditional DR is counted only while its aura is present and detected.")
        return
    end
    RC6F_PreviousHandleSlash(self,msg)
end

-- RC6f audit heading is updated in the existing /mt math printer above.


-- ============================================================================
-- RC6g - hardened equipped-item DR scanner for Vanilla/Octo private clients
-- ============================================================================
-- Some 1.12-derived clients populate GameTooltip correctly from SetInventoryItem
-- but return nil/false from the call.  RC6f treated that return value as a hard
-- failure, so valid green Equip text could be present while /mt itemdr reported
-- nothing.  RC6g trusts the populated tooltip lines, and also parses the raw
-- tooltip lines directly instead of depending on the general aura classifier.

RC6G_ParseDRLine = function(text)
    RC6G_Line = lower(tostring(text or ""))
    RC6G_Value = nil
    RC6G_Kind = nil

    -- Most specific forms first.
    _,_,RC6G_Value = string.find(RC6G_Line,"decreases physical damage taken by ([%d%.]+)%%")
    if not RC6G_Value then _,_,RC6G_Value = string.find(RC6G_Line,"reduces physical damage taken by ([%d%.]+)%%") end
    if RC6G_Value then return "physicalDR", tonumber(RC6G_Value) end

    _,_,RC6G_Value = string.find(RC6G_Line,"decreases spell damage taken by ([%d%.]+)%%")
    if not RC6G_Value then _,_,RC6G_Value = string.find(RC6G_Line,"reduces spell damage taken by ([%d%.]+)%%") end
    if not RC6G_Value then _,_,RC6G_Value = string.find(RC6G_Line,"decreases magic damage taken by ([%d%.]+)%%") end
    if not RC6G_Value then _,_,RC6G_Value = string.find(RC6G_Line,"reduces magic damage taken by ([%d%.]+)%%") end
    if RC6G_Value then return "spellDR", tonumber(RC6G_Value) end

    _,_,RC6G_Value = string.find(RC6G_Line,"decreases all damage taken by ([%d%.]+)%%")
    if not RC6G_Value then _,_,RC6G_Value = string.find(RC6G_Line,"reduces all damage taken by ([%d%.]+)%%") end
    if not RC6G_Value then _,_,RC6G_Value = string.find(RC6G_Line,"decreases damage taken by ([%d%.]+)%%") end
    if not RC6G_Value then _,_,RC6G_Value = string.find(RC6G_Line,"reduces damage taken by ([%d%.]+)%%") end
    if not RC6G_Value then _,_,RC6G_Value = string.find(RC6G_Line,"damage taken is reduced by ([%d%.]+)%%") end
    if RC6G_Value then return "percentDR", tonumber(RC6G_Value) end

    return nil, nil
end

RC6G_EffectFromTooltip = function(tip, fallbackName)
    if not tip or not tip.NumLines or (tip:NumLines() or 0) <= 0 then return nil end
    RC6G_TipName = tostring(fallbackName or "")
    RC6G_TipPrefix = tip:GetName() or "MainTankScanTooltip"
    for RC6G_LineIndex=1,(tip:NumLines() or 0) do
        RC6G_LeftFS = getglobal(RC6G_TipPrefix.."TextLeft"..RC6G_LineIndex)
        RC6G_RightFS = getglobal(RC6G_TipPrefix.."TextRight"..RC6G_LineIndex)
        RC6G_LeftText = RC6G_LeftFS and RC6G_LeftFS:GetText() or nil
        RC6G_RightText = RC6G_RightFS and RC6G_RightFS:GetText() or nil
        if RC6G_LineIndex==1 and RC6G_LeftText and RC6G_LeftText~="" then RC6G_TipName=RC5_TrimText(RC6G_LeftText) end

        RC6G_Kind,RC6G_Pct = RC6G_ParseDRLine(RC6G_LeftText)
        if not RC6G_Kind then RC6G_Kind,RC6G_Pct = RC6G_ParseDRLine(RC6G_RightText) end
        if RC6G_Kind and RC6G_Pct and RC6G_Pct>0 then
            RC6G_Effect = { name=RC6G_TipName, kind=RC6G_Kind, value=RC6G_Pct, known=true, source="item" }
            if RC6G_Kind=="physicalDR" then RC6G_Effect.label="Physical damage reduction"
            elseif RC6G_Kind=="spellDR" then RC6G_Effect.label="Magic damage reduction"
            else RC6G_Effect.label="All damage reduction" end
            return RC6G_Effect
        end
    end
    return nil
end

RC5B_ScanEquippedDR = function()
    RC6G_Results = {}
    RC6G_Tip = GetScanTooltip()

    for RC6G_Slot=1,19 do
        RC6G_Link = GetInventoryItemLink("player",RC6G_Slot)
        if RC6G_Link then
            RC6G_Effect = nil
            _,_,RC6G_LinkName = string.find(RC6G_Link,"%[(.-)%]")

            -- Path 1: native equipped-slot tooltip.  Deliberately ignore the
            -- SetInventoryItem return value; NumLines is the reliable signal.
            RC6G_Tip:Hide()
            RC6G_Tip:ClearLines()
            RC5_SafeTooltipCall(function() RC6G_Tip:SetInventoryItem("player",RC6G_Slot) end)
            if (RC6G_Tip:NumLines() or 0)>0 then
                RC6G_Effect = RC6G_EffectFromTooltip(RC6G_Tip,RC6G_LinkName)
            end

            -- Path 2: exact item hyperlink.  This frequently contains green
            -- Equip text that private-client SetInventoryItem omits.
            if not RC6G_Effect then
                _,_,RC6G_ItemString = string.find(RC6G_Link,"(item:[^|]+)")
                if RC6G_ItemString then
                    RC6G_Tip:Hide()
                    RC6G_Tip:ClearLines()
                    RC5_SafeTooltipCall(function() RC6G_Tip:SetHyperlink(RC6G_ItemString) end)
                    if (RC6G_Tip:NumLines() or 0)>0 then
                        RC6G_Effect = RC6G_EffectFromTooltip(RC6G_Tip,RC6G_LinkName)
                    end
                end
            end

            if RC6G_Effect then
                RC6G_Effect.slot = RC6G_Slot
                table.insert(RC6G_Results,RC6G_Effect)
            end
        end
    end
    RC6G_Tip:Hide()
    return RC6G_Results
end

-- Force the context cache to pick up gear changes immediately when requested.
RC6G_PreviousHandleSlash = MT.HandleSlash
function MT:HandleSlash(msg)
    RC6G_Cmd = lower(tostring(msg or ""))
    if RC6G_Cmd=="itemdr" then
        self.rc5ContextCacheAt=nil
        self:RefreshMitigationContextCache(true)
        Print("RC6g equipped item DR")
        RC6G_List=self.rc5EquipmentDR or {}
        if table.getn(RC6G_List)==0 then Print("No equipped direct-DR items detected.")
        else
            for RC6G_I=1,table.getn(RC6G_List) do
                RC6G_E=RC6G_List[RC6G_I]
                RC6G_Label="All DR"
                if RC6G_E.kind=="physicalDR" then RC6G_Label="Physical DR"
                elseif RC6G_E.kind=="spellDR" then RC6G_Label="Magic DR" end
                Print((RC6G_E.name or "Equipped item").." = "..tostring(RC6G_E.value or 0).."% "..RC6G_Label.." (slot "..tostring(RC6G_E.slot or "?")..")")
            end
        end
        return
    elseif RC6G_Cmd=="itemraw" then
        -- Diagnostic escape hatch: print the exact tooltip strings the scanner
        -- receives from equipped slots. Useful for unusual private-client items.
        RC6G_Tip=GetScanTooltip()
        Print("RC6g raw equipped-item tooltip scan")
        for RC6G_Slot=1,19 do
            RC6G_Link=GetInventoryItemLink("player",RC6G_Slot)
            if RC6G_Link then
                _,_,RC6G_LinkName=string.find(RC6G_Link,"%[(.-)%]")
                RC6G_Tip:Hide(); RC6G_Tip:ClearLines()
                RC5_SafeTooltipCall(function() RC6G_Tip:SetInventoryItem("player",RC6G_Slot) end)
                Print("Slot "..tostring(RC6G_Slot).." "..tostring(RC6G_LinkName or "item").." lines="..tostring(RC6G_Tip:NumLines() or 0))
                RC6G_Prefix=RC6G_Tip:GetName() or "MainTankScanTooltip"
                for RC6G_J=1,(RC6G_Tip:NumLines() or 0) do
                    RC6G_FS=getglobal(RC6G_Prefix.."TextLeft"..RC6G_J)
                    RC6G_Txt=RC6G_FS and RC6G_FS:GetText() or nil
                    if RC6G_Txt and RC6G_Txt~="" then Print("  "..RC6G_TrimForChat(RC6G_Txt)) end
                end
            end
        end
        RC6G_Tip:Hide()
        return
    end
    return RC6G_PreviousHandleSlash(self,msg)
end

-- Keep debug output short enough for the 1.12 chat frame.
function RC6G_TrimForChat(text)
    RC6G_T=string.gsub(tostring(text or ""),"|c%x%x%x%x%x%x%x%x","")
    RC6G_T=string.gsub(RC6G_T,"|r","")
    if string.len(RC6G_T)>180 then RC6G_T=string.sub(RC6G_T,1,180).."..." end
    return RC6G_T
end


-- ============================================================================
-- RC6i - fixed-line equipped item tooltip scanner
-- ============================================================================
-- Some Project Legacy/Octo-derived clients return NumLines()==0 for hidden
-- GameTooltip instances even when SetInventoryItem populated the named
-- TextLeftN/TextRightN font strings.  Do not trust NumLines here.  Probe a
-- fixed line range directly, then retry from the inventory hyperlink.
RC6I_GearTooltip = getglobal("MainTankGearTooltip") or CreateFrame("GameTooltip", "MainTankGearTooltip", nil, "GameTooltipTemplate")
RC6I_GearPrefix = "MainTankGearTooltip"
RC6I_GearTooltip:SetOwner(WorldFrame, "ANCHOR_NONE")
RC6I_MAX_TOOLTIP_LINES = 30

RC6I_ParseItemDRLine = function(text)
    local s = string.lower(tostring(text or ""))
    local _,_,v
    _,_,v = string.find(s, "decreases physical damage taken by (%d+)%%")
    if not v then _,_,v = string.find(s, "reduces physical damage taken by (%d+)%%") end
    if v then return "physicalDR", tonumber(v) end
    _,_,v = string.find(s, "decreases spell damage taken by (%d+)%%")
    if not v then _,_,v = string.find(s, "reduces spell damage taken by (%d+)%%") end
    if not v then _,_,v = string.find(s, "decreases magic damage taken by (%d+)%%") end
    if not v then _,_,v = string.find(s, "reduces magic damage taken by (%d+)%%") end
    if v then return "spellDR", tonumber(v) end
    _,_,v = string.find(s, "decreases all damage taken by (%d+)%%")
    if not v then _,_,v = string.find(s, "reduces all damage taken by (%d+)%%") end
    if not v then _,_,v = string.find(s, "decreases damage taken by (%d+)%%") end
    if not v then _,_,v = string.find(s, "reduces damage taken by (%d+)%%") end
    if not v then _,_,v = string.find(s, "damage taken is reduced by (%d+)%%") end
    if v then return "percentDR", tonumber(v) end
    return nil,nil
end

RC6I_ReadTooltipLines = function()
    local out = {}
    local i,left,right,lt,rt
    for i=1,RC6I_MAX_TOOLTIP_LINES do
        left = getglobal(RC6I_GearPrefix .. "TextLeft" .. i)
        right = getglobal(RC6I_GearPrefix .. "TextRight" .. i)
        lt = left and left:GetText() or nil
        rt = right and right:GetText() or nil
        if lt and lt ~= "" then table.insert(out, lt) end
        if rt and rt ~= "" and rt ~= lt then table.insert(out, rt) end
    end
    return out
end

RC6I_LoadInventoryTooltip = function(slot)
    local lines,link
    RC6I_GearTooltip:ClearLines()
    RC5_SafeTooltipCall(function() RC6I_GearTooltip:SetInventoryItem("player", slot) end)
    lines = RC6I_ReadTooltipLines()
    if table.getn(lines) == 0 then
        link = GetInventoryItemLink("player", slot)
        if link then
            RC6I_GearTooltip:ClearLines()
            RC5_SafeTooltipCall(function() RC6I_GearTooltip:SetHyperlink(link) end)
            lines = RC6I_ReadTooltipLines()
        end
    end
    return lines
end

RC5B_ScanEquippedDR = function()
    local results = {}
    local slot, lines, i, text, kind, value, name, link
    for slot=0,19 do
        link = GetInventoryItemLink("player", slot)
        if link then
            name = nil
            _,_,name = string.find(link, "%[(.-)%]")
            lines = RC6I_LoadInventoryTooltip(slot)
            for i=1,table.getn(lines) do
                text = lines[i]
                kind,value = RC6I_ParseItemDRLine(text)
                if kind and value and value > 0 then
                    table.insert(results, {name=name or "Equipped item", kind=kind, value=value, known=true, source="item", slot=slot})
                    break
                end
            end
        end
    end
    RC6I_GearTooltip:Hide()
    return results
end

RC6I_PreviousHandleSlash = MT.HandleSlash
function MT:HandleSlash(msg)
    local cmd = string.lower(tostring(msg or ""))
    if cmd == "itemdr" then
        self.rc5ContextCacheAt = nil
        self.rc5EquipmentDR = RC5B_ScanEquippedDR()
        Print("RC6i equipped item DR")
        if table.getn(self.rc5EquipmentDR or {}) == 0 then
            Print("No equipped direct-DR items detected. Use /mt itemraw.")
        else
            local i,e,label
            for i=1,table.getn(self.rc5EquipmentDR) do
                e=self.rc5EquipmentDR[i]
                label="All DR"
                if e.kind=="physicalDR" then label="Physical DR" elseif e.kind=="spellDR" then label="Magic DR" end
                Print((e.name or "Equipped item").." = "..tostring(e.value or 0).."% "..label.." (slot "..tostring(e.slot or "?")..")")
            end
        end
        return
    elseif cmd == "itemraw" then
        Print("RC6i raw gear tooltip scan (fixed-line probe)")
        local slot,lines,i,link,name
        for slot=0,19 do
            link=GetInventoryItemLink("player",slot)
            if link then
                name=nil; _,_,name=string.find(link,"%[(.-)%]")
                lines=RC6I_LoadInventoryTooltip(slot)
                Print("Slot "..tostring(slot).." "..tostring(name or "item").." textLines="..tostring(table.getn(lines)))
                for i=1,table.getn(lines) do
                    Print("  "..RC6G_TrimForChat(lines[i]))
                end
            end
        end
        RC6I_GearTooltip:Hide()
        return
    end
    return RC6I_PreviousHandleSlash(self,msg)
end


-- ============================================================================
-- RC6j - robust equipped-item tooltip source fallback
-- ============================================================================
-- RC6i proved that the private client can populate only a skeletal hidden
-- tooltip (for example just "Cloth") even though the normal character tooltip
-- shows the full green Equip text.  BetterCharacterStats works through its own
-- long-lived tooltip, so prefer that exact tooltip when present.  If it is not
-- available, fall back to the built-in GameTooltip, which is the tooltip the
-- player actually sees and therefore has the complete item description on this
-- client.  The MT hidden tooltip remains a final fallback.

RC6J_ReadNamedTooltip = function(tip, prefix)
    local out = {}
    local count = 0
    local i, left, right, lt, rt
    if tip and tip.NumLines then count = tip:NumLines() or 0 end
    if count < 1 then count = 30 end
    if count > 30 then count = 30 end
    for i=1,count do
        left = getglobal(prefix .. "TextLeft" .. i)
        right = getglobal(prefix .. "TextRight" .. i)
        lt = left and left:GetText() or nil
        rt = right and right:GetText() or nil
        if lt and lt ~= "" then table.insert(out, lt) end
        if rt and rt ~= "" and rt ~= lt then table.insert(out, rt) end
    end
    return out
end

RC6J_HasUsefulItemText = function(lines)
    local i, s
    if not lines then return false end
    for i=1,table.getn(lines) do
        s = string.lower(tostring(lines[i] or ""))
        if string.find(s, "equip:") or string.find(s, "damage taken") or string.find(s, "requires level") or string.find(s, "soulbound") or string.find(s, "unique") then
            return true
        end
    end
    return false
end

RC6J_ScanWithTooltip = function(tip, prefix, slot)
    local ok, lines
    if not tip then return nil end
    if tip.SetOwner then pcall(function() tip:SetOwner(WorldFrame, "ANCHOR_NONE") end) end
    if tip.ClearLines then pcall(function() tip:ClearLines() end) end
    ok = pcall(function() tip:SetInventoryItem("player", slot) end)
    if not ok then return nil end
    lines = RC6J_ReadNamedTooltip(tip, prefix)
    return lines
end

RC6J_LoadInventoryTooltip = function(slot)
    local tip, lines

    -- 1) Reuse BetterCharacterStats' exact scanner tooltip when that addon is
    -- installed.  This is the same object its helper.lua uses for gear stats.
    tip = getglobal("BetterCharacterStatsTooltip")
    if tip then
        lines = RC6J_ScanWithTooltip(tip, "BetterCharacterStatsTooltip", slot)
        if RC6J_HasUsefulItemText(lines) then return lines, "BCS" end
    end

    -- 2) Built-in GameTooltip.  On this client the visible character tooltip
    -- demonstrably contains all custom Project Legacy green Equip lines.
    if GameTooltip then
        lines = RC6J_ScanWithTooltip(GameTooltip, "GameTooltip", slot)
        if RC6J_HasUsefulItemText(lines) then
            pcall(function() GameTooltip:Hide() end)
            return lines, "GameTooltip"
        end
        pcall(function() GameTooltip:Hide() end)
    end

    -- 3) MT's own hidden tooltip as a last fallback.
    if RC6I_GearTooltip then
        lines = RC6J_ScanWithTooltip(RC6I_GearTooltip, RC6I_GearPrefix, slot)
        if RC6J_HasUsefulItemText(lines) then return lines, "MTTooltip" end
    end

    return lines or {}, "none"
end

RC5B_ScanEquippedDR = function()
    local results = {}
    local slot, lines, i, text, kind, value, name, link, source
    for slot=0,19 do
        link = GetInventoryItemLink("player", slot)
        if link then
            name = nil
            _,_,name = string.find(link, "%[(.-)%]")
            lines, source = RC6J_LoadInventoryTooltip(slot)
            for i=1,table.getn(lines or {}) do
                text = lines[i]
                kind,value = RC6I_ParseItemDRLine(text)
                if kind and value and value > 0 then
                    table.insert(results, {
                        name=name or "Equipped item",
                        kind=kind,
                        value=value,
                        known=true,
                        source="item",
                        slot=slot,
                        tooltipSource=source
                    })
                    break
                end
            end
        end
    end
    if RC6I_GearTooltip then pcall(function() RC6I_GearTooltip:Hide() end) end
    if GameTooltip then pcall(function() GameTooltip:Hide() end) end
    return results
end

RC6J_PreviousHandleSlash = MT.HandleSlash
function MT:HandleSlash(msg)
    local cmd = string.lower(tostring(msg or ""))
    if cmd == "itemraw" then
        Print("RC6j raw gear tooltip scan (BCS/GameTooltip fallback)")
        local slot,lines,i,link,name,source
        for slot=0,19 do
            link=GetInventoryItemLink("player",slot)
            if link then
                name=nil; _,_,name=string.find(link,"%[(.-)%]")
                lines,source=RC6J_LoadInventoryTooltip(slot)
                Print("Slot "..tostring(slot).." "..tostring(name or "item").." source="..tostring(source).." textLines="..tostring(table.getn(lines or {})))
                for i=1,table.getn(lines or {}) do
                    Print("  "..RC6G_TrimForChat(lines[i]))
                end
            end
        end
        if RC6I_GearTooltip then pcall(function() RC6I_GearTooltip:Hide() end) end
        if GameTooltip then pcall(function() GameTooltip:Hide() end) end
        return
    end
    return RC6J_PreviousHandleSlash(self,msg)
end


-- ============================================================================
-- RC6k - consolidated DR sources / active aura reliability / release cleanup
-- ============================================================================
-- This pass consolidates the live-tested RC6 DR paths:
--   * Sanctuary rank-aware Flat DR
--   * passive talent DR discovered from actual tooltip wording
--   * active cooldown DR (Shield Wall / Divine Protection / Barkskin)
--   * BetterCharacterStats-backed equipped item DR
--   * one per-event context model consumed by Pie / Timeline / Details / saves
-- ============================================================================

-- Project Legacy: keep the named talent registry empty.

-- Active cooldowns are aura-driven.  The tooltip parser remains the first
-- source of truth, but Vanilla-derived clients sometimes expose only an icon
-- for hidden player-buff tooltips.  Learn the spellbook texture for the three
-- confirmed cooldowns and use that texture only as a fallback identification.
RC6K_ACTIVE_DR = {
    -- Project Legacy: intentionally empty; no spell-name-specific DR values.
}

RC6K_GetActiveDRTextureMap = function()
    local map = {}
    local i, name, texture, key, rule
    if type(GetSpellName) ~= "function" or type(GetSpellTexture) ~= "function" then return map end
    i = 1
    while true do
        name = GetSpellName(i, BOOKTYPE_SPELL or "spell")
        if not name then break end
        key = lower(tostring(name))
        rule = RC6K_ACTIVE_DR[key]
        if rule then
            texture = GetSpellTexture(i, BOOKTYPE_SPELL or "spell")
            if texture then map[lower(tostring(texture))] = rule end
        end
        i = i + 1
    end
    return map
end

RC6K_PreviousScanPlayerBuffs = RC5B_ScanPlayerBuffs
function RC5B_ScanPlayerBuffs()
    local results = RC6K_PreviousScanPlayerBuffs()
    local textureMap = RC6K_GetActiveDRTextureMap()
    local i, e, rule, textureKey, n
    for i=1,table.getn(results or {}) do
        e = results[i]
        if e then
            n = lower(tostring(e.name or ""))
            rule = RC6K_ACTIVE_DR[n]
            if not rule and e.texture then
                textureKey = lower(tostring(e.texture))
                rule = textureMap[textureKey]
            end
            if rule then
                -- The active aura itself is the condition.  Never infer these
                -- from the learned talent/spell alone.
                e.name = rule.name
                e.kind = rule.kind
                e.value = rule.value
                e.known = true
                e.source = "buff"
                e.activationMode = "activeAura"
                if rule.kind == "physicalDR" then
                    e.label = "Active physical-damage reduction"
                else
                    e.label = "Active all-damage reduction"
                end
            end
        end
    end
    return results
end

-- Final equipped-item scanner: preserve the RC6j path that succeeded in live
-- testing. BetterCharacterStats' long-lived tooltip is preferred because this
-- private client exposes custom green Equip text there while fresh hidden
-- tooltips may contain only armor class/type text.
RC6K_ScanEquippedDR = function()
    local results = {}
    local slot, lines, i, text, kind, value, name, link, source
    for slot=0,19 do
        link = GetInventoryItemLink("player", slot)
        if link then
            name = nil
            _,_,name = string.find(link, "%[(.-)%]")
            lines, source = RC6J_LoadInventoryTooltip(slot)
            for i=1,table.getn(lines or {}) do
                text = lines[i]
                kind,value = RC6I_ParseItemDRLine(text)
                if kind and value and value > 0 then
                    table.insert(results, {
                        name=name or "Equipped item",
                        kind=kind,
                        value=value,
                        known=true,
                        source="item",
                        slot=slot,
                        tooltipSource=source
                    })
                    break
                end
            end
        end
    end
    if RC6I_GearTooltip then pcall(function() RC6I_GearTooltip:Hide() end) end
    if GameTooltip then pcall(function() GameTooltip:Hide() end) end
    return results
end
RC5B_ScanEquippedDR = RC6K_ScanEquippedDR

-- Make the current source model a new event-math generation.  Saved fights
-- retain their original per-event context snapshots; reopening them re-runs
-- attribution from that saved context rather than from the player's current
-- gear/talents/buffs.  This is what keeps Pie/Timeline/Details consistent.
RC6K_PreviousEnsureEventAttribution = RC6B_EnsureEventAttribution
function RC6B_EnsureEventAttribution(eventData)
    local result
    if not eventData then return eventData end
    if eventData.rc6MathVersion == 8 then return eventData end
    eventData.rc6MathVersion = nil
    result = RC6K_PreviousEnsureEventAttribution(eventData)
    if result then result.rc6MathVersion = 8 end
    return result
end

-- Compact debug output for the exact sources used by the next combat event.
RC6K_PreviousHandleSlash = MT.HandleSlash
function MT:HandleSlash(msg)
    local cmd = lower(tostring(msg or ""))
    local i, e, label, shown
    if cmd == "itemdr" then
        self.rc5ContextCacheAt = nil
        self.rc5EquipmentDR = RC6K_ScanEquippedDR()
        Print("Equipped item DR")
        if table.getn(self.rc5EquipmentDR or {}) == 0 then
            Print("No equipped direct-DR items detected. Use /mt itemraw.")
        else
            for i=1,table.getn(self.rc5EquipmentDR) do
                e = self.rc5EquipmentDR[i]
                label = "All DR"
                if e.kind == "physicalDR" then label = "Physical DR"
                elseif e.kind == "spellDR" then label = "Magic DR" end
                Print((e.name or "Equipped item").." = "..tostring(e.value or 0).."% "..label.." ("..tostring(e.tooltipSource or "tooltip")..")")
            end
        end
        return
    elseif cmd == "activedr" or cmd == "cooldowndr" then
        self.rc5ContextCacheAt = nil
        self:RefreshMitigationContextCache(true)
        Print("Active DR auras")
        shown = 0
        for i=1,table.getn(self.rc5PlayerBuffs or {}) do
            e = self.rc5PlayerBuffs[i]
            if e and (e.kind=="percentDR" or e.kind=="physicalDR" or e.kind=="spellDR" or e.kind=="schoolDR" or e.kind=="flatDR") then
                if e.activationMode == "activeAura" or RC6K_ACTIVE_DR[lower(tostring(e.name or ""))] then
                    label = tostring(e.kind)
                    if e.kind=="percentDR" then label="All DR"
                    elseif e.kind=="physicalDR" then label="Physical DR"
                    elseif e.kind=="spellDR" then label="Magic DR"
                    elseif e.kind=="flatDR" then label="Flat DR" end
                    Print((e.name or "Active aura").." = "..tostring(e.value or 0)..(e.kind=="flatDR" and " flat " or "% ")..label)
                    shown = shown + 1
                end
            end
        end
        if shown == 0 then Print("No active direct-DR cooldown auras detected.") end
        return
    elseif cmd == "drscan" or cmd == "talentdr" then
        self.rc5ContextCacheAt = nil
        self:RefreshMitigationContextCache(true)
        Print("DR talent scan - learned passive effects")
        shown = 0
        for i=1,table.getn(self.rc5DefensiveTalents or {}) do
            e = self.rc5DefensiveTalents[i]
            if e and (e.kind=="percentDR" or e.kind=="physicalDR" or e.kind=="spellDR" or e.kind=="schoolDR") then
                label = ""
                if e.schools then label=" ["..RC6E_SchoolListText(e.schools).."]" end
                Print((e.name or "Unknown").." R"..tostring(e.rank or "?").." = "..tostring(e.value or 0).."% "..tostring(e.kind)..label)
                shown = shown + 1
            end
        end
        if shown == 0 then Print("No learned passive direct-DR talents detected.") end
        Print("Conditional DR is counted only while its active aura is present; values come from Project Legacy tooltip text.")
        return
    end
    return RC6K_PreviousHandleSlash(self,msg)
end

-- Fix the user-visible math audit generation label without duplicating the
-- entire audit formatter.  Existing handler text is replaced below in-source
-- during the RC6k packaging step as well, so either entry path reports RC6k.

-- ============================================================================
-- RC6n - Sanctuary attribution priority / continuity fix
--
-- Live Swampwalker testing exposed a bad edge case where an already-known
-- Rank 4 Sanctuary (+ Guardian's Favor = 36 Flat DR) could briefly become
-- "rank unresolved" after the short recent-cast window expired.  RC6d's
-- combat inference could then choose Rank 3 (24 effective flat) simply because
-- that candidate also fit one integer-rounded landed hit.  That made a stable
-- buff appear to change strength for a single event.
--
-- RC6n makes a confirmed active Sanctuary rank sticky for the lifetime of the
-- continuous aura.  It is replaced immediately by a newly confirmed aura/cast
-- rank and cleared as soon as Sanctuary is no longer present.  Combat inference
-- is now only a last resort when no rank has ever been confirmed for the
-- currently-active aura.
-- ============================================================================

RC6N_PreviousScanPlayerBuffs = RC5B_ScanPlayerBuffs
function RC5B_ScanPlayerBuffs()
    RC6N_Results = RC6N_PreviousScanPlayerBuffs()
    RC6N_FoundSanctuary = false
    RC6N_I = 1
    while RC6N_I <= table.getn(RC6N_Results or {}) do
        RC6N_E = RC6N_Results[RC6N_I]
        if RC6N_E and RC6N_E.kind == "flatDR" and find(lower(tostring(RC6N_E.name or "")), "blessing of sanctuary", 1, true) then
            RC6N_FoundSanctuary = true
            RC6N_Rank = tonumber(RC6N_E.rank) or 0

            -- Any exact rank learned from the aura tooltip or a recent local
            -- cast becomes authoritative for the rest of this continuous aura.
            if RC6N_Rank >= 1 and RC6N_Rank <= 4 then
                MT.rc6nActiveSanctuaryRank = RC6N_Rank
                MT.rc6nActiveSanctuaryRankSource = RC6N_E.rankSource or "confirmed aura"
            elseif tonumber(MT.rc6nActiveSanctuaryRank) and tonumber(MT.rc6nActiveSanctuaryRank) >= 1 and tonumber(MT.rc6nActiveSanctuaryRank) <= 4 then
                -- Hidden Vanilla buff tooltips sometimes stop exposing enough
                -- information to resolve the rank.  Do NOT downgrade the buff
                -- by combat inference while the same aura is continuously up.
                RC6N_Rank = tonumber(MT.rc6nActiveSanctuaryRank)
                RC6N_Base = RC5B_SANCTUARY_BASE[RC6N_Rank]
                if RC6N_Base then
                    RC6N_E.rank = RC6N_Rank
                    RC6N_E.value = RC6N_Base
                    RC6N_E.baseValue = RC6N_Base
                    RC6N_E.sanctuaryRankUnknown = nil
                    RC6N_E.rankSource = MT.rc6nActiveSanctuaryRankSource or "continuous aura"
                    RC6N_E.label = "Sanctuary Rank " .. tostring(RC6N_Rank) .. " / " .. tostring(RC6N_Base) .. " base flat"
                end
            end
        end
        RC6N_I = RC6N_I + 1
    end

    -- Once Sanctuary disappears, the next Sanctuary aura starts a fresh rank
    -- lifetime.  This preserves correct Rank 1 -> Rank 4 swaps while preventing
    -- a stale rank from surviving an actual buff loss/recast later.
    if not RC6N_FoundSanctuary then
        MT.rc6nActiveSanctuaryRank = nil
        MT.rc6nActiveSanctuaryRankSource = nil
    end
    return RC6N_Results
end

-- When a local cast is captured, also seed the continuous-aura authority now.
-- The normal scanner still verifies the aura is actually present before combat
-- context snapshots use it.
RC6N_PreviousRecordSanctuaryCast = RC6D_RecordSanctuaryCast
function RC6D_RecordSanctuaryCast(rank, source)
    RC6N_PreviousRecordSanctuaryCast(rank, source)
    RC6N_Rank = tonumber(rank) or 0
    if RC6N_Rank >= 1 and RC6N_Rank <= 4 then
        MT.rc6nActiveSanctuaryRank = RC6N_Rank
        MT.rc6nActiveSanctuaryRankSource = source or "cast"
    end
end

-- Compact DR page cleanup: keep the same math, but shorten "Base Effective"
-- to "Effective" so the value column does not hang outside the legacy frame.
RC6N_PreviousUpdateDRWindow = MT.UpdateDRWindow
function MT:UpdateDRWindow()
    RC6N_Frame = RC6N_PreviousUpdateDRWindow(self)
    RC6N_Frame = self.drFrame or RC6N_Frame
    if RC6N_Frame and RC6N_Frame.drRows then
        RC6N_I = 1
        while RC6N_I <= table.getn(RC6N_Frame.drRows) do
            RC6N_Row = RC6N_Frame.drRows[RC6N_I]
            if RC6N_Row and RC6N_Row.label and RC6N_Row.label.GetText and RC6N_Row.label:GetText() == "Base Effective" then
                RC6N_Row.label:SetText("Effective")
            end
            RC6N_I = RC6N_I + 1
        end
    end
    return RC6N_Frame
end

-- New math generation so saved fights recorded by RC6m can be recalculated
-- through the corrected Sanctuary-rank continuity model without rewriting the
-- event's saved mitigation context from today's gear/talents.
RC6N_PreviousEnsureEventAttribution = RC6B_EnsureEventAttribution
function RC6B_EnsureEventAttribution(eventData)
    if not eventData then return eventData end
    if eventData.rc6MathVersion == 9 then return eventData end
    eventData.rc6MathVersion = nil
    RC6N_Result = RC6N_PreviousEnsureEventAttribution(eventData)
    if RC6N_Result then RC6N_Result.rc6MathVersion = 9 end
    return RC6N_Result
end



-- ============================================================================
-- RC6o - dual-wield-safe white-swing constraints + compact UI cleanup
-- ============================================================================

-- Normal landed white attacks do not identify MH vs OH in the classic combat
-- text.  RC6n's DR hard-anchor only stored the main-hand UnitDamage range,
-- which could incorrectly clamp a legitimate off-hand hit into the MH range.
-- Preserve both ranges and use the union as the safe normal-white constraint.
-- Avoidance already uses the combined MH/OH midpoint memory, so this keeps the
-- DR attribution and the older dual-wield avoidance model compatible.
function RC6B_SnapshotWhiteSwingRange(eventData)
    if not eventData or (eventData.school or "Physical") ~= "Physical" or eventData.ability ~= "Melee" then return end
    RC6O_Memory = MT.targetDamageMemory and MT.targetDamageMemory[eventData.source]
    if not RC6O_Memory then return end

    RC6O_MHLow = tonumber(RC6O_Memory.minHit) or 0
    RC6O_MHHigh = tonumber(RC6O_Memory.maxHit) or 0
    RC6O_OHLow = tonumber(RC6O_Memory.offMinHit) or 0
    RC6O_OHHigh = tonumber(RC6O_Memory.offMaxHit) or 0

    if RC6O_MHLow > 0 and RC6O_MHHigh >= RC6O_MHLow then
        eventData.rawHintMHLow = RC6O_MHLow
        eventData.rawHintMHHigh = RC6O_MHHigh
        eventData.rawHintDualWield = false

        RC6O_Low = RC6O_MHLow
        RC6O_High = RC6O_MHHigh
        RC6O_Avg = (RC6O_MHLow + RC6O_MHHigh) / 2

        if RC6O_Memory.dualWield and RC6O_OHLow > 0 and RC6O_OHHigh >= RC6O_OHLow then
            eventData.rawHintDualWield = true
            eventData.rawHintOHLow = RC6O_OHLow
            eventData.rawHintOHHigh = RC6O_OHHigh
            if RC6O_OHLow < RC6O_Low then RC6O_Low = RC6O_OHLow end
            if RC6O_OHHigh > RC6O_High then RC6O_High = RC6O_OHHigh end
            RC6O_Avg = (((RC6O_MHLow + RC6O_MHHigh) / 2) + ((RC6O_OHLow + RC6O_OHHigh) / 2)) / 2
        end

        eventData.rawHintLow = RC6O_Low
        eventData.rawHintHigh = RC6O_High
        eventData.rawHintAverage = RC6O_Avg
        eventData.rawHintSource = RC6O_Memory.source or "UnitDamage(target)"
    end
end

function RC6B_GetWhiteSwingRange(eventData)
    if not eventData or (eventData.school or "Physical") ~= "Physical" or eventData.ability ~= "Melee" then return nil,nil,nil end
    if eventData.critical or eventData.crushing then return nil,nil,nil end

    RC6O_Low = tonumber(eventData.rawHintLow)
    RC6O_High = tonumber(eventData.rawHintHigh)
    RC6O_Avg = tonumber(eventData.rawHintAverage)
    if RC6O_Low and RC6O_High and RC6O_Low > 0 and RC6O_High >= RC6O_Low then
        if not RC6O_Avg then RC6O_Avg = (RC6O_Low + RC6O_High) / 2 end
        return RC6O_Avg, RC6O_Low, RC6O_High
    end

    RC6O_Memory = MT.targetDamageMemory and MT.targetDamageMemory[eventData.source]
    if not RC6O_Memory then return nil,nil,nil end
    RC6O_MHLow = tonumber(RC6O_Memory.minHit) or 0
    RC6O_MHHigh = tonumber(RC6O_Memory.maxHit) or 0
    if RC6O_MHLow <= 0 or RC6O_MHHigh < RC6O_MHLow then return nil,nil,nil end

    RC6O_Low = RC6O_MHLow
    RC6O_High = RC6O_MHHigh
    RC6O_Avg = (RC6O_MHLow + RC6O_MHHigh) / 2
    RC6O_OHLow = tonumber(RC6O_Memory.offMinHit) or 0
    RC6O_OHHigh = tonumber(RC6O_Memory.offMaxHit) or 0
    if RC6O_Memory.dualWield and RC6O_OHLow > 0 and RC6O_OHHigh >= RC6O_OHLow then
        if RC6O_OHLow < RC6O_Low then RC6O_Low = RC6O_OHLow end
        if RC6O_OHHigh > RC6O_High then RC6O_High = RC6O_OHHigh end
        RC6O_Avg = (((RC6O_MHLow + RC6O_MHHigh) / 2) + ((RC6O_OHLow + RC6O_OHHigh) / 2)) / 2
    end
    return RC6O_Avg, RC6O_Low, RC6O_High
end

-- Make every standard MT button use the same clean near-black surface while
-- retaining pfUI borders, fonts and hover/pushed feedback.
RC6O_PreviousStyleLegacyButton = E.StyleLegacyButtonBase
E.StyleLegacyButtonOverride = function(button)
    if not button then return end
    RC6O_WasStyled = button.mtLegacyStyled
    if not RC6O_WasStyled then RC6O_PreviousStyleLegacyButton(button) end

    if button.SetBackdrop then
        button:SetBackdrop(MT_LEGACY_BACKDROP)
        button:SetBackdropColor(0.01, 0.01, 0.01, 0.96)
        RC6O_ER, RC6O_EG, RC6O_EB, RC6O_EA = GetLegacyBorderColor()
        button:SetBackdropBorderColor(RC6O_ER, RC6O_EG, RC6O_EB, RC6O_EA)
    end
    if button.backdrop and button.backdrop.SetBackdropColor then
        button.backdrop:SetBackdropColor(0.01, 0.01, 0.01, 0.96)
    end
end

-- Final page-selector wording: both graphs use the same short neutral label.
RC6O_PreviousUpdatePieWindow = MT.UpdatePieWindow
function MT:UpdatePieWindow()
    RC6O_PreviousUpdatePieWindow(self)
    if self.pieFrame and self.pieFrame.modeButton then
        self.pieFrame.modeButton:SetText("View: " .. (self.pieMode or "RAW"))
    end
end

RC6O_PreviousUpdateTimelineWindow = MT.UpdateTimelineWindow
function MT:UpdateTimelineWindow()
    RC6O_PreviousUpdateTimelineWindow(self)
    if self.timelineFrame and self.timelineFrame.modeButton then
        self.timelineFrame.modeButton:SetText("View: " .. (self.timelineMode or "RAW"))
    end
end

-- Re-style already-created buttons too, so /reload is not required merely to
-- see the black-button cleanup after one of the analysis pages already exists.
function RC6O_BlackenFrameButtons(frame)
    if not frame or not frame.GetChildren then return end
    RC6O_Children = {frame:GetChildren()}
    RC6O_I = 1
    while RC6O_I <= table.getn(RC6O_Children) do
        RC6O_Child = RC6O_Children[RC6O_I]
        if RC6O_Child and RC6O_Child.GetObjectType and RC6O_Child:GetObjectType() == "Button" then
            StyleLegacyButton(RC6O_Child)
        end
        RC6O_I = RC6O_I + 1
    end
end

RC6O_PreviousUpdateDRWindow = MT.UpdateDRWindow
function MT:UpdateDRWindow()
    RC6O_Frame = RC6O_PreviousUpdateDRWindow(self)
    RC6O_Frame = self.drFrame or RC6O_Frame
    if RC6O_Frame then RC6O_BlackenFrameButtons(RC6O_Frame) end
    return RC6O_Frame
end


-- ============================================================================
-- RC6p - selector button visual cleanup
-- ============================================================================
-- UIPanelButtonTemplate can leave its red normal/pushed artwork visible above
-- our black backdrop.  The Timeline/Pie View selector is intentionally a plain
-- black MT control, matching the rest of the compact analysis UI.
function RC6P_ForceBlackSelector(button)
    if not button then return end
    if button.SetNormalTexture then button:SetNormalTexture("") end
    if button.SetPushedTexture then button:SetPushedTexture("") end
    if button.SetDisabledTexture then button:SetDisabledTexture("") end
    if button.SetBackdrop then
        button:SetBackdrop(MT_LEGACY_BACKDROP)
        button:SetBackdropColor(0.01, 0.01, 0.01, 0.98)
        RC6P_ER, RC6P_EG, RC6P_EB, RC6P_EA = GetLegacyBorderColor()
        button:SetBackdropBorderColor(RC6P_ER, RC6P_EG, RC6P_EB, RC6P_EA)
    end
    if button.backdrop and button.backdrop.SetBackdropColor then
        button.backdrop:SetBackdropColor(0.01, 0.01, 0.01, 0.98)
    end
    if button.GetFontString and button:GetFontString() then
        RC6P_FS = button:GetFontString()
        -- NAVPOLISH4: View: RAW/PHYSICAL/MAGIC is a neutral action selector,
        -- not a selected tab. Keep its text white through every refresh.
        RC6P_FS:SetTextColor(1.00, 1.00, 1.00)
    end
end

RC6P_PreviousUpdatePieWindow = MT.UpdatePieWindow
function MT:UpdatePieWindow()
    RC6P_PreviousUpdatePieWindow(self)
    if self.pieFrame and self.pieFrame.modeButton then
        RC6P_ForceBlackSelector(self.pieFrame.modeButton)
    end
end

RC6P_PreviousUpdateTimelineWindow = MT.UpdateTimelineWindow
function MT:UpdateTimelineWindow()
    RC6P_PreviousUpdateTimelineWindow(self)
    if self.timelineFrame and self.timelineFrame.modeButton then
        RC6P_ForceBlackSelector(self.timelineFrame.modeButton)
    end
end


-- ============================================================================
-- RC6q - school-specific Flat DR display aggregation
-- ============================================================================
-- Sanctuary applies to both physical and spell damage on Project Legacy.  RC6's
-- event records already snapshot flat DR correctly, but the consolidated
-- display snapshot only copied the all-schools flat total.  Specialized views
-- (especially MAGIC Pie) therefore saw nil/0 for magicFlatDR even though the
-- underlying Blast Wave/etc. events had Flat DR.  Rebuild both split totals
-- from the same authoritative event stream used by the math audit.
RC6Q_PreviousGetDisplayData = MT.GetDisplayData
function MT:GetDisplayData()
    local data = RC6Q_PreviousGetDisplayData(self)
    if not data then return data end
    local sums = RC6_SumEventDR(self:GetDisplayEvents() or {})
    data.flatDR = sums.flat or 0
    data.physicalFlatDR = sums.physicalFlat or 0
    data.magicFlatDR = sums.magicFlat or 0
    data.physicalDR = sums.physical or 0
    data.magicDR = sums.magic or 0
    return data
end


-- ============================================================================
-- RC6r - live Pie refresh + authoritative school-specific Flat DR aggregation
-- ============================================================================
-- RC6q split Flat DR using RC6_SumEventDR(), an older RC6 helper that still
-- called the first-generation attribution routine.  Later RC6 builds moved the
-- authoritative math to RC6B_EnsureEventAttribution(), so specialized Pie views
-- could lose Sanctuary Flat DR even while RAW/event math remained correct.
-- Always split Flat DR from the final per-event attribution used by /mt math.
function RC6R_SumFinalEventDR(events)
    RC6R_Sums = {flat=0, physicalFlat=0, magicFlat=0, physical=0, magic=0}
    RC6R_I = 1
    while RC6R_I <= table.getn(events or {}) do
        RC6R_E = events[RC6R_I]
        if RC6R_E then
            RC6B_EnsureEventAttribution(RC6R_E)
            RC6R_Flat = tonumber(RC6R_E.flatDR) or 0
            RC6R_Phys = tonumber(RC6R_E.physicalDR) or 0
            RC6R_Magic = tonumber(RC6R_E.magicDR) or 0
            RC6R_Sums.flat = RC6R_Sums.flat + RC6R_Flat
            RC6R_Sums.physical = RC6R_Sums.physical + RC6R_Phys
            RC6R_Sums.magic = RC6R_Sums.magic + RC6R_Magic
            if (RC6R_E.school or "Physical") == "Physical" then
                RC6R_Sums.physicalFlat = RC6R_Sums.physicalFlat + RC6R_Flat
            else
                RC6R_Sums.magicFlat = RC6R_Sums.magicFlat + RC6R_Flat
            end
        end
        RC6R_I = RC6R_I + 1
    end
    return RC6R_Sums
end

RC6R_PreviousGetDisplayData = MT.GetDisplayData
function MT:GetDisplayData()
    RC6R_Data = RC6R_PreviousGetDisplayData(self)
    if not RC6R_Data then return RC6R_Data end
    RC6R_Sums = RC6R_SumFinalEventDR(self:GetDisplayEvents() or {})
    RC6R_Data.flatDR = RC6R_Sums.flat or 0
    RC6R_Data.physicalFlatDR = RC6R_Sums.physicalFlat or 0
    RC6R_Data.magicFlatDR = RC6R_Sums.magicFlat or 0
    RC6R_Data.physicalDR = RC6R_Sums.physical or 0
    RC6R_Data.magicDR = RC6R_Sums.magic or 0
    return RC6R_Data
end

-- Timeline already refreshes directly when every combat event is recorded.
-- Pie rendering is a little heavier, so mark it dirty on each event and batch
-- redraws to at most four times per second. MTPie reuses its existing textures,
-- avoiding continuous frame/texture creation while still feeling live.
RC6R_PreviousRecordEvent = MT.RecordEvent
function MT:RecordEvent(eventData)
    RC6R_PreviousRecordEvent(self, eventData)
    if self.pieFrame and self.pieFrame:IsVisible() then
        self.rc6rPieDirty = true
    end
end

RC6R_PreviousEventOnUpdate = eventFrame:GetScript("OnUpdate")
eventFrame:SetScript("OnUpdate", function()
    if RC6R_PreviousEventOnUpdate then RC6R_PreviousEventOnUpdate() end
    if MT.rc6rPieDirty and MT.pieFrame and MT.pieFrame:IsVisible() then
        RC6R_Now = GetTime()
        if not MT.rc6rNextPieRefresh or RC6R_Now >= MT.rc6rNextPieRefresh then
            MT.rc6rPieDirty = nil
            MT.rc6rNextPieRefresh = RC6R_Now + 0.25
            MT:UpdatePieWindow()
        end
    end
end)


-- ============================================================================
-- RC6s - persistent per-event mitigation snapshots + reload-safe DR Pie
-- ============================================================================
-- RC6 mitigation used contextID -> MT.mitigationContexts for its historical
-- lookup.  That normally survives SavedVariables, but it leaves old events
-- dependent on a second mutable table during /reload and on aura/tool-tip state
-- when contexts are repaired/re-evaluated.  Store the complete mitigation
-- context on the event itself.  Pie/Timeline/Details can then reconstruct an
-- old hit from exactly what was active for THAT hit, regardless of mounting,
-- current buffs, gear changes, or a UI reload.

RC6S_PreviousContextForEvent = RC6_ContextForEvent
function RC6_ContextForEvent(eventData)
    if eventData and type(eventData.rc6ContextSnapshot) == "table" then
        return eventData.rc6ContextSnapshot
    end
    return RC6S_PreviousContextForEvent(eventData)
end

function RC6S_AttachContextSnapshot(eventData)
    if not eventData or type(eventData) ~= "table" then return eventData end
    if type(eventData.rc6ContextSnapshot) == "table" then return eventData end
    if eventData.contextID and MT.mitigationContexts then
        RC6S_Context = MT.mitigationContexts[eventData.contextID]
        if type(RC6S_Context) == "table" then
            eventData.rc6ContextSnapshot = CopyTable(RC6S_Context)
        end
    elseif MT.rc5ActiveContext and type(MT.rc5ActiveContext) == "table" then
        eventData.rc6ContextSnapshot = CopyTable(MT.rc5ActiveContext)
    end
    return eventData
end

-- Snapshot immediately after an incoming damage event is constructed.  The
-- existing math has already used the same context; this simply makes it
-- self-contained for SavedVariables and later display refreshes.
RC6S_PreviousBuildDamageEvent = MT.BuildDamageEvent
function MT:BuildDamageEvent(mob, attack, amountTaken, blocked, resisted, absorbed, school, isCrit, hitType, ignoreArmor)
    RC6S_Event = RC6S_PreviousBuildDamageEvent(self, mob, attack, amountTaken, blocked, resisted, absorbed, school, isCrit, hitType, ignoreArmor)
    RC6S_AttachContextSnapshot(RC6S_Event)
    return RC6S_Event
end

-- Outcome events keep the exact mitigation snapshot too. Pure Dodge/Parry/Miss
-- receive no DR credit, while Full Block/Full Resist can legitimately preserve
-- earlier Flat/%DR and Armor layers before their terminal remainder.
RC6S_PreviousBuildAvoidanceEvent = MT.BuildAvoidanceEvent
function MT:BuildAvoidanceEvent(kind, mob, attack, postArmorAmount, school)
    RC6S_Event = RC6S_PreviousBuildAvoidanceEvent(self, kind, mob, attack, postArmorAmount, school)
    RC6S_AttachContextSnapshot(RC6S_Event)
    return RC6S_Event
end

function RC6S_BackfillEventList(events)
    RC6S_I = 1
    while RC6S_I <= table.getn(events or {}) do
        RC6S_AttachContextSnapshot(events[RC6S_I])
        RC6S_I = RC6S_I + 1
    end
end

-- On /reload, backfill RC6o-q era events from the persisted context table once,
-- then leave each event self-contained from this point forward.
RC6S_PreviousRestorePersistentData = MT.RestorePersistentData
function MT:RestorePersistentData()
    RC6S_PreviousRestorePersistentData(self)

    -- FR2 startup cleanup:
    -- FR1K format 5 persists one contextSnapshotPool and rehydrates compact
    -- fight events BEFORE this Core wrapper. Re-running the old RC6s backfill
    -- across Current + Overall + every fight therefore only rechecks thousands
    -- of already-self-contained events. Keep the legacy path for pre-FR1X DBs.
    if self.profile and (tonumber(self.profile.archiveFormatVersion) or 0) >= 5 and
       type(self.profile.contextSnapshotPool) == "table" then
        self.profile.rc6SnapshotBackfillVersion = 1
        return
    end

    if not self.profile or tonumber(self.profile.rc6SnapshotBackfillVersion) ~= 1 then
        RC6S_BackfillEventList(self.events)
        RC6S_BackfillEventList(self.overallEvents)
        RC6S_I = 1
        while RC6S_I <= table.getn(self.fights or {}) do
            RC6S_Fight = self.fights[RC6S_I]
            if RC6S_Fight and RC6S_Fight.events then RC6S_BackfillEventList(RC6S_Fight.events) end
            RC6S_I = RC6S_I + 1
        end
        if self.profile then self.profile.rc6SnapshotBackfillVersion = 1 end
        -- Only legacy backfill needs to re-bind changed SavedVariables.
        self:SyncPersistentData()
    end
end

-- One generation bump causes older RC6 events to be checked once after the
-- snapshot backfill.  The actual RC6n combat equations/order are unchanged.
RC6S_PreviousEnsureEventAttribution = RC6B_EnsureEventAttribution
function RC6B_EnsureEventAttribution(eventData)
    if not eventData then return eventData end
    RC6S_AttachContextSnapshot(eventData)
    if eventData.rc6MathVersion == 10 then return eventData end
    eventData.rc6MathVersion = nil
    RC6S_Result = RC6S_PreviousEnsureEventAttribution(eventData)
    if RC6S_Result then RC6S_Result.rc6MathVersion = 10 end
    return RC6S_Result
end


-- ============================================================================
-- RC6t - reload-safe Sanctuary rank + school-channel DR sanitizer
-- ============================================================================
-- Two reload edge cases were exposed by live testing:
--   1) A Sanctuary aura can survive /reload while the short-lived "recent cast"
--      rank memory does not.  On clients whose hidden aura tooltip omits rank,
--      /mt dr could therefore say None detected even though Sanctuary is active.
--   2) Re-attributing older/persisted events could leave a percent-DR amount in
--      the wrong display channel (magicDR on a Physical event, or vice versa).
--      An incoming event has one damage school, so its percent-DR attribution
--      must always live in the channel selected by that event's school.
--
-- RC6t persists the last confirmed active Sanctuary rank, restores it before
-- the first post-reload aura scan, and uses the newest saved event snapshot as
-- a migration fallback.  It also normalizes percent-DR channels after every
-- attribution pass without changing the total amount of DR prevented.
-- ============================================================================

function RC6T_ValidSanctuaryRank(rank)
    RC6T_R = tonumber(rank) or 0
    return RC6T_R >= 1 and RC6T_R <= 4
end

function RC6T_SanctuaryRankFromContext(context)
    if type(context) ~= "table" then return nil end
    RC6T_I = 1
    while RC6T_I <= table.getn(context.buffs or {}) do
        RC6T_E = context.buffs[RC6T_I]
        if RC6T_E and RC6T_E.kind == "flatDR" and
           find(lower(tostring(RC6T_E.name or "")), "blessing of sanctuary", 1, true) then
            RC6T_R = tonumber(RC6T_E.rank) or 0
            if RC6T_R >= 1 and RC6T_R <= 4 then return RC6T_R end
        end
        RC6T_I = RC6T_I + 1
    end
    return nil
end

function RC6T_SanctuaryRankFromEvent(eventData)
    if type(eventData) ~= "table" then return nil end
    if type(eventData.rc6ContextSnapshot) == "table" then
        RC6T_R = RC6T_SanctuaryRankFromContext(eventData.rc6ContextSnapshot)
        if RC6T_R then return RC6T_R end
    end
    if eventData.contextID and MT.mitigationContexts and MT.mitigationContexts[eventData.contextID] then
        return RC6T_SanctuaryRankFromContext(MT.mitigationContexts[eventData.contextID])
    end
    return nil
end

function RC6T_FindLatestSavedSanctuaryRank(owner)
    RC6T_I = table.getn(owner.events or {})
    while RC6T_I >= 1 do
        RC6T_R = RC6T_SanctuaryRankFromEvent(owner.events[RC6T_I])
        if RC6T_R then return RC6T_R end
        RC6T_I = RC6T_I - 1
    end
    RC6T_I = table.getn(owner.fights or {})
    while RC6T_I >= 1 do
        RC6T_F = owner.fights[RC6T_I]
        if RC6T_F and RC6T_F.events then
            RC6T_J = table.getn(RC6T_F.events)
            while RC6T_J >= 1 do
                RC6T_R = RC6T_SanctuaryRankFromEvent(RC6T_F.events[RC6T_J])
                if RC6T_R then return RC6T_R end
                RC6T_J = RC6T_J - 1
            end
        end
        RC6T_I = RC6T_I - 1
    end
    return nil
end

-- Persist the continuity hint alongside the normal profile data.  This is only
-- a rank hint; RC6n still requires the Sanctuary aura itself to be present.
RC6T_PreviousSyncPersistentData = MT.SyncPersistentData
function MT:SyncPersistentData()
    RC6T_PreviousSyncPersistentData(self)
    if self.profile then
        if RC6T_ValidSanctuaryRank(self.rc6nActiveSanctuaryRank) then
            self.profile.activeSanctuaryRank = tonumber(self.rc6nActiveSanctuaryRank)
            self.profile.activeSanctuaryRankSource = self.rc6nActiveSanctuaryRankSource or "persisted continuity"
        else
            self.profile.activeSanctuaryRank = nil
            self.profile.activeSanctuaryRankSource = nil
        end
    end
end

RC6T_PreviousRestorePersistentData = MT.RestorePersistentData
function MT:RestorePersistentData()
    RC6T_PreviousRestorePersistentData(self)
    RC6T_R = self.profile and tonumber(self.profile.activeSanctuaryRank) or nil
    if not RC6T_ValidSanctuaryRank(RC6T_R) then
        RC6T_R = RC6T_FindLatestSavedSanctuaryRank(self)
        RC6T_Source = "latest saved event"
    else
        RC6T_Source = (self.profile and self.profile.activeSanctuaryRankSource) or "persisted continuity"
    end
    if RC6T_ValidSanctuaryRank(RC6T_R) then
        self.rc6nActiveSanctuaryRank = RC6T_R
        self.rc6nActiveSanctuaryRankSource = RC6T_Source
    end
end

-- Save the rank immediately when the player actually casts Sanctuary, so a
-- /reload seconds later cannot lose the authoritative rank.
RC6T_PreviousRecordSanctuaryCast = RC6D_RecordSanctuaryCast
function RC6D_RecordSanctuaryCast(rank, source)
    RC6T_PreviousRecordSanctuaryCast(rank, source)
    RC6T_R = tonumber(rank) or 0
    if RC6T_R >= 1 and RC6T_R <= 4 then
        MT.rc6nActiveSanctuaryRank = RC6T_R
        MT.rc6nActiveSanctuaryRankSource = source or "cast"
        if MT.profile then
            MT.profile.activeSanctuaryRank = RC6T_R
            MT.profile.activeSanctuaryRankSource = source or "cast"
        end
    end
end

-- Normalize the channel after the final existing RC6 attribution routine.
-- This preserves the exact total %DR math while making it impossible for a
-- Physical-only melee event to inflate Magic DR on RAW/Magic Pie views.
RC6T_PreviousEnsureEventAttribution = RC6B_EnsureEventAttribution
function RC6B_EnsureEventAttribution(eventData)
    if not eventData then return eventData end
    if eventData.rc6MathVersion == 11 then return eventData end
    eventData.rc6MathVersion = nil
    RC6T_Result = RC6T_PreviousEnsureEventAttribution(eventData)
    if not RC6T_Result then return RC6T_Result end

    RC6T_TotalPct = (tonumber(RC6T_Result.physicalDR) or 0) + (tonumber(RC6T_Result.magicDR) or 0)
    if (RC6T_Result.school or "Physical") == "Physical" then
        RC6T_Result.physicalDR = RC6T_TotalPct
        RC6T_Result.magicDR = 0
    else
        RC6T_Result.magicDR = RC6T_TotalPct
        RC6T_Result.physicalDR = 0
    end
    RC6T_Result.rc6MathVersion = 11
    return RC6T_Result
end




-- ============================================================================
-- RC6u / LAYEREDSTOP1 - outcome-aware attribution
-- ============================================================================
-- Accounting rule:
--   Dodge / Parry / Miss
--     * never land
--     * 100% of estimated pre-mitigation RAW -> Avoidance
--     * Armor / Flat DR / %DR / Block / Resist / Absorb = 0
--
--   Full Block / Full Resist
--     * are landed terminal outcomes
--     * preserve the actual preceding passive layers
--     * terminal Block/Resist receives only the remainder that reaches it
--
--   Ordinary DAMAGE events (including Partial Block and partial absorb/resist)
--     * remain on the established RC6 inverse/forward reconstruction path.
--
-- This keeps outcome labels separate from attribution. A combat-log "You block"
-- can therefore truthfully display, for example:
--   RAW 50 -> Flat DR 10 -> Armor 15 -> Full Block 25 -> Taken 0
-- instead of falsely crediting all 50 to Block.

function RC6U_IsPureAvoidance(kind)
    return kind == "Dodge" or kind == "Parry" or kind == "Miss"
end

function RC6U_IsLayeredTerminal(kind)
    return kind == "FullBlock" or kind == "FullResist"
end

function RC6U_Clamp01(value)
    value = tonumber(value) or 0
    if value < 0 then return 0 end
    if value > 1 then return 1 end
    return value
end

function RC6U_ModelForOutcome(eventData)
    RC6U_Context = RC6_ContextForEvent(eventData)
    RC6U_Model = RC6B_GetDRModel and RC6B_GetDRModel(RC6U_Context, eventData.school or "Physical") or nil
    if type(RC6U_Model) ~= "table" then
        RC6U_Model = {flatCap=0, pctFactor=1, listedPct=0, effectivePct=0}
    end
    RC6U_Model.flatCap = tonumber(RC6U_Model.flatCap) or 0
    if RC6U_Model.flatCap < 0 then RC6U_Model.flatCap = 0 end
    RC6U_Model.pctFactor = tonumber(RC6U_Model.pctFactor) or 1
    if RC6U_Model.pctFactor < 0.01 then RC6U_Model.pctFactor = 0.01 end
    if RC6U_Model.pctFactor > 1 then RC6U_Model.pctFactor = 1 end
    RC6U_Model.effectivePct = tonumber(RC6U_Model.effectivePct) or ((1-RC6U_Model.pctFactor)*100)
    RC6U_Model.listedPct = tonumber(RC6U_Model.listedPct) or 0

    RC6U_ArmorRate = RC6B_GetArmorRate and RC6B_GetArmorRate(eventData) or 0
    RC6U_ArmorRate = RC6U_Clamp01(RC6U_ArmorRate)
    if RC6U_ArmorRate > 0.75 then RC6U_ArmorRate = 0.75 end
    if (eventData.school or "Physical") ~= "Physical" then RC6U_ArmorRate = 0 end
    return RC6U_Model, RC6U_ArmorRate
end

function RC6U_InvertPostPassive(postAmount, model, armorRate)
    RC6U_Post = tonumber(postAmount) or 0
    if RC6U_Post < 0 then RC6U_Post = 0 end
    RC6U_AF = 1 - (tonumber(armorRate) or 0)
    if RC6U_AF < 0.25 then RC6U_AF = 0.25 end
    RC6U_PF = tonumber(model and model.pctFactor) or 1
    if RC6U_PF < 0.01 then RC6U_PF = 0.01 end
    RC6U_Flat = tonumber(model and model.flatCap) or 0
    if RC6U_Flat < 0 then RC6U_Flat = 0 end
    RC6U_Raw = (RC6U_Post / RC6U_AF / RC6U_PF) + RC6U_Flat
    if RC6U_Raw < RC6U_Post then RC6U_Raw = RC6U_Post end
    return RC6U_Raw
end

function RC6U_MaxRawForTerminalAmount(amount, model, armorRate)
    RC6U_Amount = tonumber(amount) or 0
    if RC6U_Amount <= 0 then return nil end
    return RC6U_InvertPostPassive(RC6U_Amount, model, armorRate)
end

function RC6U_SelectRawEstimate(eventData, model, armorRate)
    RC6U_Hint, RC6U_Low, RC6U_High = nil, nil, nil
    if RC6B_GetWhiteSwingRange then
        RC6U_Hint, RC6U_Low, RC6U_High = RC6B_GetWhiteSwingRange(eventData)
    end

    RC6U_BlockValue = tonumber(eventData.rc6BlockValue) or 0
    RC6U_Note = nil

    -- A white swing gives us an independent pre-mitigation range. For a Full
    -- Block, the observed outcome plus known Block Value narrows that range:
    -- only raw rolls whose post-DR/post-armor remainder fits inside Block Value
    -- are possible. Use the midpoint of that admissible subset.
    if RC6U_Hint and RC6U_Low and RC6U_High then
        RC6U_Raw = RC6U_Hint
        if eventData.kind == "FullBlock" and RC6U_BlockValue > 0 then
            RC6U_MaxRaw = RC6U_MaxRawForTerminalAmount(RC6U_BlockValue, model, armorRate)
            if RC6U_MaxRaw and RC6U_MaxRaw < RC6U_High then
                if RC6U_MaxRaw >= RC6U_Low then
                    RC6U_Raw = (RC6U_Low + RC6U_MaxRaw) / 2
                    RC6U_Note = "Full Block raw estimate narrowed by event-time Block Value"
                else
                    -- The observed Full Block is authoritative. If no roll in the
                    -- captured range fits the model, keep the hard lower raw bound
                    -- and surface the disagreement instead of fabricating a value.
                    RC6U_Raw = RC6U_Low
                    RC6U_Note = "Full Block conflicts with captured raw range/Block Value; lower raw bound retained"
                end
            end
        end
        return RC6U_Raw, RC6U_Note, "UnitDamage range"
    end

    -- Matching-context / learned estimates are amounts before the terminal
    -- outcome, after the passive layers. Reverse those layers to recover RAW.
    RC6U_Post = tonumber(eventData.rc6PreOutcomeEstimate)
    if RC6U_Post and RC6U_Post > 0 then
        if eventData.kind == "FullBlock" and RC6U_BlockValue > 0 and RC6U_Post > RC6U_BlockValue then
            RC6U_Post = RC6U_BlockValue
            RC6U_Note = "Full Block terminal estimate capped by event-time Block Value"
        end
        RC6U_Raw = RC6U_InvertPostPassive(RC6U_Post, model, armorRate)
        return RC6U_Raw, RC6U_Note, eventData.estimateSource or "learned post-passive estimate"
    end

    -- Legacy PL8/PL9 events do not have the new transport snapshot. Preserve
    -- their already-saved RAW estimate rather than trying to reconstruct it from
    -- current state. We can still split that RAW through the saved context.
    RC6U_Raw = tonumber(eventData.raw) or tonumber(eventData.rc6BaseRaw) or 0
    if RC6U_Raw < 0 then RC6U_Raw = 0 end
    return RC6U_Raw, "Legacy outcome RAW retained", "saved event"
end

function RC6U_SetRawSchool(eventData, raw)
    eventData.raw = raw
    if (eventData.school or "Physical") == "Physical" then
        eventData.physicalRaw = raw
        eventData.magicRaw = 0
    else
        eventData.magicRaw = raw
        eventData.physicalRaw = 0
    end
end

function RC6U_NormalizePureAvoidance(eventData)
    RC6U_Model, RC6U_ArmorRate = RC6U_ModelForOutcome(eventData)
    RC6U_Raw, RC6U_Note, RC6U_Source = RC6U_SelectRawEstimate(eventData, RC6U_Model, RC6U_ArmorRate)
    if RC6U_Raw < 0 then RC6U_Raw = 0 end

    RC6U_SetRawSchool(eventData, RC6U_Raw)
    eventData.taken = 0
    eventData.armor = 0
    eventData.flatDR = 0
    eventData.physicalDR = 0
    eventData.magicDR = 0
    eventData.block = 0
    eventData.resist = 0
    eventData.absorb = 0
    eventData.avoidance = RC6U_Raw
    eventData.drEstimated = false
    eventData.drSaturated = false
    eventData.drPctEffective = 0
    eventData.drPctListed = 0
    eventData.outcomeEstimateSource = RC6U_Source
    eventData.drMathNote = "Pure avoidance: all estimated RAW credited to " .. tostring(eventData.kind)
    if RC6U_Note then eventData.drMathNote = eventData.drMathNote .. "; " .. RC6U_Note end
    eventData.layeredOutcomeVersion = 1
    return eventData
end

function RC6U_NormalizeLayeredTerminal(eventData)
    RC6U_Model, RC6U_ArmorRate = RC6U_ModelForOutcome(eventData)
    RC6U_Raw, RC6U_Note, RC6U_Source = RC6U_SelectRawEstimate(eventData, RC6U_Model, RC6U_ArmorRate)
    if RC6U_Raw < 0 then RC6U_Raw = 0 end

    -- Full Block/Full Resist are landed outcomes, so passive Flat DR follows the
    -- same 1-damage floor used by the established landed-hit RC6 model. A later
    -- terminal layer is then allowed to consume that final remainder.
    RC6U_FlatCap = tonumber(RC6U_Model.flatCap) or 0
    RC6U_MaxFlat = RC6U_Raw - 1
    if RC6U_MaxFlat < 0 then RC6U_MaxFlat = 0 end
    RC6U_FlatUsed = RC6U_FlatCap
    if RC6U_FlatUsed > RC6U_MaxFlat then RC6U_FlatUsed = RC6U_MaxFlat end
    if RC6U_FlatUsed < 0 then RC6U_FlatUsed = 0 end

    RC6U_AfterFlat = RC6U_Raw - RC6U_FlatUsed
    RC6U_PctFactor = tonumber(RC6U_Model.pctFactor) or 1
    if RC6U_PctFactor < 0.01 then RC6U_PctFactor = 0.01 end
    if RC6U_PctFactor > 1 then RC6U_PctFactor = 1 end
    RC6U_AfterPct = RC6U_AfterFlat * RC6U_PctFactor
    RC6U_PctStopped = RC6U_AfterFlat - RC6U_AfterPct
    if RC6U_PctStopped < 0 then RC6U_PctStopped = 0 end

    RC6U_ArmorStopped = 0
    RC6U_AfterArmor = RC6U_AfterPct
    if (eventData.school or "Physical") == "Physical" then
        RC6U_ArmorStopped = RC6U_AfterPct * RC6U_ArmorRate
        if RC6U_ArmorStopped < 0 then RC6U_ArmorStopped = 0 end
        if RC6U_ArmorStopped > RC6U_AfterPct then RC6U_ArmorStopped = RC6U_AfterPct end
        RC6U_AfterArmor = RC6U_AfterPct - RC6U_ArmorStopped
    end
    if RC6U_AfterArmor < 0 then RC6U_AfterArmor = 0 end

    RC6U_SetRawSchool(eventData, RC6U_Raw)
    eventData.taken = 0
    eventData.avoidance = 0
    eventData.flatDR = RC6U_FlatUsed
    eventData.armor = RC6U_ArmorStopped
    eventData.absorb = 0
    eventData.drPctEffective = tonumber(RC6U_Model.effectivePct) or 0
    eventData.drPctListed = tonumber(RC6U_Model.listedPct) or 0
    eventData.drEstimated = (RC6U_FlatUsed + RC6U_PctStopped) > 0
    eventData.drSaturated = RC6U_FlatUsed > 0 and RC6U_AfterFlat <= 1.0001

    if (eventData.school or "Physical") == "Physical" then
        eventData.physicalDR = RC6U_PctStopped
        eventData.magicDR = 0
    else
        eventData.magicDR = RC6U_PctStopped
        eventData.physicalDR = 0
    end

    if eventData.kind == "FullBlock" then
        eventData.block = RC6U_AfterArmor
        eventData.resist = 0
        eventData.drMathNote = "Layered Full Block: Flat/%DR -> Armor -> Full Block"
        RC6U_BlockValue = tonumber(eventData.rc6BlockValue) or 0
        if RC6U_BlockValue > 0 and eventData.block > RC6U_BlockValue + 0.51 then
            eventData.drMathNote = eventData.drMathNote .. "; estimated block remainder exceeds captured Block Value"
        end
    else
        eventData.block = 0
        eventData.resist = RC6U_AfterArmor
        eventData.drMathNote = "Layered Full Resist: Flat/%DR -> Armor(if physical) -> Full Resist"
    end

    if RC6U_Note then eventData.drMathNote = eventData.drMathNote .. "; " .. RC6U_Note end
    eventData.outcomeEstimateSource = RC6U_Source
    eventData.layeredOutcomeVersion = 1
    return eventData
end

function RC6U_NormalizeOutcome(eventData)
    if not eventData or type(eventData) ~= "table" then return eventData end

    -- Once a finalized event has been calculated under this model, its saved
    -- category amounts are authoritative. Pass-2A may strip diagnostic inputs,
    -- so never recalculate a persisted LAYEREDSTOP1 event from missing metadata.
    if eventData.layeredOutcomeVersion == 1 then return eventData end

    if RC6U_IsPureAvoidance(eventData.kind) then
        return RC6U_NormalizePureAvoidance(eventData)
    elseif RC6U_IsLayeredTerminal(eventData.kind) then
        return RC6U_NormalizeLayeredTerminal(eventData)
    end
    return eventData
end

-- Run after the final RC6t channel-normalization layer. Ordinary DAMAGE events
-- are untouched. Outcome normalization is idempotent and writes a durable marker
-- so Archive/History/reload paths preserve the exact finalized attribution.
RC6U_PreviousEnsureEventAttribution = RC6B_EnsureEventAttribution
function RC6B_EnsureEventAttribution(eventData)
    RC6U_Result = RC6U_PreviousEnsureEventAttribution(eventData)
    return RC6U_NormalizeOutcome(RC6U_Result)
end


-- ============================================================================
-- RC6v / LAYEREDSTOP2 - immutable finalized outcomes + hand-aware Full Block
-- ============================================================================
-- PL11 live data exposed two linked Full Block defects:
--   1) A finalized LAYEREDSTOP1 event could be passed through the older RC6
--      stack again after Pass-2A stripped rc6MathVersion. The old stack restored
--      base RAW/zero DR, then the late outcome marker prevented re-normalization.
--   2) Dual-wield Full Block used the union of MH/OH ranges as one continuous
--      range. If Block Value made only the OH range possible, the midpoint could
--      land in the impossible gap between OH and MH.
--
-- LAYEREDSTOP2 makes finalized outcome attribution immutable BEFORE the older
-- RC6 stack can touch it, validates the accounting invariant, chooses feasible
-- MH/OH ranges independently for Full Block, and normalizes outcome events
-- before RecordEvent builds Timeline/Overall buckets.
-- ============================================================================

RC6V_PreviousContextForEvent = RC6_ContextForEvent
function RC6_ContextForEvent(eventData)
    if eventData and type(eventData.rc6ContextSnapshot) == "table" then
        return eventData.rc6ContextSnapshot
    end
    -- Pass-2A/SVH1 persists compact numeric context references on completed
    -- live fights. Prefer that event-specific historical context over today's
    -- active context when a saved fight is opened after combat or /reload.
    if eventData and tonumber(eventData.context) and MT.profile and
       type(MT.profile.compactContextPool) == "table" then
        RC6V_Context = MT.profile.compactContextPool[tonumber(eventData.context)]
        if type(RC6V_Context) == "table" then return RC6V_Context end
    end
    return RC6V_PreviousContextForEvent(eventData)
end

function RC6V_ClippedRangeMid(low, high, maxRaw)
    low = tonumber(low) or 0
    high = tonumber(high) or 0
    maxRaw = tonumber(maxRaw)
    if low <= 0 or high < low then return nil end
    if maxRaw and high > maxRaw then high = maxRaw end
    if high + 0.0001 < low then return nil end
    return (low + high) / 2, low, high
end

-- Replace the LAYEREDSTOP1 selector with a dual-wield-aware Full Block solver.
-- Dodge/Parry/Miss deliberately retain the combined MH/OH average because the
-- avoided combat text gives us no hand-specific terminal constraint.
function RC6U_SelectRawEstimate(eventData, model, armorRate)
    RC6U_Hint, RC6U_Low, RC6U_High = nil, nil, nil
    if RC6B_GetWhiteSwingRange then
        RC6U_Hint, RC6U_Low, RC6U_High = RC6B_GetWhiteSwingRange(eventData)
    end

    RC6U_BlockValue = tonumber(eventData.rc6BlockValue) or 0
    RC6U_Note = nil

    if RC6U_Hint and RC6U_Low and RC6U_High then
        RC6U_Raw = RC6U_Hint

        if eventData.kind == "FullBlock" and RC6U_BlockValue > 0 then
            RC6U_MaxRaw = RC6U_MaxRawForTerminalAmount(RC6U_BlockValue, model, armorRate)

            -- Dual wield: MH and OH are two discrete ranges, not one continuous
            -- 17..43-style range. Test each hand independently against the
            -- maximum raw roll that can still fit under event-time Block Value.
            if eventData.rawHintDualWield then
                RC6V_MHMid = RC6V_ClippedRangeMid(eventData.rawHintMHLow, eventData.rawHintMHHigh, RC6U_MaxRaw)
                RC6V_OHMid = RC6V_ClippedRangeMid(eventData.rawHintOHLow, eventData.rawHintOHHigh, RC6U_MaxRaw)

                if RC6V_MHMid and not RC6V_OHMid then
                    RC6U_Raw = RC6V_MHMid
                    RC6U_Note = "Full Block proven main-hand feasible by event-time Block Value"
                    return RC6U_Raw, RC6U_Note, "UnitDamage MH range"
                elseif RC6V_OHMid and not RC6V_MHMid then
                    RC6U_Raw = RC6V_OHMid
                    RC6U_Note = "Full Block proven off-hand feasible by event-time Block Value"
                    return RC6U_Raw, RC6U_Note, "UnitDamage OH range"
                elseif RC6V_MHMid and RC6V_OHMid then
                    -- Both hands can produce the outcome. With no hand marker in
                    -- vanilla combat text, keep the established equal-hand
                    -- midpoint policy, but only across the feasible subsets.
                    RC6U_Raw = (RC6V_MHMid + RC6V_OHMid) / 2
                    RC6U_Note = "Full Block compatible with both hands; feasible MH/OH average used"
                    return RC6U_Raw, RC6U_Note, "UnitDamage feasible MH/OH ranges"
                end

                RC6U_Note = "Full Block conflicts with both captured hand ranges/Block Value"
            end

            -- Single-wield or old events without separate hand ranges retain the
            -- bounded-range behavior from LAYEREDSTOP1.
            if RC6U_MaxRaw and RC6U_MaxRaw < RC6U_High then
                if RC6U_MaxRaw >= RC6U_Low then
                    RC6U_Raw = (RC6U_Low + RC6U_MaxRaw) / 2
                    RC6U_Note = RC6U_Note or "Full Block raw estimate narrowed by event-time Block Value"
                else
                    RC6U_Raw = RC6U_Low
                    RC6U_Note = RC6U_Note or "Full Block conflicts with captured raw range/Block Value; lower raw bound retained"
                end
            end
        end
        return RC6U_Raw, RC6U_Note, "UnitDamage range"
    end

    -- Matching-context estimates are post-passive amounts immediately before
    -- the terminal outcome. Reverse Flat/%DR/Armor to recover RAW.
    RC6U_Post = tonumber(eventData.rc6PreOutcomeEstimate)
    if RC6U_Post and RC6U_Post > 0 then
        if eventData.kind == "FullBlock" and RC6U_BlockValue > 0 and RC6U_Post > RC6U_BlockValue then
            RC6U_Post = RC6U_BlockValue
            RC6U_Note = "Full Block terminal estimate capped by event-time Block Value"
        end
        RC6U_Raw = RC6U_InvertPostPassive(RC6U_Post, model, armorRate)
        return RC6U_Raw, RC6U_Note, eventData.estimateSource or "learned post-passive estimate"
    end

    RC6U_Raw = tonumber(eventData.raw) or tonumber(eventData.rc6BaseRaw) or 0
    if RC6U_Raw < 0 then RC6U_Raw = 0 end
    return RC6U_Raw, "Legacy outcome RAW retained", "saved event"
end

function RC6V_OutcomeBalance(eventData)
    if not eventData then return 999999, 0 end
    RC6V_Raw = tonumber(eventData.raw) or 0
    RC6V_Sum = (tonumber(eventData.taken) or 0) +
        (tonumber(eventData.flatDR) or 0) +
        (tonumber(eventData.physicalDR) or 0) +
        (tonumber(eventData.magicDR) or 0) +
        (tonumber(eventData.armor) or 0) +
        (tonumber(eventData.block) or 0) +
        (tonumber(eventData.resist) or 0) +
        (tonumber(eventData.absorb) or 0) +
        (tonumber(eventData.avoidance) or 0)
    return math.abs(RC6V_Raw - RC6V_Sum), RC6V_Sum
end

-- The final attribution gate must check the durable outcome marker BEFORE
-- invoking the historical RC6 stack. Pass-2A intentionally removes
-- rc6MathVersion and other transport fields; calling the old stack first could
-- otherwise restore base RAW/zero DR on a perfectly finalized Full Block.
RC6V_PreviousEnsureEventAttribution = RC6B_EnsureEventAttribution
function RC6B_EnsureEventAttribution(eventData)
    if not eventData then return eventData end

    RC6V_IsOutcome = RC6U_IsPureAvoidance(eventData.kind) or RC6U_IsLayeredTerminal(eventData.kind)
    if RC6V_IsOutcome then
        -- PL12 events are immutable once their accounting equation is proven.
        if tonumber(eventData.layeredOutcomeVersion) == 2 then
            RC6V_Delta = RC6V_OutcomeBalance(eventData)
            if RC6V_Delta <= 0.02 then return eventData end
            -- Do not silently rebuild a persisted malformed v2 event from
            -- today's state. Surface the integrity failure and preserve evidence.
            eventData.layeredOutcomeIntegrityFailed = true
            return eventData
        end

        -- PL10/PL11 marker-1 events may already have had their transient inputs
        -- stripped. Freeze them as historical evidence rather than letting an
        -- old RC6 pass mutate them again. New events enter here with no marker.
        if tonumber(eventData.layeredOutcomeVersion) == 1 then
            return eventData
        end
    end

    RC6V_Result = RC6V_PreviousEnsureEventAttribution(eventData)
    if not RC6V_Result then return RC6V_Result end

    if RC6U_IsPureAvoidance(RC6V_Result.kind) or RC6U_IsLayeredTerminal(RC6V_Result.kind) then
        RC6V_Delta = RC6V_OutcomeBalance(RC6V_Result)
        if RC6V_Delta <= 0.02 then
            RC6V_Result.layeredOutcomeVersion = 2
            RC6V_Result.layeredOutcomeIntegrityFailed = nil
        else
            -- Never bless an unbalanced terminal outcome as finalized.
            RC6V_Result.layeredOutcomeVersion = nil
            RC6V_Result.layeredOutcomeIntegrityFailed = true
        end
    end
    return RC6V_Result
end

-- Normalize first, THEN store the event and build Timeline/Overall buckets.
-- This makes Timeline use the same final Full Block RAW/Flat/Armor/Block split
-- as Details, Pie, Main, Compare and FINALAGG1 instead of preserving the
-- pre-normalization legacy transport estimate.
RC6V_PreviousRecordEvent = MT.RecordEvent
function MT:RecordEvent(eventData)
    if eventData and RC6B_EnsureEventAttribution then
        eventData = RC6B_EnsureEventAttribution(eventData)
    end
    return RC6V_PreviousRecordEvent(self, eventData)
end

-- ============================================================================
-- RC6w / LAYEREDSTOP3 - retire first-generation attribution mutator
-- ============================================================================
-- PL12 live SavedVariables proved the Timeline initially received the correct
-- hand-aware Full Block (19.25 RAW with Sanctuary/Armor/Block layers), but the
-- stored event later reverted to 28.875 RAW / 0 Flat DR.  The cause was an old
-- RC6q compatibility path: RC6_SumEventDR() still called RC6_EnsureEventAttribution(),
-- the first-generation mutating routine.  That routine restores rc6BaseRaw and
-- zeroes DR for non-DAMAGE outcomes, bypassing the final RC6v immutable gate.
--
-- RC6r's README note already identified RC6q's helper as obsolete for totals,
-- but RC6q remained in the wrapper chain, so simply overwriting its final totals
-- did not prevent the underlying event mutation.
--
-- Route every surviving legacy caller through the final outcome-aware gate.
-- This is intentionally defined LAST, after RC6v owns RC6B_EnsureEventAttribution.
-- There is no recursion: the RC6v chain never calls RC6_EnsureEventAttribution.
RC6W_FirstGenerationEnsureEventAttribution = RC6_EnsureEventAttribution
function RC6_EnsureEventAttribution(eventData)
    if not eventData then return eventData end
    return RC6B_EnsureEventAttribution(eventData)
end

