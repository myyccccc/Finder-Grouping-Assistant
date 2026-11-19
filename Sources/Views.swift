import SwiftUI
import AppKit

enum Page {
    case overview, rules, feedback
    var height: Double {
        switch self { case .overview: return 330; case .rules: return 330; case .feedback: return 350 }
    }
}

enum WidgetLayout {
    static let width: CGFloat = 320
    static let controlInset: CGFloat = 31
    static let switchWidth: CGFloat = 36
    static func height(for model: AppModel) -> Double {
        model.ruleEditor != nil ? 490 : model.showSetup ? 410 : model.selectedPage == .overview ? model.overviewHeight : model.selectedPage.height
    }
}

private struct PanelContentHeight: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value += nextValue() }
}

private struct MeasurePanelPart: ViewModifier {
    func body(content: Content) -> some View {
        content.background(GeometryReader { geometry in
            Color.clear.preference(key: PanelContentHeight.self, value: geometry.size.height)
        })
    }
}

enum Palette {
    static let accent = Color.accentColor
    static let text = Color(nsColor: .labelColor)
    static let secondary = Color(nsColor: .secondaryLabelColor)
    static let background = Color(nsColor: .windowBackgroundColor)
    static let card = Color(nsColor: NSColor(name: nil) {
        $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor.white.withAlphaComponent(0.055) : NSColor.white.withAlphaComponent(0.40)
    })
    static let line = Color.primary.opacity(0.08)
}

// Keep the scroll behavior native; only the in-app knob drawing is shared.
final class ThinScroller: NSScroller {
    override class var isCompatibleWithOverlayScrollers: Bool { true }
    override func drawKnob() {
        let native = rect(for: .knob)
        guard native.height > 0 else { return }
        let knob = NSRect(x: native.midX - 2.5, y: native.minY, width: 5, height: native.height)
        NSColor.labelColor.withAlphaComponent(0.32).setFill()
        NSBezierPath(roundedRect: knob, xRadius: 2.5, yRadius: 2.5).fill()
    }
    override func drawKnobSlot(in slotRect: NSRect, highlight flag: Bool) {}
}

private struct ScrollAppearance: NSViewRepresentable {
    final class Accessor: NSView {
        weak var configuredScroll: NSScrollView?
        override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); configure() }
        override func viewDidMoveToSuperview() { super.viewDidMoveToSuperview(); configure() }
        func configure() {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                var ancestor = self.superview
                while let view = ancestor {
                    if let scroll = view as? NSScrollView {
                        guard self.configuredScroll !== scroll else { return }
                        scroll.scrollerStyle = .overlay
                        scroll.verticalScroller = ThinScroller(frame: NSRect(x: 0, y: 0, width: 12, height: 100))
                        self.configuredScroll = scroll
                        return
                    }
                    ancestor = view.superview
                }
            }
        }
    }
    func makeNSView(context: Context) -> Accessor { Accessor() }
    func updateNSView(_ view: Accessor, context: Context) { view.configure() }
}

struct AppScrollView<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View { ScrollView { content.background(ScrollAppearance()) } }
}

struct Card<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content.background(Palette.card, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Palette.line, lineWidth: 0.5))
    }
}

// The header and menu bar use the same artwork, including the three folder marks.
enum BrandArtwork {
    // A template outline keeps the menu bar monochrome in every system appearance.
    static let menuBarImage: NSImage = {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            NSColor.black.setStroke()
            let folder = NSBezierPath()
            folder.move(to: NSPoint(x: 3, y: 3.5))
            folder.line(to: NSPoint(x: 15, y: 3.5))
            folder.curve(to: NSPoint(x: 16.5, y: 5), controlPoint1: NSPoint(x: 15.85, y: 3.5), controlPoint2: NSPoint(x: 16.5, y: 4.15))
            folder.line(to: NSPoint(x: 16.5, y: 11))
            folder.curve(to: NSPoint(x: 15, y: 12.5), controlPoint1: NSPoint(x: 16.5, y: 11.85), controlPoint2: NSPoint(x: 15.85, y: 12.5))
            folder.line(to: NSPoint(x: 9, y: 12.5))
            folder.line(to: NSPoint(x: 7.2, y: 14.5))
            folder.line(to: NSPoint(x: 3, y: 14.5))
            folder.curve(to: NSPoint(x: 1.5, y: 13), controlPoint1: NSPoint(x: 2.15, y: 14.5), controlPoint2: NSPoint(x: 1.5, y: 13.85))
            folder.line(to: NSPoint(x: 1.5, y: 5))
            folder.curve(to: NSPoint(x: 3, y: 3.5), controlPoint1: NSPoint(x: 1.5, y: 4.15), controlPoint2: NSPoint(x: 2.15, y: 3.5))
            folder.close()
            folder.lineWidth = 1.25; folder.lineJoinStyle = .round; folder.stroke()
            NSColor.black.setFill()
            for x in [6.0, 9.0, 12.0] { NSBezierPath(ovalIn: NSRect(x: x - 0.55, y: 7.1, width: 1.1, height: 1.1)).fill() }
            return true
        }
        image.isTemplate = true
        return image
    }()
    static let image: NSImage = {
        let image = NSImage(size: NSSize(width: 32, height: 32), flipped: false) { bounds in
            let background = NSBezierPath(roundedRect: bounds, xRadius: 7.7, yRadius: 7.7)
            NSGradient(starting: NSColor(calibratedRed: 0.40, green: 0.60, blue: 0.88, alpha: 1),
                       ending: NSColor(calibratedRed: 0.12, green: 0.48, blue: 0.96, alpha: 1))?.draw(in: background, angle: -70)
            let configuration = NSImage.SymbolConfiguration(paletteColors: [.white])
            NSImage(systemSymbolName: "folder.fill", accessibilityDescription: nil)?
                .withSymbolConfiguration(configuration)?.draw(in: NSRect(x: 6, y: 8, width: 20, height: 17))
            NSColor(calibratedRed: 0.18, green: 0.52, blue: 0.98, alpha: 1).setFill()
            for x in [9.5, 14.5, 19.5] {
                NSBezierPath(roundedRect: NSRect(x: x, y: 11, width: 3, height: 3), xRadius: 0.8, yRadius: 0.8).fill()
            }
            return true
        }
        image.accessibilityDescription = L.t("Finder 分组助手")
        return image
    }()
}

struct BrandMark: View {
    var size: CGFloat = 38
    var body: some View { Image(nsImage: BrandArtwork.image).resizable().frame(width: size, height: size) }
}

struct StatusPill: View {
    let text: String
    var color: Color = .green
    var body: some View {
        HStack(spacing: 6) { Circle().fill(color).frame(width: 5, height: 5); Text(text).font(.system(size: 11, weight: .medium)) }
            .foregroundStyle(color).padding(.horizontal, 10).padding(.vertical, 5).background(color.opacity(0.09), in: Capsule())
    }
}

struct IconTile: View {
    let symbol: String
    var color: Color = Palette.accent
    var body: some View {
        Image(systemName: symbol).font(.system(size: 18, weight: .medium)).foregroundStyle(color)
            .frame(width: 40, height: 40).background(color.opacity(0.09), in: RoundedRectangle(cornerRadius: 10))
    }
}

struct RootView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        Group {
            if let rule = model.ruleEditor {
                AppScrollView { RuleEditorView(rule: rule, compact: true, onClose: { model.ruleEditor = nil }) }
            } else if model.showSetup {
                AppScrollView { SetupView(compact: true, onClose: { model.showSetup = false }) }
            } else if model.selectedPage == .overview {
                VStack(spacing: 0) {
                    header.modifier(MeasurePanelPart())
                    overviewContent.fixedSize(horizontal: false, vertical: true).modifier(MeasurePanelPart())
                    Spacer(minLength: 12)
                    footer.modifier(MeasurePanelPart())
                }
            } else {
                VStack(spacing: 0) {
                    header
                    AppScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            message
                            switch model.selectedPage {
                            case .overview: EmptyView()
                            case .rules: LocationsView()
                            case .feedback: FeedbackView()
                            }
                        }.padding(.horizontal, 16).padding(.top, 2).padding(.bottom, 12)
                    }
                    footer
                }
            }
        }
        .id(model.preferences.language)
        .frame(width: WidgetLayout.width, height: WidgetLayout.height(for: model))
        // NSPopover supplies one continuous native glass surface, including its arrow.
        .onPreferenceChange(PanelContentHeight.self) { measured in
            guard model.selectedPage == .overview, model.ruleEditor == nil, !model.showSetup else { return }
            let height = max(Page.overview.height, ceil(Double(measured) + 12))
            if abs(model.overviewHeight - height) > 0.5 { model.overviewHeight = height }
        }
        .foregroundStyle(Palette.text).tint(Palette.accent)
        .preferredColorScheme(model.preferredColorScheme)
        .environment(\.locale, L.locale).environment(\.layoutDirection, L.direction)
    }
    @ViewBuilder private var message: some View {
        if let text = model.message {
            HStack(alignment: .top, spacing: 6) {
                Text(text).font(.system(size: 10)).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Button { model.message = nil } label: { Image(systemName: "xmark") }
                    .buttonStyle(.plain).accessibilityLabel(L.t("关闭提示"))
            }
        }
    }
    private var overviewContent: some View {
        VStack(alignment: .leading, spacing: 10) { message; QuickControls() }
            .padding(.horizontal, 16).padding(.top, 2)
    }
    private var header: some View {
        HStack(spacing: 8) {
            if model.selectedPage != .overview {
                Button { model.selectedPage = .overview } label: {
                    Image(systemName: L.direction == .rightToLeft ? "chevron.right" : "chevron.left").frame(width: 16, height: 24)
                }.buttonStyle(.plain).accessibilityLabel(L.t("返回"))
            } else { BrandMark(size: 22) }
            Text(model.selectedPage == .overview ? L.t("Finder 分组助手") : model.selectedPage == .rules ? L.t("专属规则") : L.t("反馈"))
                .font(.system(size: 13, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.78)
            if model.selectedPage == .overview {
                Text("v" + (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""))
                    .font(.system(size: 9)).foregroundStyle(Palette.secondary)
            }
            Spacer(minLength: 4)
            if model.selectedPage == .overview {
                Toggle(L.t("自动分组"), isOn: Binding(get: { model.isRunning }, set: { $0 ? model.start() : model.pause() }))
                    .labelsHidden().toggleStyle(.switch).controlSize(.mini).frame(width: WidgetLayout.switchWidth, alignment: .trailing).help(L.t("自动分组"))
            }
        }.padding(.leading, 16).padding(.trailing, model.selectedPage == .overview ? WidgetLayout.controlInset : 16).padding(.top, 16).padding(.bottom, 14)
    }
    private var footer: some View {
        HStack {
            if model.selectedPage == .overview {
                Spacer()
                SettingsMenu().padding(.trailing, 5)
            } else { Spacer().frame(height: 1) }
        }.font(.system(size: 11)).padding(.leading, 16).padding(.trailing, WidgetLayout.controlInset + (WidgetLayout.switchWidth - 32) / 2).padding(.bottom, model.selectedPage == .overview ? 14 : 10)
    }
}

struct QuickControls: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        VStack(spacing: 12) {
            if model.legacyRunning || !model.accessibilityGranted || !model.automationGranted {
                if model.permissionsChecked && !model.permissionChecking {
                    Button(L.t("检查权限")) { model.showPermissionSetup() }.buttonStyle(.bordered)
                }
            }
            Card { GroupPickers(grouping: $model.preferences.grouping, sorting: $model.preferences.sorting) }
            Card { DisplayControls() }
        }
    }
}

struct FeedbackView: View {
    @EnvironmentObject var model: AppModel
    @State private var copied = false
    @State private var saveError: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L.t("遇到了什么问题，或想改进什么？")).font(.system(size: 12)).foregroundStyle(Palette.secondary)
            TextEditor(text: $model.feedbackDraft).font(.system(size: 12)).frame(height: 155)
                .scrollContentBackground(.hidden).padding(8).background(Palette.card, in: RoundedRectangle(cornerRadius: 9))
                .accessibilityLabel(L.t("反馈内容"))
            Toggle(L.t("附带版本与系统信息"), isOn: $model.feedbackIncludesSystem).font(.system(size: 11))
            if let saveError { Text(saveError).font(.system(size: 10)).foregroundStyle(.orange) }
            HStack {
                Button(copied ? L.t("已复制") : L.t("复制反馈")) {
                    NSPasteboard.general.clearContents(); NSPasteboard.general.setString(report, forType: .string); copied = true
                }.disabled(model.feedbackDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button(L.t("保存反馈")) { save() }.disabled(model.feedbackDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }.buttonStyle(.bordered).font(.system(size: 11))
        }.onChange(of: model.feedbackDraft) { _ in copied = false }
    }
    private var report: String { FeedbackReport.make(message: model.feedbackDraft, includeSystem: model.feedbackIncludesSystem) }
    private func save() {
        let panel = NSSavePanel(); panel.nameFieldStringValue = "Finder-feedback.txt"; panel.allowedContentTypes = [.plainText]
        if panel.runModal() == .OK, let url = panel.url {
            do { try report.write(to: url, atomically: true, encoding: .utf8); saveError = nil }
            catch { saveError = L.f("反馈保存失败：%@", error.localizedDescription) }
        }
        AppDelegate.shared?.showWindow(resetPage: false)
    }
}

struct SectionCaption: View {
    let title: String
    var detail: String? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.system(size: 13, weight: .semibold))
            if let detail = detail { Text(detail).font(.system(size: 11)).foregroundStyle(Palette.secondary) }
        }
    }
}

/// Icon view, icon size and start at login, shown on the main panel.
struct DisplayControls: View {
    @EnvironmentObject var model: AppModel
    @State private var size: Double?
    /// Until a size is chosen, the slider starts at Finder's own default icon size.
    private var shownSize: Double { size ?? model.preferences.iconSize.map(Double.init) ?? finderDefaultSize }
    private let finderDefaultSize = min(256, max(16, (PreGrouping.defaultIconOptions()["iconSize"] as? Double) ?? 64))
    var body: some View {
        VStack(spacing: 0) {
            PreferenceRow(symbol: model.preferences.viewStyle.symbol, title: L.t("窗口视图")) {
                Picker(L.t("窗口视图"), selection: $model.preferences.viewStyle) {
                    ForEach(ViewStyle.allCases) { Text($0.title).tag($0) }
                }.labelsHidden().frame(width: 112).tint(Palette.text).foregroundStyle(Palette.text)
            }
            if [.icon, .keep].contains(model.preferences.viewStyle) {
            Divider().padding(.leading, 46)
            HStack(spacing: 9) {
                Image(systemName: "photo").font(.system(size: 15)).foregroundStyle(Palette.secondary).frame(width: 22)
                Text(L.t("图标大小")).font(.system(size: 12, weight: .medium)).fixedSize()
                Image(systemName: "photo").font(.system(size: 8)).foregroundStyle(Palette.secondary)
                Slider(value: Binding(get: { shownSize }, set: { value in
                           if Int(value) != size.map(Int.init) { model.previewIconSize(Int(value)) }
                           size = value
                       }),
                       in: Double(Preferences.iconSizeRange.lowerBound)...256, step: 4) { editing in
                    guard !editing, let size else { return }
                    model.commitIconSize(Int(size))
                }.controlSize(.mini)
                Image(systemName: "photo").font(.system(size: 13)).foregroundStyle(Palette.secondary)
                Text(L.number(Int(shownSize))).font(.system(size: 10).monospacedDigit()).foregroundStyle(Palette.secondary).frame(width: 24, alignment: .trailing)
            }.padding(.horizontal, 15).padding(.vertical, 11)
            }
            Divider().padding(.leading, 46)
            PreferenceRow(symbol: "power", title: L.t("登录时启动")) {
                Toggle(L.t("登录时启动"), isOn: Binding(get: { model.loginEnabled }, set: { model.setLoginItem($0) })).labelsHidden().toggleStyle(.switch).controlSize(.mini).frame(width: WidgetLayout.switchWidth, alignment: .trailing)
            }
        }
    }
}
struct PreferenceRow<Control: View>: View {
    let symbol: String
    let title: String
    var detail: String? = nil
    @ViewBuilder var control: Control
    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: symbol).font(.system(size: 15)).foregroundStyle(Palette.secondary).frame(width: 22)
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.system(size: 12, weight: .medium))
                if let detail = detail { Text(detail).font(.system(size: 10)).foregroundStyle(Palette.secondary).fixedSize(horizontal: false, vertical: true) }
            }
            Spacer(minLength: 10)
            control
        }.padding(.horizontal, 15).padding(.vertical, 13)
    }
}

struct GroupPickers: View {
    @Binding var grouping: Grouping
    @Binding var sorting: Sorting
    var body: some View {
        VStack(spacing: 0) {
            PreferenceRow(symbol: "square.grid.2x2", title: L.t("分组依据")) {
                Picker(L.t("分组依据"), selection: $grouping) { ForEach(Grouping.allCases) { Text($0.title).tag($0) } }.labelsHidden().frame(width: 112).tint(Palette.text).foregroundStyle(Palette.text)
            }
            Divider().padding(.leading, 55)
            PreferenceRow(symbol: "arrow.up.arrow.down", title: L.t("组内排序")) {
                Picker(L.t("组内排序"), selection: $sorting) { ForEach(Sorting.allCases) { Text($0.title).tag($0) } }.labelsHidden().frame(width: 112).tint(Palette.text).foregroundStyle(Palette.text)
            }
        }
    }
}

struct LocationsView: View {
    @EnvironmentObject var model: AppModel
    @State private var search = ""
    private var filteredRules: [LocationRule] {
        model.preferences.rules.filter { matches($0.name, $0.path) }
    }
    private var unconfiguredVolumes: [MountedVolume] {
        model.volumes.filter { volume in
            !model.preferences.rules.contains { RuleResolver.matchesDevice($0, uuid: volume.uuid, path: volume.path) }
                && matches(volume.name, volume.path)
        }
    }
    private func matches(_ name: String, _ path: String) -> Bool {
        search.isEmpty || name.localizedCaseInsensitiveContains(search) || path.localizedCaseInsensitiveContains(search)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").foregroundStyle(Palette.secondary)
                    TextField(L.t("查找位置"), text: $search).textFieldStyle(.plain)
                }.font(.system(size: 11)).padding(8).background(Palette.card, in: RoundedRectangle(cornerRadius: 7))
                Menu {
                    Button(L.t("添加文件夹")) { model.chooseFolder() }
                    Button(L.t("排除文件夹")) { model.chooseFolder(excluded: true) }
                } label: { Label(L.t("添加"), systemImage: "plus") }.fixedSize()
                Button { model.refreshEnvironment() } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.plain).foregroundStyle(Palette.secondary)
                    .help(L.t("刷新设备")).accessibilityLabel(L.t("刷新设备"))
            }
            if filteredRules.isEmpty && unconfiguredVolumes.isEmpty {
                Text(search.isEmpty ? L.t("尚未添加规则") : L.t("没有匹配的位置"))
                    .font(.system(size: 11)).foregroundStyle(Palette.secondary).frame(maxWidth: .infinity).padding(.vertical, 15)
            } else {
                VStack(spacing: 0) {
                    ForEach(filteredRules) { rule in
                        ruleRow(rule)
                        Divider()
                    }
                    ForEach(unconfiguredVolumes) { volume in
                        deviceRow(volume)
                        if volume.id != unconfiguredVolumes.last?.id { Divider() }
                    }
                }
            }
        }
    }
    private func deviceRow(_ volume: MountedVolume) -> some View {
        HStack(spacing: 10) {
            Image(systemName: volume.symbol).font(.system(size: 19)).foregroundStyle(Palette.accent).frame(width: 25)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(volume.name).font(.system(size: 12, weight: .medium))
                    if volume.readOnly { Text(L.t("只读")).font(.system(size: 9)).foregroundStyle(Palette.secondary) }
                }
                Text(model.preferences.externalEnabled ? L.t("继承全局默认") : L.t("保持原有设置"))
                    .font(.system(size: 10)).foregroundStyle(Palette.secondary)
            }
            Spacer()
            Button(L.t("自定义规则")) { model.editDevice(volume) }.buttonStyle(.bordered).controlSize(.small)
        }.padding(.vertical, 10)
        .help(L.f("%@ · 可用 %@", formattedBytes(volume.total), formattedBytes(volume.available)))
        .contextMenu { Button(L.t("在 Finder 中打开")) { model.openLocation(volume.path) } }
    }
    private func ruleRow(_ rule: LocationRule) -> some View {
        let volume = model.volumes.first { RuleResolver.matchesDevice(rule, uuid: $0.uuid, path: $0.path) }
        let path = volume?.path ?? rule.path
        return HStack(spacing: 10) {
            Image(systemName: rule.scope == .device ? "externaldrive" : rule.excluded ? "folder.badge.minus" : "folder")
                .font(.system(size: 19)).foregroundStyle(Palette.accent.opacity(rule.enabled ? 1 : 0.4)).frame(width: 25)
            VStack(alignment: .leading, spacing: 4) {
                Text(volume?.name ?? rule.name).font(.system(size: 12, weight: .medium)).lineLimit(1)
                Text(rule.excluded ? L.t("保持原有设置") : "\(rule.grouping.title) · \(rule.sorting.title)")
                    .font(.system(size: 10)).foregroundStyle(Palette.secondary)
            }
            Spacer(minLength: 8)
            Toggle(L.f("启用 %@", rule.name), isOn: Binding(get: {
                model.preferences.rules.first(where: { $0.id == rule.id })?.enabled ?? false
            }, set: { enabled in
                if let index = model.preferences.rules.firstIndex(where: { $0.id == rule.id }) { model.preferences.rules[index].enabled = enabled }
            })).labelsHidden().toggleStyle(.switch).controlSize(.mini)
            Button(L.t("编辑规则")) { model.ruleEditor = rule }.buttonStyle(.bordered).controlSize(.small)
        }.padding(.vertical, 10).help(readablePath(path))
        .contextMenu { Button(L.t("在 Finder 中打开")) { model.openLocation(path) } }
    }
}

struct RuleEditorView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) var dismiss
    @State var rule: LocationRule
    var compact = false
    var onClose: (() -> Void)? = nil
    private func close() { if let onClose { onClose() } else { dismiss() } }
    @State private var confirmDelete = false
    var exists: Bool { model.preferences.rules.contains(where: { $0.id == rule.id }) }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 14) {
                IconTile(symbol: rule.scope == .device ? "externaldrive" : "folder")
                VStack(alignment: .leading, spacing: 7) {
                    Text(exists ? L.t("编辑规则") : L.t("添加专属规则")).font(.system(size: 20, weight: .semibold))
                    Text(readablePath(rule.path)).font(.system(size: 11)).foregroundStyle(Palette.secondary).lineLimit(2)
                }
                Spacer()
            }
            HStack { Text(L.t("位置名称")).font(.system(size: 12)); Spacer(); TextField(L.t("规则名称"), text: $rule.name).frame(width: compact ? 170 : 280).textFieldStyle(.roundedBorder) }
            Card {
                PreferenceRow(symbol: "slider.horizontal.3", title: L.t("显示方式")) {
                    Picker(L.t("显示方式"), selection: $rule.excluded) { Text(L.t("专属规则")).tag(false); Text(L.t("保持 Finder 原有设置")).tag(true) }.labelsHidden().frame(width: compact ? 150 : 195)
                }
            }
            if !rule.excluded { Card { GroupPickers(grouping: $rule.grouping, sorting: $rule.sorting) } }
            if rule.scope == .folder {
                Toggle(L.t("同时应用到子文件夹"), isOn: $rule.includeChildren).font(.system(size: 12))
                Text(L.t("更深层的文件夹有自己的规则时，优先使用它的设置。")).font(.system(size: 10)).foregroundStyle(Palette.secondary)
            } else {
                Label(rule.volumeID == nil ? L.t("未获得磁盘标识，将按挂载路径记忆。") : L.t("按磁盘标识记忆，设备更名和重新连接后仍可匹配。"), systemImage: "link")
                    .font(.system(size: 10)).foregroundStyle(Palette.secondary)
            }
            Divider()
            HStack {
                if exists { Button(L.t("删除规则"), role: .destructive) { confirmDelete = true }.buttonStyle(.borderless) }
                Spacer()
                Button(L.t("取消")) { close() }.keyboardShortcut(.cancelAction)
                Button(L.t("保存规则")) { model.saveRule(rule); close() }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
            }
        }.padding(compact ? 16 : 28).frame(width: compact ? WidgetLayout.width : 560)
            .alert(L.t("删除这条专属规则？"), isPresented: $confirmDelete) {
                Button(L.t("删除规则"), role: .destructive) { model.deleteRule(rule.id); close() }
                Button(L.t("取消"), role: .cancel) {}
            } message: { Text(L.t("此位置将恢复继承全局或设备规则。文件内容不受影响。")) }
    }
}

struct SettingsMenu: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        Menu {
            Picker(L.t("语言"), selection: $model.preferences.language) {
                ForEach(AppLanguage.allCases) { Text($0.title).tag($0.rawValue) }
            }
            Picker(L.t("外观"), selection: $model.preferences.appearance) {
                Text(L.t("跟随系统")).tag("system")
                Text(L.t("浅色")).tag("light")
                Text(L.t("深色")).tag("dark")
            }
            Toggle(L.t("始终不显示隐藏文件"), isOn: $model.preferences.hideOnNavigation)
            Divider()
            Button(L.t("检查权限")) { model.showPermissionSetup() }
            Menu(L.t("预先分组")) {
                Button(L.t("预先整理文件夹…")) { AppDelegate.shared?.closeForFinderAction(); model.preGroupFolders() }.disabled(model.busy)
                Button(L.t("还原预先整理…")) { AppDelegate.shared?.closeForFinderAction(); model.restorePreGrouping() }.disabled(model.busy || !model.preGroupingAvailable)
            }
            Button(L.t("检查更新")) { UpdateChecker.shared.check(userInitiated: true) }
            Divider()
            Button(L.t("还原当前文件夹排列…")) { model.restoreCurrentFolder() }.disabled(model.busy)
            Button(L.t("退出分组助手")) { AppDelegate.shared?.quit() }
        } label: {
            Image(systemName: "gearshape").font(.system(size: 15, weight: .medium)).foregroundStyle(Palette.text).frame(width: 32, height: 32).contentShape(Rectangle())
        }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().tint(Palette.text)
            .help(L.t("设置")).accessibilityLabel(L.t("设置"))
    }
}

struct SetupView: View {
    var compact = false
    var onClose: (() -> Void)? = nil
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 14) {
                IconTile(symbol: "lock.shield")
                VStack(alignment: .leading, spacing: 8) { Text(L.t("允许助手为 Finder 分组")).font(.system(size: 20, weight: .semibold));  }
            }
            Card {
                VStack(spacing: 0) {
                    PreferenceRow(symbol: model.accessibilityGranted ? "checkmark.circle" : "1.circle", title: L.t("辅助功能")) {
                        Button(model.accessibilityGranted ? L.t("已授权") : L.t("打开系统设置")) { model.openAccessibility() }.buttonStyle(.bordered)
                    }
                    Divider().padding(.leading, 55)
                    PreferenceRow(symbol: model.automationGranted ? "checkmark.circle" : "2.circle", title: L.t("自动化")) {
                        Button(model.automationGranted ? L.t("已授权") : L.t("查看权限")) { model.openAutomation() }.buttonStyle(.bordered)
                    }
                }
            }
            Text(L.t("允许辅助功能，以及对 Finder 和 System Events 的自动化访问。授权完成后会自动开启分组。")).font(.system(size: 11)).foregroundStyle(Palette.secondary).fixedSize(horizontal: false, vertical: true)
            if let message = model.message { Text(message).font(.system(size: 11)).foregroundStyle(.orange) }
            HStack {
                Button(L.t("刷新状态")) { model.refreshEnvironment() }.buttonStyle(.borderless)
                Spacer()
                Button(L.t("稍后")) { model.cancelPermissionSetup(); if let onClose { onClose() } else { dismiss() } }.keyboardShortcut(.cancelAction)
                Button(model.permissionChecking ? L.t("正在检查…") : L.t("检查并开启")) { model.start() }.buttonStyle(.borderedProminent).disabled(model.busy || model.permissionChecking).keyboardShortcut(.defaultAction)
            }
        }.padding(compact ? 16 : 28).frame(width: compact ? WidgetLayout.width : 590)
    }
}
