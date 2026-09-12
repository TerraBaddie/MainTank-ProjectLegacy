-- MainTank REFACXML1 - Legacy/pfUI presentation core
-- UI styling and analysis-tooltip presentation extracted from Core\Engine.lua.

local MT = MainTank
local E = MT._engine

local MT_LEGACY_BACKDROP = {
    bgFile = "Interface\\Buttons\\WHITE8X8",
    edgeFile = "Interface\\Buttons\\WHITE8X8",
    tile = false,
    tileSize = 0,
    edgeSize = 1,
    insets = {left = 1, right = 1, top = 1, bottom = 1}
}

local function ParseColorString(value, dr, dg, db, da)
    if type(value) ~= "string" then return dr, dg, db, da end
    local _, _, r, g, b, a = string.find(value, "^%s*([%d%.%-]+)%s*,%s*([%d%.%-]+)%s*,%s*([%d%.%-]+)%s*,?%s*([%d%.%-]*)")
    r, g, b = tonumber(r), tonumber(g), tonumber(b)
    a = tonumber(a)
    if not r or not g or not b then return dr, dg, db, da end
    if not a then a = da end
    return r, g, b, a
end

local function GetLegacyBackdropColor()
    if pfUI_config and pfUI_config.appearance and pfUI_config.appearance.border then
        return ParseColorString(pfUI_config.appearance.border.background, 0.10, 0.10, 0.10, 0.80)
    end
    return 0.10, 0.10, 0.10, 0.80
end

local function GetLegacyBorderColor()
    if pfUI_config and pfUI_config.appearance and pfUI_config.appearance.border then
        return ParseColorString(pfUI_config.appearance.border.color, 0, 0, 0, 1)
    end
    return 0, 0, 0, 1
end

local function GetLegacyAccent()
    -- pfUI Legacy itself uses neutral panel colors. Keep only a restrained gold
    -- accent for MainTank's title and active separators.
    return 1.00, 0.82, 0.10
end

local function GetLegacyFont()
    if pfUI and pfUI.font_default then return pfUI.font_default end
    if pfUI_config and pfUI_config.global and pfUI_config.global.font_default then
        return pfUI_config.global.font_default
    end
    return "Fonts\\FRIZQT__.TTF"
end

local function GetLegacyFontSize(defaultSize)
    if pfUI_config and pfUI_config.global and tonumber(pfUI_config.global.font_size) then
        return tonumber(pfUI_config.global.font_size)
    end
    return defaultSize or 10
end

local function HasNativePfUI()
    return pfUI and pfUI.api and pfUI.api.CreateBackdrop and pfUI.api.SkinButton
end

local function StyleLegacyFontString(fontString, size)
    if not fontString or not fontString.SetFont then return end
    local fontSize = size or GetLegacyFontSize(10)
    local ok = fontString:SetFont(GetLegacyFont(), fontSize, "OUTLINE")
    if not ok then fontString:SetFont("Fonts\\FRIZQT__.TTF", fontSize, "OUTLINE") end
    fontString:SetShadowOffset(0, 0)
end

local function IsCloseButton(button)
    local tex = button and button.GetNormalTexture and button:GetNormalTexture()
    local path = tex and tex.GetTexture and tex:GetTexture()
    return type(path) == "string" and string.find(path, "UI%-Panel%-MinimizeButton")
end

local function StyleLegacyButtonBase(button)
    if not button or button.mtLegacyStyled then return end

    -- Detect UIPanelCloseButton before pfUI SkinButton replaces its original
    -- UI-Panel-MinimizeButton texture. Otherwise it is mistaken for a normal
    -- button and keeps the template's oversized square dimensions.
    local isClose = IsCloseButton(button)

    button.mtLegacyStyled = true
    local ar, ag, ab = GetLegacyAccent()
    local br, bg, bb, ba = GetLegacyBackdropColor()
    local er, eg, eb, ea = GetLegacyBorderColor()

    if HasNativePfUI() then
        -- Use pfUI's own button implementation so border thickness, font,
        -- highlights, and configured colors are identical to docked meters.
        pfUI.api.SkinButton(button)
    else
        button:SetBackdrop(MT_LEGACY_BACKDROP)
        button:SetBackdropColor(br, bg, bb, math.min(1, ba + 0.08))
        button:SetBackdropBorderColor(er, eg, eb, ea)
    end

    if isClose then
        button:SetWidth(18)
        button:SetHeight(18)
        button:SetNormalTexture("")
        button:SetPushedTexture("")
        button:SetDisabledTexture("")
        button:SetHighlightTexture("Interface\\Buttons\\WHITE8X8")
        local hi = button:GetHighlightTexture()
        if hi then hi:SetVertexColor(0.75, 0.16, 0.12, 0.45) end
        if not button.mtCloseText then
            button.mtCloseText = button:CreateFontString(nil, "OVERLAY")
            button.mtCloseText:SetPoint("CENTER", button, "CENTER", 0, 0)
            -- Set a font before SetText. WoW 1.12 throws "Font not set" otherwise.
            StyleLegacyFontString(button.mtCloseText, 11)
            button.mtCloseText:SetText("x")
            button.mtCloseText:SetTextColor(0.9, 0.9, 0.9)
        end
    else
        button:SetNormalTexture("")
        button:SetPushedTexture("Interface\\Buttons\\WHITE8X8")
        local pushed = button:GetPushedTexture()
        if pushed then pushed:SetVertexColor(ar, ag, ab, 0.22) end
        button:SetHighlightTexture("Interface\\Buttons\\WHITE8X8")
        local hi = button:GetHighlightTexture()
        if hi then hi:SetVertexColor(ar, ag, ab, 0.16) end
        button:SetDisabledTexture("Interface\\Buttons\\WHITE8X8")
        local disabled = button:GetDisabledTexture()
        if disabled then disabled:SetVertexColor(0.35, 0.35, 0.35, 0.18) end
        if button.SetTextColor then button:SetTextColor(0.88, 0.88, 0.88) end
        if button.SetDisabledTextColor then button:SetDisabledTextColor(0.45, 0.45, 0.45) end
        if button.SetFont then
            local fontSize = GetLegacyFontSize(10)
            local ok = button:SetFont(GetLegacyFont(), fontSize, "OUTLINE")
            if not ok then button:SetFont("Fonts\\FRIZQT__.TTF", fontSize, "OUTLINE") end
        end
    end
end

-- Dispatch through a private override slot so later historical style layers can
-- replace the implementation even after Engine.lua has been split into files.
-- In the old monolith, the later `function StyleLegacyButton` assignment
-- mutated this same lexical local; this dispatcher preserves that behavior.
local function StyleLegacyButton(button)
    if MT._engine and MT._engine.StyleLegacyButtonOverride then
        return MT._engine.StyleLegacyButtonOverride(button)
    end
    return StyleLegacyButtonBase(button)
end

local function StyleLegacyWindow(frame, alpha)
    if not frame or frame.mtLegacyStyled then return end
    frame.mtLegacyStyled = true
    local ar, ag, ab = GetLegacyAccent()
    local br, bg, bb, ba = GetLegacyBackdropColor()
    local er, eg, eb, ea = GetLegacyBorderColor()
    if alpha and alpha < ba then ba = alpha end

    if HasNativePfUI() then
        -- This is the same path pfUI uses for docked KTM/DPSMate meters.
        -- The optional .8 transparency and chat background override mirror
        -- modules/thirdparty-vanilla.lua exactly.
        frame:SetBackdrop(nil)
        pfUI.api.CreateBackdrop(frame, nil, nil,
            (pfUI_config.thirdparty and pfUI_config.thirdparty.chatbg == "1") and 0.8 or nil)

        if frame.backdrop and pfUI_config.thirdparty and
           pfUI_config.thirdparty.chatbg == "1" and
           pfUI_config.chat and pfUI_config.chat.global and
           pfUI_config.chat.global.custombg == "1" then
            local cr, cg, cb, ca = ParseColorString(pfUI_config.chat.global.background, br, bg, bb, ba)
            local rr, rg, rb, ra = ParseColorString(pfUI_config.chat.global.border, er, eg, eb, ea)
            frame.backdrop:SetBackdropColor(cr, cg, cb, ca)
            frame.backdrop:SetBackdropBorderColor(rr, rg, rb, ra)
        end
    else
        frame:SetBackdrop(MT_LEGACY_BACKDROP)
        frame:SetBackdropColor(br, bg, bb, ba)
        frame:SetBackdropBorderColor(er, eg, eb, ea)
    end
end

local function StyleLegacyTree(frame)
    if not frame then return end
    local regions = {frame:GetRegions()}
    local i, region
    for i = 1, table.getn(regions) do
        region = regions[i]
        if region and region.GetObjectType and region:GetObjectType() == "FontString" then
            StyleLegacyFontString(region, 10)
        end
    end
    local children = {frame:GetChildren()}
    local child
    for i = 1, table.getn(children) do
        child = children[i]
        if child and child.GetObjectType and child:GetObjectType() == "Button" then
            StyleLegacyButton(child)
        end
        StyleLegacyTree(child)
    end
end

local function FinalizeLegacyWindow(frame)
    StyleLegacyWindow(frame)
    StyleLegacyTree(frame)
    if frame.title then
        StyleLegacyFontString(frame.title, 11)
        local r, g, b = GetLegacyAccent()
        frame.title:SetTextColor(r, g, b)
    end
    if frame.subtitle then StyleLegacyFontString(frame.subtitle, 9) end
end



local function ResetLegacyStyleFlags(frame)
    if not frame then return end
    frame.mtLegacyStyled = nil
    local children = {frame:GetChildren()}
    local i
    for i = 1, table.getn(children) do
        ResetLegacyStyleFlags(children[i])
    end
end


local function HideDefaultTooltipTextures(tip)
    if not tip then return end
    local regions = {tip:GetRegions()}
    local i, region, texture
    for i = 1, table.getn(regions) do
        region = regions[i]
        if region and region.GetObjectType and region:GetObjectType() == "Texture" then
            texture = region.GetTexture and region:GetTexture()
            if type(texture) == "string" and
               (string.find(texture, "UI%-Tooltip%-Background") or string.find(texture, "UI%-Tooltip%-Border")) then
                region:Hide()
            end
        end
    end
end

function MT:StyleAnalysisTooltipLines(tip)
    if not tip then return end
    local font = GetLegacyFont()
    local size = GetLegacyFontSize(9)
    if pfUI_config and pfUI_config.tooltip then
        if pfUI_config.tooltip.font_tooltip then font = pfUI_config.tooltip.font_tooltip end
        if tonumber(pfUI_config.tooltip.font_tooltip_size) then size = tonumber(pfUI_config.tooltip.font_tooltip_size) end
    end
    local i, left, right, ok
    for i = 1, 30 do
        left = getglobal("MainTankAnalysisTooltipTextLeft" .. i)
        right = getglobal("MainTankAnalysisTooltipTextRight" .. i)
        if left then
            ok = left:SetFont(font, i == 1 and size + 1 or size, "OUTLINE")
            if not ok then left:SetFont("Fonts\\FRIZQT__.TTF", i == 1 and size + 1 or size, "OUTLINE") end
            left:SetShadowOffset(0, 0)
        end
        if right then
            ok = right:SetFont(font, size, "OUTLINE")
            if not ok then right:SetFont("Fonts\\FRIZQT__.TTF", size, "OUTLINE") end
            right:SetShadowOffset(0, 0)
        end
    end
end

function MT:StyleAnalysisTooltip(tip, force)
    if not tip then return end
    if tip.mtAnalysisStyled and not force then return end
    tip.mtAnalysisStyled = true
    HideDefaultTooltipTextures(tip)

    local br, bg, bb, ba = GetLegacyBackdropColor()
    local er, eg, eb, ea = GetLegacyBorderColor()
    local alpha = ba
    if pfUI_config and pfUI_config.tooltip and tonumber(pfUI_config.tooltip.alpha) then
        alpha = tonumber(pfUI_config.tooltip.alpha)
    end

    if HasNativePfUI() then
        if not tip.backdrop then pfUI.api.CreateBackdrop(tip, nil, nil, alpha) end
        if tip.backdrop then
            tip.backdrop:SetBackdropColor(br, bg, bb, alpha)
            tip.backdrop:SetBackdropBorderColor(er, eg, eb, ea)
        end
        if pfUI.api.CreateBackdropShadow and not tip.mtShadowCreated then
            pfUI.api.CreateBackdropShadow(tip)
            tip.mtShadowCreated = true
        end
    else
        tip:SetBackdrop(MT_LEGACY_BACKDROP)
        tip:SetBackdropColor(0.035, 0.035, 0.035, 0.90)
        tip:SetBackdropBorderColor(0, 0, 0, 1)
    end
    tip:SetClampedToScreen(true)
    self:StyleAnalysisTooltipLines(tip)
end

function MT:GetAnalysisTooltip()
    if not self.analysisTooltip then
        local tip = CreateFrame("GameTooltip", "MainTankAnalysisTooltip", UIParent, "GameTooltipTemplate")
        tip:SetFrameStrata("TOOLTIP")
        tip:SetFrameLevel(20)
        tip:SetScript("OnShow", function()
            MT:StyleAnalysisTooltip(this, false)
            MT:StyleAnalysisTooltipLines(this)
        end)
        self.analysisTooltip = tip
        self:StyleAnalysisTooltip(tip, true)
    end
    return self.analysisTooltip
end

function MT:HideAnalysisTooltip()
    if self.analysisTooltip then self.analysisTooltip:Hide() end
end

function MT:RefreshPfUISkin()
    local frames = {self.frame, self.timelineFrame, self.pieFrame, self.detailsFrame, self.biggestFrame}
    local i, frame
    for i = 1, table.getn(frames) do
        frame = frames[i]
        if frame then
            ResetLegacyStyleFlags(frame)
            FinalizeLegacyWindow(frame)
        end
    end
    if self.analysisTooltip then
        self.analysisTooltip.mtAnalysisStyled = nil
        self:StyleAnalysisTooltip(self.analysisTooltip, true)
    end
    -- Styling must never be allowed to alter Full/Mini visibility state.
    if self.ReconcileMainWindowMode then self:ReconcileMainWindowMode() end
end


-- Private compatibility surface used by the historical UI override stack.
E.MT_LEGACY_BACKDROP = MT_LEGACY_BACKDROP
E.GetLegacyFont = GetLegacyFont
E.GetLegacyFontSize = GetLegacyFontSize
E.GetLegacyBorderColor = GetLegacyBorderColor
E.StyleLegacyButton = StyleLegacyButton
E.StyleLegacyButtonBase = StyleLegacyButtonBase
E.StyleLegacyWindow = StyleLegacyWindow
E.FinalizeLegacyWindow = FinalizeLegacyWindow
