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
local LrProgressScope = import "LrProgressScope"

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

    -- Read from pre-populated cache only
    local thumbPath = nil
    local photoInfo = nil
    if reg and reg ~= "" and thumbnailCache[reg] then
        thumbPath = thumbnailCache[reg].path
        photoInfo = thumbnailCache[reg].info
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
        f:static_text {
            title = tostring(index),
            font = { name = "Helvetica", size = 24 },
            text_color = LrColor(0.45, 0.45, 0.45),
            width = 44,
            alignment = "right",
        },
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

        local f = LrView.osFactory()
        local thumbnailCache = {}

        -- Pre-fetch all thumbnails with progress indication
        local uniqueRegs = {}
        local regOrder = {}
        for _, c in ipairs(candidates) do
            local reg = c.registration
            if reg and reg ~= "" and not uniqueRegs[reg] then
                uniqueRegs[reg] = true
                regOrder[#regOrder + 1] = reg
            end
        end

        if #regOrder > 0 then
            local thumbProgress = LrProgressScope({
                title = "PlaneSpotter Pal — Loading aircraft photos…",
            })
            for i, reg in ipairs(regOrder) do
                if thumbProgress:isCanceled() then break end
                thumbProgress:setPortionComplete(i - 1, #regOrder)
                thumbProgress:setCaption(string.format("%s (%d of %d)", reg, i, #regOrder))

                local photoInfo = PlaneSpottersAPI.getPhotoByRegistration(reg)
                if photoInfo and photoInfo.thumbnailUrl then
                    local thumbPath = PlaneSpottersAPI.downloadThumbnail(photoInfo.thumbnailUrl, reg)
                    thumbnailCache[reg] = { path = thumbPath, info = photoInfo }
                else
                    thumbnailCache[reg] = { path = false, info = nil }
                end
            end
            thumbProgress:done()
        end

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
            }

            -- Add API quota info if available
            if searchContext.rateLimit then
                local rl = searchContext.rateLimit
                local parts = {}

                if rl.unitsRemaining then
                    parts[#parts + 1] = string.format("API units: %d / %d",
                        rl.unitsRemaining, rl.unitsLimit or 0)
                end
                if rl.requestsRemaining then
                    parts[#parts + 1] = string.format("Requests: %d / %d",
                        rl.requestsRemaining, rl.requestsLimit or 0)
                end

                if #parts > 0 then
                    local remaining = rl.unitsRemaining or rl.requestsRemaining or 999
                    contextRows[#contextRows + 1] = f:static_text {
                        title = "📊 " .. table.concat(parts, "  •  "),
                        font = "<system/small>",
                        text_color = remaining < 50
                            and LrColor(0.8, 0.2, 0.2)
                            or LrColor(0.4, 0.4, 0.4),
                    }
                end
            end

            contextRows[#contextRows + 1] = f:separator { fill_horizontal = 1 }
        end

        -- Count arrivals & departures and build filtered index lists
        local arrCount, depCount = 0, 0
        local arrIndices = {}
        local depIndices = {}
        for i, c in ipairs(candidates) do
            if c.direction == "arrival" then
                arrCount = arrCount + 1
                arrIndices[#arrIndices + 1] = i
            else
                depCount = depCount + 1
                depIndices[#depIndices + 1] = i
            end
        end

        -- Helper: build a popup items list and rows for a subset of candidates
        local function buildTabContent(indices, label)
            local items = {}
            local rows = {}
            for pos, idx in ipairs(indices) do
                local c = candidates[idx]
                items[#items + 1] = {
                    title = string.format("%d. %s — %s %s (%s)",
                        pos,
                        c.flightNumber or "?",
                        c.airline or "",
                        c.aircraftType or "",
                        c.registration or "?"
                    ),
                    value = idx,
                }
                rows[#rows + 1] = buildCandidateRow(f, c, pos, thumbnailCache)
                rows[#rows + 1] = f:separator { fill_horizontal = 1 }
            end
            return items, rows
        end

        -- Build "All" list with direction tags
        local allItems = {}
        for i, c in ipairs(candidates) do
            local tag = c.direction == "arrival" and "ARR" or "DEP"
            allItems[i] = {
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
        local allRows = {}
        for i = 1, #candidates do
            allRows[#allRows + 1] = buildCandidateRow(f, candidates[i], i, thumbnailCache)
            allRows[#allRows + 1] = f:separator { fill_horizontal = 1 }
        end

        local arrItems, arrRows = buildTabContent(arrIndices, "ARR")
        local depItems, depRows = buildTabContent(depIndices, "DEP")

        -- Each tab gets its own selection property
        props.selAll = 1
        props.selArr = arrIndices[1] or 1
        props.selDep = depIndices[1] or 1
        props.activeTab = "all"

        props:addObserver("selAll", function() props.activeTab = "all" end)
        props:addObserver("selArr", function() props.activeTab = "arr" end)
        props:addObserver("selDep", function() props.activeTab = "dep" end)

        -- Build contents column programmatically (Lua 5.1 can't unpack mid-table)
        local contentItems = {}

        -- Add search context if available
        for _, item in ipairs(contextRows) do
            contentItems[#contentItems + 1] = item
        end

        contentItems[#contentItems + 1] = f:static_text {
            title = string.format("Found %d candidate flight(s). Select the correct aircraft:",
                #candidates),
            font = "<system/bold>",
        }

        -- Tab view with per-tab dropdown + scrolled list
        contentItems[#contentItems + 1] = f:tab_view {
            f:tab_view_item {
                title = string.format("All (%d)", #candidates),
                identifier = "tab_all",
                f:column {
                    spacing = 8,
                    bind_to_object = props,
                    f:row {
                        f:static_text { title = "Select aircraft:" },
                        f:popup_menu {
                            items = allItems,
                            value = LrView.bind("selAll"),
                            width = 560,
                        },
                    },
                    f:scrolled_view {
                        width = 680, height = 440,
                        f:column(allRows),
                    },
                },
            },
            f:tab_view_item {
                title = string.format("Arrivals (%d)", arrCount),
                identifier = "tab_arrivals",
                f:column {
                    spacing = 8,
                    bind_to_object = props,
                    f:row {
                        f:static_text { title = "Select aircraft:" },
                        f:popup_menu {
                            items = arrItems,
                            value = LrView.bind("selArr"),
                            width = 560,
                        },
                    },
                    f:scrolled_view {
                        width = 680, height = 440,
                        f:column(arrRows),
                    },
                },
            },
            f:tab_view_item {
                title = string.format("Departures (%d)", depCount),
                identifier = "tab_departures",
                f:column {
                    spacing = 8,
                    bind_to_object = props,
                    f:row {
                        f:static_text { title = "Select aircraft:" },
                        f:popup_menu {
                            items = depItems,
                            value = LrView.bind("selDep"),
                            width = 560,
                        },
                    },
                    f:scrolled_view {
                        width = 680, height = 440,
                        f:column(depRows),
                    },
                },
            },
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
            local idx
            if props.activeTab == "arr" then
                idx = props.selArr
            elseif props.activeTab == "dep" then
                idx = props.selDep
            else
                idx = props.selAll
            end
            if idx and idx >= 1 and idx <= #candidates then
                result = candidates[idx]
            end
        end
    end)

    -- Clean up stale cached thumbnails (>24h per Planespotters.net ToS)
    PlaneSpottersAPI.cleanupThumbnails()

    return result
end

return CandidateDialog
