-- editmode.lua - Edit Mode frame diagnostic dump
local addonName, addon = ...

-- Short keys accepted by /scoot debug <target>; any other word is a global frame name.
local FRAME_KEYS = {
    ab1 = "MainActionBar",
    ab2 = "MultiBarBottomLeft",
    ab3 = "MultiBarBottomRight",
    ab4 = "MultiBarRight",
    ab5 = "MultiBarLeft",
    ab6 = "MultiBar5",
    ab7 = "MultiBar6",
    ab8 = "MultiBar7",
    essential = "EssentialCooldownViewer",
    utility = "UtilityCooldownViewer",
    micro = "MicroMenuContainer",
    stance = "StanceBar",
    buffs  = "BuffFrame",
    debuffs = "DebuffFrame",
    tracker = "ObjectiveTrackerFrame",
    objectivetracker = "ObjectiveTrackerFrame",
    player = "PlayerFrame",
    target = "TargetFrame",
    focus  = "FocusFrame",
    pet    = "PetFrame",
}

-- Sorted list of the short keys, for the generated /scoot debug help.
function addon.DebugDumpTargets()
    local keys = {}
    for key in pairs(FRAME_KEYS) do keys[#keys + 1] = key end
    table.sort(keys)
    return keys
end

local function ResolveFrameByKey(key)
    key = tostring(key or ""):lower()
    local map = FRAME_KEYS
    -- Special-case resolution for Unit Frames using Edit Mode's registry for reliability
    local UNIT_KEYS = { player = "Player", target = "Target", focus = "Focus", pet = "Pet" }
    if UNIT_KEYS[key] then
        local f = addon.GetEditModeUnitFrame(UNIT_KEYS[key])
        if f then return f, (map[key] or key) end
    end
    local name = map[key] or key -- allow raw global name
    return _G[name], name
end

local function DumpEditModeSettingsForFrame(frame, frameName)
    local LEO = LibStub and LibStub("LibEditModeOverride-1.0")
    if not (LEO and LEO.IsReady and LEO:IsReady()) then
        return "Edit Mode is not ready. Open Edit Mode once to initialize."
    end
    if LEO.LoadLayouts then pcall(LEO.LoadLayouts, LEO) end
    if not frame or not frame.system then
        return string.format("Frame not found or not Edit Mode managed: %s", tostring(frameName))
    end
    local lines = {}
    local function push(s) table.insert(lines, s) end
    push(string.format("Frame: %s  system=%s index=%s", tostring(frameName), tostring(frame.system), tostring(frame.systemIndex)))

    -- Special Aura Frame dump for Buffs/Debuffs to troubleshoot Orientation/Wrap/Direction.
    local sysEnum = _G.Enum and _G.Enum.EditModeSystem
    local dirEnum = _G.Enum and _G.Enum.AuraFrameIconDirection
    if sysEnum and frame.system == sysEnum.AuraFrame and dirEnum then
        local LEO = LibStub and LibStub("LibEditModeOverride-1.0")
        if LEO and LEO.IsReady and LEO:IsReady() then
            if LEO.LoadLayouts then pcall(LEO.LoadLayouts, LEO) end
            local function safeGet(settingLogical)
                local id = addon.EditMode and addon.EditMode.ResolveSettingIdForComponent and addon.EditMode.ResolveSettingIdForComponent({ frameName = frameName }, settingLogical)
                if not id then return "id=nil", nil end
                local ok, v = pcall(function() return LEO:GetFrameSetting(frame, id) end)
                if not ok then return string.format("id=%s error", tostring(id)), nil end
                return string.format("id=%s value=%s", tostring(id), tostring(v)), v
            end

            push("")
            push("== Aura Frame Orientation/Wrap/Direction (raw) ==")
            local orientStr, orientVal = safeGet("orientation")
            local wrapStr,   wrapVal   = safeGet("icon_wrap")
            local dirStr,    dirVal    = safeGet("icon_direction")
            push("Orientation: "..orientStr)
            push("IconWrap   : "..wrapStr)
            push("IconDir    : "..dirStr)

            local function mapDirEnum(v)
                if v == dirEnum.Up then return "Up"
                elseif v == dirEnum.Down then return "Down"
                elseif v == dirEnum.Left then return "Left"
                elseif v == dirEnum.Right then return "Right"
                end
                return tostring(v)
            end

            if wrapVal ~= nil or dirVal ~= nil then
                push("")
                push("Interpreted (AuraFrameIconDirection):")
                push("  Wrap enum -> "..mapDirEnum(wrapVal))
                push("  Dir  enum -> "..mapDirEnum(dirVal))
            end

            -- Also dump Scoot DB snapshot for Buffs component if present.
            if addon.Components and addon.Components.buffs then
                local c = addon.Components.buffs
                push("")
                push("Scoot Buffs DB snapshot:")
                push("  orientation = "..tostring(c.db and c.db.orientation))
                push("  iconWrap    = "..tostring(c.db and c.db.iconWrap))
                push("  direction   = "..tostring(c.db and c.db.direction))
            end
        else
            push("")
            push("Aura Frame: LibEditModeOverride not ready; raw dump unavailable.")
        end
        push("")
        push("-- Full Edit Mode setting list follows --")
    end
    local entries = _G.EditModeSettingDisplayInfoManager and _G.EditModeSettingDisplayInfoManager.systemSettingDisplayInfo and _G.EditModeSettingDisplayInfoManager.systemSettingDisplayInfo[frame.system]
    if type(entries) ~= "table" then
        push("No setting display info available for this system.")
        return table.concat(lines, "\n")
    end
    -- Sort by setting id for stability
    table.sort(entries, function(a,b) return (a.setting or 0) < (b.setting or 0) end)
    for _, setup in ipairs(entries) do
        local id = setup.setting
        local name = setup.name or "(unnamed)"
        local tp = setup.type
        local val
        local ok, v = pcall(function() return LEO:GetFrameSetting(frame, id) end)
        if ok then val = v else val = "<error>" end
        if tp == Enum.EditModeSettingDisplayType.Slider then
            local minV = setup.minValue; local maxV = setup.maxValue; local step = setup.stepSize
            push(string.format("[%s] %s (Slider min=%s max=%s step=%s) = %s", tostring(id), name, tostring(minV), tostring(maxV), tostring(step), tostring(val)))
        elseif tp == Enum.EditModeSettingDisplayType.Dropdown then
            local opts = ""
            if type(setup.options) == "table" then
                local buf = {}
                for _, opt in ipairs(setup.options) do table.insert(buf, string.format("%s:%s", tostring(opt.value), tostring(opt.text or opt.value))) end
                opts = table.concat(buf, ", ")
            end
            push(string.format("[%s] %s (Dropdown options=%s) = %s", tostring(id), name, opts, tostring(val)))
        elseif tp == Enum.EditModeSettingDisplayType.Checkbox then
            push(string.format("[%s] %s (Checkbox 0/1) = %s", tostring(id), name, tostring(val)))
        else
            push(string.format("[%s] %s (type=%s) = %s", tostring(id), name, tostring(tp), tostring(val)))
        end
    end
    return table.concat(lines, "\n")
end

function addon.DebugDump(target)
    local frame, name = ResolveFrameByKey(target)
    local dump = DumpEditModeSettingsForFrame(frame, name)
    addon.DebugShowWindow("Edit Mode Settings - "..tostring(name), dump)
end
