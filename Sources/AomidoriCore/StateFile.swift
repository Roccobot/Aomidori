import Foundation

/// Reads the JSON files that hold the reader's own data (positions, bookmarks) without ever
/// losing them. A missing file is a fresh start; a file that exists but cannot be decoded
/// (damaged, or written by a later version) is renamed `<name>.unreadable-<date>` before the
/// store starts empty, so the next save cannot overwrite it.
/// Author: Rocco Casadei, a.k.a. Roccobot
enum StateFile {
    static func decode<T: Decodable>(_ type: T.Type, from fileURL: URL, decoder: JSONDecoder) -> T? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        do {
            return try decoder.decode(type, from: data)
        } catch {
            setAside(fileURL)
            return nil
        }
    }

    private static func setAside(_ fileURL: URL) {
        let stamp = Date().formatted(.verbatim("\(year: .defaultDigits)\(month: .twoDigits)\(day: .twoDigits)-\(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased))\(minute: .twoDigits)\(second: .twoDigits)",
                                               timeZone: .current, calendar: Calendar(identifier: .gregorian)))
        let target = fileURL.deletingLastPathComponent()
            .appendingPathComponent("\(fileURL.lastPathComponent).unreadable-\(stamp)")
        do {
            try FileManager.default.moveItem(at: fileURL, to: target)
        } catch {
            NSLog("Aomidori: cannot set aside unreadable %@: %@", fileURL.path, error.localizedDescription)
        }
    }
}
