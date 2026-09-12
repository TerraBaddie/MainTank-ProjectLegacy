-- MainTank v1.0.0 FR1S
-- Modules/BlockAnalysis.lua
-- Finalized, bounded block-value reconstruction extracted from Core/Engine.lua.
-- No background retry loop is allowed in this module.

if not MainTank then return end
local MT = MainTank
local floor = math.floor

local function ParseBlockFromItemLine(text)
    local s, value
    if not text then return 0 end
    s = string.lower(tostring(text))
    _, _, value = string.find(s, "^block%s*:%s*%+?(%d+)%s*$")
    if not value then _, _, value = string.find(s, "^block%s+%+?(%d+)%s*$") end
    if not value then _, _, value = string.find(s, "^%+?(%d+)%s+block%s*$") end
    if not value then _, _, value = string.find(s, "block value%s*%+%s*(%d+)") end
    if not value then _, _, value = string.find(s, "block value%s*%+?(%d+)") end
    if not value then _, _, value = string.find(s, "increases the block value of your shield by%s+(%d+)") end
    if not value then _, _, value = string.find(s, "increases your shield block value by%s+(%d+)") end
    return tonumber(value) or 0
end

local function GetShieldSpecializationPercent()
    local tab, talent, name, rank
    for tab = 1, GetNumTalentTabs() do
        for talent = 1, GetNumTalents(tab) do
            name, _, _, _, rank = GetTalentInfo(tab, talent)
            if name == "Shield Specialization" then
                rank = tonumber(rank) or 0
                -- Project Legacy uses three ranks: 10% / 20% / 30%.
                -- Do not inherit VanillaPlus' historical 15% / 30% mapping.
                if rank < 1 then return 0, "Project Legacy talent rank" end
                if rank > 3 then rank = 3 end
                return rank * 10, "Project Legacy talent rank"
            end
        end
    end
    return 0, "not learned"
end

local function ScanAllBlockGearOnce()
    local total, equippedItems, scannedItems = 0, 0, 0
    local sources = {}
    local slot, link, lines, source, i, amount

    for slot = 0, 19 do
        link = GetInventoryItemLink("player", slot)
        if link then
            equippedItems = equippedItems + 1
            if MT.LoadInventoryTooltip then lines, source = MT:LoadInventoryTooltip(slot) else lines, source = {}, "none" end
            if lines and table.getn(lines) > 0 then scannedItems = scannedItems + 1 end
            for i = 1, table.getn(lines or {}) do
                amount = ParseBlockFromItemLine(lines[i])
                if amount and amount > 0 then
                    total = total + amount
                    table.insert(sources, {slot=slot, value=amount, source=source or "tooltip", text=tostring(lines[i] or "")})
                end
            end
        end
    end
    return total, equippedItems, scannedItems, sources
end

function MT:CalculateBlockValue()
    local gear, equippedItems, scannedItems, gearSources = ScanAllBlockGearOnce()

    local _, strength = UnitStat("player", 1)
    strength = tonumber(strength) or 0
    -- Project Legacy / vanilla-style rule: 20 Strength = 1 block value,
    -- preserving the historical one-point baseline correction already used by MT.
    -- BetterCharacterStats/vanilla floors the final value; do not round to nearest.
    local strengthValue = (strength / 20) - 1
    if strengthValue < 0 then strengthValue = 0 end

    local talentPct, talentSource = GetShieldSpecializationPercent()
    local apiValue = 0
    if type(GetShieldBlock) == "function" then apiValue = tonumber(GetShieldBlock()) or 0 end

    local directGearFound = gear > 0
    local gearInferred = false
    local gearSource = directGearFound and "BCS/GameTooltip" or "none"

    if not directGearFound and apiValue > 0 then
        local divisor = 1 + ((talentPct or 0) / 100)
        if divisor <= 0 then divisor = 1 end
        local beforeTalent = apiValue / divisor
        local inferred = floor((beforeTalent - strengthValue) + 0.5)
        if inferred > 0 then
            gear = inferred
            gearInferred = true
            gearSource = "Client API inference"
        end
    end

    local preTalent = gear + strengthValue
    local calculated = floor(preTalent * (1 + ((talentPct or 0) / 100)))
    if calculated < 0 then calculated = 0 end

    local value = calculated
    if not directGearFound and apiValue > 0 then value = apiValue end

    self.cachedBlockDetails = {
        gear = gear,
        strength = strengthValue,
        talentPct = talentPct or 0,
        scanReady = true,
        equippedItems = equippedItems,
        scannedItems = scannedItems,
        gearSources = gearSources,
        gearInferred = gearInferred,
        gearScanSource = gearSource,
        talentScanSource = talentSource or "none",
        api = apiValue,
        calculated = calculated,
        preTalent = preTalent
    }

    -- Stability invariant: never self-schedule another tooltip scan.
    self.blockValueRetryAt = nil
    self.blockValueRetryCount = 0
    return value
end

-- Force exactly one fresh bounded pass for interactive explanation/reporting.
local PreviousShowBlockValueTooltip = MT.ShowBlockValueTooltip
function MT:ShowBlockValueTooltip(owner)
    self:RefreshBlockValue(true)
    PreviousShowBlockValueTooltip(self, owner)
end

local PreviousPrintBlockReport = MT.PrintBlockReport
function MT:PrintBlockReport()
    self:RefreshBlockValue(true)
    PreviousPrintBlockReport(self)
end

