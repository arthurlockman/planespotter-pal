--[[
    CandidateDialog.lua
    Presents a modal dialog for the user to select the correct aircraft
    from a list of candidate flights. Shows Planespotters.net thumbnails
    alongside flight details.
]]

local LrDialogs    = import "LrDialogs"
local LrView       = import "LrView"
local LrDate       = import "LrDate"
local LrLogger     = import "LrLogger"
local LrBinding    = import "LrBinding"
local LrFunctionContext = import "LrFunctionContext"
local LrColor      = import "LrColor"

local PlaneSpottersAPI = require "PlaneSpottersAPI"

local logger = LrLogger("PlaneSpotterPal")

local CandidateDialog = {}

--- Format a timestamp for display.
local function formatTime(timestamp)
    if not timestamp then return "—" end
    return LrDate.timeToUserFormat(timestamp, "%H:%M")
end

--- Format the direction arrow.
local function formatRoute(candidate)
    local origin = candidate.origin or "?"
    local dest   = candidate.destination or "?"
    if candidate.direction == "arrival" then
        return origin .. " → " .. dest
    else
        return origin .. " → " .. dest
    end
end

--- Build a single candidate row with thumbnail and flight info.
local function buildCandidateRow(f, candidate, index, thumbnailCache)
    local reg = candidate.registration

    -- Try to get thumbnail from cache or fetch it
    local thumbPath = nil
    local photoInfo = nil
    if reg and reg ~= "" then
        if thumbnailCache[reg] == nil then
            -- Fetch photo info (may return nil)
            photoInfo = PlaneSpottersAPI.getPhotoByRegistration(reg)
            if photoInfo and photoInfo.thumbnailUrl then
                thumbPath = PlaneSpottersAPI.downloadThumbnail(photoInfo.thumbnailUrl)
                thumbnailCache[reg] = { path = thumbPath, info = photoInfo }
            else
                thumbnailCache[reg] = { path = false, info = nil }
            end
        else
            thumbPath = thumbnailCache[reg].path
            photoInfo = thumbnailCache[reg].info
        end
    end

    -- Thumbnail column
    local thumbView
    if thumbPath and thumbPath ~= false then
        thumbView = f:column {
            spacing = 2,
            f:picture {
                value = thumbPath,
                width = 200,
                height = 133,
            },
            f:static_text {
                title = "📷 " .. (photoInfo and photoInfo.photographer or ""),
                font = "<system/small>",
                text_color = LrColor(0.5, 0.5, 0.5),
                width = 200,
                truncation = "middle",
            },
        }
    else
        thumbView = f:column {
            width = 200,
            height = 133,
            f:static_text {
                title = "No photo available",
                font = "<system/small>",
                text_color = LrColor(0.6, 0.6, 0.6),
                alignment = "center",
                width = 200,
            },
        }
    end

    -- Time display
    local timeStr = formatTime(candidate.actualTime or candidate.scheduledTime)
    if candidate.actualTime and candidate.scheduledTime then
        timeStr = formatTime(candidate.actualTime) .. " (sched " .. formatTime(candidate.scheduledTime) .. ")"
    end

    -- Info column
    local infoView = f:column {
        spacing = 2,
        fill_horizontal = 1,
        f:row {
            f:static_text {
                title = (candidate.airline or "Unknown Airline"),
                font = "<system/bold>",
                fill_horizontal = 1,
            },
            f:static_text {
                title = candidate.direction == "arrival" and "⬇ ARR" or "⬆ DEP",
                font = "<system/small/bold>",
                text_color = candidate.direction == "arrival"
                    and LrColor(0.2, 0.6, 0.2) or LrColor(0.2, 0.2, 0.8),
            },
        },
        f:static_text {
            title = string.format("%s  •  %s  •  %s",
                candidate.flightNumber or "—",
                candidate.aircraftType or candidate.aircraftIcao or "—",
                candidate.registration or "—"
            ),
            font = "<system>",
        },
        f:static_text {
            title = formatRoute(candidate),
            font = "<system>",
        },
        f:static_text {
            title = "Time: " .. timeStr,
            font = "<system/small>",
            text_color = LrColor(0.4, 0.4, 0.4),
        },
    }

    return f:row {
        spacing = 12,
        margin_top = index > 1 and 8 or 0,
        thumbView,
        infoView,
    }
end

--- Show the candidate selection dialog.
-- @param candidates array of CandidateFlight
-- @param photo LrPhoto (for context in the dialog title)
-- @param searchContext table (optional) {airports, photoTime, timeWindowMin, radiusNm, providerName}
-- @return selected CandidateFlight, or nil if cancelled
function CandidateDialog.show(candidates, photo, searchContext)
    local result = nil

    LrFunctionContext.callWithContext("CandidateDialog", function(context)
        local props = LrBinding.makePropertyTable(context)
        props.selectedIndex = 1

        local f = LrView.osFactory()
        local thumbnailCache = {}

        -- Build search context header
        local contextRows = {}
        if searchContext then
            local photoTimeStr = "Unknown"
            if searchContext.photoTime then
                photoTimeStr = LrDate.timeToUserFormat(searchContext.photoTime, "%Y-%m-%d %H:%M:%S")
            end

            local airportStr = "None"
            if searchContext.airports and #searchContext.airports > 0 then
                airportStr = table.concat(searchContext.airports, ", ")
            end

            contextRows = {
                f:static_text {
                    title = "Search Details",
                    font = "<system/bold>",
                },
                f:static_text {
                    title = string.format("📍 Photo taken: %s", photoTimeStr),
                    font = "<system/small>",
                },
                f:static_text {
                    title = string.format("✈ Airport(s): %s", airportStr),
                    font = "<system/small>",
                },
                f:static_text {
                    title = string.format("🔍 Window: ±%d min  •  Radius: %d nm  •  Provider: %s",
                        searchContext.timeWindowMin or 5,
                        searchContext.radiusNm or 5,
                        searchContext.providerName or "Unknown"),
                    font = "<system/small>",
                },
                f:separator { fill_horizontal = 1 },
            }
        end

        -- Count arrivals & departures
        local arrCount, depCount = 0, 0
        for _, c in ipairs(candidates) do
            if c.direction == "arrival" then arrCount = arrCount + 1
            else depCount = depCount + 1 end
        end

        -- Direction filter
        props.filterDirection = "all"
        local filterItems = {
            { title = string.format("All (%d)", #candidates),  value = "all" },
            { title = string.format("Arrivals (%d)", arrCount), value = "arrival" },
            { title = string.format("Departures (%d)", depCount), value = "departure" },
        }

        -- Build selection items for popup (include direction tag)
        local popupItems = {}
        for i, c in ipairs(candidates) do
            local tag = c.direction == "arrival" and "ARR" or "DEP"
            popupItems[i] = {
                title = string.format("%d. [%s] %s — %s %s (%s)",
                    i, tag,
                    c.flightNumber or "?",
                    c.airline or "",
                    c.aircraftType or "",
                    c.registration or "?"
                ),
                value = i,
            }
        end

        -- Initialize per-row visibility properties
        for i = 1, #candidates do
            props["row_" .. i .. "_visible"] = true
        end

        -- Observer: when filter changes, toggle row visibility
        props:addObserver("filterDirection", function(_, _, newValue)
            for i, c in ipairs(candidates) do
                props["row_" .. i .. "_visible"] =
                    (newValue == "all" or c.direction == newValue)
            end
        end)

        -- Build all candidate rows with visibility binding
        local rows = {}
        for i = 1, #candidates do
            rows[#rows + 1] = f:column {
                visible = LrView.bind("row_" .. i .. "_visible"),
                fill_horizontal = 1,
                buildCandidateRow(f, candidates[i], i, thumbnailCache),
                f:separator { fill_horizontal = 1 },
            }
        end

        -- Build contents column programmatically (Lua 5.1 can't unpack mid-table)
        local contentItems = {}

        -- Add search context if available
        for _, item in ipairs(contextRows) do
            contentItems[#contentItems + 1] = item
        end

        contentItems[#contentItems + 1] = f:row {
            spacing = 12,
            f:static_text {
                title = string.format("Found %d candidate flight(s).", #candidates),
                font = "<system/bold>",
                fill_horizontal = 1,
            },
            f:static_text { title = "Filter:" },
            f:popup_menu {
                items = filterItems,
                value = LrView.bind("filterDirection"),
                width = 160,
            },
        }

        contentItems[#contentItems + 1] = f:row {
            f:static_text { title = "Select aircraft:" },
            f:popup_menu {
                items = popupItems,
                value = LrView.bind("selectedIndex"),
                width = 500,
            },
        }

        contentItems[#contentItems + 1] = f:separator { fill_horizontal = 1 }

        contentItems[#contentItems + 1] = f:scrolled_view {
            width = 700,
            height = 500,
            f:column(rows),
        }

        contentItems[#contentItems + 1] = f:static_text {
            title = "Aircraft photos courtesy of Planespotters.net. Photographer credit shown per image.",
            font = "<system/small>",
        }

        contentItems.spacing = 8
        contentItems.bind_to_object = props

        local contents = f:column(contentItems)

        local dialogResult = LrDialogs.presentModalDialog({
            title = "PlaneSpotter Pal — Identify Aircraft",
            contents = contents,
            actionVerb = "Assign Keywords",
            cancelVerb = "Cancel",
        })

        if dialogResult == "ok" then
            local idx = props.selectedIndex
            if idx and idx >= 1 and idx <= #candidates then
                result = candidates[idx]
            end
        end
    end)

    return result
end

return CandidateDialog
