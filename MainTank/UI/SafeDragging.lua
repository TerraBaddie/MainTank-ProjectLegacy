-- MainTank v1.0.0 FR1W
-- Vanilla 1.12.1-safe movable-window controller.
--
-- FR1V UI rules:
--   * Lock state persists per character across /reload/login.
--   * Only the MAIN MainTank page shows the lock/unlock button.
--   * The one main-page lock controls movement for all managed MainTank windows.
--   * Unlocked icon = open shackle; locked icon = closed shackle.
--   * Drag-stop only stops movement and records geometry. It never clears or
--     reapplies anchors inside the mouse-release callback.

if not MainTank then return end
local MT = MainTank

-- Runtime state is restored from the active character profile during CreateUI.
MT.windowLocked = false
MT.safeDragFrames = MT.safeDragFrames or {}
MT.safeDragButtons = MT.safeDragButtons or {}

local LOCKED_TEX   = "Interface\\AddOns\\MainTank\\UI\\Textures\\LockLocked"
local UNLOCKED_TEX = "Interface\\AddOns\\MainTank\\UI\\Textures\\LockUnlocked"

local function SafeBottomRight(frame)
    if not frame then return nil, nil end
    local right = frame:GetRight()
    local bottom = frame:GetBottom()
    if right and bottom then
        return tonumber(right), tonumber(bottom)
    end
    return nil, nil
end

local function SafeSavePosition(frame)
    if not frame or not MainTankDB then return end
    local right, bottom = SafeBottomRight(frame)
    if not right or not bottom then return end

    -- Save a UIParent-relative tuple that cannot contain a stale/self frame ref.
    MainTankDB.position = {
        point = "BOTTOMRIGHT",
        relativePoint = "BOTTOMLEFT",
        x = right,
        y = bottom
    }
end

local function RefreshLockButton(button)
    if not button then return end

    if button.mtLockIcon then
        if MT.windowLocked then
            button.mtLockIcon:SetTexture(LOCKED_TEX)
        else
            button.mtLockIcon:SetTexture(UNLOCKED_TEX)
        end
        button.mtLockIcon:SetVertexColor(1, 1, 1, 1)
    end

    if MT.windowLocked then
        button.mtLockTooltip = "MainTank locked - click to unlock window movement"
    else
        button.mtLockTooltip = "MainTank unlocked - click to lock window movement"
    end
end

function MT:RefreshSafeDragButtons()
    local i
    for i = 1, table.getn(self.safeDragButtons) do
        RefreshLockButton(self.safeDragButtons[i])
    end
end

function MT:SetWindowLocked(locked)
    self.windowLocked = locked and true or false

    -- Persist the choice on the active character profile. This keeps one
    -- character's UI lock preference from changing another character's.
    if self.profile then
        self.profile.windowLocked = self.windowLocked
    elseif MainTankDB then
        -- Defensive fallback for any unusually early call before profile restore.
        MainTankDB.windowLocked = self.windowLocked
    end

    local i, frame
    for i = 1, table.getn(self.safeDragFrames) do
        frame = self.safeDragFrames[i]
        if frame then
            frame:SetMovable(not self.windowLocked)
        end
    end
    self:RefreshSafeDragButtons()
end

function MT:ToggleWindowLocked()
    self:SetWindowLocked(not self.windowLocked)
end

local function FindMainCloseButton(frame)
    if not frame then return nil end
    if frame.closeButton then return frame.closeButton end

    local children = {frame:GetChildren()}
    local i, child
    for i = 1, table.getn(children) do
        child = children[i]
        -- FinalizeLegacyWindow marks the real UIPanelCloseButton this way.
        if child and child.mtCloseText then
            return child
        end
    end
    return nil
end

local function MakeMainCloseRed(frame)
    local close = FindMainCloseButton(frame)
    if close and close.mtCloseText then
        -- Match the destructive/delete visual language: the X itself is red.
        close.mtCloseText:SetTextColor(1.0, 0.10, 0.10)
    end
end

local function AddMainLockButton(frame)
    -- FR1U: the lock control exists ONLY on the main MainTank page.
    if not frame or frame ~= MT.frame or frame.mtSafeLockButton then return end

    local close = FindMainCloseButton(frame)
    if not close then return end

    local button = CreateFrame("Button", nil, frame)
    button:SetWidth(18)
    button:SetHeight(18)
    button:SetPoint("TOPRIGHT", close, "TOPLEFT", -2, 0)

    -- Keep the control visually identical in scale to the tiny red close X.
    -- The supplied artwork is 11x16; render it slightly inset in the 18px hitbox.
    local icon = button:CreateTexture(nil, "OVERLAY")
    icon:SetWidth(10)
    icon:SetHeight(14)
    icon:SetPoint("CENTER", button, "CENTER", 0, 0)
    button.mtLockIcon = icon

    -- Subtle hover only; no Blizzard button art is used.
    local highlight = button:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetTexture("Interface\\Buttons\\WHITE8X8")
    highlight:SetAllPoints(button)
    highlight:SetVertexColor(1.0, 0.82, 0.10, 0.12)

    button:SetScript("OnClick", function()
        MT:ToggleWindowLocked()
    end)
    button:SetScript("OnEnter", function()
        if GameTooltip then
            GameTooltip:SetOwner(this, "ANCHOR_BOTTOMLEFT")
            GameTooltip:SetText(this.mtLockTooltip or "MainTank window lock")
            GameTooltip:Show()
        end
    end)
    button:SetScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)

    frame.mtSafeLockButton = button
    table.insert(MT.safeDragButtons, button)
    RefreshLockButton(button)
end

function MT:InstallSafeDragging(frame)
    if not frame then return end

    if not frame.mtSafeDragInstalled then
        frame:SetMovable(not self.windowLocked)
        frame:EnableMouse(true)
        frame:RegisterForDrag("LeftButton")

        frame:SetScript("OnDragStart", function()
            if MT.windowLocked then return end
            this:StartMoving()
        end)

        frame:SetScript("OnDragStop", function()
            -- IMPORTANT for the 1.12.1 client: do not ClearAllPoints/SetPoint,
            -- resize, reparent, or move a second frame from this callback.
            this:StopMovingOrSizing()
            SafeSavePosition(this)
        end)

        frame.mtSafeDragInstalled = true
        table.insert(self.safeDragFrames, frame)
    end

    -- Only the main page gets a visible lock control.
    if frame == self.frame then
        AddMainLockButton(frame)
        MakeMainCloseRed(frame)
    end
end

function MT:InstallSafeDraggingOnKnownFrames()
    self:InstallSafeDragging(self.frame)
    self:InstallSafeDragging(self.timelineFrame or getglobal("MainTankTimelineFrame"))
    self:InstallSafeDragging(self.pieFrame or getglobal("MainTankPieFrame"))
    self:InstallSafeDragging(self.detailsFrame or getglobal("MainTankDetailsFrame"))
    self:InstallSafeDragging(self.biggestFrame or getglobal("MainTankBiggestFrame"))
    self:InstallSafeDragging(self.historyFrame or getglobal("MainTankHistoryFrame"))
    self:InstallSafeDragging(self.compareFrame or getglobal("MainTankTankCompareFrame"))
    self:InstallSafeDragging(self.drFrame or getglobal("MainTankDRFrame"))
end

-- Install on the main frame immediately after it is created.
local OldCreateUI = MT.CreateUI
function MT:CreateUI()
    OldCreateUI(self)

    -- Restore the current character's last lock choice. Existing FR1U users
    -- without this saved field default to unlocked exactly as before.
    if self.profile and self.profile.windowLocked ~= nil then
        self.windowLocked = self.profile.windowLocked and true or false
    elseif MainTankDB and MainTankDB.windowLocked ~= nil then
        -- One-time compatibility fallback if an interim build stored it globally.
        self.windowLocked = MainTankDB.windowLocked and true or false
        if self.profile then self.profile.windowLocked = self.windowLocked end
        MainTankDB.windowLocked = nil
    else
        self.windowLocked = false
    end

    self:InstallSafeDraggingOnKnownFrames()
    self:SetWindowLocked(self.windowLocked)
end

-- Lazily-created analysis pages exist by the time ShowManagedPage is entered.
-- They still receive the safe drag callback, but never receive a lock button.
if MT.ShowManagedPage then
    local OldShowManagedPage = MT.ShowManagedPage
    function MT:ShowManagedPage(name, updater)
        self:InstallSafeDraggingOnKnownFrames()
        local result = OldShowManagedPage(self, name, updater)
        self:InstallSafeDraggingOnKnownFrames()
        return result
    end
end

-- Compare/DR pages may use ShowRCPage directly before/around registration.
if MT.ShowRCPage then
    local OldShowRCPage = MT.ShowRCPage
    function MT:ShowRCPage(frame, updater)
        self:InstallSafeDragging(frame)
        local result = OldShowRCPage(self, frame, updater)
        self:InstallSafeDragging(frame)
        return result
    end
end
