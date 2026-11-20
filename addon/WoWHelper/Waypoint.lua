-- WoWHelper: waypoints (TomTom if installed, otherwise the built-in map pin)
-- and the /wh where helper used to write or correct guide steps.
local _, ns = ...
local WH = ns.WH

local function stepLabel(s)
    return s.npc or s.quest or s.text or s.location or "WoWHelper"
end

function WH:ClearWaypoint()
    if self.tomtomUid and TomTom and TomTom.RemoveWaypoint then
        pcall(TomTom.RemoveWaypoint, TomTom, self.tomtomUid)
    end
    self.tomtomUid = nil
end

function WH:SetWaypointForStep(s, verbose)
    if not s then return end
    if not verbose and not self.db.autoWaypoint then return end
    if not (s.mapId and s.x and s.y) then
        if verbose then self:Print("This step has no coordinates.") end
        return
    end
    local x, y = s.x / 100, s.y / 100
    self:ClearWaypoint()

    if TomTom and TomTom.AddWaypoint then
        local ok, uid = pcall(TomTom.AddWaypoint, TomTom, s.mapId, x, y,
            { title = stepLabel(s), persistent = false, minimap = true, world = true, from = "WoWHelper" })
        if ok then
            self.tomtomUid = uid
            return
        end
    end

    if C_Map.SetUserWaypoint and UiMapPoint and UiMapPoint.CreateFromCoordinates then
        local ok = pcall(function()
            if C_Map.CanSetUserWaypointOnMap and not C_Map.CanSetUserWaypointOnMap(s.mapId) then
                error("map does not accept waypoints")
            end
            C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(s.mapId, x, y))
            if self.db.superTrack and C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then
                C_SuperTrack.SetSuperTrackedUserWaypoint(true)
            end
        end)
        if not ok and verbose then self:Print("Could not place a map pin on this map.") end
    end
end

-- Prints the player's location (and target) as a ready-to-paste JSON step.
-- Usage: /wh where [action] [quest name]
function WH:PrintWhere(args)
    local map, x, y = self:GetPlayerPosition()
    if not x then
        self:Print("Your position is not available here (instances hide it).")
        return
    end
    local action, quest = (args or ""):match("^(%S*)%s*(.-)$")
    if not action or action == "" then action = "goto" end
    local zone = self:GetZoneName(map) or tostring(map)
    local parts = {
        ('"action": "%s"'):format(action),
    }
    if quest and quest ~= "" then parts[#parts + 1] = ('"quest": "%s"'):format(quest) end
    local npc = UnitExists("target") and not UnitIsPlayer("target") and UnitName("target")
    if npc then parts[#parts + 1] = ('"npc": "%s"'):format(npc) end
    parts[#parts + 1] = ('"zone": "%s"'):format(zone)
    parts[#parts + 1] = ('"x": %.2f, "y": %.2f'):format(x, y)
    self:Print("mapID %d (%s) %.2f, %.2f", map, zone, x, y)
    DEFAULT_CHAT_FRAME:AddMessage("{ " .. table.concat(parts, ", ") .. " }")
end
