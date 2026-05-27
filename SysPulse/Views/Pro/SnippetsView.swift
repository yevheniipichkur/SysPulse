import SwiftData
import SwiftUI

struct SnippetsView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \CommandSnippet.updatedAt, order: .reverse) private var snippets: [CommandSnippet]

    @State private var isAdding = false
    @State private var editingSnippet: CommandSnippet?
    @State private var copiedID: UUID?
    @State private var searchText = ""
    @State private var selectedCategory: String?

    var onInsert: ((String) -> Void)?

    var body: some View {
        ZStack {
            AppBackground()

            ScrollView {
                VStack(spacing: 16) {
                    PageHeader(
                        title: "Snippets",
                        subtitle: "Reusable command templates",
                        actionSymbol: "plus"
                    ) {
                        guard appState.isProUnlocked else {
                            appState.isPaywallPresented = true
                            return
                        }
                        isAdding = true
                    }

                    if !appState.isProUnlocked {
                        ProLockedBanner(feature: "Command Snippets")
                    } else {
                        if !categories.isEmpty {
                            categoryFilter
                        }

                        TextField("Search snippets", text: $searchText)
                            .textInputAutocapitalization(.never)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                        if filtered.isEmpty {
                            if snippets.isEmpty {
                                ActionEmptyStateView(
                                    title: "No snippets",
                                    message: "Save frequently-used commands as snippets for quick reuse.",
                                    symbol: "text.badge.plus",
                                    actionTitle: "Add Snippet",
                                    actionSymbol: "plus"
                                ) { isAdding = true }
                            } else {
                                Text("No results for "\(searchText)"")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .padding(.top, 20)
                            }
                        } else {
                            ForEach(Array(filtered.enumerated()), id: \.element.id) { index, snippet in
                                SnippetCard(
                                    snippet: snippet,
                                    isCopied: copiedID == snippet.id,
                                    canInsert: onInsert != nil
                                ) {
                                    editingSnippet = snippet
                                } onCopy: {
                                    copySnippet(snippet)
                                } onInsert: {
                                    onInsert?(snippet.body)
                                } onDelete: {
                                    deleteSnippet(snippet)
                                }
                                .listItemEntrance(index: index, disabled: appState.shouldReduceMotion)
                            }
                        }
                    }
                }
                .padding(.horizontal, SysPulseDesign.pagePadding)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
            .scrollIndicators(.hidden)
        }
        .sheet(isPresented: $isAdding) {
            SnippetFormView()
                .presentationDetents([.medium, .large])
                .presentationCornerRadius(32)
        }
        .sheet(item: $editingSnippet) { snippet in
            SnippetFormView(editingSnippet: snippet)
                .presentationDetents([.medium, .large])
                .presentationCornerRadius(32)
        }
    }

    private var categories: [String] {
        Array(Set(snippets.compactMap { $0.category.isEmpty ? nil : $0.category })).sorted()
    }

    private var filtered: [CommandSnippet] {
        var result = snippets
        if let cat = selectedCategory {
            result = result.filter { $0.category == cat }
        }
        if !searchText.isEmpty {
            result = result.filter {
                $0.title.localizedCaseInsensitiveContains(searchText) ||
                $0.body.localizedCaseInsensitiveContains(searchText)
            }
        }
        return result
    }

    private var categoryFilter: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                FilterChip(label: "All", isSelected: selectedCategory == nil) {
                    selectedCategory = nil
                }
                ForEach(categories, id: \.self) { cat in
                    FilterChip(label: cat, isSelected: selectedCategory == cat) {
                        selectedCategory = selectedCategory == cat ? nil : cat
                    }
                }
            }
        }
    }

    private func copySnippet(_ snippet: CommandSnippet) {
        UIPasteboard.general.string = snippet.body
        copiedID = snippet.id
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copiedID = nil }
    }

    private func deleteSnippet(_ snippet: CommandSnippet) {
        modelContext.delete(snippet)
        try? modelContext.save()
    }
}

// MARK: - Snippet Card

private struct SnippetCard: View {
    var snippet: CommandSnippet
    var isCopied: Bool
    var canInsert: Bool
    var onEdit: () -> Void
    var onCopy: () -> Void
    var onInsert: () -> Void
    var onDelete: () -> Void

    var body: some View {
        GlassCard(cornerRadius: 22, padding: 15) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(snippet.title)
                            .font(.headline)
                        if !snippet.category.isEmpty {
                            Text(snippet.category)
                                .font(.caption.weight(.medium))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(.cyan.opacity(0.18), in: Capsule())
                                .foregroundStyle(.cyan)
                        }
                    }
                    Spacer()
                    Button(action: onEdit) {
                        Image(systemName: "pencil")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }

                Text(snippet.body)
                    .font(.caption.monospaced())
                    .lineLimit(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                HStack(spacing: 10) {
                    if canInsert {
                        Button(action: onInsert) {
                            Label("Insert", systemImage: "return")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.cyan)
                        .buttonBorderShape(.roundedRectangle(radius: 12))
                    }

                    Button(action: onCopy) {
                        Label(isCopied ? "Copied" : "Copy", systemImage: isCopied ? "checkmark" : "doc.on.doc")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(isCopied ? .green : .secondary)
                    .buttonBorderShape(.roundedRectangle(radius: 12))

                    Button(role: .destructive, action: onDelete) {
                        Image(systemName: "trash")
                            .frame(width: 36, height: 36)
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.roundedRectangle(radius: 12))
                }
            }
        }
    }
}

// MARK: - Snippet Form

private struct SnippetFormView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    var editingSnippet: CommandSnippet?

    @State private var title = ""
    @State private var body = ""
    @State private var category = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Title") {
                    TextField("e.g. Docker cleanup", text: $title)
                        .autocorrectionDisabled()
                }
                Section("Category (optional)") {
                    TextField("e.g. Docker, Nginx, System", text: $category)
                        .autocorrectionDisabled()
                }
                Section("Command") {
                    TextEditor(text: $body)
                        .font(.caption.monospaced())
                        .frame(minHeight: 120)
                        .autocorrectionDisabled()
                        .autocapitalization(.none)
                }
            }
            .navigationTitle(editingSnippet == nil ? "New Snippet" : "Edit Snippet")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || body.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .onAppear {
            if let s = editingSnippet {
                title = s.title
                body = s.body
                category = s.category
            }
        }
    }

    private func save() {
        if let snippet = editingSnippet {
            snippet.title = title
            snippet.body = body
            snippet.category = category
            snippet.updatedAt = .now
        } else {
            let snippet = CommandSnippet(
                title: title,
                body: body,
                category: category.trimmingCharacters(in: .whitespaces)
            )
            modelContext.insert(snippet)
        }
        try? modelContext.save()
        dismiss()
    }
}

// MARK: - Filter Chip

struct FilterChip: View {
    var label: String
    var isSelected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(
                    isSelected ? Color.cyan : Color.white.opacity(0.1),
                    in: Capsule()
                )
                .foregroundStyle(isSelected ? .white : .primary)
        }
        .buttonStyle(.plain)
    }
}
