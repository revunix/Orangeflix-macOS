import AppKit
import SwiftUI

/// The messages of one sender that follow each other (Go
/// `chatMessageLines`), laid out like a messenger on the Mac: the picture in
/// its own column, the name and the time on top, the messages under the
/// name. The pointer brings up reply, reactions and copy above the row
/// without moving anything; a quote jumps to the answered message.
struct LiveChatBubble: View {
    @Bindable var model: LiveModel
    /// The messages of the run, the first one carries the head.
    let lines: [LiveChatLine]
    /// Scrolls the list to the message with this id.
    var onFocus: (String) -> Void = { _ in }

    @State private var hovering = false
    @Environment(\.liveChatStyle) private var style
    /// While the list scrolls, rows passing under the pointer stay calm.
    @Environment(\.liveChatScrolling) private var scrolling

    /// The size of the picture of the sender.
    static let avatarSize: CGFloat = 28

    /// A font of the chat in the size of the settings.
    private func font(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size * style.scale, weight: weight)
    }

    private var pointed: Bool { hovering && !scrolling }
    private var showsActions: Bool { pointed || lines.contains(where: isSelected) }
    private var isOwn: Bool { lines.first?.isSelf == true }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if style.avatars, let first = lines.first {
                avatar(first)
            }
            VStack(alignment: .leading, spacing: 3) {
                head
                ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                    message(line)
                        .id(Self.anchor(line, index: index))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, Space.s)
        .padding(.vertical, 6)
        // Only the fill fades under the pointer; the animation stays on it,
        // so the text and the reactions of the row never move with it.
        .background {
            RoundedRectangle(cornerRadius: Radius.l, style: .continuous)
                .fill(rowFill)
                .animation(.easeOut(duration: 0.12), value: pointed)
        }
        // The actions float over the upper edge of the row; nothing moves
        // when they come. They only fade: the glass does not scale in.
        .overlay(alignment: .topTrailing) {
            ZStack(alignment: .topTrailing) {
                if showsActions, let target = actionTarget {
                    LiveChatActionBar(model: model, line: target)
                        .offset(y: -10)
                        .padding(.trailing, Space.s)
                        .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.12), value: showsActions)
        }
        .zIndex(showsActions ? 1 : 0)
        .contentShape(Rectangle())
        .onHover { inside in
            if hovering != inside { hovering = inside }
        }
    }

    /// The quiet fill of the row: a tint for one's own messages, a shade
    /// under the pointer.
    private var rowFill: Color {
        if isOwn { return Palette.accent.opacity(pointed ? 0.14 : 0.09) }
        return pointed ? Palette.textPrimary.opacity(0.05) : .clear
    }

    /// One message: the quote it answers, the text and its reactions.
    private func message(_ line: LiveChatLine) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            if !line.replyTo.isEmpty {
                replyQuote(line)
            }
            Text(line.text)
                .font(font(13))
                .foregroundStyle(line.isPending ? Palette.textSecondary : Palette.textPrimary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            if !LiveChatLogic.reactionOrder(counts: line.reactions).isEmpty {
                reactionChips(line)
            }
        }
        .background {
            // The chosen message is marked; the mark reaches a little past
            // the text, so the words keep their line.
            RoundedRectangle(cornerRadius: Radius.m, style: .continuous)
                .fill(isSelected(line) ? Palette.accent.opacity(0.16) : .clear)
                .padding(.horizontal, -6)
                .padding(.vertical, -2)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            model.selectedID = line.id.isEmpty ? nil : line.id
        }
        .contextMenu {
            menu(for: line)
        }
    }

    /// The message the action bar talks about: the chosen one, else the last.
    private var actionTarget: LiveChatLine? {
        if let selected = lines.first(where: { isSelected($0) }) { return selected }
        return lines.last
    }

    /// The head of the run: the name of the sender, its marks and the time.
    private var head: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            if let line = lines.first {
                if line.isAdmin {
                    Image(systemName: "star.fill")
                        .font(font(9, .semibold))
                        .foregroundStyle(Palette.accent)
                }
                Text(LiveChatLogic.displayName(line))
                    .font(font(12, .semibold))
                    .foregroundStyle(nameColor(line))
                    .lineLimit(1)
                if line.isStudio {
                    tag("An das Studio", color: Palette.accentText, fill: Palette.accent.opacity(0.18))
                }
                if line.isReplay {
                    tag("Mitschnitt", color: Palette.textSecondary, fill: Palette.textPrimary.opacity(0.08))
                }
                if style.times {
                    Text(displayTime(line))
                        .font(font(11).monospacedDigit())
                        .foregroundStyle(Palette.textTertiary)
                }
            }
            Spacer(minLength: 0)
        }
    }

    /// A small mark beside the name.
    private func tag(_ text: String, color: Color, fill: Color) -> some View {
        Text(text)
            .font(font(10, .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(fill, in: Capsule())
    }

    /// The menu of a message (Go `chatMenu`).
    @ViewBuilder
    private func menu(for line: LiveChatLine) -> some View {
        if model.isChatConnected, !line.isReplay, !line.id.isEmpty {
            Button("Antworten") { model.startReply(to: line) }
            if !line.isSelf {
                ForEach(ChatReactions.keys, id: \.self) { key in
                    Button("\(model.reactionEmoji(key)) \(model.reactionName(key))") {
                        model.toggleReaction(id: line.id, key: key)
                    }
                }
            }
        }
        Button("Text kopieren") { AppFormat.copy(line.text) }
    }

    /// The quote of the answered message. A click jumps to it.
    private func replyQuote(_ line: LiveChatLine) -> some View {
        let target = model.lines.first { $0.id == line.replyTo }
        return Button {
            guard !line.replyTo.isEmpty else { return }
            onFocus(line.replyTo)
        } label: {
            HStack(spacing: Space.s) {
                Capsule()
                    .fill(Palette.accent)
                    .frame(width: 3)
                VStack(alignment: .leading, spacing: 1) {
                    if let target {
                        Text(LiveChatLogic.displayName(target))
                            .font(font(11, .medium))
                            .foregroundStyle(Palette.accentText)
                        Text(target.text)
                            .font(font(11))
                            .foregroundStyle(Palette.textSecondary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    } else {
                        Text("Antwort auf eine ältere Nachricht")
                            .font(font(11))
                            .foregroundStyle(Palette.textTertiary)
                    }
                }
                Spacer(minLength: 0)
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(.vertical, 5)
            .padding(.leading, 5)
            .padding(.trailing, Space.s)
            .background(Palette.textPrimary.opacity(0.05),
                        in: RoundedRectangle(cornerRadius: Radius.m, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Zur beantworteten Nachricht")
    }

    /// The reactions below a message (Go `reactionChips`).
    private func reactionChips(_ line: LiveChatLine) -> some View {
        HStack(spacing: Space.xs) {
            ForEach(LiveChatLogic.reactionOrder(counts: line.reactions), id: \.self) { key in
                let count = line.reactions[key] ?? 0
                let mine = line.mine.contains(key)
                Button {
                    model.toggleReaction(id: line.id, key: key)
                } label: {
                    HStack(spacing: 3) {
                        Text(model.reactionEmoji(key))
                            .font(font(11))
                        Text("\(count)")
                            .font(font(11).monospacedDigit())
                            .foregroundStyle(mine ? Palette.accentText : Palette.textSecondary)
                    }
                    .padding(.horizontal, 7)
                    .frame(height: 20 * style.scale)
                    .background(mine ? Palette.accent.opacity(0.18) : Palette.textPrimary.opacity(0.06),
                                in: Capsule())
                    .overlay {
                        Capsule().strokeBorder(mine ? Palette.accent.opacity(0.55) : Palette.divider, lineWidth: 1)
                    }
                }
                .buttonStyle(.plain)
                .disabled(!model.isChatConnected || line.isSelf || line.isReplay || line.id.isEmpty)
                .help(model.reactionName(key))
            }
        }
    }

    /// The picture of the sender; without one its initial on its colour.
    @ViewBuilder
    private func avatar(_ line: LiveChatLine) -> some View {
        let name = line.isSelf ? (model.selfName.isEmpty ? line.from : model.selfName) : line.from
        Group {
            if let data = model.avatars[name], let image = NSImage(data: data) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Circle()
                    .fill(LiveAvatarStyle.color(LiveAvatarStyle.colorHex(for: name)))
                    .overlay(
                        Text(String(name.prefix(1)).uppercased())
                            .font(font(12, .semibold))
                            .foregroundStyle(.black.opacity(0.6)))
            }
        }
        .frame(width: Self.avatarSize * style.scale, height: Self.avatarSize * style.scale)
        .clipShape(Circle())
        .overlay { Circle().strokeBorder(Palette.textPrimary.opacity(0.08), lineWidth: 1) }
        // The picture stands on the line of the name.
        .padding(.top, 1)
    }

    /// The colour of the name of a sender (Go `chatNameStyle`).
    private func nameColor(_ line: LiveChatLine) -> Color {
        if line.isSelf { return Palette.accentText }
        if line.isAdmin || line.isStudio { return Palette.accent }
        return Palette.textPrimary
    }

    /// Whether the message is the chosen one.
    private func isSelected(_ line: LiveChatLine) -> Bool {
        guard !line.id.isEmpty else { return false }
        return model.selectedID == line.id
    }

    /// The time of a message (Go `chatClock`).
    private func displayTime(_ line: LiveChatLine) -> String {
        if line.isPending { return "…" }
        guard let time = line.time else { return "" }
        return LiveChatBubble.clock.string(from: time)
    }

    /// The id the list scrolls to. A pending line has none from the server.
    static func anchor(_ line: LiveChatLine, index: Int) -> String {
        if !line.id.isEmpty { return line.id }
        let stamp = line.time?.timeIntervalSince1970 ?? 0
        return "local-\(line.from)-\(stamp)-\(line.text.hashValue)-\(index)"
    }

    private static let clock: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
}

/// Reply, the four reactions of the web chat, and copy, as a small glass bar
/// over a message (Go `chatMenu`).
struct LiveChatActionBar: View {
    @Bindable var model: LiveModel
    let line: LiveChatLine

    /// Answers and reactions need a connected chat and a server id.
    private var interactive: Bool {
        model.isChatConnected && !line.isReplay && !line.id.isEmpty && !line.isSystem
    }

    var body: some View {
        HStack(spacing: 0) {
            if interactive {
                symbolButton("arrowshape.turn.up.left", help: "Antworten") {
                    model.startReply(to: line)
                }
                if !line.isSelf {
                    separator
                    ForEach(ChatReactions.keys, id: \.self) { key in
                        ActionBarButton(help: model.reactionName(key), isOn: line.mine.contains(key)) {
                            model.toggleReaction(id: line.id, key: key)
                        } label: {
                            Text(model.reactionEmoji(key))
                                .font(.system(size: 13))
                        }
                    }
                }
                separator
            }
            symbolButton("doc.on.doc", help: "Text kopieren") {
                AppFormat.copy(line.text)
            }
        }
        .padding(2)
        // No scale-in of the glass: it would play on top of the fade and
        // let the bar jitter when the pointer moves from row to row.
        .glassPlate(in: Capsule(), tint: .black.opacity(0.45), interactive: true, quietAppear: true)
        .shadow(color: .black.opacity(0.18), radius: 6, y: 2)
    }

    private var separator: some View {
        Rectangle()
            .fill(Palette.divider)
            .frame(width: 1, height: 14)
            .padding(.horizontal, 2)
    }

    private func symbolButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        ActionBarButton(help: help, isOn: false, action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Palette.textPrimary)
        }
    }
}

/// One button of the action bar, with a soft shade under the pointer.
struct ActionBarButton<Label: View>: View {
    let help: String
    let isOn: Bool
    let action: () -> Void
    @ViewBuilder let label: () -> Label

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            label()
                .frame(width: 26, height: 24)
                .background {
                    Capsule().fill(isOn ? Palette.accent.opacity(0.35)
                                   : hovering ? Palette.textPrimary.opacity(0.1) : .clear)
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
    }
}

/// The field to write a message (Go `chatComposer`): one rounded field with
/// the emoji on the left and the send button on the right; under it where
/// the message goes and how long it is.
struct LiveComposer: View {
    /// The model of the Live screen.
    @Bindable var model: LiveModel

    @FocusState private var focused: Bool
    /// Whether the row of quick emoji stands above the field.
    @State private var showsQuickEmojis = false

    /// The height of the round buttons inside the field.
    private static let control: CGFloat = 26

    private var count: Int { LiveChatLogic.characterCount(model.composerText) }
    private var canSend: Bool {
        model.isChatConnected && LiveChatLogic.outgoing(model.composerText, toStudio: model.sendToStudio) != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            if let target = model.replyTarget {
                replyBanner(target)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            if showsQuickEmojis {
                quickEmojis
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            field
            footer
        }
        .animation(.easeOut(duration: 0.15), value: model.replyTarget?.id)
        .animation(.easeOut(duration: 0.15), value: showsQuickEmojis)
    }

    /// The message that is answered, with the way back.
    private func replyBanner(_ target: LiveChatLine) -> some View {
        HStack(spacing: Space.s) {
            Capsule()
                .fill(Palette.accent)
                .frame(width: 3)
            VStack(alignment: .leading, spacing: 1) {
                Text("Antwort an \(LiveChatLogic.displayName(target))")
                    .font(AppFont.captionMedium)
                    .foregroundStyle(Palette.accentText)
                Text(target.text)
                    .font(AppFont.caption)
                    .foregroundStyle(Palette.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Button {
                model.cancelReply()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Palette.textSecondary)
                    .frame(width: 20, height: 20)
                    .background(Palette.textPrimary.opacity(0.08), in: Circle())
            }
            .buttonStyle(.plain)
            .help("Antwort abbrechen")
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.vertical, 6)
        .padding(.leading, 6)
        .padding(.trailing, Space.s)
        .background(Palette.textPrimary.opacity(0.05),
                    in: RoundedRectangle(cornerRadius: Radius.l, style: .continuous))
    }

    /// The field: emoji, text, send.
    private var field: some View {
        HStack(alignment: .bottom, spacing: Space.xs) {
            Button {
                withAnimation(.easeOut(duration: 0.15)) { showsQuickEmojis.toggle() }
            } label: {
                Image(systemName: showsQuickEmojis ? "face.smiling.fill" : "face.smiling")
                    .font(.system(size: 15))
                    .foregroundStyle(Palette.textSecondary)
                    .frame(width: Self.control, height: Self.control)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Schnell-Emojis")

            TextField(model.sendToStudio ? "Nachricht an das Studio …" : "Nachricht schreiben …",
                      text: $model.composerText, axis: .vertical)
                .textFieldStyle(.plain)
                .font(AppFont.body)
                .foregroundStyle(Palette.textPrimary)
                .lineLimit(1...5)
                .focused($focused)
                .padding(.vertical, 5)
                .onSubmit { model.send() }

            Button {
                model.send()
            } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(canSend ? Color.white : Palette.textTertiary)
                    .frame(width: Self.control, height: Self.control)
                    .background(canSend ? Palette.accent : Palette.textPrimary.opacity(0.08), in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
            .keyboardShortcut(.return, modifiers: .command)
            .help(model.sendToStudio ? "An das Studio senden (↩)" : "Senden (↩)")
            .animation(.easeOut(duration: 0.15), value: canSend)
        }
        .padding(4)
        .background(Palette.textPrimary.opacity(0.06),
                    in: RoundedRectangle(cornerRadius: 17, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .strokeBorder(focused ? Palette.accent.opacity(0.55) : Palette.divider, lineWidth: 1)
        }
        .animation(.easeOut(duration: 0.15), value: focused)
    }

    /// Where the message goes, and its length once there is text.
    private var footer: some View {
        HStack(spacing: Space.s) {
            RecipientPill(toStudio: $model.sendToStudio)
                .disabled(model.replyTarget != nil)
                .opacity(model.replyTarget != nil ? 0.5 : 1)
            if model.sendToStudio {
                Text("Nur das Team liest mit")
                    .font(AppFont.caption)
                    .foregroundStyle(Palette.textTertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if count > 0 {
                Text("\(count)/\(LiveChatLogic.messageLimit)")
                    .font(AppFont.digits)
                    .foregroundStyle(counterColor)
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, 2)
        .animation(.easeOut(duration: 0.15), value: count > 0)
    }

    /// The quick emoji above the field; the last button opens the full picker.
    private var quickEmojis: some View {
        HStack(spacing: 2) {
            ForEach(LiveChatLogic.quickEmojis, id: \.self) { emoji in
                QuickEmojiButton(emoji: emoji) {
                    model.composerText += emoji
                    focused = true
                }
            }
            Button {
                showEmojiPicker()
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Palette.textSecondary)
                    .frame(width: 30, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Alle Emojis (⌃⌘Leertaste)")
        }
        .padding(.horizontal, Space.s)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.textPrimary.opacity(0.06), in: Capsule())
    }

    /// Opens the emoji picker of macOS at the field. The picker writes into
    /// the field that has the focus, so the field takes it first.
    private func showEmojiPicker() {
        focused = true
        DispatchQueue.main.async {
            NSApp.orderFrontCharacterPalette(nil)
        }
    }

    /// The colour of the counter of the composer (Go `composerField`).
    private var counterColor: Color {
        switch LiveChatLogic.counterState(for: count) {
        case .normal: return Palette.textTertiary
        case .warning: return Palette.warning
        case .tooLong: return Palette.danger
        }
    }
}

/// One emoji of the quick row above the composer.
private struct QuickEmojiButton: View {
    let emoji: String
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(emoji)
                .font(.system(size: 17))
                .frame(width: 30, height: 28)
                .background(hovering ? Palette.textPrimary.opacity(0.1) : .clear,
                            in: RoundedRectangle(cornerRadius: Radius.m, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// Where a message goes: the chat or only the studio. A small pill like the
/// navigation of the toolbar, its capsule slides to the choice.
struct RecipientPill: View {
    @Binding var toStudio: Bool

    @Namespace private var namespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 0) {
            segment("Chat", value: false, help: "An alle im Chat schreiben")
            segment("Studio", value: true, help: "Nur an das Studio schreiben; das Team liest mit")
        }
        .padding(2)
        .background(Palette.textPrimary.opacity(0.06), in: Capsule())
        .overlay { Capsule().strokeBorder(Palette.divider, lineWidth: 1) }
        .fixedSize()
    }

    private func segment(_ title: String, value: Bool, help: String) -> some View {
        let isOn = toStudio == value
        return Button {
            guard !isOn else { return }
            if reduceMotion {
                toStudio = value
            } else {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.78)) { toStudio = value }
            }
        } label: {
            // The bold word holds the room, so nothing jumps when it turns.
            Text(title)
                .font(AppFont.captionMedium.weight(.semibold))
                .hidden()
                .overlay {
                    Text(title)
                        .font(isOn ? AppFont.captionMedium.weight(.semibold) : AppFont.captionMedium)
                        .foregroundStyle(isOn ? (value ? Palette.accentText : Palette.textPrimary)
                                         : Palette.textSecondary)
                }
                .padding(.horizontal, 10)
                .frame(height: 22)
                .background {
                    if isOn {
                        Capsule()
                            .fill(Palette.surface)
                            .overlay {
                                Capsule().strokeBorder(Palette.textPrimary.opacity(0.14), lineWidth: 1)
                            }
                            .matchedGeometryEffect(id: "choice", in: namespace)
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

extension LiveAvatarStyle {
    /// The colour of a hex string like "#7dd3fc".
    static func color(_ hex: String) -> Color {
        var value = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("#") { value.removeFirst() }
        guard value.count == 6, let number = UInt32(value, radix: 16) else { return .gray }
        return Color(.sRGB,
                     red: Double((number >> 16) & 0xff) / 255,
                     green: Double((number >> 8) & 0xff) / 255,
                     blue: Double(number & 0xff) / 255,
                     opacity: 1)
    }
}

/// A button in the glass capsule above the picture: ink of the page, a soft
/// fill under the pointer. `active` marks a mode that is on.
struct LiveHeaderButtonStyle: ButtonStyle {
    var active = false

    func makeBody(configuration: Configuration) -> some View {
        Face(configuration: configuration, active: active)
    }

    private struct Face: View {
        let configuration: Configuration
        let active: Bool
        @State private var hovering = false

        var body: some View {
            configuration.label
                .labelStyle(.titleAndIcon)
                .font(AppFont.subheading)
                .foregroundStyle(active ? Palette.accentText : Palette.textPrimary)
                .padding(.horizontal, Space.m)
                .padding(.vertical, 7)
                .background {
                    Capsule().fill(Palette.textPrimary.opacity(configuration.isPressed ? 0.14 : hovering ? 0.08 : 0))
                }
                .contentShape(Capsule())
                .onHover { hovering = $0 }
                .animation(.easeOut(duration: 0.12), value: hovering)
        }
    }
}

/// How the live chat reads: the factor on its text and what a message shows
/// besides its text. Set by the settings.
struct LiveChatStyle: Equatable {
    var scale: CGFloat = 1
    var avatars = true
    var times = true
}

extension EnvironmentValues {
    @Entry var liveChatStyle = LiveChatStyle()
    /// Whether the chat list is scrolling right now.
    @Entry var liveChatScrolling = false
}


/// Where the chat stands in the Live window.
enum LiveWindowLayout: String {
    case side, below
}
