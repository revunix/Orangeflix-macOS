import Testing
@testable import OrangeflixLogic

@Suite("Chat notifications")
struct ChatNotificationsTests {
    @Test("a mention is found whatever the case")
    func mentionCase() {
        #expect(ChatNotifications.mentions("Hallo @Nils, schau mal", name: "nils"))
        #expect(ChatNotifications.mentions("guten abend NILS", name: "Nils"))
    }

    @Test("a name in a longer word counts, like the web chat")
    func mentionInWord() {
        #expect(ChatNotifications.mentions("nilsen war schneller", name: "nils"))
    }

    @Test("a name without accents also finds accented text")
    func mentionAccents() {
        #expect(ChatNotifications.mentions("grüße an jörg", name: "jorg"))
    }

    @Test("a message without the name is no mention")
    func noMention() {
        #expect(!ChatNotifications.mentions("Hallo zusammen", name: "Nils"))
        #expect(!ChatNotifications.mentions("", name: "Nils"))
    }

    @Test("a name too short is never a mention")
    func shortName() {
        #expect(!ChatNotifications.mentions("a", name: "a"))
        #expect(!ChatNotifications.mentions("Hallo", name: " "))
    }

    @Test("the mention line names the sender")
    func mentionBody() {
        #expect(ChatNotifications.mentionBody(from: "Anna", text: "Hallo Nils") == "Anna: Hallo Nils")
        #expect(ChatNotifications.mentionBody(from: "  ", text: "Hallo") == "Hallo")
    }

    @Test("the reaction line names the actor, the emoji and the message")
    func reactionBody() {
        #expect(ChatNotifications.reactionBody(actor: "Ben", emoji: "👍", text: "Tolle Folge")
                == "Ben: 👍 auf deine Nachricht: „Tolle Folge“")
        #expect(ChatNotifications.reactionBody(actor: "", emoji: "❤️", text: "")
                == "❤️ auf deine Nachricht")
    }

    @Test("a long message is cut with an ellipsis")
    func excerpt() {
        let long = String(repeating: "a", count: 200)
        let cut = ChatNotifications.excerpt(long)
        #expect(cut.count == ChatNotifications.excerptLimit + 1)
        #expect(cut.hasSuffix("…"))
        #expect(ChatNotifications.excerpt("kurz") == "kurz")
    }
}
