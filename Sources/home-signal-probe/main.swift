import Foundation
#if os(macOS)
import HomeSignalMirroring

MediaRouteProbeMain.main()
#else
FileHandle.standardError.write(Data("home-signal-probe runs on macOS.\n".utf8))
exit(1)
#endif
