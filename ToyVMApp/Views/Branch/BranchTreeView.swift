//
//  BranchTreeView.swift
//  ToyVMApp
//

import SwiftUI
#if canImport(ToyVMCore)
import ToyVMCore
#endif

// MARK: - Actions

/// Callbacks for branch operations triggered from tree node context menus.
@available(macOS 15.0, *)
struct BranchActions {
    var onCreate: (String) -> Void = { _ in }
    var onSelect: (String) -> Void = { _ in }
    var onRename: (String) -> Void = { _ in }
    var onDelete: (String) -> Void = { _ in }
    var onRevert: (String) -> Void = { _ in }
    var onCommit: (String) -> Void = { _ in }
    var onToggleReadOnly: (String) -> Void = { _ in }
}

// MARK: - BranchTreeView

/// Renders the branch hierarchy as a graphical tree with connecting lines,
/// node indicators, and context menus for branch operations.
@available(macOS 15.0, *)
struct BranchTreeView: View {
    let meta: BundleMeta
    let actions: BranchActions
    let isDisabled: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(flattenedNodes, id: \.name) { node in
                BranchNodeRow(
                    name: node.name,
                    meta: meta,
                    actions: actions,
                    isDisabled: isDisabled,
                    prefix: node.prefix
                )
            }
        }
    }

    /// Flattens the branch tree into a pre-order list of (name, prefix) pairs
    /// suitable for rendering in a single ForEach.
    private var flattenedNodes: [(name: String, prefix: [ConnectorKind])] {
        guard let root = meta.rootBranch else { return [] }
        var result: [(name: String, prefix: [ConnectorKind])] = []
        result.append((name: root, prefix: []))
        appendChildren(of: root, prefix: [], to: &result)
        return result
    }

    private func appendChildren(
        of parent: String,
        prefix: [ConnectorKind],
        to result: inout [(name: String, prefix: [ConnectorKind])]
    ) {
        let kids = meta.children(of: parent)
        for (index, child) in kids.enumerated() {
            let isLast = index == kids.count - 1
            let childPrefix = prefix + [isLast ? .lastChild : .child]
            result.append((name: child, prefix: childPrefix))
            appendChildren(
                of: child,
                prefix: prefix + [isLast ? .blank : .continuation],
                to: &result
            )
        }
    }
}

// MARK: - ConnectorKind

/// Describes the type of tree connector to draw for one level of indentation.
enum ConnectorKind {
    case child         // ├─  (has more siblings below)
    case lastChild     // └─  (last sibling)
    case continuation  // │   (vertical line from ancestor)
    case blank         //     (empty space, ancestor was last child)
}

// MARK: - BranchNodeRow

/// A single row in the branch tree: [connectors] [circle] [name] [badges].
@available(macOS 15.0, *)
struct BranchNodeRow: View {
    let name: String
    let meta: BundleMeta
    let actions: BranchActions
    let isDisabled: Bool
    let prefix: [ConnectorKind]

    private var isActive: Bool { name == meta.activeBranch }
    private var isReadOnly: Bool { meta.branches[name]?.readOnly == true }
    private var isRoot: Bool { meta.branches[name]?.parent == nil }
    private var isLeaf: Bool { meta.children(of: name).isEmpty }
    private var hasParent: Bool { meta.branches[name]?.parent != nil }

    var body: some View {
        HStack(spacing: 0) {
            // Tree connectors
            ForEach(Array(prefix.enumerated()), id: \.offset) { _, kind in
                ConnectorView(kind: kind)
            }

            // Node circle
            Circle()
                .fill(isActive ? Color.accentColor : Color.clear)
                .overlay(Circle().stroke(isActive ? Color.accentColor : Color.secondary, lineWidth: 1.5))
                .frame(width: 10, height: 10)
                .padding(.trailing, 6)

            // Branch name
            Text(name)
                .fontWeight(isActive ? .semibold : .regular)
                .foregroundStyle(isActive ? Color.accentColor : Color.primary)

            // Badges
            if isActive {
                Text("active")
                    .font(.caption2)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Color.accentColor.opacity(0.15))
                    .foregroundStyle(Color.accentColor)
                    .clipShape(Capsule())
                    .padding(.leading, 4)
            }
            if isReadOnly {
                Image(systemName: "lock.fill")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 4)
            }

            Spacer()
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .contextMenu { contextMenuItems }
    }

    @ViewBuilder
    private var contextMenuItems: some View {
        if !isDisabled {
            Button("Create Branch…") { actions.onCreate(name) }

            if isLeaf && !isActive {
                Button("Select") { actions.onSelect(name) }
            }

            Button("Rename…") { actions.onRename(name) }

            if hasParent && !isReadOnly {
                Divider()
                Button("Revert to Parent…") { actions.onRevert(name) }
            }

            if isLeaf && hasParent && !isReadOnly {
                let parentName = meta.branches[name]?.parent ?? ""
                let parentSiblings = meta.children(of: parentName).filter { $0 != name }
                let parentReadOnly = meta.branches[parentName]?.readOnly == true
                if parentSiblings.isEmpty && !parentReadOnly {
                    Button("Commit to Parent…") { actions.onCommit(name) }
                }
            }

            Divider()

            Button(isReadOnly ? "Make Writable" : "Make Read-Only") {
                actions.onToggleReadOnly(name)
            }

            if !isRoot && !isReadOnly {
                Divider()
                Button("Delete…", role: .destructive) { actions.onDelete(name) }
            }
        }
    }
}

// MARK: - ConnectorView

/// Draws a single tree connector segment (20pt wide × row height).
private struct ConnectorView: View {
    let kind: ConnectorKind

    private let width: CGFloat = 20
    private let lineColor = Color.secondary.opacity(0.5)
    private let lineWidth: CGFloat = 1

    var body: some View {
        Canvas { context, size in
            let midX = size.width / 2
            let midY = size.height / 2

            switch kind {
            case .child:
                // Vertical line top to bottom + horizontal from mid to right
                var vLine = Path()
                vLine.move(to: CGPoint(x: midX, y: 0))
                vLine.addLine(to: CGPoint(x: midX, y: size.height))
                context.stroke(vLine, with: .color(lineColor), lineWidth: lineWidth)

                var hLine = Path()
                hLine.move(to: CGPoint(x: midX, y: midY))
                hLine.addLine(to: CGPoint(x: size.width, y: midY))
                context.stroke(hLine, with: .color(lineColor), lineWidth: lineWidth)

            case .lastChild:
                // Vertical line top to mid + horizontal from mid to right
                var vLine = Path()
                vLine.move(to: CGPoint(x: midX, y: 0))
                vLine.addLine(to: CGPoint(x: midX, y: midY))
                context.stroke(vLine, with: .color(lineColor), lineWidth: lineWidth)

                var hLine = Path()
                hLine.move(to: CGPoint(x: midX, y: midY))
                hLine.addLine(to: CGPoint(x: size.width, y: midY))
                context.stroke(hLine, with: .color(lineColor), lineWidth: lineWidth)

            case .continuation:
                // Vertical line top to bottom
                var vLine = Path()
                vLine.move(to: CGPoint(x: midX, y: 0))
                vLine.addLine(to: CGPoint(x: midX, y: size.height))
                context.stroke(vLine, with: .color(lineColor), lineWidth: lineWidth)

            case .blank:
                break
            }
        }
        .frame(width: width)
    }
}
