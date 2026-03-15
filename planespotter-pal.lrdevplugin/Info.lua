return {
    LrSdkVersion = 13.0,
    LrSdkMinimumVersion = 12.0,
    LrToolkitIdentifier = "com.planespotterpal.lightroom",
    LrPluginName = "PlaneSpotter Pal",
    LrPluginInfoUrl = "https://github.com/planespotter-pal",

    LrLibraryMenuItems = {
        {
            title = "Identify Aircraft",
            file = "IdentifyAircraft.lua",
            enabledWhen = "photosAvailable",
        },
        {
            title = "PlaneSpotter Pal Settings",
            file = "ShowSettings.lua",
        },
    },

    VERSION = { major = 0, minor = 1, revision = 0, display = "0.1.0" },
}
