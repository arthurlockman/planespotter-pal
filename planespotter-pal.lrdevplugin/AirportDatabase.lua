local AirportDatabase = {}

local airports = require "airports"
local GeoUtils = require "GeoUtils"

--- Find airports nearest to a given point.
-- @param lat number Latitude
-- @param lon number Longitude  
-- @param radiusNm number Search radius in nautical miles
-- @param maxResults number Maximum results to return (default 5)
-- @return table Array of {icao, iata, name, lat, lon, country, distanceNm} sorted by distance
function AirportDatabase.findNearest(lat, lon, radiusNm, maxResults)
    maxResults = maxResults or 5
    local results = {}
    
    for _, apt in ipairs(airports) do
        local dist = GeoUtils.haversine(lat, lon, apt.lat, apt.lon)
        if dist <= radiusNm then
            results[#results + 1] = {
                icao = apt.icao,
                iata = apt.iata,
                name = apt.name,
                lat = apt.lat,
                lon = apt.lon,
                country = apt.country,
                distanceNm = dist,
            }
        end
    end
    
    table.sort(results, function(a, b) return a.distanceNm < b.distanceNm end)
    
    -- Trim to maxResults
    if #results > maxResults then
        local trimmed = {}
        for i = 1, maxResults do trimmed[i] = results[i] end
        return trimmed
    end
    
    return results
end

--- Find an airport by ICAO or IATA code.
-- @param code string ICAO (e.g., "KLAX") or IATA (e.g., "LAX") code
-- @return table {icao, iata, name, lat, lon, country} or nil
function AirportDatabase.findByCode(code)
    if not code or code == "" then return nil end
    local upper = code:upper()
    for _, apt in ipairs(airports) do
        if apt.icao == upper or apt.iata == upper then
            return {
                icao = apt.icao,
                iata = apt.iata,
                name = apt.name,
                lat = apt.lat,
                lon = apt.lon,
                country = apt.country,
                distanceNm = 0,
            }
        end
    end
    return nil
end

return AirportDatabase
