import Foundation

public enum DisplayLayout {
    public static let reminderSpec = """
    {
      "title": "Reminder",
      "theme": "default",
      "modules": [
        {
          "type": "message",
          "text": "Example reminder"
        }
      ]
    }
    """

    public static let scheduleSpec = """
    {
      "title": "Example day",
      "theme": "moonlit-autumn",
      "modules": [
        {
          "type": "header",
          "title": "Example day",
          "subtitle": "Placeholder"
        },
        {
          "type": "columns",
          "columns": [
            {
              "title": "Morning",
              "items": [
                { "leading": "09:00", "text": "Example item" },
                { "leading": "10:30", "text": "Example item" }
              ]
            },
            {
              "title": "Afternoon",
              "items": [
                { "leading": "13:00", "text": "Example meeting" },
                { "leading": "16:00", "text": "Example item" }
              ]
            }
          ]
        },
        {
          "type": "summary",
          "label": "Next",
          "value": "Example item",
          "detail": "09:00"
        }
      ]
    }
    """

    public static func render(json: String, theme themeOverride: String? = nil, baseDirectory: String? = nil) throws -> String {
        try render(page: try page(json: json, theme: themeOverride), baseDirectory: baseDirectory)
    }

    public static func render(page: DisplayPage, baseDirectory: String? = nil) throws -> String {
        let theme = try DisplayThemes.named(page.themeID)
        return try render(page: page, theme: theme, baseDirectory: baseDirectory)
    }

    public static func render(page: DisplayPage, theme: DisplayTheme, baseDirectory: String? = nil) throws -> String {
        let modules = try page.blocks.map { try DisplayModuleHTML.render($0, baseDirectory: baseDirectory) }.joined()
        let title = DisplayRendering.escape(page.title)
        let names = DisplayTypeToken.allCases.map { "\"\($0.rawValue)\"" }.joined(separator: ",")
        return """
        <!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>\(title)</title><style>
        \(DisplayTokens.rootCSS())
        \(layoutCSS)
        \(theme.css())
        </style></head><body><div class="stage" data-theme="\(DisplayRendering.escape(theme.id))"><div class="page">\(modules)</div></div><script>
        \(fitScript(names))
        </script></body></html>
        """
    }

    static func page(json: String, theme themeOverride: String?) throws -> DisplayPage {
        let trimmed = json.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw HomeSignalError.displayRefusal("Layout spec is empty.")
        }
        let dto: LayoutSpecDTO
        do {
            dto = try JSONDecoder().decode(LayoutSpecDTO.self, from: Data(trimmed.utf8))
        } catch {
            throw HomeSignalError.displayRefusal("Layout spec is invalid.")
        }
        let title = dto.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !title.isEmpty else {
            throw HomeSignalError.displayRefusal("Layout spec needs a title.")
        }
        let themeID = try themeID(specified: dto.theme, override: themeOverride)
        guard let modules = dto.modules, !modules.isEmpty else {
            throw HomeSignalError.displayRefusal("Layout spec needs at least one module.")
        }
        let blocks = try modules.enumerated().map { index, module in
            try LayoutModuleParser.block(module, index: index + 1)
        }
        return try DisplayPage(title: title, themeID: themeID, blocks: blocks)
    }

    private static func themeID(specified: String?, override: String?) throws -> String {
        if let override {
            let name = override.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else {
                throw HomeSignalError.displayRefusal("Theme name is empty.")
            }
            return name
        }
        if let specified {
            let name = specified.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else {
                throw HomeSignalError.displayRefusal("Layout spec theme is empty.")
            }
            return name
        }
        return DisplayThemes.defaultID
    }

    private static let layoutCSS = """
    *{box-sizing:border-box}
    html,body{margin:0;height:100%;overflow:hidden}
    body{display:flex;align-items:center;justify-content:center}
    .stage{aspect-ratio:16/9;width:min(100vw,calc(100vh * 16 / 9));height:min(100vh,calc(100vw * 9 / 16));box-sizing:border-box;display:flex;flex-direction:column;overflow:hidden;padding:var(--space-xl);background:var(--background);color:var(--foreground);font-family:var(--font);font-weight:500;line-height:1.15}
    .page{flex:1;min-height:0;display:grid;grid-template-columns:1fr;grid-auto-rows:minmax(0,1fr);gap:var(--space-l)}
    .block{flex:1;min-height:0;min-width:0;display:flex;flex-direction:column;overflow:hidden}
    .fit{min-height:0;min-width:0;overflow:hidden;display:flex;align-items:center;justify-content:center;font-size:var(--fit-max,var(--type-l))}
    .fit.grow{flex:1;width:100%}
    .rows{flex:1;min-height:0;margin:0;padding:0;list-style:none;display:flex;flex-direction:column;gap:var(--space-s);font-size:var(--fit-max,var(--type-m));overflow:hidden}
    .row{flex:1;min-height:0;min-width:0;display:flex;align-items:center;overflow:hidden}
    .cols{flex:1;min-height:0;display:grid;grid-auto-flow:column;grid-auto-columns:minmax(0,1fr);gap:var(--space-l)}
    .col{min-width:0;min-height:0;display:flex;flex-direction:column;gap:var(--space-s);overflow:hidden}
    h1,h2,p{margin:0;font:inherit;font-weight:600;overflow-wrap:anywhere}
    .kicker{color:var(--muted);font-size:var(--type-s);font-weight:500}
    .heading{flex:0 0 auto;font-size:var(--type-m);font-weight:600}
    .col-title{flex:0 0 auto;font-size:var(--type-m);font-weight:600;color:var(--accent)}
    .leading{flex:0 0 auto;color:var(--accent)}
    .text{flex:1;min-width:0}
    .inner{max-width:100%;white-space:pre-wrap;overflow-wrap:anywhere}
    .inner.center{display:flex;flex-direction:column;align-items:center;justify-content:center;gap:var(--space-s);text-align:center;width:100%}
    .inner.start{display:flex;flex-direction:row;align-items:center;justify-content:flex-start;gap:var(--space-m);text-align:left;width:100%}
    .block[data-module="alert"]{background:var(--surface);box-shadow:inset 0.5vh 0 0 var(--accent);padding:0 var(--space-m)}
    .block[data-module="alert"][data-level="warning"]{box-shadow:inset 0.5vh 0 0 var(--alert)}
    .block[data-module="alert"][data-level="critical"]{background:var(--alert);color:var(--alert-foreground);box-shadow:none}
    .block[data-module="alert"][data-level="critical"] .kicker{color:var(--alert-foreground)}
    .embed{flex:1;min-height:0;min-width:0;width:100%;border:0;overflow:hidden;background:transparent}
    .media-slot{flex:1;min-height:0;min-width:0;overflow:hidden;display:flex}
    .media{width:100%;height:100%;object-fit:contain}
    .media[data-fit="cover"]{object-fit:cover}
    .caption{flex:0 0 auto;margin:0;text-align:center;color:var(--muted);font-size:var(--type-s);font-weight:500}
    """

    private static func fitScript(_ names: String) -> String {
        """
        (function(){
        var names=[\(names)];
        function stepSize(name){return parseFloat(getComputedStyle(document.documentElement).getPropertyValue("--type-"+name))}
        function overflows(el){
          if(el.clientHeight<1||el.clientWidth<1) return false;
          var nodes=el.querySelectorAll(".inner");
          for(var i=0;i<nodes.length;i++){
            var box=nodes[i].parentElement;
            if(!box||box.clientHeight<1) continue;
            if(nodes[i].scrollHeight>box.clientHeight+1||nodes[i].scrollWidth>box.clientWidth+1) return true;
          }
          return false;
        }
        function fit(){
          var nodes=document.querySelectorAll("[data-fit]");
          for(var i=0;i<nodes.length;i++){
            var el=nodes[i];
            if(!overflows(el)) continue;
            var max=names.indexOf(el.getAttribute("data-fit"));
            if(max<0) max=names.length-1;
            for(var step=max; step>=0; step--){
              var size=stepSize(names[step]);
              if(!size) continue;
              el.style.fontSize=size+"vh";
              if(!overflows(el)) break;
            }
          }
        }
        fit();
        requestAnimationFrame(fit);
        window.addEventListener("resize",fit);
        })();
        """
    }
}
