import Foundation

/// System-level power reading from IOReport or fallback.
struct PowerSample {
    let timestamp: TimeInterval
    let cpuWatts: Double       // Total CPU power (P-cores + E-cores)
    let gpuWatts: Double       // GPU power
    let aneWatts: Double       // Neural Engine power
    let dramWatts: Double      // DRAM power
    let packageWatts: Double   // Total SoC package (sum of above + overhead)

    /// Individual cluster readings when available.
    let pCoreWatts: Double     // P-cluster(s) total
    let eCoreWatts: Double     // E-cluster total

    var totalWatts: Double { cpuWatts + gpuWatts + aneWatts + dramWatts }

    static let zero = PowerSample(
        timestamp: 0, cpuWatts: 0, gpuWatts: 0, aneWatts: 0,
        dramWatts: 0, packageWatts: 0, pCoreWatts: 0, eCoreWatts: 0
    )
}

/// Reads system power via IOReport (Apple Silicon) with CPU% proxy fallback.
final class PowerSampler {

    /// Whether IOReport is available on this system.
    private(set) var isIOReportAvailable: Bool = false

    /// Most recent power sample.
    private(set) var latestSample: PowerSample = .zero

    // IOReport function pointers loaded via dlsym
    private var ioReportHandle: UnsafeMutableRawPointer?
    private var subscription: OpaquePointer?
    private var subscribedChannels: Unmanaged<CFMutableDictionary>?
    private var previousSample: CFDictionary?
    private var previousTimestamp: TimeInterval = 0

    // dlsym function types
    private typealias CopyChannelsInGroupFn = @convention(c)
        (CFString?, CFString?, UInt64, UInt64, UInt64) -> Unmanaged<CFDictionary>?
    private typealias MergeChannelsFn = @convention(c)
        (CFMutableDictionary, CFDictionary, CFTypeRef?) -> Void
    private typealias CreateSubscriptionFn = @convention(c)
        (UnsafeMutableRawPointer?, CFMutableDictionary,
         UnsafeMutablePointer<Unmanaged<CFMutableDictionary>?>?,
         UInt64, CFTypeRef?) -> OpaquePointer?
    private typealias CreateSamplesFn = @convention(c)
        (OpaquePointer?, CFMutableDictionary?, CFTypeRef?) -> Unmanaged<CFDictionary>?
    private typealias CreateSamplesDeltaFn = @convention(c)
        (CFDictionary, CFDictionary, CFTypeRef?) -> Unmanaged<CFDictionary>?
    private typealias ChannelGetStringFn = @convention(c)
        (CFDictionary) -> Unmanaged<CFString>?
    private typealias SimpleGetIntFn = @convention(c)
        (CFDictionary, Int32) -> Int64

    private var fnCopyChannelsInGroup: CopyChannelsInGroupFn?
    private var fnMergeChannels: MergeChannelsFn?
    private var fnCreateSubscription: CreateSubscriptionFn?
    private var fnCreateSamples: CreateSamplesFn?
    private var fnCreateSamplesDelta: CreateSamplesDeltaFn?
    private var fnChannelGetGroup: ChannelGetStringFn?
    private var fnChannelGetChannelName: ChannelGetStringFn?
    private var fnChannelGetUnitLabel: ChannelGetStringFn?
    private var fnSimpleGetIntegerValue: SimpleGetIntFn?

    // IOReportIterate needs special handling — it takes an ObjC block
    private typealias IterateFn = @convention(c)
        (CFDictionary, @convention(block) (CFDictionary) -> Int32) -> Void
    private var fnIterate: IterateFn?

    init() {
        loadIOReport()
    }

    deinit {
        if let handle = ioReportHandle {
            dlclose(handle)
        }
    }

    // MARK: - Setup

    private func loadIOReport() {
        // Try private framework first, then dylib
        let handle = dlopen(
            "/System/Library/PrivateFrameworks/IOReport.framework/IOReport",
            RTLD_NOW
        ) ?? dlopen("/usr/lib/libIOReport.dylib", RTLD_NOW)

        guard let handle else {
            isIOReportAvailable = false
            return
        }
        ioReportHandle = handle

        // Load all function pointers
        func load<T>(_ name: String) -> T? {
            guard let sym = dlsym(handle, name) else { return nil }
            return unsafeBitCast(sym, to: T.self)
        }

        fnCopyChannelsInGroup = load("IOReportCopyChannelsInGroup")
        fnMergeChannels = load("IOReportMergeChannels")
        fnCreateSubscription = load("IOReportCreateSubscription")
        fnCreateSamples = load("IOReportCreateSamples")
        fnCreateSamplesDelta = load("IOReportCreateSamplesDelta")
        fnChannelGetGroup = load("IOReportChannelGetGroup")
        fnChannelGetChannelName = load("IOReportChannelGetChannelName")
        fnChannelGetUnitLabel = load("IOReportChannelGetUnitLabel")
        fnSimpleGetIntegerValue = load("IOReportSimpleGetIntegerValue")
        fnIterate = load("IOReportIterate")

        // Verify all required functions loaded
        guard fnCopyChannelsInGroup != nil,
              fnCreateSubscription != nil,
              fnCreateSamples != nil,
              fnCreateSamplesDelta != nil,
              fnChannelGetGroup != nil,
              fnChannelGetChannelName != nil,
              fnChannelGetUnitLabel != nil,
              fnSimpleGetIntegerValue != nil,
              fnIterate != nil
        else {
            isIOReportAvailable = false
            dlclose(handle)
            ioReportHandle = nil
            return
        }

        // Subscribe to Energy Model channels
        guard let energyChannels = fnCopyChannelsInGroup!(
            "Energy Model" as CFString, nil, 0, 0, 0
        )?.takeRetainedValue() as CFDictionary? else {
            isIOReportAvailable = false
            return
        }

        var subbedPtr: Unmanaged<CFMutableDictionary>?
        let mutableChannels = energyChannels as! CFMutableDictionary
        subscription = fnCreateSubscription!(nil, mutableChannels, &subbedPtr, 0, nil)

        guard let subscription, let subbed = subbedPtr else {
            isIOReportAvailable = false
            return
        }

        subscribedChannels = subbed
        self.subscription = subscription
        isIOReportAvailable = true

        // Take initial baseline sample
        if let sample = fnCreateSamples!(subscription, subbed.takeUnretainedValue(), nil) {
            previousSample = sample.takeRetainedValue()
            previousTimestamp = Foundation.ProcessInfo.processInfo.systemUptime
        }
    }

    // MARK: - Sampling

    /// Take a new power sample. Call this each poll cycle.
    /// Returns the latest PowerSample, or a zero sample if IOReport is unavailable.
    @discardableResult
    func sample() -> PowerSample {
        guard isIOReportAvailable,
              let subscription,
              let subChannels = subscribedChannels,
              let previousSample
        else {
            return .zero
        }

        let now = Foundation.ProcessInfo.processInfo.systemUptime
        let interval = now - previousTimestamp
        guard interval > 0.1 else { return latestSample }  // Too soon

        guard let currentUnmanaged = fnCreateSamples!(
            subscription, subChannels.takeUnretainedValue(), nil
        ) else {
            return latestSample
        }
        let currentSample = currentUnmanaged.takeRetainedValue()

        guard let deltaUnmanaged = fnCreateSamplesDelta!(
            previousSample, currentSample, nil
        ) else {
            self.previousSample = currentSample
            self.previousTimestamp = now
            return latestSample
        }
        let delta = deltaUnmanaged.takeRetainedValue()

        // Parse the delta for energy values
        var pCoreEnergy: Double = 0
        var eCoreEnergy: Double = 0
        var gpuEnergy: Double = 0
        var aneEnergy: Double = 0
        var dramEnergy: Double = 0

        fnIterate!(delta) { [self] channelSample in
            guard let groupRef = self.fnChannelGetGroup!(channelSample),
                  let nameRef = self.fnChannelGetChannelName!(channelSample)
            else { return 0 }  // kIOReportIterOk

            let group = groupRef.takeUnretainedValue() as String
            let name = nameRef.takeUnretainedValue() as String

            guard group == "Energy Model" else { return 0 }

            let rawValue = self.fnSimpleGetIntegerValue!(channelSample, 0)
            let joules = self.energyToJoules(rawValue, channel: channelSample)

            // Categorize by channel name
            // Base chips: ECPU, PCPU, GPU, ANE, DRAM
            // Pro/Max: EACC_CPU, PACC0_CPU, PACC1_CPU, GPU0, ANE0, DRAM0
            // Ultra: DIE_0_EACC_CPU, etc.
            let upperName = name.uppercased()
            if upperName.contains("ECPU") || upperName.contains("EACC") {
                eCoreEnergy += joules
            } else if upperName.contains("PCPU") || upperName.contains("PACC") {
                pCoreEnergy += joules
            } else if upperName.contains("GPU") {
                gpuEnergy += joules
            } else if upperName.contains("ANE") {
                aneEnergy += joules
            } else if upperName.contains("DRAM") {
                dramEnergy += joules
            }

            return 0  // kIOReportIterOk
        }

        // Convert energy (joules) to power (watts) by dividing by interval
        let result = PowerSample(
            timestamp: now,
            cpuWatts: (pCoreEnergy + eCoreEnergy) / interval,
            gpuWatts: gpuEnergy / interval,
            aneWatts: aneEnergy / interval,
            dramWatts: dramEnergy / interval,
            packageWatts: (pCoreEnergy + eCoreEnergy + gpuEnergy + aneEnergy + dramEnergy) / interval,
            pCoreWatts: pCoreEnergy / interval,
            eCoreWatts: eCoreEnergy / interval
        )

        self.previousSample = currentSample
        self.previousTimestamp = now
        self.latestSample = result
        return result
    }

    // MARK: - Helpers

    private func energyToJoules(_ rawValue: Int64, channel: CFDictionary) -> Double {
        let unitRef = fnChannelGetUnitLabel?(channel)
        let unit = unitRef?.takeUnretainedValue() as String? ?? "nJ"
        let value = Double(rawValue)

        switch unit {
        case "mJ": return value / 1_000
        case "uJ": return value / 1_000_000
        case "nJ": return value / 1_000_000_000
        default:   return value / 1_000_000_000  // assume nJ if unknown
        }
    }
}
