--[[
    FlightDataProvider.lua
    Base interface definition for flight data providers.
    
    Every provider module must implement:
      provider.getArrivals(icaoCode, dateTimeFrom, dateTimeTo, apiKey)  → CandidateFlight[], err
      provider.getDepartures(icaoCode, dateTimeFrom, dateTimeTo, apiKey) → CandidateFlight[], err
      provider.getName() → string
      provider.validateApiKey(apiKey) → boolean, errorMsg
    
    CandidateFlight structure:
    {
        flightNumber  = "WN1234",
        callsign      = "SWA1234",        -- may be nil
        airline       = "Southwest Airlines",
        airlineIcao   = "SWA",            -- may be nil
        aircraftType  = "B737-800",       -- may be nil
        aircraftIcao  = "B738",           -- may be nil
        registration  = "N8541W",         -- may be nil
        origin        = "KDEN",           -- ICAO code
        destination   = "KLAX",           -- ICAO code
        scheduledTime = 1710523200,       -- Unix timestamp, may be nil
        actualTime    = 1710523440,       -- Unix timestamp, may be nil
        direction     = "arrival",        -- "arrival" or "departure"
    }
]]

local FlightDataProvider = {}

--- Create a new CandidateFlight with defaults for missing fields.
function FlightDataProvider.newCandidate(fields)
    return {
        flightNumber  = fields.flightNumber or "Unknown",
        callsign      = fields.callsign,
        airline       = fields.airline or "Unknown",
        airlineIcao   = fields.airlineIcao,
        aircraftType  = fields.aircraftType,
        aircraftIcao  = fields.aircraftIcao,
        registration  = fields.registration,
        origin        = fields.origin,
        destination   = fields.destination,
        scheduledTime = fields.scheduledTime,
        actualTime    = fields.actualTime,
        direction     = fields.direction or "arrival",
    }
end

return FlightDataProvider
