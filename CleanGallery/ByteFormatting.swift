import Foundation

extension Int64 {
    /// Human-readable size using GB / MB / KB (English).
    var formattedByteCount: String {
        if self <= 0 { return "—" }
        let gb = Double(self) / 1_073_741_824
        if gb >= 1 {
            return String(format: "%.2f GB", gb)
        }
        let mb = Double(self) / 1_048_576
        if mb >= 1 {
            return String(format: "%.1f MB", mb)
        }
        let kb = Double(self) / 1024
        return String(format: "%.0f KB", kb)
    }
}
