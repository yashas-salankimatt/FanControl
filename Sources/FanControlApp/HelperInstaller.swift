import Foundation
import AppKit

/// Handles installing the privileged helper daemon from within the app.
/// Uses AppleScript `do shell script ... with administrator privileges` for the sudo prompt.
/// This class is intentionally NOT @MainActor so install() can run on a background thread
/// without blocking the UI while the admin dialog is displayed.
class HelperInstaller {
    static let shared = HelperInstaller()

    private let helperName = "FanControlHelper"
    private let helperDest = "/Library/PrivilegedHelperTools/FanControlHelper"
    private let plistName = "com.fancontrol.helper"
    private let plistDest = "/Library/LaunchDaemons/com.fancontrol.helper.plist"

    /// Path to the helper binary bundled inside the .app
    private var bundledHelperPath: String? {
        Bundle.main.path(forResource: helperName, ofType: nil)
    }

    /// Path to the LaunchDaemon plist bundled inside the .app
    private var bundledPlistPath: String? {
        Bundle.main.path(forResource: plistName, ofType: "plist")
    }

    /// Check if the helper binary is bundled in this app.
    var isBundled: Bool {
        bundledHelperPath != nil && bundledPlistPath != nil
    }

    /// Check if the helper is already installed on disk.
    var isInstalled: Bool {
        FileManager.default.fileExists(atPath: helperDest)
    }

    /// Escape a string for use inside a single-quoted shell argument.
    /// Replaces ' with '\'' (end quote, escaped quote, start quote).
    private func shellEscape(_ s: String) -> String {
        s.replacingOccurrences(of: "'", with: "'\\''")
    }

    /// Escape a string for embedding inside an AppleScript double-quoted string.
    /// Escapes backslashes and double quotes.
    private func appleScriptEscape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
         .replacingOccurrences(of: "\"", with: "\\\"")
    }

    /// Install the helper daemon. Returns nil on success, or an error message.
    /// This method blocks while the admin dialog is displayed — call from a background thread.
    func install() -> String? {
        guard let helperSrc = bundledHelperPath, let plistSrc = bundledPlistPath else {
            return "Helper binary not found in app bundle. Please rebuild the app."
        }

        let escapedHelperSrc = shellEscape(helperSrc)
        let escapedPlistSrc = shellEscape(plistSrc)
        let escapedHelperDest = shellEscape(helperDest)
        let escapedPlistDest = shellEscape(plistDest)

        // Build the shell script that will run with admin privileges
        let script = "/bin/mkdir -p /Library/PrivilegedHelperTools && " +
            "/bin/cp '\(escapedHelperSrc)' '\(escapedHelperDest)' && " +
            "/usr/sbin/chown root:wheel '\(escapedHelperDest)' && " +
            "/bin/chmod 755 '\(escapedHelperDest)' && " +
            "/bin/cp '\(escapedPlistSrc)' '\(escapedPlistDest)' && " +
            "/usr/sbin/chown root:wheel '\(escapedPlistDest)' && " +
            "/bin/chmod 644 '\(escapedPlistDest)' && " +
            "/bin/launchctl bootout 'system/\(shellEscape(plistName))' 2>/dev/null; " +
            "/bin/launchctl bootstrap system '\(escapedPlistDest)'"

        let escapedScript = appleScriptEscape(script)
        let appleScript = "do shell script \"\(escapedScript)\" with administrator privileges"

        var error: NSDictionary?
        let scriptObj = NSAppleScript(source: appleScript)
        scriptObj?.executeAndReturnError(&error)

        if let error = error {
            let errorMsg = error[NSAppleScript.errorMessage] as? String ?? "Unknown error"
            if errorMsg.contains("User canceled") || errorMsg.contains("-128") {
                return "cancelled"
            }
            return errorMsg
        }

        return nil
    }

    /// Uninstall the helper daemon. Returns nil on success, or an error message.
    func uninstall() -> String? {
        let escapedHelperDest = shellEscape(helperDest)
        let escapedPlistDest = shellEscape(plistDest)

        let script = "/bin/launchctl bootout 'system/\(shellEscape(plistName))' 2>/dev/null; " +
            "/bin/rm -f '\(escapedHelperDest)' '\(escapedPlistDest)' /var/run/fancontrol.sock"

        let escapedScript = appleScriptEscape(script)
        let appleScript = "do shell script \"\(escapedScript)\" with administrator privileges"

        var error: NSDictionary?
        let scriptObj = NSAppleScript(source: appleScript)
        scriptObj?.executeAndReturnError(&error)

        if let error = error {
            let errorMsg = error[NSAppleScript.errorMessage] as? String ?? "Unknown error"
            if errorMsg.contains("User canceled") || errorMsg.contains("-128") {
                return "cancelled"
            }
            return errorMsg
        }

        return nil
    }
}
