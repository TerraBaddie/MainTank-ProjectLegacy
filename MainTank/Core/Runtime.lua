-- MainTank REFACXML1 - Runtime bootstrap and event routing
-- Defines Initialize and the authoritative MainTankEventFrame after the parser,
-- session, summary, and base command layers have been declared.

local MT = MainTank
local E = MT._engine
local Print = E.Print

function MT:Initialize()
    if not MainTankDB then MainTankDB = {} end
    self.playerName = UnitName("player") or "You"

    local fr2Start = GetTime and GetTime() or 0
    self:MigrateDatabase()
    local fr2AfterMigrate = GetTime and GetTime() or fr2Start
    self:RestorePersistentData()
    local fr2AfterRestore = GetTime and GetTime() or fr2AfterMigrate
    self:CreateUI()
    -- UIFIX3: CreateUI is historically wrapper-heavy. Reassert the persisted
    -- Full/Mini invariant from Initialize itself so startup does not depend on
    -- which wrapper happened to be outermost in the 1.12 client.
    if self.ReconcileMainWindowMode then self:ReconcileMainWindowMode() end
    local fr2AfterUI = GetTime and GetTime() or fr2AfterRestore

    self.fr2StartupTiming = {
        migrate = fr2AfterMigrate - fr2Start,
        restore = fr2AfterRestore - fr2AfterMigrate,
        ui = fr2AfterUI - fr2AfterRestore,
        total = fr2AfterUI - fr2Start,
    }

    self:CaptureTargetDamage()
    self:MarkBlockValueDirty(1.0)

    SLASH_MAINTANK1 = "/mt"
    SLASH_MAINTANK2 = "/maintank"
    SlashCmdList["MAINTANK"] = function(msg) MT:HandleSlash(msg) end

    Print("v" .. self.version .. " loaded. Type /mt for commands.")
end

local eventFrame = CreateFrame("Frame", "MainTankEventFrame")
eventFrame:RegisterEvent("VARIABLES_LOADED")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("PLAYER_LOGOUT")
eventFrame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
eventFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
eventFrame:RegisterEvent("UNIT_INVENTORY_CHANGED")
eventFrame:RegisterEvent("UNIT_STATS")
eventFrame:RegisterEvent("PLAYER_AURAS_CHANGED")
eventFrame:RegisterEvent("CHARACTER_POINTS_CHANGED")
eventFrame:RegisterEvent("CHAT_MSG_COMBAT_CREATURE_VS_SELF_HITS")
eventFrame:RegisterEvent("CHAT_MSG_COMBAT_CREATURE_VS_SELF_MISSES")
eventFrame:RegisterEvent("CHAT_MSG_COMBAT_HOSTILEPLAYER_HITS")
eventFrame:RegisterEvent("CHAT_MSG_COMBAT_HOSTILEPLAYER_MISSES")
eventFrame:RegisterEvent("CHAT_MSG_SPELL_CREATURE_VS_SELF_DAMAGE")
eventFrame:RegisterEvent("CHAT_MSG_SPELL_HOSTILEPLAYER_DAMAGE")
eventFrame:RegisterEvent("CHAT_MSG_SPELL_PERIODIC_SELF_DAMAGE")
eventFrame:RegisterEvent("CHAT_MSG_SPELL_SELF_DAMAGE")
eventFrame:RegisterEvent("CHAT_MSG_COMBAT_MISC_INFO")
eventFrame:RegisterEvent("CHAT_MSG_COMBAT_SELF_HITS")
eventFrame:RegisterEvent("CHAT_MSG_COMBAT_HOSTILE_DEATH")

eventFrame:SetScript("OnUpdate", function()
    local now = GetTime()
    if MT.blockValueRetryAt and now >= MT.blockValueRetryAt then
        MT.blockValueRetryAt = nil
        MT.blockValueDirty = true
        MT:RefreshBlockValue(false)
        MT:UpdateDisplay()
    end

    -- Refresh live target damage during combat so temporary NPC damage
    -- modifiers or weapon-state changes can update the avoidance estimate.
    if MT.inCombat and UnitExists("target") and not UnitIsFriend("player", "target") then
        if not MT.nextTargetDamageScan or now >= MT.nextTargetDamageScan then
            MT.nextTargetDamageScan = now + 0.75
            MT:CaptureTargetDamage()
        end
    else
        MT.nextTargetDamageScan = nil
    end
end)

eventFrame:SetScript("OnEvent", function()
    if event == "ADDON_LOADED" and arg1 == "pfUI" then
        -- MainTank can load before pfUI alphabetically. Reapply the
        -- native pfUI skin as soon as pfUI's API becomes available.
        if MT.frame then MT:RefreshPfUISkin() end
    elseif event == "VARIABLES_LOADED" then
        MT:Initialize()
    elseif event == "PLAYER_LOGOUT" then
        MT:SyncPersistentData()
    elseif event == "PLAYER_REGEN_DISABLED" then
        MT:StartCombat()
    elseif event == "PLAYER_REGEN_ENABLED" then
        MT:EndCombat()
    elseif event == "PLAYER_ENTERING_WORLD" then
        -- RELEASEPOLISH1: required storage companions are normal enabled addons.
        -- Check only after the addon-loading phase is complete so a missing or
        -- disabled companion produces one actionable warning, never a false
        -- positive caused by load order.
        if MT.CheckRequiredCompanions then MT:CheckRequiredCompanions() end
        MT:MarkBlockValueDirty(1.0)
        MT:UpdateDisplay()
        -- One final world-entry pass catches any UI skin/addon-load activity
        -- that occurred after VARIABLES_LOADED without changing saved mode.
        if MT.ReconcileMainWindowMode then MT:ReconcileMainWindowMode() end
    elseif event == "PLAYER_TARGET_CHANGED" then
        MT:CaptureTargetDamage()
        MT:UpdateDisplay()
    elseif event == "PLAYER_EQUIPMENT_CHANGED" then
        MT:MarkBlockValueDirty(0.35)
        MT:UpdateDisplay()
    elseif event == "UNIT_INVENTORY_CHANGED" or event == "UNIT_STATS" then
        if not arg1 or arg1 == "player" then
            MT:MarkBlockValueDirty(0.35)
            MT:UpdateDisplay()
        end
    elseif event == "PLAYER_AURAS_CHANGED" or event == "CHARACTER_POINTS_CHANGED" then
        MT:MarkBlockValueDirty(0.25)
        MT:UpdateDisplay()
    elseif event == "CHAT_MSG_COMBAT_HOSTILE_DEATH" and arg1 then
        MT:RecordHostileDeath(arg1)
    elseif arg1 then
        MT:ParseCombatMessage(arg1)
    end
end)


-- Mitigation.lua deliberately wraps this exact frame's OnEvent/OnUpdate scripts.
E.eventFrame = eventFrame
