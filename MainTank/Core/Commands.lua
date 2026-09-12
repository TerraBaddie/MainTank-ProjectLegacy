-- MainTank release command surface
-- Core/Commands.lua
-- Central user-facing command reference. Existing command implementations are
-- intentionally left in their proven compatibility chain; this module owns the
-- help surface and provides one authoritative, maintainable command catalog.

if not MainTank then return end
local MT = MainTank

local function Chat(text, r, g, b)
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage("|cff66ccffMainTank:|r " .. tostring(text or ""), r or 1, g or 1, b or 1)
    end
end

local HELP = {
    {"WINDOW", {
        {"/mt show", "Open the MainTank window."},
        {"/mt hide", "Hide MainTank."},
        {"/mt mini  |  /mt full", "Switch between compact and full mode."},
        {"/mt automini on|off", "Enable or disable automatic Mini Mode in combat."},
        {"/mt lock  |  /mt unlock", "Lock/unlock window movement."}
    }},
    {"FIGHTS & DATA", {
        {"/mt current", "View the current fight."},
        {"/mt overall", "View the current session total."},
        {"/mt fights", "Open Fights on the Recent tab."},
        {"/mt fight N", "View detailed fight N."},
        {"/mt resetfight", "Reset only the current encounter."},
        {"/mt reset", "Open the confirmed full-data reset."}
    }},
    {"ANALYSIS", {
        {"/mt timeline", "Open/close Timeline."},
        {"/mt pie", "Open/close the mitigation Pie Chart."},
        {"/mt events", "Open Events: enemy, ability, and combat-event analysis."},
        {"/mt highlights", "Open Combat Highlights."},
        {"/mt boss", "Open Boss/encounter analysis."},
        {"/mt compare", "Open Tank Compare."},
        {"/mt export", "Open Summary / Detailed / Boss Profile exports."},
        {"/mt history", "Open Fights on the History tab."},
        {"/mt dr", "Open Mitigation DR."}
    }},
    {"SHARING", {
        {"/mt share party|raid|guild|say", "Send the compact Summary export to chat."},
        {"/mt sync", "Broadcast the latest tank summary for Compare."}
    }},
    {"STORAGE", {
        {"/mt archive", "Open Fights on the Archive tab."},
        {"/mt archive restore N", "Move Archive fight N back into Recent."},
        {"/mt cleararchives", "Show the Archive/History clear confirmation command."}
    }},
    {"HELP", {
        {"/mt  |  /mt help  |  /mt ?", "Show this command reference."}
    }}
}

function MT:ShowCommandHelp()
    Chat("|cffffd200v" .. tostring(self.version or "1.0.0") .. " - Command Reference|r")
    local i, j, section, row
    for i = 1, table.getn(HELP) do
        section = HELP[i]
        Chat("|cffffcc00" .. section[1] .. "|r")
        for j = 1, table.getn(section[2]) do
            row = section[2][j]
            Chat("  |cffeeeeee" .. row[1] .. "|r  |cffaaaaaa- " .. row[2] .. "|r")
        end
    end
end


local FR1L_PreviousHandleSlash = MT.HandleSlash
function MT:HandleSlash(msg)
    local text = string.lower(tostring(msg or ""))
    text = string.gsub(text, "^%s+", "")
    text = string.gsub(text, "%s+$", "")
    if text == "" or text == "help" or text == "?" or text == "commands" then
        self:ShowCommandHelp()
        return
    elseif text == "lock" then
        -- /mt lock intentionally behaves as a toggle. This makes the command
        -- useful both for quickly locking and for recovering from a locked UI.
        if self.ToggleWindowLocked then
            self:ToggleWindowLocked()
            Chat(self.windowLocked and "Window movement locked." or "Window movement unlocked.")
        else
            Chat("Window lock controller is not available yet.")
        end
        return
    elseif text == "unlock" then
        -- /mt unlock is one-way by design: it can never lock the window.
        if self.SetWindowLocked then
            self:SetWindowLocked(false)
            Chat("Window movement unlocked.")
        else
            Chat("Window lock controller is not available yet.")
        end
        return
    end
    return FR1L_PreviousHandleSlash(self, msg)
end

-- Public version ownership is centralized in Core/Release.lua.
