import AppKit
import Foundation
import Observation

/// The Live screen: the running show, its chat, the voting of the team and
/// the replay (Go `App.Live`, `App.OpenChat`, `App.SendChat`, `App.ReplyChat`,
/// `App.ReactChat`, `App.VotePoll` and `App.PlayLive`).
@MainActor @Observable final class LiveModel {
    @ObservationIgnored let app: AppModel

    /// The state of the live endpoint.
    private(set) var info: LivestreamInfo?
    /// Whether the live state is loading.
    private(set) var isLoading = false
    /// The lines of the chat, the oldest first.
    private(set) var lines: [LiveChatLine] = []
        /// Every line that came into the chat, including those the history cap
        /// drops again. The Live screen counts new messages with it.
        private(set) var receivedLines = 0
    /// The voting of the show.
    private(set) var poll: LivePoll?
    /// Whether the chat is connected.
    private(set) var isChatConnected = false
    /// The state of the chat ("Chat verbunden", "12 im Chat").
    private(set) var chatStatus = ""
    /// The number of people in the chat.
    private(set) var chatPeople = ""
    /// The text of the composer.
    var composerText = ""
    /// Whether the message goes to the studio; only the team reads it.
    var sendToStudio = false
    /// The message that is answered.
    private(set) var replyTarget: LiveChatLine?
    /// The chosen message of the chat.
    var selectedID: String?
    /// The pictures of the senders.
    private(set) var avatars: [String: Data] = [:]
    /// The emoji of the reactions the server named and the app does not
    /// know.
    private(set) var reactionEmojis: [String: String] = [:]
    /// The name the server gives the own messages.
    private(set) var selfName = ""

    /// Announces a mention or a reaction of the chat; the container wires it
    /// to the notification center of the app.
    @ObservationIgnored var notify: (@MainActor (_ title: String, _ body: String) -> Void)?

    @ObservationIgnored private var session: ChatSession?
    @ObservationIgnored private var sessionTask: Task<Void, Never>?
    @ObservationIgnored private let avatarLoader = LiveAvatarLoader()
    /// The account the chat belongs to; a change closes the chat.
    @ObservationIgnored private var account = -1
    /// When the live state was read; `liveActive` is skipped while it is
    /// younger than `CacheTTL.live`.
    private(set) var lastLoadedAt: Date?
    /// Increases with every load; an answer of an older load is dropped.
    @ObservationIgnored private var loadToken = 0
    /// Increases with every chat start and close; a stale start closes its
    /// connection instead of publishing it.
    @ObservationIgnored private var chatGeneration = 0
    /// The pending new attempt to connect the chat.
    @ObservationIgnored private var retryTask: Task<Void, Never>?
    /// The attempts since the chat last connected; the wait grows with them.
    @ObservationIgnored private var retryCount = 0
    /// The Live screens that show; the chat closes only when none is left.
    @ObservationIgnored private var screens = 0
    /// The close after the last screen went; a screen that comes back
    /// within the grace time cancels it.
    @ObservationIgnored private var closeTask: Task<Void, Never>?
    /// The connects that run right now.
    @ObservationIgnored private var startsInFlight = 0

    init(app: AppModel) {
        self.app = app
    }

    // MARK: The chat of the moment

    /// Whether the app watches the chat for mentions and reactions even
    /// while the Live page is not showing. The setting is on by default.
    private var watchesChat: Bool { app.settings.chatNotificationsOn && app.hasCredentials }

    /// Whether the chat of the moment can be shown: during a show only when
    /// the show has one; without a show the room stays open, as on the web
    /// page.
    private var chatAvailable: Bool {
        guard let info else { return true }
        if info.isLive { return info.show?.chat == true }
        return true
    }

    /// Whether the chat should be connected right now: a Live screen wants
    /// it, or the app watches it for notifications.
    private var chatWanted: Bool {
        if watchesChat { return true }
        return screens > 0 && chatAvailable
    }

    /// Starts the background chat: with the setting on, the chat stays open
    /// so mentions and reactions reach the Mac even when the Live page is
    /// closed. Called once at launch, after the credentials are read.
    func start() {
        guard chatWanted else { return }
        Task { await syncChat() }
    }

    /// The chat notifications were switched: connect or drop the background
    /// chat.
    func settingsChanged() async {
        if chatWanted {
            await syncChat()
        } else if screens == 0 || !chatAvailable {
            await close()
        }
    }

    /// Opens the chat when it should be connected and is not.
    private func syncChat() async {
        guard chatWanted, !isChatConnected, session == nil,
              startsInFlight == 0, retryTask == nil else { return }
        await startChat()
    }

    // MARK: Loading

    /// Reads the live state and opens the chat the page wants (Go `loadLive`
    /// and `LiveMsg`).
    /// - Parameter force: asks the API even when the state is fresh (the
    ///   toolbar's refresh).
    func load(force: Bool = false) async {
        loadToken += 1
        let token = loadToken
        // A section switch inside the TTL keeps the state and the chat.
        if !force, info != nil, let lastLoadedAt,
           Date().timeIntervalSince(lastLoadedAt) <= CacheTTL.live {
            // The state is fresh, but the screen closed the chat when it
            // was left: open it again, or keep it for the background.
            if chatWanted, session == nil { await startChat() }
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            let state = try await app.services.api.liveActive(refresh: force)
            guard token == loadToken else { return }
            info = state
            lastLoadedAt = Date()
            if chatWanted {
                if !isChatConnected {
                    if chatAvailable { lines.removeAll() }
                    await startChat()
                    // A newer load owns the state now; the chat opened here
                    // belongs to nobody.
                    if token != loadToken {
                        await closeChat()
                    }
                }
            } else {
                await closeChat()
            }
        } catch {
            guard token == loadToken else { return }
            app.show(error)
        }
    }

    /// The account changed: the chat of the old account is closed and the
    /// new one is opened.
    func accountChanged() async {
        await closeChat()
        lines.removeAll()
        poll = nil
        await load()
    }

    /// Loads the live state; a new account closes the chat first.
    func refresh(account generation: Int) async {
        if generation != account {
            account = generation
            await accountChanged()
        } else {
            await load()
        }
    }

    /// Reads only whether a show runs, for the dot in the navigation, and
    /// keeps the background chat going; it stays quiet on errors, the Live
    /// screen reports them.
    func checkStatus() async {
        guard !isLoading else { return }
        do {
            try await app.ensureSession()
            info = try await app.services.api.liveActive()
        } catch {
            // The next round tries again.
        }
        await syncChat()
    }

    /// A Live screen shows. A close that waits for the last screen is off.
    func screenAppeared() {
        screens += 1
        closeTask?.cancel()
        closeTask = nil
    }

    /// A Live screen went. The chat closes a moment later when no screen
    /// came back; a screen that is only rebuilt keeps its chat. With the
    /// chat notifications on it stays for the background.
    func screenDisappeared() {
        screens = max(0, screens - 1)
        guard screens == 0 else { return }
        closeTask?.cancel()
        closeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard let self, !Task.isCancelled, self.screens == 0 else { return }
            self.closeTask = nil
            guard !self.chatWanted else { return }
            await self.close()
        }
    }

    /// Opens the chat when the page wants it and no connect runs or waits.
    /// The screen calls it every few seconds, so a connect that was cut off
    /// on its way never leaves the chat hanging.
    func ensureChat() async {
        guard screens > 0 else { return }
        await syncChat()
    }

    /// Closes the chat; the screen calls it when it is left (Go
    /// `closeChat`).
    func close() async {
        retryTask?.cancel()
        retryTask = nil
        await closeChat()
    }

    // MARK: The chat

    /// Connects to the chat of the show (Go `OpenChat`).
    private func startChat() async {
        startsInFlight += 1
        defer { startsInFlight -= 1 }
        await closeChat()
        chatGeneration += 1
        let token = chatGeneration
        let api = app.services.api
        // An expired login gives no chat token; renew it first.
        try? await app.ensureSession()
        guard token == chatGeneration else { return }
        do {
            let opened = try await ChatSession.open(tokenProvider: { try await api.chatToken().jwt })
            // A start or a close happened meanwhile; this connection has no
            // owner any more.
            guard token == chatGeneration, session == nil else {
                await opened.close()
                return
            }
            session = opened
            // The chat name of the account is known from the token, so the
            // own picture shows from the first message on.
            if !opened.username.isEmpty {
                selfName = opened.username
                loadAvatar(named: opened.username)
            }
            isChatConnected = true
            chatStatus = "Chat verbunden"
            retryCount = 0
            sessionTask = Task { [weak self] in
                for await event in opened.events {
                    guard let self else { return }
                    self.handle(event)
                }
                // The connection ended without a close of the app: try again.
                guard let self, !Task.isCancelled, token == self.chatGeneration else { return }
                self.isChatConnected = false
                self.session = nil
                self.scheduleReconnect()
            }
        } catch {
            guard token == chatGeneration else { return }
            isChatConnected = false
            chatStatus = error.localizedDescription
            // Only the first failure in a row is worth a line in the chat.
            if retryCount == 0 {
                appendSystem("Chat nicht erreichbar: \(error.localizedDescription). Neuer Versuch läuft …")
            }
            scheduleReconnect()
        }
    }

    /// Connects the chat again after a wait that grows with every failure
    /// (2, 4, 8 … up to 30 seconds), while the screen wants it.
    private func scheduleReconnect() {
        guard chatWanted, retryTask == nil else { return }
        let delay = min(pow(2, Double(retryCount + 1)), 30)
        retryCount += 1
        retryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard let self, !Task.isCancelled else { return }
            self.retryTask = nil
            guard self.chatWanted, !self.isChatConnected else { return }
            await self.startChat()
        }
    }

    /// A chat that says it is cut off gets some seconds for its own
    /// reconnect; then it is opened anew.
    private func watchDisconnect() {
        let token = chatGeneration
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(10))
            guard let self, token == self.chatGeneration, self.chatWanted, !self.isChatConnected else { return }
            await self.startChat()
        }
    }

    /// Disconnects the chat (Go `CloseChat`).
    func closeChat() async {
        chatGeneration += 1
        let token = chatGeneration
        sessionTask?.cancel()
        let session = self.session
        self.session = nil
        isChatConnected = false
        chatStatus = ""
        chatPeople = ""
        if let session {
            await session.close()
        }
        // Only now: a start that ran meanwhile owns the task.
        if token == chatGeneration { sessionTask = nil }
    }

    /// Takes over the events of the chat (Go `forwardChat`).
    private func handle(_ event: ChatEvent) {
        switch event {
        case .message(let message):
            append(message)
            if shouldNotify(mention: message) { notifyMention(message) }
        case .history(let messages):
            for message in messages { append(message) }
        case .status(let text):
            chatStatus = text
            if text.hasSuffix(" im Chat") { chatPeople = text }
            if text == "Chat getrennt" {
                isChatConnected = false
                watchDisconnect()
            }
            if text == "Chat verbunden" { isChatConnected = true }
        case .error(let error):
            appendSystem(error.localizedDescription)
            // The socket gave up its own reconnects: open a new chat.
            if error == .connectionLost {
                isChatConnected = false
                scheduleReconnect()
            }
        case .reactions(let states, let emojis):
            applyReactions(states, emojis: emojis)
        case .reactionChanged(let update):
            applyReactionChange(update)
        case .poll(let poll):
            applyPoll(poll)
        case .pollRemoved:
            self.poll = nil
        case .pollVoted:
            markVoted()
        }
    }

    /// Adds a message of the chat (Go `applyEvent` for `EventChat`).
    private func append(_ message: ChatMessage) {
        if message.isSelf, !message.from.isEmpty, message.from != "Du" {
            selfName = message.from
            loadAvatar(named: message.from)
        }
        let line = LiveChatLine(id: message.id, from: message.from, text: message.text,
                                time: message.time, isSelf: message.isSelf, isAdmin: message.isAdmin,
                                replyTo: message.replyTo)
        // The echo of the server replaces the pending line.
        if message.isSelf, LiveChatLogic.replacePending(with: line, in: &lines, now: Date()) {
            return
        }
        add(line)
        loadAvatar(for: line)
    }

    /// Adds a line to the chat and counts it.
    private func add(_ newLine: LiveChatLine) {
        LiveChatLogic.append(newLine, to: &lines)
        receivedLines += 1
    }

    /// Adds a note of the program to the chat.
    private func appendSystem(_ text: String) {
        add(LiveChatLine(text: text, isSystem: true))
    }

    /// Adds a message of the chat transcript of a replay; it cannot be
    /// answered.
    private func appendReplayLine(_ line: ReplayChatLine) {
        var chat = LiveChatLine(from: line.from, text: line.text, isReplay: true)
        if line.unix > 0 {
            chat.time = Date(timeIntervalSince1970: TimeInterval(line.unix))
        }
        add(chat)
        loadAvatar(for: chat)
    }

    // MARK: Notifications

    /// Whether a chat notification may pop up: only with the setting on, and
    /// not while the reader has the Live page in front, where the chat is
    /// on screen anyway.
    private var shouldNotifyChat: Bool {
        guard app.settings.chatNotificationsOn else { return false }
        return !(screens > 0 && NSApp.isActive)
    }

    /// Whether a live message mentions the account.
    private func shouldNotify(mention message: ChatMessage) -> Bool {
        guard shouldNotifyChat, !message.isSelf, !message.isPinned, !selfName.isEmpty else { return false }
        return ChatNotifications.mentions(message.text, name: selfName)
    }

    /// Announces a mention of the account.
    private func notifyMention(_ message: ChatMessage) {
        notify?("Im Chat erwähnt", ChatNotifications.mentionBody(from: message.from, text: message.text))
    }

    /// Announces a reaction of someone else on an own message.
    private func notifyReaction(_ update: ChatReactionUpdate, line: LiveChatLine) {
        notify?("Reaktion auf deine Nachricht",
                ChatNotifications.reactionBody(actor: update.actor,
                                               emoji: reactionEmoji(update.emoji),
                                               text: line.text))
    }

    // MARK: The composer

    /// Sends the text of the composer (Go `sendChat`).
    func send() {
        guard let outgoing = LiveChatLogic.outgoing(composerText, toStudio: sendToStudio) else { return }
        guard isChatConnected, let session else {
            chatStatus = "Der Chat ist nicht verbunden."
            return
        }
        if LiveChatLogic.characterCount(outgoing.text) > LiveChatLogic.messageLimit {
            app.show("Nachricht zu lang (max. \(LiveChatLogic.messageLimit) Zeichen).", error: true)
            return
        }
        composerText = ""
        let target = replyTarget
        replyTarget = nil
        if outgoing.isStudio {
            add(LiveChatLine(from: "Du", text: outgoing.text, time: Date(),
                                              isSelf: true, isStudio: true))
            Task { await sendStudio(outgoing.text, session: session) }
            return
        }
        let replyTo = target?.id ?? ""
        let localID = UUID().uuidString
        var pending = LiveChatLine(from: "Du", text: outgoing.text, time: Date(),
                                   isSelf: true, isPending: true, replyTo: replyTo)
        pending.localID = localID
        add(pending)
        Task { await sendMessage(outgoing.text, replyTo: replyTo, localID: localID, session: session) }
    }

    /// Writes a message to the chat of the room (Go `SendChat`).
    private func sendMessage(_ text: String, replyTo: String, localID: String, session: ChatSession) async {
        do {
            if replyTo.isEmpty {
                try await session.send(text)
            } else {
                try await session.sendReply(text, replyTo: replyTo)
            }
            markSent(localID)
        } catch {
            removePending(localID)
            appendSystem("Nachricht nicht gesendet: \(error.localizedDescription)")
        }
    }

    /// Writes a message to the studio of the show (Go `SendStudio`).
    private func sendStudio(_ text: String, session: ChatSession) async {
        do {
            try await session.sendHost(text)
        } catch {
            appendSystem("Nachricht nicht gesendet: \(error.localizedDescription)")
        }
    }

    /// Answers a message of the chat (Go `ReplyChat`).
    func startReply(to line: LiveChatLine) {
        guard isChatConnected else {
            app.show("Antworten geht nur im verbundenen Chat.", error: true)
            return
        }
        replyTarget = line
        selectedID = nil
    }

    /// Drops the answer that is open.
    func cancelReply() {
        replyTarget = nil
    }

    /// The server took the message: its line no longer looks pending,
    /// whether or not the echo found it.
    private func markSent(_ localID: String) {
        guard let index = lines.lastIndex(where: { $0.localID == localID }) else { return }
        lines[index].isPending = false
    }

    /// The line of a message that could not be sent goes.
    private func removePending(_ localID: String) {
        if let index = lines.lastIndex(where: { $0.localID == localID && $0.id.isEmpty }) {
            lines.remove(at: index)
        }
    }

    // MARK: Reactions

    /// Sets or takes back a reaction of the account (Go `toggleReaction`).
    func toggleReaction(id: String, key: String) {
        guard let index = lines.firstIndex(where: { $0.id == id }) else {
            app.show("Nachricht nicht mehr verfügbar.", error: true)
            return
        }
        if lines[index].isSelf {
            app.show("Auf eigene Nachrichten kann man nicht reagieren.", error: true)
            return
        }
        guard isChatConnected, let session else {
            app.show("Reagieren geht nur im verbundenen Chat.", error: true)
            return
        }
        let active = !lines[index].mine.contains(key)
        LiveChatLogic.adjustReaction(&lines[index], key: key, active: active)
        Task {
            do {
                try await session.react(messageID: id, emoji: key, active: active)
            } catch let error as LiveError {
                switch error {
                case .reactionUnchanged:
                    // The server decided otherwise: the state is read again.
                    await refreshReactions([id], session: session)
                default:
                    revert(id: id, key: key, active: active)
                    app.show(error.localizedDescription, error: true)
                }
            } catch {
                revert(id: id, key: key, active: active)
                app.show("Reaktion fehlgeschlagen: \(error.localizedDescription)", error: true)
            }
        }
    }

    /// Takes the reaction of the account back after a refusal.
    private func revert(id: String, key: String, active: Bool) {
        guard let index = lines.firstIndex(where: { $0.id == id }) else { return }
        LiveChatLogic.adjustReaction(&lines[index], key: key, active: !active)
    }

    /// Reads the reactions of messages again (Go `refreshReactions`).
    private func refreshReactions(_ ids: [String], session: ChatSession) async {
        do {
            let (states, emojis) = try await session.reactionStates(messageIDs: ids)
            applyReactions(states, emojis: emojis)
        } catch {
            app.show(error)
        }
    }

    /// Takes over the state of the reactions of the server (Go
    /// `applyReactionStates`).
    private func applyReactions(_ states: [ChatReactionState], emojis: [String: String]) {
        for (key, emoji) in emojis where ChatReactions.emojis[key] == nil {
            let trimmed = emoji.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { reactionEmojis[key] = trimmed }
        }
        let converted = states.map {
            LiveReactionState(messageID: $0.messageID, cursor: $0.cursor, counts: $0.counts, mine: $0.mine)
        }
        LiveChatLogic.applyReactionStates(converted, to: &lines)
    }

    /// Takes over one change of the reactions (Go `applyReactionChange`).
    private func applyReactionChange(_ update: ChatReactionUpdate) {
        let before = lines.first { $0.id == update.messageID }
        let applied = LiveChatLogic.applyReactionChange(
            LiveReactionChange(messageID: update.messageID, cursor: update.cursor, emoji: update.emoji,
                               count: update.count, active: update.active, isSelf: update.isSelf),
            to: &lines)
        // Someone else reacted to an own message while the chat is not in
        // front: tell the reader.
        if applied, update.active, !update.isSelf, let before, before.isSelf, shouldNotifyChat {
            notifyReaction(update, line: before)
        }
    }

    /// The emoji of a reaction key (Go `reactionEmoji`).
    func reactionEmoji(_ key: String) -> String {
        LiveChatLogic.reactionEmoji(key, known: reactionEmojis)
    }

    /// The name of a reaction in German (Go `chat.ReactionNames`).
    func reactionName(_ key: String) -> String {
        ChatReactions.names[key] ?? key
    }

    // MARK: The voting

    /// Takes over a voting of the server (Go `applyPoll`).
    private func applyPoll(_ incoming: ChatPoll) {
        var next = LivePoll()
        next.question = incoming.question
        next.answers = incoming.answers
        next.results = incoming.results
        next.pollID = incoming.pollID
        next.secret = incoming.secret
        next.resultsVisible = incoming.resultsVisible
        next.submissions = incoming.submissions
        next.closed = incoming.closed
        next = LivePoll.merged(next, current: poll)
        // The server does not tell whether the account voted; the app
        // remembers it, so the choice outlasts a reconnect or a restart.
        if !next.hasVoted, let stored = LivePollVotes.choice(for: next) {
            if stored >= 0 { next.choice = stored } else { next.votedElsewhere = true }
        }
        poll = next
    }

    /// The server says the account (or its network) already voted. The
    /// answer stays unknown unless this app gave it.
    private func markVoted() {
        guard var current = poll, !current.hasVoted else { return }
        current.votedElsewhere = true
        poll = current
        LivePollVotes.remember(-1, for: current)
    }

    /// Answers the voting of the show (Go `votePoll`). A vote is final: the
    /// server does not take a second one, so a voting that has the choice of
    /// the account takes no more.
    func vote(answer: Int) {
        guard let poll, !poll.answers.isEmpty, !poll.hasVoted else { return }
        guard answer >= 0, answer < poll.answers.count else { return }
        if poll.closed {
            app.show("Die Abstimmung ist beendet.", error: true)
            return
        }
        guard isChatConnected, let session else {
            app.show("Abstimmung fehlgeschlagen: Der Chat ist nicht verbunden.", error: true)
            return
        }
        self.poll?.choice = answer
        Task {
            do {
                try await session.vote(answer: answer)
                LivePollVotes.remember(answer, for: poll)
                app.show("Deine Stimme ist gezählt.")
            } catch let error as LiveError where error == .voteRejected {
                // The server counts one vote per network; a refused vote
                // means one was given there already, so the voting stays
                // locked like in the web chat.
                self.poll?.choice = -1
                self.poll?.votedElsewhere = true
                if let current = self.poll { LivePollVotes.remember(-1, for: current) }
                app.show("Stimme nicht angenommen. Vielleicht hat in deinem Netzwerk schon jemand abgestimmt.",
                         error: true)
            } catch {
                self.poll?.choice = -1
                app.show("Abstimmung fehlgeschlagen: \(error.localizedDescription)", error: true)
            }
        }
    }

    // MARK: Playing

    /// Plays the running stream in the Live screen (Go `playLive("live")`).
    func watchLive() {
        guard let info else { return }
        Task { await playLive(info, mode: .live) }
    }

    /// Plays the replay of the last show in the Live screen (Go
    /// `playLive("replay")`).
    func watchReplay() {
        guard let info else { return }
        Task { await playLive(info, mode: .replay) }
    }

    /// Hands the live stream to the player of the app; the picture stays in
    /// the Live screen.
    private func playLive(_ info: LivestreamInfo, mode: LivePlaybackMode) async {
        guard let player = app.playback as? any LivePlaybackStarting else {
            app.show("Die Wiedergabe ist nicht verfügbar.", error: true)
            return
        }
        if mode == .replay {
            await closeChat()
            lines.removeAll()
            app.show("Chat-Mitschnitt wird geladen …")
        }
        player.setReplayChatHandler { [weak self] line in
            self?.appendReplayLine(line)
        }
        await player.playLive(info, mode: mode, inline: true)
    }

    // MARK: The pictures of the senders

    /// Loads the picture of a sender (Go `ChatAvatar`).
    private func loadAvatar(for line: LiveChatLine) {
        guard !line.isSystem, !line.isReplay else { return }
        // A line written here says "Du"; without the name of the account
        // there is no picture to ask for yet.
        if line.isSelf, selfName.isEmpty { return }
        loadAvatar(named: line.isSelf ? selfName : line.from)
    }

    /// Loads the picture of a chat name once.
    private func loadAvatar(named name: String) {
        guard !name.isEmpty, avatars[name] == nil else { return }
        Task {
            guard let data = await avatarLoader.data(for: name) else { return }
            avatars[name] = data
        }
    }
}
