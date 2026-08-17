import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var configStore: ConfigStore

    @State private var newUtilityName = ""
    @State private var newUtilityExecutable = ""
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
                ForEach($configStore.utilities) { $utility in
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                TextField("Имя", text: $utility.name)
                                    .frame(width: 100)
                                TextField("Исполняемый файл/путь", text: $utility.executable)
                            }
                            TextField("Шаблон команды", text: $utility.commandTemplate)
                                .font(.system(.body, design: .monospaced))
                        }
                        deleteButton {
                            configStore.utilities.removeAll { $0.id == utility.id }
                            configStore.save()
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
            .onChange(of: configStore.utilities) { _, _ in
                configStore.save()
            }

            HStack {
                TextField("Имя", text: $newUtilityName)
                TextField("Исполняемый файл/путь", text: $newUtilityExecutable)
                Button("Добавить") {
                    guard !newUtilityName.isEmpty, !newUtilityExecutable.isEmpty else { return }
                    configStore.utilities.append(
                        Utility(
                            name: newUtilityName,
                            executable: newUtilityExecutable,
                            commandTemplate: "{executable} --context {context} -n {namespace} {app}"
                        )
                    )
                    configStore.save()
                    newUtilityName = ""
                    newUtilityExecutable = ""
                }
            }
        }
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
