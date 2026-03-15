--[[
    KeywordWriter.lua
    Writes selected aircraft data as Lightroom keywords.
    
    Keyword hierarchy:
      Aircraft > <Airline> > <Aircraft Type> > <Registration>
    Flat keywords:
      Flight number, route (e.g., "KJFK-KLAX")
]]

local LrLogger = import "LrLogger"

local logger = LrLogger("PlaneSpotterPal")

local KeywordWriter = {}

--- Write aircraft keywords to a photo.
-- Must be called from within an async task.
-- @param catalog LrCatalog
-- @param photo LrPhoto
-- @param candidate CandidateFlight table
function KeywordWriter.writeKeywords(catalog, photo, candidate)
    catalog:withWriteAccessDo("PlaneSpotter Pal: Add Aircraft Keywords", function()
        -- Create hierarchical keywords: Aircraft > Airline > Type > Registration
        -- includeOnExport = true so they appear in keyword tags
        local rootKeyword = catalog:createKeyword("Aircraft", {}, true, nil, true)
        photo:addKeyword(rootKeyword)

        local airlineKeyword
        if candidate.airline and candidate.airline ~= "Unknown" then
            airlineKeyword = catalog:createKeyword(
                candidate.airline, {}, true, rootKeyword, true
            )
            photo:addKeyword(airlineKeyword)
        end

        local typeKeyword
        if candidate.aircraftType then
            local parent = airlineKeyword or rootKeyword
            typeKeyword = catalog:createKeyword(
                candidate.aircraftType, {}, true, parent, true
            )
            photo:addKeyword(typeKeyword)
        end

        if candidate.registration then
            local parent = typeKeyword or airlineKeyword or rootKeyword
            local regKeyword = catalog:createKeyword(
                candidate.registration, {}, true, parent, true
            )
            photo:addKeyword(regKeyword)
        end

        -- Flat keywords: flight number, callsign, route, ICAO type
        if candidate.flightNumber and candidate.flightNumber ~= "Unknown" then
            local flightKw = catalog:createKeyword(
                candidate.flightNumber, {}, true, nil, true
            )
            photo:addKeyword(flightKw)
        end

        if candidate.callsign and candidate.callsign ~= "" then
            local csKw = catalog:createKeyword(
                candidate.callsign, {}, true, nil, true
            )
            photo:addKeyword(csKw)
        end

        if candidate.origin and candidate.destination then
            local routeStr = candidate.origin .. "-" .. candidate.destination
            local routeKw = catalog:createKeyword(routeStr, {}, true, nil, true)
            photo:addKeyword(routeKw)
        end

        if candidate.aircraftIcao then
            local icaoKw = catalog:createKeyword(
                candidate.aircraftIcao, {}, true, nil, true
            )
            photo:addKeyword(icaoKw)
        end

        logger:info(string.format("Keywords written for %s (%s)",
            candidate.flightNumber or "unknown",
            candidate.registration or "unknown"
        ))
    end)
end

return KeywordWriter
