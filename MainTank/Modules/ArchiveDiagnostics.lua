-- MainTank v1.2.14 SVH3 - three-file storage/release diagnostics
if not MainTank then return end
local MT = MainTank

local function D_Print(msg, red)
    if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
        if red then DEFAULT_CHAT_FRAME:AddMessage("MainTank: "..tostring(msg),1.0,0.12,0.12)
        else DEFAULT_CHAT_FRAME:AddMessage("MainTank: "..tostring(msg)) end
    end
end

local function D_CountTable(t)
    local n = 0
    if type(t) ~= "table" then return 0 end
    local _
    for _ in pairs(t) do n = n + 1 end
    return n
end

local function D_CheckFight(fight)
    local issues, events = 0, 0
    if type(fight) ~= "table" or type(fight.events) ~= "table" then return 1, 0 end
    events = table.getn(fight.events)
    local pool = fight.compactContextPool or fight.contextSnapshots
    local isPVP = fight.combatType == "PVP" or fight.pvp == true
    local i, e, id
    for i = 1, events do
        e = fight.events[i]
        if type(e) ~= "table" then issues = issues + 1
        else
            id = e.contextID or e.context
            if isPVP then
                if id ~= nil or e.rc6ContextSnapshot ~= nil then issues = issues + 1 end
            elseif id and (type(pool) ~= "table" or type(pool[id]) ~= "table") then
                issues = issues + 1
            end
        end
    end
    return issues, events
end

local function D_Stores(owner)
    local ap = owner.GetExternalArchiveProfile and owner:GetExternalArchiveProfile(true) or nil
    local hp = owner.GetExternalHistoryProfile and owner:GetExternalHistoryProfile(true) or nil
    return ap and ap.fights or {}, hp and hp.summaries or {}
end

function MT:CheckConsolidatedStorage()
    local recent = self.fights or {}
    local archive, history = D_Stores(self)
    local issues, events, fi, ev, i = 0, 0, 0, 0, 1
    if self.RequiredCompanionsReady and not self:RequiredCompanionsReady() then issues = issues + 1 end
    if table.getn(recent) > 8 then issues = issues + 1 end
    if table.getn(archive) > 8 then issues = issues + 1 end
    if table.getn(history) > 64 then issues = issues + 1 end
    if table.getn(recent) + table.getn(archive) + table.getn(history) > 80 then issues = issues + 1 end
    for i = 1, table.getn(archive) do fi, ev = D_CheckFight(archive[i]); issues = issues + fi; events = events + ev end
    for i = 1, table.getn(history) do if type(history[i]) ~= "table" or not history[i].summaryOnly or history[i].events ~= nil then issues = issues + 1 end end
    if issues == 0 then
        D_Print("Storage PASS - Recent "..table.getn(recent).."/8 | Archive "..table.getn(archive).."/8 | History "..table.getn(history).."/64 | archived events "..events..".")
        return true
    end
    if self.RequiredCompanionsReady and not self:RequiredCompanionsReady() then
        D_Print("Storage companion FAIL - MainTank_Archive and MainTank_History must both be installed, enabled, and loaded.", true)
    end
    D_Print("Storage FAIL - "..tostring(issues).." bounded-storage/contract issue(s).", true)
    return false
end

local function D_IsPvPFight(f) return type(f)=="table" and (f.combatType=="PVP" or f.pvp==true) end
local function D_CountPvPContextRefs(fights)
    local refs=0; local i,j,f,e
    for i=1,table.getn(fights or {}) do
        f=fights[i]
        if D_IsPvPFight(f) then
            if type(f.compactContextPool)=="table" then refs=refs+D_CountTable(f.compactContextPool) end
            if type(f.contextSnapshots)=="table" then refs=refs+D_CountTable(f.contextSnapshots) end
            for j=1,table.getn(f.events or {}) do e=f.events[j]; if type(e)=="table" and (e.contextID~=nil or e.context~=nil or e.rc6ContextSnapshot~=nil) then refs=refs+1 end end
        end
    end
    return refs
end

local function D_EventStats(fights)
    local total,maxEvents,maxLabel=0,0,"-"; local i,f,n
    for i=1,table.getn(fights or {}) do f=fights[i]; n=type(f)=="table" and table.getn(f.events or {}) or 0; total=total+n; if n>maxEvents then maxEvents=n; maxLabel=(f and f.label) or ("Fight "..tostring(i)) end end
    return total,maxEvents,maxLabel
end

function MT:ReleaseCheck()
    local p=self.profile or {}; local recent=self.fights or p.fights or {}; local archive,history=D_Stores(self)
    local recentEvents,recentMax,recentMaxLabel=D_EventStats(recent); local archiveEvents,archiveMax,archiveMaxLabel=D_EventStats(archive)
    local pvpRefs=D_CountPvPContextRefs(recent)+D_CountPvPContextRefs(archive)
    local poolSnapshots=D_CountTable(p.contextSnapshotPool); local poolMitigation=D_CountTable(p.mitigationContexts); local poolCompact=D_CountTable(p.compactContextPool)
    local totalRecords=table.getn(recent)+table.getn(archive)+table.getn(history); local issues=0
    local companionsReady=not self.RequiredCompanionsReady or self:RequiredCompanionsReady()
    if not companionsReady then issues=issues+1 end
    if table.getn(recent)>8 then issues=issues+1 end; if table.getn(archive)>8 then issues=issues+1 end; if table.getn(history)>64 then issues=issues+1 end; if totalRecords>80 then issues=issues+1 end; if pvpRefs>0 then issues=issues+1 end
    D_Print("Release check - Recent "..table.getn(recent).."/8 | Archive "..table.getn(archive).."/8 | History "..table.getn(history).."/64 | total "..totalRecords.."/80.")
    D_Print("Detailed events - Recent "..recentEvents.." (max "..recentMax.." in "..tostring(recentMaxLabel)..") | Archive "..archiveEvents.." (max "..archiveMax.." in "..tostring(archiveMaxLabel)..").")
    D_Print("Core persisted context pools - snapshots "..poolSnapshots.." | mitigation "..poolMitigation.." | compact "..poolCompact..".")
    if companionsReady then D_Print("Storage companions - PASS: Archive and History are loaded.") else D_Print("Storage companions - FAIL: required Archive/History companion unavailable.",true) end
    if pvpRefs==0 then D_Print("PvP persistence - PASS: 0 pure-PvP context references/snapshots found.") else D_Print("PvP persistence - FAIL: "..pvpRefs.." pure-PvP context reference(s)/snapshot(s) remain.",true) end
    if issues==0 then D_Print("RELEASE CHECK PASS - three-file bounded persistence and PvP quarantine contracts are intact.") return true end
    D_Print("RELEASE CHECK FAIL - "..issues.." release-safety contract issue(s).",true); return false
end

local D_PreviousHandleSlash=MT.HandleSlash
function MT:HandleSlash(msg)
    local text=string.lower(tostring(msg or "")); text=string.gsub(text,"^%s+",""); text=string.gsub(text,"%s+$","")
    if text=="archive check" or text=="archive check all" or text=="storage check" then self:CheckConsolidatedStorage(); return end
    if text=="releasecheck" or text=="release check" then self:ReleaseCheck(); return end
    return D_PreviousHandleSlash(self,msg)
end
