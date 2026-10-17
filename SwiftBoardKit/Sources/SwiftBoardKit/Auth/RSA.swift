import Foundation
import Security

/// Minimal DER reader used to turn a `SubjectPublicKeyInfo` PEM into the
/// PKCS#1 RSAPublicKey blob expected by `SecKeyCreateWithData`.
struct DERReader {
    struct Element {
        let tag: UInt8
        let content: Data
    }

    private let bytes: [UInt8]
    private var index = 0

    init(_ data: Data) {
        bytes = [UInt8](data)
    }

    var isAtEnd: Bool { index >= bytes.count }

    mutating func next() throws -> Element {
        guard index < bytes.count else { throw RSAError.malformedKey }
        let tag = bytes[index]
        index += 1

        guard index < bytes.count else { throw RSAError.malformedKey }
        var length = Int(bytes[index])
        index += 1
        if length & 0x80 != 0 {
            let count = length & 0x7F
            guard count > 0, count <= 4, index + count <= bytes.count else { throw RSAError.malformedKey }
            length = 0
            for _ in 0..<count {
                length = (length << 8) | Int(bytes[index])
                index += 1
            }
        }
        guard length >= 0, index + length <= bytes.count else { throw RSAError.malformedKey }
        let content = Data(bytes[index..<(index + length)])
        index += length
        return Element(tag: tag, content: content)
    }
}

public enum RSAError: Error, LocalizedError {
    case malformedKey
    case encryptionFailed(String)

    public var errorDescription: String? {
        switch self {
        case .malformedKey: "无法解析登录公钥"
        case .encryptionFailed(let reason): "密码加密失败：\(reason)"
        }
    }
}

/// RSA PKCS#1 v1.5 encryption compatible with the `jsencrypt` call used by
/// PKU's IAAA login page.
public enum RSA {
    public static func encrypt(_ plaintext: String, publicKeyPEM pem: String) throws -> String {
        let keyData = try pkcs1Key(fromPEM: pem)
        let attributes: [CFString: Any] = [
            kSecAttrKeyType: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass: kSecAttrKeyClassPublic
        ]
        var error: Unmanaged<CFError>?
        guard let key = SecKeyCreateWithData(keyData as CFData, attributes as CFDictionary, &error) else {
            throw RSAError.encryptionFailed(error?.takeRetainedValue().localizedDescription ?? "unknown")
        }
        guard let encrypted = SecKeyCreateEncryptedData(
            key,
            .rsaEncryptionPKCS1,
            Data(plaintext.utf8) as CFData,
            &error
        ) else {
            throw RSAError.encryptionFailed(error?.takeRetainedValue().localizedDescription ?? "unknown")
        }
        return (encrypted as Data).base64EncodedString()
    }

    static func pkcs1Key(fromPEM pem: String) throws -> Data {
        let base64Lines = pem
            .split(whereSeparator: \.isNewline)
            .filter { !$0.hasPrefix("-----") }
        guard let der = Data(base64Encoded: base64Lines.joined()) else { throw RSAError.malformedKey }

        var reader = DERReader(der)
        let outer = try reader.next()
        guard outer.tag == 0x30 else { throw RSAError.malformedKey }

        var inner = DERReader(outer.content)
        let algorithm = try inner.next()
        guard algorithm.tag == 0x30 else { throw RSAError.malformedKey }
        let bitString = try inner.next()
        guard bitString.tag == 0x03, bitString.content.count > 1 else { throw RSAError.malformedKey }

        // First byte of a BIT STRING is the number of unused bits.
        let key = bitString.content.dropFirst()
        guard key.first == 0x30 else { throw RSAError.malformedKey }
        return Data(key)
    }
}
