-- config.lua (v1.5.0) — optimized defaults
Config = Config or {}

-- Core
Config.Locale    = 'en'
Config.ESXMode   = 'auto'      -- 'exports' | 'trigger' | 'auto'
Config.Debug     = false
Config.PoliceJob = 'police'
Config.RequirePoliceForStart = true

-- Models
Config.BusModel            = 'pbus'
Config.DriverPedModel      = 's_m_m_prisguard_01'
Config.GuardEscortPedModel = 's_m_m_prisguard_01'

-- Drive style (per-user preference in Model Set Context: ALWAYS 443)
-- 443 = safe, avoids traffic, obeys lanes better than 786603 for convoys.
Config.DriveStyle = 443

-- Speeds (m/s); 1 mph ≈ 0.44704 m/s
Config.LeadSpeedMS   = 17.9  -- ~40 mph
Config.RearSpeedMS   = 17.0  -- ~38 mph
Config.CatchupSpeedMS= 22.3  -- ~50 mph

-- Timings (seconds)
Config.WaitAfterFirstPrisonerLoaded = 12
Config.PrisonCheckFreezeSeconds     = 15
Config.AutoJailMinutes              = 15   -- lower bound is enforced in code

-- Blips
Config.Blips = {
  Enabled    = true,
  LeadSprite = 56,  -- police car
  RearSprite = 56,
  Colour     = 3,
  LeadName   = 'Convoy Lead',
  RearName   = 'Convoy Rear'
}

-- Escort tuning
Config.Escort = {
  Enabled        = true,  -- enable rear escort
  OffsetLead     = vector3(0.0, 8.0, 0.0),
  OffsetRear     = vector3(0.0, -10.5, 0.0),
  FollowingDist  = 11.0,   -- how closely escorts follow
  RepathThresh   = 28.0,   -- recalc path if distance exceeds this
  SirensOn       = true,
  SirenLightsOn  = true   -- lights even if siren muted
}

-- Stations / Points
Config.PrisonerWaitingArea = vector3(1845.24, 2585.95, 45.67)
Config.BusSpawnPoint       = vector4(1848.85, 2597.12, 45.67, 90.0)
Config.PrisonCheckpoint    = vector4(1840.73, 2589.50, 45.67, 90.0)
Config.UnjailLocation      = vector4(1847.84, 2576.32, 45.67, 180.0)

-- Route: example nodes from Sandy route to Bolingbroke
Config.CustomRoute = {
  Enabled     = true,
  NodeArrive  = 12.0,
  FinalArrive = 15.0,
  Debug       = false,
  Nodes = {
    vector3(1682.42, 3566.48, 35.83),
    vector3(1691.03, 3513.49, 36.43),
    vector3(1717.92, 3466.75, 38.90),
    vector3(2099.66, 2998.98, 45.12),
    vector3(1899.92, 2609.51, 45.74)
  }
}
