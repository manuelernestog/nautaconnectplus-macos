import Foundation

public enum AccountFormValidation {
    public static func canSave(username: String, password: String) -> Bool {
        let username = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = username.split(separator: "@", omittingEmptySubsequences: false)
        guard !password.isEmpty, parts.count == 2, !parts[0].isEmpty,
              !username.contains(where: { $0.isWhitespace }) else { return false }
        return ["nauta.com.cu", "nauta.co.cu"].contains(parts[1].lowercased())
    }
}
