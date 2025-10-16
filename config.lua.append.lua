-- config.lua (ultimate failsafe)
Config = Config or {}
Config.UltimateFailsafe = Config.UltimateFailsafe or {
  Enabled = true,         -- hard guarantee completion even if AI pathing fails
  MaxTotalSeconds = 300,  -- if a leg takes longer than this, warp to the leg's destination
  MaxStallCycles = 12     -- or after this many stall cycles (retries/nudges) warp
}
