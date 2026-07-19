-- AvatarLabSection.lua - DEV-ONLY editor for the pixel-art avatar prototype.
-- This was moved out of the player unit-frame menu; it is now surfaced only under
-- the hidden Debug section (Debug > Avatar Lab) so it can be iterated in-game
-- without exposing it in the shipped product. This file and the whole avatar
-- infrastructure are stripped from CurseForge releases by export-curseforge.ps1.
--
-- Drives the live player-frame avatar and an in-panel preview through the same
-- compositor (addon.Avatar).
local addonName, addon = ...

addon.UI = addon.UI or {}
addon.UI.UnitFrames = addon.UI.UnitFrames or {}
local UF = addon.UI.UnitFrames

-- Slot groups shown as tabs. tintable marks slots that get a color picker.
local SLOT_GROUPS = {
    { key = "head", label = "Head", slots = {
        { slot = "head", label = "Face", tintable = true },
        { slot = "ears", label = "Ears", tintable = true },
        { slot = "tusks", label = "Tusks", tintable = false },
    } },
    { key = "hairface", label = "Hair & Face", slots = {
        { slot = "hair", label = "Hair", tintable = true },
        { slot = "facialHair", label = "Facial Hair", tintable = true },
    } },
    { key = "eyes", label = "Eyes", slots = {
        { slot = "eyes", label = "Eyes", tintable = false },
    } },
    { key = "jewelry", label = "Jewelry", slots = {
        { slot = "jewelry", label = "Jewelry", tintable = false },
    } },
}

function UF.buildAvatarSection(builder, componentId, unitKey)
    local A = addon.Avatar
    if not A or not A.GetManifest or not A.GetManifest() then return end
    unitKey = unitKey or "Player"

    local function ensureAvatar()
        local t = UF.ensureUFDB(unitKey)
        if not t then return nil end
        t.avatar = t.avatar or {}
        t.avatar.slots = t.avatar.slots or {}
        return t.avatar
    end
    local function getAvatar()
        local t = UF.getUFDB(unitKey)
        return t and rawget(t, "avatar") or nil
    end
    local function identitySex()
        local id = A.GetIdentity()
        return (id and id.sex) or "Male"
    end
    local function defaultKeyFor(rdata, slot)
        local def = rdata.defaultsBySex and rdata.defaultsBySex[identitySex()]
        return def and def[slot] or "none"
    end

    local previewFrame

    local function refresh()
        if addon.ApplyUnitFrameAvatarFor then
            addon.ApplyUnitFrameAvatarFor("Player")
        end
        if previewFrame and previewFrame.Render then
            previewFrame.Render(A.GetPlayerSettings())
        end
    end

    -- One variant selector (+ optional color) for a slot.
    local function addSlotControls(tabInner, race, rdata, def)
        local variants = rdata.variants and rdata.variants[def.slot]
        if not variants then return end

        local values, order = {}, {}
        for _, v in ipairs(variants) do
            values[v.key] = v.label or v.key
            order[#order + 1] = v.key
        end

        tabInner:AddSelector({
            label = def.label,
            values = values,
            order = order,
            get = function()
                local av = getAvatar()
                local s = av and av.slots and av.slots[def.slot]
                if s and s.key then return s.key end
                return defaultKeyFor(rdata, def.slot)
            end,
            set = function(v)
                local av = ensureAvatar()
                if not av then return end
                av.slots[def.slot] = av.slots[def.slot] or {}
                av.slots[def.slot].key = v
                refresh()
            end,
        })

        if def.tintable then
            tabInner:AddColorPicker({
                label = def.label .. " Color",
                hasAlpha = false,
                get = function()
                    local av = getAvatar()
                    local s = av and av.slots and av.slots[def.slot]
                    local c = s and s.color
                    if not c then
                        local key = (s and s.key) or defaultKeyFor(rdata, def.slot)
                        local vmeta = key and A.GetVariant(race, def.slot, key)
                        c = vmeta and vmeta.defaultColor
                    end
                    c = c or { 1, 1, 1, 1 }
                    return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1
                end,
                set = function(r, g, b)
                    local av = ensureAvatar()
                    if not av then return end
                    av.slots[def.slot] = av.slots[def.slot] or {}
                    av.slots[def.slot].color = { r, g, b, 1 }
                    refresh()
                end,
            })
        end
    end

    -- Helmet drives two slots (back + front) plus a shared tint.
    local function addHelmetControls(tabInner, race, rdata)
        local helmets = rdata.helmets
        if not helmets then return end
        local values, order, byKey = {}, {}, {}
        for _, h in ipairs(helmets) do
            values[h.key] = h.label or h.key
            order[#order + 1] = h.key
            byKey[h.key] = h
        end

        tabInner:AddSelector({
            label = "Helmet",
            values = values,
            order = order,
            get = function()
                local av = getAvatar()
                return (av and av._helmetKey) or "none"
            end,
            set = function(v)
                local av = ensureAvatar()
                if not av then return end
                local h = byKey[v]
                av._helmetKey = v
                local color = av._helmetColor
                av.slots.helmetBack = { key = (h and h.back) or "none", color = color }
                av.slots.helmetFront = { key = (h and h.front) or "none", color = color }
                refresh()
            end,
        })

        tabInner:AddColorPicker({
            label = "Helmet Color",
            hasAlpha = false,
            get = function()
                local av = getAvatar()
                local c = av and av._helmetColor
                if not c then
                    local h = av and av._helmetKey and byKey[av._helmetKey]
                    c = h and h.defaultColor
                end
                c = c or { 0.66, 0.69, 0.74, 1 }
                return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1
            end,
            set = function(r, g, b)
                local av = ensureAvatar()
                if not av then return end
                local color = { r, g, b, 1 }
                av._helmetColor = color
                if av.slots.helmetBack then av.slots.helmetBack.color = color end
                if av.slots.helmetFront then av.slots.helmetFront.color = color end
                refresh()
            end,
        })
    end

    builder:AddCollapsibleSection({
        title = "Avatar",
        componentId = componentId,
        sectionKey = "avatar",
        defaultExpanded = true,
        buildContent = function(contentFrame, inner)
            inner:AddToggle({
                label = "Enable Pixel Avatar",
                description = "Show a pixel-art head beside the portrait. Auto-matches race and sex; customize freely below.",
                emphasized = true,
                get = function()
                    local av = getAvatar()
                    return not not (av and av.enabled)
                end,
                set = function(v)
                    local av = ensureAvatar()
                    if not av then return end
                    av.enabled = v and true or false
                    refresh()
                end,
            })

            -- Oversized on purpose: this is a debug harness, not shippable UI. The
            -- source PNGs are block-baked at 480 px (the generator nearest-neighbor
            -- expands each of the 96 logical pixels into a hard 5 px block, since
            -- WoW has no nearest filter), so the host is sized to 480 for a 1:1,
            -- crisp render with no bilinear filtering.
            inner:AddAvatarPreview({
                height = 500,
                hostSize = 480,
                onCreate = function(f) previewFrame = f end,
            })

            inner:AddSelector({
                label = "Side",
                values = { left = "Left of Portrait", right = "Right of Portrait", over = "Over Portrait" },
                order = { "left", "right", "over" },
                get = function()
                    local av = getAvatar()
                    return (av and av.side) or "left"
                end,
                set = function(v)
                    local av = ensureAvatar()
                    if not av then return end
                    av.side = v
                    refresh()
                end,
            })

            inner:AddSlider({
                label = "Gap",
                min = -20, max = 60, step = 1,
                get = function()
                    local av = getAvatar()
                    return tonumber(av and av.gap) or 2
                end,
                set = function(v)
                    local av = ensureAvatar()
                    if not av then return end
                    av.gap = tonumber(v) or 2
                    refresh()
                end,
            })

            inner:AddSlider({
                label = "Size (Scale)",
                min = 50, max = 200, step = 5,
                get = function()
                    local av = getAvatar()
                    return tonumber(av and av.scalePct) or 100
                end,
                set = function(v)
                    local av = ensureAvatar()
                    if not av then return end
                    av.scalePct = tonumber(v) or 100
                    refresh()
                end,
                minLabel = "50%",
                maxLabel = "200%",
            })

            inner:AddDualSlider({
                label = "Offset",
                sliderA = {
                    axisLabel = "X",
                    min = -60, max = 60, step = 1,
                    get = function() local av = getAvatar(); return tonumber(av and av.offsetX) or 0 end,
                    set = function(v)
                        local av = ensureAvatar()
                        if not av then return end
                        av.offsetX = tonumber(v) or 0
                        refresh()
                    end,
                },
                sliderB = {
                    axisLabel = "Y",
                    min = -60, max = 60, step = 1,
                    get = function() local av = getAvatar(); return tonumber(av and av.offsetY) or 0 end,
                    set = function(v)
                        local av = ensureAvatar()
                        if not av then return end
                        av.offsetY = tonumber(v) or 0
                        refresh()
                    end,
                },
            })

            -- Per-slot customization, filtered to the resolved race.
            local id = A.GetIdentity()
            local race = id and id.race
            local rdata = race and A.GetRaceData(race)
            if rdata then
                local tabs = {}
                for _, grp in ipairs(SLOT_GROUPS) do
                    tabs[#tabs + 1] = { key = grp.key, label = grp.label }
                end
                tabs[#tabs + 1] = { key = "helmet", label = "Helmet" }

                local buildContent = {}
                for _, grp in ipairs(SLOT_GROUPS) do
                    buildContent[grp.key] = function(cf, tabInner)
                        for _, def in ipairs(grp.slots) do
                            addSlotControls(tabInner, race, rdata, def)
                        end
                        tabInner:Finalize()
                    end
                end
                buildContent.helmet = function(cf, tabInner)
                    addHelmetControls(tabInner, race, rdata)
                    tabInner:Finalize()
                end

                inner:AddTabbedSection({
                    tabs = tabs,
                    componentId = componentId,
                    sectionKey = "avatar_tabs",
                    buildContent = buildContent,
                })
            end

            -- Render the initial preview.
            if previewFrame and previewFrame.Render then
                previewFrame.Render(A.GetPlayerSettings())
            end

            inner:Finalize()
        end,
    })
end
