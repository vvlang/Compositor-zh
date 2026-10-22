import SwiftUI

struct LayersPanel: View {
    @Bindable var session: EditorSession
    /// Dragging the panel's left edge sets it, within `widths`.
    var width: CGFloat = 252
    /// No narrower than the footer: its icons can't shrink, and a footer wider than the panel pushed everything in
    /// it out past both edges, over the edge that resizes it.
    static let widths: ClosedRange<Double> = 222...352

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            LayersHeader(session: session)
            Divider()
            LayerAppearanceControls(session: session, layerID: session.activeLayerID).id(session.activeLayerID)
            Divider()
            if let layers = session.document?.layers, !layers.isEmpty {
                if session.isFilteringLayers, session.filteredLayerRows.isEmpty {
                    LayersUnavailableView("No layers match the filter.", systemImage: "line.3.horizontal.decrease.circle.fill") {
                        Button("Clear All") {
                            session.clearLayerSearch()
                            session.clearLayerTypeFilter()
                        }
                        .controlSize(.large)
                    }
                } else {
                    NativeLayerList(session: session)
                }
            } else {
                LayersUnavailableView("No layers yet", systemImage: "square.3.layers.3d") {
                    L10n.text(session.document == nil ? "Create a canvas or import a file." : "Import a file or add a blank layer.")
                        .font(.caption).multilineTextAlignment(.center)
                }
            }
            Divider()
            // No spacing: each button's hit area supplies it (8 pt either side makes the 16 pt gap).
            HStack(spacing: 0) {
                Button { session.addBlankLayer() } label: { FooterIcon(systemName: "plus.square") }
                    .help("New blank layer (⇧⌘N)").accessibilityLabel("New blank layer")
                    .accessibilityIdentifier("addBlankLayer").disabled(!session.layersLookEditable)
                Button { session.groupSelectedLayers() } label: { FooterIcon(systemName: "folder.badge.plus") }
                    .help("Group selected layers (⌘G)").accessibilityLabel("New folder").disabled(!session.layersLookEditable)
                LayerMaskMenu(session: session)
                Menu {
                    // The Image menu's adjustments, then the Filter menu's filters.
                    ForEach(AdjustmentKind.imageAdjustments, id: \.self) { kind in
                        Button { session.addAdjustment(kind) } label: { Text(verbatim: kind.localizedName) }
                    }
                    Divider()
                    ForEach(AdjustmentKind.filters, id: \.self) { kind in
                        Button { session.addAdjustment(kind) } label: { Text(verbatim: kind.localizedName) }
                    }
                } label: { Image(systemName: "circle.lefthalf.filled").footerHitArea() }
                    .menuStyle(.borderlessButton).fixedSize().help("New adjustment layer").disabled(!session.layersLookEditable)
                Menu {
                    ForEach(LayerEffectKind.allCases, id: \.self) { kind in
                        Button { session.addEffect(kind) } label: { Text(verbatim: kind.localizedName + "…") }
                    }
                } label: { Image(systemName: "sparkles").footerHitArea() }
                    .menuStyle(.borderlessButton).fixedSize()
                    .help("Add layer effect").accessibilityLabel("Layer effects")
                    .accessibilityIdentifier("layerEffects").disabled(!session.layersLookEditable || session.activeLayer?.isGroup != false || session.activeLayer?.asset == nil)
                Spacer()
                Button { session.deleteLayerOrMask() } label: { FooterIcon(systemName: "trash") }
                    .help(deleteTitle)
                    .accessibilityLabel(deleteTitle)
                    .accessibilityIdentifier("deleteLayer")
                    .disabled(!session.layersLookEditable || session.activeLayer == nil)
            }
            .buttonStyle(.plain).foregroundStyle(.secondary)
            .padding(.horizontal, 8).padding(.vertical, 4) // Plus the hit areas' 8 and 12: the original 16.

        }
        .frame(width: width)
        .task(id: session.adjustmentEditingID) {
            if let id = session.adjustmentEditingID { await session.beginAdjustmentEditing(id) }
        }
    }

    /// 底部垃圾桶针对什么，取决于当前选中的是效果、蒙版还是图层。拆成属性而不是
    /// 留在原地，是因为四层三元没法整体进目录——中文语序和英文不同。
    private var deleteTitle: String {
        if session.selectedEffect != nil { return L10n.string("Delete selected effect") }
        if session.isMaskSelected { return L10n.string("Delete layer mask") }
        return session.selectedLayerIDs.count > 1
            ? L10n.string("Delete selected layers") : L10n.string("Delete selected layer")
    }
}

/// The panel's empty states: a light icon over a title, with a line or two of detail beneath.
private struct LayersUnavailableView<Content: View>: View {
    let title: LocalizedStringKey
    let systemImage: String
    @ViewBuilder let content: () -> Content

    init(_ title: LocalizedStringKey, systemImage: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.systemImage = systemImage
        self.content = content
    }

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage).font(.system(size: 25, weight: .light))
            Text(title).font(.callout.weight(.medium))
            content()
                .font(.caption).multilineTextAlignment(.center)
        }
        .foregroundStyle(.secondary).padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// A footer button's icon: full strength when the button can be used, and as dim as the footer's menus (Effects,
/// Adjustments) when it can't. A plain button with its own color doesn't dim when disabled, so the footer looked
/// uneven, some disabled icons barely fading and others nearly gone.
struct FooterIcon: View {
    let systemName: String
    @Environment(\.isEnabled) private var isEnabled
    var body: some View {
        // Disabled, as dim as the menus' icons (a quarter-strength white, measured): SwiftUI halves a disabled
        // button's own color again, so the button asks for half-strength white.
        Image(systemName: systemName)
            .foregroundStyle(isEnabled ? AnyShapeStyle(.primary) : AnyShapeStyle(Color.white.opacity(0.5)))
            .footerHitArea()
    }
}

extension View {
    /// Makes a small footer icon easier to click. The padding is the clickable area, so the
    /// footer's own spacing is reduced to match and every icon keeps its old position.
    /// (Negative padding to hand the space back does not work: the button then only answers
    /// clicks inside its shrunken frame.)
    func footerHitArea() -> some View {
        padding(.horizontal, 8).padding(.vertical, 12)
            .contentShape(Rectangle())
    }
}
