import SwiftUI

/// The popup of a running "mark as watched/unwatched" batch. It dims the
/// window and holds it until every episode is saved, so nothing else asks
/// the server in between.
struct WatchedBatchOverlay: View {
    @Environment(BrowseModel.self) private var model

    var body: some View {
        ZStack {
            if let batch = model.watchedBatch {
                Color.black.opacity(0.35)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    // Swallow clicks and scrolls while the batch runs.
                    .onTapGesture {}
                    .transition(.opacity)
                WatchedBatchCard(batch: batch)
                    .transition(.scale(scale: 0.92).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.35, bounce: 0.2), value: model.watchedBatch != nil)
    }
}

private struct WatchedBatchCard: View {
    let batch: BrowseModel.WatchedBatch

    @Environment(BrowseModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var fraction: Double {
        batch.total > 0 ? Double(batch.handled) / Double(batch.total) : 0
    }

    private var state: String { batch.watched ? "gesehen" : "ungesehen" }

    var body: some View {
        VStack(spacing: Space.m) {
            ring
                .frame(width: 84, height: 84)
                .padding(.top, Space.xs)

            VStack(spacing: Space.xxs) {
                Text(title)
                    .font(AppFont.heading)
                    .foregroundStyle(Palette.textPrimary)
                    .multilineTextAlignment(.center)
                Text(subtitle)
                    .font(AppFont.bodySmall)
                    .foregroundStyle(Palette.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .frame(minHeight: 34, alignment: .top)
                    .contentTransition(.opacity)
                    .animation(.easeOut(duration: 0.2), value: batch.current)
            }

            VStack(spacing: Space.xs) {
                ProgressView(value: fraction)
                    .progressViewStyle(.linear)
                    .tint(batch.failed > 0 ? Palette.warning : Palette.accent)
                    .animation(.easeInOut(duration: 0.4), value: fraction)
                HStack {
                    Text("\(batch.handled) von \(batch.total)")
                        .contentTransition(.numericText())
                        .animation(.snappy, value: batch.handled)
                    Spacer()
                    if batch.failed > 0 {
                        Text("\(batch.failed) fehlgeschlagen")
                            .foregroundStyle(Palette.warning)
                    }
                }
                .font(AppFont.digits)
                .foregroundStyle(Palette.textTertiary)
            }

            if batch.finished {
                if batch.failed > 0 || batch.cancelled {
                    PillButton(title: "Schließen", style: .accent) { model.dismissWatchedBatch() }
                }
            } else {
                Button("Abbrechen") { model.cancelWatchedBatch() }
                    .buttonStyle(.link)
                    .font(AppFont.caption)
                    .help("Nach der aktuellen Folge aufhören")
            }
        }
        .padding(Space.xl)
        .frame(width: 340)
        .background(Palette.surfaceRaised, in: RoundedRectangle(cornerRadius: Radius.panel, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Radius.panel, style: .continuous)
                .strokeBorder(Palette.divider)
        }
        .shadow(color: .black.opacity(0.25), radius: 24, y: 10)
        .accessibilityElement(children: .combine)
    }

    private var title: String {
        if batch.finished {
            if batch.cancelled { return "Abgebrochen" }
            if batch.failed > 0 { return "Teilweise gespeichert" }
            return batch.done == 1 ? "1 Folge als \(state) markiert" : "\(batch.done) Folgen als \(state) markiert"
        }
        return "Markiere als \(state) …"
    }

    private var subtitle: String {
        if batch.finished {
            if batch.failed > 0 { return batch.lastError ?? "Einige Folgen konnten nicht gespeichert werden." }
            if batch.cancelled { return "\(batch.done) von \(batch.total) Folgen wurden gespeichert." }
            return "Alles erledigt."
        }
        return batch.current.isEmpty ? "Bitte warten, der Server verarbeitet die Folgen." : batch.current
    }

    /// A ring that fills with the progress and turns into a check (or a
    /// warning) at the end.
    private var ring: some View {
        ZStack {
            Circle()
                .stroke(Palette.surfaceMuted, lineWidth: 6)
            Circle()
                .trim(from: 0, to: batch.finished ? 1 : max(fraction, 0.04))
                .stroke(ringColor, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.45), value: fraction)
                .animation(.easeInOut(duration: 0.45), value: batch.finished)
            if batch.finished {
                Image(systemName: endSymbol)
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(ringColor)
                    .transition(.scale(scale: 0.4).combined(with: .opacity))
                    .symbolEffect(.bounce, value: batch.finished)
            } else {
                Image(systemName: batch.watched ? "checkmark.circle" : "arrow.counterclockwise")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(Palette.accent)
                    .symbolEffect(.pulse, options: .repeating, isActive: !reduceMotion)
                    .transition(.opacity)
            }
        }
        .animation(.spring(duration: 0.4, bounce: 0.35), value: batch.finished)
    }

    private var ringColor: Color {
        if batch.finished && (batch.failed > 0 || batch.cancelled) { return Palette.warning }
        return batch.finished ? Palette.success : Palette.accent
    }

    private var endSymbol: String {
        if batch.cancelled { return "stop.fill" }
        return batch.failed > 0 ? "exclamationmark" : "checkmark"
    }
}
