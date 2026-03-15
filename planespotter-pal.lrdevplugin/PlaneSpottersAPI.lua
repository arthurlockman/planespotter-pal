--[[
    PlaneSpottersAPI.lua
    Client for the Planespotters.net Photo API.
    Free, no API key required.
    
    Returns aircraft thumbnails for display in the candidate selection dialog.
    Terms of use: must credit photographer, link to original page, no caching > 24h.
]]

local LrHttp      = import "LrHttp"
local LrPathUtils = import "LrPathUtils"
local LrFileUtils = import "LrFileUtils"
local LrLogger    = import "LrLogger"

local json = require "dkjson"

local logger = LrLogger("PlaneSpotterPal")

local PlaneSpottersAPI = {}

local BASE_URL = "https://api.planespotters.net/pub/photos"

--- Fetch photo info by aircraft registration.
-- @param registration string e.g. "N8541W"
-- @return table {thumbnailUrl, thumbnailWidth, thumbnailHeight, linkUrl, photographer} or nil
function PlaneSpottersAPI.getPhotoByRegistration(registration)
    if not registration or registration == "" then return nil end
    local url = BASE_URL .. "/reg/" .. registration
    return PlaneSpottersAPI._fetchPhoto(url)
end

--- Fetch photo info by ICAO hex code.
-- @param hex string e.g. "ABC123"
-- @return table or nil
function PlaneSpottersAPI.getPhotoByHex(hex)
    if not hex or hex == "" then return nil end
    local url = BASE_URL .. "/hex/" .. hex
    return PlaneSpottersAPI._fetchPhoto(url)
end

--- Internal: fetch and parse a photo API response.
function PlaneSpottersAPI._fetchPhoto(url)
    local response, headers = LrHttp.get(url)

    if not response then
        logger:warn("PlaneSpotters API request failed for: " .. url)
        return nil
    end

    local data, _, err = json.decode(response)
    if err or not data then
        logger:warn("PlaneSpotters API JSON parse error: " .. tostring(err))
        return nil
    end

    if data.error then
        logger:warn("PlaneSpotters API error: " .. tostring(data.error))
        return nil
    end

    if not data.photos or #data.photos == 0 then
        return nil
    end

    local photo = data.photos[1]
    local thumb = photo.thumbnail_large or photo.thumbnail
    if not thumb then return nil end

    return {
        thumbnailUrl    = thumb.src,
        thumbnailWidth  = thumb.size and thumb.size.width,
        thumbnailHeight = thumb.size and thumb.size.height,
        linkUrl         = photo.link,
        photographer    = photo.photographer,
        photoId         = photo.id,
    }
end

--- Download a thumbnail image to a temp file for display in LrView:picture.
-- @param thumbnailUrl string The CDN URL from the API response
-- @return string path to temp file, or nil on failure
function PlaneSpottersAPI.downloadThumbnail(thumbnailUrl)
    if not thumbnailUrl then return nil end

    local imageData, headers = LrHttp.get(thumbnailUrl)
    if not imageData then
        logger:warn("Failed to download thumbnail: " .. thumbnailUrl)
        return nil
    end

    local tempDir = LrPathUtils.getStandardFilePath("temp")
    -- Use a hash-like name to avoid collisions
    local filename = "psp_" .. tostring(os.time()) .. "_" .. math.random(10000, 99999) .. ".jpg"
    local tempPath = LrPathUtils.child(tempDir, filename)

    local file = io.open(tempPath, "wb")
    if not file then
        logger:warn("Failed to create temp file: " .. tempPath)
        return nil
    end
    file:write(imageData)
    file:close()

    return tempPath
end

return PlaneSpottersAPI
