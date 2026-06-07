import Foundation

nonisolated extension String.Encoding {
    static let gb18030: String.Encoding = {
        let encoding = CFStringConvertEncodingToNSStringEncoding(
            CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)
        )
        return String.Encoding(rawValue: encoding)
    }()
}
