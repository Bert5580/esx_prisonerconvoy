# esx_prisonerconvoy (v1.5.0)

Prisoner convoy for **ESX Legacy** using **mysql-async**. Spawns a prisoner bus with **lead + rear** police escorts, follows a configurable route, performs a checkpoint handoff at Bolingbroke, and locally jails the escorted player with an on‑screen timer.

## Features
- Lead + rear escorts with sirens, blips, and safe driving (**DriveStyle 443**).
- Custom route with arrival thresholds, final checkpoint freeze & handoff.
- Anti‑stall `/convoy_unstuck` to clear nearby peds/vehicles.
- Local jail handoff (minimum 15 minutes enforced) with countdown UI.
- Clean up on resource stop; resilient nil-guards and timeouts.
- ESX-based job gate for starting convoys (optional).

## Requirements
- ESX Legacy
- mysql-async (optional: for prisoner_jail_log)

## Install
1. Copy the folder to your `resources/` (name it `esx_prisonerconvoy`).  
2. Add `ensure esx_prisonerconvoy` to your `server.cfg`.  
3. (Optional) Create a log table:
   ```sql
   CREATE TABLE IF NOT EXISTS prisoner_jail_log (
     id INT AUTO_INCREMENT PRIMARY KEY,
     identifier VARCHAR(60) NOT NULL,
     minutes INT NOT NULL,
     created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
   );
   ```

## Configuration
See `config.lua`. Key points:
- `Config.DriveStyle = 443` (**required per preference**)  
- `Config.CustomRoute` nodes can be edited for your path.  
- `Config.RequirePoliceForStart = true` to require police job.

## Commands
- `/convoy_start` — starts the convoy for the caller (police if gated).
- `/convoy_unstuck` — clears the immediate area (use if stalled).

## Events (Client)
- `esx_prisonerconvoy:cl_start` — spawns and runs the convoy.
- `esx_prisonerconvoy:cl_unstuck` — anti-stall clear area.
- `esx_prisonerconvoy:cl_begin_local_jail (vector4, minutes)` — teleports & shows timer.
- `esx_prisonerconvoy:cl_release_local_jail (vector4)` — releases & teleports to UnjailLocation.

## Notes
- This sample uses a **local client jail**. If you use a jail resource, replace the jail section in `server.lua` to call your jail’s API.
- The script enforces **≥ 15 minutes** jail time per requirements.

## Credits
Bert + Assistant
