local json = require "openLuup.json"

local x =     {
      AllowMultiple   = "0",
      Title           = "Alternate UI",
      Icon            = "http://code.mios.com/trac/mios_alternate_ui/export/12/iconALTUI.png",
      Instructions    = "http://forum.micasaverde.com/index.php/board,78.0.html",
      Hidden          = "0",
      AutoUpdate      = "1",
--      Version         = 28706,
      VersionMajor    = 0 or '?',
      VersionMinor    = 88 or '?',
--      "SupportedPlatforms": null,
--      "MinimumVersion": null,
--      "DevStatus": null,
--      "Approved": "0",
      id              = 8246,
--      "TargetVersion": "28706",
      timestamp       = os.time(),
      Files           = {},
    }

print (json.encode (x))
