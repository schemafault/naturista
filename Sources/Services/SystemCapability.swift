import Foundation

// Read-only snapshot of the host machine's resources, used by the
// model picker to refuse downloads / loads that would OOM-kill the
// Python subprocess on the user's hardware.
//
// Apple Silicon's unified memory means GPU memory isn't separately
// queryable — total physical RAM is the right proxy for "will this
// model fit." Disk capacity is queried per-volume because the model
// directory may live on an external drive in the future; today it's
// the home volume.
struct SystemCapability {
    static let current = SystemCapability()

    let physicalMemoryGB: Double
    let isAppleSilicon: Bool
    let chipModel: String

    init() {
        self.physicalMemoryGB = Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824.0
        self.isAppleSilicon = Self.detectAppleSilicon()
        self.chipModel = Self.detectChipModel()
    }

    // .volumeAvailableCapacityForImportantUsageKey is the right key here:
    // it accounts for purgeable storage macOS will free under pressure,
    // matching what a user sees in About This Mac. Returns nil if the
    // path can't be resolved (e.g. neither it nor any ancestor exists).
    func availableDiskGB(at url: URL) -> Double? {
        let probe = existingAncestor(of: url) ?? URL(fileURLWithPath: NSHomeDirectory())
        guard let values = try? probe.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
              let bytes = values.volumeAvailableCapacityForImportantUsage else {
            return nil
        }
        return Double(bytes) / 1_073_741_824.0
    }

    private func existingAncestor(of url: URL) -> URL? {
        var candidate = url
        let fm = FileManager.default
        while !fm.fileExists(atPath: candidate.path) {
            let parent = candidate.deletingLastPathComponent()
            if parent.path == candidate.path { return nil }
            candidate = parent
        }
        return candidate
    }

    private static func detectAppleSilicon() -> Bool {
        var ret: Int32 = 0
        var size = MemoryLayout<Int32>.size
        let result = sysctlbyname("hw.optional.arm64", &ret, &size, nil, 0)
        return result == 0 && ret == 1
    }

    private static func detectChipModel() -> String {
        var size = 0
        sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0)
        guard size > 0 else { return "Unknown CPU" }
        var bytes = [CChar](repeating: 0, count: size)
        sysctlbyname("machdep.cpu.brand_string", &bytes, &size, nil, 0)
        return String(cString: bytes)
    }
}
