import MCP

enum SystemToolDefinitions {
  static let all: [ToolDefinition] = [
    .read(0, SystemContextToolCatalog.overviewTool) {
      try await $0.overviewResult(arguments: $1)
    },
    .read(1, SystemContextToolCatalog.sessionContextTool) { registry, _ in
      try await registry.sessionContextResult()
    },
    .read(2, SystemContextToolCatalog.syncStatusTool) { registry, _ in
      try await registry.syncStatusResult()
    },
    .read(3, SystemContextToolCatalog.setupStatusTool) { registry, _ in
      try await registry.setupStatusResult()
    },
    .read(4, SystemContextToolCatalog.aiChangelogTool) {
      try await $0.aiChangelogResult(arguments: $1)
    },
    .read(5, SystemContextToolCatalog.recentLogsTool) {
      try await $0.recentLogsResult(arguments: $1)
    },
    .read(6, SystemContextToolCatalog.guideTool) {
      try await $0.guideResult(arguments: $1)
    },
    .read(57, DataExportToolCatalog.exportDataTool) {
      try await $0.exportDataResult(arguments: $1)
    },
    .read(107, SystemPreferencesToolCatalog.getAllPreferencesTool) { registry, _ in
      try await registry.getAllPreferencesResult()
    },
    .read(108, SystemPreferencesToolCatalog.getPreferenceTool) {
      try await $0.getPreferenceResult(arguments: $1)
    },
    .write(109, SystemPreferencesToolCatalog.setPreferenceTool) {
      try await $0.setPreferenceResult(arguments: $1)
    },
    .write(110, SystemPreferencesToolCatalog.deletePreferenceTool) {
      try await $0.deletePreferenceResult(arguments: $1)
    },
    .write(111, SystemPreferencesToolCatalog.completeSetupTool) {
      try await $0.completeSetupResult(arguments: $1)
    },
  ]
}
