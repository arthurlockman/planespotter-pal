--[[
    FlightAwareProvider.lua
    Flight data provider using FlightAware AeroAPI.
    
    Endpoints:
      GET /airports/{icao}/flights/arrivals?start=...&end=...
      GET /airports/{icao}/flights/departures?start=...&end=...
    Auth: x-apikey header
    Note: Uses ISO 8601 UTC timestamps.
]]

local LrHttp   = import "LrHttp"
local LrLogger = import "LrLogger"
local LrDate   = import "LrDate"

local json              = require "dkjson"
local FlightDataProvider = require "FlightDataProvider"

local logger = LrLogger("PlaneSpotterPal")

local FlightAwareProvider = {}

local BASE_URL = "https://aeroapi.flightaware.com/aeroapi"

function FlightAwareProvider.getName()
    return "FlightAware"
end

function FlightAwareProvider.validateApiKey(apiKey)
    if not apiKey or apiKey == "" then
        return false, "API key is empty"
    end
    local url = BASE_URL .. "/airports/KJFK"
    local headers = {
        { field = "x-apikey", value = apiKey },
    }
    local response, respHeaders = LrHttp.get(url, headers)
    if response then
        local data = json.decode(response)
        if data and not data.error then
            return true, nil
        end
    end
    return false, "Could not connect to FlightAware AeroAPI. Check your API key."
end

--- Format a LrDate timestamp to ISO 8601 UTC string.
-- Note: dateTimeOriginal is local time with no TZ info. We approximate by
-- treating it as UTC. For accurate results, the user should ensure their
-- camera clock is reasonably close, and the ±5min window will compensate.
local function formatUTC(lrTimestamp)
    return LrDate.timeToUserFormat(lrTimestamp, "%Y-%m-%dT%H:%M:%SZ")
end

--- Parse ISO 8601 timestamp from FlightAware response.
local function parseISOTimestamp(isoStr)
    if not isoStr then return nil end
    local y, m, d, h, min, s = isoStr:match("(%d+)-(%d+)-(%d+)T(%d+):(%d+):(%d+)")
    if not y then return nil end
    return LrDate.timeFromComponents(
        tonumber(y), tonumber(m), tonumber(d),
        tonumber(h), tonumber(min), tonumber(s), "local"
    )
end

--- Fetch flights from FlightAware.
local function fetchFlights(icaoCode, dateTimeFrom, dateTimeTo, apiKey, direction)
    local startStr = formatUTC(dateTimeFrom)
    local endStr   = formatUTC(dateTimeTo)

    local url = string.format("%s/airports/%s/flights/%s?start=%s&end=%s&type=Airline",
        BASE_URL, icaoCode, direction .. "s", startStr, endStr)

    local headers = {
        { field = "x-apikey", value = apiKey },
    }

    local response, respHeaders = LrHttp.get(url, headers)
    if not response then
        return nil, "FlightAware API request failed"
    end

    local data, _, err = json.decode(response)
    if err or not data then
        return nil, "Failed to parse FlightAware response: " .. tostring(err)
    end

    if data.error then
        return nil, "FlightAware error: " .. tostring(data.error)
    end

    local candidates = {}
    local flights = data[direction .. "s"] or {}

    for _, flight in ipairs(flights) do
        local origin = flight.origin or {}
        local dest   = flight.destination or {}

        local scheduledTime = nil
        local actualTime = nil

        if direction == "arrival" then
            scheduledTime = parseISOTimestamp(flight.scheduled_in)
            actualTime    = parseISOTimestamp(flight.actual_in)
        else
            scheduledTime = parseISOTimestamp(flight.scheduled_out)
            actualTime    = parseISOTimestamp(flight.actual_out)
        end

        candidates[#candidates + 1] = FlightDataProvider.newCandidate({
            flightNumber  = flight.ident,
            callsign      = flight.ident_icao,
            airline       = flight.operator,
            airlineIcao   = flight.operator_icao,
            aircraftType  = flight.aircraft_type,
            registration  = flight.registration,
            origin        = origin.code,
            destination   = dest.code,
            scheduledTime = scheduledTime,
            actualTime    = actualTime,
            direction     = direction,
        })
    end

    return candidates, nil
end

function FlightAwareProvider.getArrivals(icaoCode, dateTimeFrom, dateTimeTo, apiKey)
    return fetchFlights(icaoCode, dateTimeFrom, dateTimeTo, apiKey, "arrival")
end

function FlightAwareProvider.getDepartures(icaoCode, dateTimeFrom, dateTimeTo, apiKey)
    return fetchFlights(icaoCode, dateTimeFrom, dateTimeTo, apiKey, "departure")
end

return FlightAwareProvider
