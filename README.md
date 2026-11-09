# NimbleTask

**A minimal TaskPaper-style to-do editor for macOS. Your tasks are a plain text file.**

No database, no account, no sync service. Write your list in a text file you can keep anywhere and still read in 20 years. Existing TaskPaper files open as they are.

![NimbleTask window with tag and project filters](Screenshot%202026-09-29%20at%2009.29.33.png)

> Free and open source (GPL-3.0). Part of [Nimble Apps](https://nimbleapps.ch).

## The format

```
* Work
Website Redesign:
- Pick a font @design
- Reply to Marcus about the budget @email @waiting

* Home
Apartment:
- Call the plumber @today
```

- `* Work` is an area
- `Project:` (ending with a colon) is a project
- `- Something` is a task
- `@anything` is a tag

More examples are in [`samples/`](samples/).

## Features

- **Filter pills** for every tag and project at the top of the window. Combine tags to narrow the list, or type in search.
- **Edit while filtered.** New tasks pick up the tags you're filtering by, so they don't disappear.
- **Reopens your files** on the next launch, with as many windows as you like.
- Works with files in iCloud Drive, Dropbox or any folder.

| Shortcut | Action |
|---|---|
| ⌘D | Toggle `@done` |
| ⌘T | Toggle `@today` |
| ⌘F | Search |
| Esc | Clear all filters |
| ⌘Z | Undo |

## Requirements

- macOS 15.6 or later

## Install

[Download NimbleTask on the Mac App Store](https://apps.apple.com/app/nimble-task/id6761774816). It's free. More on [nimbleapps.ch](https://nimbleapps.ch/nimbletask/index.html).

## Build from source

You need Xcode.

```sh
git clone https://github.com/backpedal272/NimbleTask.git
cd NimbleTask
open NimbleTask/NimbleTask.xcodeproj
```

Then choose **Product › Run**. To run it signed on your own Mac, pick your team under **Signing & Capabilities**.

## Contributing

Bug reports and suggestions are welcome in [Issues](https://github.com/backpedal272/NimbleTask/issues). Contact: info@nimbleapps.ch.

## License

GPL-3.0. See [LICENSE](LICENSE).

TaskPaper is a product of Hog Bay Software. This project is not affiliated with it; it only reads and writes the same plain-text format.
