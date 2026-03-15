--[[
    GeoUtils.lua
    Geographic utility functions for PlaneSpotter Pal.
]]

local GeoUtils = {}

local EARTH_RADIUS_NM = 3440.065 -- nautical miles
local RAD = math.pi / 180
local DEG = 180 / math.pi

--- Haversine distance between two lat/lon points.
-- @return distance in nautical miles
function GeoUtils.haversine(lat1, lon1, lat2, lon2)
    local dLat = (lat2 - lat1) * RAD
    local dLon = (lon2 - lon1) * RAD
    local a = math.sin(dLat / 2) ^ 2
            + math.cos(lat1 * RAD) * math.cos(lat2 * RAD)
            * math.sin(dLon / 2) ^ 2
    local c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))
    return EARTH_RADIUS_NM * c
end

--- Compute a bounding box around a point.
-- @return table {latMin, latMax, lonMin, lonMax}
function GeoUtils.boundingBox(lat, lon, radiusNm)
    local dLat = (radiusNm / EARTH_RADIUS_NM) * DEG
    local dLon = dLat / math.cos(lat * RAD)
    return {
        latMin = lat - dLat,
        latMax = lat + dLat,
        lonMin = lon - dLon,
        lonMax = lon + dLon,
    }
end

--- Initial bearing from point 1 to point 2.
-- @return bearing in degrees (0-360)
function GeoUtils.bearing(lat1, lon1, lat2, lon2)
    local dLon = (lon2 - lon1) * RAD
    local y = math.sin(dLon) * math.cos(lat2 * RAD)
    local x = math.cos(lat1 * RAD) * math.sin(lat2 * RAD)
          - math.sin(lat1 * RAD) * math.cos(lat2 * RAD) * math.cos(dLon)
    local brng = math.atan2(y, x) * DEG
    return (brng + 360) % 360
end

--- Check if a target point falls within the camera's field of view.
-- @param cameraLat, cameraLon  Camera position
-- @param cameraHeading         Camera compass heading in degrees
-- @param fovDeg                Total field of view in degrees
-- @param targetLat, targetLon  Target position
-- @return boolean
function GeoUtils.isInFOV(cameraLat, cameraLon, cameraHeading, fovDeg, targetLat, targetLon)
    local targetBearing = GeoUtils.bearing(cameraLat, cameraLon, targetLat, targetLon)
    local diff = math.abs(targetBearing - cameraHeading)
    if diff > 180 then diff = 360 - diff end
    return diff <= (fovDeg / 2)
end

--- Estimate horizontal field of view from focal length (35mm equivalent).
-- Assumes a standard 36mm sensor width.
-- @param focalLength35mm  Focal length in mm (35mm equivalent)
-- @return FOV in degrees
function GeoUtils.estimateFOV(focalLength35mm)
    if not focalLength35mm or focalLength35mm <= 0 then
        return nil
    end
    return 2 * math.atan(36 / (2 * focalLength35mm)) * DEG
end

return GeoUtils
