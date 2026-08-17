-- rosteroverlay.lua - /scoot debug rosteroverlay: why the raid overlay rows read blank
local addonName, addon = ...

--------------------------------------------------------------------------------
-- /scoot debug rosteroverlay — why are the overlay rows blank?
--------------------------------------------------------------------------------
-- The overlay wraps every name transfer in pcall so a secret value cannot break
-- layout. The cost is that a failing transfer is completely silent -- no error
-- reaches BugSack. This dump un-swallows those pcalls: for each raid member
-- frame it reports whether the frame exists, whether its name FontString
-- exists, and exactly what GetText/SetText did, including the error text.
--------------------------------------------------------------------------------

local function describe(ok, value, err)
    if not ok then
        return "ERROR: " .. tostring(err)
    end
    if value == nil then
        return "nil"
    end
    local secret = false
    if issecretvalue then
        local okS, isS = pcall(issecretvalue, value)
        secret = okS and isS or false
    end
    if secret then
        return "SECRET (type " .. tostring(type(value)) .. ")"
    end
    return string.format("%q", tostring(value))
end

local function probeFrame(lines, label, frame)
    if not frame then return false end

    -- Ask the real code which FontString it would bind, so this report cannot
    -- drift from the live behaviour. Falls back to frame.name if the overlay
    -- module predates the accessor.
    local RO = addon.RaidRosterOverlay
    local nameFS
    if RO and RO.ResolveNameSource then
        nameFS = RO:ResolveNameSource(frame)
    else
        nameFS = frame.name
    end

    -- Which one did it pick? This is the whole question when colours are wrong:
    -- Scoot colours its own overlay FontString, never Blizzard's.
    local sourceDesc = "blizzard name"
    local BRF = addon.BarsRaidFrames
    local state = BRF and BRF._getState and BRF._getState(frame)
    if state and state.nameOverlayText and nameFS == state.nameOverlayText then
        sourceDesc = "scoot overlay"
    elseif state and state.nameOverlayText then
        sourceDesc = "blizzard name (scoot overlay exists but inactive)"
    end

    if not nameFS then
        table.insert(lines, label .. ": frame exists, name FontString = nil"
            .. "  [source " .. sourceDesc .. "]")
        return true
    end

    -- GetText, with the error surfaced rather than swallowed.
    local okGet, valOrErr = pcall(nameFS.GetText, nameFS)
    local getDesc
    if okGet then
        getDesc = describe(true, valOrErr)
    else
        getDesc = describe(false, nil, valOrErr)
    end

    -- Can that value be forwarded into a throwaway FontString? This is the exact
    -- operation the overlay performs, so its result is the answer.
    local probe = addon._RosterOverlayProbeFS
    if not probe then
        local host = CreateFrame("Frame", nil, UIParent)
        host:Hide()
        probe = host:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        addon._RosterOverlayProbeFS = probe
    end
    local setDesc = "not attempted"
    if okGet then
        local okSet, setErr = pcall(probe.SetText, probe, valOrErr)
        setDesc = okSet and "ok" or ("ERROR: " .. tostring(setErr))
    end

    -- Is the overlay hooked to this FontString, and pointed somewhere?
    local bound = "no"
    local bindings = addon.RaidRosterOverlay and addon.RaidRosterOverlay._bindings
    if bindings then
        local b = bindings[nameFS]
        if b then
            bound = b.target and "yes -> target set" or "yes -> target NIL"
        end
    end

    -- The colour expected to land on the row. A mismatch between this and the
    -- row's own colour localises the failure to the forwarding, not the source.
    local colorDesc = "?"
    local okC, r, g, b, a = pcall(nameFS.GetTextColor, nameFS)
    if okC and r then
        colorDesc = string.format("r=%.2f g=%.2f b=%.2f a=%.2f", r, g or 0, b or 0, a or 0)
        if r > 0.95 and (g or 0) > 0.95 and (b or 0) > 0.95 then
            colorDesc = colorDesc .. "   <-- WHITE (unclassed)"
        end
    elseif not okC then
        colorDesc = "ERROR: " .. tostring(r)
    end

    -- The frame's own shown state, which is what decides whether the overlay
    -- lists it at all. A hidden frame still holding text is a retired slot.
    local frameShown = "?"
    local okF, fShown = pcall(frame.IsShown, frame)
    if okF then
        frameShown = tostring(fShown)
        if not fShown then
            frameShown = frameShown .. "   <-- RETIRED, not listed"
        end
    end

    table.insert(lines, label .. ":")
    table.insert(lines, "    frameShown = " .. frameShown)
    table.insert(lines, "    source   = " .. sourceDesc)
    table.insert(lines, "    GetText  = " .. getDesc)
    table.insert(lines, "    SetText  = " .. setDesc)
    table.insert(lines, "    color    = " .. colorDesc)
    table.insert(lines, "    shown    = " .. tostring(nameFS:IsShown()))
    table.insert(lines, "    bound    = " .. bound)
    return true
end

function addon.DebugRosterOverlay()
    local lines = { "== Roster Overlay probe ==" }

    local RO = addon.RaidRosterOverlay
    table.insert(lines, "module loaded : " .. tostring(RO ~= nil))
    table.insert(lines, "frame built   : " .. tostring(RO and RO._frame ~= nil))
    table.insert(lines, "last apply    : " .. tostring(RO and RO._lastApplyReason))
    table.insert(lines, "issecretvalue : " .. tostring(issecretvalue ~= nil))
    table.insert(lines, "IsInRaid()    : " .. tostring(IsInRaid and IsInRaid()))
    table.insert(lines, "GetNumGroupMembers: " .. tostring(GetNumGroupMembers and GetNumGroupMembers()))

    local bindingCount = 0
    if RO and RO._bindings then
        for _ in pairs(RO._bindings) do bindingCount = bindingCount + 1 end
    end
    table.insert(lines, "bindings held : " .. bindingCount)
    table.insert(lines, "")

    -- Grouped frames first, then the combined-mode flat frames.
    table.insert(lines, "-- CompactRaidGroup<G>Member<M> --")
    local groupedFound = 0
    for g = 1, 8 do
        for m = 1, 5 do
            local label = "  G" .. g .. "M" .. m
            local f = _G["CompactRaidGroup" .. g .. "Member" .. m]
            if probeFrame(lines, label, f) then
                groupedFound = groupedFound + 1
            end
        end
    end
    if groupedFound == 0 then
        table.insert(lines, "  (none exist)")
    end

    table.insert(lines, "")
    table.insert(lines, "-- CompactRaidFrame<N> --")
    local flatFound = 0
    for i = 1, 40 do
        local f = _G["CompactRaidFrame" .. i]
        if probeFrame(lines, "  RF" .. i, f) then
            flatFound = flatFound + 1
        end
    end
    if flatFound == 0 then
        table.insert(lines, "  (none exist)")
    end

    addon.DebugShowWindow("Roster Overlay Probe", lines)
end

--------------------------------------------------------------------------------
-- /scoot debug roster rows — what state are the Scoot rows in?
--------------------------------------------------------------------------------
-- The other probe looks at Blizzard's side of the transfer. This one looks at
-- the Scoot side: are the rows shown, sized, positioned, and -- the question that matters
-- most -- what alpha is their text colour sitting at? A row holding the right
-- text at alpha 0 is indistinguishable from an empty row on screen.
--------------------------------------------------------------------------------

local function dumpRow(lines, label, fs)
    if not fs then
        table.insert(lines, label .. ": nil")
        return
    end

    local shown = tostring(fs:IsShown())
    local w = tostring(math.floor((fs:GetWidth() or 0) + 0.5))
    local h = tostring(math.floor((fs:GetHeight() or 0) + 0.5))

    local colorDesc = "?"
    local okC, r, g, b, a = pcall(fs.GetTextColor, fs)
    if okC and r then
        colorDesc = string.format("r=%.2f g=%.2f b=%.2f a=%.2f",
            r or 0, g or 0, b or 0, a or 0)
        if (a or 0) < 0.05 then
            colorDesc = colorDesc .. "   <-- INVISIBLE"
        end
    elseif not okC then
        colorDesc = "ERROR: " .. tostring(r)
    end

    -- Scoot's own rows may hold a secret name, so GetText is reported defensively
    -- and never compared against anything.
    local textDesc
    local okT, val = pcall(fs.GetText, fs)
    if not okT then
        textDesc = "ERROR: " .. tostring(val)
    elseif val == nil then
        textDesc = "nil"
    else
        local secret = false
        if issecretvalue then
            local okS, isS = pcall(issecretvalue, val)
            secret = okS and isS or false
        end
        if secret then
            textDesc = "SECRET (has content)"
        else
            local okStr, s = pcall(tostring, val)
            textDesc = okStr and string.format("%q", s) or "unprintable"
        end
    end

    local anchorDesc = "no point"
    local okP, point, _, _, x, y = pcall(fs.GetPoint, fs, 1)
    if okP and point then
        anchorDesc = string.format("%s %d,%d", tostring(point),
            math.floor((x or 0) + 0.5), math.floor((y or 0) + 0.5))
    end

    table.insert(lines, label .. ":")
    table.insert(lines, "    shown = " .. shown .. "   size = " .. w .. "x" .. h)
    table.insert(lines, "    anchor= " .. anchorDesc)
    table.insert(lines, "    color = " .. colorDesc)
    table.insert(lines, "    text  = " .. textDesc)
end

function addon.DebugRosterOverlayRows()
    local lines = { "== Roster Overlay row state ==" }

    local RO = addon.RaidRosterOverlay
    local frame = RO and RO._frame
    if not frame then
        table.insert(lines, "Overlay frame does not exist (never enabled?).")
        addon.DebugShowWindow("Roster Overlay Rows", lines)
        return
    end

    local okA, alpha = pcall(frame.GetAlpha, frame)
    table.insert(lines, "frame shown   : " .. tostring(frame:IsShown()))
    table.insert(lines, "frame alpha   : " .. tostring(okA and alpha))
    table.insert(lines, "frame size    : "
        .. math.floor((frame:GetWidth() or 0) + 0.5) .. "x"
        .. math.floor((frame:GetHeight() or 0) + 0.5))
    table.insert(lines, "last apply    : " .. tostring(RO._lastApplyReason))
    table.insert(lines, "")

    table.insert(lines, "-- group blocks (shown rows only) --")
    local anyShown = false
    for g = 1, 8 do
        local block = frame._groups and frame._groups[g]
        if block then
            if block.header and block.header:IsShown() then
                anyShown = true
                dumpRow(lines, "  G" .. g .. " header", block.header)
                for m = 1, 5 do
                    local row = block.rows and block.rows[m]
                    if row and row:IsShown() then
                        dumpRow(lines, "  G" .. g .. "M" .. m, row)
                    end
                end
            end
        end
    end
    if not anyShown then
        table.insert(lines, "  (no group blocks shown)")
    end

    table.insert(lines, "")
    table.insert(lines, "-- flat rows (shown only) --")
    local anyFlat = false
    for i = 1, 40 do
        local row = frame._flatRows and frame._flatRows[i]
        if row and row:IsShown() then
            anyFlat = true
            dumpRow(lines, "  RF" .. i, row)
        end
    end
    if not anyFlat then
        table.insert(lines, "  (none shown)")
    end

    addon.DebugShowWindow("Roster Overlay Rows", lines)
end
