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
-- Uses registration-based filenames to avoid duplicate downloads within a session.
-- @param thumbnailUrl string The CDN URL from the API response
-- @param registration string (optional) Used for stable filename
-- @return string path to temp file, or nil on failure
function PlaneSpottersAPI.downloadThumbnail(thumbnailUrl, registration)
    if not thumbnailUrl then return nil end

    local tempDir = LrPathUtils.getStandardFilePath("temp")
    local pspDir = LrPathUtils.child(tempDir, "PlaneSpotterPal")
    LrFileUtils.createAllDirectories(pspDir)

    -- Use registration for stable filename, fall back to random
    local safeName = registration and registration:gsub("[^%w%-]", "_") or
        (tostring(os.time()) .. "_" .. math.random(10000, 99999))
    local filename = "psp_" .. safeName .. ".jpg"
    local tempPath = LrPathUtils.child(pspDir, filename)

    -- Skip download if file already exists and is recent (< 24h per ToS)
    if LrFileUtils.exists(tempPath) then
        local attrs = LrFileUtils.fileAttributes(tempPath)
        if attrs and attrs.fileModificationDate then
            local age = os.time() - attrs.fileModificationDate
            if age < 86400 then
                return tempPath
            end
        end
    end

    local imageData, headers = LrHttp.get(thumbnailUrl)
    if not imageData then
        logger:warn("Failed to download thumbnail: " .. thumbnailUrl)
        return nil
    end

    local file = io.open(tempPath, "wb")
    if not file then
        logger:warn("Failed to create temp file: " .. tempPath)
        return nil
    end
    file:write(imageData)
    file:close()

    return tempPath
end

--- Clean up cached thumbnail files older than maxAgeSec (default 24 hours).
function PlaneSpottersAPI.cleanupThumbnails(maxAgeSec)
    maxAgeSec = maxAgeSec or 86400
    local tempDir = LrPathUtils.getStandardFilePath("temp")
    local pspDir = LrPathUtils.child(tempDir, "PlaneSpotterPal")

    if not LrFileUtils.exists(pspDir) then return end

    local now = os.time()
    for filePath in LrFileUtils.files(pspDir) do
        local attrs = LrFileUtils.fileAttributes(filePath)
        if attrs and attrs.fileModificationDate then
            if (now - attrs.fileModificationDate) > maxAgeSec then
                LrFileUtils.delete(filePath)
            end
        end
    end
end

return PlaneSpottersAPI
