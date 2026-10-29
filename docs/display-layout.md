# Display layout

`display layout` renders a JSON spec into a 16:9 page. These pictures are headless renders at 1920×1080. They do not use a physical display.

## Command flow

```mermaid
flowchart TD
  spec[JSON spec] --> validate[Validate]
  validate -->|empty or invalid| fail[Exit 1. Screen unchanged]
  validate -->|valid| render[Render HTML]
  render --> show[Wake, reconnect target, full screen]
  show --> verify[Hash, target screen, full screen]
  verify -->|all match| ok[Exit 0. verified true]
  verify -->|failed step| mismatch[Non-zero. Step named]
```

An empty file, invalid JSON, unknown theme, unknown module, or blank field stops at validate. The current page stays in place.

## Token scale

Type sizes are vh. Steps from `xs` through `l` are 1.5 times the previous step. `xl` is 8vh. `xxl` is 12vh, 1.5 times `xl`.

```mermaid
flowchart LR
  xs["type xs 1.6vh"] -->|1.5x| s["type s 2.4vh"] -->|1.5x| m["type m 3.6vh"] -->|1.5x| l["type l 5.4vh"] --> xl["type xl 8vh"] -->|1.5x| xxl["type xxl 12vh"]
```

Space tokens. `l` is the grid gap. `xl` is the page margin.

```mermaid
flowchart LR
  xs["space xs 0.8vh"] --> s["space s 1.6vh"] --> m["space m 2.4vh"] --> l["space l 4vh gap"] --> xl["space xl 6vh margin"]
```

CSS names are `--type-xs` through `--type-xxl` and `--space-xs` through `--space-xl`.

## Module catalog

```mermaid
classDiagram
  class Page {
    title
    theme optional
    modules
  }
  class header {
    title
    subtitle optional
    size optional
  }
  class message {
    text
    size optional
  }
  class columns {
    columns
    size optional
  }
  class list {
    items
    title optional
    size optional
  }
  class summary {
    label
    value
    detail optional
    size optional
  }
  class alert {
    text
    title optional
    level optional
    size optional
  }
  Page --> header
  Page --> message
  Page --> columns
  Page --> list
  Page --> summary
  Page --> alert
```

A column has an optional `title` and `items`. A list or column item is `{ "leading", "text" }` or a string used as `text`. Alert `level` is `info`, `warning`, or `critical`. `size` is a type token.

## Themes

The same reminder on `default` and `moonlit-autumn`.

| Default | Moonlit autumn |
| --- | --- |
| ![One-line reminder, default theme](images/reminder-default.png) | ![One-line reminder, moonlit autumn theme](images/reminder-moonlit.png) |

The same schedule on both themes.

| Default | Moonlit autumn |
| --- | --- |
| ![Schedule, default theme](images/schedule-default.png) | ![Schedule, moonlit autumn theme](images/schedule-moonlit.png) |

## Pages

One-line reminder. One message block fills the canvas.

![One-line reminder](images/reminder-default.png)

Multi-section schedule. Header, two columns, and a summary share the page.

![Multi-section schedule](images/schedule-moonlit.png)

Alert. A warning and a critical alert each take a slot under a header.

![Alert](images/alert.png)

List and summary.

![List and summary](images/list-summary.png)

## Blocks fill the grid

Each block is `flex: 1`. Rows use `grid-auto-rows: minmax(0, 1fr)` and `gap: var(--space-l)`. Adding a block shortens the others. Nothing is left over.

| 1 block | 2 blocks |
| --- | --- |
| ![One block](images/grid-1.png) | ![Two blocks](images/grid-2.png) |

| 3 blocks | 4 blocks |
| --- | --- |
| ![Three blocks](images/grid-3.png) | ![Four blocks](images/grid-4.png) |

## Grid overlay

The red band is the page margin, `space-xl` (6vh). The amber bands are the grid gaps, `space-l` (4vh). The blue outlines are the slots.

![Grid overlay](images/grid-debug.png)
