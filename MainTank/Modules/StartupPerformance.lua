-- MainTank v1.1.0 FR2 - Startup Performance Diagnostics
-- Manual/read-only. No archive loading and no historical scans.
if not MainTank then return end

local MT = MainTank
local FR2SP_PreviousHandleSlash = MT.HandleSlash

local function FR2SP_Print(msg)
    if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
        DEFAULT_CHAT_FRAME:AddMessage("MainTank: " .. tostring(msg))
    end
end

function MT:HandleSlash(msg)
    local text = string.lower(msg or "")
    text = string.gsub(text, "^%s+", "")
    text = string.gsub(text, "%s+$", "")

    if text == "startup" or text == "startup time" or text == "startuptime" then
        local t = self.fr2StartupTiming or {}
        FR2SP_Print(string.format(
            "FR2 startup - migrate %.3fs | restore %.3fs | UI %.3fs | measured addon work %.3fs.",
            tonumber(t.migrate) or 0,
            tonumber(t.restore) or 0,
            tonumber(t.ui) or 0,
            tonumber(t.total) or 0
        ))
        FR2SP_Print("Phone stopwatch includes WoW/client work outside MainTank; this command isolates MainTank Initialize phases.")
        return
    end

    return FR2SP_PreviousHandleSlash(self, msg)
end
