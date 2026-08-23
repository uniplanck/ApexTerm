import ApexTermCore
import SwiftUI

struct UIControlCustomizationView: View {
    @ObservedObject var model: AppModel
    @State private var hoveredControl: UIControlID?
    @State private var legacyExpanded = false
    @FocusState private var focusedControl: UIControlID?

    private var previewControl: UIControlID? {
        hoveredControl
            ?? focusedControl
            ?? model.uiControlCustomization.topBarOrder.first
    }

    var body: some View {
        HStack(spacing: 0) {
            Form {
                Section("Toolbar") {
                    Text("⌘-drag toolbar icons directly to reorder them. You can also drag the handle here. Hidden buttons keep their commands available from menus and shortcuts.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    ForEach(
                        model.uiControlCustomization.topBarOrder
                    ) { control in
                        mainToolbarRow(control)
                    }

                    Text("Sidebar placement/toggle lives in the sidebar itself. Column split directions live in each column + button context menu.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack {
                        Spacer()
                        Button("Reset Toolbar") {
                            model.resetTopBarCustomization()
                        }
                    }
                }

                controlSection(.tabBar)
                controlSection(.compactToolbar)
                controlSection(.sidebarHeader)
                controlSection(.compactLeftRail)

                Section {
                    DisclosureGroup(isExpanded: $legacyExpanded) {
                        ForEach(UIControlID.allCases.filter { $0.isLegacy }) { control in
                            legacyControlRow(control)
                        }
                    } label: {
                        Label("Legacy / Retired Controls", systemImage: "archivebox")
                    }

                    Text("These identifiers are kept for settings migration and compatibility. They are not shown in the current ApexTerm interface.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            previewPane
                .frame(width: 320)
                .frame(maxHeight: .infinity, alignment: .top)
                .padding(16)
        }
        .padding(.horizontal, 8)
    }

    private func mainToolbarRow(_ control: UIControlID) -> some View {
        previewableRow(control) {
            HStack(spacing: 10) {
                Image(systemName: "line.3.horizontal")
                    .foregroundStyle(.tertiary)
                    .frame(width: 16)
                    .draggable(control.rawValue)

                Image(systemName: control.systemImage)
                    .frame(width: 20)
                    .foregroundStyle(.secondary)

                Text(control.title)
                Spacer()

                Toggle("", isOn: visibilityBinding(control))
                    .labelsHidden()
            }
            .contentShape(Rectangle())
            .dropDestination(for: String.self) { items, _ in
                guard let rawValue = items.first,
                      let dragged = UIControlID(rawValue: rawValue),
                      dragged.isTopBarReorderable,
                      dragged != control else {
                    return false
                }
                model.moveTopBarControl(dragged, relativeTo: control, after: false)
                return true
            }
        }
    }

    @ViewBuilder
    private func controlSection(_ zone: UIControlZone) -> some View {
        Section(zone.title) {
            ForEach(
                UIControlID.controls(in: zone).filter {
                    zone != .tabBar || !$0.isTopBarReorderable
                }
            ) { control in
                previewableRow(control) {
                    HStack(spacing: 10) {
                        Image(systemName: control.systemImage)
                            .frame(width: 20)
                            .foregroundStyle(.secondary)
                        Toggle(control.title, isOn: visibilityBinding(control))
                    }
                }
            }
        }
    }

    private func legacyControlRow(_ control: UIControlID) -> some View {
        previewableRow(control) {
            HStack(spacing: 10) {
                Image(systemName: control.systemImage)
                    .frame(width: 20)
                    .foregroundStyle(.tertiary)
                Text(control.title)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("Legacy")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(.quaternary, in: Capsule())
            }
        }
    }

    private func previewableRow<Content: View>(
        _ control: UIControlID,
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                isPreviewing(control) ? Color.accentColor.opacity(0.08) : Color.clear,
                in: RoundedRectangle(cornerRadius: 7)
            )
            .contentShape(Rectangle())
            .focusable()
            .focused($focusedControl, equals: control)
            .onHover { hovering in
                if hovering {
                    hoveredControl = control
                } else if hoveredControl == control {
                    hoveredControl = nil
                }
            }
            .help(control.shortDescription)
    }

    private func isPreviewing(_ control: UIControlID) -> Bool {
        hoveredControl == control || focusedControl == control
    }

    @ViewBuilder
    private var previewPane: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Icon Preview")
                .font(.headline)

            Text("Hover an icon, or move keyboard focus to it, to see what it does before changing its visibility.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let control = previewControl {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .center, spacing: 12) {
                        Image(systemName: control.systemImage)
                            .font(.system(size: 22, weight: .medium))
                            .frame(width: 48, height: 48)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                            .overlay {
                                RoundedRectangle(cornerRadius: 12)
                                    .strokeBorder(.primary.opacity(0.08), lineWidth: 0.5)
                            }

                        VStack(alignment: .leading, spacing: 4) {
                            Text(control.title)
                                .font(.title3.weight(.semibold))
                                .lineLimit(2)

                            statusLabel(control)
                        }
                    }

                    Text(control.shortDescription)
                        .font(.headline)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(control.detailDescription)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Divider()

                    metadataRow(
                        title: "Placement",
                        value: control.placementTitle,
                        systemImage: "rectangle.on.rectangle"
                    )

                    metadataRow(
                        title: "Recommendation",
                        value: control.recommendation.title,
                        systemImage: control.recommendation.systemImage
                    )

                    if control.isLegacy {
                        HStack(spacing: 8) {
                            Image(systemName: "archivebox")
                                .frame(width: 18)
                            Text("Legacy")
                                .font(.caption.weight(.semibold))
                            Spacer()
                            Text("Compatibility only")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 9))
                    }
                }
                .padding(16)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
                .overlay {
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(.primary.opacity(0.08), lineWidth: 0.5)
                }
                .id(control)
                .transition(.opacity)
            }

            Spacer(minLength: 0)
        }
        .animation(.easeInOut(duration: 0.14), value: previewControl)
    }

    @ViewBuilder
    private func statusLabel(_ control: UIControlID) -> some View {
        if control.isLegacy {
            Label("Retired", systemImage: "archivebox")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else if model.isUIControlVisible(control) {
            Label("Visible", systemImage: "eye")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            Label("Hidden", systemImage: "eye.slash")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func metadataRow(
        title: String,
        value: String,
        systemImage: String
    ) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .frame(width: 18)
                .foregroundStyle(.secondary)

            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            Text(value)
                .font(.caption.weight(.semibold))
                .multilineTextAlignment(.trailing)
        }
    }

    private func visibilityBinding(_ control: UIControlID) -> Binding<Bool> {
        Binding(
            get: { model.isUIControlVisible(control) },
            set: { model.setUIControlVisible(control, visible: $0) }
        )
    }
}
