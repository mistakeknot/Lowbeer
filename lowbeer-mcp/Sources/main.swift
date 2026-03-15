import Darwin
import Foundation
import IOKit.ps

// MARK: - JSON-RPC / MCP Protocol

/// Minimal MCP server over stdio (JSON-RPC 2.0).
/// Supports: initialize, tools/list, tools/call, notifications/initialized.

func writeResponse(_ json: [String: Any]) {
    guard let data = try? JSONSerialization.data(withJSONObject: json) else { return }
    // Newline-delimited JSON: one JSON object per line, no embedded newlines
    var bytes = [UInt8](data)
    bytes.append(0x0A)  // \n
    bytes.withUnsafeBufferPointer { buf in
        _ = Darwin.write(STDOUT_FILENO, buf.baseAddress!, buf.count)
    }
}

func makeResponse(id: Any, result: Any) -> [String: Any] {
    ["jsonrpc": "2.0", "id": id, "result": result]
}

func makeError(id: Any, code: Int, message: String) -> [String: Any] {
    ["jsonrpc": "2.0", "id": id, "error": ["code": code, "message": message]]
}

// MARK: - Process Sampling (libproc)

private let PROC_PIDPATHINFO_SIZE: UInt32 = 4096

struct ProcSample {
    let pid: pid_t
    let name: String
    let path: String
    let totalNs: UInt64
    let timestamp: CFAbsoluteTime
    let residentBytes: UInt64
}

func sampleAllProcesses() -> [pid_t: ProcSample] {
    let bufferSize = proc_listallpids(nil, 0)
    guard bufferSize > 0 else { return [:] }

    var pids = [pid_t](repeating: 0, count: Int(bufferSize))
    let count = proc_listallpids(&pids, Int32(MemoryLayout<pid_t>.size * pids.count))
    guard count > 0 else { return [:] }

    let now = CFAbsoluteTimeGetCurrent()
    var results = [pid_t: ProcSample]()
    results.reserveCapacity(Int(count))

    for i in 0..<Int(count) {
        let pid = pids[i]
        guard pid > 0 else { continue }

        var taskInfo = proc_taskinfo()
        let size = Int32(MemoryLayout<proc_taskinfo>.size)
        let ret = proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &taskInfo, size)
        guard ret == size else { continue }

        var pathBuffer = [CChar](repeating: 0, count: Int(PROC_PIDPATHINFO_SIZE))
        let pathLen = proc_pidpath(pid, &pathBuffer, UInt32(pathBuffer.count))

        let path: String
        let name: String
        if pathLen > 0 {
            path = String(cString: pathBuffer)
            name = (path as NSString).lastPathComponent
        } else {
            var nameBuffer = [CChar](repeating: 0, count: Int(MAXCOMLEN + 1))
            proc_name(pid, &nameBuffer, UInt32(nameBuffer.count))
            name = String(cString: nameBuffer)
            path = name
        }

        results[pid] = ProcSample(
            pid: pid,
            name: name,
            path: path,
            totalNs: taskInfo.pti_total_user + taskInfo.pti_total_system,
            timestamp: now,
            residentBytes: taskInfo.pti_resident_size
        )
    }
    return results
}

// MARK: - IOReport Power Sampling

private typealias CopyChannelsInGroupFn = @convention(c)
    (CFString?, CFString?, UInt64, UInt64, UInt64) -> Unmanaged<CFDictionary>?
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
private typealias IterateFn = @convention(c)
    (CFDictionary, @convention(block) (CFDictionary) -> Int32) -> Void

struct PowerReading {
    var cpuWatts: Double = 0
    var gpuWatts: Double = 0
    var aneWatts: Double = 0
    var dramWatts: Double = 0
    var pCoreWatts: Double = 0
    var eCoreWatts: Double = 0
    var totalWatts: Double { cpuWatts + gpuWatts + aneWatts + dramWatts }
}

func samplePower(delaySeconds: Double = 1.0) -> PowerReading? {
    let handle = dlopen(
        "/System/Library/PrivateFrameworks/IOReport.framework/IOReport",
        RTLD_NOW
    ) ?? dlopen("/usr/lib/libIOReport.dylib", RTLD_NOW)
    guard let handle else { return nil }
    defer { dlclose(handle) }

    func load<T>(_ name: String) -> T? {
        guard let sym = dlsym(handle, name) else { return nil }
        return unsafeBitCast(sym, to: T.self)
    }

    guard let fnCopyChannels: CopyChannelsInGroupFn = load("IOReportCopyChannelsInGroup"),
          let fnCreateSub: CreateSubscriptionFn = load("IOReportCreateSubscription"),
          let fnCreateSamples: CreateSamplesFn = load("IOReportCreateSamples"),
          let fnCreateDelta: CreateSamplesDeltaFn = load("IOReportCreateSamplesDelta"),
          let fnGetGroup: ChannelGetStringFn = load("IOReportChannelGetGroup"),
          let fnGetName: ChannelGetStringFn = load("IOReportChannelGetChannelName"),
          let fnGetUnit: ChannelGetStringFn = load("IOReportChannelGetUnitLabel"),
          let fnGetInt: SimpleGetIntFn = load("IOReportSimpleGetIntegerValue"),
          let fnIterate: IterateFn = load("IOReportIterate")
    else { return nil }

    guard let channels = fnCopyChannels("Energy Model" as CFString, nil, 0, 0, 0)?
            .takeRetainedValue() as CFDictionary?
    else { return nil }

    let mutableChannels = channels as! CFMutableDictionary
    var subbedPtr: Unmanaged<CFMutableDictionary>?
    guard let sub = fnCreateSub(nil, mutableChannels, &subbedPtr, 0, nil),
          let subbed = subbedPtr
    else { return nil }

    // First sample (baseline)
    guard let s1 = fnCreateSamples(sub, subbed.takeUnretainedValue(), nil) else { return nil }
    let sample1 = s1.takeRetainedValue()
    let t1 = ProcessInfo.processInfo.systemUptime

    // Wait for measurement interval
    Thread.sleep(forTimeInterval: delaySeconds)

    // Second sample
    guard let s2 = fnCreateSamples(sub, subbed.takeUnretainedValue(), nil) else { return nil }
    let sample2 = s2.takeRetainedValue()
    let t2 = ProcessInfo.processInfo.systemUptime
    let interval = t2 - t1
    guard interval > 0.01 else { return nil }

    guard let deltaUnmanaged = fnCreateDelta(sample1, sample2, nil) else { return nil }
    let delta = deltaUnmanaged.takeRetainedValue()

    var pCoreJ: Double = 0, eCoreJ: Double = 0
    var gpuJ: Double = 0, aneJ: Double = 0, dramJ: Double = 0

    fnIterate(delta) { channelSample in
        guard let groupRef = fnGetGroup(channelSample),
              let nameRef = fnGetName(channelSample)
        else { return 0 }

        let group = groupRef.takeUnretainedValue() as String
        let name = nameRef.takeUnretainedValue() as String
        guard group == "Energy Model" else { return 0 }

        let rawValue = fnGetInt(channelSample, 0)
        let unitRef = fnGetUnit(channelSample)
        let unit = unitRef?.takeUnretainedValue() as String? ?? "nJ"
        let value = Double(rawValue)
        let joules: Double
        switch unit {
        case "mJ": joules = value / 1_000
        case "uJ": joules = value / 1_000_000
        default:   joules = value / 1_000_000_000  // nJ
        }

        if name.localizedCaseInsensitiveContains("ECPU") || name.localizedCaseInsensitiveContains("EACC") {
            eCoreJ += joules
        } else if name.localizedCaseInsensitiveContains("PCPU") || name.localizedCaseInsensitiveContains("PACC") {
            pCoreJ += joules
        } else if name.localizedCaseInsensitiveContains("GPU") {
            gpuJ += joules
        } else if name.localizedCaseInsensitiveContains("ANE") {
            aneJ += joules
        } else if name.localizedCaseInsensitiveContains("DRAM") {
            dramJ += joules
        }
        return 0
    }

    return PowerReading(
        cpuWatts: (pCoreJ + eCoreJ) / interval,
        gpuWatts: gpuJ / interval,
        aneWatts: aneJ / interval,
        dramWatts: dramJ / interval,
        pCoreWatts: pCoreJ / interval,
        eCoreWatts: eCoreJ / interval
    )
}

// MARK: - Battery State

func getBatteryInfo() -> [String: Any] {
    guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
          let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [Any],
          let firstSource = sources.first,
          let desc = IOPSGetPowerSourceDescription(snapshot, firstSource as CFTypeRef)?
              .takeUnretainedValue() as? [String: Any]
    else {
        return ["available": false]
    }

    let powerSource = desc[kIOPSPowerSourceStateKey as String] as? String
    let isOnBattery = powerSource == kIOPSBatteryPowerValue as String
    let currentCap = desc[kIOPSCurrentCapacityKey as String] as? Int ?? 0
    let maxCap = desc[kIOPSMaxCapacityKey as String] as? Int ?? 100
    let isCharging = desc[kIOPSIsChargingKey as String] as? Bool ?? false

    return [
        "available": true,
        "on_battery": isOnBattery,
        "charging": isCharging,
        "percent": currentCap,
        "max_capacity": maxCap,
    ]
}

// MARK: - Tool Implementations

func handleGetProcesses(args: [String: Any]) -> Any {
    let limit = args["limit"] as? Int ?? 15
    let sortBy = args["sort_by"] as? String ?? "cpu"

    // Take two samples to compute CPU delta
    let s1 = sampleAllProcesses()
    Thread.sleep(forTimeInterval: 1.0)
    let s2 = sampleAllProcesses()

    struct ProcessResult {
        let pid: pid_t
        let name: String
        let path: String
        let cpuPercent: Double
        let ramMB: Double
    }

    var results = [ProcessResult]()
    for (pid, current) in s2 {
        guard let previous = s1[pid] else { continue }
        let deltaNs = current.totalNs - previous.totalNs
        let deltaTime = current.timestamp - previous.timestamp
        guard deltaTime > 0 else { continue }
        let cpuPercent = (Double(deltaNs) / (deltaTime * 1_000_000_000)) * 100.0
        guard cpuPercent >= 0.1 else { continue }
        let ramMB = Double(current.residentBytes) / (1024 * 1024)
        results.append(ProcessResult(pid: pid, name: current.name, path: current.path,
                                     cpuPercent: cpuPercent, ramMB: ramMB))
    }

    switch sortBy {
    case "ram":
        results.sort { $0.ramMB > $1.ramMB }
    default:
        results.sort { $0.cpuPercent > $1.cpuPercent }
    }

    let top = results.prefix(limit)
    let totalCPU = results.reduce(0.0) { $0 + $1.cpuPercent }

    var processList = [[String: Any]]()
    for p in top {
        processList.append([
            "pid": p.pid,
            "name": p.name,
            "path": p.path,
            "cpu_percent": round(p.cpuPercent * 10) / 10,
            "ram_mb": round(p.ramMB * 10) / 10,
        ])
    }

    return [
        "total_cpu_percent": round(totalCPU * 10) / 10,
        "process_count": results.count,
        "showing": min(limit, results.count),
        "sorted_by": sortBy,
        "processes": processList,
    ] as [String: Any]
}

func handleGetSystemPower() -> Any {
    guard let power = samplePower(delaySeconds: 1.0) else {
        return ["error": "IOReport unavailable (not Apple Silicon?)"]
    }

    return [
        "total_watts": round(power.totalWatts * 100) / 100,
        "cpu_watts": round(power.cpuWatts * 100) / 100,
        "gpu_watts": round(power.gpuWatts * 100) / 100,
        "ane_watts": round(power.aneWatts * 100) / 100,
        "dram_watts": round(power.dramWatts * 100) / 100,
        "p_core_watts": round(power.pCoreWatts * 100) / 100,
        "e_core_watts": round(power.eCoreWatts * 100) / 100,
        "battery": getBatteryInfo(),
    ] as [String: Any]
}

func handleGetTopEnergy(args: [String: Any]) -> Any {
    let limit = args["limit"] as? Int ?? 10

    // Sample processes + power simultaneously over 2 seconds for better accuracy
    let s1 = sampleAllProcesses()
    guard let power = samplePower(delaySeconds: 2.0) else {
        return ["error": "IOReport unavailable"]
    }
    let s2 = sampleAllProcesses()

    struct EnergyResult {
        let name: String
        let path: String
        let cpuPercent: Double
        let watts: Double
        let ramMB: Double
        let pid: pid_t
    }

    var results = [EnergyResult]()
    var totalCPU: Double = 0

    // First pass: compute CPU% for all processes
    var cpuByPID = [(pid: pid_t, name: String, path: String, cpu: Double, ram: Double)]()
    for (pid, current) in s2 {
        guard let previous = s1[pid] else { continue }
        let deltaNs = current.totalNs - previous.totalNs
        let deltaTime = current.timestamp - previous.timestamp
        guard deltaTime > 0 else { continue }
        let cpuPercent = (Double(deltaNs) / (deltaTime * 1_000_000_000)) * 100.0
        guard cpuPercent >= 0.1 else { continue }
        totalCPU += cpuPercent
        cpuByPID.append((pid, current.name, current.path, cpuPercent,
                         Double(current.residentBytes) / (1024 * 1024)))
    }

    // Second pass: compute per-process watts
    let systemWatts = min(power.totalWatts, 120.0)
    if totalCPU >= 1.0, systemWatts >= 1.0 {
        for p in cpuByPID {
            let share = p.cpu / totalCPU
            let watts = share * systemWatts
            results.append(EnergyResult(name: p.name, path: p.path, cpuPercent: p.cpu,
                                        watts: watts, ramMB: p.ram, pid: p.pid))
        }
    }

    results.sort { $0.watts > $1.watts }

    var processList = [[String: Any]]()
    for p in results.prefix(limit) {
        processList.append([
            "pid": p.pid,
            "name": p.name,
            "cpu_percent": round(p.cpuPercent * 10) / 10,
            "watts": round(p.watts * 100) / 100,
            "ram_mb": round(p.ramMB * 10) / 10,
        ])
    }

    return [
        "system_watts": round(systemWatts * 100) / 100,
        "total_cpu_percent": round(totalCPU * 10) / 10,
        "showing": min(limit, results.count),
        "battery": getBatteryInfo(),
        "processes": processList,
    ] as [String: Any]
}

func handleGetBattery() -> Any {
    return getBatteryInfo()
}

func handleGetMemory(args: [String: Any]) -> Any {
    let limit = args["limit"] as? Int ?? 10
    let thresholdGB = args["threshold_gb"] as? Double ?? 10.0
    let thresholdBytes = UInt64(thresholdGB * 1024 * 1024 * 1024)

    let samples = sampleAllProcesses()

    struct MemResult {
        let pid: pid_t
        let name: String
        let ramMB: Double
        let ramGB: Double
    }

    let results = samples.values.map { s in
        MemResult(
            pid: s.pid,
            name: s.name,
            ramMB: Double(s.residentBytes) / (1024 * 1024),
            ramGB: Double(s.residentBytes) / (1024 * 1024 * 1024)
        )
    }.filter { $0.ramMB >= 1.0 }  // At least 1 MB
    .sorted { $0.ramMB > $1.ramMB }

    var processList = [[String: Any]]()
    var anomalyList = [[String: Any]]()

    for p in results.prefix(limit) {
        var entry: [String: Any] = [
            "pid": p.pid,
            "name": p.name,
            "ram_mb": round(p.ramMB * 10) / 10,
            "ram_gb": round(p.ramGB * 100) / 100,
        ]
        if UInt64(p.ramGB * 1024 * 1024 * 1024) > thresholdBytes {
            entry["anomaly"] = "exceeds_threshold"
            anomalyList.append(entry)
        }
        processList.append(entry)
    }

    let totalMB = results.reduce(0.0) { $0 + $1.ramMB }

    return [
        "total_tracked_mb": round(totalMB * 10) / 10,
        "total_tracked_gb": round(totalMB / 1024 * 100) / 100,
        "process_count": results.count,
        "showing": min(limit, results.count),
        "threshold_gb": thresholdGB,
        "anomalies": anomalyList,
        "processes": processList,
    ] as [String: Any]
}

// MARK: - MCP Tool Definitions

func makeTools() -> [[String: Any]] { [
    [
        "name": "get_processes",
        "description": "Get top processes by CPU usage or RAM. Shows process name, PID, CPU%, and RAM (MB). Takes a 1-second measurement window for accurate CPU deltas.",
        "inputSchema": [
            "type": "object",
            "properties": [
                "limit": ["type": "integer", "description": "Max processes to return (default: 15)", "default": 15],
                "sort_by": ["type": "string", "enum": ["cpu", "ram"], "description": "Sort by cpu or ram (default: cpu)", "default": "cpu"],
            ],
        ],
    ],
    [
        "name": "get_system_power",
        "description": "Get real-time system power draw in watts from Apple Silicon IOReport. Shows breakdown by CPU (P-cores, E-cores), GPU, Neural Engine, and DRAM. Also includes battery state (on battery/AC, charge %). Takes a 1-second measurement.",
        "inputSchema": ["type": "object", "properties": [:]],
    ],
    [
        "name": "get_top_energy",
        "description": "Get processes ranked by estimated energy consumption (watts). Combines CPU measurement with IOReport power data to show per-process wattage. Best tool for answering 'what is draining my battery?' Takes a 2-second measurement.",
        "inputSchema": [
            "type": "object",
            "properties": [
                "limit": ["type": "integer", "description": "Max processes to return (default: 10)", "default": 10],
            ],
        ],
    ],
    [
        "name": "get_battery",
        "description": "Get battery status: on AC or battery power, charge percentage, whether charging.",
        "inputSchema": ["type": "object", "properties": [:]],
    ],
    [
        "name": "get_memory",
        "description": "Get processes with highest memory (RAM) usage. Flags anomalies: processes exceeding a threshold (default 10 GB). Instant measurement, no delay.",
        "inputSchema": [
            "type": "object",
            "properties": [
                "limit": ["type": "integer", "description": "Max processes to return (default: 10)", "default": 10],
                "threshold_gb": ["type": "number", "description": "Flag processes above this GB threshold (default: 10)", "default": 10],
            ],
        ],
    ],
] }

// MARK: - Request Handling

func handleRequest(_ request: [String: Any]) {
    let method = request["method"] as? String ?? ""
    let id = request["id"]  // nil for notifications
    let params = request["params"] as? [String: Any] ?? [:]

    switch method {
    case "initialize":
        let result: [String: Any] = [
            "protocolVersion": "2024-11-05",
            "capabilities": ["tools": [:]],
            "serverInfo": [
                "name": "lowbeer-mcp",
                "version": "0.1.0",
            ],
        ]
        writeResponse(makeResponse(id: id!, result: result))

    case "notifications/initialized":
        break  // No response needed

    case "tools/list":
        writeResponse(makeResponse(id: id!, result: ["tools": makeTools()]))

    case "tools/call":
        let toolName = params["name"] as? String ?? ""
        let args = params["arguments"] as? [String: Any] ?? [:]

        let toolResult: Any
        switch toolName {
        case "get_processes":
            toolResult = handleGetProcesses(args: args)
        case "get_system_power":
            toolResult = handleGetSystemPower()
        case "get_top_energy":
            toolResult = handleGetTopEnergy(args: args)
        case "get_battery":
            toolResult = handleGetBattery()
        case "get_memory":
            toolResult = handleGetMemory(args: args)
        default:
            writeResponse(makeError(id: id!, code: -32601, message: "Unknown tool: \(toolName)"))
            return
        }

        // Format as MCP tool result
        let jsonData = try! JSONSerialization.data(withJSONObject: toolResult)
        let jsonStr = String(data: jsonData, encoding: .utf8)!

        let result: [String: Any] = [
            "content": [
                ["type": "text", "text": jsonStr]
            ]
        ]
        writeResponse(makeResponse(id: id!, result: result))

    case "ping":
        writeResponse(makeResponse(id: id!, result: [:]))

    default:
        if let id {
            writeResponse(makeError(id: id, code: -32601, message: "Method not found: \(method)"))
        }
    }
}

// MARK: - Main Loop (newline-delimited JSON over stdio)

// Prevent buffering on stdout
setbuf(stdout, nil)

/// Read a line from stdin using raw read() — Swift's readLine() can hang on EOF in release builds.
func readStdinLine() -> String? {
    var bytes = [UInt8]()
    var buf: UInt8 = 0
    while true {
        let n = Darwin.read(STDIN_FILENO, &buf, 1)
        if n <= 0 { return bytes.isEmpty ? nil : String(bytes: bytes, encoding: .utf8) }
        if buf == 0x0A { break }  // \n
        if buf != 0x0D { bytes.append(buf) }  // skip \r
    }
    return String(bytes: bytes, encoding: .utf8)
}

while let line = readStdinLine() {
    let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty,
          let data = trimmed.data(using: .utf8),
          let request = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else { continue }
    handleRequest(request)
}
