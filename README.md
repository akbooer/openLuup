# openLuup
 a pure-Lua open-source emulation of the Vera Luup environment
 
 **openLuup** is an environment which supports the running of some MiOS (Vera) plugins on generic Unix systems (or, indeed, Windows systems.) Processors such as Raspberry Pi and BeagleBone Black are ideal for running this environment, although it can also run on Apple Mac, Microsoft Windows PCs, anything, in fact, which can run Lua code (most things can - even an Arduino Yún board.) The intention is to offload processing (cpu and memory use) from a running Vera to a remote machine to increase system reliability.

Running on non-specific hardware means that there is no native support for Z-wave, although plugins to handle Z-wave USB sticks may support this. The full range of MySensors (http://www.mysensors.org/) Arduino devices are supported though the Ethernet Bridge plugin available on that site. A plugin to provide a bi-directional ‘bridge’ (monitoring / control) to remote MiOS (Vera) systems is provided in the openLuup installation.

**openLuup** is extremely fast to start (a few seconds before it starts running any created devices startup code) has very low cpu load, and has a very compact memory footprint. Whereas each plugin on a Vera system might take ~4 Mbytes, it’s far less than this under openLuup, in fact, the whole system can fit into that sort of space. Since the hardware on which it runs is anyway likely to have much more physical memory than current Vera systems, memory is not really an issue.

There is no built-in user interface, but we have, courtesy of @amg0, the most excellent altUI: Alternate UI to UI7 (see the Vera forum board http://forum.micasaverde.com/index.php/board,78.0.html) An automated way of installing and updating the ALTUI environment is now built-in to openLuup. There’s actually no requirement for any user interface if all that’s needed is an environment to run plugins.

Devices, scenes, rooms and attributes are persisted across restarts. The startup initialisation process supports both the option of starting with a ‘factory-reset’ system, or any saved image, or continuing seamlessly with the previously saved environment. A separate utility is provided to transfer a complete set of uncompressed device files and icons from any Vera on your network to the openLuup target machine.

What **openLuup** does:

* runs the ALTUI plugin to give a great UI experience
*    runs the MySensors Arduino plugin (ethernet connection to gateway only) which is really the main goal - to have a Vera-like machine built entirely from third-party bits (open source)
*    includes a bridge app to link to remote Veras (which can be running UI5 or UI7 and require no additional software.)
*    runs many plugins unmodified – particularly those which just create virtual devices   (eg. Netatmo, ...)
*    uses a tiny amount of memory and boots up very quickly (a few seconds)
*    supports scenes with timers and ALTUI-style triggers
*    has its own port 3480 HTTP server supporting multiple asynchronous client requests
*    has a fairly complete implementation of the Luup API and the HTTP requests
*    has a simple to understand log structure - written to LuaUPnP.log in the current directory - most events generate just one entry each in the log.
*    writes variables to a separate log file for ALTUI to display variable and scene changes. 


What it doesn't do:

*    Some less-used HTML requests are not yet implemented, eg. lu_invoke.
*    Doesn't support the incoming or timeout action tags in service files,   but does support the device-level incoming tag (for asynchronous socket I/O.)
*    Doesn’t directly support local serial I/O hardware (there are work-arounds.)
*    Doesn't run encrypted, or licensed, plugins.
*    Doesn't use lots of memory.
*    Doesn’t use lots of cpu.
*    Doesn’t constantly reload (like Vera often does, for no apparent reason.)
*    Doesn't do UPnP (and never will.)  
