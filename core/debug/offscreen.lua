-- offscreen.lua - /scoot debug offscreen: why a dragged frame lands outside the screen
local addonName, addon = ...

--[[----------------------------------------------------------------------------
    Off-screen drag debugging

    Purpose:
      The off-screen unlock feature is sensitive to which exact frame Edit Mode
      is dragging (system wrapper vs. proxy/handle vs. underlying unit frame).
      This dump prints clamp state + anchor summary for Player/Target candidates.

    Usage:
      /scoot debug offscreen
----------------------------------------------------------------------------]]--

local function _SafeName(f)
    if not f then return "<nil>" end
    if f.GetName then
        local ok, n = pcall(f.GetName, f)
        if ok and n and n ~= "" then return n end
    end
    return tostring(f)
end

local function _SafeBoolCall(f, methodName)
    if not (f and f[methodName]) then return "<no:"..methodName..">" end
    local ok, v = pcall(f[methodName], f)
    if not ok then return "<err>" end
    return v and true or false
end

local function _SafeClampInsets(f)
    if not (f and f.GetClampRectInsets) then return "<no:GetClampRectInsets>" end
    local ok, l, r, t, b = pcall(f.GetClampRectInsets, f)
    if not ok then return "<err>" end
    return string.format("l=%s r=%s t=%s b=%s", tostring(l or 0), tostring(r or 0), tostring(t or 0), tostring(b or 0))
end

local function _SafePointSummary(f)
    if not (f and f.GetNumPoints and f.GetPoint) then return "<no:GetPoint>" end
    local okN, n = pcall(f.GetNumPoints, f)
    if not okN or not n or n <= 0 then return "<no_points>" end
    local ok, point, relTo, relPoint, xOfs, yOfs = pcall(f.GetPoint, f, 1)
    if not ok or not point then return "<err>" end
    return string.format("%s -> %s %s (x=%s y=%s) (#pts=%d)",
        tostring(point),
        _SafeName(relTo),
        tostring(relPoint or point),
        tostring(xOfs or 0),
        tostring(yOfs or 0),
        tonumber(n) or 0
    )
end

local function _CollectOffscreenCandidates(unitKey)
    local out, seen = {}, {}
    local function add(f)
        if not f or type(f) ~= "table" then return end
        if seen[f] then return end
        seen[f] = true
        table.insert(out, f)
    end

    local reg = addon.GetEditModeUnitFrame(unitKey)
    add(reg)
    if reg then
        add(rawget(reg, "DragHandle"))
        add(rawget(reg, "dragHandle"))
        add(rawget(reg, "Selection"))
        add(rawget(reg, "selection"))
        add(rawget(reg, "Mover"))
        add(rawget(reg, "mover"))
        add(rawget(reg, "SystemFrame"))
        add(rawget(reg, "systemFrame"))
        add(rawget(reg, "frame"))
        add(rawget(reg, "managedFrame"))
        if reg.GetChildren then
            local kids = { reg:GetChildren() }
            for i = 1, math.min(#kids, 20) do
                add(kids[i])
            end
        end
    end
    add(unitKey == "Player" and _G.PlayerFrame or nil)
    add(unitKey == "Target" and _G.TargetFrame or nil)

    -- parent chain (bounded)
    for i = 1, #out do
        local f = out[i]
        local p = (f and f.GetParent) and f:GetParent() or nil
        if p and type(p) == "table" then
            add(p)
            local pp = (p.GetParent and p:GetParent()) or nil
            if pp and type(pp) == "table" then add(pp) end
        end
    end

    return out, reg
end

function addon.DebugOffscreenUnlockDump()
    local lines = {}
    local function push(s) table.insert(lines, s) end

    local profile = addon and addon.db and addon.db.profile
    local uf = profile and rawget(profile, "unitFrames")
    push("Scoot Off-screen Unlock Debug")
    push("Note: This is a diagnostic dump. Copy/paste into chat with your agent if needed.")
    push("")

    for _, unitKey in ipairs({ "Player", "Target" }) do
        local unitCfg = (type(uf) == "table") and rawget(uf, unitKey) or nil
        local misc = (type(unitCfg) == "table") and rawget(unitCfg, "misc") or nil
        local allow = (type(misc) == "table") and (rawget(misc, "allowOffscreenDrag") == true) or false
        push("== "..unitKey.." ==")
        push("DB: allowOffscreenDrag="..tostring(allow))

        local candidates, reg = _CollectOffscreenCandidates(unitKey)
        push("RegisteredSystemFrame: ".._SafeName(reg))
        push("Candidates: "..tostring(#candidates))

        for i, f in ipairs(candidates) do
            local hasClamp = (f and f.SetClampedToScreen) and true or false
            local hasInsets = (f and f.SetClampRectInsets) and true or false
            push(string.format("  [%02d] %s", i, _SafeName(f)))
            push("       hasSetClampedToScreen="..tostring(hasClamp).."  hasSetClampRectInsets="..tostring(hasInsets))
            push("       IsClampedToScreen="..tostring(_SafeBoolCall(f, "IsClampedToScreen")))
            push("       ClampInsets="..tostring(_SafeClampInsets(f)))
            -- Scoot runtime flags (if any)
            local active = f and rawget(f, "_ScootOffscreenUnclampActive")
            local enforce = f and rawget(f, "_ScootOffscreenEnforceEnabled")
            push("       ScootFlags: active="..tostring(active).." enforce="..tostring(enforce))
            push("       Point1="..tostring(_SafePointSummary(f)))
        end

        push("")
    end

    addon.DebugShowWindow("Off-screen Unlock Debug", table.concat(lines, "\n"))
end
