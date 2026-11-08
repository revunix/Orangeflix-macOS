import SwiftUI

// The sheets of the profile page. They collect the optional data of the
// account; the values go to the server and are never read back.

/// The shipping address of the account.
struct AddressSheet: View {
    /// Hands the address to the caller and closes the sheet.
    let save: (AddressInput) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var street = ""
    @State private var street2 = ""
    @State private var zip = ""
    @State private var city = ""
    @State private var country = "DE"

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Text("Lieferadresse")
                .font(AppFont.displaySmall)
                .foregroundStyle(Palette.textPrimary)
            Text("Die Lieferadresse des Kontos für den Versand.")
                .font(AppFont.bodySmall)
                .foregroundStyle(Palette.textSecondary)
            fields
            HStack {
                Spacer()
                Button("Abbrechen") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Speichern", action: saveAddress)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!isComplete)
            }
        }
        .padding(Space.xl)
        .frame(minWidth: 380)
        .background(Palette.surfaceRaised)
    }

    private var fields: some View {
        VStack(spacing: Space.s) {
            TextField("Name", text: $name, prompt: Text("Name"))
            TextField("Straße und Nummer", text: $street, prompt: Text("Straße und Nummer"))
            TextField("Zusatz", text: $street2, prompt: Text("Zusatz (optional)"))
            HStack(spacing: Space.s) {
                TextField("PLZ", text: $zip, prompt: Text("PLZ"))
                TextField("Ort", text: $city, prompt: Text("Ort"))
            }
            TextField("Land", text: $country, prompt: Text("Land"))
                .onChange(of: country) { _, value in
                    country = String(value.uppercased().prefix(3))
                }
        }
        .textFieldStyle(.roundedBorder)
    }

    /// Whether the fields carry everything the server needs.
    private var isComplete: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && !street.trimmingCharacters(in: .whitespaces).isEmpty
            && !zip.trimmingCharacters(in: .whitespaces).isEmpty
            && !city.trimmingCharacters(in: .whitespaces).isEmpty
            && country.count >= 2
    }

    private func saveAddress() {
        let trimmedSecond = street2.trimmingCharacters(in: .whitespaces)
        save(AddressInput(
            name: name.trimmingCharacters(in: .whitespaces),
            address: street.trimmingCharacters(in: .whitespaces),
            address2: trimmedSecond.isEmpty ? nil : trimmedSecond,
            zip: zip.trimmingCharacters(in: .whitespaces),
            city: city.trimmingCharacters(in: .whitespaces),
            country: country.uppercased()))
        dismiss()
    }
}

/// The birthday of the account. A calendar picks the day; the year is
/// optional, so the sheet offers the day and the month on their own too.
struct BirthdaySheet: View {
    /// Hands the birthday to the caller and closes the sheet.
    let save: (BirthdayInput) -> Void

    @Environment(\.dismiss) private var dismiss

    /// The day of the month; the sheet starts on the first of the month, so
    /// only the day and the month have to be picked.
    @State private var day = 1
    /// The month; the sheet starts in the current one.
    @State private var month = Calendar.current.component(.month, from: Date())
    /// The year; it is only sent when the account wants to name it.
    @State private var year = Calendar.current.component(.year, from: Date())
    /// Whether the account wants to name the year.
    @State private var withYear = false

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Text("Geburtsdatum")
                .font(AppFont.displaySmall)
                .foregroundStyle(Palette.textPrimary)
            Text("Tag und Monat genügen; das Jahr darf fehlen.")
                .font(AppFont.bodySmall)
                .foregroundStyle(Palette.textSecondary)

            DatePicker("Geburtsdatum", selection: dateBinding, displayedComponents: .date)
                .datePickerStyle(.graphical)
                .labelsHidden()
                .frame(maxWidth: .infinity)

            HStack {
                Text(summary)
                    .font(AppFont.subheading)
                    .foregroundStyle(Palette.textPrimary)
                Spacer(minLength: Space.m)
                Toggle("Jahr angeben", isOn: $withYear)
                    .toggleStyle(.switch)
                    .font(AppFont.body)
            }

            HStack {
                Spacer()
                Button("Abbrechen") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Speichern", action: saveBirthday)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(Space.xl)
        .frame(minWidth: 340)
        .background(Palette.surfaceRaised)
    }

    /// The chosen date as a text; without a year it names the day and the
    /// month only.
    private var summary: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.dateFormat = withYear ? "d. MMMM yyyy" : "d. MMMM"
        return formatter.string(from: dateBinding.wrappedValue)
    }

    /// The date the calendar shows; the picker writes the parts back.
    private var dateBinding: Binding<Date> {
        Binding(
            get: {
                var components = DateComponents()
                components.year = year
                components.month = month
                components.day = day
                return Calendar.current.date(from: components) ?? Date()
            },
            set: { newValue in
                let parts = Calendar.current.dateComponents([.day, .month, .year], from: newValue)
                if let value = parts.day { day = value }
                if let value = parts.month { month = value }
                if let value = parts.year { year = value }
            })
    }

    private func saveBirthday() {
        save(BirthdayInput(day: day, month: month, year: withYear ? year : nil))
        dismiss()
    }
}

/// The mention of the account in the credits.
struct CreditsSheet: View {
    /// Hands the entry to the caller and closes the sheet.
    let save: (CreditsInput) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var magazine = ""

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Text("Credits")
                .font(AppFont.displaySmall)
                .foregroundStyle(Palette.textPrimary)
            Text("So wird das Konto in den Credits genannt.")
                .font(AppFont.bodySmall)
                .foregroundStyle(Palette.textSecondary)
            VStack(spacing: Space.s) {
                TextField("Name", text: $name, prompt: Text("Name im Abspann"))
                TextField("Format", text: $magazine, prompt: Text("Format, zum Beispiel „Mediathek“"))
            }
            .textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button("Abbrechen") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Speichern", action: saveEntry)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!isComplete)
            }
        }
        .padding(Space.xl)
        .frame(minWidth: 340)
        .background(Palette.surfaceRaised)
    }

    /// Whether the fields carry everything the server needs.
    private var isComplete: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && !magazine.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func saveEntry() {
        save(CreditsInput(
            name: name.trimmingCharacters(in: .whitespaces),
            mag: magazine.trimmingCharacters(in: .whitespaces)))
        dismiss()
    }
}
