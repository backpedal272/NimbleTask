import SwiftUI
import AppKit

// MARK: - NSWindow bridge

/// Suppresses the title-bar document proxy popover (rename / move / tags
/// dropdown) so the title bar shows only the filename — no chevron, no proxy
/// icon, nothing clickable. We have to keep re-applying because `DocumentGroup`
/// re-sets `representedURL` / `representedFilename` on save, rename, etc.
private struct TitleMenuSuppressor: NSViewRepresentable {
    final class Coordinator {
        var urlObservation: NSKeyValueObservation?
        var titleObservation: NSKeyValueObservation?
        var isApplying = false
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { [weak view] in
            guard let window = view?.window else { return }
            let coordinator = context.coordinator

            let apply: (NSWindow) -> Void = { win in
                guard !coordinator.isApplying else { return }
                coordinator.isApplying = true
                defer { coordinator.isApplying = false }

                if win.representedURL != nil {
                    win.representedURL = nil
                }
                if !win.representedFilename.isEmpty {
                    win.representedFilename = ""
                }
                // Hides the proxy icon / disclosure chevron that opens the
                // Name / Tags / Where popover.
                win.standardWindowButton(.documentIconButton)?.isHidden = true
            }

            apply(window)
            coordinator.urlObservation = window.observe(\.representedURL) { win, _ in
                apply(win)
            }
            coordinator.titleObservation = window.observe(\.title) { win, _ in
                apply(win)
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

// MARK: - TaskPaper parser

/// A document line together with its position in the document, so filtered
/// views can map every rendered line back to its source without re-matching
/// text (which mis-binds duplicate lines).
private struct DocLine {
    var text: String
    var index: Int
}

private struct ParsedGroup {
    var area: DocLine?
    var project: DocLine?
    var items: [DocLine]
}

private struct ParsedDocument {
    var lines: [String] = []
    var groups: [ParsedGroup] = []
    /// Unique project header lines, in file order.
    var projects: [String] = []
    /// Unique tags, sorted.
    var tags: [String] = []
    /// Tag → number of lines carrying it.
    var tagCounts: [String: Int] = [:]
}

/// Extracts @tags from a line via whitespace tokenization: `@home` never
/// matches inside `@homework`, and `user@example.com` is not a tag.
private func lineTags(_ line: String) -> Set<String> {
    var tags: Set<String> = []
    for word in line.components(separatedBy: .whitespaces) {
        guard word.hasPrefix("@") else { continue }
        let body = word.dropFirst().prefix(while: { $0.isLetter || $0.isNumber || $0 == "_" })
        guard !body.isEmpty else { continue }
        tags.insert("@" + body)
    }
    return tags
}

private func parseDocument(_ text: String) -> ParsedDocument {
    var doc = ParsedDocument()
    doc.lines = text.components(separatedBy: "\n")

    var currentArea: DocLine? = nil
    var currentProject: DocLine? = nil
    var items: [DocLine] = []
    var currentAreaHasGroup = false
    var seenProjects = Set<String>()

    func flush() {
        if currentProject != nil || !items.isEmpty {
            doc.groups.append(ParsedGroup(area: currentArea, project: currentProject, items: items))
            items = []
            currentAreaHasGroup = true
        }
    }

    // Areas with no content still get an (empty) group, so searching an
    // empty area's name can find its header line.
    func closeArea() {
        if let area = currentArea, !currentAreaHasGroup {
            doc.groups.append(ParsedGroup(area: area, project: nil, items: []))
        }
    }

    for (idx, line) in doc.lines.enumerated() {
        for tag in lineTags(line) {
            doc.tagCounts[tag, default: 0] += 1
        }
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { continue }
        if trimmed.hasPrefix("* ") {
            flush()
            closeArea()
            currentProject = nil
            currentArea = DocLine(text: line, index: idx)
            currentAreaHasGroup = false
        } else if trimmed.hasSuffix(":") {
            flush()
            currentProject = DocLine(text: line, index: idx)
            if seenProjects.insert(line).inserted {
                doc.projects.append(line)
            }
        } else {
            items.append(DocLine(text: line, index: idx))
        }
    }
    flush()
    closeArea()

    doc.tags = doc.tagCounts.keys.sorted()
    return doc
}

/// Memoizes the parse per document text, so pills, counts, and filters all
/// share one parse per edit instead of re-parsing on every property access.
/// Held in @State (never published — it's a pure cache).
private final class ParseCache {
    private var lastText: String?
    private var lastResult: ParsedDocument?

    func parsed(for text: String) -> ParsedDocument {
        if text == lastText, let cached = lastResult { return cached }
        let result = parseDocument(text)
        lastText = text
        lastResult = result
        return result
    }
}

private struct FilteredView {
    var text: String
    var lineMap: [Int: Int]  // filtered line index → document line index
}

// MARK: - Tag Pill

private struct TagPill: View {
    let tag: String
    var count: Int? = nil
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(tag)
                if let count {
                    Text("\(count)")
                        .foregroundStyle(isActive ? Color.white.opacity(0.75) : Color.secondary)
                }
            }
            .font(.system(.caption, design: .monospaced))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            // Accent is Nimble Blue (#009AD6 sRGB, see style guide); inactive pills use a dimmed tint of it.
            .background(isActive ? Color.accentColor : Color.accentColor.opacity(0.15))
            .foregroundColor(isActive ? .white : .primary)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - View

struct ContentView: View {
    @ObservedObject var document: TaskPaperDocument
    @Environment(\.undoManager) private var undoManager
    @State private var cache = ParseCache()
    @State private var searchText: String = ""
    @State private var activeTags: Set<String> = []
    @State private var activeProject: String? = nil
    @State private var selection: TextSelection? = nil
    @FocusState private var searchFocused: Bool
    @FocusState private var editorFocused: Bool

    private var parsed: ParsedDocument { cache.parsed(for: document.text) }
    private var allProjects: [String] { parsed.projects }
    private var allTags: [String] { parsed.tags }

    private var textBinding: Binding<String> {
        Binding(
            get: { document.text },
            set: { [weak document] newValue in
                document?.setText(newValue, undoManager: undoManager)
            }
        )
    }

    private var isFiltering: Bool {
        !searchText.isEmpty || !activeTags.isEmpty || activeProject != nil
    }

    private func clearFilter() {
        searchText = ""
        activeTags = []
        activeProject = nil
    }

    var body: some View {
        VStack(spacing: 0) {
            // Tag bar — shown when the document contains any @tags
            if !allTags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(allTags, id: \.self) { tag in
                            TagPill(tag: tag, count: parsed.tagCounts[tag], isActive: activeTags.contains(tag)) {
                                if activeTags.contains(tag) {
                                    activeTags.remove(tag)
                                } else {
                                    activeTags.insert(tag)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                }
                .background(.bar)

                Divider()
            }

            // Project bar — shown when the document contains any projects
            if !allProjects.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(allProjects, id: \.self) { project in
                            let label = String(project.trimmingCharacters(in: .whitespaces).dropLast())
                            TagPill(tag: label, isActive: activeProject == project) {
                                activeProject = activeProject == project ? nil : project
                            }
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                }
                .background(.bar)

                Divider()
            }

            // Search field
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Filter (type to search, Esc to clear)", text: $searchText)
                    .textFieldStyle(.plain)
                    .focused($searchFocused)
                    .onKeyPress(.escape) {
                        clearFilter()
                        editorFocused = true
                        return .handled
                    }
                if isFiltering {
                    Button {
                        clearFilter()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
            .background(.bar)

            Divider()

            // Main content: editor if no filter active, filtered view otherwise
            if !isFiltering {
                TextEditor(text: textBinding, selection: $selection)
                    .font(.system(.body, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .padding(4)
                    .focused($editorFocused)
            } else {
                TextEditor(text: filteredTextBinding, selection: $selection)
                    .font(.system(.body, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .padding(4)
                    .focused($editorFocused)
            }

            // Invisible buttons providing window-wide keyboard shortcuts
            Group {
                Button("Focus Search Field") { searchFocused = true }
                    .keyboardShortcut("f", modifiers: .command)
                if isFiltering {
                    Button("Clear Filter") {
                        clearFilter()
                        editorFocused = true
                    }
                    .keyboardShortcut(.escape, modifiers: [])
                }
            }
            .accessibilityHidden(true)
            .opacity(0)
            .frame(width: 0, height: 0)
            .clipped()
        }
        .frame(minWidth: 500, minHeight: 400)
        .background(TitleMenuSuppressor())
        .focusedSceneValue(\.taskActions, TaskActions(toggleTag: toggleTag))
        .onChange(of: document.text) { _, newText in
            // Drop filter state that no longer exists in the document (e.g. a
            // project renamed in edit mode while its pill was active), so the
            // user is never stuck on an empty filter with no visible pill.
            let parsed = cache.parsed(for: newText)
            if let ap = activeProject, !parsed.projects.contains(ap) {
                activeProject = nil
            }
            if !activeTags.isEmpty {
                let available = Set(parsed.tags.map { $0.lowercased() })
                activeTags = activeTags.filter { available.contains($0.lowercased()) }
            }
        }
    }

    // MARK: - Tag toggling (@done, @today)

    /// Line index (in the currently displayed text) containing the caret.
    private func selectedLineIndex(in viewText: String) -> Int? {
        guard let sel = selection else { return nil }
        let caret: String.Index
        switch sel.indices {
        case .selection(let range):
            caret = range.lowerBound
        case .multiSelection(let ranges):
            guard let first = ranges.ranges.first else { return nil }
            caret = first.lowerBound
        @unknown default:
            return nil
        }
        let clamped = min(caret, viewText.endIndex)
        var count = 0
        var idx = viewText.startIndex
        while idx < clamped && idx < viewText.endIndex {
            if viewText[idx] == "\n" { count += 1 }
            idx = viewText.index(after: idx)
        }
        return count
    }

    /// Adds `tag` (e.g. "@done") to the task line under the caret, or removes it
    /// if already present.
    private func toggleTag(_ tag: String) {
        let view = isFiltering ? filteredView : nil
        let viewText = view?.text ?? document.text
        guard let displayLine = selectedLineIndex(in: viewText) else {
            NSSound.beep()
            return
        }
        let docIdx: Int
        if let view {
            guard let mapped = view.lineMap[displayLine] else {
                NSSound.beep()
                return
            }
            docIdx = mapped
        } else {
            docIdx = displayLine
        }

        var lines = document.text.components(separatedBy: "\n")
        guard docIdx < lines.count else {
            NSSound.beep()
            return
        }
        let line = lines[docIdx]
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("* "), !trimmed.hasSuffix(":") else {
            NSSound.beep()
            return
        }

        if lineTags(line).contains(tag) {
            // Also strips a parenthesized value, e.g. "@done(2026-08-02)".
            let pattern = " ?" + NSRegularExpression.escapedPattern(for: tag) + #"(\([^)]*\))?(?=\s|$)"#
            if let range = line.range(of: pattern, options: .regularExpression) {
                lines[docIdx] = String(line[..<range.lowerBound]) + String(line[range.upperBound...])
            }
        } else {
            // Trim trailing whitespace only; leading indentation is structure.
            var base = Substring(line)
            while let last = base.last, last.isWhitespace { base = base.dropLast() }
            lines[docIdx] = base + " " + tag
        }
        document.setText(lines.joined(separator: "\n"), undoManager: undoManager)
    }

    // MARK: - Structured filter

    private var filteredTextBinding: Binding<String> {
        Binding(
            get: { filteredView.text },
            set: { applyFilteredEdit($0) }
        )
    }

    private func applyFilteredEdit(_ newText: String) {
        let view = filteredView
        guard newText != view.text else { return }

        let oldLines = view.text.components(separatedBy: "\n")
        let newLines = newText.components(separatedBy: "\n")
        var docLines = document.text.components(separatedBy: "\n")

        // Find the changed range via common prefix + suffix
        var lo = 0
        while lo < oldLines.count && lo < newLines.count && oldLines[lo] == newLines[lo] { lo += 1 }
        var oldHi = oldLines.count - 1
        var newHi = newLines.count - 1
        while oldHi >= lo && newHi >= lo && oldLines[oldHi] == newLines[newHi] { oldHi -= 1; newHi -= 1 }

        guard lo <= oldHi || lo <= newHi else { return }

        let removedFiltIndices = oldHi >= lo ? Array(lo...oldHi) : []
        var insertedLines = newHi >= lo ? Array(newLines[lo...newHi]) : []
        let docIndices = removedFiltIndices.compactMap { view.lineMap[$0] }.sorted()

        // In pure project view the header is filtered line 0; remember it so
        // a rename can carry the filter along instead of stranding it.
        let isPureProjectView = activeProject != nil && activeTags.isEmpty && searchText.isEmpty
        let headerDocIndex = isPureProjectView ? view.lineMap[0] : nil

        // New lines typed while a tag filter is active inherit the active
        // tags, so they stay visible and actually carry the tag in view.
        func withActiveTags(_ line: String) -> String {
            guard !activeTags.isEmpty else { return line }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("* "), !trimmed.hasSuffix(":") else { return line }
            let present = Set(lineTags(line).map { $0.lowercased() })
            var result = line
            for tag in activeTags.sorted() where !present.contains(tag.lowercased()) {
                result += " " + tag
            }
            return result
        }

        if docIndices.isEmpty {
            // Pure insertion (e.g. Enter at end of a line): place the new
            // lines right after the nearest preceding visible line.
            guard !insertedLines.isEmpty else { return }
            var insertAfter = -1
            for i in stride(from: lo - 1, through: 0, by: -1) {
                if let d = view.lineMap[i] { insertAfter = d; break }
            }
            insertedLines = insertedLines.map(withActiveTags)
            docLines.insert(contentsOf: insertedLines, at: insertAfter + 1)
        } else {
            let span = docIndices.first!...docIndices.last!
            if docIndices.count == span.count {
                // The edited region is contiguous in the document — safe to
                // replace as a block.
                docLines.replaceSubrange(span, with: insertedLines)
            } else if removedFiltIndices.count == insertedLines.count {
                // Line-for-line edits across a hidden gap: apply each visible
                // line's change individually, leaving hidden lines untouched.
                for (offset, filtIdx) in removedFiltIndices.enumerated() {
                    if let d = view.lineMap[filtIdx] {
                        docLines[d] = insertedLines[offset]
                    } else if oldLines[filtIdx] != insertedLines[offset] {
                        // Editing a synthetic separator line is ambiguous.
                        NSSound.beep()
                        return
                    }
                }
            } else {
                // A structural change (merge / multi-line delete) spanning
                // hidden document lines would destroy them — refuse.
                NSSound.beep()
                return
            }
        }

        document.setText(docLines.joined(separator: "\n"), undoManager: undoManager)

        // Follow a header rename in project view, or drop the filter if the
        // header line is no longer a project.
        if isPureProjectView, let ap = activeProject, !docLines.contains(ap) {
            if let h = headerDocIndex, h < docLines.count {
                let candidate = docLines[h]
                let t = candidate.trimmingCharacters(in: .whitespaces)
                activeProject = (t.hasSuffix(":") && t.count > 1) ? candidate : nil
            } else {
                activeProject = nil
            }
        }
    }

    // Returns a FilteredView containing all lines of the given project from the
    // document (header + items + empty lines), stopping at the next project or
    // area. Trailing empty lines from the doc are kept and mapped so that
    // typing on them uses replaceSubrange (not insert), avoiding SwiftUI
    // cursor resets. New lines are created by pressing Enter at the end of any
    // existing line.
    private func projectFilteredView(_ ap: String) -> FilteredView {
        let docLines = document.text.components(separatedBy: "\n")
        var lines: [String] = []
        var lineMap: [Int: Int] = [:]
        var inProject = false

        for (idx, line) in docLines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if !inProject {
                if line == ap {
                    inProject = true
                    lineMap[lines.count] = idx
                    lines.append(line)
                }
            } else {
                if !trimmed.isEmpty && (trimmed.hasPrefix("* ") || trimmed.hasSuffix(":")) {
                    break
                }
                lineMap[lines.count] = idx
                lines.append(line)
            }
        }

        return FilteredView(text: lines.joined(separator: "\n"), lineMap: lineMap)
    }

    private var filteredView: FilteredView {
        // When only a project is selected (no text search, no tag filter),
        // show its full content directly so all lines are visible and editable.
        if let ap = activeProject, activeTags.isEmpty && searchText.isEmpty {
            return projectFilteredView(ap)
        }

        let needle = searchText.lowercased()
        let activeTagsLower = Set(activeTags.map { $0.lowercased() })
        let groups = parsed.groups

        // Rendered line + its document index (nil for synthetic separators).
        var sections: [[(text: String, doc: Int?)]] = []

        func itemMatches(_ item: DocLine) -> Bool {
            let lower = item.text.lowercased()
            let textMatch = needle.isEmpty || lower.contains(needle)
            let tagMatch = activeTagsLower.isEmpty
                || activeTagsLower.isSubset(of: Set(lineTags(item.text).map { $0.lowercased() }))
            return textMatch && tagMatch
        }

        // Returns header + matching items if the group has any match, nil
        // otherwise. A header matches on text search only (project names
        // rarely carry @tags); items must satisfy search and tag filter.
        func renderProject(_ group: ParsedGroup) -> [(text: String, doc: Int?)]? {
            guard let header = group.project else { return nil }
            let headerMatches = !needle.isEmpty && header.text.lowercased().contains(needle)
            let matchingItems = group.items.filter { itemMatches($0) }
            guard headerMatches || !matchingItems.isEmpty else { return nil }
            return [(header.text, header.index)] + matchingItems.map { ($0.text, $0.index) }
        }

        // 1. Loose section — tasks/notes before first project, no area
        if activeProject == nil {
            let loose = groups
                .filter { $0.area == nil && $0.project == nil }
                .flatMap { $0.items }
                .filter { itemMatches($0) }
            if !loose.isEmpty {
                sections.append(loose.map { ($0.text, $0.index) })
            }
        }

        // 2. Area-less projects (projects that appear before the first area)
        for group in groups where group.area == nil && group.project != nil {
            if let ap = activeProject, group.project?.text != ap { continue }
            if let s = renderProject(group) {
                sections.append(s)
            }
        }

        // 3. Areas — deduplicated by document position, in file order
        var seenAreaIndices = Set<Int>()
        var areasInOrder: [DocLine] = []
        for group in groups {
            if let area = group.area, seenAreaIndices.insert(area.index).inserted {
                areasInOrder.append(area)
            }
        }

        for area in areasInOrder {
            let areaGroups = groups.filter { $0.area?.index == area.index }
            let areaHeaderMatches = !needle.isEmpty && area.text.lowercased().contains(needle)

            var projectParts: [[(text: String, doc: Int?)]] = []
            for areaGroup in areaGroups where areaGroup.project != nil {
                if let ap = activeProject, areaGroup.project?.text != ap { continue }
                if let s = renderProject(areaGroup) {
                    projectParts.append(s)
                }
            }

            // Items directly under the area header (no project)
            let areaLoose: [DocLine]
            if activeProject == nil {
                areaLoose = areaGroups
                    .filter { $0.project == nil }
                    .flatMap { $0.items }
                    .filter { itemMatches($0) }
            } else {
                areaLoose = []
            }

            guard areaHeaderMatches || !projectParts.isEmpty || !areaLoose.isEmpty else { continue }

            // Area section: header, then loose items, then projects
            // (blank-line-separated).
            var content: [(text: String, doc: Int?)] = [(area.text, area.index)]
            content += areaLoose.map { ($0.text, $0.index) }
            if !projectParts.isEmpty {
                if !areaLoose.isEmpty { content.append(("", nil)) }
                for (i, part) in projectParts.enumerated() {
                    if i > 0 { content.append(("", nil)) }
                    content += part
                }
            }
            sections.append(content)
        }

        // Join sections with a single blank separator line
        var rendered: [(text: String, doc: Int?)] = []
        for (i, section) in sections.enumerated() {
            if i > 0 { rendered.append(("", nil)) }
            rendered += section
        }

        var lineMap: [Int: Int] = [:]
        for (i, line) in rendered.enumerated() {
            if let d = line.doc { lineMap[i] = d }
        }

        return FilteredView(
            text: rendered.map { $0.text }.joined(separator: "\n"),
            lineMap: lineMap
        )
    }
}
