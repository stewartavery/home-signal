public enum MirrorScript {
    public static let library = """
    on safeAttr(el, attrName)
      try
        set v to value of attribute attrName of el
        if v is missing value then return ""
        return clean(v as text)
      end try
      return ""
    end safeAttr
    on safeProp(el, which)
      try
        if which is "role" then return clean(role of el as text)
        if which is "subrole" then return clean(subrole of el as text)
        if which is "name" then return clean(name of el as text)
        if which is "desc" then return clean(description of el as text)
      end try
      return ""
    end safeProp
    on clean(t)
      set AppleScript's text item delimiters to {tab, return, linefeed}
      set parts to text items of t
      set AppleScript's text item delimiters to " "
      set t to parts as text
      set AppleScript's text item delimiters to ""
      return t
    end clean
    on lineFor(el, depth)
      set r to safeProp(el, "role")
      set s to safeProp(el, "subrole")
      set i to safeAttr(el, "AXIdentifier")
      set n to safeProp(el, "name")
      set d to safeProp(el, "desc")
      set v to ""
      try
        set raw to value of el
        if raw is not missing value then set v to clean(raw as text)
      end try
      return (depth as text) & tab & r & tab & s & tab & i & tab & n & tab & d & tab & v & linefeed
    end lineFor
    on walk(el, depth, maxDepth, soFar)
      if depth > maxDepth then return soFar
      if (count of soFar) > 20000 then return soFar
      set soFar to soFar & lineFor(el, depth)
      try
        set kids to UI elements of el
        repeat with childEl in kids
          set soFar to walk(childEl, depth + 1, maxDepth, soFar)
        end repeat
      end try
      return soFar
    end walk
    """

    public static func dumpMenuBar() -> String {
        library + """

        set mirrorAction to "dump-menubar"
        set out to ""
        tell application "System Events"
          tell process "ControlCenter"
            repeat with anItem in menu bar items of menu bar 1
              set out to out & lineFor(anItem, 1)
            end repeat
          end tell
        end tell
        return out
        """
    }

    public static func clickMenuBar(_ label: String) -> String {
        let wanted = appleString(label)
        return library + """

        set mirrorAction to "click-menubar"
        set wanted to \(wanted)
        tell application "System Events"
          tell process "ControlCenter"
            repeat with anItem in menu bar items of menu bar 1
              set d to safeProp(anItem, "desc")
              set n to safeProp(anItem, "name")
              if d is wanted or n is wanted then
                click anItem
                delay 0.5
                return "clicked"
              end if
            end repeat
          end tell
        end tell
        error "menu bar item not found: " & wanted
        """
    }

    public static func dumpWindow(maxDepth: Int = 6) -> String {
        library + """

        set mirrorAction to "dump-window"
        tell application "System Events"
          tell process "ControlCenter"
            return walk(window 1, 1, \(maxDepth), "")
          end tell
        end tell
        """
    }

    public static func clickModule(identifier: String, description: String) -> String {
        let ident = appleString(identifier)
        let desc = appleString(description)
        return library + """

        set mirrorAction to "click-module"
        set wantedID to \(ident)
        set wantedDesc to \(desc)
        tell application "System Events"
          tell process "ControlCenter"
            set bits to entire contents of window 1
            repeat with el in bits
              set ident to safeAttr(el, "AXIdentifier")
              set d to safeProp(el, "desc")
              set n to safeProp(el, "name")
              set roleName to safeProp(el, "role")
              if roleName contains "button" or roleName contains "checkbox" or roleName contains "check box" then
                if (wantedID is not "" and ident is wantedID) or (wantedDesc is not "" and (d is wantedDesc or n is wantedDesc)) then
                  click el
                  delay 0.5
                  return "clicked"
                end if
              end if
            end repeat
          end tell
        end tell
        error "Screen Mirroring module not found"
        """
    }

    public static func dumpRoutes() -> String {
        library + """

        set mirrorAction to "dump-routes"
        set out to ""
        tell application "System Events"
          tell process "ControlCenter"
            repeat with w in windows
              try
                set bits to entire contents of w
                repeat with el in bits
                  set roleName to safeProp(el, "role")
                  if roleName contains "checkbox" or roleName contains "check box" or roleName contains "radio" or roleName contains "menuitem" or roleName contains "menu item" or roleName contains "button" then
                    set out to out & lineFor(el, 1)
                  end if
                end repeat
              end try
            end repeat
          end tell
        end tell
        return out
        """
    }

    public static func clickRoute(_ name: String) -> String {
        let wanted = appleString(name)
        return library + """

        set mirrorAction to "click-route"
        set wanted to \(wanted)
        tell application "System Events"
          tell process "ControlCenter"
            repeat with w in windows
              try
                set bits to entire contents of w
                repeat with el in bits
                  set d to safeProp(el, "desc")
                  set n to safeProp(el, "name")
                  if d is wanted or n is wanted then
                    click el
                    return "clicked"
                  end if
                end repeat
              end try
            end repeat
          end tell
        end tell
        error "AirPlay target not found: " & wanted
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
