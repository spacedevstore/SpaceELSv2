Config = {}

Config.ELS = {
    Command = 'els',
    CommandAlias = 'elsui',
    StudioCommand = 'controlels',
    StudioCommandAlias = 'elscontrol',

    DefaultKey = 'U',
    KeyDescription = 'Toggle ELS UI',

    AllowPassengers = true, -- If false, only the driver seat can operate ELS and sirens

    EnableEnvironmentalLighting = true,
    EnvironmentalLightMaxDistance = 28.0,

    SoundVolume = 0.6, -- Volume scale for NUI switch clicks and interactive panel sounds

    RequireAdminForBuilder = true, -- If true, only players with admin permissions can save/reset vehicle profiles to disk
    AdminPermission = 'admin' -- ACE permission (or QBCore admin level) required if RequireAdminForBuilder is true
}
