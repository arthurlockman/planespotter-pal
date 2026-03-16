--[[
    AeroDataBoxProvider.lua
    Flight data provider using AeroDataBox via RapidAPI.
    
    Endpoint: GET /flights/airports/icao/{icao}/{fromLocal}/{toLocal}
    Auth: X-RapidAPI-Key header
    Note: Uses local times (no TZ conversion needed from EXIF dateTimeOriginal).
]]

local LrHttp   = import "LrHttp"
local LrLogger = import "LrLogger"
local LrDate   = import "LrDate"

local json              = require "dkjson"
local FlightDataProvider = require "FlightDataProvider"

local logger = LrLogger("PlaneSpotterPal")

local AeroDataBoxProvider = {}

local BASE_URL = "https://aerodatabox.p.rapidapi.com/flights/airports/icao"
local HOST     = "aerodatabox.p.rapidapi.com"

function AeroDataBoxProvider.getName()
    return "AeroDataBox"
end

function AeroDataBoxProvider.validateApiKey(apiKey)
    if not apiKey or apiKey == "" then
        return false, "API key is empty"
    end
    -- Make a lightweight test call
    local url = "https://aerodatabox.p.rapidapi.com/health/services/feeds"
    local headers = {
        { field = "X-RapidAPI-Key",  value = apiKey },
        { field = "X-RapidAPI-Host", value = HOST },
    }
    local response, respHeaders = LrHttp.get(url, headers)
    if response then
        return true, nil
    else
        return false, "Could not connect to AeroDataBox API. Check your API key."
    end
end

--- Format a LrDate timestamp to ISO 8601 local time string for AeroDataBox.
local function formatLocalTime(lrTimestamp)
    return LrDate.timeToUserFormat(lrTimestamp, "%Y-%m-%dT%H:%M")
end

--- Parse a list of flights from one direction in the API response.
local function parseFlightList(flights, direction, icaoCode)
    local candidates = {}
    for _, flight in ipairs(flights) do
        local movement = flight.movement or {}
        local aircraft = flight.aircraft or {}
        local airline = flight.airline or {}

        -- Parse time from AeroDataBox {utc, local} objects or plain strings
        local function parseTime(timeObj)
            if not timeObj then return nil end
            local str = timeObj
            if type(timeObj) == "table" then
                str = timeObj["local"] or timeObj.utc
            end
            if type(str) ~= "string" then return nil end
            -- Handle "2025-03-15 12:00-07:00" or "2025-03-15T12:00"
            local y, mo, d, h, mi = str:match("(%d+)-(%d+)-(%d+)[T ](%d+):(%d+)")
            if not y then return nil end
            return LrDate.timeFromComponents(
                tonumber(y), tonumber(mo), tonumber(d),
                tonumber(h), tonumber(mi), 0, "local"
            )
        end

        -- movement.airport is the OTHER end of the flight
        local movementAirport = movement.airport or {}
        local otherCode = movementAirport.icao or movementAirport.iata

        local origin, destination
        if direction == "arrival" then
            origin      = otherCode       -- where it came from
            destination = icaoCode        -- the airport we queried
        else
            origin      = icaoCode        -- the airport we queried
            destination = otherCode       -- where it's going
        end

        local scheduledTime = parseTime(movement.scheduledTime)
        local actualTime    = parseTime(movement.runwayTime or movement.revisedTime)

        candidates[#candidates + 1] = FlightDataProvider.newCandidate({
            flightNumber  = flight.number,
            callsign      = flight.callSign,
            airline       = airline.name,
            airlineIcao   = airline.icao,
            aircraftType  = aircraft.model,
            aircraftIcao  = aircraft.icaoCode,
            registration  = aircraft.reg,
            origin        = origin,
            destination   = destination,
            scheduledTime = scheduledTime,
            actualTime    = actualTime,
            direction     = direction,
        })
    end
    return candidates
end

--- Extract rate limit info from RapidAPI response headers.
local function parseRateLimitHeaders(respHeaders)
    if not respHeaders then return nil end
    local info = {}
    for _, h in ipairs(respHeaders) do
        local name = (h.field or ""):lower()
        if name == "x-ratelimit-requests-limit" then
            info.requestsLimit = tonumber(h.value)
        elseif name == "x-ratelimit-requests-remaining" then
            info.requestsRemaining = tonumber(h.value)
        elseif name == "x-ratelimit-api-units-limit" then
            info.unitsLimit = tonumber(h.value)
        elseif name == "x-ratelimit-api-units-remaining" then
            info.unitsRemaining = tonumber(h.value)
        end
    end
    if info.requestsLimit or info.unitsLimit then return info end
    return nil
end

--- Fetch all flights (arrivals + departures) in a single API call.
function AeroDataBoxProvider.getAllFlights(icaoCode, dateTimeFrom, dateTimeTo, apiKey)
    local fromStr = formatLocalTime(dateTimeFrom)
    local toStr   = formatLocalTime(dateTimeTo)

    local url = string.format("%s/%s/%s/%s",
        BASE_URL, icaoCode, fromStr, toStr)

    local headers = {
        { field = "X-RapidAPI-Key",  value = apiKey },
        { field = "X-RapidAPI-Host", value = HOST },
    }

    local response, respHeaders = LrHttp.get(url, headers)
    if not response then
        return nil, nil, "AeroDataBox API request failed"
    end

    local rateLimitInfo = parseRateLimitHeaders(respHeaders)

    local data, _, err = json.decode(response)
    if err or not data then
        return nil, nil, "Failed to parse AeroDataBox response: " .. tostring(err)
    end

    if data.error then
        return nil, nil, "AeroDataBox error: " .. tostring(data.error)
    end

    local arrivals = parseFlightList(data.arrivals or {}, "arrival", icaoCode)
    local departures = parseFlightList(data.departures or {}, "departure", icaoCode)

    return arrivals, departures, nil, rateLimitInfo
end

-- Legacy single-direction methods (for provider interface compatibility)
function AeroDataBoxProvider.getArrivals(icaoCode, dateTimeFrom, dateTimeTo, apiKey)
    local arrivals, _, err = AeroDataBoxProvider.getAllFlights(icaoCode, dateTimeFrom, dateTimeTo, apiKey)
    return arrivals, err
end

function AeroDataBoxProvider.getDepartures(icaoCode, dateTimeFrom, dateTimeTo, apiKey)
    local _, departures, err = AeroDataBoxProvider.getAllFlights(icaoCode, dateTimeFrom, dateTimeTo, apiKey)
    return departures, err
end

return AeroDataBoxProvider
