-- MainTank 0.9.11
-- World of Warcraft 1.12.1 / Lua 5.0

MainTank = {}
local MT = MainTank

MT.playerName = nil
MT.inCombat = false
MT.debug = false
MT.encounterMemory = {}
MT.sessionMemory = {}
MT.targetDamageMemory = {}
MT.pending = {}
MT.data = {}
MT.overallData = {}
MT.fights = {}
MT.fightStartTime = nil
MT.rows = {}
MT.currentPage = "RAW"
MT.currentView = "CURRENT"
MT.events = {}
MT.overallEvents = {}
MT.timeline = {}
MT.overallTimeline = {}
MT.timelineMode = "RAW"
MT.pieMode = "RAW"
MT.sessionStartTime = nil
MT.abilitySchoolMemory = {}
MT.detailsEnemyPage = 1
MT.detailsAbilityPage = 1
MT.detailsSelectedEnemy = nil
MT.detailsEventPage = 1
MT.detailsSelectedEvent = nil
MT.timelineSelection = nil
MT.enemyDeathCounts = {}

local DB_SCHEMA_VERSION = 11

local floor = math.floor
local format = string.format
local find = string.find
local lower = string.lower

local DAMAGE_SCHOOLS = {
    holy = "Holy",
    fire = "Fire",
    nature = "Nature",
    frost = "Frost",
    shadow = "Shadow",
    arcane = "Arcane",
    physical = "Physical"
}

local function NewData()
    return {
        rawIncoming = 0,
        physicalRaw = 0,
        magicRaw = 0,
        damageTaken = 0,
        physicalTaken = 0,
        magicTaken = 0,
        armorReduced = 0,
        blocked = 0,
        physicalBlocked = 0,
        magicBlocked = 0,
        fullBlockedEstimated = 0,
        physicalFullBlockedEstimated = 0,
        magicFullBlockedEstimated = 0,
        absorbed = 0,
        resistedPartial = 0,
        resistedFullEstimated = 0,
        dodgedEstimated = 0,
        parriedEstimated = 0,
        missedEstimated = 0,
        dodgeCount = 0,
        parryCount = 0,
        missCount = 0,
        blockCount = 0,
        minPartialBlock = nil,
        maxPartialBlock = 0,
        totalPartialBlock = 0,
        fullBlockCount = 0,
        partialResistCount = 0,
        fullResistCount = 0,
        absorbCount = 0,
        meleeHitCount = 0,
        magicHitCount = 0,
        schools = {},
        mobs = {}
    }
end

local function CopyTable(source)
    if type(source) ~= "table" then return source end
    local copy = {}
    local key, value
    for key, value in pairs(source) do
        if type(value) == "table" then
            copy[key] = CopyTable(value)
        else
            copy[key] = value
        end
    end
    return copy
end

local function WithData(data, callback)
    local previous = MT.data
    MT.data = data
    callback()
    MT.data = previous
end

local function Round(value)
    if not value then return 0 end
    return floor(value + 0.5)
end

-- pfUI-aware neutral skin. When pfUI is loaded, this reads the player's
-- active border background, border color, font, and alpha directly from
-- pfUI_config. Without pfUI it falls back to a neutral charcoal style.
-- REFACXML1: legacy/pfUI skinning and analysis-tooltip presentation moved
-- to UI\StyleCore.lua.

local function NewTimelineBucket(second)
    return {
        second = second or 0,
        raw = 0,
        armor = 0,
        block = 0,
        avoidance = 0,
        resist = 0,
        absorb = 0,
        taken = 0,
        physicalTaken = 0,
        magicTaken = 0,
        physicalRaw = 0,
        magicRaw = 0,
        events = 0
    }
end

local function AddToTimelineBucket(root, eventData)
    if not root or not eventData then return end
    local second = floor(eventData.time or 0)
    if second < 0 then second = 0 end
    if not root[second] then root[second] = NewTimelineBucket(second) end
    local bucket = root[second]
    bucket.raw = bucket.raw + (eventData.raw or 0)
    bucket.armor = bucket.armor + (eventData.armor or 0)
    bucket.block = bucket.block + (eventData.block or 0)
    bucket.avoidance = bucket.avoidance + (eventData.avoidance or 0)
    bucket.resist = bucket.resist + (eventData.resist or 0)
    bucket.absorb = bucket.absorb + (eventData.absorb or 0)
    bucket.taken = bucket.taken + (eventData.taken or 0)
    if eventData.school == "Physical" then
        bucket.physicalTaken = (bucket.physicalTaken or 0) + (eventData.taken or 0)
    else
        bucket.magicTaken = (bucket.magicTaken or 0) + (eventData.taken or 0)
    end
    bucket.physicalRaw = bucket.physicalRaw + (eventData.physicalRaw or 0)
    bucket.magicRaw = bucket.magicRaw + (eventData.magicRaw or 0)
    bucket.events = bucket.events + 1
end

local function Print(msg)
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage("|cff66ccffMainTank:|r " .. msg)
    end
end

local function Debug(msg)
    if MT.debug then
        Print("|cffffff00DEBUG|r " .. msg)
    end
end

local function SafeNumber(value)
    if not value then return 0 end
    value = string.gsub(value, ",", "")
    return tonumber(value) or 0
end

local function GetSchoolBucket(school)
    school = school or "Physical"
    if not MT.data.schools[school] then
        MT.data.schools[school] = {
            taken = 0,
            partial = 0,
            fullEstimated = 0,
            fullCount = 0
        }
    end
    return MT.data.schools[school]
end

local function GetMobBucket(mob)
    mob = mob or "Unknown"
    if not MT.data.mobs[mob] then
        MT.data.mobs[mob] = {
            taken = 0,
            blocked = 0,
            resisted = 0,
            avoidedEstimated = 0,
            dodgeCount = 0,
            parryCount = 0,
            missCount = 0,
            blockCount = 0,
            blockMin = nil,
            blockMax = 0,
            blockTotal = 0
        }
    end
    return MT.data.mobs[mob]
end

local function GetAttackerLevel(mob)
    if UnitExists("target") and UnitName("target") == mob then
        local level = UnitLevel("target")
        if level and level > 0 then return level end
    end
    local playerLevel = UnitLevel("player") or 60
    if playerLevel < 1 then playerLevel = 60 end
    return playerLevel
end

local function GetArmorReduction(mob)
    local _, effectiveArmor = UnitArmor("player")
    effectiveArmor = effectiveArmor or 0
    if effectiveArmor < 0 then effectiveArmor = 0 end

    local level = GetAttackerLevel(mob)
    local reduction = effectiveArmor / (effectiveArmor + 400 + (85 * level))
    if reduction < 0 then reduction = 0 end
    if reduction > 0.75 then reduction = 0.75 end
    return reduction, effectiveArmor, level
end

-- Vanilla 1.12.1 does not normally expose GetShieldBlock().  OctoWoW's
-- BetterCharacterStats reconstructs block value by scanning equipped-item and
-- talent tooltips.  Project Legacy uses 20 Str = 1 block value (with the
-- historical -1 correction), so MainTank performs its own cached calculation.
MT.blockValueDirty = true
MT.cachedBlockValue = 0
MT.cachedBlockDetails = { gear = 0, strength = 0, talentPct = 0, scanReady = false }
MT.blockValueRetryAt = nil
MT.blockValueRetryCount = 0

local function GetScanTooltip()
    if MT.scanTooltip then return MT.scanTooltip end
    local tip = CreateFrame("GameTooltip", "MainTankScanTooltip", UIParent, "GameTooltipTemplate")
    tip:SetOwner(UIParent, "ANCHOR_NONE")
    MT.scanTooltip = tip
    return tip
end

local function ScanTooltipNumber(tip, patterns)
    local total = 0
    local i, j, text, value
    for i = 1, tip:NumLines() do
        local left = getglobal("MainTankScanTooltipTextLeft" .. i)
        local right = getglobal("MainTankScanTooltipTextRight" .. i)
        for j = 1, 2 do
            text = (j == 1 and left and left:GetText()) or (j == 2 and right and right:GetText())
            if text then
                local k
                for k = 1, table.getn(patterns) do
                    _, _, value = string.find(text, patterns[k])
                    if value then
                        total = total + (tonumber(value) or 0)
                        break
                    end
                end
            end
        end
    end
    return total
end

local function ScanBlockTalentPercent()
    local tip = GetScanTooltip()
    local total = 0
    local tab, talent, line, text, value, name, rank
    for tab = 1, GetNumTalentTabs() do
        for talent = 1, GetNumTalents(tab) do
            name, _, _, _, rank = GetTalentInfo(tab, talent)
            rank = tonumber(rank) or 0
            if rank > 0 then
                -- Project Legacy Shield Specialization is 10/20/30% at ranks 1/2/3.
                -- Prefer the learned rank directly so the "Next rank" tooltip text
                -- can never be mistaken for the currently active bonus.
                if name == "Shield Specialization" then
                    if rank > 3 then rank = 3 end
                    total = total + (rank * 10)
                else
                    tip:ClearLines()
                    tip:SetTalent(tab, talent)
                    for line = 1, tip:NumLines() do
                        local fs = getglobal("MainTankScanTooltipTextLeft" .. line)
                        text = fs and fs:GetText()
                        if text then
                            if TOOLTIP_TALENT_NEXT_RANK and text == TOOLTIP_TALENT_NEXT_RANK then break end
                            _, _, value = string.find(text, "amount of damage absorbed by your shield by (%d+)%%")
                            if not value then _, _, value = string.find(text, "increases the amount blocked by (%d+)%%") end
                            if value then total = total + (tonumber(value) or 0) end
                        end
                    end
                end
            end
        end
    end
    return total
end

local function PrepareInventoryTooltip(tip, slot)
    tip:ClearLines()
    local found = tip:SetInventoryItem("player", slot)
    if not found then return false end

    -- OctoWoW/Turtle-derived clients can return an incomplete inventory tooltip
    -- during login or immediately after a gear swap. BetterCharacterStats solves
    -- this by rebuilding the tooltip from the equipped item hyperlink.
    local link = GetInventoryItemLink("player", slot)
    if link then
        local _, _, itemString = string.find(link, "(item:%-?%d+:%-?%d+:%-?%d+:%-?%d+)")
        if itemString then
            tip:ClearLines()
            tip:SetHyperlink(itemString)
        end
    end
    return tip:NumLines() > 0
end

local function CalculateBlockValue()
    local tip = GetScanTooltip()
    local gear = 0
    local equippedItems = 0
    local scannedItems = 0
    local slot
    for slot = 1, 19 do
        if GetInventoryItemLink("player", slot) then equippedItems = equippedItems + 1 end
        if PrepareInventoryTooltip(tip, slot) then
            scannedItems = scannedItems + 1
            gear = gear + ScanTooltipNumber(tip, {
                "(%d+) Block",
                "Equip: Increases the block value of your shield by (%d+)%.",
                "Increases the block value of your shield by (%d+)",
                "Block Value %+(%d+)"
            })
        end
    end

    local _, strength = UnitStat("player", 1)
    strength = tonumber(strength) or 0
    local strengthValue = (strength / 20) - 1
    if strengthValue < 0 then strengthValue = 0 end

    local talentPct = ScanBlockTalentPercent()
    local base = gear + strengthValue
    local value = floor(base * (1 + (talentPct / 100)))
    if value < 0 then value = 0 end

    local scanReady = equippedItems == 0 or scannedItems > 0
    MT.cachedBlockDetails = {
        gear = gear,
        strength = strengthValue,
        talentPct = talentPct,
        scanReady = scanReady,
        equippedItems = equippedItems,
        scannedItems = scannedItems
    }

    -- A shield is equipped but no block line was available yet. Keep the last
    -- known good value and retry shortly instead of replacing it with zero.
    local offhandLink = GetInventoryItemLink("player", 17)
    if offhandLink and gear == 0 then
        MT.blockValueRetryCount = (MT.blockValueRetryCount or 0) + 1
        MT.blockValueRetryAt = GetTime() + 0.75
        if (MT.cachedBlockValue or 0) > 0 then return MT.cachedBlockValue end
    else
        MT.blockValueRetryCount = 0
        MT.blockValueRetryAt = nil
    end

    return value
end

function MT:MarkBlockValueDirty(delay)
    self.blockValueDirty = true
    self.blockValueRetryAt = GetTime() + (delay or 0)
end

function MT:RefreshBlockValue(force)
    if force then self.blockValueDirty = true end
    if self.blockValueDirty then
        if self.CalculateBlockValue then
            self.cachedBlockValue = self:CalculateBlockValue()
        else
            self.cachedBlockValue = CalculateBlockValue()
        end
        self.blockValueDirty = false
    end
    return self.cachedBlockValue or 0
end

local function GetBlockValueBreakdown(data)
    MT:RefreshBlockValue(false)

    local apiValue = 0
    if type(GetShieldBlock) == "function" then
        apiValue = tonumber(GetShieldBlock()) or 0
    end

    local details = MT.cachedBlockDetails or {}
    local gear = details.gear or 0
    local strength = details.strength or 0
    local talentPct = details.talentPct or 0
    local calculated = MT.cachedBlockValue or 0
    local baseValue = calculated
    if apiValue > 0 then baseValue = apiValue end

    local count = data and data.blockCount or 0
    local observedMin = data and data.minPartialBlock or nil
    local observedMax = data and data.maxPartialBlock or 0
    local observedTotal = data and data.totalPartialBlock or 0
    local observedAverage = 0
    if count > 0 then observedAverage = observedTotal / count end

    return {
        gear = gear,
        strength = strength,
        talentPct = talentPct,
        calculated = calculated,
        api = apiValue,
        baseValue = baseValue,
        observedMin = observedMin or 0,
        observedAverage = observedAverage,
        observedMax = observedMax,
        observedCount = count,
        scanReady = details.scanReady,
        equippedItems = details.equippedItems or 0,
        scannedItems = details.scannedItems or 0
    }
end

local function GetBaseBlockValue(data)
    return GetBlockValueBreakdown(data or MT.data).baseValue
end

function MT:CaptureTargetDamage()
    if not UnitExists("target") or UnitIsFriend("player", "target") then return end
    local mob = UnitName("target")
    if not mob then return end

    local low, high, offLow, offHigh, posBuff, negBuff, percentMod = UnitDamage("target")
    low = tonumber(low) or 0
    high = tonumber(high) or 0
    offLow = tonumber(offLow) or 0
    offHigh = tonumber(offHigh) or 0
    posBuff = tonumber(posBuff) or 0
    negBuff = tonumber(negBuff) or 0
    percentMod = tonumber(percentMod) or 1

    if high > 0 and high >= low then
        local memory = self.targetDamageMemory[mob] or {}
        memory.minHit = low
        memory.maxHit = high
        memory.mainHandAverage = (low + high) / 2
        memory.offMinHit = offLow
        memory.offMaxHit = offHigh
        memory.dualWield = offLow > 0 and offHigh > 0 and offHigh >= offLow
        if memory.dualWield then
            memory.offHandAverage = (offLow + offHigh) / 2
            memory.avoidanceRawEstimate = (memory.mainHandAverage + memory.offHandAverage) / 2
            memory.estimateReason = "Live MH/OH average"
        else
            memory.offHandAverage = nil
            memory.avoidanceRawEstimate = memory.mainHandAverage
            memory.estimateReason = "Live main-hand average"
        end
        memory.positiveBuff = posBuff
        memory.negativeBuff = negBuff
        memory.damageModifier = percentMod
        memory.level = UnitLevel("target") or 0
        memory.source = "UnitDamage(target)"
        memory.capturedAt = GetTime()
        self.targetDamageMemory[mob] = memory

        if memory.dualWield then
            Debug(mob .. " live MH " .. format("%.1f-%.1f", low, high) ..
                " / OH " .. format("%.1f-%.1f", offLow, offHigh) ..
                " / avoided raw est " .. format("%.1f", memory.avoidanceRawEstimate))
        else
            Debug(mob .. " live MH " .. format("%.1f-%.1f", low, high))
        end
    end
end

local function GetTargetRawEstimate(mob)
    local memory = MT.targetDamageMemory[mob]
    if not memory or not memory.minHit or not memory.maxHit then return nil end

    if memory.avoidanceRawEstimate and memory.avoidanceRawEstimate > 0 then
        return memory.avoidanceRawEstimate, memory
    end

    local mainAverage = (memory.minHit + memory.maxHit) / 2
    if memory.offMinHit and memory.offMaxHit and memory.offMinHit > 0 and memory.offMaxHit > 0 then
        local offAverage = (memory.offMinHit + memory.offMaxHit) / 2
        return (mainAverage + offAverage) / 2, memory
    end
    return mainAverage, memory
end

local function EnsureMemory(root, mob, attack)
    if not root[mob] then root[mob] = {} end
    if not root[mob][attack] then
        root[mob][attack] = {
            minHit = nil,
            maxHit = nil,
            samples = 0
        }
    end
    return root[mob][attack]
end

local function UpdateRange(root, mob, attack, amount)
    if not mob or not attack or not amount or amount <= 0 then return end
    local memory = EnsureMemory(root, mob, attack)
    if not memory.minHit or amount < memory.minHit then memory.minHit = amount end
    if not memory.maxHit or amount > memory.maxHit then memory.maxHit = amount end
    memory.samples = memory.samples + 1
end

local function ObserveHit(mob, attack, postArmorAmount, isCrit)
    if isCrit then return end
    UpdateRange(MT.encounterMemory, mob, attack, postArmorAmount)
    UpdateRange(MT.sessionMemory, mob, attack, postArmorAmount)
    MT:ResolvePending(mob, attack)
end

local function GetEstimate(mob, attack)
    local memory = nil
    if MT.encounterMemory[mob] then memory = MT.encounterMemory[mob][attack] end
    if not memory and MT.sessionMemory[mob] then memory = MT.sessionMemory[mob][attack] end
    if not memory or not memory.minHit or not memory.maxHit then return nil end
    return (memory.minHit + memory.maxHit) / 2, memory
end

local function QueuePending(mob, attack, kind, school)
    if not MT.pending[mob] then MT.pending[mob] = {} end
    if not MT.pending[mob][attack] then MT.pending[mob][attack] = {} end
    table.insert(MT.pending[mob][attack], {kind = kind, school = school})
end


function MT:LearnAbilitySchool(mob, ability, school)
    if not mob or not ability or not school or school == "Physical" or school == "Unknown" then return end
    if not self.abilitySchoolMemory[mob] then self.abilitySchoolMemory[mob] = {} end
    self.abilitySchoolMemory[mob][ability] = school
end

function MT:GetAbilitySchool(mob, ability)
    if mob and ability and self.abilitySchoolMemory[mob] then
        return self.abilitySchoolMemory[mob][ability]
    end
    return nil
end

function MT:GetEventTime()
    if self.fightStartTime then
        local elapsed = GetTime() - self.fightStartTime
        if elapsed < 0 then elapsed = 0 end
        return elapsed
    end
    return 0
end

function MT:RecordEvent(eventData)
    if not eventData then return end
    eventData.time = eventData.time or self:GetEventTime()
    table.insert(self.events, eventData)
    AddToTimelineBucket(self.timeline, eventData)

    local overallEvent = CopyTable(eventData)
    -- Overall timeline is COMBAT TIME, not wall-clock session time. Idle time
    -- between pulls must never create empty 60-second pages. The completed
    -- combat duration accumulator is constant for the lifetime of this fight.
    overallEvent.time = (tonumber(self.overallCombatElapsed) or 0) + (tonumber(eventData.time) or 0)
    if overallEvent.time < 0 then overallEvent.time = 0 end
    table.insert(self.overallEvents, overallEvent)
    AddToTimelineBucket(self.overallTimeline, overallEvent)
    if self.profile then self.profile.overallElapsed = floor(overallEvent.time or 0) end
    if self.timelineFrame and self.timelineFrame:IsVisible() then
        self:UpdateTimelineWindow()
    end
end

function MT:BuildAvoidanceEvent(kind, mob, attack, postArmorAmount, school)
    postArmorAmount = postArmorAmount or 0
    school = school or "Physical"

    -- LAYEREDSTOP1 base model:
    --   Dodge/Parry/Miss never land, so the entire hypothetical RAW roll belongs
    --   to Avoidance and Armor receives zero credit.
    --   FullBlock/FullResist are landed terminal outcomes.  At the legacy layer
    --   we preserve Armor + terminal remainder; Core\Mitigation.lua later adds
    --   Flat/%DR from the event's exact mitigation snapshot.
    -- Partial blocks remain ordinary DAMAGE events.
    local rawAmount = postArmorAmount
    local armor = 0
    if school == "Physical" then
        local reduction = GetArmorReduction(mob)
        if reduction < 0.999 then rawAmount = postArmorAmount / (1 - reduction) end
        if kind == "FullBlock" or kind == "FullResist" then
            armor = rawAmount - postArmorAmount
            if armor < 0 then armor = 0 end
        end
    end
    if rawAmount < 0 then rawAmount = 0 end

    local pureAvoid = kind == "Dodge" or kind == "Parry" or kind == "Miss"
    return {
        time = self:GetEventTime(),
        source = mob or "Unknown",
        ability = attack or "Melee",
        school = school,
        kind = kind,
        raw = rawAmount,
        armor = pureAvoid and 0 or armor,
        block = kind == "FullBlock" and postArmorAmount or 0,
        avoidance = pureAvoid and rawAmount or 0,
        resist = kind == "FullResist" and postArmorAmount or 0,
        absorb = 0,
        taken = 0,
        physicalRaw = school == "Physical" and rawAmount or 0,
        magicRaw = school ~= "Physical" and rawAmount or 0,
        estimated = true
    }
end

function MT:BuildDamageEvent(mob, attack, amountTaken, blocked, resisted, absorbed, school, isCrit, hitType, ignoreArmor)
    amountTaken = amountTaken or 0
    blocked = blocked or 0
    resisted = resisted or 0
    absorbed = absorbed or 0
    school = school or "Physical"
    local postArmor = amountTaken + blocked + absorbed
    local raw = amountTaken + blocked + resisted + absorbed
    local armor = 0
    if school == "Physical" and not ignoreArmor then
        local reduction = GetArmorReduction(mob)
        if reduction < 0.999 then raw = postArmor / (1 - reduction) else raw = postArmor end
        armor = raw - postArmor
        if armor < 0 then armor = 0 end
    end
    return {
        time = self:GetEventTime(),
        source = mob or "Unknown",
        ability = attack or "Unknown",
        school = school,
        kind = "DAMAGE",
        raw = raw,
        armor = armor,
        block = blocked,
        avoidance = 0,
        resist = resisted,
        absorb = absorbed,
        taken = amountTaken,
        physicalRaw = school == "Physical" and raw or 0,
        magicRaw = school ~= "Physical" and raw or 0,
        critical = isCrit and true or false,
        crushing = hitType == "CRUSHING",
        environmental = hitType == "ENVIRONMENTAL",
        estimated = false
    }
end

function MT:ApplyAvoidanceToActiveData(kind, mob, postArmorAmount, school)
    local mobData = GetMobBucket(mob)
    postArmorAmount = postArmorAmount or 0
    school = school or "Physical"

    -- Keep the legacy aggregate as close as possible to the final event model.
    -- Pure avoidance owns the whole RAW estimate. FullBlock/FullResist are
    -- landed outcomes, so Armor keeps its pre-terminal share here; the final
    -- RC6 event rebuild adds any Flat/%DR that also preceded the terminal stop.
    local rawAmount = postArmorAmount
    local armor = 0
    if school == "Physical" then
        local reduction = GetArmorReduction(mob)
        if reduction < 0.999 then rawAmount = postArmorAmount / (1 - reduction) end
        if kind == "FullBlock" or kind == "FullResist" then
            armor = rawAmount - postArmorAmount
            if armor < 0 then armor = 0 end
            self.data.armorReduced = self.data.armorReduced + armor
        end
        self.data.physicalRaw = self.data.physicalRaw + rawAmount
    else
        self.data.magicRaw = self.data.magicRaw + rawAmount
    end
    if rawAmount < 0 then rawAmount = 0 end
    self.data.rawIncoming = self.data.rawIncoming + rawAmount

    if kind == "Dodge" then
        self.data.dodgeCount = self.data.dodgeCount + 1
        self.data.dodgedEstimated = self.data.dodgedEstimated + rawAmount
        mobData.dodgeCount = mobData.dodgeCount + 1
    elseif kind == "Parry" then
        self.data.parryCount = self.data.parryCount + 1
        self.data.parriedEstimated = self.data.parriedEstimated + rawAmount
        mobData.parryCount = mobData.parryCount + 1
    elseif kind == "Miss" then
        self.data.missCount = self.data.missCount + 1
        self.data.missedEstimated = self.data.missedEstimated + rawAmount
        mobData.missCount = mobData.missCount + 1
    elseif kind == "FullBlock" then
        self.data.fullBlockCount = self.data.fullBlockCount + 1
        self.data.fullBlockedEstimated = self.data.fullBlockedEstimated + postArmorAmount
    elseif kind == "FullResist" then
        self.data.fullResistCount = self.data.fullResistCount + 1
        self.data.resistedFullEstimated = self.data.resistedFullEstimated + postArmorAmount
        local schoolData = GetSchoolBucket(school or "Unknown")
        schoolData.fullCount = schoolData.fullCount + 1
        schoolData.fullEstimated = schoolData.fullEstimated + postArmorAmount
    end

    mobData.avoidedEstimated = mobData.avoidedEstimated +
        ((kind == "Dodge" or kind == "Parry" or kind == "Miss") and rawAmount or postArmorAmount)
end

function MT:ApplyAvoidance(kind, mob, postArmorAmount, school, attack)
    self:RecordEvent(self:BuildAvoidanceEvent(kind, mob, attack or "Melee", postArmorAmount, school))
    WithData(self.data, function() MT:ApplyAvoidanceToActiveData(kind, mob, postArmorAmount, school) end)
    WithData(self.overallData, function() MT:ApplyAvoidanceToActiveData(kind, mob, postArmorAmount, school) end)
end

function MT:RecordAvoidance(kind, mob, attack, school)
    self:CaptureTargetDamage()

    -- Full-resist combat messages usually omit the damage school. Reuse the
    -- school learned from a landed hit of the same mob ability when possible.
    if kind == "FullResist" and (not school or school == "Physical") then
        school = self:GetAbilitySchool(mob, attack) or "Unknown"
    end

    -- For white physical outcomes, UnitDamage(target) gives the preferred
    -- pre-mitigation swing range. The legacy ApplyAvoidance API carries a
    -- post-armor transport value. Core\Mitigation.lua snapshots the raw range
    -- and later applies the final outcome policy: pure avoidance gets all RAW,
    -- while Full Block keeps the preceding DR/Armor layers.
    if school == "Physical" and attack == "Melee" then
        local rawEstimate = GetTargetRawEstimate(mob)
        if rawEstimate then
            local reduction = GetArmorReduction(mob)
            local postArmorEstimate = rawEstimate * (1 - reduction)
            self:ApplyAvoidance(kind, mob, postArmorEstimate, school, attack)
            self:UpdateDisplay()
            return
        end
    end

    local estimate = GetEstimate(mob, attack)
    if estimate then
        self:ApplyAvoidance(kind, mob, estimate, school, attack)
    else
        QueuePending(mob, attack, kind, school)
        Debug(kind .. " pending for " .. mob .. " / " .. attack)
    end
    self:UpdateDisplay()
end

function MT:ResolvePending(mob, attack)
    if not self.pending[mob] or not self.pending[mob][attack] then return end
    local estimate = GetEstimate(mob, attack)
    if not estimate then return end

    local pendingList = self.pending[mob][attack]
    local i
    for i = 1, table.getn(pendingList) do
        local entry = pendingList[i]
        self:ApplyAvoidance(entry.kind, mob, estimate, entry.school, attack)
    end
    self.pending[mob][attack] = nil
    self:UpdateDisplay()
end

function MT:RecordDamageToActiveData(mob, attack, amountTaken, blocked, resisted, absorbed, school, isCrit, hitType, ignoreArmor)
    amountTaken = amountTaken or 0
    blocked = blocked or 0
    resisted = resisted or 0
    absorbed = absorbed or 0
    school = school or "Physical"

    local postArmor = amountTaken + blocked + absorbed
    local raw = amountTaken + blocked + resisted + absorbed
    if school == "Physical" then
        if not ignoreArmor then
            local reduction = GetArmorReduction(mob)
            if reduction < 0.999 then
                raw = postArmor / (1 - reduction)
            else
                raw = postArmor
            end
            local armor = raw - postArmor
            if armor < 0 then armor = 0 end
            self.data.armorReduced = self.data.armorReduced + armor
        else
            raw = amountTaken + blocked + resisted + absorbed
        end
        self.data.physicalRaw = self.data.physicalRaw + raw
    else
        self.data.magicRaw = self.data.magicRaw + raw
    end

    self.data.rawIncoming = self.data.rawIncoming + raw
    self.data.damageTaken = self.data.damageTaken + amountTaken
    if school == "Physical" then
        self.data.physicalTaken = self.data.physicalTaken + amountTaken
        if attack == "Melee" then self.data.meleeHitCount = self.data.meleeHitCount + 1 end
    else
        self.data.magicTaken = self.data.magicTaken + amountTaken
        self.data.magicHitCount = self.data.magicHitCount + 1
    end
    self.data.blocked = self.data.blocked + blocked
    if school == "Physical" then
        self.data.physicalBlocked = (self.data.physicalBlocked or 0) + blocked
    else
        self.data.magicBlocked = (self.data.magicBlocked or 0) + blocked
    end
    if blocked > 0 then
        if not self.data.minPartialBlock or blocked < self.data.minPartialBlock then self.data.minPartialBlock = blocked end
        if blocked > (self.data.maxPartialBlock or 0) then self.data.maxPartialBlock = blocked end
        self.data.totalPartialBlock = (self.data.totalPartialBlock or 0) + blocked
    end
    self.data.resistedPartial = self.data.resistedPartial + resisted
    self.data.absorbed = self.data.absorbed + absorbed

    if blocked > 0 then self.data.blockCount = self.data.blockCount + 1 end
    if resisted > 0 then self.data.partialResistCount = self.data.partialResistCount + 1 end
    if absorbed > 0 then self.data.absorbCount = self.data.absorbCount + 1 end

    local schoolData = GetSchoolBucket(school)
    schoolData.taken = schoolData.taken + amountTaken
    schoolData.partial = schoolData.partial + resisted

    local mobData = GetMobBucket(mob)
    mobData.taken = mobData.taken + amountTaken
    mobData.blocked = mobData.blocked + blocked
    if blocked > 0 then
        mobData.blockCount = (mobData.blockCount or 0) + 1
        if not mobData.blockMin or blocked < mobData.blockMin then mobData.blockMin = blocked end
        if blocked > (mobData.blockMax or 0) then mobData.blockMax = blocked end
        mobData.blockTotal = (mobData.blockTotal or 0) + blocked
    end
    mobData.resisted = mobData.resisted + resisted

    -- Learned melee/spell memory is post-armor but before block/absorb.
    ObserveHit(mob, attack, postArmor, isCrit or hitType == "CRUSHING" or hitType == "ENVIRONMENTAL")
end

function MT:RecordDamage(mob, attack, amountTaken, blocked, resisted, absorbed, school, isCrit, hitType, ignoreArmor)
    self:CaptureTargetDamage()
    self:LearnAbilitySchool(mob, attack, school)
    self:RecordEvent(self:BuildDamageEvent(mob, attack, amountTaken, blocked, resisted, absorbed, school, isCrit, hitType, ignoreArmor))
    WithData(self.data, function() MT:RecordDamageToActiveData(mob, attack, amountTaken, blocked, resisted, absorbed, school, isCrit, hitType, ignoreArmor) end)
    WithData(self.overallData, function() MT:RecordDamageToActiveData(mob, attack, amountTaken, blocked, resisted, absorbed, school, isCrit, hitType, ignoreArmor) end)
    self:UpdateDisplay()
end

local function ParseSuffixes(message)
    local blocked, resisted, absorbed = 0, 0, 0
    local value

    value = string.gsub(message, ".-%(([%d,]+) blocked%)", "%1")
    if value ~= message then blocked = SafeNumber(value) end

    value = string.gsub(message, ".-%(([%d,]+) resisted%)", "%1")
    if value ~= message then resisted = SafeNumber(value) end

    value = string.gsub(message, ".-%(([%d,]+) absorbed%)", "%1")
    if value ~= message then absorbed = SafeNumber(value) end

    return blocked, resisted, absorbed
end

local function DetectSchool(message)
    local low = lower(message)
    local key, label
    for key, label in pairs(DAMAGE_SCHOOLS) do
        if find(low, key, 1, true) then return label end
    end
    return "Physical"
end

function MT:ParseCombatMessage(message)
    if not message then return end
    Debug(message)

    local mob, amountText
    local blocked, resisted, absorbed = ParseSuffixes(message)
    local school = DetectSchool(message)
    local isCrit = find(message, " crits you for ", 1, true) ~= nil or find(message, " critically hits you for ", 1, true) ~= nil
    local hitType = isCrit and "CRITICAL" or "NORMAL"
    local spell

    -- Environmental damage uses combat-log families separate from creature and
    -- spell hits. Armor must not be reconstructed for falling/drowning/fatigue.
    _, _, amountText = find(message, "^You fall and lose ([%d,]+) health%.?$")
    if amountText then
        self:RecordDamage("Environment", "Falling", SafeNumber(amountText), 0, 0, absorbed, "Physical", false, "ENVIRONMENTAL", true)
        return
    end
    _, _, amountText = find(message, "^You are drowning and lose ([%d,]+) health%.$")
    if amountText then
        self:RecordDamage("Environment", "Drowning", SafeNumber(amountText), 0, 0, absorbed, "Physical", false, "ENVIRONMENTAL", true)
        return
    end
    _, _, amountText = find(message, "^You are exhausted and lose ([%d,]+) health%.$")
    if amountText then
        self:RecordDamage("Environment", "Fatigue", SafeNumber(amountText), 0, 0, absorbed, "Physical", false, "ENVIRONMENTAL", true)
        return
    end
    _, _, amountText = find(message, "^You suffer ([%d,]+) points? of fire damage%.?$")
    if amountText then
        self:RecordDamage("Environment", "Fire", SafeNumber(amountText), 0, resisted, absorbed, "Fire", false, "ENVIRONMENTAL", true)
        return
    end
    _, _, amountText = find(message, "^You suffer ([%d,]+) points of lava damage%.$")
    if amountText then
        self:RecordDamage("Environment", "Lava", SafeNumber(amountText), 0, resisted, absorbed, "Fire", false, "ENVIRONMENTAL", true)
        return
    end
    _, _, amountText = find(message, "^You lose ([%d,]+) health for swimming in lava%.$")
    if amountText then
        self:RecordDamage("Environment", "Lava", SafeNumber(amountText), 0, resisted, absorbed, "Fire", false, "ENVIRONMENTAL", true)
        return
    end

    -- Periodic damage / damage-over-time effects.
    local sourceText, schoolText
    _, _, amountText, schoolText, sourceText = find(message, "^You suffer ([%d,]+) ([%a]+) damage from (.+)%.")
    if amountText and sourceText then
        _, _, mob, spell = find(sourceText, "^(.+)'s (.+)$")
        if not mob then mob = sourceText; spell = "Periodic Damage" end
        school = DAMAGE_SCHOOLS[lower(schoolText or "")] or schoolText or DetectSchool(message)
        self:RecordDamage(mob, spell, SafeNumber(amountText), blocked, resisted, absorbed, school, false, "PERIODIC")
        return
    end
    _, _, amountText, sourceText = find(message, "^You suffer ([%d,]+) damage from (.+)%.")
    if amountText and sourceText then
        _, _, mob, spell = find(sourceText, "^(.+)'s (.+)$")
        if not mob then mob = sourceText; spell = "Periodic Damage" end
        self:RecordDamage(mob, spell, SafeNumber(amountText), blocked, resisted, absorbed, DetectSchool(message), false, "PERIODIC")
        return
    end

    -- Named abilities and spells, including critical variants. Match the
    -- critical forms before the generic "hits" form so Lua's greedy captures
    -- cannot fold the word "critically" into the ability name.
    _, _, mob, spell, amountText = find(message, "^(.+)'s (.+) crits you for ([%d,]+)")
    if mob then isCrit = true; hitType = "CRITICAL" end
    if not mob then
        _, _, mob, spell, amountText = find(message, "^(.+)'s (.+) critically hits you for ([%d,]+)")
        if mob then isCrit = true; hitType = "CRITICAL" end
    end
    if not mob then
        _, _, mob, spell, amountText = find(message, "^(.+)'s (.+) hits you for ([%d,]+)")
    end
    if mob and spell and amountText then
        self:RecordDamage(mob, spell, SafeNumber(amountText), blocked, resisted, absorbed, school, isCrit, hitType)
        return
    end

    -- White melee: normal, critical, and crushing blows.
    -- Match explicit critical forms first so the generic "hits" capture cannot
    -- turn "Princess Theradras critically hits..." into a mob named
    -- "Princess Theradras critically".
    _, _, mob, amountText = find(message, "^(.+) crits you for ([%d,]+)")
    if mob then isCrit = true; hitType = "CRITICAL" end
    if not mob then
        _, _, mob, amountText = find(message, "^(.+) critically hits you for ([%d,]+)")
        if mob then isCrit = true; hitType = "CRITICAL" end
    end
    if not mob then
        -- Vanilla commonly reports a crushing blow as an ordinary white hit
        -- with a trailing "(crushing)" marker:
        --   Mob hits you for 500. (crushing)
        -- Detect it before returning from the generic hit branch so the one
        -- authoritative event flag feeds Events, Highlights, Boss and Export.
        _, _, mob, amountText = find(message, "^(.+) hits you for ([%d,]+)")
        if mob and find(message, "(crushing)", 1, true) then
            isCrit = false
            hitType = "CRUSHING"
        end
    end
    if not mob then
        _, _, mob, amountText = find(message, "^(.+) crushes you for ([%d,]+)")
        if mob then hitType = "CRUSHING" end
    end
    if mob and amountText then
        self:RecordDamage(mob, "Melee", SafeNumber(amountText), blocked, resisted, absorbed, school, isCrit, hitType)
        return
    end

    -- Dodge / parry / miss / complete block.
    _, _, mob = find(message, "^(.+) attacks%. You dodge%.$")
    if mob then self:RecordAvoidance("Dodge", mob, "Melee", "Physical") return end
    _, _, mob = find(message, "^(.+) attacks%. You parry%.$")
    if mob then self:RecordAvoidance("Parry", mob, "Melee", "Physical") return end
    _, _, mob = find(message, "^(.+) misses you%.$")
    if mob then self:RecordAvoidance("Miss", mob, "Melee", "Physical") return end
    _, _, mob = find(message, "^(.+) attacks%. You block%.$")
    if mob then self:RecordAvoidance("FullBlock", mob, "Melee", "Physical") return end
    _, _, mob = find(message, "^You dodge (.+)'s attack%.$")
    if mob then self:RecordAvoidance("Dodge", mob, "Melee", "Physical") return end
    _, _, mob = find(message, "^You parry (.+)'s attack%.$")
    if mob then self:RecordAvoidance("Parry", mob, "Melee", "Physical") return end
    _, _, mob = find(message, "^You block (.+)'s attack%.$")
    if mob then self:RecordAvoidance("FullBlock", mob, "Melee", "Physical") return end

    -- Full spell resist.
    _, _, mob, spell = find(message, "^(.+)'s (.+) was resisted%.$")
    if not mob then _, _, mob, spell = find(message, "^(.+)'s (.+) is resisted%.$") end
    if mob and spell then self:RecordAvoidance("FullResist", mob, spell, school) return end
end

function MT:GetPendingCount()
    local count = 0
    local mob, attacks, attack, list
    for mob, attacks in pairs(self.pending) do
        for attack, list in pairs(attacks) do
            count = count + table.getn(list)
        end
    end
    return count
end

function MT:GetTotals(data)
    data = data or self.data
    local avoidance = data.dodgedEstimated + data.parriedEstimated + data.missedEstimated
    local mitigated = data.armorReduced + data.blocked + data.fullBlockedEstimated + data.resistedPartial + data.resistedFullEstimated + data.absorbed + avoidance
    return mitigated, data.rawIncoming
end


-- REFACXML1: session lifecycle, view-state selectors, migration, and base
-- persistence moved to Core\Session.lua.

-- REFACXML1: summary presentation and MainFrame XML binding moved to
-- UI\Summary.lua.

-- REFACXML1: base slash routing moved to Core\BaseCommands.lua.

-- REFACXML1: runtime initialization/event routing moved to Core\Runtime.lua.




-- ============================================================================
-- REFACXML1 private engine bridge
-- ============================================================================
-- Engine.lua owns the original lexical helpers. Extracted compatibility layers
-- receive the exact same closures/objects through this private runtime table,
-- preserving the historical override order without turning internals into
-- public addon APIs. Nothing under MT._engine is persisted to SavedVariables.
MT._engine = MT._engine or {}
MT._engine.NewData = NewData
MT._engine.DB_SCHEMA_VERSION = DB_SCHEMA_VERSION
MT._engine.NewTimelineBucket = NewTimelineBucket
MT._engine.CopyTable = CopyTable
MT._engine.Round = Round
MT._engine.Print = Print
MT._engine.AddToTimelineBucket = AddToTimelineBucket
MT._engine.GetArmorReduction = GetArmorReduction
MT._engine.GetScanTooltip = GetScanTooltip
MT._engine.PrepareInventoryTooltip = PrepareInventoryTooltip
MT._engine.CalculateBlockValue = CalculateBlockValue
MT._engine.GetBlockValueBreakdown = GetBlockValueBreakdown
MT._engine.GetBaseBlockValue = GetBaseBlockValue
