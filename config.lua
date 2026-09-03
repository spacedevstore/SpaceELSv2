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

    SoundVolume = 0.6 -- Volume scale for NUI switch clicks and interactive panel sounds
}
