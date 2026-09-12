-- MainTank standalone pie renderer
-- Adapted from DPSMate GraphLib's pie-only implementation.
-- No AceLibrary, XML, or external library registration required.

MTPie = MTPie or {}

local PI = math.pi
local COS = math.cos
local SIN = math.sin
local INSERT = table.insert
local GETN = table.getn

local TEXTURE_BASE = "Interface\\AddOns\\MainTank\\GraphTextures\\"
local PIE_PIECES = {
    {50, "Pie\\1-2", 180},
    {25, "Pie\\1-4", 90},
    {12.5, "Pie\\1-8", 45},
    {6.25, "Pie\\1-16", 22.5},
    {3.125, "Pie\\1-32", 11.25},
    {1.5625, "Pie\\1-64", 5.625},
    {0.78125, "Pie\\1-128", 2.8125},
}

local function RotateTexture(texture, angle)
    local radian = PI * (45 - angle) / 180
    local radius = 0.7071067811865475
    local tx = radius * COS(radian)
    local ty = radius * SIN(radian)
    local tx2 = -ty
    local ty2 = tx
    texture:SetTexCoord(
        0.5-tx,  0.5-ty,
        0.5+tx2, 0.5+ty2,
        0.5-tx2, 0.5-ty2,
        0.5+tx,  0.5+ty
    )
end

local function FindTexture(graph)
    graph.pieUsed = graph.pieUsed + 1
    local texture = graph.textures[graph.pieUsed]
    if not texture then
        texture = graph:CreateTexture(nil, "ARTWORK")
        graph.textures[graph.pieUsed] = texture
    end
    texture:ClearAllPoints()
    texture:SetPoint("CENTER", graph, "CENTER", 0, 0)
    texture:SetWidth(graph:GetWidth())
    texture:SetHeight(graph:GetHeight())
    texture:SetBlendMode("BLEND")
    texture:Show()
    return texture
end

local function HideTextures(graph)
    local i
    for i = 1, GETN(graph.textures) do
        graph.textures[i]:Hide()
    end
end

function MTPie:Create(parent, width, height)
    local graph = CreateFrame("Frame", nil, parent)
    graph:SetWidth(width)
    graph:SetHeight(height)
    graph:SetFrameLevel(parent:GetFrameLevel() + 1)
    graph.textures = {}
    graph.sections = {}
    graph.pieUsed = 0
    graph.percentOn = 0
    graph.remaining = 0
    graph:Show()
    return graph
end

function MTPie:Reset(graph)
    HideTextures(graph)
    graph.pieUsed = 0
    graph.percentOn = 0
    graph.remaining = 0
    graph.sections = {}
end

local function AddSection(graph, percent, color, label, complete)
    local piePercent = graph.percentOn
    local currentAngle = piePercent * 3.6
    local section = {textures = {}, color = color, label = label}

    if complete then
        percent = 100 - piePercent
    end
    percent = percent + graph.remaining

    -- Single 100% slice uses the dedicated complete-circle texture.
    if complete and piePercent == 0 then
        local texture = FindTexture(graph)
        texture:SetTexture(TEXTURE_BASE .. "Pie\\1-1")
        texture:SetTexCoord(0, 1, 0, 1)
        texture:SetVertexColor(color[1], color[2], color[3], 1)
        INSERT(section.textures, texture)
        section.endAngle = 360
        INSERT(graph.sections, section)
        graph.percentOn = 100
        graph.remaining = 0
        return
    end

    local i
    for i = 1, GETN(PIE_PIECES) do
        local piecePercent = PIE_PIECES[i][1]
        if (percent + 0.1) > piecePercent then
            local texture = FindTexture(graph)
            texture:SetTexture(TEXTURE_BASE .. PIE_PIECES[i][2])
            texture:SetTexCoord(0, 1, 0, 1)
            RotateTexture(texture, currentAngle)
            texture:SetVertexColor(color[1], color[2], color[3], 1)
            INSERT(section.textures, texture)

            percent = percent - piecePercent
            piePercent = piePercent + piecePercent
            currentAngle = currentAngle + PIE_PIECES[i][3]
        end
    end

    section.endAngle = complete and 360 or currentAngle
    INSERT(graph.sections, section)
    graph.percentOn = piePercent
    graph.remaining = percent
end

function MTPie:Draw(graph, entries, total)
    self:Reset(graph)
    if not entries or GETN(entries) == 0 or not total or total <= 0 then
        local texture = FindTexture(graph)
        texture:SetTexture(TEXTURE_BASE .. "Pie\\1-1")
        texture:SetTexCoord(0, 1, 0, 1)
        texture:SetVertexColor(0.20, 0.20, 0.20, 0.65)
        graph.sections[1] = {endAngle=360, label="No data", color={0.2,0.2,0.2}}
        return
    end

    local i, entry
    for i = 1, GETN(entries) do
        entry = entries[i]
        if i == GETN(entries) then
            AddSection(graph, 0, entry.color, entry.label, true)
        else
            AddSection(graph, (entry.value / total) * 100, entry.color, entry.label, false)
        end
    end
end
