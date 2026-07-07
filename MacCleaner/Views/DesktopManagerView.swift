import SwiftUI
import AppKit
import QuickLook
import UniformTypeIdentifiers

// MARK: - Thumbnail Cache

final class ThumbnailCache {
    static let shared = ThumbnailCache()
    private let cache = NSCache<NSURL, NSImage>()
    private init() {
        cache.countLimit = 300
        cache.totalCostLimit = 150 * 1024 * 1024  // 150 MB
    }
    func get(_ url: URL) -> NSImage? { cache.object(forKey: url as NSURL) }
    func set(_ img: NSImage, for url: URL) {
        let cost = Int(img.size.width * img.size.height * 4)
        cache.setObject(img, forKey: url as NSURL, cost: cost)
    }
}

// MARK: - Quick-select groups

enum FileGroup: String, CaseIterable {
    case images    = "Images"
    case screenshots = "Screenshots"
    case documents = "Documents"
    case archives  = "Archives"
    case video     = "Video"
    case audio     = "Audio"
    case code      = "Code"

    var icon: String {
        switch self {
        case .images:      return "photo.on.rectangle"
        case .screenshots: return "camera.viewfinder"
        case .documents:   return "doc.text"
        case .archives:    return "archivebox"
        case .video:       return "film"
        case .audio:       return "music.note"
        case .code:        return "chevron.left.forwardslash.chevron.right"
        }
    }
    var color: Color {
        switch self {
        case .images:      return .blue
        case .screenshots: return .purple
        case .documents:   return .orange
        case .archives:    return .brown
        case .video:       return .pink
        case .audio:       return .green
        case .code:        return .cyan
        }
    }
    var categories: [DesktopFileCategory] {
        switch self {
        case .images:      return [.image]
        case .screenshots: return [.screenshot]
        case .documents:   return [.document]
        case .archives:    return [.archive]
        case .video:       return [.video]
        case .audio:       return [.audio]
        case .code:        return [.code]
        }
    }
}

// MARK: - Main View

struct DesktopManagerView: View {
    @ObservedObject var service: DesktopService
    @Binding var operationActive: Bool
    @State private var previewFile: DesktopFile? = nil
    @State private var metadataFile: DesktopFile? = nil
    @State private var showRenameSheet = false
    @State private var renameTarget: DesktopFile? = nil
    @State private var renameText = ""
    @State private var showDeleteConfirm = false
    @State private var pendingTrashFiles: [DesktopFile] = []
    @State private var showAutoOrganizeAlert = false
    @State private var organizeInProgress = false
    @State private var autoOrganizeResult: String? = nil
    @State private var showNewFolderSheet = false
    @State private var newFolderName = ""
    @State private var showMovePanel = false
    @State private var dropTargetID: UUID? = nil

    private var isWorking: Bool {
        operationActive || service.isScanning || organizeInProgress
    }

    var body: some View {
        VStack(spacing: 0) {
            // ── Header (always visible, never rebuilds) ──
            headerBar
            Divider()

            HSplitView {
                sidebarPanel.frame(minWidth: 200, maxWidth: 230)
                filesContent
            }
        }
        .onAppear {
            if service.files.isEmpty { service.scanCurrentDirectory() }
            if service.desktopRecursiveFiles.isEmpty { service.scanDesktopSummary() }
        }
        .sheet(item: $previewFile) { file in
            DesktopFilePreview(file: file, service: service,
                               onMetadata: { metadataFile = file },
                               onTrashRequest: { requestTrash([file]) })
        }
        .sheet(item: $metadataFile) { file in
            ImageMetadataSheet(file: file, service: service)
        }
        .sheet(isPresented: $showRenameSheet) { renameSheet }
        .sheet(isPresented: $showNewFolderSheet) { newFolderSheet }
        .alert("Auto-Organize Desktop", isPresented: $showAutoOrganizeAlert) {
            Button("Organize", role: .destructive) { runAutoOrganize() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Files will be moved into subfolders by type on your Desktop. Undoable via Trash.")
        }
        .alert("Delete Selected", isPresented: $showDeleteConfirm) {
            Button("Move to Trash", role: .destructive) { confirmPendingTrash() }
            Button("Cancel", role: .cancel) { pendingTrashFiles = [] }
        } message: {
            Text("Move \(pendingTrashFiles.count) file(s) to Trash?")
        }
    }

    // Files-tab outer wrapper: sidebar is stable, only content area reacts to isScanning
    private var filesContent: some View {
        mainContent
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack(spacing: 10) {
            // Nav buttons
            HStack(spacing: 2) {
                navBtn("chevron.left",  enabled: service.canGoBack)    { service.goBack() }
                navBtn("chevron.right", enabled: service.canGoForward) { service.goForward() }
                navBtn("chevron.up",    enabled: !service.isAtDesktop) { service.goUp() }
            }

            // Breadcrumb
            HStack(spacing: 2) {
                ForEach(Array(service.breadcrumbs.enumerated()), id: \.offset) { i, url in
                    if i > 0 {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(Color.textTertiaryLight)
                    }
                    Button(action: { service.navigate(to: url) }) {
                        Text(url == service.desktopURL ? "Desktop" : url.lastPathComponent)
                            .font(.system(size: 12, weight: i == service.breadcrumbs.count - 1 ? .semibold : .regular))
                            .foregroundStyle(i == service.breadcrumbs.count - 1 ? Color.textPrimaryLight : Color.textSecondaryLight)
                            .lineLimit(1)
                    }.buttonStyle(.plain)
                }
            }

            Spacer()

            if let msg = autoOrganizeResult {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.accentGreen)
                    Text(msg)
                }.font(.system(size: 11)).foregroundStyle(Color.accentGreen).transition(.opacity)
            }

            if isWorking {
                CleaningActivityIndicator(color: .accentBlue, size: 13)
                    .transition(.scale.combined(with: .opacity))
            }

            if service.isAtDesktop {
                Button(action: { showAutoOrganizeAlert = true }) {
                    HStack(spacing: 4) {
                        ZStack {
                            if organizeInProgress {
                                ProgressView().scaleEffect(0.5)
                            } else {
                                Image(systemName: "wand.and.stars")
                            }
                        }
                        .frame(width: 14, height: 14)
                        Text(organizeInProgress ? "Organizing…" : "Auto-Organize")
                            .font(.system(size: 11, weight: .medium))
                            .fixedSize()
                    }
                    .padding(.horizontal, 11).padding(.vertical, 6)
                    .background(Color.accentBlue.opacity(0.15))
                    .foregroundStyle(Color.accentBlue)
                    .clipShape(Capsule())
                }.buttonStyle(.plain).disabled(organizeInProgress)
            }

            Button(action: { service.scanCurrentDirectory() }) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.textSecondaryLight)
                    .frame(width: 28, height: 28)
                    .background(Color.surfaceCardLight)
                    .clipShape(Circle())
            }.buttonStyle(.plain)
        }
        .padding(.horizontal, 16).padding(.vertical, 11)
        .background(Color.surfaceCardLight)
    }

    private func navBtn(_ icon: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(enabled ? Color.textSecondaryLight : Color.textTertiaryLight.opacity(0.7))
                .frame(width: 26, height: 26)
                .background(enabled ? Color.surfaceCardLight : Color.surfaceLight)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.borderLight, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }.buttonStyle(.plain).disabled(!enabled)
    }

    // MARK: - Sidebar

    private var sidebarPanel: some View {
        VStack(spacing: 0) {


            // Search
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(Color.textTertiaryLight).font(.system(size: 11))
                TextField("Search…", text: $service.searchQuery)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.textPrimaryLight)
                if !service.searchQuery.isEmpty {
                    Button(action: { service.searchQuery = "" }) {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(Color.textTertiaryLight).font(.system(size: 11))
                    }.buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(Color.surfaceCardLight)
            .overlay(Rectangle().fill(Color.borderLight).frame(height: 1), alignment: .bottom)

            Rectangle().fill(Color.borderLight).frame(height: 1)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    sectionHeader("CATEGORIES")
                    VStack(spacing: 1) {
                        categoryRow(icon: "square.grid.2x2", color: .accentBlue, label: "All Files",
                                    count: service.desktopTotalCount, size: service.desktopTotalSize,
                                    active: service.filterCategory == nil) { service.filterCategory = nil }
                        ForEach(service.desktopCategorySummary, id: \.0) { cat, count, sz in
                            categoryRow(icon: cat.icon, color: cat.color, label: cat.rawValue,
                                        count: count, size: sz, active: service.filterCategory == cat)
                            { service.filterCategory = cat }
                        }
                    }.padding(.horizontal, 8).padding(.bottom, 10)

                    Rectangle().fill(Color.borderLight).frame(height: 1).padding(.horizontal, 12)

                    sectionHeader("SORT BY")
                    VStack(spacing: 1) {
                        ForEach(DesktopSortOrder.allCases, id: \.self) { order in
                            Button(action: { service.sortOrder = order }) {
                                HStack {
                                    Text(order.rawValue).font(.system(size: 12))
                                        .foregroundStyle(service.sortOrder == order ? Color.accentBlue : Color.textPrimaryLight)
                                    Spacer()
                                    if service.sortOrder == order {
                                        Image(systemName: "checkmark").font(.system(size: 10, weight: .semibold))
                                            .foregroundStyle(Color.accentBlue)
                                    }
                                }
                                .padding(.horizontal, 12).padding(.vertical, 6)
                                .background(service.sortOrder == order ? Color.accentBlue.opacity(0.1) : Color.clear)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                            }.buttonStyle(.plain)
                        }
                    }.padding(.horizontal, 8).padding(.bottom, 10)
                }.padding(.top, 4)
            }

            Rectangle().fill(Color.borderLight).frame(height: 1)

            // Selection panel
            VStack(spacing: 7) {
                if service.selectedFiles.isEmpty {
                    Button(action: { service.selectAll() }) {
                        Label("Select All", systemImage: "checkmark.circle")
                            .font(.system(size: 12)).frame(maxWidth: .infinity)
                            .padding(.vertical, 7).background(Color.surfaceCardLight)
                            .foregroundStyle(Color.textSecondaryLight).clipShape(RoundedRectangle(cornerRadius: 8))
                    }.buttonStyle(.plain)
                } else {
                    HStack(spacing: 6) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("\(service.selectedFiles.count) selected")
                                .font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.textPrimaryLight)
                            Text(ByteCountFormatter.string(
                                fromByteCount: Int64(service.selectedFiles.reduce(0) { $0 + $1.size }),
                                countStyle: .file)).font(.system(size: 10)).foregroundStyle(Color.textTertiaryLight)
                        }
                        Spacer()
                        Button(action: { service.deselectAll() }) {
                            Image(systemName: "xmark").font(.system(size: 11, weight: .medium))
                                .foregroundStyle(Color.textTertiaryLight).frame(width: 24, height: 24)
                                .background(Color.surfaceCardLight).clipShape(Circle())
                        }.buttonStyle(.plain)
                    }
                    Button(action: { showDeleteConfirm = true }) {
                        Label("Move to Trash", systemImage: "trash")
                            .font(.system(size: 12, weight: .semibold)).frame(maxWidth: .infinity)
                            .padding(.vertical, 7).background(Color.accentRed).foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }.buttonStyle(.plain)
                }
            }.padding(.horizontal, 10).padding(.vertical, 10)
        }
        .background(Color.surfaceLight)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title).font(.system(size: 10, weight: .semibold)).foregroundStyle(Color.textTertiaryLight)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14).padding(.top, 10).padding(.bottom, 4)
    }

    private func categoryRow(icon: String, color: Color, label: String,
                              count: Int, size: UInt64, active: Bool,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon).font(.system(size: 11))
                    .foregroundStyle(active ? .white : color)
                    .frame(width: 22, height: 22)
                    .background(active ? color : color.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                VStack(alignment: .leading, spacing: 1) {
                    Text(label).font(.system(size: 12)).foregroundStyle(Color.textPrimaryLight).lineLimit(1)
                    Text(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))
                        .font(.system(size: 9)).foregroundStyle(Color.textTertiaryLight)
                }
                Spacer()
                Text("\(count)").font(.system(size: 10, weight: .medium))
                    .foregroundStyle(active ? Color.accentBlue : Color.textTertiaryLight)
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .background(active ? Color.accentBlue.opacity(0.12) : Color.clear)
                    .clipShape(Capsule())
            }
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(active ? Color.accentBlue.opacity(0.08) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Main content area

    private var mainContent: some View {
        VStack(spacing: 0) {
            toolbar
            Rectangle().fill(Color.borderLight).frame(height: 1)
            // Контент с плавным переходом при смене папки.
            ZStack(alignment: .top) {
                contentArea
                    .animation(.easeInOut(duration: 0.22), value: service.currentURL)
                    .background(Color.surfaceLight)

                // Тонкая прогресс-полоска сверху
                if service.isScanning {
                    VStack(spacing: 0) {
                        GeometryReader { g in
                            Rectangle()
                                .fill(Color.accentBlue.opacity(0.7))
                                .frame(width: g.size.width, height: 2)
                                .transition(.opacity)
                        }.frame(height: 2)
                        Spacer()
                    }
                    .transition(.opacity)
                    .animation(.easeInOut(duration: 0.2), value: service.isScanning)
                }
            }
        }
        .background(Color.surfaceLight)
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            // Quick Select — меню вместо чипов
            Menu {
                ForEach(FileGroup.allCases, id: \.self) { group in
                    let count = service.files.filter { group.categories.contains($0.category) }.count
                    if count > 0 {
                        Button(action: { service.selectByCategories(group.categories) }) {
                            Label("\(group.rawValue) (\(count))", systemImage: group.icon)
                        }
                    }
                }
                Divider()
                Button(action: { service.selectAll() }) { Label("Select All", systemImage: "checkmark.circle") }
                Button(action: { service.deselectAll() }) { Label("Deselect All", systemImage: "circle") }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "checkmark.circle.badge.questionmark")
                    Text("Select")
                    Image(systemName: "chevron.down").font(.system(size: 9))
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.textSecondaryLight)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(Color.surfaceCardLight)
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.borderLight, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 7))
            }.menuStyle(.borderlessButton).fixedSize()

            // Move to… button (visible when files selected)
            if !service.selectedFiles.isEmpty {
                Button(action: { moveSelectedWithPanel() }) {
                    Label("Move to…", systemImage: "arrow.up.forward.app")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.textSecondaryLight)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(Color.surfaceCardLight)
                        .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.borderLight, lineWidth: 1))
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                }.buttonStyle(.plain)
            }

            // New folder button
            Button(action: { showNewFolderSheet = true }) {
                Label("New Folder", systemImage: "folder.badge.plus")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.textSecondaryLight)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(Color.surfaceCardLight)
                    .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.borderLight, lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: 7))
            }.buttonStyle(.plain)

            // Group toggle
            Button(action: { service.groupByCategory.toggle() }) {
                HStack(spacing: 4) {
                    Image(systemName: "folder.badge.gearshape")
                    Text("Group")
                }.font(.system(size: 11, weight: .medium))
                .foregroundStyle(service.groupByCategory ? Color.accentBlue : Color.textSecondaryLight)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(service.groupByCategory ? Color.accentBlue.opacity(0.12) : Color.surfaceCardLight)
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(service.groupByCategory ? Color.accentBlue.opacity(0.18) : Color.borderLight, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 7))
            }.buttonStyle(.plain)

            Spacer()

            // Selection action bar
            if !service.selectedFiles.isEmpty {
                HStack(spacing: 6) {
                    Text("\(service.selectedFiles.count) selected")
                        .font(.system(size: 11)).foregroundStyle(Color.textSecondaryLight)
                    Button(action: { showDeleteConfirm = true }) {
                        Label("Trash", systemImage: "trash")
                            .font(.system(size: 11, weight: .semibold))
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(Color.accentRed.opacity(0.9)).foregroundStyle(.white).clipShape(Capsule())
                    }.buttonStyle(.plain)
                    Button(action: { service.deselectAll() }) {
                        Image(systemName: "xmark").font(.system(size: 10)).foregroundStyle(Color.textTertiaryLight)
                    }.buttonStyle(.plain)
                }
                .padding(.trailing, 4)
                .transition(.opacity.combined(with: .move(edge: .trailing)))
            }

            // View mode switcher
            HStack(spacing: 1) {
                ForEach(DesktopViewMode.allCases, id: \.self) { mode in
                    Button(action: { withAnimation(.easeInOut(duration: 0.15)) { service.viewMode = mode } }) {
                        Image(systemName: mode.icon)
                            .font(.system(size: 12, weight: service.viewMode == mode ? .semibold : .regular))
                            .foregroundStyle(service.viewMode == mode ? Color.accentBlue : Color.textSecondaryLight)
                            .frame(width: 28, height: 26)
                            .background(service.viewMode == mode ? Color.accentBlue.opacity(0.12) : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: 5))
                    }.buttonStyle(.plain).help(mode.rawValue)
                }
            }
            .padding(3)
            .background(Color.surfaceCardLight)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.borderLight, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(Color.surfaceLight)
        .animation(.easeInOut(duration: 0.2), value: service.selectedFiles.count)
    }

    @ViewBuilder
    private var contentArea: some View {
        Group {
            switch service.viewMode {
            case .grid:    gridView
            case .list:    listView
            case .columns: columnsView
            }
        }
        // id(currentURL) заставляет SwiftUI пересоздать view при смене папки
        // НЕ добавляем .animation — это вызывает лаги при перестройке LazyVGrid
        .id(service.currentURL)
    }

    // MARK: - Grid view

    private var gridView: some View {
        ScrollView {
            if service.files.isEmpty && !service.isScanning {
                // Empty state
                VStack(spacing: 12) {
                    Image(systemName: "folder.badge.questionmark")
                        .font(.system(size: 36)).foregroundStyle(Color.textTertiaryLight.opacity(0.5))
                    Text("This folder is empty")
                        .font(.system(size: 13)).foregroundStyle(Color.textTertiaryLight)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.top, 80)
            } else if service.groupByCategory {
                VStack(alignment: .leading, spacing: 20) {
                    ForEach(service.groupedFiles, id: \.0) { cat, catFiles in
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 7) {
                                Image(systemName: cat.icon).font(.system(size: 11)).foregroundStyle(.white)
                                    .frame(width: 22, height: 22).background(cat.color)
                                    .clipShape(RoundedRectangle(cornerRadius: 5))
                                Text(cat.rawValue).font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.textPrimaryLight)
                                Text("(\(catFiles.count))").font(.system(size: 12)).foregroundStyle(Color.textTertiaryLight)
                                Spacer()
                            }
                            gridItems(catFiles)
                        }
                    }
                }.padding(16)
            } else {
                gridItems(service.displayedFiles).padding(16)
            }
        }
    }

    private func gridItems(_ files: [DesktopFile]) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 120, maximum: 150), spacing: 10)], spacing: 10) {
            ForEach(files) { file in
                DesktopFileCell(
                    file: file,
                    isSelected:     service.selectedIDs.contains(file.id),
                    isDropTarget:   dropTargetID == file.id,
                    onSelect:       { service.toggleSelect(id: file.id) },
                    onOpen:         { service.open(file) },
                    onPreview:      { previewFile = file },
                    onRename:       { renameTarget = file; renameText = file.name; showRenameSheet = true },
                    onMetadata:     { metadataFile = file },
                    onDuplicate:    { service.duplicate(file) },
                    onTrash:        { requestTrash([file]) },
                    onShowInFinder: { service.showInFinder(file) },
                    onNavigate:     { if file.isDirectory { service.navigate(to: file.url) } }
                )
                .onDrag { NSItemProvider(object: file.url as NSURL) }
                .onDrop(of: [.fileURL], isTargeted: file.isDirectory ? Binding(
                    get: { dropTargetID == file.id },
                    set: { dropTargetID = $0 ? file.id : nil }
                ) : .constant(false)) { providers in
                    guard file.isDirectory else { return false }
                    return handleDrop(providers: providers, into: file.url)
                }
            }
        }
    }

    // MARK: - List view

    private var listView: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Header row
                HStack(spacing: 0) {
                    Text("Name").frame(maxWidth: .infinity, alignment: .leading)
                    Text("Kind").frame(width: 100, alignment: .leading)
                    Text("Size").frame(width: 72, alignment: .trailing)
                    Text("Modified").frame(width: 120, alignment: .trailing)
                }
                .font(.system(size: 10, weight: .semibold)).foregroundStyle(Color.textTertiaryLight)
                .padding(.horizontal, 14).padding(.vertical, 6)
                .background(Color.surfaceCardLight)
                Divider()
                ForEach(service.displayedFiles) { file in
                    DesktopListRow(
                        file: file,
                        isSelected:     service.selectedIDs.contains(file.id),
                        isDropTarget:   dropTargetID == file.id,
                        onSelect:       { service.toggleSelect(id: file.id) },
                        onOpen:         { service.open(file) },
                        onPreview:      { previewFile = file },
                        onRename:       { renameTarget = file; renameText = file.name; showRenameSheet = true },
                        onMetadata:     { metadataFile = file },
                        onDuplicate:    { service.duplicate(file) },
                        onTrash:        { requestTrash([file]) },
                        onShowInFinder: { service.showInFinder(file) },
                        onNavigate:     { if file.isDirectory { service.navigate(to: file.url) } }
                    )
                    .onDrag { NSItemProvider(object: file.url as NSURL) }
                    .onDrop(of: [.fileURL], isTargeted: file.isDirectory ? Binding(
                        get: { dropTargetID == file.id },
                        set: { dropTargetID = $0 ? file.id : nil }
                    ) : .constant(false)) { providers in
                        guard file.isDirectory else { return false }
                        return handleDrop(providers: providers, into: file.url)
                    }
                    Divider().opacity(0.3)
                }
            }
        }
    }

    // MARK: - Columns view

    private var columnsView: some View {
        DesktopColumnsView(service: service,
            onPreview: { previewFile = $0 },
            onRename: { f in renameTarget = f; renameText = f.name; showRenameSheet = true },
            onMetadata: { metadataFile = $0 },
            onTrash: { requestTrash([$0]) })
    }

    // MARK: - Sheets & Rename

    private var renameSheet: some View {
        VStack(spacing: 20) {
            Text("Rename").font(.system(size: 16, weight: .bold)).foregroundStyle(Color.textPrimary)
            TextField("New name", text: $renameText).textFieldStyle(.roundedBorder).frame(width: 280)
            HStack(spacing: 10) {
                Button("Cancel") { showRenameSheet = false }
                    .buttonStyle(.plain).padding(.horizontal, 18).padding(.vertical, 8)
                    .background(Color.surfaceSecondary).foregroundStyle(Color.textSecondary).clipShape(Capsule())
                Button("Rename") {
                    if let t = renameTarget, !renameText.isEmpty { _ = service.rename(t, to: renameText) }
                    showRenameSheet = false
                }
                .buttonStyle(.plain).padding(.horizontal, 18).padding(.vertical, 8)
                .background(Color.accentColor).foregroundStyle(.white).clipShape(Capsule())
            }
        }.padding(32).frame(width: 370).background(Color.surfacePrimary)
    }

    private var newFolderSheet: some View {
        VStack(spacing: 20) {
            Text("New Folder").font(.system(size: 16, weight: .bold)).foregroundStyle(Color.textPrimaryLight)
            TextField("Folder name", text: $newFolderName).textFieldStyle(.roundedBorder).frame(width: 280)
            HStack(spacing: 10) {
                Button("Cancel") { showNewFolderSheet = false; newFolderName = "" }
                    .buttonStyle(.plain).padding(.horizontal, 18).padding(.vertical, 8)
                    .background(Color.surfaceSecondary).foregroundStyle(Color.textSecondary).clipShape(Capsule())
                Button("Create") {
                    if !newFolderName.isEmpty { service.createFolder(named: newFolderName) }
                    showNewFolderSheet = false; newFolderName = ""
                }
                .buttonStyle(.plain).padding(.horizontal, 18).padding(.vertical, 8)
                .background(Color.accentColor).foregroundStyle(.white).clipShape(Capsule())
            }
        }.padding(32).frame(width: 370).background(Color.surfacePrimary)
    }

    // MARK: - Actions

    private func requestTrash(_ files: [DesktopFile]) {
        guard !files.isEmpty else { return }
        pendingTrashFiles = files
        showDeleteConfirm = true
    }

    private func confirmPendingTrash() {
        let files = pendingTrashFiles
        pendingTrashFiles = []
        trash(files)
    }

    private func trash(_ files: [DesktopFile]) {
        guard !files.isEmpty else { return }
        operationActive = true
        service.trash(files: files) { _ in
            operationActive = false
        }
    }

    private func deleteSelected() {
        requestTrash(service.selectedFiles)
    }

    private func handleDrop(providers: [NSItemProvider], into destination: URL) -> Bool {
        var handled = false
        for provider in providers {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                guard let data = item as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                let dest = destination.appendingPathComponent(url.lastPathComponent)
                DispatchQueue.main.async {
                    try? FileManager.default.moveItem(at: url, to: dest)
                    self.service.scanCurrentDirectory()
                }
            }
            handled = true
        }
        return handled
    }

    private func moveSelectedWithPanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Move Here"
        panel.message = "Choose a destination folder for \(service.selectedFiles.count) item(s)"
        panel.begin { response in
            guard response == .OK, let dest = panel.url else { return }
            let selected = self.service.selectedFiles
            self.service.moveItems(selected, to: dest)
            self.service.deselectAll()
        }
    }

    private func runAutoOrganize() {
        operationActive = true
        organizeInProgress = true; autoOrganizeResult = nil
        service.autoOrganize { moved in
            operationActive = false
            organizeInProgress = false
            withAnimation { autoOrganizeResult = "Moved \(moved) files" }
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { withAnimation { autoOrganizeResult = nil } }
        }
    }
}

// MARK: - Grid Cell

struct DesktopFileCell: View {
    let file: DesktopFile
    let isSelected: Bool          // из service.selectedIDs — не из file.isSelected
    var isDropTarget: Bool = false
    let onSelect: () -> Void
    let onOpen: () -> Void
    let onPreview: () -> Void
    let onRename: () -> Void
    let onMetadata: () -> Void
    let onDuplicate: () -> Void
    let onTrash: () -> Void
    let onShowInFinder: () -> Void
    var onNavigate: (() -> Void)? = nil

    @State private var thumbnail: NSImage? = nil
    @State private var isHovered = false

    private let thumbW: CGFloat = 120
    private let thumbH: CGFloat = 90

    var body: some View {
        VStack(spacing: 0) {
            // Thumbnail / icon area
            ZStack(alignment: .topTrailing) {
                thumbnailView
                    .frame(width: thumbW, height: thumbH)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(
                                isSelected ? Color.accentBlue
                                    : (isHovered ? Color.borderLight : Color.clear),
                                lineWidth: isSelected ? 2 : 1
                            )
                    )

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 17))
                        .foregroundStyle(Color.accentBlue)
                        .background(Circle().fill(Color.surfaceLight).frame(width: 14, height: 14))
                        .offset(x: 5, y: -5)
                }

                if !file.ext.isEmpty && !file.isDirectory {
                    Text(file.ext.uppercased())
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(file.category.color.opacity(0.9))
                        .clipShape(Capsule())
                        .offset(x: -5, y: thumbH - 14)
                        .opacity(isSelected ? 0 : 1)
                }
            }

            // Name + size
            VStack(spacing: 2) {
                Text(file.displayName)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.textPrimaryLight)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                if !file.isDirectory {
                    Text(file.formattedSize)
                        .font(.system(size: 9))
                        .foregroundStyle(Color.textTertiaryLight)
                }
            }
            .padding(.horizontal, 6)
            .padding(.top, 6)
            .padding(.bottom, 8)
            .frame(width: thumbW)
        }
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isDropTarget
                      ? Color.accentGreen.opacity(0.12)
                      : (isSelected ? Color.accentBlue.opacity(0.10)
                      : (isHovered ? Color.surfaceCardLight : Color.clear)))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(isDropTarget ? Color.accentGreen : Color.clear, lineWidth: 2)
        )
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .animation(.spring(response: 0.18, dampingFraction: 0.75), value: isHovered)
        .onHover { isHovered = $0 }
        .gesture(
            TapGesture(count: 2)
                .onEnded { if file.isDirectory { onNavigate?() } else { onPreview() } }
                .exclusively(before: TapGesture(count: 1).onEnded { onSelect() })
        )
        .contextMenu { contextMenuContent }
        .task(id: file.url) {
            // Instant display from cache — no flicker
            if let cached = ThumbnailCache.shared.get(file.url) {
                thumbnail = cached
            } else {
                thumbnail = nil
                thumbnail = await loadThumbnail(for: file.url, isDir: file.isDirectory)
            }
        }
    }

    @ViewBuilder
    private var thumbnailView: some View {
        if file.isDirectory {
            ZStack {
                Color.blue.opacity(0.08)
                Image(systemName: "folder.fill")
                    .font(.system(size: 52))
                    .foregroundStyle(Color.blue.opacity(0.85))
            }
        } else if let thumb = thumbnail {
            Image(nsImage: thumb)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: thumbW, height: thumbH)
        } else {
            ZStack {
                file.category.color.opacity(0.10)
                VStack(spacing: 6) {
                    Image(systemName: file.category.icon)
                        .font(.system(size: 32))
                        .foregroundStyle(file.category.color)
                    ProgressView().scaleEffect(0.5).opacity(0.5)
                }
            }
        }
    }

    @ViewBuilder
    private var contextMenuContent: some View {
        if file.isDirectory {
            Button("Open in Browser") { onNavigate?() }
            Button("Open in Finder")  { onShowInFinder() }
        } else {
            Button("Open")            { onOpen() }
            Button("Preview")         { onPreview() }
            if [.image, .screenshot].contains(file.category) {
                Button("View Metadata") { onMetadata() }
            }
            Button("Show in Finder")  { onShowInFinder() }
        }
        Divider()
        Button("Rename…")   { onRename() }
        Button("Duplicate") { onDuplicate() }
        Divider()
        Button("Move to Trash", role: .destructive) { onTrash() }
    }

    private func loadThumbnail(for url: URL, isDir: Bool) async -> NSImage? {
        guard !isDir else { return nil }
        // Cache hit — instant, no background task needed
        if let cached = ThumbnailCache.shared.get(url) { return cached }
        return await Task.detached(priority: .utility) {
            let ext = url.pathExtension.lowercased()
            let imageExts: Set<String> = ["png","jpg","jpeg","heic","gif","bmp","tiff","tif","webp"]
            var result: NSImage?

            if imageExts.contains(ext) {
                let opts: [CFString: Any] = [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceShouldCacheImmediately: false,
                    kCGImageSourceThumbnailMaxPixelSize: 240
                ]
                if let src = CGImageSourceCreateWithURL(url as CFURL, nil),
                   let cgImg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) {
                    result = NSImage(cgImage: cgImg, size: .zero)
                }
            }

            if result == nil {
                let size = CGSize(width: 240, height: 180)
                let dict: [CFString: Any] = [kQLThumbnailOptionIconModeKey: false]
                if let ref = QLThumbnailImageCreate(kCFAllocatorDefault, url as CFURL, size, dict as CFDictionary) {
                    result = NSImage(cgImage: ref.takeRetainedValue(), size: size)
                }
            }

            if result == nil {
                result = NSWorkspace.shared.icon(forFile: url.path)
            }

            if let img = result { ThumbnailCache.shared.set(img, for: url) }
            return result
        }.value
    }
}

// MARK: - List Row

struct DesktopListRow: View {
    let file: DesktopFile
    let isSelected: Bool
    var isDropTarget: Bool = false
    let onSelect: () -> Void
    let onOpen: () -> Void
    let onPreview: () -> Void
    let onRename: () -> Void
    let onMetadata: () -> Void
    let onDuplicate: () -> Void
    let onTrash: () -> Void
    let onShowInFinder: () -> Void
    var onNavigate: (() -> Void)? = nil

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(file.isDirectory ? Color.blue.opacity(0.13) : file.category.color.opacity(0.12))
                    .frame(width: 30, height: 30)
                Image(systemName: file.isDirectory ? "folder.fill" : file.category.icon)
                    .font(.system(size: file.isDirectory ? 14 : 12))
                    .foregroundStyle(file.isDirectory ? Color.blue : file.category.color)
            }
            Text(file.displayName)
                .font(.system(size: 12)).foregroundStyle(Color.textPrimaryLight).lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(file.isDirectory ? "Folder" : file.category.rawValue)
                .font(.system(size: 11)).foregroundStyle(Color.textSecondaryLight)
                .frame(width: 100, alignment: .leading)
            Text(file.isDirectory ? "—" : file.formattedSize)
                .font(.system(size: 11).monospacedDigit()).foregroundStyle(Color.textSecondaryLight)
                .frame(width: 72, alignment: .trailing)
            Text(file.dateModified, style: .date)
                .font(.system(size: 11)).foregroundStyle(Color.textTertiary)
                .frame(width: 120, alignment: .trailing)
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 14))
                .foregroundStyle(isSelected ? Color.accentBlue : Color.textTertiaryLight.opacity(0.4))
        }
        .padding(.horizontal, 14).padding(.vertical, 7)
        .background(isDropTarget ? Color.accentGreen.opacity(0.08)
                    : (isSelected ? Color.accentColor.opacity(0.07)
                    : (isHovered ? Color.surfaceSecondary.opacity(0.5) : Color.clear)))
        .overlay(alignment: .leading) {
            if isDropTarget {
                Rectangle().fill(Color.accentGreen).frame(width: 3)
            }
        }
        .onHover { isHovered = $0 }
        .gesture(
            TapGesture(count: 2)
                .onEnded { if file.isDirectory { onNavigate?() } else { onPreview() } }
                .exclusively(before: TapGesture(count: 1).onEnded { onSelect() })
        )
        .contextMenu {
            if file.isDirectory {
                Button("Open in Browser") { onNavigate?() }
                Button("Open in Finder")  { onShowInFinder() }
            } else {
                Button("Open")           { onOpen() }
                Button("Preview")        { onPreview() }
                if [.image, .screenshot].contains(file.category) {
                    Button("View Metadata") { onMetadata() }
                }
                Button("Show in Finder") { onShowInFinder() }
            }
            Divider()
            Button("Rename…")   { onRename() }
            Button("Duplicate") { onDuplicate() }
            Divider()
            Button("Move to Trash", role: .destructive) { onTrash() }
        }
    }
}

// MARK: - Columns View

struct DesktopColumnsView: View {
    @ObservedObject var service: DesktopService
    let onPreview: (DesktopFile) -> Void
    let onRename: (DesktopFile) -> Void
    let onMetadata: (DesktopFile) -> Void
    let onTrash: (DesktopFile) -> Void

    @State private var selectedFile: DesktopFile? = nil

    var body: some View {
        HSplitView {
            // Left: file list column
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(service.displayedFiles) { file in
                        columnsRow(file)
                        Divider().opacity(0.3)
                    }
                }
            }
            .frame(minWidth: 220)

            // Right: detail / preview pane
            Group {
                if let file = selectedFile {
                    columnsDetail(file)
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "sidebar.right")
                            .font(.system(size: 32)).foregroundStyle(Color.textTertiary.opacity(0.4))
                        Text("Select a file to preview")
                            .font(.system(size: 13)).foregroundStyle(Color.textTertiary)
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(minWidth: 200)
        }
    }

    private func columnsRow(_ file: DesktopFile) -> some View {
        HStack(spacing: 9) {
            ZStack {
                RoundedRectangle(cornerRadius: 5)
                    .fill(file.isDirectory ? Color.blue.opacity(0.13) : file.category.color.opacity(0.12))
                    .frame(width: 26, height: 26)
                Image(systemName: file.isDirectory ? "folder.fill" : file.category.icon)
                    .font(.system(size: file.isDirectory ? 12 : 11))
                    .foregroundStyle(file.isDirectory ? Color.blue : file.category.color)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(file.displayName).font(.system(size: 12)).foregroundStyle(Color.textPrimary).lineLimit(1)
                Text(file.isDirectory ? "Folder" : file.formattedSize)
                    .font(.system(size: 9)).foregroundStyle(Color.textTertiary)
            }
            Spacer()
            if file.isDirectory {
                Image(systemName: "chevron.right").font(.system(size: 10)).foregroundStyle(Color.textTertiary)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 7)
        .background(selectedFile?.id == file.id ? Color.accentColor.opacity(0.1) : Color.clear)
        .gesture(
            TapGesture(count: 2)
                .onEnded { if file.isDirectory { service.navigate(to: file.url) } else { onPreview(file) } }
                .exclusively(before: TapGesture(count: 1).onEnded { selectedFile = file })
        )
        .contextMenu {
            if file.isDirectory {
                Button("Open") { service.navigate(to: file.url) }
                Button("Show in Finder") { service.showInFinder(file) }
            } else {
                Button("Open")           { service.open(file) }
                Button("Preview")        { onPreview(file) }
                Button("Show in Finder") { service.showInFinder(file) }
            }
            Divider()
            Button("Rename…")   { onRename(file) }
            Button("Duplicate") { service.duplicate(file) }
            Divider()
            Button("Move to Trash", role: .destructive) { onTrash(file) }
        }
    }

    @ViewBuilder
    private func columnsDetail(_ file: DesktopFile) -> some View {
        VStack(spacing: 0) {
            // Thumbnail
            ColumnsThumbView(file: file)
                .frame(maxWidth: .infinity)
                .frame(height: 180)
                .background(Color.black.opacity(0.7))

            Divider()

            // Info rows
            ScrollView {
                VStack(spacing: 0) {
                    detailRow("Name",     value: file.displayName)
                    detailRow("Kind",     value: file.isDirectory ? "Folder" : file.category.rawValue)
                    if !file.isDirectory { detailRow("Size", value: file.formattedSize) }
                    detailRow("Modified", value: file.dateModified.formatted(date: .abbreviated, time: .shortened))
                    detailRow("Added",    value: file.dateAdded.formatted(date: .abbreviated, time: .omitted))
                    if !file.ext.isEmpty { detailRow("Extension", value: ".\(file.ext.uppercased())") }
                }.padding(.bottom, 12)
            }

            Divider()

            // Actions
            HStack(spacing: 6) {
                Button(action: { service.open(file) }) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.forward.app").font(.system(size: 11))
                        Text("Open").font(.system(size: 11, weight: .medium))
                    }
                    .frame(minWidth: 60)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(Color.accentColor).foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                }.buttonStyle(.plain)
                if !file.isDirectory {
                    Button(action: { onPreview(file) }) {
                        HStack(spacing: 4) {
                            Image(systemName: "eye").font(.system(size: 11))
                            Text("Preview").font(.system(size: 11, weight: .medium))
                        }
                        .frame(minWidth: 70)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(Color.surfaceSecondary).foregroundStyle(Color.textSecondary)
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                    }.buttonStyle(.plain)
                }
                Spacer()
                Button(action: { service.showInFinder(file) }) {
                    Image(systemName: "arrow.up.forward.square")
                        .font(.system(size: 14)).foregroundStyle(Color.textSecondary)
                        .frame(width: 28, height: 28)
                        .background(Color.surfaceSecondary)
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                }.buttonStyle(.plain).help("Show in Finder")
            }.padding(.horizontal, 12).padding(.vertical, 10)
        }
    }

    private func detailRow(_ label: String, value: String) -> some View {
        HStack(alignment: .top) {
            Text(label).font(.system(size: 11)).foregroundStyle(Color.textTertiary).frame(width: 80, alignment: .leading)
            Text(value).font(.system(size: 11)).foregroundStyle(Color.textPrimary).textSelection(.enabled)
            Spacer()
        }.padding(.horizontal, 14).padding(.vertical, 5)
    }
}

struct ColumnsThumbView: View {
    let file: DesktopFile
    @State private var thumbnail: NSImage? = nil
    @State private var loadingTask: Task<Void, Never>? = nil

    var body: some View {
        ZStack {
            Color.black.opacity(0.05)
            if let img = thumbnail {
                Image(nsImage: img)
                    .resizable().aspectRatio(contentMode: .fit)
                    .padding(10)
                    .transition(.opacity.animation(.easeIn(duration: 0.15)))
            } else if file.isDirectory {
                Image(systemName: "folder.fill")
                    .font(.system(size: 52)).foregroundStyle(Color.blue.opacity(0.8))
            } else {
                VStack(spacing: 10) {
                    Image(systemName: file.category.icon)
                        .font(.system(size: 32)).foregroundStyle(file.category.color.opacity(0.7))
                    ProgressView().scaleEffect(0.6).tint(Color.textTertiary)
                }
            }
        }
        // KEY FIX: .id(file.id) forces SwiftUI to destroy+recreate this view
        // when the selected file changes → thumbnail resets and task re-fires
        .id(file.id)
        .onAppear { startLoad() }
        .onDisappear { loadingTask?.cancel() }
    }

    private func startLoad() {
        guard !file.isDirectory else { return }
        // Instant from cache
        if let cached = ThumbnailCache.shared.get(file.url) {
            thumbnail = cached; return
        }
        thumbnail = nil
        loadingTask?.cancel()
        let url = file.url
        loadingTask = Task {
            let img = await Task.detached(priority: .utility) { () -> NSImage? in
                let ext = url.pathExtension.lowercased()
                let imageExts: Set<String> = ["png","jpg","jpeg","heic","gif","bmp","tiff","tif","webp"]
                var result: NSImage?

                if imageExts.contains(ext) {
                    let opts: [CFString: Any] = [
                        kCGImageSourceCreateThumbnailFromImageAlways: true,
                        kCGImageSourceCreateThumbnailWithTransform: true,
                        kCGImageSourceShouldCacheImmediately: false,
                        kCGImageSourceThumbnailMaxPixelSize: 480
                    ]
                    if let src = CGImageSourceCreateWithURL(url as CFURL, nil),
                       let cgImg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) {
                        result = NSImage(cgImage: cgImg, size: .zero)
                    }
                }

                if result == nil {
                    let size = CGSize(width: 480, height: 360)
                    let dict: [CFString: Any] = [kQLThumbnailOptionIconModeKey: false]
                    if let ref = QLThumbnailImageCreate(kCFAllocatorDefault, url as CFURL, size, dict as CFDictionary) {
                        result = NSImage(cgImage: ref.takeRetainedValue(), size: size)
                    }
                }
                if result == nil { result = NSWorkspace.shared.icon(forFile: url.path) }
                if let img = result { ThumbnailCache.shared.set(img, for: url) }
                return result
            }.value
            guard !Task.isCancelled else { return }
            await MainActor.run { thumbnail = img }
        }
    }
}

// MARK: - Desktop Canvas View (full-screen desktop projection)

struct DesktopCanvasView: View {
    @ObservedObject var service: DesktopService

    @State private var dragOffsets: [UUID: CGSize] = [:]
    @State private var activeID: UUID? = nil
    @State private var previewFile: DesktopFile? = nil
    @State private var metadataFile: DesktopFile? = nil
    @State private var renameTarget: DesktopFile? = nil
    @State private var renameText = ""
    @State private var showRenameSheet = false
    @State private var pendingMoves: [UUID: CGPoint] = [:]  // несохранённые сдвиги
    @State private var pendingTrashFile: DesktopFile? = nil
    @State private var showTrashConfirm = false
    @State private var isSaving = false

    // Только файлы прямо в Desktop, не из вложенных папок
    private var desktopFiles: [DesktopFile] {
        let desktopPath = service.desktopURL.path
        return service.files.filter {
            $0.url.deletingLastPathComponent().path == desktopPath
        }
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                // Wallpaper
                Group {
                    if let img = service.wallpaperImage {
                        Image(nsImage: img)
                            .resizable().aspectRatio(contentMode: .fill)
                            .frame(width: geo.size.width, height: geo.size.height)
                            .clipped()
                    } else {
                        LinearGradient(
                            colors: [Color(red:0.07,green:0.09,blue:0.15), Color(red:0.05,green:0.07,blue:0.12)],
                            startPoint: .topLeading, endPoint: .bottomTrailing)
                    }
                }.frame(width: geo.size.width, height: geo.size.height)

                Color.black.opacity(0.08).frame(width: geo.size.width, height: geo.size.height)

                // Icons — только реальные desktop-файлы
                ForEach(desktopFiles) { file in
                    let base = scaledPos(file.position, in: geo.size)
                    let drag = dragOffsets[file.id] ?? .zero
                    let pos  = CGPoint(x: base.x + drag.width, y: base.y + drag.height)
                    let isActive = activeID == file.id
                    let isSelected = service.selectedIDs.contains(file.id)

                    CanvasIcon(file: file,
                               isSelected: isSelected,
                               onSelect:   { service.toggleSelect(id: file.id) },
                               onPreview:  { previewFile = file },
                               onNavigate: { service.navigate(to: file.url) },
                               onRename:   { renameTarget = file; renameText = file.name; showRenameSheet = true },
                               onMetadata: { metadataFile = file },
                               onOpen:     { service.open(file) },
                               onTrash:    {
                                   pendingTrashFile = file
                                   showTrashConfirm = true
                               },
                               onShowInFinder: { service.showInFinder(file) })
                        .position(pos)
                        .zIndex(isActive ? 10 : 0)
                        .gesture(
                            DragGesture(coordinateSpace: .named("canvas"))
                                .onChanged { val in
                                    activeID = file.id
                                    let base2 = scaledPos(file.position, in: geo.size)
                                    dragOffsets[file.id] = CGSize(
                                        width:  val.location.x - base2.x,
                                        height: val.location.y - base2.y)
                                }
                                .onEnded { val in
                                    let finalPos = CGPoint(x: val.location.x, y: val.location.y)
                                    let realPos  = unscaledPos(finalPos, in: geo.size)
                                    dragOffsets.removeValue(forKey: file.id)
                                    activeID = nil
                                    // Сохраняем позицию локально + отмечаем как pending
                                    service.updatePositionLocal(id: file.id, to: realPos)
                                    pendingMoves[file.id] = realPos
                                }
                        )
                }

                // Кнопка Apply Changes (появляется если есть несохранённые сдвиги)
                if !pendingMoves.isEmpty {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            Button(action: applyChanges) {
                                HStack(spacing: 8) {
                                    if isSaving {
                                        ProgressView().scaleEffect(0.7).tint(.white)
                                    } else {
                                        Image(systemName: "checkmark.circle.fill").font(.system(size: 14))
                                    }
                                    Text(isSaving ? "Applying..." : "Apply \(pendingMoves.count) change\(pendingMoves.count == 1 ? "" : "s")")
                                        .font(.system(size: 12, weight: .semibold))
                                }
                                .foregroundStyle(.white)
                                .padding(.horizontal, 16).padding(.vertical, 9)
                                .background(Color.accentColor)
                                .clipShape(Capsule())
                                .shadow(color: .black.opacity(0.4), radius: 8, y: 4)
                            }
                            .buttonStyle(.plain)
                            .disabled(isSaving)
                            .padding(.trailing, 20).padding(.bottom, 20)
                        }
                    }
                }
            }
            .coordinateSpace(name: "canvas")
        }
        .onAppear {
            if service.wallpaperImage == nil { service.scan() }
            // При открытии Canvas загружаем реальные позиции из Finder
            service.loadCanvasPositions()
        }
        .sheet(item: $previewFile) { file in
            DesktopFilePreview(
                file: file,
                service: service,
                onMetadata: { metadataFile = file },
                onTrashRequest: {
                    pendingTrashFile = file
                    showTrashConfirm = true
                }
            )
        }
        .sheet(item: $metadataFile) { file in ImageMetadataSheet(file: file, service: service) }
        .alert("Move to Trash", isPresented: $showTrashConfirm) {
            Button("Move to Trash", role: .destructive) {
                if let pendingTrashFile {
                    service.trash(files: [pendingTrashFile]) { _ in }
                    self.pendingTrashFile = nil
                }
            }
            Button("Cancel", role: .cancel) { pendingTrashFile = nil }
        } message: {
            Text("Move \(pendingTrashFile?.displayName ?? "this file") to Trash?")
        }
        .sheet(isPresented: $showRenameSheet) {
            VStack(spacing: 20) {
                Text("Rename").font(.system(size: 16, weight: .bold)).foregroundStyle(Color.textPrimary)
                TextField("New name", text: $renameText).textFieldStyle(.roundedBorder).frame(width: 280)
                HStack(spacing: 10) {
                    Button("Cancel") { showRenameSheet = false }
                        .buttonStyle(.plain).padding(.horizontal, 18).padding(.vertical, 8)
                        .background(Color.surfaceSecondary).foregroundStyle(Color.textSecondary).clipShape(Capsule())
                    Button("Rename") {
                        if let t = renameTarget, !renameText.isEmpty { _ = service.rename(t, to: renameText) }
                        showRenameSheet = false
                    }
                    .buttonStyle(.plain).padding(.horizontal, 18).padding(.vertical, 8)
                    .background(Color.accentColor).foregroundStyle(.white).clipShape(Capsule())
                }
            }.padding(32).frame(width: 370).background(Color.surfacePrimary)
        }
    }

    private func scaledPos(_ pt: CGPoint, in size: CGSize) -> CGPoint {
        let sx = size.width  / service.screenSize.width
        let sy = size.height / service.screenSize.height
        return CGPoint(
            x: max(40, min(size.width  - 40, pt.x * sx)),
            y: max(50, min(size.height - 50, pt.y * sy)))
    }

    private func unscaledPos(_ pt: CGPoint, in size: CGSize) -> CGPoint {
        CGPoint(x: pt.x * service.screenSize.width  / size.width,
                y: pt.y * service.screenSize.height / size.height)
    }

    private func applyChanges() {
        guard !pendingMoves.isEmpty else { return }
        isSaving = true
        let moves = pendingMoves
        let files = service.files
        Task.detached(priority: .utility) {
            for (id, pt) in moves {
                guard let f = files.first(where: { $0.id == id }) else { continue }
                let x = Int(pt.x); let y = Int(pt.y)
                let script = """
                tell application "Finder"
                    set position of (POSIX file "\(f.url.path)" as alias) to {\(x), \(y)}
                end tell
                """
                var err: NSDictionary?
                NSAppleScript(source: script)?.executeAndReturnError(&err)
            }
            await MainActor.run {
                self.pendingMoves.removeAll()
                self.isSaving = false
            }
        }
    }
}

// MARK: - Canvas Icon

struct CanvasIcon: View {
    let file: DesktopFile
    let isSelected: Bool
    let onSelect: () -> Void
    let onPreview: () -> Void
    let onNavigate: () -> Void
    let onRename: () -> Void
    let onMetadata: () -> Void
    let onOpen: () -> Void
    let onTrash: () -> Void
    let onShowInFinder: () -> Void

    @State private var thumbnail: NSImage? = nil
    @State private var isHovered = false
    private let sz: CGFloat = 58

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                iconContent
                    .frame(width: sz, height: sz)
                    .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .strokeBorder(isSelected ? Color.accentColor : (isHovered ? Color.white.opacity(0.35) : Color.clear),
                                      lineWidth: isSelected ? 2.5 : 1))
                    .shadow(color: .black.opacity(isSelected ? 0.55 : 0.30),
                            radius: isSelected ? 10 : 5, y: 3)
                    .scaleEffect(isHovered ? 1.07 : 1.0)
                    .animation(.spring(response: 0.18, dampingFraction: 0.7), value: isHovered)

                if isSelected {
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 16))
                        .foregroundStyle(Color.accentColor)
                        .background(Circle().fill(Color.white).frame(width: 12, height: 12))
                        .offset(x: sz/2 - 7, y: -sz/2 + 7)
                }
            }

            Text(file.displayName)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white)
                .lineLimit(2).multilineTextAlignment(.center)
                .frame(maxWidth: 72)
                .padding(.horizontal, 4).padding(.vertical, 2)
                .background(RoundedRectangle(cornerRadius: 4)
                    .fill(isSelected ? Color.accentColor.opacity(0.75) : Color.black.opacity(0.5)))
                .shadow(color: .black.opacity(0.7), radius: 2)
        }
        .frame(width: 76)
        .onHover { isHovered = $0 }
        .gesture(
            TapGesture(count: 2)
                .onEnded { if file.isDirectory { onNavigate() } else { onPreview() } }
                .exclusively(before: TapGesture(count: 1).onEnded { onSelect() })
        )
        .contextMenu {
            Button("Open")           { onOpen() }
            if !file.isDirectory {
                Button("Preview")    { onPreview() }
                if [.image, .screenshot].contains(file.category) {
                    Button("View Metadata") { onMetadata() }
                }
            }
            Button("Show in Finder") { onShowInFinder() }
            Divider()
            Button("Rename…")        { onRename() }
            Divider()
            Button("Move to Trash", role: .destructive) { onTrash() }
        }
        .task(id: file.url) {
            thumbnail = nil
            thumbnail = await loadThumb(url: file.url, isDir: file.isDirectory)
        }
    }

    @ViewBuilder
    private var iconContent: some View {
        if file.isDirectory {
            ZStack {
                Color.blue.opacity(0.15)
                Image(systemName: "folder.fill").font(.system(size: 32)).foregroundStyle(Color.blue.opacity(0.9))
            }
        } else if let img = thumbnail {
            Image(nsImage: img).resizable().aspectRatio(contentMode: .fit)
        } else {
            ZStack {
                file.category.color.opacity(0.15)
                Image(systemName: file.category.icon).font(.system(size: 24)).foregroundStyle(file.category.color)
            }
        }
    }

    private func loadThumb(url: URL, isDir: Bool) async -> NSImage? {
        guard !isDir else { return nil }
        if let cached = ThumbnailCache.shared.get(url) { return cached }
        return await Task.detached(priority: .utility) {
            let ext = url.pathExtension.lowercased()
            let imageExts: Set<String> = ["png","jpg","jpeg","heic","gif","bmp","tiff","tif","webp"]
            var result: NSImage?
            if imageExts.contains(ext) {
                let opts: [CFString: Any] = [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceShouldCacheImmediately: false,
                    kCGImageSourceThumbnailMaxPixelSize: 116
                ]
                if let src = CGImageSourceCreateWithURL(url as CFURL, nil),
                   let cgImg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) {
                    result = NSImage(cgImage: cgImg, size: .zero)
                }
            }
            if result == nil {
                let dict: [CFString: Any] = [kQLThumbnailOptionIconModeKey: false]
                let sz = CGSize(width: 116, height: 116)
                if let ref = QLThumbnailImageCreate(kCFAllocatorDefault, url as CFURL, sz, dict as CFDictionary) {
                    result = NSImage(cgImage: ref.takeRetainedValue(), size: sz)
                }
            }
            if result == nil { result = NSWorkspace.shared.icon(forFile: url.path) }
            if let img = result { ThumbnailCache.shared.set(img, for: url) }
            return result
        }.value
    }
}

// MARK: - File Preview

struct DesktopFilePreview: View {
    let file: DesktopFile
    @ObservedObject var service: DesktopService
    var onMetadata: (() -> Void)? = nil
    var onTrashRequest: (() -> Void)? = nil
    @Environment(\.dismiss) var dismiss

    @State private var previewImage: NSImage? = nil
    @State private var loadingPreview = true
    @State private var showTrashConfirm = false

    private var isImage: Bool { [.image, .screenshot].contains(file.category) }

    var body: some View {
        VStack(spacing: 0) {
            // Header bar
            HStack(spacing: 12) {
                // File info
                VStack(alignment: .leading, spacing: 3) {
                    Text(file.displayName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(1)
                    Text("\(file.formattedSize)  ·  \(file.dateModified, style: .date)")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.textTertiary)
                }

                Spacer()

                HStack(spacing: 6) {
                    if isImage, let onMeta = onMetadata {
                        Button(action: { dismiss(); DispatchQueue.main.async { onMeta() } }) {
                            Label("Metadata", systemImage: "info.circle")
                                .font(.system(size: 12))
                                .padding(.horizontal, 10).padding(.vertical, 5)
                                .foregroundStyle(Color.textSecondary)
                                .background(Color.surfaceSecondary)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                        }.buttonStyle(.plain)
                    }

                    Button(action: { service.open(file) }) {
                        Label("Open", systemImage: "arrow.up.forward.app")
                            .font(.system(size: 12))
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .foregroundStyle(Color.textSecondary)
                            .background(Color.surfaceSecondary)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }.buttonStyle(.plain)

                    Button(action: {
                        if let onTrashRequest {
                            dismiss()
                            onTrashRequest()
                        } else {
                            showTrashConfirm = true
                        }
                    }) {
                        Label("Trash", systemImage: "trash")
                            .font(.system(size: 12))
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .foregroundStyle(Color.red)
                            .background(Color.surfaceSecondary)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }.buttonStyle(.plain)

                    Rectangle().fill(Color.borderLight).frame(width: 1, height: 16).padding(.horizontal, 4)

                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Color.textSecondary)
                            .frame(width: 24, height: 24)
                            .background(Color.surfaceSecondary)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }.buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            .background(Color.surfacePrimary)

            Divider()

            // Preview area
            ZStack {
                Color.surfaceSecondary
                if loadingPreview {
                    ProgressView().scaleEffect(0.8)
                } else if let img = previewImage {
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .padding(16)
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: file.category.icon)
                            .font(.system(size: 32))
                            .foregroundStyle(file.category.color)
                        Text("No preview available")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.textTertiary)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 760, height: 560)
        .background(Color.surfacePrimary)
        .alert("Move to Trash", isPresented: $showTrashConfirm) {
            Button("Move to Trash", role: .destructive) {
                dismiss()
                service.trash(files: [file]) { _ in }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Move \(file.displayName) to Trash?")
        }
        .task { await loadPreview() }
    }

    private func loadPreview() async {
        loadingPreview = true
        let result = await Task.detached(priority: .utility) { () -> NSImage? in
            let size = CGSize(width: 1440, height: 1080)
            let dict: [CFString: Any] = [kQLThumbnailOptionIconModeKey: false]
            guard let ref = QLThumbnailImageCreate(kCFAllocatorDefault, file.url as CFURL, size, dict as CFDictionary) else {
                return NSWorkspace.shared.icon(forFile: file.url.path)
            }
            return NSImage(cgImage: ref.takeRetainedValue(), size: .zero)
        }.value
        previewImage = result
        loadingPreview = false
    }
}

// MARK: - Image Metadata Sheet

struct ImageMetadataSheet: View {
    let file: DesktopFile
    @ObservedObject var service: DesktopService
    @Environment(\.dismiss) var dismiss

    @State private var metadata: ImageMetadata? = nil
    @State private var thumbnail: NSImage? = nil

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(file.displayName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.textPrimary).lineLimit(1)
                    Text("Image Metadata")
                        .font(.system(size: 11)).foregroundStyle(Color.textTertiary)
                }
                Spacer()
                HStack(spacing: 6) {
                    Button(action: { service.open(file) }) {
                        Label("Open", systemImage: "arrow.up.forward.app")
                            .font(.system(size: 12))
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .foregroundStyle(Color.textSecondary)
                            .background(Color.surfaceSecondary)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }.buttonStyle(.plain)

                    Rectangle().fill(Color.borderLight).frame(width: 1, height: 16).padding(.horizontal, 4)

                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Color.textSecondary)
                            .frame(width: 24, height: 24)
                            .background(Color.surfaceSecondary)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }.buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            .background(Color.surfacePrimary)

            Divider()

            HStack(spacing: 0) {
                // Left: thumbnail
                ZStack {
                    Color.black.opacity(0.8)
                    if let img = thumbnail {
                        Image(nsImage: img)
                            .resizable().aspectRatio(contentMode: .fit)
                            .padding(16)
                            .shadow(color: .black.opacity(0.4), radius: 12)
                    } else {
                        ProgressView().tint(.white)
                    }
                }
                .frame(width: 280)

                Divider()

                // Right: metadata rows
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        if let m = metadata {
                            metaSection("Image") {
                                metaRow("Resolution", value: m.resolution)
                                metaRow("DPI", value: m.dpi.map { String(format: "%.0f", $0) })
                                metaRow("Colour model", value: m.colorModel)
                                metaRow("Bit depth", value: m.colorDepth.map { "\($0)-bit" })
                                metaRow("File size", value: file.formattedSize)
                            }
                            if m.camera != nil || m.lens != nil || m.iso != nil
                                || m.fNumber != nil || m.exposureTime != nil {
                                metaSection("Camera") {
                                    metaRow("Camera",    value: m.camera)
                                    metaRow("Lens",      value: m.lens)
                                    metaRow("ISO",       value: m.iso.map { "ISO \($0)" })
                                    metaRow("Aperture",  value: m.fNumberFormatted)
                                    metaRow("Shutter",   value: m.exposureFormatted)
                                    metaRow("Focal length", value: m.focalLengthFormatted)
                                    metaRow("Date taken", value: m.dateTaken)
                                }
                            }
                            if m.gpsLatitude != nil {
                                metaSection("Location") {
                                    metaRow("Coordinates", value: m.gpsFormatted)
                                }
                            }
                        } else {
                            VStack(spacing: 10) {
                                Image(systemName: "photo.badge.exclamationmark")
                                    .font(.system(size: 28)).foregroundStyle(Color.textTertiary)
                                Text("No EXIF metadata found")
                                    .font(.system(size: 12)).foregroundStyle(Color.textTertiary)
                            }
                            .frame(maxWidth: .infinity).padding(.top, 40)
                        }
                    }
                    .padding(.bottom, 16)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(width: 660, height: 460)
        .background(Color.surfacePrimary)
        .task {
            metadata = service.readImageMetadata(for: file)
            thumbnail = await loadThumb()
        }
    }

    private func metaSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color.textTertiary)
                .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 5)
            content()
            Divider().padding(.horizontal, 12).padding(.top, 8)
        }
    }

    private func metaRow(_ label: String, value: String?) -> some View {
        Group {
            if let v = value {
                HStack(alignment: .top) {
                    Text(label)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.textTertiary)
                        .frame(width: 110, alignment: .leading)
                    Text(v)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.textPrimary)
                        .textSelection(.enabled)
                    Spacer()
                }
                .padding(.horizontal, 16).padding(.vertical, 4)
            }
        }
    }

    private func loadThumb() async -> NSImage? {
        await Task.detached(priority: .utility) {
            let size = CGSize(width: 560, height: 800)
            let dict: [CFString: Any] = [kQLThumbnailOptionIconModeKey: false]
            if let ref = QLThumbnailImageCreate(kCFAllocatorDefault, file.url as CFURL, size, dict as CFDictionary) {
                return NSImage(cgImage: ref.takeRetainedValue(), size: size)
            }
            return nil
        }.value
    }
}
