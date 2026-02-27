import Foundation
import AppKit

/// Handles installing the privileged helper daemon from within the app.
/// Uses AppleScript `do shell script ... with administrator privileges` for the sudo prompt.
@MainActor
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

    /// Install the helper daemon. Returns nil on success, or an error message.
    func install() -> String? {
        guard let helperSrc = bundledHelperPath, let plistSrc = bundledPlistPath else {
            return "Helper binary not found in app bundle. Please rebuild the app."
        }

        // Build the shell script that will run with admin privileges
        let script = """
        /bin/mkdir -p /Library/PrivilegedHelperTools && \
        /bin/cp '\(helperSrc)' '\(helperDest)' && \
        /usr/sbin/chown root:wheel '\(helperDest)' && \
        /bin/chmod 755 '\(helperDest)' && \
        /bin/cp '\(plistSrc)' '\(plistDest)' && \
        /usr/sbin/chown root:wheel '\(plistDest)' && \
        /bin/chmod 644 '\(plistDest)' && \
        /bin/launchctl bootout system/\(plistName) 2>/dev/null; \
        /bin/launchctl bootstrap system '\(plistDest)'
        """

        // Use AppleScript to get the admin password prompt
        let appleScript = """
        do shell script "\(script)" with administrator privileges
        """

        var error: NSDictionary?
        let scriptObj = NSAppleScript(source: appleScript)
        scriptObj?.executeAndReturnError(&error)

        if let error = error {
            let errorMsg = error[NSAppleScript.errorMessage] as? String ?? "Unknown error"
            // User cancelled the auth dialog
            if errorMsg.contains("User canceled") || errorMsg.contains("-128") {
                return "cancelled"
            }
            return errorMsg
        }

        return nil
    }

    /// Uninstall the helper daemon. Returns nil on success, or an error message.
    func uninstall() -> String? {
        let script = """
        /bin/launchctl bootout system/\(plistName) 2>/dev/null; \
        /bin/rm -f '\(helperDest)' '\(plistDest)' /var/run/fancontrol.sock
        """

        let appleScript = """
        do shell script "\(script)" with administrator privileges
        """

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
