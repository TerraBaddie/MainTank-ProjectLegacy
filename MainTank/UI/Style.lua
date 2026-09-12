-- MainTank v1.0.0 FR1S
-- UI/Style.lua
-- Consolidated first-release UI styling/lifecycle maintenance extracted from
-- Core/Engine.lua.  This module intentionally consumes only explicit MT APIs.
--
-- FR1R fixes an FR1P/FR1Q regression: the generic recursive button pass called
-- RC6P_ForceBlackSelector() on EVERY button.  That selector helper intentionally
-- paints its font yellow and removes normal/disabled textures; doing that to
-- ordinary buttons erased selected/disabled visual state and stripped the red
-- reset icon.  Selector styling is now limited to the Pie/Timeline View button.

if not MainTank then return end
local MT = MainTank

local function IsResetIconButton(button)
    if not button or not button.GetNormalTexture then return false end
    local tex = button:GetNormalTexture()
    local path = tex and tex.GetTexture and tex:GetTexture() or nil
    if type(path) ~= "string" then return false end
    return string.find(path, "UI%-GroupLoot%-Pass") ~= nil
end

local function StyleButton(button)
    if not button then return end
    -- Preserve icon-driven controls.  In particular the data-reset button uses
    -- Blizzard's red Pass/Cancel artwork and must never be flattened into a
    -- generic black text button.
    if IsResetIconButton(button) then return end
    if MT.ApplyLegacyButtonStyle then MT:ApplyLegacyButtonStyle(button) end
end

local function StyleSelector(button)
    if not button then return end
    if MT.ApplyLegacyButtonStyle then MT:ApplyLegacyButtonStyle(button) end
    if RC6P_ForceBlackSelector then RC6P_ForceBlackSelector(button) end
end

local function CloseAllMainTankWindows()
    MT.backNavHistory = {}
    MT.currentManagedPage = "MAIN"
    MT.activeRCPage = nil
    if MT.HideAllManagedPages then MT:HideAllManagedPages() end
    if MT.frame then MT.frame:Hide() end
    if MT.historyFrame then MT.historyFrame:Hide() end
    MT:HideAnalysisTooltip()
end

local function FinalizeCloseButton(frame)
    if not frame or not frame.GetChildren then return end
    local children = {frame:GetChildren()}
    local i, child
    for i = 1, table.getn(children) do
        child = children[i]
        if child and child.GetObjectType and child:GetObjectType() == "Button" then
            StyleButton(child)
            if child.mtCloseText then
                child.mtCloseText:SetTextColor(1.0, 0.10, 0.10)
                child:SetScript("OnClick", CloseAllMainTankWindows)
            end
        end
    end
end


local function BlackenButtonsDeep(frame, depth, seen)
    if not frame or not frame.GetChildren then return end
    depth = tonumber(depth) or 0
    if depth > 4 then return end
    seen = seen or {}
    if seen[frame] then return end
    seen[frame] = true

    local children = { frame:GetChildren() }
    local i, child
    for i = 1, table.getn(children) do
        child = children[i]
        if child and child.GetObjectType and child:GetObjectType() == "Button" then
            StyleButton(child)
        end
        if child and child.GetChildren then
            BlackenButtonsDeep(child, depth + 1, seen)
        end
    end
end

MT.BlackenButtonsDeep = BlackenButtonsDeep

-- Preserve the complete page-manager contract.  This also prevents the old
-- first-render Pie/Timeline bug where dropping updater made the chart appear
-- only after the View button was clicked.
local PreviousShowManagedPage = MT.ShowManagedPage
function MT:ShowManagedPage(pageName, updater)
    local result = PreviousShowManagedPage(self, pageName, updater)
    local frame = self.managedPages and self.managedPages[pageName] or nil
    if frame then
        BlackenButtonsDeep(frame, 0, {})
        FinalizeCloseButton(frame)
    end
    return result
end

local PreviousCreatePieWindow = MT.CreatePieWindow
function MT:CreatePieWindow()
    local frame = PreviousCreatePieWindow(self)
    if frame then
        if frame.modeButton then StyleSelector(frame.modeButton) end
        if not frame.fr1pCleanupHooked then
            frame.fr1pCleanupHooked = true
            local oldOnHide = frame:GetScript("OnHide")
            frame:SetScript("OnHide", function()
                if oldOnHide then oldOnHide() end
                if this and this.ring then
                    this.ring.hoverEntry = nil
                    this.ring.entry = nil
                end
                MT:HideAnalysisTooltip()
                MT.rc6rPieDirty = nil
                MT.rc6rNextPieRefresh = nil
            end)
        end
        BlackenButtonsDeep(frame, 0, {})
        FinalizeCloseButton(frame)
    end
    return frame
end

local PreviousCreateTimelineWindow = MT.CreateTimelineWindow
function MT:CreateTimelineWindow()
    local frame = PreviousCreateTimelineWindow(self)
    if frame then
        if frame.modeButton then StyleSelector(frame.modeButton) end
        if frame.prevMinute then StyleButton(frame.prevMinute) end
        if frame.nextMinute then StyleButton(frame.nextMinute) end
        BlackenButtonsDeep(frame, 0, {})
        FinalizeCloseButton(frame)
    end
    return frame
end

-- Base Block Value row hover/click surface repair.  Anchor the invisible mouse
-- frame between the visible label and value so Mini Mode/layout wrappers cannot
-- collapse it to a zero-width region.
local function RepairMainRowHitFrames(self)
    if not self or not self.frame or not self.rows then return end
    local i, row
    for i = 1, 8 do
        row = self.rows[i]
        if row and row.hit and row.label and row.value then
            row.hit:ClearAllPoints()
            row.hit:SetPoint("TOPLEFT", row.label, "TOPLEFT", -5, 4)
            row.hit:SetPoint("BOTTOMRIGHT", row.value, "BOTTOMRIGHT", 5, -4)
            row.hit:SetFrameLevel(self.frame:GetFrameLevel() + 20)
            row.hit:EnableMouse(true)
            if not self.miniMode and row.label:IsVisible() then row.hit:Show() else row.hit:Hide() end
        end
    end
end

local PreviousCreateUI = MT.CreateUI
function MT:CreateUI()
    PreviousCreateUI(self)
    RepairMainRowHitFrames(self)
    if self.frame then
        BlackenButtonsDeep(self.frame, 0, {})
        FinalizeCloseButton(self.frame)
    end
end

local PreviousSetRow = MT.SetRow
function MT:SetRow(index, label, value)
    PreviousSetRow(self, index, label, value)
    local row = self.rows and self.rows[index]
    if row and row.hit and row.label and row.value then
        row.hit:ClearAllPoints()
        row.hit:SetPoint("TOPLEFT", row.label, "TOPLEFT", -5, 4)
        row.hit:SetPoint("BOTTOMRIGHT", row.value, "BOTTOMRIGHT", 5, -4)
        if self.frame then row.hit:SetFrameLevel(self.frame:GetFrameLevel() + 20) end
        row.hit:EnableMouse(true)
        if label and label ~= "" and not self.miniMode then row.hit:Show() else row.hit:Hide() end
    end
end
