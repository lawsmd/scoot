-- export.lua - Profile export to copyable Lua table
local addonName, addon = ...

--[[----------------------------------------------------------------------------
    Profile export (AceDB -> copyable Lua table)

    Purpose:
      - Produce a deterministic, copy/paste friendly Lua table literal for a given
        AceDB profile (usually the current profile).
      - Intended for preset ingestion into the preset payload files under core/preset_*.lua
        (for example core/preset_scooterui.lua).
----------------------------------------------------------------------------]]--

local function _IsIdentifierKey(s)
    return type(s) == "string" and s:match("^[A-Za-z_][A-Za-z0-9_]*$") ~= nil
end

local function _SortKeysStable(keys)
    local typeOrder = {
        number = 1,
        string = 2,
        boolean = 3,
        table = 4,
        userdata = 5,
        ["function"] = 6,
        thread = 7,
        ["nil"] = 8,
    }
    table.sort(keys, function(a, b)
        local ta, tb = type(a), type(b)
        local oa, ob = typeOrder[ta] or 99, typeOrder[tb] or 99
        if oa ~= ob then return oa < ob end
        if ta == "number" then return a < b end
        if ta == "string" then return a < b end
        if ta == "boolean" then return (a == false and b == true) end
        return tostring(a) < tostring(b)
    end)
end

local function _SerializeLuaValue(value, indent, visited, depth)
    indent = indent or 0
    visited = visited or {}
    depth = depth or 0

    local t = type(value)
    if t == "nil" then return "nil" end
    if t == "boolean" then return value and "true" or "false" end
    if t == "number" then
        -- Preserve numeric fidelity (avoid locale formatting); tostring is fine in WoW Lua.
        return tostring(value)
    end
    if t == "string" then
        return string.format("%q", value)
    end
    if t ~= "table" then
        -- Unsupported types should not appear in AceDB profiles, but guard anyway.
        return "nil --[[unsupported:" .. t .. "]]"
    end

    if visited[value] then
        -- Cycles are unexpected in AceDB; keep the output valid Lua.
        return "nil --[[cycle]]"
    end
    if depth > 25 then
        return "nil --[[max_depth]]"
    end
    visited[value] = true

    local pad = string.rep("  ", indent)
    local padIn = string.rep("  ", indent + 1)

    -- Detect simple array (1..n) with no extra keys to keep output compact.
    local isArray = true
    local maxIndex = 0
    local count = 0
    for k in pairs(value) do
        if type(k) ~= "number" or k < 1 or k % 1 ~= 0 then
            isArray = false
            break
        end
        if k > maxIndex then maxIndex = k end
        count = count + 1
    end
    if isArray and count ~= maxIndex then
        isArray = false
    end

    local out = {}
    table.insert(out, "{\n")

    if isArray then
        for i = 1, maxIndex do
            local v = value[i]
            table.insert(out, padIn)
            table.insert(out, _SerializeLuaValue(v, indent + 1, visited, depth + 1))
            table.insert(out, ",\n")
        end
    else
        local keys = {}
        for k in pairs(value) do
            table.insert(keys, k)
        end
        _SortKeysStable(keys)

        for _, k in ipairs(keys) do
            local v = value[k]
            local keyExpr
            if _IsIdentifierKey(k) then
                keyExpr = k
            else
                local kt = type(k)
                if kt == "string" then
                    keyExpr = "[" .. string.format("%q", k) .. "]"
                elseif kt == "number" or kt == "boolean" then
                    keyExpr = "[" .. tostring(k) .. "]"
                else
                    -- Fall back to stringifying the key to keep the output valid.
                    keyExpr = "[" .. string.format("%q", tostring(k)) .. "]"
                end
            end

            table.insert(out, padIn)
            table.insert(out, keyExpr)
            table.insert(out, " = ")
            table.insert(out, _SerializeLuaValue(v, indent + 1, visited, depth + 1))
            table.insert(out, ",\n")
        end
    end

    table.insert(out, pad)
    table.insert(out, "}")
    visited[value] = nil
    return table.concat(out, "")
end

function addon.DebugExportProfile(profileName)
    if not addon or not addon.db then
        addon.DebugShowWindow("Scoot Profile Export", "AceDB not initialized.")
        return
    end

    local db = addon.db
    local key = profileName
    if type(key) ~= "string" or key == "" then
        if db.GetCurrentProfile then
            key = db:GetCurrentProfile()
        end
    end
    if type(key) ~= "string" or key == "" then
        key = "<unknown>"
    end

    local profile
    if db.profiles and db.profiles[key] then
        profile = db.profiles[key]
    else
        -- Fallback to currently active profile table (includes live unsaved changes).
        profile = db.profile
    end

    if type(profile) ~= "table" then
        addon.DebugShowWindow("Scoot Profile Export - " .. tostring(key), "Profile table not found.")
        return
    end

    local snapshot = CopyTable(profile)
    local header = table.concat({
        "-- Scoot profile export",
        "-- Profile: " .. tostring(key),
        "-- Captured: " .. (date and date("%Y-%m-%d %H:%M:%S") or "unknown"),
        "",
    }, "\n")

    local payload = _SerializeLuaValue(snapshot, 0, {}, 0)
    addon.DebugShowWindow("Scoot Profile Export - " .. tostring(key), header .. payload)

    -- Persist the last export into SavedVariables so preset ingestion can be
    -- performed without manual copy/paste (run export, then /reload or logout).
    -- NOTE: This is stored in AceDB.global intentionally (not per-profile).
    if db and db.global then
        db.global.presetCaptures = db.global.presetCaptures or {}
        db.global.presetCaptures.profile = {
            profileKey = key,
            capturedAt = date and date("%Y-%m-%d %H:%M:%S") or nil,
            payload = payload,
        }
        if _G.C_Crypto and type(_G.C_Crypto.Hash) == "function" then
            local ok, hash = pcall(_G.C_Crypto.Hash, "SHA256", payload)
            if ok and type(hash) == "string" and hash ~= "" then
                db.global.presetCaptures.profile.sha256 = string.lower(hash)
            end
        end
    end
end

local function _FindLayoutInfoByName(layoutName)
    if not _G.C_EditMode or type(_G.C_EditMode.GetLayouts) ~= "function" then
        return nil, "C_EditMode.GetLayouts unavailable."
    end
    local li = _G.C_EditMode.GetLayouts()
    if not (li and type(li.layouts) == "table") then
        return nil, "Unable to read layouts."
    end
    if type(layoutName) == "string" and layoutName ~= "" then
        for _, layout in ipairs(li.layouts) do
            if layout and layout.layoutName == layoutName then
                return layout
            end
        end
        return nil, "Layout not found: " .. tostring(layoutName)
    end
    local idx = li.activeLayout
    local active = idx and li.layouts and li.layouts[idx]
    if not active then
        return nil, "Active layout not found."
    end
    return active
end

function addon.DebugExportEditModeLayout(layoutName)
    if not addon or not addon.db then
        addon.DebugShowWindow("Edit Mode Layout Export", "AceDB not initialized.")
        return
    end
    if not _G.C_EditMode or type(_G.C_EditMode.ConvertLayoutInfoToString) ~= "function" then
        addon.DebugShowWindow("Edit Mode Layout Export", "C_EditMode.ConvertLayoutInfoToString API unavailable.")
        return
    end

    local layoutInfo, err = _FindLayoutInfoByName(layoutName)
    if not layoutInfo then
        addon.DebugShowWindow("Edit Mode Layout Export", err or "Unable to resolve layout.")
        return
    end

    local ok, exportString = pcall(_G.C_EditMode.ConvertLayoutInfoToString, layoutInfo)
    if not ok or type(exportString) ~= "string" or exportString == "" then
        addon.DebugShowWindow("Edit Mode Layout Export", "Export failed: " .. tostring(exportString))
        return
    end

    local name = layoutInfo.layoutName or layoutName or "Active"
    local header = table.concat({
        "-- Edit Mode layout export (Blizzard Share string)",
        "-- Layout: " .. tostring(name),
        "-- Captured: " .. (date and date("%Y-%m-%d %H:%M:%S") or "unknown"),
        "",
    }, "\n")

    addon.DebugShowWindow("Edit Mode Layout Export - " .. tostring(name), header .. exportString)

    -- Persist to SavedVariables for agent ingestion (run export, then /reload or logout).
    local db = addon.db
    db.global = db.global or {}
    db.global.presetCaptures = db.global.presetCaptures or {}
    db.global.presetCaptures.editMode = {
        layoutName = name,
        capturedAt = date and date("%Y-%m-%d %H:%M:%S") or nil,
        export = exportString,
    }
    if _G.C_Crypto and type(_G.C_Crypto.Hash) == "function" then
        local okHash, hash = pcall(_G.C_Crypto.Hash, "SHA256", exportString)
        if okHash and type(hash) == "string" and hash ~= "" then
            db.global.presetCaptures.editMode.sha256 = string.lower(hash)
        end
    end
end

function addon.DebugExportEditModeLayoutTable(layoutName)
    if not addon or not addon.db then
        addon.DebugShowWindow("Edit Mode Layout Export (Table)", "AceDB not initialized.")
        return
    end
    if not _G.C_EditMode or type(_G.C_EditMode.GetLayouts) ~= "function" then
        addon.DebugShowWindow("Edit Mode Layout Export (Table)", "C_EditMode.GetLayouts API unavailable.")
        return
    end

    local layoutInfo, err = _FindLayoutInfoByName(layoutName)
    if not layoutInfo then
        addon.DebugShowWindow("Edit Mode Layout Export (Table)", err or "Unable to resolve layout.")
        return
    end

    local snapshot = CopyTable(layoutInfo)
    local name = snapshot.layoutName or layoutName or "Active"

    local shaLine = nil
    if _G.C_EditMode and type(_G.C_EditMode.ConvertLayoutInfoToString) == "function" and _G.C_Crypto and type(_G.C_Crypto.Hash) == "function" then
        local okExport, exportString = pcall(_G.C_EditMode.ConvertLayoutInfoToString, snapshot)
        if okExport and type(exportString) == "string" and exportString ~= "" then
            local okHash, hash = pcall(_G.C_Crypto.Hash, "SHA256", exportString)
            if okHash and type(hash) == "string" and hash ~= "" then
                shaLine = "-- SHA256: " .. string.lower(hash)
            end
        end
    end

    local headerParts = {
        "-- Edit Mode layout export (raw layout table)",
        "-- Layout: " .. tostring(name),
        "-- Captured: " .. (date and date("%Y-%m-%d %H:%M:%S") or "unknown"),
    }
    if shaLine then table.insert(headerParts, shaLine) end
    table.insert(headerParts, "")
    local header = table.concat(headerParts, "\n")

    local payload = _SerializeLuaValue(snapshot, 0, {}, 0)
    addon.DebugShowWindow("Edit Mode Layout Export (Table) - " .. tostring(name), header .. payload)

    -- Persist to SavedVariables for agent ingestion (run export, then /reload or logout).
    local db = addon.db
    db.global = db.global or {}
    db.global.presetCaptures = db.global.presetCaptures or {}
    db.global.presetCaptures.editModeLayout = {
        layoutName = name,
        capturedAt = date and date("%Y-%m-%d %H:%M:%S") or nil,
        payload = payload,
    }

    if shaLine then
        db.global.presetCaptures.editModeLayout.sha256 = shaLine:gsub("^%-%- SHA256:%s*", "")
    end
end

--[[----------------------------------------------------------------------------
    ConsolePort export (SavedVariables -> copyable Lua table)

    Purpose:
      - Capture a deterministic snapshot of ConsolePort-related SavedVariables
        for ingestion into ScooterDeck preset payloads.
      - Keybindings and action loadouts are intentionally excluded since
        they are often character-specific and can be disruptive when imported.

    Usage:
      /scoot debug consoleport export
----------------------------------------------------------------------------]]--

local function _SafeCopyGlobal(name)
    local v = _G[name]
    if type(v) == "table" then
        return CopyTable(v)
    end
    if v ~= nil then
        -- Preserve non-table values, but keep the payload valid.
        return v
    end
end

function addon.DebugExportConsolePortProfile()
    if not addon or not addon.db then
        addon.DebugShowWindow("ConsolePort Export", "AceDB not initialized.")
        return
    end

    -- ConsolePort base addon must be loaded for these globals to exist.
    if not _G.ConsolePort and not _G.ConsolePortSettings then
        addon.DebugShowWindow("ConsolePort Export", "ConsolePort does not appear to be loaded on this client.")
        return
    end

    local payloadTable = {
        -- ConsolePort.toc: SavedVariables
        ConsolePortSettings = _SafeCopyGlobal("ConsolePortSettings"),
        ConsolePortDevices = _SafeCopyGlobal("ConsolePortDevices"),
        ConsolePortShared = _SafeCopyGlobal("ConsolePortShared"),
        ConsolePortBindingIcons = _SafeCopyGlobal("ConsolePortBindingIcons"),

        -- ConsolePort.toc: SavedVariablesPerCharacter (exported for completeness; may be used by rings)
        ConsolePortUtility = _SafeCopyGlobal("ConsolePortUtility"),
        ConsolePortUtilityDeprecated = _SafeCopyGlobal("ConsolePortUtilityDeprecated"),

        -- ConsolePort_Bar addon SavedVariables (if installed/loaded)
        ConsolePort_BarLayout = _SafeCopyGlobal("ConsolePort_BarLayout"),
        ConsolePort_BarPresets = _SafeCopyGlobal("ConsolePort_BarPresets"),
        -- Intentionally omitted: ConsolePort_BarLoadout (action placement / macros)
    }

    -- Trim nil keys so the output stays small and deterministic.
    for k, v in pairs(CopyTable(payloadTable)) do
        if v == nil then
            payloadTable[k] = nil
        end
    end

    local header = table.concat({
        "-- ConsolePort export (SavedVariables snapshot)",
        "-- Captured: " .. (date and date("%Y-%m-%d %H:%M:%S") or "unknown"),
        "-- Note: bindings and action loadouts are intentionally omitted.",
        "",
    }, "\n")

    local payload = _SerializeLuaValue(payloadTable, 0, {}, 0)
    addon.DebugShowWindow("ConsolePort Export", header .. payload)

    -- Persist to SavedVariables for ingestion (run export, then /reload or logout).
    local db = addon.db
    db.global = db.global or {}
    db.global.presetCaptures = db.global.presetCaptures or {}
    db.global.presetCaptures.consolePort = {
        capturedAt = date and date("%Y-%m-%d %H:%M:%S") or nil,
        payload = payload,
    }
    if _G.C_Crypto and type(_G.C_Crypto.Hash) == "function" then
        local okHash, hash = pcall(_G.C_Crypto.Hash, "SHA256", payload)
        if okHash and type(hash) == "string" and hash ~= "" then
            db.global.presetCaptures.consolePort.sha256 = string.lower(hash)
        end
    end
end

addon:RegisterDebugCommand({
    name = "profiles", help = "profile export and the reload log",
    verbs = {
        { word = "export", usage = 'export ["Profile Name"]', help = "profile as a Lua table; current profile when no name", fn = addon.DebugExportProfile },
        { word = "reload", help = "the reload debug log", fn = addon.DumpReloadDebugLog },
    },
})

local Commands = addon.Commands

-- Read-only dump of one layout's persisted anchor data, straight from
-- C_EditMode.GetLayouts(). For before/after comparison when verifying that
-- cross-machine sessions leave a layout's stored geometry untouched.
addon:RegisterDebugCommand({
    name = "layoutdump", help = "persisted Edit Mode anchors of one layout",
    usage = { 'layoutdump "Layout Name"' },
    handler = function(_, rest)
        local name = rest[1]
        if not name or name == "" then return Commands.USAGE end
        local li = _G.C_EditMode and _G.C_EditMode.GetLayouts and _G.C_EditMode.GetLayouts()
        if not (li and li.layouts) then
            addon:Print("C_EditMode.GetLayouts() returned no data.")
            return
        end
        local found
        for _, layout in ipairs(li.layouts) do
            if layout.layoutName == name then found = layout break end
        end
        if not found then
            local names = {}
            for _, layout in ipairs(li.layouts) do table.insert(names, tostring(layout.layoutName)) end
            addon:Print("Layout not found: " .. tostring(name))
            addon:Print("Available: " .. table.concat(names, ", "))
            return
        end
        local lines = {}
        table.insert(lines, string.format("Layout '%s' (layoutType=%s), %d systems",
            tostring(found.layoutName), tostring(found.layoutType), #(found.systems or {})))
        for _, sys in ipairs(found.systems or {}) do
            local a = sys.anchorInfo or {}
            table.insert(lines, string.format("system=%s index=%s default=%s | %s -> %s/%s (%.2f, %.2f)",
                tostring(sys.system), tostring(sys.systemIndex), tostring(sys.isInDefaultPosition),
                tostring(a.point), tostring(a.relativeTo), tostring(a.relativePoint),
                tonumber(a.offsetX) or 0, tonumber(a.offsetY) or 0))
        end
        addon.DebugShowWindow("Layout dump: " .. name, lines)
    end,
})

addon:RegisterDebugCommand({
    name = "consoleport", help = "ConsolePort profile export",
    verbs = {
        { word = "export", help = "copyable ConsolePort profile", fn = addon.DebugExportConsolePortProfile },
    },
})

addon:RegisterDebugCommand({
    name = "editmode", help = "Edit Mode layout export",
    verbs = {
        { word = "export", usage = 'export ["Layout Name"]', help = "raw layout table", fn = addon.DebugExportEditModeLayoutTable },
        { word = "exportstring", usage = 'exportstring ["Layout Name"]', help = "Blizzard share string", fn = addon.DebugExportEditModeLayout },
    },
})
