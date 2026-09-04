-- debug/widget.lua - /scoot debug widget commands for the Widget component
local addonName, addon = ...

local DUMMY_COLORS = {
    { 0.20, 0.55, 0.95 },
    { 0.95, 0.55, 0.20 },
    { 0.75, 0.30, 0.85 },
    { 0.95, 0.85, 0.20 },
    { 0.30, 0.85, 0.65 },
}

local dummyCount = 0

local function makeDummyFrame(index)
    local frame = CreateFrame("Frame", nil, UIParent)
    frame:SetSize(200, 60)
    frame:SetFrameStrata("MEDIUM")

    local bg = frame:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    local c = DUMMY_COLORS[((index - 1) % #DUMMY_COLORS) + 1]
    bg:SetColorTexture(c[1], c[2], c[3], 0.85)

    local label = frame:CreateFontString(nil, "OVERLAY")
    local fontPath = select(1, GameFontNormal:GetFont())
    label:SetFont(fontPath, 12, "OUTLINE")
    label:SetPoint("CENTER")
    label:SetText("Flyout Child #" .. index)
    label:SetTextColor(1, 1, 1, 1)

    return frame
end

function addon.DebugWidgetSpawnChild()
    if not addon.Widget or not addon.Widget.RegisterFlyoutChild then
        addon:Print("Widget module not loaded.")
        return
    end
    local W = addon.Widget
    if not W:GetFrame() then
        addon:Print("Widget frame not created yet. Enable the Widget module on the Features page and reload.")
        return
    end

    dummyCount = dummyCount + 1
    local frame = makeDummyFrame(dummyCount)
    local handle = W:RegisterFlyoutChild(frame, {
        id = "debugDummy" .. dummyCount,
        onRelease = function(f)
            if f and f.Hide then f:Hide() end
            if f and f.SetParent then f:SetParent(nil) end
        end,
    })

    if not handle then
        addon:Print("RegisterFlyoutChild returned nil.")
        return
    end

    addon._debugWidgetHandles = addon._debugWidgetHandles or {}
    table.insert(addon._debugWidgetHandles, handle)
    addon:Print("Spawned flyout child #" .. dummyCount .. " (direction: " .. (W:GetFlyoutDirection() or "?") .. ")")
end

function addon.DebugWidgetReleaseAll()
    if not addon.Widget or not addon.Widget.ReleaseAllFlyoutChildren then
        addon:Print("Widget module not loaded.")
        return
    end
    addon.Widget:ReleaseAllFlyoutChildren()
    addon._debugWidgetHandles = nil
    dummyCount = 0
    addon:Print("Released all flyout children.")
end

function addon.DebugWidgetState()
    if not addon.Widget then
        addon:Print("Widget module not loaded.")
        return
    end
    local W = addon.Widget
    local comp = addon.Components and addon.Components["widget"]
    local frame = W:GetFrame()
    addon:Print("== Widget State ==")
    addon:Print("  Component registered: " .. tostring(comp ~= nil))
    addon:Print("  Frame created: " .. tostring(frame ~= nil))
    addon:Print("  IsVisible: " .. tostring(W:IsVisible()))
    addon:Print("  Flyout direction: " .. tostring(W:GetFlyoutDirection()))
    if frame then
        addon:Print("  Alpha: " .. string.format("%.2f", frame:GetAlpha()))
        local point, _, relativePoint, x, y = frame:GetPoint(1)
        if point then
            addon:Print(string.format("  Position: %s -> %s, %d, %d", point, tostring(relativePoint), x or 0, y or 0))
        end
    end
end

addon:RegisterDebugCommand({
    name = "widget", help = "widget component pool", default = "state",
    verbs = {
        { word = "state", help = "pool and handle state", fn = addon.DebugWidgetState },
        { word = "spawnchild", help = "spawn one child handle", fn = addon.DebugWidgetSpawnChild },
        { word = "releaseall", help = "release every handle", fn = addon.DebugWidgetReleaseAll },
    },
})
