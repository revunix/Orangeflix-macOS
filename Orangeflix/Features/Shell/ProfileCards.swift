import SwiftUI

// The cards of the profile page. They carry the things the account may
// store and the confirmations it has to give: a symbol, the name, a short
// text, the state and the actions.

/// One entry of the profile page: a symbol in a tinted circle, the name of
/// the thing, a short text about it and its state. The actions sit
/// underneath.
struct ProfileCard<Actions: View>: View {
    /// The symbol of the entry.
    let symbol: String
    /// The name of the thing.
    let title: String
    /// A short text about it.
    let text: String
    /// The state of the thing ("hinterlegt", "offen"); nil leaves the pill
    /// out.
    var state: String?
    /// Whether the state is a good one (green) or an open one (orange).
    var isSet = false
    /// The actions of the entry.
    @ViewBuilder var actions: Actions

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            HStack(alignment: .top, spacing: Space.m) {
                icon
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(AppFont.subheading)
                        .foregroundStyle(Palette.textPrimary)
                    Text(text)
                        .font(AppFont.caption)
                        .foregroundStyle(Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: Space.s)
                if let state {
                    BrandPill(text: state,
                              color: isSet ? Palette.success : Palette.warning,
                              background: isSet ? Palette.successSoft : Palette.warningSoft)
                }
            }
            actions
        }
        .padding(Space.m)
        .contentCard()
    }

    /// The symbol of the entry in a circle of the state colour.
    private var icon: some View {
        Image(systemName: symbol)
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(isSet ? Palette.success : Palette.textSecondary)
            .frame(width: 30, height: 30)
            .background(isSet ? Palette.successSoft : Palette.surfaceMuted, in: Circle())
    }
}

/// A notice that something is still open: the server wants a confirmation.
struct ProfileNotice: View {
    /// The symbol of the notice.
    let symbol: String
    /// The text of the notice.
    let text: String
    /// The color of the notice.
    var tint: Color = Palette.warning
    /// The background of the notice.
    var background: Color = Palette.warningSoft

    var body: some View {
        HStack(alignment: .top, spacing: Space.s) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(tint)
            Text(text)
                .font(AppFont.bodySmall)
                .foregroundStyle(Palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(Space.m)
        .background(background, in: RoundedRectangle(cornerRadius: Radius.m, style: .continuous))
    }
}
