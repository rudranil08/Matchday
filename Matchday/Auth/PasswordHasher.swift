import Foundation
import CommonCrypto
import Security

/// Passwords are never stored. Each one is turned into a salted PBKDF2-SHA256 hash;
/// only the salt and hash are kept, so nobody (developer or user) can read a password back.
enum PasswordHasher {
    static let iterations = 310_000
    private static let keyLength = 32

    struct Hashed: Codable, Equatable {
        let salt: Data
        let hash: Data
        let iterations: Int
    }

    static func hash(_ password: String) -> Hashed {
        let salt = randomBytes(16)
        return Hashed(salt: salt, hash: derive(password, salt: salt, iterations: iterations), iterations: iterations)
    }

    static func verify(_ password: String, against stored: Hashed) -> Bool {
        constantTimeEqual(derive(password, salt: stored.salt, iterations: stored.iterations), stored.hash)
    }

    static func derive(_ password: String, salt: Data, iterations: Int) -> Data {
        let pw = Array(password.utf8)
        var out = [UInt8](repeating: 0, count: keyLength)
        salt.withUnsafeBytes { saltPtr in
            _ = CCKeyDerivationPBKDF(
                CCPBKDFAlgorithm(kCCPBKDF2),
                pw.map { Int8(bitPattern: $0) }, pw.count,
                saltPtr.bindMemory(to: UInt8.self).baseAddress, salt.count,
                CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), UInt32(iterations),
                &out, keyLength
            )
        }
        return Data(out)
    }

    static func randomBytes(_ count: Int) -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        _ = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        return Data(bytes)
    }

    /// Compares without leaking how many leading bytes matched.
    private static func constantTimeEqual(_ a: Data, _ b: Data) -> Bool {
        guard a.count == b.count else { return false }
        var diff: UInt8 = 0
        for (x, y) in zip(a, b) { diff |= x ^ y }
        return diff == 0
    }
}

extension Data {
    init?(hex: String) {
        var data = Data(capacity: hex.count / 2)
        var i = hex.startIndex
        while i < hex.endIndex {
            let j = hex.index(i, offsetBy: 2)
            guard let byte = UInt8(hex[i..<j], radix: 16) else { return nil }
            data.append(byte)
            i = j
        }
        self = data
    }
}
