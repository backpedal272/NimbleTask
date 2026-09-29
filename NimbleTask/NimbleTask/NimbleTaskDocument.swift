import Combine
import Foundation
import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    /// `.taskpaper` files. Imported (declared in Info.plist) so the Open
    /// panel and Launch Services treat them as text this app can edit —
    /// without this, `.taskpaper` gets a dynamic UTI that does not conform
    /// to `public.plain-text` and is greyed out in the Open panel.
    static let taskPaper = UTType(importedAs: "com.taskpaper.text")
}

final class TaskPaperDocument: ReferenceFileDocument {
    typealias Snapshot = String

    static var readableContentTypes: [UTType] { [.taskPaper, .plainText] }
    static var writableContentTypes: [UTType] { [.taskPaper, .plainText] }

    @Published var text: String = ""

    init() {}

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents,
              let contents = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.text = contents
    }

    func snapshot(contentType: UTType) throws -> String {
        text
    }

    func fileWrapper(snapshot: String, configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(snapshot.utf8))
    }

    /// Single write path for programmatic edits. The undo closure calls back
    /// into this method, which re-registers the inverse operation — that is
    /// what makes redo work (a plain `doc.text = old` closure leaves the
    /// redo stack empty).
    func setText(_ newText: String, undoManager: UndoManager?) {
        let old = text
        guard old != newText else { return }
        text = newText
        undoManager?.registerUndo(withTarget: self) { [weak undoManager] doc in
            doc.setText(old, undoManager: undoManager)
        }
    }
}
