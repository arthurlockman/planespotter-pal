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

LrTasks.startAsyncTask(function()
    local Preferences     = require "Preferences"
    local CandidateFinder = require "CandidateFinder"
    local CandidateDialog = require "CandidateDialog"
    local KeywordWriter   = require "KeywordWriter"

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

    -- For multiple photos, offer "Same Aircraft" vs "Each Separately"
    local batchMode = "single" -- "single", "same", or "each"
    if #photos > 1 then
        local confirm = LrDialogs.confirm(
            "PlaneSpotter Pal",
            string.format(
                "You selected %d photos. Are these all the same aircraft, "
                .. "or should each photo be identified separately?\n\n"
                .. "• Same Aircraft — 1 API call, keywords applied to all %d photos\n"
                .. "• Each Separately — up to %d API calls, one dialog per photo",
                #photos, #photos, #photos
            ),
            "Same Aircraft", "Cancel", "Each Separately"
        )
        if confirm == "cancel" then return end
        batchMode = (confirm == "ok") and "same" or "each"
    end

    -- Helper: find candidates for a single photo
    local function findForPhoto(photo, index)
        local gps = photo:getRawMetadata("gps")
        local dateTime = photo:getRawMetadata("dateTimeOriginal")

        if not gps then
            logger:info("Photo " .. index .. " has no GPS data, skipping")
            return nil, nil, "no_gps"
        end
        if not dateTime then
            logger:info("Photo " .. index .. " has no capture time, skipping")
            return nil, nil, "no_time"
        end

        local heading = photo:getRawMetadata("gpsImgDirection")
        local focalLength = photo:getRawMetadata("focalLength35mm")

        local ok, candidates, err, searchContext = LrTasks.pcall(CandidateFinder.findCandidates, {
            lat = gps.latitude,
            lon = gps.longitude,
            dateTime = dateTime,
            heading = heading,
            focalLength = focalLength,
        })

        if not ok then
            return nil, nil, "error", tostring(candidates)
        end
        return candidates, searchContext, err and "api_error" or nil, err
    end

    -- "Same Aircraft" mode: one lookup, apply to all
    if batchMode == "same" then
        local sameProgress = LrProgressScope({
            title = "PlaneSpotter Pal — Finding flights…",
        })
        sameProgress:setIndeterminate()

        -- Use the first photo with GPS data for the lookup
        local refPhoto, refIndex
        for i, photo in ipairs(photos) do
            if photo:getRawMetadata("gps") and photo:getRawMetadata("dateTimeOriginal") then
                refPhoto = photo
                refIndex = i
                break
            end
        end

        if not refPhoto then
            sameProgress:done()
            LrDialogs.message("PlaneSpotter Pal",
                "None of the selected photos have GPS and time data.", "warning")
            return
        end

        sameProgress:setCaption("Querying flight data…")
        local candidates, searchContext, status, errMsg = findForPhoto(refPhoto, refIndex)

        if status == "error" then
            sameProgress:done()
            LrDialogs.message("PlaneSpotter Pal",
                "Error finding flights:\n" .. tostring(errMsg), "warning")
            return
        elseif status == "api_error" then
            sameProgress:done()
            LrDialogs.message("PlaneSpotter Pal", errMsg, "warning")
            return
        elseif not candidates or #candidates == 0 then
            sameProgress:done()
            LrDialogs.message("PlaneSpotter Pal",
                "No candidate flights found.\n"
                .. "Try widening the search radius or time window in Settings.",
                "info")
            return
        end

        sameProgress:setCaption(string.format("Loading thumbnails for %d candidates…", #candidates))
        sameProgress:done()

        local selected = CandidateDialog.show(candidates, refPhoto, searchContext)
        if not selected then return end

        -- Apply keywords to all selected photos
        local writeProgress = LrProgressScope({
            title = "PlaneSpotter Pal — Applying keywords…",
        })
        local writeErrors = 0
        for i, photo in ipairs(photos) do
            writeProgress:setPortionComplete(i - 1, #photos)
            writeProgress:setCaption(string.format("Photo %d of %d", i, #photos))
            local writeOk, writeErr = LrTasks.pcall(
                KeywordWriter.writeKeywords, catalog, photo, selected
            )
            if not writeOk then
                logger:error("Failed to write keywords: " .. tostring(writeErr))
                writeErrors = writeErrors + 1
            end
        end
        writeProgress:done()

        local msg = string.format("Keywords applied to %d photo(s).", #photos - writeErrors)
        if writeErrors > 0 then
            msg = msg .. string.format("\n%d photo(s) had errors.", writeErrors)
        end
        LrDialogs.message("PlaneSpotter Pal", msg, "info")
        return
    end

    -- "Each Separately" or single-photo mode
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

        local candidates, searchContext, status, errMsg = findForPhoto(photo, i)

        if status == "no_gps" or status == "no_time" then
            skipped = skipped + 1
        elseif status == "error" then
            logger:error("Unexpected error for photo " .. i .. ": " .. tostring(errMsg))
            errors = errors + 1
            local action = LrDialogs.confirm(
                "PlaneSpotter Pal",
                "Unexpected error processing photo " .. i .. ":\n" .. tostring(errMsg),
                "Continue", "Stop"
            )
            if action == "cancel" then break end
        elseif status == "api_error" then
            logger:warn("Photo " .. i .. ": " .. errMsg)
            errors = errors + 1
            if #photos == 1 then
                LrDialogs.message("PlaneSpotter Pal", errMsg, "warning")
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
            local selected = CandidateDialog.show(candidates, photo, searchContext)
            if selected then
                local writeOk, writeErr = LrTasks.pcall(
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

