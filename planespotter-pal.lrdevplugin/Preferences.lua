--[[
    Preferences.lua
    Stores and retrieves user preferences for PlaneSpotter Pal.
    Provides a settings dialog for configuring providers, API keys,
    search radius, and time window.
]]

local LrPrefs   = import "LrPrefs"
local LrDialogs = import "LrDialogs"
local LrView    = import "LrView"

local Preferences = {}

local PROVIDERS = {
    { title = "AeroDataBox (RapidAPI)", value = "AeroDataBox" },
    { title = "FlightAware AeroAPI",    value = "FlightAware" },
    { title = "FlightRadar24",          value = "FlightRadar24" },
}

local DEFAULTS = {
    activeProvider      = "AeroDataBox",
    apiKey_AeroDataBox  = "",
    apiKey_FlightAware  = "",
    apiKey_FlightRadar24 = "",
    searchRadiusNm      = 10,
    timeWindowMinutes    = 60,
}

-- ---------------------------------------------------------------------------
-- Public API
-- ---------------------------------------------------------------------------

function Preferences.getPrefs()
    local prefs = LrPrefs.prefsForPlugin()
    for k, v in pairs(DEFAULTS) do
        if prefs[k] == nil then
            prefs[k] = v
        end
    end
    return prefs
end

function Preferences.getActiveProviderName()
    local prefs = Preferences.getPrefs()
    return prefs.activeProvider
end

function Preferences.getActiveApiKey()
    local prefs = Preferences.getPrefs()
    local keyMap = {
        AeroDataBox    = "apiKey_AeroDataBox",
        FlightAware    = "apiKey_FlightAware",
        FlightRadar24  = "apiKey_FlightRadar24",
    }
    local keyName = keyMap[prefs.activeProvider]
    return keyName and prefs[keyName] or ""
end

-- ---------------------------------------------------------------------------
-- Settings dialog
-- ---------------------------------------------------------------------------

function Preferences.showSettingsDialog()
    local prefs = Preferences.getPrefs()
    local f = LrView.osFactory()

    local contents = f:column {
        spacing = f:control_spacing(),
        bind_to_object = prefs,

        -- ── Provider ─────────────────────────────────────────────────
        f:static_text {
            title = "Flight Data Provider",
            font  = "<system/bold>",
        },
        f:separator { fill_horizontal = 1 },

        f:row {
            f:static_text {
                title     = "Active provider:",
                alignment = "right",
                width     = LrView.share "label_width",
            },
            f:popup_menu {
                value   = LrView.bind "activeProvider",
                items   = PROVIDERS,
                width   = 220,
            },
        },

        f:spacer { height = 12 },

        -- ── API Keys ─────────────────────────────────────────────────
        f:static_text {
            title = "API Keys",
            font  = "<system/bold>",
        },
        f:separator { fill_horizontal = 1 },

        f:row {
            f:static_text {
                title     = "AeroDataBox:",
                alignment = "right",
                width     = LrView.share "label_width",
            },
            f:edit_field {
                value           = LrView.bind "apiKey_AeroDataBox",
                width_in_chars  = 36,
                immediate       = true,
            },
        },
        f:static_text {
            title      = "RapidAPI key for AeroDataBox",
            font       = "<system/small>",
        },

        f:row {
            f:static_text {
                title     = "FlightAware:",
                alignment = "right",
                width     = LrView.share "label_width",
            },
            f:edit_field {
                value           = LrView.bind "apiKey_FlightAware",
                width_in_chars  = 36,
                immediate       = true,
            },
        },
        f:static_text {
            title      = "FlightAware AeroAPI key",
            font       = "<system/small>",
        },

        f:row {
            f:static_text {
                title     = "FlightRadar24:",
                alignment = "right",
                width     = LrView.share "label_width",
            },
            f:edit_field {
                value           = LrView.bind "apiKey_FlightRadar24",
                width_in_chars  = 36,
                immediate       = true,
            },
        },
        f:static_text {
            title      = "Bearer token for FlightRadar24 API",
            font       = "<system/small>",
        },

        f:spacer { height = 12 },

        -- ── Search Parameters ────────────────────────────────────────
        f:static_text {
            title = "Search Parameters",
            font  = "<system/bold>",
        },
        f:separator { fill_horizontal = 1 },

        f:row {
            f:static_text {
                title     = "Search radius:",
                alignment = "right",
                width     = LrView.share "label_width",
            },
            f:slider {
                value   = LrView.bind "searchRadiusNm",
                min     = 1,
                max     = 50,
                width   = 180,
            },
            f:edit_field {
                value          = LrView.bind "searchRadiusNm",
                width_in_chars = 4,
                min            = 1,
                max            = 50,
                increment      = 1,
                precision      = 0,
                immediate      = true,
            },
            f:static_text { title = "nm" },
        },

        f:row {
            f:static_text {
                title     = "Time window:",
                alignment = "right",
                width     = LrView.share "label_width",
            },
            f:slider {
                value   = LrView.bind "timeWindowMinutes",
                min     = 5,
                max     = 180,
                width   = 180,
            },
            f:edit_field {
                value          = LrView.bind "timeWindowMinutes",
                width_in_chars = 4,
                min            = 5,
                max            = 180,
                increment      = 1,
                precision      = 0,
                immediate      = true,
            },
            f:static_text { title = "min" },
        },

        f:spacer { height = 12 },

        -- ── Cache Management ─────────────────────────────────────────
        f:static_text {
            title = "Cache",
            font  = "<system/bold>",
        },
        f:separator { fill_horizontal = 1 },

        f:static_text {
            title = "Cached data speeds up repeated lookups. Clear if results seem stale.",
            font  = "<system/small>",
        },

        f:row {
            f:push_button {
                title  = "Clear Flight Cache",
                action = function()
                    local CandidateFinder = require "CandidateFinder"
                    CandidateFinder.clearCache()
                    LrDialogs.message("PlaneSpotter Pal",
                        "Flight data cache cleared.", "info")
                end,
            },
            f:push_button {
                title  = "Clear Thumbnail Cache",
                action = function()
                    local PlaneSpottersAPI = require "PlaneSpottersAPI"
                    PlaneSpottersAPI.cleanupThumbnails(0)
                    LrDialogs.message("PlaneSpotter Pal",
                        "Thumbnail cache cleared.", "info")
                end,
            },
            f:push_button {
                title  = "Clear All Caches",
                action = function()
                    local CandidateFinder = require "CandidateFinder"
                    local PlaneSpottersAPI = require "PlaneSpottersAPI"
                    CandidateFinder.clearCache()
                    PlaneSpottersAPI.cleanupThumbnails(0)
                    LrDialogs.message("PlaneSpotter Pal",
                        "All caches cleared.", "info")
                end,
            },
        },

        f:spacer { height = 12 },

        -- ── Test Connection ──────────────────────────────────────────
        f:separator { fill_horizontal = 1 },

        f:row {
            f:push_button {
                title    = "Test Connection",
                action   = function()
                    local provider = prefs.activeProvider
                    local key      = Preferences.getActiveApiKey()
                    if not key or key == "" then
                        LrDialogs.message(
                            "PlaneSpotter Pal",
                            "No API key entered for " .. provider .. ".",
                            "warning"
                        )
                    else
                        -- Placeholder — actual connectivity test wired up later
                        LrDialogs.message(
                            "PlaneSpotter Pal",
                            provider .. " connection test not yet implemented.\n"
                                .. "API key is configured (" .. string.len(key)
                                .. " characters).",
                            "info"
                        )
                    end
                end,
            },
        },
    }

    local result = LrDialogs.presentModalDialog {
        title            = "PlaneSpotter Pal — Settings",
        contents         = contents,
        actionVerb       = "Save",
        cancelVerb       = "Cancel",
    }

    return result
end

return Preferences
