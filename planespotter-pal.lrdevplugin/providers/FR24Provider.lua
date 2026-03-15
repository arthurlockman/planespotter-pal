--[[
    FR24Provider.lua
    Flight data provider using FlightRadar24 API.
    
    Endpoint: GET /flight-summary/full
    Auth: Authorization: Bearer {token}
    Note: Uses UTC timestamps. Data available from June 2022 onward.
]]

local LrHttp   = import "LrHttp"
local LrLogger = import "LrLogger"
local LrDate   = import "LrDate"

local json              = require "dkjson"
local FlightDataProvider = require "providers.FlightDataProvider"

local logger = LrLogger("PlaneSpotterPal")

local FR24Provider = {}

local BASE_URL = "https://fr24api.flightradar24.com/api"

function FR24Provider.getName()
    return "FlightRadar24"
end

function FR24Provider.validateApiKey(apiKey)
    if not apiKey or apiKey == "" then
        return false, "API key is empty"
    end
    local url = BASE_URL .. "/usage"
    local headers = {
        { field = "Authorization", value = "Bearer " .. apiKey },
        { field = "Accept",        value = "application/json" },
    }
    local response, respHeaders = LrHttp.get(url, headers)
    if response then
        local data = json.decode(response)
        if data and not data.error then
            return true, nil
        end
    end
    return false, "Could not connect to FlightRadar24 API. Check your API key and subscription."
end

--- Format a LrDate timestamp to FR24 date-time format (UTC).
local function formatUTC(lrTimestamp)
    return LrDate.timeToUserFormat(lrTimestamp, "%Y-%m-%dT%H:%M:%S")
end

--- Parse FR24 timestamp.
local function parseTimestamp(tsStr)
    if not tsStr then return nil end
    local y, m, d, h, min, s = tsStr:match("(%d+)-(%d+)-(%d+)T(%d+):(%d+):(%d+)")
    if not y then
        -- Try Unix timestamp
        local num = tonumber(tsStr)
        if num then return num end
        return nil
    end
    return LrDate.timeFromComponents(
        tonumber(y), tonumber(m), tonumber(d),
        tonumber(h), tonumber(min), tonumber(s), "local"
    )
end

--- Fetch flights from FR24 Flight Summary endpoint.
local function fetchFlights(icaoCode, dateTimeFrom, dateTimeTo, apiKey, direction)
    local fromStr = formatUTC(dateTimeFrom)
    local toStr   = formatUTC(dateTimeTo)

    -- FR24 uses "inbound" for arrivals, "outbound" for departures, "both" for either
    local airportFilter
    if direction == "arrival" then
        airportFilter = "inbound:" .. icaoCode
    else
        airportFilter = "outbound:" .. icaoCode
    end

    local url = string.format(
        "%s/flight-summary/full?airports=%s&flight_datetime_from=%s&flight_datetime_to=%s&limit=100",
        BASE_URL, airportFilter, fromStr, toStr
    )

    local headers = {
        { field = "Authorization", value = "Bearer " .. apiKey },
        { field = "Accept",        value = "application/json" },
    }

    local response, respHeaders = LrHttp.get(url, headers)
    if not response then
        return nil, "FlightRadar24 API request failed"
    end

    local data, _, err = json.decode(response)
    if err or not data then
        return nil, "Failed to parse FR24 response: " .. tostring(err)
    end

    if data.error then
        return nil, "FR24 error: " .. tostring(data.error)
    end

    local candidates = {}
    local flights = data.data or data.results or data or {}

    -- Handle case where response is the array directly
    if flights[1] == nil and data[1] ~= nil then
        flights = data
    end

    for _, flight in ipairs(flights) do
        local dep = flight.departure or flight.origin or {}
        local arr = flight.arrival or flight.destination or {}
        local aircraft = flight.aircraft or {}
        local airline = flight.airline or flight.operator or {}

        candidates[#candidates + 1] = FlightDataProvider.newCandidate({
            flightNumber  = flight.flight_number or flight.flight,
            callsign      = flight.callsign,
            airline       = airline.name or airline.short,
            airlineIcao   = airline.icao or airline.code,
            aircraftType  = aircraft.model or aircraft.text,
            aircraftIcao  = aircraft.code or aircraft.icao,
            registration  = aircraft.registration or aircraft.reg,
            origin        = dep.airport_icao or dep.icao or dep.code,
            destination   = arr.airport_icao or arr.icao or arr.code,
            scheduledTime = parseTimestamp(flight.scheduled_departure or flight.scheduled_arrival),
            actualTime    = parseTimestamp(flight.actual_departure or flight.actual_arrival
                            or flight.first_seen or flight.last_seen),
            direction     = direction,
        })
    end

    return candidates, nil
end

function FR24Provider.getArrivals(icaoCode, dateTimeFrom, dateTimeTo, apiKey)
    return fetchFlights(icaoCode, dateTimeFrom, dateTimeTo, apiKey, "arrival")
end

function FR24Provider.getDepartures(icaoCode, dateTimeFrom, dateTimeTo, apiKey)
    return fetchFlights(icaoCode, dateTimeFrom, dateTimeTo, apiKey, "departure")
end

return FR24Provider
