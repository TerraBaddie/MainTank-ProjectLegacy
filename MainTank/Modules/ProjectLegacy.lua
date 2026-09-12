-- MainTank - Project Legacy compatibility
-- Keep the Project Legacy fork intentionally narrow:
--   * vanilla-style Strength block scaling: 20 Strength = 1 block value
--   * Blessing of Sanctuary and all other MainTank mitigation logic unchanged

if not MainTank then return end
local MT = MainTank
local E = MT._engine

-- BlockAnalysis.lua owns the authoritative calculation on this branch and uses
-- (Strength / 20) - 1. This late presentation override keeps the Physical-page
-- Block Analysis tooltip consistent with that Project Legacy rule without
-- changing unrelated shared UI behavior.
function MT:ShowBlockValueTooltip(owner)
    if self.currentPage ~= "PHYSICAL" then return end

    -- Force the bounded BlockAnalysis pass so the displayed breakdown is fresh.
    self:RefreshBlockValue(true)

    local data = self:GetDisplayData()
    local details = E.GetBlockValueBreakdown(data)
    local tooltip = MT:GetAnalysisTooltip()

    tooltip:SetOwner(owner, "ANCHOR_RIGHT")
    tooltip:SetText("Block Analysis", 1, 0.82, 0)
    tooltip:AddDoubleLine("Base Block Value", self:FormatNumber(details.baseValue), 1, 0.82, 0, 1, 0.82, 0)
    tooltip:AddLine(" ")

    tooltip:AddLine("Calculated Sources", 0.55, 0.8, 1)
    tooltip:AddDoubleLine("Shield and gear", self:FormatNumber(details.gear), 0.82, 0.82, 0.82, 1, 1, 1)
    tooltip:AddDoubleLine("Strength (20 = 1)", self:FormatNumber(details.strength), 0.82, 0.82, 0.82, 1, 1, 1)
    tooltip:AddDoubleLine("Talent bonus", "+" .. self:FormatNumber(details.talentPct) .. "%", 0.82, 0.82, 0.82, 1, 1, 1)
    if details.api and details.api > 0 then
        tooltip:AddDoubleLine("Client API", self:FormatNumber(details.api), 0.82, 0.82, 0.82, 1, 1, 1)
    end
    if details.scanReady == false then
        tooltip:AddLine("Equipment scan retrying...", 1, 0.55, 0.2)
    end

    tooltip:AddLine(" ")
    tooltip:AddLine("Observed Partial Blocks", 0.55, 0.8, 1)
    if details.observedCount > 0 then
        tooltip:AddDoubleLine("Lowest", self:FormatNumber(details.observedMin), 0.82, 0.82, 0.82, 1, 1, 1)
        tooltip:AddDoubleLine("Average", self:FormatNumber(details.observedAverage), 0.82, 0.82, 0.82, 1, 1, 1)
        tooltip:AddDoubleLine("Highest", self:FormatNumber(details.observedMax), 0.82, 0.82, 0.82, 1, 1, 1)
        tooltip:AddDoubleLine("Samples", tostring(details.observedCount), 0.82, 0.82, 0.82, 1, 1, 1)
    else
        tooltip:AddLine("No exact samples in this view.", 0.68, 0.68, 0.68)
    end

    local targetName = UnitExists("target") and UnitName("target") or nil
    local mobData = targetName and data.mobs and data.mobs[targetName] or nil
    if mobData and (mobData.blockCount or 0) > 0 then
        local avg = (mobData.blockTotal or 0) / mobData.blockCount
        tooltip:AddLine(" ")
        tooltip:AddLine(targetName, 1, 0.82, 0)
        tooltip:AddDoubleLine("Low / Avg / High", self:FormatNumber(mobData.blockMin) .. " / " .. self:FormatNumber(avg) .. " / " .. self:FormatNumber(mobData.blockMax), 0.82, 0.82, 0.82, 1, 1, 1)
        tooltip:AddDoubleLine("Samples", tostring(mobData.blockCount), 0.82, 0.82, 0.82, 1, 1, 1)
    end

    tooltip:AddLine(" ")
    tooltip:AddLine("Project Legacy uses vanilla-style 20 Strength = 1 Block Value.", 0.7, 0.8, 1)
    tooltip:AddLine("Observed values do not replace the Base Block Value.", 0.7, 0.8, 1)
    tooltip:Show()
end


-- ============================================================================
-- Project Legacy Sanctuary final compatibility layer (PL5)
--
-- Core\Mitigation.lua contains a long historical override stack.  Earlier
-- Sanctuary scanners are intentionally replaced by later RC6 layers, so PL
-- compatibility must wrap the FINAL RC5B_ScanPlayerBuffs implementation here,
-- after Core\Mitigation.lua and every later historical override has loaded.
--
-- Project Legacy keeps vanilla Sanctuary semantics for MainTank:
-- flat damage reduction applies to all incoming damage sources.
-- ============================================================================

local PL_SANCTUARY_BASE = { [1] = 10, [2] = 15, [3] = 20, [4] = 30 }

local function PL_IsSanctuaryEffect(effect)
    if not effect then return false end
    local name = string.lower(tostring(effect.name or ""))
    if string.find(name, "blessing of sanctuary", 1, true) then return true end

    local desc = string.lower(tostring(effect.description or ""))
    if string.find(desc, "damage taken reduced by up to", 1, true) or
       string.find(desc, "reduces damage taken by up to", 1, true) or
       string.find(desc, "reducing damage taken by up to", 1, true) then
        return true
    end
    return false
end

local function PL_ParseSanctuaryBase(text)
    text = string.lower(tostring(text or ""))
    local _, _, value = string.find(text, "damage taken reduced by up to%s+(%d+)")
    if not value then _, _, value = string.find(text, "reduces damage taken by up to%s+(%d+)") end
    if not value then _, _, value = string.find(text, "reducing damage taken by up to%s+(%d+)") end
    value = tonumber(value)
    if value == 10 or value == 15 or value == 20 or value == 30 then return value end
    return nil
end

local function PL_ApplySanctuaryRank(effect, rank, source)
    rank = tonumber(rank) or 0
    local base = PL_SANCTUARY_BASE[rank]
    if not effect or not base then return false end

    effect.name = "Blessing of Sanctuary"
    effect.kind = "flatDR"
    effect.known = true
    effect.school = "all"
    effect.rank = rank
    effect.value = base
    effect.baseValue = base
    effect.sanctuaryRankUnknown = nil
    effect.rankSource = source or "Project Legacy"
    effect.label = "Sanctuary Rank " .. tostring(rank) .. " / " .. tostring(base) .. " base flat"
    return true
end

local PL_PreviousScanPlayerBuffs = RC5B_ScanPlayerBuffs
if type(PL_PreviousScanPlayerBuffs) == "function" then
    function RC5B_ScanPlayerBuffs()
        local results = PL_PreviousScanPlayerBuffs() or {}
        local sanctuary = nil
        local i, effect

        -- First repair any Sanctuary already recognized by the final RC6 stack.
        for i = 1, table.getn(results) do
            effect = results[i]
            if PL_IsSanctuaryEffect(effect) then
                sanctuary = effect
                effect.name = "Blessing of Sanctuary"
                effect.kind = "flatDR"
                effect.known = true
                effect.school = "all"

                if (tonumber(effect.value) or 0) <= 0 then
                    local base = PL_ParseSanctuaryBase(
                        tostring(effect.name or "") .. " " .. tostring(effect.description or "")
                    )

                    if base then
                        if base == 10 then PL_ApplySanctuaryRank(effect, 1, "Project Legacy aura tooltip")
                        elseif base == 15 then PL_ApplySanctuaryRank(effect, 2, "Project Legacy aura tooltip")
                        elseif base == 20 then PL_ApplySanctuaryRank(effect, 3, "Project Legacy aura tooltip")
                        elseif base == 30 then PL_ApplySanctuaryRank(effect, 4, "Project Legacy aura tooltip")
                        end
                    end

                    -- Exact recent local cast rank is preferred when available.
                    if (tonumber(effect.value) or 0) <= 0 and type(RC6D_GetRecentSanctuaryCastRank) == "function" then
                        local recentRank = RC6D_GetRecentSanctuaryCastRank()
                        if recentRank then
                            PL_ApplySanctuaryRank(effect, recentRank, "Project Legacy recent cast")
                        end
                    end

                    -- RC6n keeps a confirmed rank authoritative for one
                    -- continuous aura. Reuse it if the current tooltip is hidden.
                    if (tonumber(effect.value) or 0) <= 0 then
                        local stickyRank = tonumber(MT.rc6nActiveSanctuaryRank) or 0
                        if stickyRank >= 1 and stickyRank <= 4 then
                            PL_ApplySanctuaryRank(effect, stickyRank, "Project Legacy continuous aura")
                        end
                    end

                    -- Safe login/reload fallback: if only Rank 1 is learned,
                    -- there is no possible down-rank ambiguity. This is the
                    -- important Project Legacy low-level case seen in testing.
                    if (tonumber(effect.value) or 0) <= 0 then
                        local maxLearned = tonumber(effect.maxLearnedRank) or 0
                        if maxLearned == 1 then
                            PL_ApplySanctuaryRank(effect, 1, "Project Legacy only learned rank")
                        end
                    end
                end
                break
            end
        end

        -- If Sanctuary is active but the final scanner exposed only the icon,
        -- recover it from the vanilla player-buff texture. Do NOT assume the
        -- highest learned rank except when Rank 1 is literally the only rank.
        if not sanctuary and type(GetPlayerBuff) == "function" and
           type(GetPlayerBuffTexture) == "function" and
           type(RC5B_GetSanctuarySpellInfo) == "function" and
           type(RC5B_IsSanctuaryTexture) == "function" then

            local learnedTexture, maxLearnedRank = RC5B_GetSanctuarySpellInfo()
            local slot = 0
            while slot <= 31 do
                local buffIndex = GetPlayerBuff(slot, "HELPFUL")
                if buffIndex and buffIndex >= 0 then
                    local texture = GetPlayerBuffTexture(buffIndex)
                    if texture and RC5B_IsSanctuaryTexture(texture, learnedTexture) then
                        sanctuary = {
                            name = "Blessing of Sanctuary",
                            description = "",
                            kind = "flatDR",
                            known = true,
                            school = "all",
                            texture = texture,
                            buffIndex = buffIndex,
                            rank = 0,
                            value = 0,
                            sanctuaryRankUnknown = true,
                            maxLearnedRank = maxLearnedRank,
                            label = "Sanctuary active / rank unresolved"
                        }

                        local recentRank = nil
                        if type(RC6D_GetRecentSanctuaryCastRank) == "function" then
                            recentRank = RC6D_GetRecentSanctuaryCastRank()
                        end

                        if recentRank then
                            PL_ApplySanctuaryRank(sanctuary, recentRank, "Project Legacy recent cast")
                        elseif tonumber(MT.rc6nActiveSanctuaryRank) and
                               tonumber(MT.rc6nActiveSanctuaryRank) >= 1 and
                               tonumber(MT.rc6nActiveSanctuaryRank) <= 4 then
                            PL_ApplySanctuaryRank(
                                sanctuary,
                                tonumber(MT.rc6nActiveSanctuaryRank),
                                "Project Legacy continuous aura"
                            )
                        elseif tonumber(maxLearnedRank) == 1 then
                            PL_ApplySanctuaryRank(sanctuary, 1, "Project Legacy only learned rank")
                        end

                        table.insert(results, sanctuary)
                        break
                    end
                end
                slot = slot + 1
            end
        end

        return results
    end
end

-- The stock DR page hides zero-valued unresolved Sanctuary as "None detected".
-- On Project Legacy, show that the aura is active even if rank could not be
-- proven yet; combat inference can still resolve a higher-rank/down-rank case.
local PL_PreviousUpdateDRWindow = MT.UpdateDRWindow
function MT:UpdateDRWindow()
    local frame = PL_PreviousUpdateDRWindow(self)

    -- If the normal page still says None detected, check whether the final
    -- Project Legacy scanner at least sees Sanctuary as an active unresolved aura.
    self:RefreshMitigationContextCache(true)
    local attacker = UnitExists("target") and UnitName("target") or nil
    local context = self:CaptureMitigationContext(attacker)
    local unresolved = false
    local i, effect

    for i = 1, table.getn(context and context.buffs or {}) do
        effect = context.buffs[i]
        if PL_IsSanctuaryEffect(effect) then
            if (tonumber(effect.value) or 0) > 0 then
                -- Normal DR page already displays resolved Sanctuary.
                return frame
            end
            unresolved = true
            break
        end
    end

    if unresolved and self.drFrame and self.drFrame.drRows then
        local rows = self.drFrame.drRows
        for i = 1, table.getn(rows) do
            if rows[i] and rows[i].label and rows[i].label.GetText and
               rows[i].label:GetText() == "None detected" then
                rows[i].label:SetText("Blessing of Sanctuary")
                if rows[i].value then rows[i].value:SetText("Active (rank unresolved)") end
                break
            end
        end
    end
    return frame
end
