import UIKit
import RefereeKit

/// Renders a report layout to PDF data: A4 pages of text with page breaks as needed.
/// It has no side effects other than the returned data.
enum ReportPDFRenderer {
    static let pageSize = CGSize(width: 595.2, height: 841.8)
    static let margin: CGFloat = 48

    static func render(_ match: Match, timeZone: TimeZone = .current) -> Data {
        render(ReportLayout(match: match, timeZone: timeZone))
    }

    static func render(_ layout: ReportLayout) -> Data {
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [
            kCGPDFContextTitle as String: layout.title,
            kCGPDFContextCreator as String: "RefereeWatch",
        ]
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: pageSize), format: format)
        return renderer.pdfData { context in
            var writer = PageWriter(context: context)
            writer.beginPage()
            writer.write(layout.title, style: .title)
            if !layout.subtitle.isEmpty { writer.write(layout.subtitle, style: .secondary) }
            writer.space(10)
            writer.write(layout.score, style: .score)
            if let penalties = layout.penalties { writer.write(penalties, style: .body) }

            if layout.hasEvents {
                for section in layout.sections where !section.rows.isEmpty {
                    writer.space(14)
                    writer.write(section.title, style: .heading)
                    for row in section.rows { writer.write(rowText(row), style: .body) }
                }
            } else {
                writer.space(14)
                writer.write("No events logged.", style: .secondary)
            }

            if !layout.workout.isEmpty {
                writer.space(14)
                writer.write("Workout", style: .heading)
                for row in layout.workout { writer.write(rowText(row), style: .body) }
            }
        }
    }

    static func rowText(_ row: ReportLayout.Row) -> String {
        guard let lead = row.lead else { return row.text }
        return "\(lead)  \(row.text)"
    }

    enum Style {
        case title, secondary, score, heading, body

        var attributes: [NSAttributedString.Key: Any] {
            let font: UIFont
            let color: UIColor
            switch self {
            case .title: font = .systemFont(ofSize: 22, weight: .bold); color = .black
            case .secondary: font = .systemFont(ofSize: 12); color = .darkGray
            case .score: font = .systemFont(ofSize: 18, weight: .semibold); color = .black
            case .heading: font = .systemFont(ofSize: 14, weight: .semibold); color = .black
            case .body: font = .systemFont(ofSize: 12); color = .black
            }
            return [.font: font, .foregroundColor: color]
        }
    }

    /// Writes lines top to bottom and starts a new page when one does not fit.
    private struct PageWriter {
        let context: UIGraphicsPDFRendererContext
        var y: CGFloat = 0

        init(context: UIGraphicsPDFRendererContext) {
            self.context = context
        }

        var width: CGFloat { pageSize.width - 2 * margin }

        mutating func beginPage() {
            context.beginPage()
            y = margin
        }

        mutating func space(_ amount: CGFloat) {
            y += amount
        }

        mutating func write(_ text: String, style: Style) {
            let string = NSAttributedString(string: text, attributes: style.attributes)
            let bounds = string.boundingRect(
                with: CGSize(width: width, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                context: nil)
            let height = ceil(bounds.height)
            if y + height > pageSize.height - margin { beginPage() }
            string.draw(with: CGRect(x: margin, y: y, width: width, height: height),
                        options: [.usesLineFragmentOrigin, .usesFontLeading],
                        context: nil)
            y += height + 4
        }
    }
}
