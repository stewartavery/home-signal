public enum MirrorScript {
    public static func controlCenter(target: String, deviceID: String, action: String, leaveOpen: Bool) -> String {
        let name = appleString(target)
        let identifier = appleString(deviceID)
        let verb = appleString(action)
        let stay = leaveOpen ? "true" : "false"
        return """
        set targetName to \(name)
        set deviceID to \(identifier)
        set actionName to \(verb)
        set leaveOpen to \(stay)
        tell application "System Events"
          tell process "ControlCenter"
            click (first menu bar item of menu bar 1 whose description is "Control Center")
            delay 0.6
            click (first checkbox of group 1 of window 1 whose value of attribute "AXIdentifier" is "controlcenter-screen-mirroring")
            set cb to missing value
            repeat 20 times
              delay 0.3
              try
                if deviceID is not "" then
                  set cb to (first checkbox of group 1 of scroll area 1 of group 1 of window 1 whose value of attribute "AXIdentifier" is deviceID)
                else
                  set cb to (first checkbox of group 1 of scroll area 1 of group 1 of window 1 whose description contains targetName or name contains targetName)
                end if
                exit repeat
              end try
            end repeat
            if cb is missing value then error "AirPlay target not found: " & targetName
            set isOn to value of cb
            if actionName is "status" then
              if leaveOpen is false then key code 53
              return isOn as text
            else if actionName is "connect" then
              if isOn is 0 then
                click cb
                if leaveOpen is false then key code 53
                return "connected"
              else
                if leaveOpen is false then key code 53
                return "already-connected"
              end if
            else if actionName is "disconnect" then
              if isOn is 1 then
                click cb
                if leaveOpen is false then key code 53
                return "disconnected"
              else
                if leaveOpen is false then key code 53
                return "already-disconnected"
              end if
            end if
          end tell
        end tell
        """
    }

    public static func panelBounds() -> String {
        """
        tell application "System Events" to tell process "ControlCenter"
          set p to position of window 1
          set s to size of window 1
          return (item 1 of p as text) & "," & (item 2 of p as text) & "," & (item 1 of s as text) & "," & (item 2 of s as text)
        end tell
        """
    }

    public static func closePanel() -> String {
        """
        tell application "System Events" to key code 53
        """
    }

    public static func appleString(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
}

public enum NativeAirPlay {
    /// AVRoutePickerView can only present a picker. It has no API to select a named AirPlay target from a process.
    public static func isHeadlessSelectionAvailable() -> Bool {
        #if os(macOS)
        return MacNativeAirPlayProbe.available
        #else
        return false
        #endif
    }
}

#if os(macOS)
import AVKit

enum MacNativeAirPlayProbe {
    static var available: Bool {
        _ = AVRoutePickerView.self
        return false
    }
}
#endif
