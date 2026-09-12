-- MainTank required companion health checks
-- MainTank_Archive and MainTank_History are normal enabled addons with a
-- dependency on MainTank. They contain only separate SavedVariables stores.
-- The core addon remains usable if one is unavailable, but warns clearly so a
-- packaging/enable-state problem cannot silently disable bounded persistence.

if not MainTank then return end

local MT = MainTank
local G = getfenv(0)

local REQUIRED = {
    { addon = "MainTank_Archive", globalName = "MainTankArchiveDB", versionGlobal = "MainTankArchivePackageVersion", role = "detailed Archive storage" },
    { addon = "MainTank_History", globalName = "MainTankHistoryDB", versionGlobal = "MainTankHistoryPackageVersion", role = "History summary storage" },
}

local function CompanionPrint(msg, red)
    if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
        if red then
            DEFAULT_CHAT_FRAME:AddMessage("|cff66ccffMainTank:|r " .. tostring(msg), 1.0, 0.18, 0.18)
        else
            DEFAULT_CHAT_FRAME:AddMessage("|cff66ccffMainTank:|r " .. tostring(msg))
        end
    end
end

local function FindInstalledAddon(addonName)
    if type(GetNumAddOns) ~= "function" or type(GetAddOnInfo) ~= "function" then
        return nil, nil
    end
    local count = tonumber(GetNumAddOns()) or 0
    local i, name
    for i = 1, count do
        name = GetAddOnInfo(i)
        if name == addonName then return true, i end
    end
    return false, nil
end

local function FindSpec(addonName)
    local i
    for i = 1, table.getn(REQUIRED) do
        if REQUIRED[i].addon == addonName then return REQUIRED[i] end
    end
    return nil
end

function MT:GetRequiredCompanionStatus(addonName)
    local spec = FindSpec(addonName)
    if not spec then return nil end

    local installed, index = FindInstalledAddon(spec.addon)
    local loaded = G[spec.globalName] ~= nil

    -- The SavedVariables global is the strongest signal because these tiny
    -- companions create it immediately when their only Lua file executes.
    -- IsAddOnLoaded is a secondary fallback for clients that expose the API.
    if not loaded and type(IsAddOnLoaded) == "function" then
        local ok, value = pcall(IsAddOnLoaded, index or spec.addon)
        if ok and value then loaded = true end
    end

    -- Prefer the companion's LIVE self-reported package version. Vanilla can
    -- cache TOC metadata for the lifetime of the client, so replacing addon
    -- folders followed by /reload may otherwise report the previous version.
    -- TOC metadata remains the fallback for older companion builds that do not
    -- expose a runtime package-version global.
    local version = G[spec.versionGlobal]
    if (not version or version == "") and type(GetAddOnMetadata) == "function" then
        local ok, value = pcall(GetAddOnMetadata, spec.addon, "Version")
        if ok then version = value end
    end

    return {
        addon = spec.addon,
        globalName = spec.globalName,
        role = spec.role,
        installed = installed,
        loaded = loaded and true or false,
        available = loaded and G[spec.globalName] ~= nil,
        version = version,
    }
end

function MT:WarnRequiredCompanion(addonName)
    local status = self:GetRequiredCompanionStatus(addonName)
    if not status or status.available then return false end

    self.requiredCompanionWarnings = self.requiredCompanionWarnings or {}
    if self.requiredCompanionWarnings[addonName] then return true end
    self.requiredCompanionWarnings[addonName] = true

    if status.installed == false then
        CompanionPrint("WARNING: " .. addonName .. " is missing from Interface\\AddOns. " .. status.role .. " is unavailable.", true)
    elseif status.installed == true and status.loaded then
        CompanionPrint("WARNING: " .. addonName .. " loaded but its storage backend did not initialize. Check for a Lua error and reinstall the matching MainTank package.", true)
    elseif status.installed == true then
        CompanionPrint("WARNING: " .. addonName .. " is installed but not loaded. Enable it in the AddOns list and /reload.", true)
    else
        CompanionPrint("WARNING: " .. addonName .. " is not loaded. Make sure the companion folder is installed and enabled, then /reload.", true)
    end
    return true
end


function MT:RequiredCompanionVersionMatches(addonName)
    local status = self:GetRequiredCompanionStatus(addonName)
    if not status or not status.available then return false end
    local coreVersion = self.packageVersion
    if not coreVersion or not status.version or status.version == "" then return true end
    return tostring(status.version) == tostring(coreVersion)
end

function MT:RequiredCompanionsReady()
    local ready = true
    local i, status
    for i = 1, table.getn(REQUIRED) do
        status = self:GetRequiredCompanionStatus(REQUIRED[i].addon)
        if not status or not status.available or not self:RequiredCompanionVersionMatches(REQUIRED[i].addon) then ready = false end
    end
    return ready
end

function MT:CheckRequiredCompanions()
    local hadIssue = false
    local i
    for i = 1, table.getn(REQUIRED) do
        local spec = REQUIRED[i]
        if self:WarnRequiredCompanion(spec.addon) then
            hadIssue = true
        elseif not self:RequiredCompanionVersionMatches(spec.addon) then
            hadIssue = true
            self.requiredCompanionWarnings = self.requiredCompanionWarnings or {}
            local key = spec.addon .. ":version"
            if not self.requiredCompanionWarnings[key] then
                self.requiredCompanionWarnings[key] = true
                local status = self:GetRequiredCompanionStatus(spec.addon)
                CompanionPrint("WARNING: " .. spec.addon .. " version " .. tostring(status and status.version or "unknown") .. " does not match MainTank " .. tostring(self.packageVersion or "unknown") .. ". Reinstall all three folders from the same package.", true)
            end
        end
    end
    if hadIssue and not self.requiredCompanionSetupHintShown then
        self.requiredCompanionSetupHintShown = true
        CompanionPrint("Install and enable MainTank, MainTank_Archive, and MainTank_History together. Recent tracking remains usable, but full Archive/History persistence requires both companions.", true)
    end
    return not hadIssue
end

