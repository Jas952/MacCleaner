import Foundation

struct AssistantPrompt: Identifiable {
    var id: String { text }
    let text: String
    let icon: String
    let tool: String

    static let starters: [Self] = [
        .init(text: "Check Mac health", icon: "desktopcomputer", tool: "check_system_status"),
        .init(text: "Find large files", icon: "doc", tool: "scan_large_files"),
        .init(text: "Uninstall app", icon: "app.badge", tool: "uninstall_app"),
        .init(text: "Check temperature", icon: "thermometer", tool: "check_thermal_state"),
        .init(text: "Show processes", icon: "cpu", tool: "list_processes"),
        .init(text: "Test my connection", icon: "network", tool: "run_network_test")
    ]

    static func completions(for text: String) -> [Self] {
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return [] }
        return all.filter { $0.text.lowercased().hasPrefix(query) && $0.text.lowercased() != query }
    }

    static let all: [Self] = starters + [
        .init(text: "Organize Downloads", icon: "folder", tool: "organize_folder"),
        .init(text: "Organize Desktop", icon: "desktopcomputer", tool: "organize_folder"),
        .init(text: "Find files over 1 GB", icon: "doc", tool: "scan_large_files"),
        .init(text: "Find files over 5 GB", icon: "doc", tool: "scan_large_files"),
        .init(text: "Check battery health", icon: "battery.100", tool: "check_battery_health"),
        .init(text: "Show startup items", icon: "power", tool: "list_startup_items"),
        .init(text: "Find duplicate files", icon: "doc.on.doc", tool: "scan_duplicates")
    ]
}

/// Presentation metadata only. No command is executed by the preview catalog.
struct AssistantToolPresentation: Identifiable {
    enum Layout { case metrics, files, applications, processes, operation, navigation, clarification }
    let id: String
    let title: String
    let layout: Layout
    var icon: String {
        switch layout {
        case .metrics: return "chart.bar"
        case .files: return "doc.on.doc"
        case .applications: return "app"
        case .processes: return "cpu"
        case .operation: return "checklist"
        case .navigation: return "rectangle.on.rectangle"
        case .clarification: return "questionmark.bubble"
        }
    }
    static let all: [Self] = [
        .init(id: "request_clarification", title: "Clarify request", layout: .clarification),
        .init(id: "check_system_status", title: "Mac health", layout: .metrics),
        .init(id: "list_processes", title: "Running processes", layout: .processes),
        .init(id: "find_heavy_processes", title: "Resource-heavy processes", layout: .processes),
        .init(id: "show_windows", title: "Open windows", layout: .navigation),
        .init(id: "show_ai_workloads", title: "Local AI workloads", layout: .processes),
        .init(id: "scan_junk_files", title: "Cleanup overview", layout: .files),
        .init(id: "scan_large_files", title: "Large files", layout: .files),
        .init(id: "scan_duplicates", title: "Duplicate files", layout: .files),
        .init(id: "scan_similar_photos", title: "Similar photos", layout: .files),
        .init(id: "show_disk_map", title: "Storage map", layout: .metrics),
        .init(id: "scan_storage", title: "Storage analysis", layout: .files),
        .init(id: "clean_selected_items", title: "Clean selected items", layout: .operation),
        .init(id: "move_items_to_trash", title: "Move to Trash", layout: .operation),
        .init(id: "reclaim_cloud_storage", title: "Reclaim cloud storage", layout: .operation),
        .init(id: "find_old_installers", title: "Old installers", layout: .files),
        .init(id: "find_developer_caches", title: "Developer caches", layout: .files),
        .init(id: "find_ai_caches", title: "AI caches", layout: .files),
        .init(id: "list_installed_apps", title: "Installed applications", layout: .applications),
        .init(id: "uninstall_app", title: "Uninstall application", layout: .applications),
        .init(id: "show_app_related_files", title: "Application-related files", layout: .files),
        .init(id: "list_startup_items", title: "Startup items", layout: .applications),
        .init(id: "disable_startup_item", title: "Disable startup item", layout: .operation),
        .init(id: "restore_startup_item", title: "Restore startup item", layout: .operation),
        .init(id: "check_for_updates", title: "Application updates", layout: .applications),
        .init(id: "run_doctor_mode", title: "Full diagnostics", layout: .metrics),
        .init(id: "run_maintenance", title: "System maintenance", layout: .operation),
        .init(id: "flush_dns", title: "Flush DNS cache", layout: .operation),
        .init(id: "show_fan_status", title: "Fan status", layout: .metrics),
        .init(id: "check_thermal_state", title: "Temperature", layout: .metrics),
        .init(id: "check_battery_health", title: "Battery health", layout: .metrics),
        .init(id: "check_ssd_health", title: "SSD health", layout: .metrics),
        .init(id: "run_network_test", title: "Network diagnostics", layout: .metrics),
        .init(id: "run_speaker_test", title: "Speaker test", layout: .operation),
        .init(id: "run_keyboard_test", title: "Keyboard test", layout: .operation),
        .init(id: "navigate_to", title: "Open section", layout: .navigation),
        .init(id: "search_files", title: "File search", layout: .files),
        .init(id: "organize_folder", title: "Organize folder", layout: .operation),
        .init(id: "inspect_homebrew", title: "Homebrew packages", layout: .applications)
    ]
}

enum AssistantPreviewPhase: String, CaseIterable, Identifiable {
    case running = "Running", result = "Complete", confirmation = "Review"
    case deferred = "Continuing"
    case empty = "No results", failed = "Failed", cancelled = "Cancelled"
    var id: String { rawValue }
}
