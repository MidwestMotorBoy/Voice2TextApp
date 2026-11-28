import Foundation
import Security

/// Where the app keeps what the person entered in setup.
/// The Worker address goes in UserDefaults; the family token goes in the Keychain.
enum Settings {
    private static let addressKey = "workerAddress"

    static var address: String {
        get { UserDefaults.standard.string(forKey: addressKey) ?? "" }
        set { UserDefaults.standard.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: addressKey) }
    }

    static var token: String {
        get { Keychain.read() ?? "" }
        set { Keychain.save(newValue.trimmingCharacters(in: .whitespacesAndNewlines)) }
    }

    static var isConfigured: Bool {
        DictationClient.endpoint(from: address) != nil && !token.isEmpty
    }
}

enum Keychain {
    private static let service = "FamilyDictation"
    private static let account = "familyToken"

    private static var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    static func read() -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func save(_ value: String) {
        SecItemDelete(baseQuery as CFDictionary)
        guard !value.isEmpty else { return }
        var query = baseQuery
        query[kSecValueData as String] = Data(value.utf8)
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(query as CFDictionary, nil)
    }
}
