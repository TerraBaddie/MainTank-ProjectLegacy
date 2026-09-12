-- MainTank v1.2.33 REFACXML2_UIFIX3
-- Final main-window visibility reconciliation.
--
-- MainTank's historical CreateUI wrapper chain intentionally creates several
-- full-size controls after UI\Summary.lua has already restored Mini Mode. On a
-- fresh login or /reload while Mini Mode is saved, those late-created controls
-- have therefore missed the original SetMiniMode(true) hide pass.
--
-- This file loads after every UI feature/style/drag wrapper and performs one
-- final, idempotent visibility reconciliation. It does not move controls,
-- rebuild pages, or touch combat/persistence state.

local MT = MainTank
if not MT then return end

function MT:ReconcileMainWindowMode()
    local frame = self.frame
    if not frame then return end

    local mini = self.miniMode and true or false
    local controls = self.fullControls
    local _, control

    -- Do not depend on an array-length boundary here.  The historical UI stack
    -- grows this table in several later wrappers, so iterate every registered
    -- entry and normalize it.
    if controls then
        for _, control in pairs(controls) do
            if (type(control) == "table" or type(control) == "userdata") and control.Hide and control.Show then
                if mini then control:Hide() else control:Show() end
            end
        end
    end

    -- Belt-and-suspenders fallback for the five historical late-created controls
    -- that exposed the login/reload bug. RegisterFullControl should already own
    -- these; named reconciliation makes the invariant independent of that table.
    local late = {
        frame.resetDataButton, frame.exportButton, frame.bossButton,
        frame.compareButton, frame.historyButton
    }
    for _, control in pairs(late) do
        if control then
            if mini then control:Hide() else control:Show() end
        end
    end

    -- RC1i creates these decorative rules after the base Summary CreateUI has
    -- already restored Mini Mode, so they need the same final reconciliation.
    if frame.headerRule then
        if mini then frame.headerRule:Hide() else frame.headerRule:Show() end
    end
    if frame.statsRule then
        if mini then frame.statsRule:Hide() else frame.statsRule:Show() end
    end

    -- FIGHTBROWSER1: this Back control is conditional, not a normal fullControl.
    -- It exists only while Main is showing a Recent fight opened from Fights.
    if frame.fightBrowserBackButton then
        if mini or not self.fightBrowserReturnActive then
            frame.fightBrowserBackButton:Hide()
        elseif frame:IsVisible() then
            frame.fightBrowserBackButton:Show()
        end
    end
end

-- Outermost CreateUI wrapper: every historical feature has finished creating
-- and registering its main-page controls before this reconciliation runs.
local Lifecycle_OldCreateUI = MT.CreateUI
function MT:CreateUI()
    Lifecycle_OldCreateUI(self)
    self:ReconcileMainWindowMode()
end

-- Keep the invariant true for normal Full <-> Mini toggles as well. The older
-- SetMiniMode chain still owns geometry, mini rows, subtitle, rules, and display
-- updates; this layer only normalizes full-size control visibility afterward.
local Lifecycle_OldSetMiniMode = MT.SetMiniMode
function MT:SetMiniMode(enabled, automatic)
    Lifecycle_OldSetMiniMode(self, enabled, automatic)
    self:ReconcileMainWindowMode()
end
