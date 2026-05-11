export interface SessionListInfo {
  id: string
  title: string
  messageCount?: number
  lastMessagePreview?: string
  createdAt: number
  updatedAt: number
}

export interface SessionHistoryMessage {
  id: string
  type: string
  role?: string
  timestamp: number
  content?: SessionHistoryMessageContent[]
  messageId?: string
  taskId?: string
  action?: string
  taskTitle?: string
  todos?: SessionHistoryMessageTodoItem[]
  sandboxId?: string
  acceptedSummary?: string
  reviewDiff?: FileDiff[]
  reviewDiffTotal?: number
  confirmationId?: string
  traceparent?: string
  tracestate?: string
  question?: SessionHistoryMessageQuestionInfo
  questionReply?: SessionHistoryMessageQuestionReplyInfo
  saveFileRequest?: SessionHistoryMessageSaveFileRequestInfo
  saveFileReply?: SessionHistoryMessageSaveFileReplyInfo
  permissionRequest?: SessionHistoryMessagePermissionRequestInfo
  permissionReply?: SessionHistoryMessagePermissionReplyInfo
  secretInput?: SessionHistoryMessageSecretInputInfo
  secretInputReply?: SessionHistoryMessageSecretInputReplyInfo
  schedule?: SessionHistoryMessageScheduleReference
  toolUseId?: string
  errorType?: string
  error?: string
}

export interface SessionHistoryMessageContent {
  type: string
  text?: string
  url?: string
  fileRef?: SessionHistoryMessageFileRef
  fileRefs?: SessionHistoryMessageFileRef[]
  fileName?: string
  mimeType?: string
  sizeBytes?: number
  entryKind?: string
  quoteRef?: SessionHistoryMessageQuoteReference
}

export interface SessionHistoryMessageQuoteReference {
  sourceMessageId: string
  startOffset: number
  endOffset: number
}

export interface SessionHistoryMessageFileRef {
  environmentId?: string
  path: string
}

export interface SessionHistoryMessageTodoItem {
  content: string
  status: string
}

export interface SessionHistoryMessageQuestionInfo {
  question: string
  header?: string
  options: SessionHistoryMessageQuestionOption[]
  multiSelect?: boolean
}

export interface SessionHistoryMessageQuestionOption {
  label: string
  description?: string
}

export interface SessionHistoryMessageQuestionReplyInfo {
  reply?: AnyCodable
  cancelled?: boolean
}

export interface SessionHistoryMessageSaveFileRequestInfo {
  environmentId: string
  path: string
  fileName?: string
  mimeType?: string
  title?: string
  message?: string
  size?: number
}

export interface SessionHistoryMessageSaveFileReplyInfo {
  approved?: boolean
  cancelled?: boolean
  fileName?: string
  mimeType?: string
  bytesWritten?: number
}

export interface SessionHistoryMessagePermissionRequestInfo {
  environmentId: string
  environmentLabel?: string
  kind?: string
  description: string
  computerUseStart?: SessionHistoryMessageComputerUseStartInfo
}

export interface SessionHistoryMessageComputerUseStartInfo {
  availableModes: string[]
  apps?: string[]
  permissions?: SessionHistoryMessageComputerUsePermissionPane[]
}

export interface SessionHistoryMessageComputerUsePermissionPane {
  pane: string
  granted: boolean
}

export interface SessionHistoryMessagePermissionReplyInfo {
  approved: boolean
  reason?: string
  mode?: string
}

export interface SessionHistoryMessageSecretInputInfo {
  prompt: string
  label?: string
  slot?: string
}

export interface SessionHistoryMessageSecretInputReplyInfo {
  provided: boolean
  cancelled?: boolean
}

export interface SessionHistoryMessageScheduleReference {
  scheduleId: string
  title: string
  subtitle?: string
  isPaused?: boolean
  hasError?: boolean
}

export interface FileDiff {
  path: string
  mode: number
  isDir: boolean
  isUpdated: boolean
  isDeleted: boolean
  movedFrom?: string
  timestamp: string
  size: number
}

export interface WorkspaceState {
  sessionId: string
  environmentId: string
  environmentLabel: string
  fileDiff: FileDiff[]
}

export interface AssistantStageStreamState {
  messageId?: string
  responseId?: string
  text: string
  isStreaming: boolean
}

export interface AssistantToolCallState {
  callId: string
  toolName: string
  summary?: string
  args?: string
  startedAt: number
  endedAt?: number
  success?: boolean
  error?: string
  result?: string
  status?: string
  statusUpdatedAt?: number
}

export interface AssistantState {
  phase: string
  sequence: number
  phaseStartedAt: number
  updatedAt: number
  reasoning?: AssistantStageStreamState
  messaging?: AssistantStageStreamState
  tools: AssistantToolCallState[]
  asyncToolcalls: AssistantAsyncToolcallState[]
}

export interface AssistantAsyncToolcallState {
  toolcallId: string
  llmCallId?: string
  toolName: string
  summary?: string
  environmentId?: string
  environmentLabel?: string
  requestedMode?: string
  promotedToAsync: boolean
  resultPath?: string
  status: string
  createdAt: number
  startedAt?: number
  endedAt?: number
  error?: string
  exitCode?: number
}

export interface WebViewContextMenuIcon {
  kind: string
  value: string
}

export interface WebViewContextMenuItem {
  kind: string
  id?: string
  title?: string
  icon?: WebViewContextMenuIcon
  enabled?: boolean
  items?: WebViewContextMenuItem[]
}

export interface WebViewContextMenuRequest {
  menuId: string
  x: number
  y: number
  items: WebViewContextMenuItem[]
  hasSelection: boolean
  isEditable: boolean
}

export interface WebViewContextMenuActionEvent {
  menuId: string
  itemId: string
}

export interface WebViewContextMenuClosedEvent {
  menuId: string
}

export interface FollowUpItem {
  id: string
  displayText: string
  sendText: string
}

export interface FollowUpState {
  items: FollowUpItem[]
  isGenerating: boolean
}

export interface ScheduleCard {
  id: string
  title: string
  subtitle: string
  hasError: boolean
  isPaused: boolean
  isDeleted: boolean
  willTriggerAgain: boolean
}

export interface ChatHistoryInitPayload {
  messages: SessionHistoryMessage[]
  scrollTop?: number
}

export interface WebViewPreviewSourceRect {
  x: number
  y: number
  width: number
  height: number
}

export interface ConversationSearchResult {
  id: string
  conversationId: string
  conversationTitle: string
  messageId: string
  role: string
  createdAt: number
  snippet: string
  score: number
}

export interface ComposerQuotePayload {
  text: string
  quoteRef: SessionHistoryMessageQuoteReference
}

export interface QuoteFocusEvent {
  quoteRef: SessionHistoryMessageQuoteReference
  requestId: number
}

export interface ContextMenuBridge {
  popupMenu: (request: WebViewContextMenuRequest) => Promise<void>
  onMenuAction: (listener: (data: WebViewContextMenuActionEvent) => void) => () => void
  onMenuClosed: (listener: (data: WebViewContextMenuClosedEvent) => void) => () => void
}

export interface MessagesBridge {
  getSchedules: () => Promise<ScheduleCard[]>
  getFileIcon: (path: string) => Promise<string | undefined | null>
  getLocalImageDataURL: (path: string) => Promise<string | undefined | null>
  revealInFinder: (path: string[]) => Promise<void>
  openFolder: (path: string) => Promise<void>
  previewWorkspaceFile: (path: string, environmentId: string, sourceRect: WebViewPreviewSourceRect | undefined | null) => Promise<void>
  previewHostFile: (relPath: string, sourceRect: WebViewPreviewSourceRect | undefined | null) => Promise<void>
  previewAttachment: (source: string, fileName: string | undefined | null, mimeType: string | undefined | null, sourceRect: WebViewPreviewSourceRect | undefined | null) => Promise<void>
  prepareAttachmentPreview: (source: string, fileName: string | undefined | null, mimeType: string | undefined | null) => Promise<void>
  clearAttachmentPreviews: () => Promise<void>
  checkFilesExist: (paths: string[]) => Promise<{[key: string]: boolean}>
  cancelTask: (_: string) => Promise<void>
  acceptFiles: (paths: string[], environmentId: string) => Promise<void>
  discardAllChanges: (environmentId: string) => Promise<void>
  getWorkspaceState: () => Promise<WorkspaceState | undefined | null>
  openComputerUsePermissionFlow: () => Promise<void>
  requestComputerUsePermission: (pane: string) => Promise<SessionHistoryMessageComputerUsePermissionPane[]>
  getComputerUsePermissionsStatus: () => Promise<SessionHistoryMessageComputerUsePermissionPane[]>
  replyInteraction: (confirmationId: string, replyJSON: string) => Promise<void>
  saveRemoteFile: (_: string) => Promise<void>
  sendMessage: (text: string) => Promise<void>
  setComposerQuote: (payload: ComposerQuotePayload) => Promise<void>
  retryMessage: () => Promise<void>
  pauseSchedule: (scheduleID: string) => Promise<void>
  resumeSchedule: (scheduleID: string) => Promise<void>
  deleteSchedule: (scheduleID: string) => Promise<void>
  trackCopyFromChat: (contentType: string) => Promise<void>
  copyText: (text: string) => Promise<boolean>
  goodMessage: (userMessageId: string) => Promise<void>
  badMessage: (userMessageId: string) => Promise<void>
  fetchRecentConversations: () => Promise<SessionListInfo[]>
  openConversation: (conversationId: string) => Promise<void>
  searchConversations: (query: string) => Promise<ConversationSearchResult[]>
  openConversationSearchResult: (conversationId: string, messageId: string | undefined | null) => Promise<void>
  getStorageDownloadUrl: (url: string) => Promise<string>
  getAssistantState: () => Promise<AssistantState | undefined | null>
  updateScrollPosition: (scrollTop: number) => Promise<void>
  onIsStreaming: (listener: (data: boolean) => void) => () => void
  onHasOpenTask: (listener: (data: boolean) => void) => () => void
  onHistoryMessageAdded: (listener: (data: SessionHistoryMessage) => void) => () => void
  onHistoryInit: (listener: (data: ChatHistoryInitPayload) => void) => () => void
  onWorkspaceState: (listener: (data: WorkspaceState | undefined | null) => void) => () => void
  onAssistantState: (listener: (data: AssistantState | undefined | null) => void) => () => void
  onPaddingTop: (listener: (data: number) => void) => () => void
  onFollowUpState: (listener: (data: FollowUpState) => void) => () => void
  onSchedules: (listener: (data: ScheduleCard[]) => void) => () => void
  onCanRetry: (listener: (data: boolean) => void) => () => void
  onRecentSessions: (listener: (data: SessionListInfo[]) => void) => () => void
  onConversationSearchRequested: (listener: (data: number) => void) => () => void
  onFocusMessage: (listener: (data: string) => void) => () => void
  onFocusQuote: (listener: (data: QuoteFocusEvent) => void) => () => void
}

export interface UtilsBridge {
  openURL: (urlString: string) => Promise<void>
  isDebugMode: () => Promise<boolean>
  getAccentBackgroundColor: () => Promise<string>
  getAccentForegroundColor: () => Promise<string>
  getLanguage: () => Promise<string>
  saveFile: (filename: string, content: string, mimeType: string) => Promise<void>
  getUsername: () => Promise<string>
  openPaywall: () => Promise<void>
  getMacOSMajorVersion: () => Promise<number>
  saveImage: (imageURL: string, filename: string | undefined | null) => Promise<void>
  onSetDebugMode: (listener: (data: boolean) => void) => () => void
  onSetAccentForegroundColor: (listener: (data: string) => void) => () => void
  onSetAccentBackgroundColor: (listener: (data: string) => void) => () => void
  onSetLanguage: (listener: (data: string) => void) => () => void
  onSetUsername: (listener: (data: string) => void) => () => void
}

declare global {
  interface Window {
    jsb: {
      ContextMenuBridge: ContextMenuBridge
      MessagesBridge: MessagesBridge
      UtilsBridge: UtilsBridge
    }
    jsbEvents: {
      emit: (event: string, data: unknown) => void
    }
  }
}