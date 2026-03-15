--[[
    ShowSettings.lua
    Entry point for the "PlaneSpotter Pal Settings" menu action.
]]

local LrTasks = import "LrTasks"
local Preferences = require "Preferences"

LrTasks.startAsyncTask(function()
    Preferences.showSettingsDialog()
end)
