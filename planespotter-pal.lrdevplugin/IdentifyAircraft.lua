--[[
    IdentifyAircraft.lua
    Main entry point for the "Identify Aircraft" menu action.
    Reads selected photo(s), finds candidate flights, presents selection dialog.
    Supports batch processing with progress reporting.
]]

local LrTasks         = import "LrTasks"
local LrDialogs       = import "LrDialogs"
local LrApplication   = import "LrApplication"
local LrLogger        = import "LrLogger"
local LrProgressScope = import "LrProgressScope"

local logger = LrLogger("PlaneSpotterPal")

local Preferences     = require "Preferences"
local CandidateFinder = require "CandidateFinder"
local CandidateDialog = require "CandidateDialog"
local KeywordWriter   = require "KeywordWriter"

LrTasks.startAsyncTask(function()
    local catalog = LrApplication.activeCatalog()
    local photos = catalog:getTargetPhotos()

    if #photos == 0 then
        LrDialogs.message("PlaneSpotter Pal", "No photos selected.", "info")
        return
    end

    -- Validate that a provider is configured
    local prefs = Preferences.getPrefs()
    if not prefs.activeProvider or prefs.activeProvider == "" then
        LrDialogs.message("PlaneSpotter Pal",
            "No flight data provider configured. Please open Settings first.",
            "warning")
        return
    end

    local apiKey = Preferences.getActiveApiKey()
    if not apiKey or apiKey == "" then
        LrDialogs.message("PlaneSpotter Pal",
            "No API key set for " .. prefs.activeProvider .. ". Please open Settings.",
            "warning")
        return
    end

    -- Confirm batch operations (warns about API usage)
    if #photos > 1 then
        local confirm = LrDialogs.confirm(
            "PlaneSpotter Pal",
            string.format(
                "Process %d photos? This will make approximately %d API calls to %s.",
                #photos, #photos * 2, prefs.activeProvider
            ),
            "Continue", "Cancel"
        )
        if confirm == "cancel" then return end
    end

    local progress = LrProgressScope({
        title = "PlaneSpotter Pal — Identifying Aircraft",
        functionContext = nil,
    })

    local identified = 0
    local skipped = 0
    local errors = 0

    for i, photo in ipairs(photos) do
        if progress:isCanceled() then break end

        progress:setPortionComplete(i - 1, #photos)
        progress:setCaption(string.format("Photo %d of %d", i, #photos))

        local gps = photo:getRawMetadata("gps")
        local dateTime = photo:getRawMetadata("dateTimeOriginal")

        if not gps then
            logger:info("Photo " .. i .. " has no GPS data, skipping")
            skipped = skipped + 1
        elseif not dateTime then
            logger:info("Photo " .. i .. " has no capture time, skipping")
            skipped = skipped + 1
        else
            local heading = photo:getRawMetadata("gpsImgDirection")
            local focalLength = photo:getRawMetadata("focalLength35mm")

            local ok, candidates, err = pcall(CandidateFinder.findCandidates, {
                lat = gps.latitude,
                lon = gps.longitude,
                dateTime = dateTime,
                heading = heading,
                focalLength = focalLength,
            })

            if not ok then
                -- pcall caught an unexpected error
                logger:error("Unexpected error for photo " .. i .. ": " .. tostring(candidates))
                errors = errors + 1
                local action = LrDialogs.confirm(
                    "PlaneSpotter Pal",
                    "Unexpected error processing photo " .. i .. ":\n" .. tostring(candidates),
                    "Continue", "Stop"
                )
                if action == "cancel" then break end
            elseif err then
                logger:warn("Photo " .. i .. ": " .. err)
                errors = errors + 1
                -- For single photos, show the error. For batch, log and continue.
                if #photos == 1 then
                    LrDialogs.message("PlaneSpotter Pal", err, "warning")
                end
            elseif not candidates or #candidates == 0 then
                skipped = skipped + 1
                if #photos == 1 then
                    LrDialogs.message("PlaneSpotter Pal",
                        "No candidate flights found.\n"
                        .. "Try widening the search radius or time window in Settings.",
                        "info")
                end
            else
                local selected = CandidateDialog.show(candidates, photo)
                if selected then
                    local writeOk, writeErr = pcall(
                        KeywordWriter.writeKeywords, catalog, photo, selected
                    )
                    if writeOk then
                        identified = identified + 1
                    else
                        logger:error("Failed to write keywords: " .. tostring(writeErr))
                        errors = errors + 1
                    end
                end
            end
        end
    end

    progress:done()

    -- Show summary for batch operations
    if #photos > 1 then
        LrDialogs.message("PlaneSpotter Pal",
            string.format(
                "Batch complete:\n• %d aircraft identified\n• %d photos skipped\n• %d errors",
                identified, skipped, errors
            ),
            "info"
        )
    end
end)

