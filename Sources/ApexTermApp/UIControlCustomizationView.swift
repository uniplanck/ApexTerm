import ApexTermCore
import SwiftUI

struct UIControlCustomizationView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Form {
            Section("Main Toolbar") {
                Text("Drag the handle to reorder toolbar buttons. Hidden buttons keep their commands available from menus and shortcuts.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ForEach(
                    model.uiControlCustomization.mainToolbarOrder.filter(\.isMainToolbarSurfaceAvailable)
                ) { control in
                    mainToolbarRow(control)
                }

                Text("Sidebar placement/toggle lives in the sidebar itself. Column split directions live in each column + button context menu.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack {
                    Spacer()
                    Button("Reset Main Toolbar") {
                        model.resetMainToolbarCustomization()
                    }
                }
            }

            controlSection(.tabBar)
            controlSection(.compactToolbar)
            controlSection(.sidebarHeader)
            controlSection(.compactLeftRail)
        }
        .formStyle(.grouped)
        .padding(.horizontal, 8)
    }

    private func mainToolbarRow(_ control: UIControlID) -> some View {
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
                  dragged.zone == .mainToolbar,
                  dragged != control else {
                return false
            }
            model.moveMainToolbarControl(dragged, before: control)
            return true
        }
    }

    @ViewBuilder
    private func controlSection(_ zone: UIControlZone) -> some View {
        Section(zone.title) {
            ForEach(UIControlID.controls(in: zone)) { control in
                HStack(spacing: 10) {
                    Image(systemName: control.systemImage)
                        .frame(width: 20)
                        .foregroundStyle(.secondary)
                    Toggle(control.title, isOn: visibilityBinding(control))
                }
            }
        }
    }

    private func visibilityBinding(_ control: UIControlID) -> Binding<Bool> {
        Binding(
            get: { model.isUIControlVisible(control) },
            set: { model.setUIControlVisible(control, visible: $0) }
        )
    }
}
