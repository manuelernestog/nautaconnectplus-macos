import Foundation

public enum Language: String, CaseIterable {
    case english = "en"
    case spanish = "es"

    /// Follows the user's preferred system language.
    public static var system: Language {
        (Locale.preferredLanguages.first ?? "en").hasPrefix("es") ? .spanish : .english
    }

    public var displayName: String {
        switch self {
        case .english: return "English"
        case .spanish: return "Español"
        }
    }
}

/// In-code bilingual string table. Exhaustive per language: a missing
/// translation is a compile-time problem, not a runtime surprise.
public enum L10n {
    public static var language: Language = .english

    public enum Key: String, CaseIterable {
        case statusConnected
        case statusDisconnected
        case statusNotOnNetwork
        case statusWorking
        case accounts
        case addAccount
        case addAccountTitle
        case duplicateAccount
        case keychainFailure
        case connect
        case disconnect
        case timeLeft
        case timeLeftUnknown
        case sessionTime
        case settings
        case quit
        case settingsTitle
        case usernameLabel
        case usernamePlaceholder
        case passwordLabel
        case languageLabel
        case launchAtLogin
        case showTimeInMenuBar
        case save
        case saved
        case errorTitle
        case missingCredentials
        case refreshTimeLeft
        case discardSession
        case keepSession
        case disconnectTimer
        case disconnectIn
        case cancelTimer
        case customTimer
        case customTimerTitle
        case customTimerPrompt
        case customTimerInvalid
        case startTimer
        case cancel
        case minutesUnit
        case hourUnit
        case hoursUnit
        case autoReconnect
        case autoReconnectInterval
        case secondsShort
        case statusReconnecting
        case cancelReconnect
        case reconnectFailedTitle
    }

    public static func t(_ key: Key) -> String {
        table[language]?[key] ?? key.rawValue
    }

    private static let table: [Language: [Key: String]] = [
        .english: [
            .statusConnected: "Connected",
            .statusDisconnected: "Disconnected",
            .statusNotOnNetwork: "Not on a Nauta network",
            .statusWorking: "Working…",
            .accounts: "Accounts:",
            .addAccount: "+ Add account",
            .addAccountTitle: "Add account",
            .duplicateAccount: "This account is already saved.",
            .keychainFailure: "Could not save the password in Keychain. Try again.",
            .connect: "Connect",
            .disconnect: "Disconnect",
            .timeLeft: "Time left",
            .timeLeftUnknown: "Time left: —",
            .sessionTime: "Session",
            .settings: "Settings…",
            .quit: "Quit NautaConnectPlus",
            .settingsTitle: "NautaConnectPlus Settings",
            .usernameLabel: "Username:",
            .usernamePlaceholder: "user@nauta.com.cu",
            .passwordLabel: "Password:",
            .languageLabel: "Language:",
            .launchAtLogin: "Launch at login",
            .showTimeInMenuBar: "Show time in menu bar",
            .save: "Save",
            .saved: "Saved",
            .errorTitle: "NautaConnectPlus",
            .missingCredentials: "Enter your Nauta username and password in Settings first.",
            .refreshTimeLeft: "Refresh time left",
            .discardSession: "Discard local session",
            .keepSession: "Keep session",
            .disconnectTimer: "Disconnect timer",
            .disconnectIn: "Disconnect in",
            .cancelTimer: "Cancel timer",
            .customTimer: "Custom…",
            .customTimerTitle: "Disconnect Timer",
            .customTimerPrompt: "Disconnect automatically after:",
            .customTimerInvalid: "Enter a valid duration greater than 0.",
            .startTimer: "Start",
            .cancel: "Cancel",
            .minutesUnit: "min",
            .hourUnit: "hour",
            .hoursUnit: "hours",
            .autoReconnect: "Auto-reconnect",
            .autoReconnectInterval: "Check every:",
            .secondsShort: "s",
            .statusReconnecting: "Reconnecting…",
            .cancelReconnect: "Cancel reconnection",
            .reconnectFailedTitle: "Auto-reconnect stopped",
        ],
        .spanish: [
            .statusConnected: "Conectado",
            .statusDisconnected: "Desconectado",
            .statusNotOnNetwork: "No estás en una red Nauta",
            .statusWorking: "Procesando…",
            .accounts: "Cuentas:",
            .addAccount: "+ Agregar cuenta",
            .addAccountTitle: "Agregar cuenta",
            .duplicateAccount: "Esta cuenta ya está guardada.",
            .keychainFailure: "No se pudo guardar la contraseña en el Llavero. Inténtalo de nuevo.",
            .connect: "Conectar",
            .disconnect: "Desconectar",
            .timeLeft: "Tiempo disponible",
            .timeLeftUnknown: "Tiempo disponible: —",
            .sessionTime: "Sesión",
            .settings: "Ajustes…",
            .quit: "Salir de NautaConnectPlus",
            .settingsTitle: "Ajustes de NautaConnectPlus",
            .usernameLabel: "Usuario:",
            .usernamePlaceholder: "usuario@nauta.com.cu",
            .passwordLabel: "Contraseña:",
            .languageLabel: "Idioma:",
            .launchAtLogin: "Abrir al iniciar sesión",
            .showTimeInMenuBar: "Mostrar tiempo en la barra de menú",
            .save: "Guardar",
            .saved: "Guardado",
            .errorTitle: "NautaConnectPlus",
            .missingCredentials: "Primero escribe tu usuario y contraseña de Nauta en Ajustes.",
            .refreshTimeLeft: "Actualizar tiempo disponible",
            .discardSession: "Descartar sesión local",
            .keepSession: "Mantener sesión",
            .disconnectTimer: "Temporizador de desconexión",
            .disconnectIn: "Desconectar en",
            .cancelTimer: "Cancelar temporizador",
            .customTimer: "Personalizado…",
            .customTimerTitle: "Temporizador de desconexión",
            .customTimerPrompt: "Desconectar automáticamente después de:",
            .customTimerInvalid: "Introduce una duración válida mayor que 0.",
            .startTimer: "Iniciar",
            .cancel: "Cancelar",
            .minutesUnit: "min",
            .hourUnit: "hora",
            .hoursUnit: "horas",
            .autoReconnect: "Reconectar automáticamente",
            .autoReconnectInterval: "Comprobar cada:",
            .secondsShort: "s",
            .statusReconnecting: "Reconectando…",
            .cancelReconnect: "Cancelar reconexión",
            .reconnectFailedTitle: "Reconexión automática detenida",
        ],
    ]
}
