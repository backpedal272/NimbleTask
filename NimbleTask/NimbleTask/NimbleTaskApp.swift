//
//  NimbleTaskApp.swift
//  NimbleTask
//
//  Created by alain on 06.04.2026.
//

import SwiftUI
import AppKit

@main
struct NimbleTaskApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        DocumentGroup(newDocument: { TaskPaperDocument() }) { file in
            ContentView(document: file.document)
        }
        .commands {
            TaskCommands()
        }
    }
}

// MARK: - Task menu
//
// The toggle logic lives in ContentView (it needs the editor's selection), so
// the focused window publishes it via `focusedSceneValue` and the menu calls it.

struct TaskActions {
    let toggleTag: (String) -> Void
}

private struct TaskActionsKey: FocusedValueKey {
    typealias Value = TaskActions
}

extension FocusedValues {
    var taskActions: TaskActions? {
        get { self[TaskActionsKey.self] }
        set { self[TaskActionsKey.self] = newValue }
    }
}

struct TaskCommands: Commands {
    @FocusedValue(\.taskActions) private var actions

    var body: some Commands {
        CommandMenu("Task") {
            Button("Toggle @done") { actions?.toggleTag("@done") }
                .keyboardShortcut("d", modifiers: .command)
                .disabled(actions == nil)
            Button("Toggle @today") { actions?.toggleTag("@today") }
                .keyboardShortcut("t", modifiers: .command)
                .disabled(actions == nil)
        }
    }
}

// MARK: - Session persistence
//
// Remembers which documents were open at quit time and reopens them on the
// next launch (when the user launches the app fresh, not by double-clicking a
// file). Uses security-scoped bookmarks (requires the
// com.apple.security.files.bookmarks.app-scope entitlement) so it keeps
// working under sandboxing and if the file has moved.
//
// Note: we deliberately do NOT implement application(_:openFile:) /
// application(_:openFiles:). Implementing them takes over open-file events
// from NSDocumentController, and unless we open the files ourselves the
// events are swallowed — Finder double-clicks would silently do nothing.

final class AppDelegate: NSObject, NSApplicationDelegate {
    private static let bookmarksKey = "ReopenDocumentBookmarks"

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Give AppKit a moment to process open-file events that arrived with
        // launch and to run system window restoration. If either produced a
        // file-backed document, our saved session is superseded.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            guard let self else { return }
            let hasFileBackedDocuments = NSDocumentController.shared.documents
                .contains { $0.fileURL != nil }
            if hasFileBackedDocuments {
                UserDefaults.standard.removeObject(forKey: Self.bookmarksKey)
            } else {
                self.restoreSession()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        saveSession()
    }

    // MARK: - Save / restore

    private func saveSession() {
        let urls = NSDocumentController.shared.documents.compactMap { $0.fileURL }
        let bookmarks: [Data] = urls.compactMap { url in
            try? url.bookmarkData(
                options: [.withSecurityScope],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
        }
        if bookmarks.isEmpty {
            UserDefaults.standard.removeObject(forKey: Self.bookmarksKey)
        } else {
            UserDefaults.standard.set(bookmarks, forKey: Self.bookmarksKey)
        }
    }

    private func restoreSession() {
        guard let bookmarks = UserDefaults.standard.array(forKey: Self.bookmarksKey) as? [Data],
              !bookmarks.isEmpty else { return }

        // Clear immediately so a crash mid-restore doesn't keep us in a loop.
        UserDefaults.standard.removeObject(forKey: Self.bookmarksKey)

        let controller = NSDocumentController.shared
        for data in bookmarks {
            var isStale = false
            guard let url = try? URL(
                resolvingBookmarkData: data,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) else { continue }

            // Already open (e.g. system restoration raced us) — skip.
            guard controller.document(for: url) == nil else { continue }

            let didStart = url.startAccessingSecurityScopedResource()
            controller.openDocument(withContentsOf: url, display: true) { _, _, _ in
                if didStart { url.stopAccessingSecurityScopedResource() }
                self.closeEmptyUntitledDocuments()
            }
        }
    }

    /// After restoring a session, the untitled document DocumentGroup opened
    /// at launch is just clutter — close it if the user hasn't typed in it.
    private func closeEmptyUntitledDocuments() {
        for doc in NSDocumentController.shared.documents
        where doc.fileURL == nil && !doc.isDocumentEdited {
            doc.close()
        }
    }
}
