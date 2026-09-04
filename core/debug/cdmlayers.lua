-- cdmlayers.lua — Diagnostic dump of CDM icon frame levels and Scoot overlay layers.
-- Usage: /scoot debug cdmlayers
local addonName, addon = ...

local CDM_VIEWERS = addon.CDM_VIEWERS

local function safeGetLevel(frame)
    local ok, level = pcall(function() return frame:GetFrameLevel() end)
    return ok and type(level) == "number" and level or "?"
end

local function safeGetStrata(frame)
    local ok, strata = pcall(function() return frame:GetFrameStrata() end)
    return ok and type(strata) == "string" and strata or "?"
end

local function frameName(frame)
    local ok, name = pcall(function() return frame:GetName() end)
    return ok and name or nil
end

local function DebugCDMLayers()
    local Overlays = addon.CDMOverlays
    local PG = addon.PixelGlow
    local activeOverlays = Overlays and Overlays._activeOverlays
    local lines = {}

    for viewerName, _ in pairs(CDM_VIEWERS) do
        local viewer = _G[viewerName]
        if viewer and viewer.GetChildren then
            table.insert(lines, string.format("CDM Icon Layers — %s", viewerName))
            table.insert(lines, string.rep("=", 60))

            local children = { viewer:GetChildren() }
            local iconCount = 0
            for _, child in ipairs(children) do
                if child and child.Icon then
                    iconCount = iconCount + 1
                    local shown = child.IsShown and child:IsShown()
                    local childName = frameName(child) or tostring(child):gsub("table: ", "")
                    local iconLevel = safeGetLevel(child)
                    local iconStrata = safeGetStrata(child)

                    table.insert(lines, string.format("\nIcon: %s  %s", childName, shown and "" or "(hidden)"))
                    table.insert(lines, string.format("  Strata: %s  Level: %s", iconStrata, tostring(iconLevel)))

                    -- Blizzard children
                    table.insert(lines, "  Children:")
                    local blizChildren = { child:GetChildren() }
                    for _, bc in ipairs(blizChildren) do
                        local bcName = frameName(bc)
                        -- Skip Scoot overlay/borderFrame (they have overlay.borderFrame ref)
                        local isScoot = false
                        if activeOverlays then
                            local ov = activeOverlays[child]
                            if ov and (bc == ov or bc == ov.borderFrame) then
                                isScoot = true
                            end
                        end
                        if not isScoot then
                            local bcLevel = safeGetLevel(bc)
                            local bcStrata = safeGetStrata(bc)
                            local label = bcName or tostring(bc):gsub("table: ", "")
                            -- Strip parent prefix for readability
                            if bcName and childName then
                                label = bcName:gsub("^" .. childName:gsub("([%.%-%+%*%?%[%]%^%$%(%)%%])", "%%%1") .. "%.", "")
                            end
                            local raised = ""
                            if type(iconLevel) == "number" and type(bcLevel) == "number" and bcLevel > iconLevel + 2 then
                                raised = "  (raised)"
                            end
                            table.insert(lines, string.format("    %-20s Strata: %-8s Level: %s%s", label, bcStrata, tostring(bcLevel), raised))
                        end
                    end

                    -- Scoot layers
                    if activeOverlays then
                        local overlay = activeOverlays[child]
                        if overlay then
                            table.insert(lines, "  Scoot:")
                            if overlay.borderFrame then
                                table.insert(lines, string.format("    %-20s Strata: %-8s Level: %s",
                                    "borderFrame", safeGetStrata(overlay.borderFrame), tostring(safeGetLevel(overlay.borderFrame))))
                            end
                            table.insert(lines, string.format("    %-20s Strata: %-8s Level: %s",
                                "overlay", safeGetStrata(overlay), tostring(safeGetLevel(overlay))))
                            -- Pixel glow
                            if PG and PG.GetForIcon then
                                local glowCtrl = PG.GetForIcon(child)
                                if glowCtrl and glowCtrl.frame then
                                    local playing = glowCtrl.playing and "(playing)" or "(stopped)"
                                    table.insert(lines, string.format("    %-20s Strata: %-8s Level: %s  %s",
                                        "pixelGlow", safeGetStrata(glowCtrl.frame), tostring(safeGetLevel(glowCtrl.frame)), playing))
                                end
                            end
                        else
                            table.insert(lines, "  Scoot: (no overlay)")
                        end
                    else
                        table.insert(lines, "  Scoot: (overlays not initialized)")
                    end
                end
            end

            if iconCount == 0 then
                table.insert(lines, "  (no icons found)")
            end
            table.insert(lines, "")
        end
    end

    if #lines == 0 then
        table.insert(lines, "No CDM viewers found. Are cooldowns enabled in Blizzard settings?")
    end

    if addon.DebugShowWindow then
        addon.DebugShowWindow("CDM Icon Layer Diagnostic", lines)
    end
end

addon:RegisterDebugCommand({
    name = "cdmlayers", help = "CDM icon frame levels and overlay layers",
    handler = function() DebugCDMLayers() end,
})
