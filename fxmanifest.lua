fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'esx_prisonerconvoy'
description 'Prisoner convoy with police escort, anti-stall, jail handoff, and route navigation (optimized)'
author 'Bert + Assistant'
version 'Ev1.5.0'

shared_scripts {{
  'config.lua',
  'Locales/en.lua'
}}

client_scripts {{
  'client.lua'
}}

server_scripts {{
  '@es_extended/imports.lua',
  'server.lua'
}}

dependencies {{
  'es_extended'
}}
