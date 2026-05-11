enum AccessibilityID {
    enum Chat {
        static let window = "chat.window"
        static let panelWindow = "chat.window.panel"
        static let mainWindow = "chat.window.main"
        static let closeButton = "chat.header.closeButton"
        static let newChatButton = "chat.header.newChatButton"
        static let historyButton = "chat.header.historyButton"
        static let searchButton = "chat.header.searchButton"
        static let moreButton = "chat.header.moreButton"
        static let sidebarToggleButton = "chat.header.sidebarToggleButton"
        static let switchPresentationButton = "chat.header.switchPresentationButton"
        static let messageContainer = "chat.message.container"
        static let sidebar = "chat.sidebar"
        static let composer = "chat.composer.container"
        static let composerInput = "chat.composer.input"
        static let composerSendButton = "chat.composer.sendButton"
        static let composerModelSelector = "chat.composer.modelSelector"
        static let composerPermissionSelector = "chat.composer.permissionSelector"
        static let composerUploadButton = "chat.composer.uploadButton"
        static let composerVoiceButton = "chat.composer.voiceButton"
        static let composerVoiceWaveform = "chat.composer.voiceWaveform"
        static let composerVoiceStopButton = "chat.composer.voiceStopButton"
        static let moreMenuOpenLargeWindow = "chat.moreMenu.openLargeWindow"
        static let moreMenuOpenSkillSettings = "chat.moreMenu.openSkillSettings"
        static let messageWebViewHost = "chat.message.webViewHost"
        static let skillBadge = "chat.skill.badge"
        static let skillDismissButton = "chat.skill.dismissButton"
        static let autoSkillBadge = "chat.autoSkill.badge"
        static let autoSkillDismissButton = "chat.autoSkill.dismissButton"
        static let autoSkillRunButton = "chat.autoSkill.runButton"
    }

    enum Settings {
        static let window = "settings.window"
        static let sidebar = "settings.sidebar"
        static let generalTab = "settings.tab.general"
        static let soundsTab = "settings.tab.sounds"
        static let systemSkillsTab = "settings.tab.systemSkills"
        static let mySkillsTab = "settings.tab.mySkills"
        static let syncedSkillsTab = "settings.tab.syncedSkills"
        static let shortcutsTab = "settings.tab.shortcuts"
        static let accessTab = "settings.tab.access"
        static let accessScreenRecordingRefreshButton = "settings.access.screenRecording.refreshButton"
        static let notificationsTab = "settings.tab.notifications"
        static let notificationsRoot = "settings.notifications.root"
        static let notificationsScheduledTaskToggle = "settings.notifications.scheduledTaskToggle"
        static let aboutTab = "settings.tab.about"
    }

    enum Notch {
        static let container = "notch.container"
        static let taskCard = "notch.taskCard"
        static let taskCardTitle = "notch.taskCard.title"
        static let taskCardCloseButton = "notch.taskCard.closeButton"
        static let taskCardCancelButton = "notch.taskCard.cancelButton"
        static let taskCardAcceptButton = "notch.taskCard.acceptButton"
        static let taskCardOpenInChatButton = "notch.taskCard.openInChatButton"
        static let clearCompletedTasksButton = "notch.clearCompletedTasksButton"
    }

    enum WebViewHost {}

    enum Window {
        static let chat = "window.chat"
        static let settings = "window.settings"
        static let backgroundTasks = "window.backgroundTasks"
    }
}
