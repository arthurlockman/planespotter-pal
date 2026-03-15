--[[
    ProviderRegistry.lua
    Maps provider names to their modules and returns the active provider.
]]

local Preferences = require "Preferences"

local ProviderRegistry = {}

local providerModules = {
    AeroDataBox    = "providers.AeroDataBoxProvider",
    FlightAware    = "providers.FlightAwareProvider",
    FlightRadar24  = "providers.FR24Provider",
}

--- Get the currently active provider module.
-- @return provider module table, or nil + error message
function ProviderRegistry.getActiveProvider()
    local prefs = Preferences.getPrefs()
    local name = prefs.activeProvider

    local moduleName = providerModules[name]
    if not moduleName then
        return nil, "Unknown provider: " .. tostring(name)
    end

    local ok, provider = pcall(require, moduleName)
    if not ok then
        return nil, "Failed to load provider module: " .. tostring(provider)
    end

    return provider, nil
end

--- Get the API key for the active provider.
-- @return apiKey string, providerName string
function ProviderRegistry.getActiveApiKey()
    local prefs = Preferences.getPrefs()
    return Preferences.getActiveApiKey(), prefs.activeProvider
end

--- Get a list of all available provider names.
-- @return table of strings
function ProviderRegistry.getProviderNames()
    local names = {}
    for name, _ in pairs(providerModules) do
        names[#names + 1] = name
    end
    table.sort(names)
    return names
end

return ProviderRegistry
