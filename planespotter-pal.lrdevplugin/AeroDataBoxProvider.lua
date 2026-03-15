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

--- Shared fetch for arrivals or departures.
local function fetchFlights(icaoCode, dateTimeFrom, dateTimeTo, apiKey, direction)
    local fromStr = formatLocalTime(dateTimeFrom)
    local toStr   = formatLocalTime(dateTimeTo)

    local url = string.format("%s/%s/%s/%s",
        BASE_URL, icaoCode, fromStr, toStr)

    -- Add direction filter via query parameter
    url = url .. "?direction=" .. direction

    local headers = {
        { field = "X-RapidAPI-Key",  value = apiKey },
        { field = "X-RapidAPI-Host", value = HOST },
    }

    local response, respHeaders = LrHttp.get(url, headers)
    if not response then
        return nil, "AeroDataBox API request failed"
    end

    local data, _, err = json.decode(response)
    if err or not data then
        return nil, "Failed to parse AeroDataBox response: " .. tostring(err)
    end

    if data.error then
        return nil, "AeroDataBox error: " .. tostring(data.error)
    end

    local candidates = {}
    local flights = data[direction .. "s"] or data.arrivals or data.departures or {}

    for _, flight in ipairs(flights) do
        local dep = flight.departure or {}
        local arr = flight.arrival or {}
        local aircraft = flight.aircraft or {}
        local airline = flight.airline or {}

        local scheduledTime = nil
        local actualTime = nil

        if direction == "arrival" then
            if arr.scheduledTime then
                scheduledTime = LrDate.timeFromComponents(
                    tonumber(string.sub(arr.scheduledTime, 1, 4)),
                    tonumber(string.sub(arr.scheduledTime, 6, 7)),
                    tonumber(string.sub(arr.scheduledTime, 9, 10)),
                    tonumber(string.sub(arr.scheduledTime, 12, 13)),
                    tonumber(string.sub(arr.scheduledTime, 15, 16)),
                    0, "local"
                )
            end
            if arr.actualTime then
                actualTime = LrDate.timeFromComponents(
                    tonumber(string.sub(arr.actualTime, 1, 4)),
                    tonumber(string.sub(arr.actualTime, 6, 7)),
                    tonumber(string.sub(arr.actualTime, 9, 10)),
                    tonumber(string.sub(arr.actualTime, 12, 13)),
                    tonumber(string.sub(arr.actualTime, 15, 16)),
                    0, "local"
                )
            end
        else
            if dep.scheduledTime then
                scheduledTime = LrDate.timeFromComponents(
                    tonumber(string.sub(dep.scheduledTime, 1, 4)),
                    tonumber(string.sub(dep.scheduledTime, 6, 7)),
                    tonumber(string.sub(dep.scheduledTime, 9, 10)),
                    tonumber(string.sub(dep.scheduledTime, 12, 13)),
                    tonumber(string.sub(dep.scheduledTime, 15, 16)),
                    0, "local"
                )
            end
            if dep.actualTime then
                actualTime = LrDate.timeFromComponents(
                    tonumber(string.sub(dep.actualTime, 1, 4)),
                    tonumber(string.sub(dep.actualTime, 6, 7)),
                    tonumber(string.sub(dep.actualTime, 9, 10)),
                    tonumber(string.sub(dep.actualTime, 12, 13)),
                    tonumber(string.sub(dep.actualTime, 15, 16)),
                    0, "local"
                )
            end
        end

        candidates[#candidates + 1] = FlightDataProvider.newCandidate({
            flightNumber  = flight.number,
            callsign      = flight.callSign,
            airline       = airline.name,
            airlineIcao   = airline.icao,
            aircraftType  = aircraft.model,
            aircraftIcao  = aircraft.icaoCode,
            registration  = aircraft.reg,
            origin        = dep.airport and dep.airport.icao,
            destination   = arr.airport and arr.airport.icao,
            scheduledTime = scheduledTime,
            actualTime    = actualTime,
            direction     = direction,
        })
    end

    return candidates, nil
end

function AeroDataBoxProvider.getArrivals(icaoCode, dateTimeFrom, dateTimeTo, apiKey)
    return fetchFlights(icaoCode, dateTimeFrom, dateTimeTo, apiKey, "arrival")
end

function AeroDataBoxProvider.getDepartures(icaoCode, dateTimeFrom, dateTimeTo, apiKey)
    return fetchFlights(icaoCode, dateTimeFrom, dateTimeTo, apiKey, "departure")
end

return AeroDataBoxProvider
