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

    RequireAdminForBuilder = false, -- If true, only authorized admins can open and save in the ELS Studio (/controlels)
    AdminPermission = 'admin', -- FiveM ACE permission fallback (e.g. 'admin' or 'spaceels.admin')
    AdminIdentifiers = {
        -- Add allowed player identifiers here (license, discord, live, etc.)
        -- 'license:xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx',
        -- 'discord:123456789012345678'
    },

    NonELSVehicles = {
        ['police'] = true,
        ['police2'] = true,
        ['police3'] = true,
        ['police4'] = true,
        ['policeb'] = true,
        ['policet'] = true,
        ['sheriff'] = true,
        ['sheriff2'] = true,
        ['fbi'] = true,
        ['fbi2'] = true,
        ['ambulance'] = true,
        ['firetruk'] = true,
        ['pranger'] = true,
        ['riot'] = true
    }
}
