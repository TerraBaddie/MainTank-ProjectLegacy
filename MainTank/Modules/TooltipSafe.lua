-- MainTank TOOLTIPSAFE1
-- Project Legacy combat-tooltip safety and equipment-scan throttling.
--
-- Goals:
--   1) Full equipped-item DR scan exactly once at combat start.
--   2) Never borrow, clear, re-owner, or hide an already-visible GameTooltip.
--   3) The 0.75s mitigation-context refresh reuses cached equipment DR only.
--   4) During combat, only changed weapon/off-hand/ranged slots are rescanned.
--   5) Buff/debuff/active-DR refresh cadence remains unchanged.
--
-- This module loads last so it can safely wrap the final RC6/Project Legacy
-- scanner stack without rewriting the historical mitigation implementation.

if not MainTank then return end
local MT = MainTank
local E = MT._engine
local eventFrame = E and E.eventFrame

local TS_WEAPON_SLOTS = {16, 17, 18}

local function TS_IsGameTooltipVisible()
    if not GameTooltip then return false end
    if GameTooltip.IsShown then
        local ok, shown = pcall(function() return GameTooltip:IsShown() end)
        if ok and shown then return true end
    end
    if GameTooltip.IsVisible then
        local ok, visible = pcall(function() return GameTooltip:IsVisible() end)
        if ok and visible then return true end
    end
    return false
end

local function TS_HideOwnedScannerTooltip(tip)
    if tip and tip.Hide then pcall(function() tip:Hide() end) end
end

-- Safe replacement for RC6j's inventory-tooltip loader.
-- BetterCharacterStats' dedicated scanner remains preferred. The live
-- GameTooltip is permitted only while it is NOT already visible to the player.
-- MainTank's hidden tooltip remains the final fallback.
local function TS_LoadInventoryTooltip(slot)
    local tip, lines

    -- 1) Dedicated BetterCharacterStats scanner. This is not the player's live
    -- tooltip and is safe to reuse repeatedly.
    tip = getglobal and getglobal("BetterCharacterStatsTooltip") or nil
    if tip and type(RC6J_ScanWithTooltip) == "function" then
        lines = RC6J_ScanWithTooltip(tip, "BetterCharacterStatsTooltip", slot)
        if type(RC6J_HasUsefulItemText) ~= "function" or RC6J_HasUsefulItemText(lines) then
            return lines or {}, "BCS"
        end
    end

    -- 2) The built-in GameTooltip may contain private-server green Equip text
    -- that hidden scanners cannot see. Borrow it ONLY when it is currently
    -- hidden. Never touch a tooltip the player is looking at.
    if GameTooltip and not TS_IsGameTooltipVisible() and type(RC6J_ScanWithTooltip) == "function" then
        lines = RC6J_ScanWithTooltip(GameTooltip, "GameTooltip", slot)
        TS_HideOwnedScannerTooltip(GameTooltip)
        if type(RC6J_HasUsefulItemText) ~= "function" or RC6J_HasUsefulItemText(lines) then
            return lines or {}, "GameTooltip"
        end
    end

    -- 3) MainTank's own hidden tooltip. It is always safe to clear/hide.
    if RC6I_GearTooltip and type(RC6J_ScanWithTooltip) == "function" then
        lines = RC6J_ScanWithTooltip(RC6I_GearTooltip, RC6I_GearPrefix or "MainTankGearTooltip", slot)
        TS_HideOwnedScannerTooltip(RC6I_GearTooltip)
        if type(RC6J_HasUsefulItemText) ~= "function" or RC6J_HasUsefulItemText(lines) then
            return lines or {}, "MTTooltip"
        end
    end

    return lines or {}, "none"
end

-- Make diagnostics and any remaining callers inherit the same visible-tooltip
-- safety rule. No caller below is allowed to unconditionally hide GameTooltip.
RC6J_LoadInventoryTooltip = TS_LoadInventoryTooltip

local function TS_FindCachedEffectForSlot(slot)
    local i, effect
    for i = 1, table.getn(MT.rc5EquipmentDR or {}) do
        effect = MT.rc5EquipmentDR[i]
        if effect and tonumber(effect.slot) == slot then return effect end
    end
    return nil
end

local function TS_ScanEquipmentSlot(slot)
    local link = GetInventoryItemLink("player", slot)
    if not link then return nil, nil end

    local name = nil
    local _, _, linkedName = string.find(link, "%[(.-)%]")
    name = linkedName

    local lines, source = TS_LoadInventoryTooltip(slot)
    local i, kind, value
    for i = 1, table.getn(lines or {}) do
        if type(RC6I_ParseItemDRLine) == "function" then
            kind, value = RC6I_ParseItemDRLine(lines[i])
        else
            kind, value = nil, nil
        end
        if kind and value and value > 0 then
            return {
                name = name or "Equipped item",
                kind = kind,
                value = value,
                known = true,
                source = "item",
                slot = slot,
                tooltipSource = source
            }, link
        end
    end

    return nil, link
end

local function TS_FullEquipmentScan()
    local results = {}
    local previousLinks = MT.tooltipSafeEquipmentLinks or {}
    local newLinks = {}
    local slot, effect, link, cached

    for slot = 0, 19 do
        effect, link = TS_ScanEquipmentSlot(slot)
        newLinks[slot] = link

        if effect then
            table.insert(results, effect)
        elseif link and previousLinks[slot] == link then
            -- If the live GameTooltip was visible and therefore intentionally
            -- unavailable, preserve a previously-proven DR effect for the same
            -- exact item rather than silently dropping it for this fight.
            cached = TS_FindCachedEffectForSlot(slot)
            if cached then table.insert(results, cached) end
        end
    end

    MT.tooltipSafeEquipmentLinks = newLinks
    MT.tooltipSafeWeaponLinks = {
        [16] = newLinks[16],
        [17] = newLinks[17],
        [18] = newLinks[18]
    }
    MT.tooltipSafeEquipmentStale = false
    TS_HideOwnedScannerTooltip(RC6I_GearTooltip)
    return results
end

-- Keep the named RC6k scanner useful for explicit diagnostics (/mt itemdr),
-- but replace its implementation so it never hides a visible GameTooltip.
RC6K_ScanEquippedDR = TS_FullEquipmentScan

-- Critical TOOLTIPSAFE1 change: the normal mitigation-context refresh calls
-- RC5B_ScanEquippedDR every 0.75s in combat. Replace that function with a pure
-- cache read. This removes ALL equipment tooltip scanning from the fast loop.
RC5B_ScanEquippedDR = function()
    return MT.rc5EquipmentDR or {}
end

local function TS_ReplaceSlotEffect(slot)
    local old = MT.rc5EquipmentDR or {}
    local updated = {}
    local i, effect, newEffect, link

    for i = 1, table.getn(old) do
        effect = old[i]
        if not effect or tonumber(effect.slot) ~= slot then
            table.insert(updated, effect)
        end
    end

    newEffect, link = TS_ScanEquipmentSlot(slot)
    if newEffect then table.insert(updated, newEffect) end

    MT.rc5EquipmentDR = updated
    MT.tooltipSafeEquipmentLinks = MT.tooltipSafeEquipmentLinks or {}
    MT.tooltipSafeEquipmentLinks[slot] = link
    MT.tooltipSafeWeaponLinks = MT.tooltipSafeWeaponLinks or {}
    MT.tooltipSafeWeaponLinks[slot] = link

    -- The next combat event should capture a new context ID containing the
    -- changed weapon/off-hand item DR state.
    MT.rc5ContextCacheAt = nil
end

local function TS_CheckCombatWeaponChanges()
    if not MT.inCombat then return end

    MT.tooltipSafeWeaponLinks = MT.tooltipSafeWeaponLinks or {}
    local i, slot, oldLink, newLink
    for i = 1, table.getn(TS_WEAPON_SLOTS) do
        slot = TS_WEAPON_SLOTS[i]
        oldLink = MT.tooltipSafeWeaponLinks[slot]
        newLink = GetInventoryItemLink("player", slot)
        if oldLink ~= newLink then
            TS_ReplaceSlotEffect(slot)
        end
    end
end

-- Full equipment snapshot exactly once per combat. The existing StartCombat
-- logic remains authoritative for fight/session state; we only seed the static
-- equipment portion of the mitigation context before it begins updating.
local TS_PreviousStartCombat = MT.StartCombat
function MT:StartCombat()
    self.rc5EquipmentDR = TS_FullEquipmentScan()
    self.rc5ContextCacheAt = nil
    TS_PreviousStartCombat(self)
end

-- Existing Runtime.lua already registers these events. We add a final wrapper
-- rather than registering another frame so TOOLTIPSAFE1 observes the same event
-- stream as MainTank's authoritative runtime.
if eventFrame and eventFrame.GetScript and eventFrame.SetScript then
    local TS_PreviousOnEvent = eventFrame:GetScript("OnEvent")
    eventFrame:SetScript("OnEvent", function()
        local currentEvent = event
        local currentArg1 = arg1

        if TS_PreviousOnEvent then TS_PreviousOnEvent() end

        if currentEvent == "PLAYER_EQUIPMENT_CHANGED" then
            if MT.inCombat then
                TS_CheckCombatWeaponChanges()
            else
                -- No background/out-of-combat rescan is needed. The next
                -- StartCombat always takes one authoritative full snapshot.
                MT.tooltipSafeEquipmentStale = true
            end
        elseif currentEvent == "UNIT_INVENTORY_CHANGED" then
            if not currentArg1 or currentArg1 == "player" then
                if MT.inCombat then
                    TS_CheckCombatWeaponChanges()
                else
                    MT.tooltipSafeEquipmentStale = true
                end
            end
        end
    end)
end

MT.tooltipSafeBuild = "TOOLTIPSAFE1"
