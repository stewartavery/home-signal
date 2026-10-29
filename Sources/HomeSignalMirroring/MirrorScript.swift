public enum MirrorScript {
    public static let library = """
    on safeAttr(el, attrName)
      tell application "System Events"
        try
          set v to value of attribute attrName of el
          if v is missing value then return ""
          return my clean(v as text)
        end try
      end tell
      return ""
    end safeAttr
    on safeProp(el, which)
      tell application "System Events"
        try
          if which is "role" then return my clean(role of el as text)
          if which is "subrole" then return my clean(subrole of el as text)
          if which is "name" then return my clean(name of el as text)
          if which is "desc" then return my clean(description of el as text)
        end try
      end tell
      return ""
    end safeProp
    on clean(t)
      set tabChar to ASCII character 9
      set cr to ASCII character 13
      set lf to ASCII character 10
      set AppleScript's text item delimiters to {tabChar, cr, lf}
      set parts to text items of t
      set AppleScript's text item delimiters to " "
      set t to parts as text
      set AppleScript's text item delimiters to ""
      return t
    end clean
    on lineFor(el, depth)
      set tabChar to ASCII character 9
      set lf to ASCII character 10
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
      return (depth as text) & tabChar & r & tabChar & s & tabChar & i & tabChar & n & tabChar & d & tabChar & v & lf
    end lineFor
    on walk(el, depth, maxDepth, soFar)
      if depth > maxDepth then return soFar
      if (count of soFar) > 20000 then return soFar
      set soFar to soFar & my lineFor(el, depth)
      tell application "System Events"
        try
          set kids to UI elements of el
          repeat with childEl in kids
            set soFar to my walk(childEl, depth + 1, maxDepth, soFar)
          end repeat
        end try
      end tell
      return soFar
    end walk
    on routeRole(roleName)
      if (roleName contains "checkbox") then return true
      if (roleName contains "check box") then return true
      if (roleName contains "radio") then return true
      if (roleName contains "menuitem") then return true
      if (roleName contains "menu item") then return true
      if (roleName contains "button") then return true
      return false
    end routeRole
    on controlRole(roleName)
      if (roleName contains "button") then return true
      if (roleName contains "checkbox") then return true
      if (roleName contains "check box") then return true
      return false
    end controlRole
    """

    public static func dumpMenuBar() -> String {
        library + """

        on run
          set mirrorAction to "dump-menubar"
          set out to ""
          tell application "System Events"
            tell process "ControlCenter"
              repeat with anItem in menu bar items of menu bar 1
                set out to out & my lineFor(anItem, 1)
              end repeat
            end tell
          end tell
          return out
        end run
        """
    }

    public static func clickMenuBar(_ label: String) -> String {
        let wanted = appleString(label)
        return library + """

        on run
          set mirrorAction to "click-menubar"
          set wanted to \(wanted)
          set clicked to false
          tell application "System Events"
            tell process "ControlCenter"
              repeat with anItem in menu bar items of menu bar 1
                set d to my safeProp(anItem, "desc")
                set n to my safeProp(anItem, "name")
                if (d is wanted) or (n is wanted) then
                  click anItem
                  set clicked to true
                  exit repeat
                end if
              end repeat
            end tell
          end tell
          if clicked then
            delay 0.5
            return "clicked"
          end if
          error "menu bar item not found: " & wanted
        end run
        """
    }

    public static func dumpWindow(maxDepth: Int = 6) -> String {
        library + """

        on run
          set mirrorAction to "dump-window"
          set out to ""
          tell application "System Events"
            tell process "ControlCenter"
              set out to my walk(window 1, 1, \(maxDepth), "")
            end tell
          end tell
          return out
        end run
        """
    }

    public static func clickModule(identifier: String, description: String) -> String {
        let ident = appleString(identifier)
        let desc = appleString(description)
        return library + """

        on run
          set mirrorAction to "click-module"
          set wantedID to \(ident)
          set wantedDesc to \(desc)
          set clicked to false
          tell application "System Events"
            tell process "ControlCenter"
              set bits to entire contents of window 1
              repeat with el in bits
                set ident to my safeAttr(el, "AXIdentifier")
                set d to my safeProp(el, "desc")
                set n to my safeProp(el, "name")
                set roleName to my safeProp(el, "role")
                if my controlRole(roleName) then
                  if ((wantedID is not "") and (ident is wantedID)) or ((wantedDesc is not "") and ((d is wantedDesc) or (n is wantedDesc))) then
                    click el
                    set clicked to true
                    exit repeat
                  end if
                end if
              end repeat
            end tell
          end tell
          if clicked then
            delay 0.5
            return "clicked"
          end if
          error "Screen Mirroring module not found"
        end run
        """
    }

    public static func dumpRoutes() -> String {
        library + """

        on run
          set mirrorAction to "dump-routes"
          set out to ""
          tell application "System Events"
            tell process "ControlCenter"
              repeat with w in windows
                try
                  set bits to entire contents of w
                  repeat with el in bits
                    set roleName to my safeProp(el, "role")
                    if my routeRole(roleName) then
                      set out to out & my lineFor(el, 1)
                    end if
                  end repeat
                end try
              end repeat
            end tell
          end tell
          return out
        end run
        """
    }

    public static func clickRoute(_ name: String) -> String {
        let wanted = appleString(name)
        return library + """

        on run
          set mirrorAction to "click-route"
          set wanted to \(wanted)
          set clicked to false
          tell application "System Events"
            tell process "ControlCenter"
              repeat with w in windows
                try
                  set bits to entire contents of w
                  repeat with el in bits
                    set d to my safeProp(el, "desc")
                    set n to my safeProp(el, "name")
                    if (d is wanted) or (n is wanted) then
                      click el
                      set clicked to true
                      exit repeat
                    end if
                  end repeat
                end try
                if clicked then exit repeat
              end repeat
            end tell
          end tell
          if clicked then return "clicked"
          error "AirPlay target not found: " & wanted
        end run
        """
    }

    public static func panelBounds() -> String {
        """
        on run
          set boundsText to ""
          tell application "System Events"
            tell process "ControlCenter"
              set p to position of window 1
              set s to size of window 1
              set boundsText to (item 1 of p as text) & "," & (item 2 of p as text) & "," & (item 1 of s as text) & "," & (item 2 of s as text)
            end tell
          end tell
          return boundsText
        end run
        """
    }

    public static func closePanel() -> String {
        """
        tell application "System Events" to key code 53
        """
    }

    public static var generated: [String] {
        [
            dumpMenuBar(),
            dumpWindow(),
            dumpRoutes(),
            clickMenuBar("Example TV"),
            clickMenuBar("Example's \"TV\""),
            clickModule(identifier: "controlcenter-screen-mirroring", description: "Screen Mirroring"),
            clickModule(identifier: "id'1", description: "Example's \"TV\" (2)"),
            clickRoute("Example TV"),
            clickRoute("Example's \"TV\" (2)"),
            panelBounds(),
            closePanel(),
        ]
    }

    public static func appleString(_ value: String) -> String {
        var escaped = ""
        for character in value {
            switch character {
            case "\\":
                escaped += "\\\\"
            case "\"":
                escaped += "\\\""
            case "\n", "\r", "\t":
                escaped += " "
            default:
                escaped.append(character)
            }
        }
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
