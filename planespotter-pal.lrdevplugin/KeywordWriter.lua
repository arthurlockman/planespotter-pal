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
        local rootKeyword = catalog:createKeyword("Aircraft", {}, false, nil, true)

        local airlineKeyword
        if candidate.airline and candidate.airline ~= "Unknown" then
            airlineKeyword = catalog:createKeyword(
                candidate.airline, {}, false, rootKeyword, true
            )
        end

        local typeKeyword
        if candidate.aircraftType then
            local parent = airlineKeyword or rootKeyword
            typeKeyword = catalog:createKeyword(
                candidate.aircraftType, {}, false, parent, true
            )
        end

        local regKeyword
        if candidate.registration then
            local parent = typeKeyword or airlineKeyword or rootKeyword
            regKeyword = catalog:createKeyword(
                candidate.registration, {}, false, parent, true
            )
        end

        -- Add the most specific keyword (Lightroom inherits parent keywords)
        local leafKeyword = regKeyword or typeKeyword or airlineKeyword or rootKeyword
        photo:addKeyword(leafKeyword)

        -- Add flat keywords for flight number and route
        if candidate.flightNumber and candidate.flightNumber ~= "Unknown" then
            local flightKw = catalog:createKeyword(
                candidate.flightNumber, {}, false, nil, true
            )
            photo:addKeyword(flightKw)
        end

        if candidate.origin and candidate.destination then
            local routeStr = candidate.origin .. "-" .. candidate.destination
            local routeKw = catalog:createKeyword(routeStr, {}, false, nil, true)
            photo:addKeyword(routeKw)
        end

        -- Add ICAO aircraft type code as keyword if available
        if candidate.aircraftIcao then
            local icaoKw = catalog:createKeyword(
                candidate.aircraftIcao, {}, false, nil, true
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
