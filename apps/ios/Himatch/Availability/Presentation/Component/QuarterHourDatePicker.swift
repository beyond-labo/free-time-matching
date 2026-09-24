import SwiftUI
import UIKit

/// Wheel date-and-time picker restricted to 15-minute steps. SwiftUI's `DatePicker` has no
/// minute interval, so this wraps `UIDatePicker`. Values are still floored by the reducer.
struct QuarterHourDatePicker: UIViewRepresentable {
    static let height: CGFloat = 216

    let selection: Date
    let range: ClosedRange<Date>
    let accessibilityLabel: String
    let onChange: (Date) -> Void

    @Environment(\.calendar) private var calendar

    func makeCoordinator() -> Coordinator {
        Coordinator(onChange: onChange)
    }

    func makeUIView(context: Context) -> UIDatePicker {
        let picker = UIDatePicker()
        picker.datePickerMode = .dateAndTime
        picker.preferredDatePickerStyle = .wheels
        picker.minuteInterval = 15
        picker.locale = AvailabilityFormatting.locale
        picker.addTarget(context.coordinator, action: #selector(Coordinator.valueChanged(_:)), for: .valueChanged)
        picker.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return picker
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UIDatePicker, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 320, height: Self.height)
    }

    func updateUIView(_ picker: UIDatePicker, context: Context) {
        context.coordinator.onChange = onChange
        picker.calendar = calendar
        picker.timeZone = calendar.timeZone
        picker.minimumDate = range.lowerBound
        picker.maximumDate = range.upperBound
        if picker.date != selection {
            picker.setDate(selection, animated: false)
        }
        picker.accessibilityLabel = accessibilityLabel
    }

    @MainActor
    final class Coordinator: NSObject {
        var onChange: (Date) -> Void

        init(onChange: @escaping (Date) -> Void) {
            self.onChange = onChange
        }

        @objc func valueChanged(_ sender: UIDatePicker) {
            onChange(sender.date)
        }
    }
}
