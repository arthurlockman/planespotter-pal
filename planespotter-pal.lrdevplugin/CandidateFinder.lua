--[[
    CandidateFinder.lua
    Orchestrates the aircraft identification workflow:
    1. Extract photo EXIF data
    2. Find nearest airports
    3. Query the active flight data provider
    4. Rank and filter candidates
]]

local LrDate   = import "LrDate"
local LrLogger = import "LrLogger"
local LrTasks  = import "LrTasks"

local logger = LrLogger("PlaneSpotterPal")

local CandidateFinder = {}

-- Provider module names keyed by preference value
local PROVIDER_MODULES = {
    AeroDataBox    = "AeroDataBoxProvider",
    FlightAware    = "FlightAwareProvider",
    FlightRadar24  = "FR24Provider",
}

--- Load the active provider module based on preferences.
-- @return provider module, apiKey string, or nil + error string
local function loadProvider()
    local Preferences = require "Preferences"
    local prefs = Preferences.getPrefs()
    local name = prefs.activeProvider

    local moduleName = PROVIDER_MODULES[name]
    if not moduleName then
        return nil, nil, "Unknown provider: " .. tostring(name)
    end

    local ok, provider = LrTasks.pcall(require, moduleName)
    if not ok then
        return nil, nil, "Failed to load provider: " .. tostring(provider)
    end

    local apiKey = Preferences.getActiveApiKey()
    if not apiKey or apiKey == "" then
        return nil, nil, "No API key configured for " .. name
    end

    return provider, apiKey, nil
end

--- Find candidate flights for a photo.
-- @param photoData table {lat, lon, dateTime, heading (optional), focalLength (optional)}
-- @return candidates table (array of CandidateFlight), or nil + error string
function CandidateFinder.findCandidates(photoData)
    local AirportDatabase = require "AirportDatabase"
    local Preferences     = require "Preferences"

    local prefs = Preferences.getPrefs()
    local radiusNm    = prefs.searchRadiusNm or 5
    local timeWindow  = (prefs.timeWindowMinutes or 5) * 60 -- convert to seconds

    -- Step 1: Find nearest airports
    local airports = AirportDatabase.findNearest(
        photoData.lat, photoData.lon, radiusNm, 3
    )

    if #airports == 0 then
        return nil, string.format(
            "No airports found within %d nm of photo location (%.4f, %.4f).",
            radiusNm, photoData.lat, photoData.lon
        )
    end

    logger:info(string.format("Found %d airport(s) near photo location", #airports))

    -- Step 2: Get active provider
    local provider, apiKey, provErr = loadProvider()
    if not provider then
        return nil, "Provider error: " .. tostring(provErr)
    end

    -- Step 3: Query arrivals & departures for each airport
    local dateTimeFrom = photoData.dateTime - timeWindow
    local dateTimeTo   = photoData.dateTime + timeWindow

    local allCandidates = {}
    local seen = {} -- deduplicate by flightNumber + direction
    local lastRateLimitInfo = nil

    for _, airport in ipairs(airports) do
        logger:info("Querying " .. provider.getName() .. " for " .. airport.icao)

        -- Prefer getAllFlights (single API call) if provider supports it
        if provider.getAllFlights then
            local arrivals, departures, err, rateLimitInfo = provider.getAllFlights(
                airport.icao, dateTimeFrom, dateTimeTo, apiKey
            )
            if rateLimitInfo then
                lastRateLimitInfo = rateLimitInfo
            end
            if err then
                logger:warn("Flights error for " .. airport.icao .. ": " .. err)
            else
                for _, c in ipairs(arrivals or {}) do
                    local key = (c.flightNumber or "") .. "_" .. c.direction
                    if not seen[key] then
                        seen[key] = true
                        allCandidates[#allCandidates + 1] = c
                    end
                end
                for _, c in ipairs(departures or {}) do
                    local key = (c.flightNumber or "") .. "_" .. c.direction
                    if not seen[key] then
                        seen[key] = true
                        allCandidates[#allCandidates + 1] = c
                    end
                end
            end
        else
            -- Fallback: separate calls for providers without getAllFlights
            local arrivals, arrErr = provider.getArrivals(
                airport.icao, dateTimeFrom, dateTimeTo, apiKey
            )
            if arrivals then
                for _, c in ipairs(arrivals) do
                    local key = (c.flightNumber or "") .. "_" .. c.direction
                    if not seen[key] then
                        seen[key] = true
                        allCandidates[#allCandidates + 1] = c
                    end
                end
            elseif arrErr then
                logger:warn("Arrivals error for " .. airport.icao .. ": " .. arrErr)
            end

            local departures, depErr = provider.getDepartures(
                airport.icao, dateTimeFrom, dateTimeTo, apiKey
            )
            if departures then
                for _, c in ipairs(departures) do
                    local key = (c.flightNumber or "") .. "_" .. c.direction
                    if not seen[key] then
                        seen[key] = true
                        allCandidates[#allCandidates + 1] = c
                    end
                end
            elseif depErr then
                logger:warn("Departures error for " .. airport.icao .. ": " .. depErr)
            end
        end
    end

    if #allCandidates == 0 then
        return nil, "No flights found at nearby airports in the time window."
    end

    -- Step 4: Rank candidates
    CandidateFinder._rankCandidates(allCandidates, photoData)

    -- Build search context for the dialog
    local airportNames = {}
    for _, apt in ipairs(airports) do
        airportNames[#airportNames + 1] = string.format("%s (%s)", apt.name, apt.icao)
    end

    local searchContext = {
        airports      = airportNames,
        photoTime     = photoData.dateTime,
        timeWindowMin = prefs.timeWindowMinutes or 5,
        radiusNm      = radiusNm,
        providerName  = provider.getName(),
        lat           = photoData.lat,
        lon           = photoData.lon,
        rateLimit     = lastRateLimitInfo,
    }

    logger:info(string.format("Found %d candidate flight(s)", #allCandidates))
    return allCandidates, nil, searchContext
end

--- Rank candidates by time proximity and optional bearing match.
function CandidateFinder._rankCandidates(candidates, photoData)
    local GeoUtils = require "GeoUtils"
    local photoTime = photoData.dateTime
    local heading = photoData.heading
    local fov = nil

    if photoData.focalLength then
        fov = GeoUtils.estimateFOV(photoData.focalLength)
    end

    -- Compute scores
    for _, c in ipairs(candidates) do
        local refTime = c.actualTime or c.scheduledTime
        if refTime then
            c._timeDelta = math.abs(refTime - photoTime)
        else
            c._timeDelta = 9999999
        end

        c._bearingScore = 0
    end

    -- Sort by time proximity (closest first)
    table.sort(candidates, function(a, b)
        return a._timeDelta < b._timeDelta
    end)
end

return CandidateFinder
