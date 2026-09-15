import Foundation
import Darwin
import CoreGraphics

struct SwapCounterReading {
    let uptime: Double
    let wallTime: Double
    let swapInPages: UInt64
    let swapOutPages: UInt64
}

// Rates require two successful, comparable observations. A counter total or an
// existing swap file is not evidence of swapping during the current incident.
func swapRates(previous: SwapCounterReading?, current: SwapCounterReading,
               pageSize: UInt64, maxGapSeconds: Double = 90) -> [String: Any] {
    var result: [String: Any] = ["swap_in_mbps": NSNull(), "swap_out_mbps": NSNull(), "swap_sample_seconds": NSNull()]
    guard let previous = previous else { result["swap_rate_status"] = "first_sample"; return result }
    let elapsed = current.uptime - previous.uptime, wallElapsed = current.wallTime - previous.wallTime
    guard elapsed > 0, elapsed <= maxGapSeconds, wallElapsed > 0, wallElapsed <= maxGapSeconds,
          abs(wallElapsed - elapsed) <= 5 else { result["swap_rate_status"] = "sample_gap_or_clock_change"; return result }
    guard current.swapInPages >= previous.swapInPages, current.swapOutPages >= previous.swapOutPages else {
        result["swap_rate_status"] = "counter_reset"; return result
    }
    result["swap_in_mbps"] = Double(current.swapInPages - previous.swapInPages) * Double(pageSize) / 1048576 / elapsed
    result["swap_out_mbps"] = Double(current.swapOutPages - previous.swapOutPages) * Double(pageSize) / 1048576 / elapsed
    result["swap_sample_seconds"] = elapsed; result["swap_rate_status"] = "measured"
    return result
}

final class SystemTelemetrySampler {
    private var previousSwap: SwapCounterReading?
    private let maxRateGapSeconds: Double
    init(maxRateGapSeconds: Double = 90) { self.maxRateGapSeconds = max(1, maxRateGapSeconds) }

    func sample() -> [String: Any] {
        let uptime = ProcessInfo.processInfo.systemUptime
        var result: [String: Any] = ["uptime_seconds": uptime,
                                   "physical_memory_mb": Double(ProcessInfo.processInfo.physicalMemory) / 1048576]
        var health: [String: Any] = [:]
        var vm = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let host = mach_host_self()
        let status = withUnsafeMutablePointer(to: &vm) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(host, HOST_VM_INFO64, $0, &count)
            }
        }
        mach_port_deallocate(mach_task_self_, host)
        if status == KERN_SUCCESS {
            let pageSize = UInt64(getpagesize())
            let reading = SwapCounterReading(uptime: uptime, wallTime: Date().timeIntervalSince1970,
                                             swapInPages: vm.swapins, swapOutPages: vm.swapouts)
            result.merge(swapRates(previous: previousSwap, current: reading, pageSize: pageSize,
                                   maxGapSeconds: maxRateGapSeconds)) { _, new in new }
            previousSwap = reading
            result["compressed_mb"] = Double(vm.compressor_page_count) * Double(pageSize) / 1048576
            result["compressed_uncompressed_equivalent_mb"] = Double(vm.total_uncompressed_pages_in_compressor) * Double(pageSize) / 1048576
            health["vm_statistics_succeeded"] = true
        } else {
            previousSwap = nil
            result["swap_in_mbps"] = NSNull(); result["swap_out_mbps"] = NSNull()
            result["swap_sample_seconds"] = NSNull(); result["swap_rate_status"] = "collection_failed"
            result["compressed_mb"] = NSNull(); result["compressed_uncompressed_equivalent_mb"] = NSNull()
            health["vm_statistics_succeeded"] = false; health["vm_statistics_error"] = status
        }

        var swap = xsw_usage(); var swapSize = MemoryLayout<xsw_usage>.size
        if sysctlbyname("vm.swapusage", &swap, &swapSize, nil, 0) == 0 {
            result["swap_used_mb"] = Double(swap.xsu_used) / 1048576
            health["swap_usage_succeeded"] = true
        } else {
            result["swap_used_mb"] = NSNull(); health["swap_usage_succeeded"] = false; health["swap_usage_errno"] = errno
        }
        var pressure: Int32 = 0; var pressureSize = MemoryLayout<Int32>.size
        if sysctlbyname("kern.memorystatus_vm_pressure_level", &pressure, &pressureSize, nil, 0) == 0 {
            result["memory_pressure"] = Int(pressure); health["pressure_succeeded"] = true
        } else {
            result["memory_pressure"] = NSNull(); health["pressure_succeeded"] = false; health["pressure_errno"] = errno
        }
        let thermal = ProcessInfo.processInfo.thermalState
        result["thermal_state"] = thermal.rawValue
        switch thermal {
        case .nominal: result["thermal_state_name"] = "nominal"
        case .fair: result["thermal_state_name"] = "fair"
        case .serious: result["thermal_state_name"] = "serious"
        case .critical: result["thermal_state_name"] = "critical"
        @unknown default: result["thermal_state_name"] = "unknown"
        }

        var displayCount: UInt32 = 0
        let countStatus = CGGetActiveDisplayList(0, nil, &displayCount)
        if countStatus == .success {
            var ids = [CGDirectDisplayID](repeating: 0, count: Int(displayCount))
            let listStatus = CGGetActiveDisplayList(displayCount, &ids, &displayCount)
            if listStatus == .success {
                result["active_display_count"] = Int(displayCount)
                result["displays"] = ids.prefix(Int(displayCount)).map { id -> [String: Any] in
                    let mode = CGDisplayCopyDisplayMode(id)
                    return ["display_id": id, "built_in": CGDisplayIsBuiltin(id) != 0,
                            "asleep": CGDisplayIsAsleep(id) != 0,
                            "pixel_width": mode?.pixelWidth as Any? ?? NSNull(),
                            "pixel_height": mode?.pixelHeight as Any? ?? NSNull(),
                            "logical_width": mode?.width as Any? ?? NSNull(),
                            "logical_height": mode?.height as Any? ?? NSNull(),
                            "refresh_hz": mode.flatMap { $0.refreshRate > 0 ? $0.refreshRate : nil } as Any? ?? NSNull()]
                }
                health["displays_succeeded"] = true
            } else {
                result["active_display_count"] = NSNull(); result["displays"] = NSNull()
                health["displays_succeeded"] = false; health["displays_error"] = listStatus.rawValue
            }
        } else {
            result["active_display_count"] = NSNull(); result["displays"] = NSNull()
            health["displays_succeeded"] = false; health["displays_error"] = countStatus.rawValue
        }
        result["telemetry_health"] = health
        return result
    }
}
