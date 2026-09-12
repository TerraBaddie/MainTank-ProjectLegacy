-- MainTank COMPARE1 - tank-summary sync hardening / RC6 extension
--
-- The original RC4/RC5 MTANK1 protocol is intentionally preserved so older
-- MainTank builds can still exchange the core compact summary.  Modern RC6
-- fields are sent as a second tiny MTANK2 extension message and merged into
-- the same stored summary.  This avoids changing the proven MTANK1 grouping,
-- history, or SavedVariables architecture while allowing Compare to display
-- Flat/Physical/Magic DR when both clients support it.

if not MainTank then return end
local MT = MainTank

local COMPARE_EXT_PREFIX = "MTANK2"
local COMPARE_EXT_VERSION = "1"

local function CompareSummaryKey(player, fightID)
    fightID = tonumber(fightID) or 0
    if fightID <= 0 then return nil end
    return tostring(player or "Unknown") .. "#" .. tostring(fightID)
end

local function CompareApplyExtension(summary, ext)
    if not summary or not ext then return false end
    summary.flatDR = tonumber(ext.flatDR) or 0
    summary.physicalDR = tonumber(ext.physicalDR) or 0
    summary.magicDR = tonumber(ext.magicDR) or 0
    summary.compareRC6 = true
    if (tonumber(summary.fightID) or 0) <= 0 and (tonumber(ext.fightID) or 0) > 0 then
        summary.fightID = tonumber(ext.fightID) or 0
    end
    if (tonumber(summary.endedAt) or 0) <= 0 and (tonumber(ext.endedAt) or 0) > 0 then
        summary.endedAt = tonumber(ext.endedAt) or 0
    end
    return true
end

-- RC6b rebuilt the summary constructors after RC5 had added fight identity.
-- Reassert that identity here, after the entire Mitigation stack is loaded.
local CompareOldBuildFromFight = MT.BuildTankSummaryFromFight
function MT:BuildTankSummaryFromFight(fight)
    local summary = CompareOldBuildFromFight(self, fight)
    if not summary or not fight then return summary end
    if not fight.endedAt then fight.endedAt = type(time) == "function" and time() or 0 end
    summary.fightID = tonumber(fight.id) or 0
    summary.endedAt = tonumber(fight.endedAt) or 0
    summary.flatDR = tonumber(summary.flatDR) or 0
    summary.physicalDR = tonumber(summary.physicalDR) or 0
    summary.magicDR = tonumber(summary.magicDR) or 0
    summary.compareRC6 = true
    return summary
end

local CompareOldBuildFromDisplay = MT.BuildTankSummaryFromDisplay
function MT:BuildTankSummaryFromDisplay()
    local summary = CompareOldBuildFromDisplay(self)
    if not summary then return summary end
    local fight
    if type(self.currentView) == "number" and self.fights then
        fight = self.fights[self.currentView]
    elseif self.currentView ~= "OVERALL" and self.fights then
        fight = self.fights[1]
    end
    if fight then
        if not fight.endedAt then fight.endedAt = type(time) == "function" and time() or 0 end
        summary.fightID = tonumber(fight.id) or 0
        summary.endedAt = tonumber(fight.endedAt) or 0
    else
        summary.fightID = tonumber(summary.fightID) or 0
        summary.endedAt = tonumber(summary.endedAt) or 0
    end
    summary.flatDR = tonumber(summary.flatDR) or 0
    summary.physicalDR = tonumber(summary.physicalDR) or 0
    summary.magicDR = tonumber(summary.magicDR) or 0
    summary.compareRC6 = true
    return summary
end

-- MTANK1 v1/v2 remains authoritative for the shared core fields.  Remote
-- summaries are marked as legacy-RC6 until their MTANK2 extension arrives.
local CompareOldDecode = MT.DecodeTankSummary
function MT:DecodeTankSummary(message, sender)
    local summary = CompareOldDecode(self, message, sender)
    if summary and not summary.localPlayer then
        summary.compareRC6 = false
    end
    return summary
end

MT.comparePendingExtensions = MT.comparePendingExtensions or {}

local function CompareFindAndMerge(owner, sender, ext)
    local merged = false
    local fightID = tonumber(ext and ext.fightID) or 0
    if fightID <= 0 then return false end

    local i, summary
    for i = 1, table.getn(owner.tankComparisonHistory or {}) do
        summary = owner.tankComparisonHistory[i]
        if summary and tostring(summary.player or "Unknown") == tostring(sender or "Unknown") and
           (tonumber(summary.fightID) or 0) == fightID then
            CompareApplyExtension(summary, ext)
            merged = true
        end
    end

    if owner.tankComparisonLatest then
        summary = owner.tankComparisonLatest[sender]
        if summary and (tonumber(summary.fightID) or 0) == fightID then
            CompareApplyExtension(summary, ext)
            merged = true
        end
    end
    return merged
end

local CompareOldStore = MT.StoreTankSummary
function MT:StoreTankSummary(summary)
    if not summary then return CompareOldStore(self, summary) end
    if summary.localPlayer and summary.compareRC6 == nil then summary.compareRC6 = true end

    local key = CompareSummaryKey(summary.player, summary.fightID)
    local pending = key and self.comparePendingExtensions and self.comparePendingExtensions[key]
    if pending then
        CompareApplyExtension(summary, pending)
        self.comparePendingExtensions[key] = nil
    end
    return CompareOldStore(self, summary)
end

local function CompareEncodeExtension(summary)
    if not summary or (tonumber(summary.fightID) or 0) <= 0 then return nil end
    return table.concat({
        COMPARE_EXT_VERSION,
        tostring(math.floor(tonumber(summary.fightID) or 0)),
        tostring(math.floor(tonumber(summary.endedAt) or 0)),
        tostring(math.floor(tonumber(summary.flatDR) or 0)),
        tostring(math.floor(tonumber(summary.physicalDR) or 0)),
        tostring(math.floor(tonumber(summary.magicDR) or 0))
    }, ";")
end

local CompareOldSend = MT.SendTankSummary
function MT:SendTankSummary(summary, quiet)
    local sent = CompareOldSend(self, summary, quiet)
    if not sent or type(SendAddonMessage) ~= "function" then return sent end

    local message = CompareEncodeExtension(summary)
    if not message then return sent end

    local channel
    if GetNumRaidMembers() > 0 then channel = "RAID"
    elseif GetNumPartyMembers() > 0 then channel = "PARTY"
    end
    if channel then SendAddonMessage(COMPARE_EXT_PREFIX, message, channel) end
    return sent
end

local function CompareDecodeExtension(message)
    local fields = {}
    local start = 1
    local pos
    message = tostring(message or "")
    while true do
        pos = string.find(message, ";", start, true)
        if not pos then
            table.insert(fields, string.sub(message, start))
            break
        end
        table.insert(fields, string.sub(message, start, pos - 1))
        start = pos + 1
    end
    if fields[1] ~= COMPARE_EXT_VERSION or table.getn(fields) < 6 then return nil end
    local ext = {
        fightID = tonumber(fields[2]) or 0,
        endedAt = tonumber(fields[3]) or 0,
        flatDR = tonumber(fields[4]) or 0,
        physicalDR = tonumber(fields[5]) or 0,
        magicDR = tonumber(fields[6]) or 0
    }
    if ext.fightID <= 0 then return nil end
    return ext
end

-- Separate listener: do not rewrite or replace the proven MTANK1 receiver.
local CompareExtFrame = CreateFrame("Frame", "MainTankTankSyncRC6Frame")
CompareExtFrame:RegisterEvent("CHAT_MSG_ADDON")
CompareExtFrame:SetScript("OnEvent", function()
    if event ~= "CHAT_MSG_ADDON" or arg1 ~= COMPARE_EXT_PREFIX then return end
    local sender = arg4 or "Unknown"
    if sender == (MT.playerName or UnitName("player")) then return end
    local ext = CompareDecodeExtension(arg2)
    if not ext then return end

    if CompareFindAndMerge(MT, sender, ext) then
        MT:SyncPersistentData()
        if MT.compareFrame and MT.compareFrame:IsVisible() then MT:UpdateTankCompareWindow() end
    else
        local key = CompareSummaryKey(sender, ext.fightID)
        if key then MT.comparePendingExtensions[key] = ext end
    end
end)
