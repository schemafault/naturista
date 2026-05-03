import Foundation

// One-shot pre-flip migration that clones the entire
// `~/Library/Application Support/Naturista/` tree into the sandbox
// container at `~/Library/Containers/<bundleId>/Data/Library/Application
// Support/Naturista/`, so that flipping `com.apple.security.app-sandbox`
// to `true` later doesn't strand the user's DB, originals, working,
// thumbnails, illustrations, plates, and downloaded weights.
//
// Runs from the *current non-sandboxed build* — Process invocation is
// available, file access to the live Application Support path works.
// Once the sandboxed build ships, this migrator detects it's running
// inside the container and no-ops. Idempotent via UserDefaults.
//
// Cloning is done by `/bin/cp -c -R`, which uses the APFS `clonefile`
// syscall when source and destination share a volume — copy-on-write,
// nearly zero disk overhead until the user mutates the new copy.
enum SandboxContainerMigrator {
    private static let completedFlag = "sandbox.containerMigratedV1"

    static func migrateIfNeeded(
        userDefaults: UserDefaults = .standard,
        fileManager: FileManager = .default
    ) {
        if userDefaults.bool(forKey: completedFlag) { return }

        guard let bundleId = Bundle.main.bundleIdentifier else {
            print("[sandbox-migrate] no bundle id, skipping")
            return
        }

        // If the live Application Support already resolves into a
        // /Containers/ path, we're already running sandboxed — the
        // unsandboxed source isn't readable from here anyway.
        let liveAppSupport = fileManager.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first!
        if liveAppSupport.path.contains("/Containers/") {
            print("[sandbox-migrate] already inside sandbox container, skipping")
            userDefaults.set(true, forKey: completedFlag)
            return
        }

        let home = fileManager.homeDirectoryForCurrentUser
        let unsandboxed = home
            .appendingPathComponent("Library/Application Support/Naturista", isDirectory: true)
        let containerRoot = home
            .appendingPathComponent("Library/Containers/\(bundleId)/Data/Library/Application Support/Naturista", isDirectory: true)

        guard fileManager.fileExists(atPath: unsandboxed.path) else {
            print("[sandbox-migrate] no unsandboxed data to migrate")
            userDefaults.set(true, forKey: completedFlag)
            return
        }

        // If the container already has data, don't clobber — the user
        // may have already run a sandboxed build and accumulated state
        // there. Set the flag so we don't keep re-checking.
        if let contents = try? fileManager.contentsOfDirectory(atPath: containerRoot.path),
           !contents.isEmpty {
            print("[sandbox-migrate] container already populated, skipping")
            userDefaults.set(true, forKey: completedFlag)
            return
        }

        do {
            try fileManager.createDirectory(
                at: containerRoot.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
        } catch {
            print("[sandbox-migrate] could not create container parent: \(error.localizedDescription)")
            return
        }

        // `cp -c -R src/. dest/` clones the *contents* of src into dest.
        // The trailing `/.` is the canonical "files inside" form.
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/cp")
        task.arguments = ["-c", "-R", unsandboxed.path + "/.", containerRoot.path]

        do {
            try fileManager.createDirectory(at: containerRoot, withIntermediateDirectories: true)
            try task.run()
            task.waitUntilExit()
        } catch {
            print("[sandbox-migrate] cp launch failed: \(error.localizedDescription); will retry next launch")
            return
        }

        guard task.terminationStatus == 0 else {
            print("[sandbox-migrate] cp exited \(task.terminationStatus); will retry next launch")
            return
        }

        print("[sandbox-migrate] cloned \(unsandboxed.path) → \(containerRoot.path)")
        userDefaults.set(true, forKey: completedFlag)
    }
}
