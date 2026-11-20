-- WoWHelper: zone table, guide loading, validation and guide selection.
local _, ns = ...
local WH = ns.WH
local JSON = ns.JSON

WH.zonesByName = {}
WH.zonesById = {}

WH.ACTIONS = {
    accept = true,      -- accept a quest
    complete = true,    -- finish a quest's objectives (optionally one objective)
    turnin = true,      -- hand a quest in
    ["goto"] = true,    -- run to a location
    fly = true,         -- take a flight / boat / zeppelin
    flightpath = true,  -- discover a flight path
    sethearth = true,   -- bind the hearthstone at an innkeeper
    hearth = true,      -- use the hearthstone
    train = true,       -- visit a class trainer
    buy = true,         -- buy something from a vendor
    level = true,       -- reach a level (grind)
    note = true,        -- information the player confirms by hand
}

-- Undead's internal race token is "Scourge"; accept both spellings in guides.
local RACE_ALIASES = { undead = "scourge", forsaken = "scourge" }

local function lowerSet(list)
    if type(list) ~= "table" or #list == 0 then return nil end
    local set = {}
    for _, v in ipairs(list) do
        local k = tostring(v):lower():gsub("%s", "")
        set[RACE_ALIASES[k] or k] = true
    end
    return set
end

---------------------------------------------------------------------------
-- Zones
---------------------------------------------------------------------------
function WH:LoadZones()
    if not self.pendingZones then return end
    local data, err = JSON.decode(self.pendingZones)
    if not data then
        self:Print("Could not read zones: %s", err)
        return
    end
    for name, id in pairs(data.zones or {}) do
        self.zonesByName[name] = id
        if id then self.zonesById[id] = name end
    end
    self.pendingZones = nil
end

-- Zones added by WoW Forever have no known uiMapID yet; find them by name
-- in the client's map tree the first time they are needed.
local mapTreeScanned = false
function WH:ResolveMapId(zoneName)
    if not zoneName then return nil end
    local id = self.zonesByName[zoneName]
    if id then return id end
    if not mapTreeScanned and C_Map and C_Map.GetMapChildrenInfo then
        mapTreeScanned = true
        for _, root in ipairs({ 947, 1414, 1415 }) do
            local ok, children = pcall(C_Map.GetMapChildrenInfo, root, nil, true)
            if ok and children then
                for _, info in ipairs(children) do
                    if info.name and not self.zonesByName[info.name] then
                        self.zonesByName[info.name] = info.mapID
                        self.zonesById[info.mapID] = self.zonesById[info.mapID] or info.name
                    end
                end
            end
        end
        return self.zonesByName[zoneName]
    end
    return nil
end

function WH:GetZoneName(mapId)
    if not mapId then return nil end
    if self.zonesById[mapId] then return self.zonesById[mapId] end
    local info = C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(mapId)
    return info and info.name
end

---------------------------------------------------------------------------
-- Guides
---------------------------------------------------------------------------
function WH:ValidateGuide(g)
    if type(g) ~= "table" then return false, "guide is not an object" end
    if type(g.id) ~= "string" or g.id == "" then return false, "missing 'id'" end
    if type(g.title) ~= "string" then return false, "missing 'title'" end
    if type(g.steps) ~= "table" or #g.steps == 0 then return false, "missing 'steps'" end
    for i, s in ipairs(g.steps) do
        if type(s) ~= "table" then return false, ("step %d is not an object"):format(i) end
        if not self.ACTIONS[s.action] then
            return false, ("step %d has unknown action '%s'"):format(i, tostring(s.action))
        end
        if (s.action == "accept" or s.action == "complete" or s.action == "turnin")
            and not (s.quest or s.questId) then
            return false, ("step %d (%s) needs 'quest' or 'questId'"):format(i, s.action)
        end
        if s.action == "level" and type(s.level) ~= "number" then
            return false, ("step %d (level) needs a numeric 'level'"):format(i)
        end
    end
    return true
end

function WH:NormalizeGuide(g)
    g.raceSet = lowerSet(g.races)
    g.classSet = lowerSet(g.classes)
    g.minLevel = g.minLevel or 1
    g.maxLevel = g.maxLevel or 60
    local zone = g.zone
    for _, s in ipairs(g.steps) do
        -- A step without a zone inherits the zone of the step before it.
        if s.zone then zone = s.zone else s.zone = zone end
        if s.x and s.y then
            s.mapId = s.mapId or self:ResolveMapId(s.zone)
        end
        s.classSet = lowerSet(s.classes)
        s.raceSet = lowerSet(s.races)
    end
end

function WH:AddGuideFromJSON(json, source)
    local g, err = JSON.decode(json)
    if not g then return nil, err end
    local ok, verr = self:ValidateGuide(g)
    if not ok then return nil, verr end
    self:NormalizeGuide(g)
    g.source = source
    if not self.guides[g.id] then
        self.guideOrder[#self.guideOrder + 1] = g.id
    end
    self.guides[g.id] = g
    return g
end

function WH:LoadAllGuides()
    for _, json in ipairs(self.pendingGuides) do
        local g, err = self:AddGuideFromJSON(json, "bundled")
        if not g then self:Print("A bundled guide failed to load: %s", err) end
    end
    self.pendingGuides = {}
    for id, json in pairs(self.db.customGuides) do
        local g, err = self:AddGuideFromJSON(json, "imported")
        if not g then self:Print("Imported guide '%s' failed to load: %s", id, err) end
    end
end

-- Import from the in-game paste window. Imported guides are saved account-wide.
function WH:ImportGuide(json)
    local g, err = self:AddGuideFromJSON(json, "imported")
    if not g then return nil, err end
    self.db.customGuides[g.id] = json
    return g
end

---------------------------------------------------------------------------
-- Player matching
---------------------------------------------------------------------------
function WH:PlayerInfo()
    if not self.player then
        local _, raceFile = UnitRace("player")
        local _, classFile = UnitClass("player")
        self.player = {
            race = (raceFile or ""):lower(),
            class = (classFile or ""):lower(),
            faction = (UnitFactionGroup("player") or ""):lower(),
        }
    end
    return self.player
end

local function matches(set, value)
    return set == nil or set[value] == true
end

function WH:GuideApplies(g)
    local p = self:PlayerInfo()
    if g.faction and g.faction:lower() ~= p.faction then return false end
    return matches(g.raceSet, p.race) and matches(g.classSet, p.class)
end

function WH:StepApplies(s)
    local p = self:PlayerInfo()
    return matches(s.classSet, p.class) and matches(s.raceSet, p.race)
end

function WH:GetGuidesForPlayer(all)
    local list = {}
    for _, id in ipairs(self.guideOrder) do
        local g = self.guides[id]
        if all or self:GuideApplies(g) then list[#list + 1] = g end
    end
    table.sort(list, function(a, b)
        if a.minLevel ~= b.minLevel then return a.minLevel < b.minLevel end
        return a.id < b.id
    end)
    return list
end

-- First login with WoWHelper: pick the guide for the character's level and
-- skip the steps it has already done.
function WH:SelectInitialGuide()
    if self.char.guideId and self.guides[self.char.guideId] then return end
    local pick = self:GuideForLevel()
    if pick then self:StartGuide(pick) end
end

function WH:SetGuide(id)
    local g = self.guides[id]
    if not g then return end
    self:StartGuide(g)
    self:Refresh(true)
    self:Print("Guide: %s", g.title)
end
