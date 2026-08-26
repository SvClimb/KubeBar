import SwiftUI
import AppKit

private enum DropdownField {
    case utility
    case context
    case namespace
    case app
}

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

    /// Which dropdown (if any) is currently expanded. Only one may be
    /// open at a time so their overlaid lists never collide.
    @State private var openDropdown: DropdownField?

    /// Suppresses the context/namespace onChange reset logic while we
    /// programmatically restore the last-used selection on appear.
    @State private var isRestoringSelection = false

    private var selectedUtilityObject: Utility? {
        configStore.utilities.first { $0.name == selectedUtility }
    }

    private var utilityNeedsApp: Bool {
        selectedUtilityObject?.commandTemplate.contains("{app}") ?? false
    }

    private var commandPreview: String? {
        let selection = LaunchSelection(
            utilityName: selectedUtility,
            contextName: selectedContext,
            namespaceName: selectedNamespace,
            appName: selectedApp
        )
        return TerminalLauncher.previewCommand(selection: selection, utilities: configStore.utilities)
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

            FilterableDropdown(
                title: "Утилита",
                items: configStore.utilities.map(\.name),
                selection: $selectedUtility,
                isOpen: openBinding(for: .utility),
                placement: .below
            )
            .zIndex(openDropdown == .utility ? 10 : 0)

            HStack {
                FilterableDropdown(
                    title: "Контекст",
                    items: contexts.map(\.name),
                    selection: $selectedContext,
                    isOpen: openBinding(for: .context),
                    placement: .below
                )
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
            .zIndex(openDropdown == .context ? 10 : 0)

            HStack {
                FilterableDropdown(
                    title: "Namespace",
                    items: configStore.savedNamespaces.map(\.name),
                    selection: $selectedNamespace,
                    isOpen: openBinding(for: .namespace),
                    placement: .above
                )
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
            .zIndex(openDropdown == .namespace ? 10 : 0)

            if utilityNeedsApp {
                HStack {
                    FilterableDropdown(
                        title: "App",
                        items: availableApps.map(\.name),
                        selection: $selectedApp,
                        isOpen: openBinding(for: .app),
                        placement: .above
                    )
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
                .zIndex(openDropdown == .app ? 10 : 0)
            }

            if let commandPreview {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Предпросмотр")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(commandPreview)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .controlBackgroundColor)))
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
        .contentShape(Rectangle())
        .onTapGesture {
            openDropdown = nil
        }
        .onAppear {
            restoreLastSelection()
            loadContexts()
        }
        .onChange(of: selectedUtility) { _, _ in
            guard !isRestoringSelection else { return }
            persistSelection()
        }
        .onChange(of: selectedContext) { _, _ in
            guard !isRestoringSelection else { return }
            selectedNamespace = nil
            selectedApp = nil
            persistSelection()
        }
        .onChange(of: selectedNamespace) { _, _ in
            guard !isRestoringSelection else { return }
            selectedApp = nil
            persistSelection()
        }
        .onChange(of: selectedApp) { _, _ in
            guard !isRestoringSelection else { return }
            persistSelection()
        }
    }

    /// Persists the current picks as `lastSelection` immediately, not just
    /// after a Launch/Подготовить — otherwise closing the popover without
    /// running a command loses whatever the user had already chosen, since
    /// the view's @State is torn down and next time it can only restore
    /// from `configStore.lastSelection`.
    private func persistSelection() {
        configStore.lastSelection = LaunchSelection(
            utilityName: selectedUtility,
            contextName: selectedContext,
            namespaceName: selectedNamespace,
            appName: selectedApp
        )
        configStore.save()
    }

    private func openBinding(for field: DropdownField) -> Binding<Bool> {
        Binding(
            get: { openDropdown == field },
            set: { isOpen in
                if isOpen {
                    openDropdown = field
                } else if openDropdown == field {
                    openDropdown = nil
                }
            }
        )
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
