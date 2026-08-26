import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var configStore: ConfigStore

    private enum UtilitySheet: Identifiable {
        case add
        case edit(index: Int)

        var id: String {
            switch self {
            case .add: return "add"
            case .edit(let index): return "edit-\(index)"
            }
        }
    }

    @State private var utilitySheet: UtilitySheet?
    @State private var newNamespace = ""
    @State private var newApp = ""
    @State private var newTerminalName = ""
    @State private var launchAtLogin = false

    var body: some View {
        TabView {
            utilitiesTab.tabItem { Text("Утилиты") }
            namespacesTab.tabItem { Text("Namespaces") }
            appsTab.tabItem { Text("Apps") }
            terminalTab.tabItem { Text("Терминал") }
            historyTab.tabItem { Text("История") }
            generalTab.tabItem { Text("Общие") }
        }
        .padding(20)
        .frame(width: 540, height: 440)
        .onAppear {
            launchAtLogin = LoginItemManager.isEnabled
        }
    }

    private func deleteButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "minus.circle.fill")
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.borderless)
        .help("Удалить")
    }

    // MARK: - Утилиты

    private static let utilityTemplateExamples: [(name: String, template: String)] = [
        ("stern (по умолчанию)", "{executable} --context {context} -n {namespace} {app}"),
        ("stern с таймаутом", "{executable} --context {context} -n {namespace} {app} --since 1h --timeout 30m"),
        ("kubectl logs", "{executable} --context {context} -n {namespace} logs -f deployment/{app}"),
        ("kubectl get pods", "{executable} --context {context} -n {namespace} get pods -l app={app} -o wide"),
        ("kubectl без app", "{executable} --context {context} -n {namespace}")
    ]

    private var utilitiesTab: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Каждая строка — своя команда: имя (как показывается в меню), исполняемый файл/алиас (например «k»), и шаблон. Плейсхолдеры: {executable} {context} {namespace} {app} — уберите {app}, если утилите не нужен под/приложение. Нужны разные варианты для одной утилиты (get pods, logs, свои флаги) — просто добавьте ещё одну строку с тем же executable и другим именем/шаблоном.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            DisclosureGroup("Примеры шаблонов") {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Self.utilityTemplateExamples, id: \.name) { example in
                        VStack(alignment: .leading, spacing: 1) {
                            Text(example.name)
                                .font(.caption.bold())
                            Text(example.template)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.top, 4)
            }
            .font(.caption)

            List {
                ForEach(Array(configStore.utilities.enumerated()), id: \.element.id) { index, utility in
                    UtilityRow(
                        utility: utility,
                        canMoveUp: index > 0,
                        canMoveDown: index < configStore.utilities.count - 1,
                        onMoveUp: { moveUtility(from: index, to: index - 1) },
                        onMoveDown: { moveUtility(from: index, to: index + 1) },
                        onEdit: { utilitySheet = .edit(index: index) },
                        onDelete: {
                            configStore.utilities.remove(at: index)
                            configStore.save()
                        }
                    )
                }
            }

            Button("Добавить утилиту") {
                utilitySheet = .add
            }
        }
        .sheet(item: $utilitySheet) { sheet in
            switch sheet {
            case .add:
                UtilityEditorView(
                    utility: Utility(name: "", executable: "", commandTemplate: "{executable} --context {context} -n {namespace} {app}"),
                    isNew: true,
                    existingNames: Set(configStore.utilities.map(\.name))
                ) { newUtility in
                    configStore.utilities.append(newUtility)
                    configStore.save()
                }
            case .edit(let index):
                if configStore.utilities.indices.contains(index) {
                    let otherNames = Set(
                        configStore.utilities.enumerated()
                            .filter { $0.offset != index }
                            .map { $0.element.name }
                    )
                    UtilityEditorView(utility: configStore.utilities[index], isNew: false, existingNames: otherNames) { updated in
                        configStore.utilities[index] = updated
                        configStore.save()
                    }
                }
            }
        }
    }

    private func moveUtility(from: Int, to: Int) {
        guard configStore.utilities.indices.contains(from), configStore.utilities.indices.contains(to) else { return }
        configStore.utilities.swapAt(from, to)
        configStore.save()
    }

    // MARK: - Namespaces

    private var namespacesTab: some View {
        VStack(alignment: .leading) {
            List {
                ForEach(configStore.savedNamespaces) { entry in
                    HStack {
                        Text(entry.name)
                        Spacer()
                        deleteButton {
                            configStore.savedNamespaces.removeAll { $0.id == entry.id }
                            configStore.save()
                        }
                    }
                }
            }
            HStack {
                TextField("Namespace", text: $newNamespace)
                Button("Добавить") {
                    guard !newNamespace.isEmpty else { return }
                    configStore.addNamespace(newNamespace)
                    newNamespace = ""
                }
            }
        }
    }

    // MARK: - Apps

    private var appsTab: some View {
        VStack(alignment: .leading) {
            List {
                ForEach(configStore.savedApps) { entry in
                    HStack {
                        Text(entry.name)
                        if let contextName = entry.contextName, let namespaceName = entry.namespaceName {
                            Text("· \(contextName)/\(namespaceName)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        deleteButton {
                            configStore.savedApps.removeAll { $0.id == entry.id }
                            configStore.save()
                        }
                    }
                }
            }
            HStack {
                TextField("App", text: $newApp)
                Button("Добавить") {
                    guard !newApp.isEmpty else { return }
                    configStore.addApp(newApp)
                    newApp = ""
                }
            }
        }
    }

    // MARK: - Терминал

    private var terminalTab: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("{{command}} заменяется на собранную команду утилиты, строка выполняется как есть через /bin/zsh -lc. «Команда запуска» — сразу выполняет; «Команда подготовки» — открывает терминал с командой, но не запускает (пусто = режим «Подготовить» недоступен для этого профиля).")
                .font(.caption)
                .foregroundStyle(.secondary)

            Picker("Активный терминал", selection: $configStore.selectedTerminalProfileName) {
                ForEach(configStore.terminalProfiles) { profile in
                    Text(profile.name).tag(profile.name)
                }
            }
            .onChange(of: configStore.selectedTerminalProfileName) { _, _ in
                configStore.save()
            }

            List {
                ForEach($configStore.terminalProfiles) { $profile in
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            TextField("Имя", text: $profile.name)
                            TextField("Команда запуска", text: $profile.launchTemplate)
                                .font(.system(.body, design: .monospaced))
                            TextField("Команда подготовки (без выполнения)", text: $profile.prepareTemplate)
                                .font(.system(.body, design: .monospaced))
                        }
                        deleteButton {
                            configStore.terminalProfiles.removeAll { $0.id == profile.id }
                            configStore.save()
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
            .onChange(of: configStore.terminalProfiles) { _, _ in
                configStore.save()
            }

            HStack {
                TextField("Имя нового профиля", text: $newTerminalName)
                Button("Добавить") {
                    guard !newTerminalName.isEmpty else { return }
                    configStore.terminalProfiles.append(
                        TerminalProfile(
                            name: newTerminalName,
                            launchTemplate: "open -na \"\(newTerminalName)\" --args -e {{command}}",
                            prepareTemplate: "printf '%s' '{{command}}' | pbcopy && open -na \"\(newTerminalName)\""
                        )
                    )
                    configStore.save()
                    newTerminalName = ""
                }
            }
        }
    }

    // MARK: - История

    private var historyTab: some View {
        VStack(alignment: .leading) {
            HStack {
                Text("Последние \(ConfigStore.maxHistoryEntries) команд. Правый клик по записи — запустить снова.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Очистить") {
                    configStore.clearHistory()
                }
                .disabled(configStore.history.isEmpty)
            }

            if configStore.history.isEmpty {
                Text("Пока пусто — команды появятся здесь после запуска.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            List {
                ForEach(configStore.history) { entry in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.commandString)
                            .font(.system(.body, design: .monospaced))
                        HStack(spacing: 4) {
                            Text(entry.timestamp.formatted(date: .abbreviated, time: .shortened))
                            if entry.wasPrepared {
                                Text("· подготовлена")
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                    .contextMenu {
                        Button("Запустить снова") {
                            relaunch(entry, mode: .execute)
                        }
                        Button("Подготовить снова") {
                            relaunch(entry, mode: .prepare)
                        }
                    }
                }
            }
        }
    }

    private func relaunch(_ entry: HistoryEntry, mode: TerminalLaunchMode) {
        guard let profile = configStore.selectedTerminalProfile else { return }
        try? TerminalLauncher.launch(commandString: entry.commandString, terminalProfile: profile, mode: mode)
    }

    // MARK: - Общие

    private var generalTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("Запускать при входе в систему", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, newValue in
                    LoginItemManager.setEnabled(newValue)
                }
            Spacer()
        }
    }
}

/// Read-only summary row for one utility template: name and executable are
/// each explicitly labeled so they stay distinguishable even when they
/// happen to be the same word (e.g. a utility named "kubectl" that also
/// runs the "kubectl" executable). Editing happens in `UtilityEditorView`.
private struct UtilityRow: View {
    let utility: Utility
    let canMoveUp: Bool
    let canMoveDown: Bool
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(spacing: 2) {
                Button(action: onMoveUp) {
                    Image(systemName: "chevron.up")
                }
                .disabled(!canMoveUp)
                Button(action: onMoveDown) {
                    Image(systemName: "chevron.down")
                }
                .disabled(!canMoveDown)
            }
            .buttonStyle(.borderless)
            .font(.caption)
            .help("Изменить порядок")

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Text("Имя:").font(.caption).foregroundStyle(.secondary)
                    Text(utility.name).font(.headline)
                }
                HStack(spacing: 4) {
                    Text("Утилита:").font(.caption).foregroundStyle(.secondary)
                    Text(utility.executable)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                Text(utility.commandTemplate)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer()

            Button(action: onEdit) {
                Image(systemName: "pencil")
            }
            .buttonStyle(.borderless)
            .help("Редактировать")

            Button(action: onDelete) {
                Image(systemName: "minus.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .help("Удалить")
        }
        .padding(.vertical, 4)
    }
}
