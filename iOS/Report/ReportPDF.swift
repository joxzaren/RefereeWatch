import CoreTransferable
import Foundation
import UniformTypeIdentifiers

/// A rendered report for `ShareLink`. It is shared as a PDF file with a readable name.
struct ReportPDF: Transferable {
    var fileName: String
    var data: Data

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .pdf) { pdf in
            SentTransferredFile(try pdf.writeTemporaryFile())
        }
    }

    /// Writes the PDF into its own temporary folder so the file keeps its exact name.
    func writeTemporaryFile() throws -> URL {
        let folder = FileManager.default.temporaryDirectory
            .appending(path: "Reports", directoryHint: .isDirectory)
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appending(path: fileName, directoryHint: .notDirectory)
        try data.write(to: url, options: .atomic)
        return url
    }
}
