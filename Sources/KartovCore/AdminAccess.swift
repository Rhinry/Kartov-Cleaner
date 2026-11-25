import Foundation

/// The few jobs that need the administrator: freeing memory, refreshing the DNS cache and
/// removing the hidden parts of System Data.
public enum AdminTask: String, CaseIterable, Sendable {
    case memory, dns, snapshots
    case installData = "installdata"

    /// The same job through macOS's password dialog (used while no-password mode is off).
    public var shellCommand: String {
        switch self {
        case .memory: return "/usr/sbin/purge"
        case .dns: return "/usr/bin/dscacheutil -flushcache; /usr/bin/killall -HUP mDNSResponder"
        case .snapshots: return "/usr/bin/tmutil deletelocalsnapshots /"
        case .installData: return "/bin/rm -rf '/macOS Install Data'"
        }
    }
}

/// "No password" mode: a small root-owned helper that knows only the jobs above, and a sudoers rule
/// that lets this user run that helper without a password. Turning it on and off asks for the
/// password once. Nothing the user types or Kartov scans ever reaches these files: only the
/// account name, checked first.
public enum AdminAccessFiles {
    public static let helperPath = "/Library/PrivilegedHelperTools/kartov-admin"
    public static let rulePath = "/etc/sudoers.d/kartov-cleaner"

    public static let helperScript = """
    #!/bin/sh
    # Kartov Cleaner: fixed administrator jobs, nothing else. Remove with Kartov's Settings.
    PATH=/usr/bin:/bin:/usr/sbin:/sbin
    case "$1" in
      check) exit 0 ;;
      memory) exec /usr/sbin/purge ;;
      dns) /usr/bin/dscacheutil -flushcache; exec /usr/bin/killall -HUP mDNSResponder ;;
      snapshots) exec /usr/bin/tmutil deletelocalsnapshots / ;;
      installdata) exec /bin/rm -rf "/macOS Install Data" ;;
      *) exit 64 ;;
    esac

    """

    /// macOS short account names; `root` and anything sudoers could read as a keyword are refused.
    public static func isValidUser(_ name: String) -> Bool {
        guard name != "root", name.range(of: "^[a-z_][a-z0-9_.-]{0,31}$", options: .regularExpression) != nil else { return false }
        return true
    }

    public static func sudoersRule(user: String) -> String {
        "# Kartov Cleaner: run its helper without a password. Remove with Kartov's Settings.\n"
            + "\(user) ALL=(root) NOPASSWD: \(helperPath)\n"
    }

    /// One line for `do shell script … with administrator privileges`. The rule is checked by
    /// visudo under a name sudo ignores (it has a dot) and only then moved into place, so a bad
    /// file can never break sudo. `root` and `setOwner` exist for tests.
    public static func installScript(user: String, root: String = "", setOwner: Bool = true) -> String? {
        guard isValidUser(user) else { return nil }
        let helper = root + helperPath, rule = root + rulePath
        let helperData = Data(helperScript.utf8).base64EncodedString()
        let ruleData = Data(sudoersRule(user: user).utf8).base64EncodedString()
        let own = { (path: String) in setOwner ? ["/usr/sbin/chown root:wheel \(path)"] : [] }
        let steps: [String] = ["set -e", "umask 022",
                               "/bin/mkdir -p \(root)/Library/PrivilegedHelperTools \(root)/etc/sudoers.d",
                               "/bin/echo \(helperData) | /usr/bin/base64 -D > \(helper).tmp",
                               "/bin/chmod 755 \(helper).tmp"] + own("\(helper).tmp") + [
                               "/bin/mv -f \(helper).tmp \(helper)",
                               "/bin/echo \(ruleData) | /usr/bin/base64 -D > \(rule).tmp",
                               "/bin/chmod 440 \(rule).tmp"] + own("\(rule).tmp") + [
                               "/usr/sbin/visudo -cf \(rule).tmp > /dev/null || { /bin/rm -f \(rule).tmp; exit 1; }",
                               "/bin/mv -f \(rule).tmp \(rule)"]
        return steps.joined(separator: "; ")
    }

    public static func removeScript(root: String = "") -> String {
        "/bin/rm -f \(root + rulePath) \(root + helperPath)"
    }
}
