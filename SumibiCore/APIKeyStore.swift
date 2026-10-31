import Foundation
import Security

public enum APIKeyStoreError: Error, Equatable {
    case invalidEncoding
    case unexpectedData
    case keychain(OSStatus)
}

public struct APIKeyStore {
    private static let service = "org.sumibi.Sumibi-iOS.api-key"
    private static let legacyAccount = "default"

    public init() {}

    public static func maskedDisplay(for apiKey: String) -> String? {
        guard !apiKey.isEmpty else {
            return nil
        }
        guard apiKey.count > 4 else {
            return String(repeating: "•", count: apiKey.count)
        }

        let suffix = apiKey.suffix(4)
        let maskedPrefix = String(repeating: "•", count: apiKey.count - suffix.count)
        return maskedPrefix + suffix
    }

    public func load(for endpoint: String) throws -> String? {
        let account = Self.account(for: endpoint)
        if let key = try load(account: account) { return key }
        // Upgrade the pre-provider key only for the endpoint that owned it.
        guard SharedSettingsStore()?.loadProviderConfiguration().endpoint
            .trimmingCharacters(in: .whitespacesAndNewlines)
            == endpoint.trimmingCharacters(in: .whitespacesAndNewlines),
              let legacyKey = try load(account: Self.legacyAccount) else { return nil }
        try save(legacyKey, account: account)
        try delete(account: Self.legacyAccount)
        return legacyKey
    }

    public func migrateLegacyKey(for endpoint: String) throws {
        _ = try load(for: endpoint)
    }

    private func load(account: String) throws -> String? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw APIKeyStoreError.keychain(status)
        }
        guard
            let data = result as? Data,
            let apiKey = String(data: data, encoding: .utf8)
        else {
            throw APIKeyStoreError.unexpectedData
        }
        return apiKey
    }

    public func save(_ apiKey: String, for endpoint: String) throws {
        try save(apiKey, account: Self.account(for: endpoint))
    }

    private func save(_ apiKey: String, account: String) throws {
        guard let data = apiKey.data(using: .utf8) else {
            throw APIKeyStoreError.invalidEncoding
        }

        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecAttrSynchronizable as String: false,
        ]

        let updateStatus = SecItemUpdate(
            baseQuery(account: account) as CFDictionary,
            attributes as CFDictionary
        )

        if updateStatus == errSecSuccess {
            return
        }
        guard updateStatus == errSecItemNotFound else {
            throw APIKeyStoreError.keychain(updateStatus)
        }

        var item = baseQuery(account: account)
        attributes.forEach { item[$0.key] = $0.value }
        let addStatus = SecItemAdd(item as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw APIKeyStoreError.keychain(addStatus)
        }
    }

    public func delete(for endpoint: String) throws {
        try delete(account: Self.account(for: endpoint))
    }

    private func delete(account: String) throws {
        let status = SecItemDelete(baseQuery(account: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw APIKeyStoreError.keychain(status)
        }
    }

    private static func account(for endpoint: String) -> String {
        "endpoint:\(endpoint.trimmingCharacters(in: .whitespacesAndNewlines))"
    }

    private func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: account,
            kSecAttrAccessGroup as String: SharedSettingsStore.appGroupIdentifier,
            kSecAttrSynchronizable as String: false,
        ]
    }
}
