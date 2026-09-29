# NimbleTask v1.1 — Functional Spec

## File format

Plain text, UTF-8. Four line types, identified by the first non-whitespace character:

| Prefix | Type | Example |
|---|---|---|
| `* ` | **Area** (optional grouping above projects) | `* Work` |
| `…:` (line ending in colon) | **Project** | `Homelab:` |
| `- ` | **Task** | `- Fix QEMU guest agent @proxmox` |
| *(anything else)* | **Note** (belongs to the enclosing project, not to any task) | `blocked on DNS TXT record` |

Tags (`@tag`) can appear anywhere on a line. A tag is a whitespace-delimited word starting with `@` followed by letters, digits, or `_` (so `@home` never matches inside `@homework`, and `user@example.com` is not a tag). A parenthesized value is tolerated when removing `@done(…)`.

Blank lines are preserved in edit mode and in project view, and ignored in search/tag filter views.

**Scoping rules:**

- An **area** scopes all projects below it until the next area or end of file.
- A **project** scopes all tasks and notes below it until the next project, next area, or end of file.
- Tasks and notes appearing **before the first project** are "loose" (inbox-style) and belong to no project.
- Tasks/notes between an area header and its first project belong directly to the area ("area-loose").

## File types

- Opens and saves `.taskpaper` (declared as imported UTI `com.taskpaper.text`, conforming to `public.plain-text`) and any plain-text file.
- New documents default to the TaskPaper type.

## File menu

Standard SwiftUI `DocumentGroup` behavior: **New** (⌘N), **Open…** (⌘O), **Open Recent**, **Close** (⌘W), **Save** (⌘S), **Save As…** (⇧⌘S), **Duplicate**, **Revert To**, **Move To**, **Rename**.

## Window management & session restore

Multi-window; each open file has its own filter/search state. Closing the last window does not quit the app.

On quit, the app saves security-scoped bookmarks for all open file-backed documents (requires the `com.apple.security.files.bookmarks.app-scope` entitlement). On the next plain launch (not via double-clicking a file, and not already covered by system window restoration) it reopens them and closes the leftover untitled window if untouched. Launching the app by opening a specific file discards the saved session.

## Filter bars

- **Tag bar** — one pill per tag in the document, with a count of lines carrying that tag. Multiple pills can be active at once (AND semantics). Shown only when the document contains tags.
- **Project bar** — one pill per project. At most one active. Shown only when the document contains projects.
- **Search field** — case-insensitive substring match.
- All three combine. A pill whose tag/project disappears from the document is deactivated automatically.
- Active pills use the accent color (Nimble Blue `#009AD6`, see the Nimble Icons style guide v2) with white text; inactive pills use the accent at 15% opacity.

## Task menu

A **Task** menu lists **Toggle @done** (⌘D) and **Toggle @today** (⌘T), so the shortcuts are discoverable. Items are disabled when no document window is focused.

## Keyboard

- **⌘F** — focus the search field from anywhere in the window.
- **⌘D** — toggle `@done` on the task/note line containing the caret (works in edit mode and in filtered views; beeps on headers/blank lines). Adding trims trailing whitespace, then appends a space and the tag. Removes an existing `@done` or `@done(value)` tag.
- **⌘T** — toggle `@today`, same rules as ⌘D.
- **Esc** — clear all filters (search + pills) from anywhere in the window and focus the editor. (Cursor position is not restored — SwiftUI `TextEditor` does not expose it.)

## Filtered views (editable)

### Project view (project pill only, no search/tags)

Shows the project's full block verbatim — header, tasks, notes, blank lines — fully editable. This is the primary editing surface while filtered; new lines are created by pressing Enter at the end of any existing line. Renaming the project header line keeps the view following the renamed project (if the line stops being a project, the filter clears).

### Search / tag view

Matching lines grouped by structural parent, in file order:

1. **Loose section** (no header) — matching loose tasks/notes.
2. **Area-less projects** — project header shown verbatim, matching items beneath.
3. **Each area with a match** — area header, then matching area-loose items, then matching projects (blank-line-separated).

Match rules:

- A matching task/note pulls in its project header (and area header) for context, even if the headers don't match.
- A matching project or area header appears even if none of its children match (including areas with no content at all).
- Tag pills require the item line to carry **all** active tags (exact tag match, not substring). Header lines are matched by search text only.

Editing rules (the view maps every rendered line back to its document line):

- Edits to visible lines apply to the document; hidden lines are never touched. A structural edit that would span hidden document lines (e.g. selecting across two groups and deleting) is refused with a beep rather than destroying the hidden lines.
- Editing a line so it no longer matches the filter makes it drop out of the view (the edit is kept).
- New lines typed while tag pills are active automatically inherit the active tags, so they stay visible.
- Creating new lines is reliable in project view; under a text search, a new line that doesn't contain the search term will vanish from view (it is still inserted after the nearest preceding visible line).

## Undo

Full undo **and redo** of all edits (typing, filtered edits, ⌘D, ⌘T), registered per change on the window's undo manager.

## Out of scope

Syntax highlighting / dimming of `@done` lines (would require replacing `TextEditor` with an `NSTextView` wrapper), nested projects, preferences window, restoring cursor position after Esc.
