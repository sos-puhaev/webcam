import Foundation

enum CameraTimeFormatter {

    static func timeOnly(_ date: Date) -> String {
        let df = DateFormatter()
        df.locale = .current
        df.timeZone = .current
        df.dateStyle = .none
        df.timeStyle = .short
        return df.string(from: date)
    }

    // ✅ НОВОЕ: только время с секундами
    static func timeOnlyWithSeconds(_ date: Date) -> String {
        let df = DateFormatter()
        df.locale = .current
        df.timeZone = .current
        df.dateFormat = "HH:mm:ss"
        return df.string(from: date)
    }

    static func dateTimeWithDayIfNeeded(_ date: Date) -> String {
        let now = Date()
        let sameDay = Calendar.current.isDate(date, inSameDayAs: now)

        let df = DateFormatter()
        df.locale = .current
        df.timeZone = .current
        df.dateStyle = sameDay ? .none : .short
        df.timeStyle = .short
        return df.string(from: date)
    }

    // ✅ НОВОЕ: дата/время, но с секундами
    static func dateTimeWithDayIfNeededWithSeconds(_ date: Date) -> String {
        let now = Date()
        let sameDay = Calendar.current.isDate(date, inSameDayAs: now)

        let df = DateFormatter()
        df.locale = .current
        df.timeZone = .current
        // чтобы не зависеть от .short и гарантировать секунды:
        df.dateFormat = sameDay ? "HH:mm:ss" : "dd.MM.yyyy HH:mm:ss"
        return df.string(from: date)
    }

    static func archiveStart(_ date: Date) -> String {
        let df = DateFormatter()
        df.locale = .current
        df.timeZone = .current
        df.dateStyle = .medium
        df.timeStyle = .short
        return df.string(from: date)
    }
}
