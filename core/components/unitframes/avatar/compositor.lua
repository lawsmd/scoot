-- compositor.lua - turns resolved settings into an ordered layer list, then
-- renders that list onto a host frame with a reused texture pool. The editor
-- preview and the live frame both call BuildLayerList + Render, so they match.
local addonName, addon = ...

addon.Avatar = addon.Avatar or {}
local A = addon.Avatar
local FS = addon.FrameState

-- settings = {
--   race, sex, class,          -- resolved identity (plain strings/Male|Female)
--   resolution,                -- canonical asset size (48); no longer user-selectable
--   slots = { [slot] = { key = "string", color = {r,g,b,a} } },  -- user overrides
-- }
-- Returns an ordered array of { path, layer, sub, color } back to front, or nil.
function A.BuildLayerList(settings)
    local man = A.GetManifest()
    if not man or not settings then return nil end
    local race = settings.race
    local rdata = A.GetRaceData(race)
    if not rdata then return nil end

    local res = settings.resolution or 48
    local defaults = (rdata.defaultsBySex and rdata.defaultsBySex[settings.sex]) or {}
    local overrides = settings.slots or {}
    local classTint = (man.classTint and settings.class) and man.classTint[settings.class] or nil

    local list = {}
    for _, slot in ipairs(man.slots) do
        local ov = overrides[slot]
        local key = (ov and ov.key) or defaults[slot]
        if key and key ~= "none" then
            local v = A.GetVariant(race, slot, key)
            if v then
                local sl = man.slotLayer[slot] or { layer = "ARTWORK", sub = 0 }
                local color
                if v.tintable then
                    if ov and ov.color then
                        color = ov.color
                    elseif classTint and classTint[slot] and man.palettes and v.ramp and man.palettes[v.ramp] then
                        color = man.palettes[v.ramp][classTint[slot]]
                    elseif v.defaultColor then
                        color = v.defaultColor
                    end
                end
                list[#list + 1] = {
                    path = A.BuildPath(res, race, slot, key),
                    layer = sl.layer,
                    sub = sl.sub,
                    color = color,
                }
            end
        end
    end
    return list
end

-- Render a layer list onto host using a pooled set of textures stored in
-- FrameState. Unused textures are hidden, never destroyed.
function A.Render(host, list)
    if not host then return end
    local st = FS.Get(host)
    local pool = st.avatarPool
    if not pool then
        pool = {}
        st.avatarPool = pool
    end

    for i = 1, #pool do
        pool[i]:Hide()
    end

    if not list then return end

    for i = 1, #list do
        local layer = list[i]
        local tex = pool[i]
        if not tex then
            tex = host:CreateTexture(nil, "ARTWORK")
            tex:SetTexelSnappingBias(0)
            tex:SetSnapToPixelGrid(false)
            pool[i] = tex
        end
        tex:SetDrawLayer(layer.layer or "ARTWORK", layer.sub or 0)
        tex:SetTexture(layer.path)
        tex:SetAllPoints(host)
        local c = layer.color
        if c then
            tex:SetVertexColor(c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1)
        else
            tex:SetVertexColor(1, 1, 1, 1)
        end
        tex:Show()
    end
end

-- Convenience for the editor: build + render in one call against any host.
function A.RenderSettings(host, settings)
    A.Render(host, A.BuildLayerList(settings))
end
