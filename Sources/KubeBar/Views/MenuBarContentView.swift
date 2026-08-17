import SwiftUI
import AppKit

struct MenuBarContentView: View {
    @EnvironmentObject var configStore: ConfigStore

    @State private var contexts: [KubeContext] = []
    @State private var selectedUtility: String?
    @State private var selectedContext: String?
    @State private var selectedNamespace: String?
    @State private var selectedApp: String?

    @State private var isLoadingContexts = false
    @State private var isRefreshingNamespaces = false
    @State private var isRefreshingApps = false
    @State private var errorMessage: String?

    /// Suppresses the context/namespace onChange reset logic while we
    /// programmatically restore the last-used selection on appear.
    @State private var isRestoringSelection = false

    private var selectedUtilityObject: Utility? {
        configStore.utilities.first { $0.name == selectedUtility }
    }

    private var utilityNeedsApp: Bool {
        selectedUtilityObject?.commandTemplate.contains("{app}") ?? false
    }

    /// Manually added (unscoped) apps are always shown; auto-discovered
    /// ones only when they match the currently selected context+namespace.
    private var availableApps: [NamedEntry] {
        configStore.savedApps.filter { entry in
            guard let entryContext = entry.contextName, let entryNamespace = entry.namespaceName else {
                return true
            }
            return entryContext == selectedContext && entryNamespace == selectedNamespace
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("KubeBar").font(.headline)

            Picker("Утилита", selection: $selectedUtility) {
                Text("—").tag(String?.none)
                ForEach(configStore.utilities) { utility in
                    Text(utility.name).tag(String?.some(utility.name))
                }
            }

            HStack {
                Picker("Контекст", selection: $selectedContext) {
                    Text("—").tag(String?.none)
                    ForEach(contexts) { context in
                        Text(context.name).tag(String?.some(context.name))
                    }
                }
                if isLoadingContexts {
                    ProgressView().controlSize(.small)
                } else {
                    Button {
                        loadContexts()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                }
            }

            HStack {
                Picker("Namespace", selection: $selectedNamespace) {
                    Text("—").tag(String?.none)
                    ForEach(configStore.savedNamespaces) { entry in
                        Text(entry.name).tag(String?.some(entry.name))
                    }
                }
                Button {
                    refreshNamespaces()
                } label: {
                    if isRefreshingNamespaces {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .disabled(selectedContext == nil || isRefreshingNamespaces)
                .buttonStyle(.borderless)
            }

            if utilityNeedsApp {
                HStack {
                    Picker("App", selection: $selectedApp) {
                        Text("—").tag(String?.none)
                        ForEach(availableApps) { entry in
                            Text(entry.name).tag(String?.some(entry.name))
                        }
                    }
                    Button {
                        refreshApps()
                    } label: {
                        if isRefreshingApps {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .disabled(selectedContext == nil || selectedNamespace == nil || isRefreshingApps)
                    .buttonStyle(.borderless)
                }
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            HStack {
                Button("Launch") {
                    launch(mode: .execute)
                }
                .keyboardShortcut(.defaultAction)

                Button("Подготовить") {
                    launch(mode: .prepare)
                }
                .help("Открыть терминал с готовой командой, не запуская её")

                Spacer()

                Button {
                    SettingsWindowController.shared.show(configStore: configStore)
                } label: {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(.borderless)

                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(16)
        .frame(width: 340)
        .onAppear {
            restoreLastSelection()
            loadContexts()
        }
        .onChange(of: selectedContext) { _, _ in
            guard !isRestoringSelection else { return }
            selectedNamespace = nil
            selectedApp = nil
        }
        .onChange(of: selectedNamespace) { _, _ in
            guard !isRestoringSelection else { return }
            selectedApp = nil
        }
    }

    private func restoreLastSelection() {
        isRestoringSelection = true
        selectedUtility = configStore.lastSelection.utilityName
        selectedContext = configStore.lastSelection.contextName
        selectedNamespace = configStore.lastSelection.namespaceName
        selectedApp = configStore.lastSelection.appName
        DispatchQueue.main.async {
            isRestoringSelection = false
        }
    }

    private func loadContexts() {
        isLoadingContexts = true
        errorMessage = nil
        let kubectlPath = kubectlExecutable()
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let fetched = try KubeconfigService.fetchContexts(kubectlExecutable: kubectlPath)
                DispatchQueue.main.async {
                    self.contexts = fetched
                    self.isLoadingContexts = false
                    if self.selectedContext == nil {
                        self.selectedContext = fetched.first?.name
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self.errorMessage = error.localizedDescription
                    self.isLoadingContexts = false
                }
            }
        }
    }

    private func refreshNamespaces() {
        guard let context = selectedContext else { return }
        isRefreshingNamespaces = true
        errorMessage = nil
        let kubectlPath = kubectlExecutable()
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let names = try KubeQueryService.fetchNamespaces(context: context, kubectlExecutable: kubectlPath)
                DispatchQueue.main.async {
                    for name in names { self.configStore.addNamespace(name) }
                    self.isRefreshingNamespaces = false
                }
            } catch {
                DispatchQueue.main.async {
                    self.errorMessage = error.localizedDescription
                    self.isRefreshingNamespaces = false
                }
            }
        }
    }

    private func refreshApps() {
        guard let context = selectedContext, let namespace = selectedNamespace else { return }
        isRefreshingApps = true
        errorMessage = nil
        let kubectlPath = kubectlExecutable()
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let names = try KubeQueryService.fetchApps(context: context, namespace: namespace, kubectlExecutable: kubectlPath)
                DispatchQueue.main.async {
                    self.configStore.syncApps(names, contextName: context, namespaceName: namespace)
                    self.isRefreshingApps = false
                }
            } catch {
                DispatchQueue.main.async {
                    self.errorMessage = error.localizedDescription
                    self.isRefreshingApps = false
                }
            }
        }
    }

    private func kubectlExecutable() -> String {
        configStore.utilities.first(where: { $0.name == "kubectl" })?.executable ?? "kubectl"
    }

    private func launch(mode: TerminalLaunchMode) {
        let selection = LaunchSelection(
            utilityName: selectedUtility,
            contextName: selectedContext,
            namespaceName: selectedNamespace,
            appName: selectedApp
        )
        guard let profile = configStore.selectedTerminalProfile else {
            errorMessage = "Не выбран терминал в настройках."
            return
        }
        do {
            let (utility, commandString) = try TerminalLauncher.buildCommand(selection: selection, utilities: configStore.utilities)
            try TerminalLauncher.launch(commandString: commandString, terminalProfile: profile, mode: mode)
            configStore.lastSelection = selection
            configStore.addHistoryEntry(HistoryEntry(
                timestamp: Date(),
                utilityName: utility.name,
                contextName: selection.contextName ?? "",
                namespaceName: selection.namespaceName ?? "",
                appName: selection.appName,
                commandString: commandString,
                wasPrepared: mode == .prepare
            ))
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
