import SwiftUI

/// Where the expanded list appears relative to the control. Choose `.above`
/// for fields near the bottom of the popover so the list doesn't get
/// clipped by the window edge.
enum DropdownPlacement {
    case below
    case above
}

/// A combo-box style control: shows the current selection like a Picker,
/// but clicking it turns the control into a text field that filters
/// `items` by substring match as the user types. The expanded list is
/// drawn as an overlay (not inserted into the surrounding stack), so
/// opening it never shifts sibling views.
struct FilterableDropdown: View {
    let title: String
    let items: [String]
    @Binding var selection: String?
    @Binding var isOpen: Bool
    var placeholder: String = "—"
    var placement: DropdownPlacement = .below

    @State private var searchText: String = ""
    @State private var controlSize: CGSize = .zero
    @FocusState private var isFieldFocused: Bool

    private var filteredItems: [String] {
        guard !searchText.isEmpty else { return items }
        return items.filter { $0.localizedCaseInsensitiveContains(searchText) }
    }

    /// Must track `DropdownRow`'s `minHeight` and the list's own vertical
    /// padding so the ScrollView is given exactly the height its rows need.
    private var listHeight: CGFloat {
        let rowHeight: CGFloat = 28
        let verticalPadding: CGFloat = 8
        let rowCount = max(filteredItems.count, 1)
        return min(CGFloat(rowCount) * rowHeight + verticalPadding, 200)
    }

    var body: some View {
        HStack {
            Text(title)
                .frame(minWidth: 70, alignment: .leading)
            control
                .background(
                    GeometryReader { geo in
                        Color.clear
                            .onAppear { controlSize = geo.size }
                            .onChange(of: geo.size) { _, newValue in controlSize = newValue }
                    }
                )
                .overlay(alignment: placement == .below ? .topLeading : .bottomLeading) {
                    if isOpen {
                        dropdownList
                            .frame(width: max(controlSize.width, 160))
                            .offset(y: placement == .below ? controlSize.height + 6 : -(controlSize.height + 6))
                    }
                }
        }
        .onChange(of: isOpen) { _, opened in
            if opened {
                searchText = ""
                DispatchQueue.main.async { isFieldFocused = true }
            } else {
                isFieldFocused = false
            }
        }
    }

    @ViewBuilder
    private var control: some View {
        if isOpen {
            TextField("Поиск…", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .focused($isFieldFocused)
                .onSubmit { commitFirstMatch() }
                .onExitCommand { close() }
        } else {
            Button {
                isOpen = true
            } label: {
                HStack {
                    Text(selection ?? placeholder)
                        .foregroundStyle(selection == nil ? .secondary : .primary)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .controlBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3)))
            }
            .buttonStyle(.plain)
        }
    }

    private var dropdownList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if filteredItems.isEmpty {
                    Text("Нет совпадений")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .frame(minHeight: 32, alignment: .leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ForEach(filteredItems, id: \.self) { item in
                        DropdownRow(title: item, isSelected: item == selection) {
                            selection = item
                            close()
                        }
                    }
                }
            }
            .padding(.vertical, 4)
        }
        // ScrollView doesn't hug its content height inside an `.overlay` —
        // it just takes the small size proposed by the anchor control, so
        // we compute an explicit height from the row count instead of
        // relying on `minHeight`/`maxHeight` (which silently did nothing).
        .frame(height: listHeight)
        // `.controlBackgroundColor` is the same fill used by the closed
        // control's button and renders fully opaque there; the previous
        // `.windowBackgroundColor` / `.regularMaterial` fills turned out to
        // be vibrant/translucent in this window style and let the field
        // underneath bleed through.
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .compositingGroup()
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.35)))
        .shadow(radius: 8, y: 3)
        .zIndex(100)
    }

    private func commitFirstMatch() {
        if let first = filteredItems.first {
            selection = first
        }
        close()
    }

    private func close() {
        searchText = ""
        isOpen = false
    }
}

private struct DropdownRow: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 10)
            .frame(minHeight: 28)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .background(isHovering ? Color.accentColor.opacity(0.15) : Color.clear)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}
