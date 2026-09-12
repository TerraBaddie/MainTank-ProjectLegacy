-- MainTank REFACXML1 - Base slash command router
-- Later modules intentionally wrap this handler in historical load order.

local MT = MainTank
local E = MT._engine
local lower = string.lower
local format = string.format
local Print = E.Print

function MT:HandleSlash(msg)
    msg = lower(msg or "")
    if msg == "" or msg == "show" then
        -- FR1j: route slash-show through the authoritative single-window page
        -- manager.  Calling frame:Show() directly can be immediately undone by
        -- the page guard when the last active managed page was PIE/TIMELINE/etc.
        if self.ShowManagedPage then
            self:ShowManagedPage("MAIN")
        elseif self.frame then
            self.frame:Show()
        end
        MainTankDB.hidden = false
    elseif msg == "hide" then
        -- Hide the whole managed UI, not only the summary frame.  This keeps
        -- /mt hide symmetrical with /mt show even when an analysis page is open.
        if self.HideAllManagedPages then
            self:HideAllManagedPages(nil)
            self.currentManagedPage = nil
            self.activeRCPage = nil
        elseif self.frame then
            self.frame:Hide()
        end
        MainTankDB.hidden = true
    elseif msg == "reset" or msg == "resetsession" then
        self:ConfirmResetAllData()
    elseif msg == "resetfight" or msg == "resetcurrent" then
        self:ResetEncounter()
    elseif msg == "debug" then
        self.debug = not self.debug
        Print("Debug mode " .. (self.debug and "enabled." or "disabled."))
    elseif msg == "fights" then
        if table.getn(self.fights) == 0 then
            Print("No completed fights saved.")
        else
            local i, fight
            for i = 1, table.getn(self.fights) do
                fight = self.fights[i]
                local typeTag = (fight.combatType == "PVP" or fight.pvp == true) and "[PvP] " or "[PvE] "
                Print(i .. ": " .. typeTag .. (fight.label or ("Fight " .. i)) .. " - " .. format("%.1fs", fight.duration or 0) .. " - " .. tostring(fight.enemyCount or 0) .. " enemies")
            end
            Print("Use /mt fight 1 to view a saved fight.")
        end
    elseif string.sub(msg, 1, 6) == "fight " then
        local index = tonumber(string.sub(msg, 7))
        if index and self.fights[index] then
            self:SetView(index)
        else
            Print("Saved fight not found. Use /mt fights.")
        end
    elseif msg == "current" then
        self:SetView("CURRENT")
    elseif msg == "overall" then
        self:SetView("OVERALL")
    elseif msg == "blocks" then
        self:PrintBlockReport()
    elseif msg == "blockrefresh" then
        self:MarkBlockValueDirty(0)
        self:RefreshBlockValue(true)
        self:UpdateDisplay()
        Print("Block value tooltip scan refreshed.")
    elseif msg == "mini" or msg == "shrink" then
        self:SetMiniMode(true, false)
    elseif msg == "full" or msg == "expand" then
        self:SetMiniMode(false, false)
    elseif msg == "automini" then
        self.autoMiniInCombat = not self.autoMiniInCombat
        MainTankDB.autoMiniInCombat = self.autoMiniInCombat
        Print("Automatic combat mini-mode " .. (self.autoMiniInCombat and "enabled." or "disabled."))
    elseif msg == "timeline" then
        self:ToggleTimeline()
    elseif msg == "pie" or msg == "chart" then
        self:TogglePie()
    elseif msg == "events" or msg == "details" or msg == "enemies" or msg == "abilities" then
        self:ToggleDetails()
    elseif msg == "highlights" or msg == "biggest" or msg == "hits" then
        self:ToggleBiggest()
    elseif msg == "eventcount" then
        local events = self:GetDisplayEvents() or {}
        local timeline = self:GetDisplayTimeline() or {}
        local buckets = 0
        local second
        for second in pairs(timeline) do buckets = buckets + 1 end
        Print(tostring(table.getn(events)) .. " combat events across " .. tostring(buckets) .. " one-second timeline buckets in the selected view.")
    elseif msg == "memory" then
        local mob, attacks, attack, m
        Print("Session mob memory:")
        for mob, attacks in pairs(self.sessionMemory) do
            for attack, m in pairs(attacks) do
                Print(mob .. " / " .. attack .. " post-armor: " .. self:FormatNumber(m.minHit) .. "-" .. self:FormatNumber(m.maxHit) .. " (" .. m.samples .. " samples)")
            end
        end
        Print("Target raw damage memory:")
        for mob, m in pairs(self.targetDamageMemory) do
            local line = mob .. " MH " .. format("%.1f-%.1f", m.minHit or 0, m.maxHit or 0)
            if m.dualWield and m.offMinHit and m.offMaxHit then
                line = line .. " / OH " .. format("%.1f-%.1f", m.offMinHit, m.offMaxHit)
            end
            if m.avoidanceRawEstimate then
                line = line .. " / avoid est " .. format("%.1f", m.avoidanceRawEstimate)
            end
            line = line .. " / " .. (m.source or "Observed")
            Print(line)
        end
    else
        Print("Commands: /mt show, hide, mini, full, automini, reset, resetfight, current, overall, fights, fight N, timeline, pie, events, highlights")
    end
end

