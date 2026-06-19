import SwiftUI
import ThreadHive

// Minimal end-to-end demo of the ThreadHive iOS SDK. See ../README.md for how to
// run this inside an Xcode app target. Replace the widget key + API base below.

private enum Demo {
    static let widgetKey = "wk_live_replace_me"
    static let apiBaseURL = URL(string: "https://app.example.com/api")!
}

@main
struct ThreadHiveDemoApp: App {
    init() {
        // 1. Configure once at launch. The widget key is public.
        var config = ThreadHiveConfiguration(widgetKey: Demo.widgetKey, apiBaseURL: Demo.apiBaseURL)
        config.logger = ConsoleLogger(minimumLevel: .debug)
        ThreadHive.configure(config)
    }

    var body: some Scene {
        WindowGroup { DemoHome() }
    }
}

struct DemoHome: View {
    @State private var showChat = false
    @State private var unread = 0
    @State private var identified = false

    var body: some View {
        NavigationView {
            List {
                Section("Chat") {
                    Button {
                        showChat = true
                    } label: {
                        HStack {
                            Label("Open chat", systemImage: "bubble.left.and.bubble.right.fill")
                            Spacer()
                            if unread > 0 {
                                Text("\(unread)")
                                    .font(.caption.bold()).foregroundColor(.white)
                                    .padding(6).background(Color.red).clipShape(Circle())
                            }
                        }
                    }
                    Button("Refresh unread badge") {
                        ThreadHive.unreadCount { unread = $0 }
                    }
                }

                Section("Identity") {
                    Button(identified ? "Re-identify user" : "Identify as u_123") {
                        // In production, fetch userHash from YOUR backend:
                        //   userHash = HMAC-SHA256(identitySecret, "u_123")
                        ThreadHive.identify(
                            userID: "u_123",
                            email: "ada@example.com",
                            name: "Ada Lovelace",
                            userHash: nil, // demo: unverified; pass the server hash in production
                            traits: ["plan": .string("pro")]
                        )
                        identified = true
                    }
                    Button("Log out (reset visitor)", role: .destructive) {
                        ThreadHive.logout()
                        identified = false
                        unread = 0
                    }
                }

                Section("Visitor") {
                    LabeledContent("visitor_id", value: ThreadHive.visitorID ?? "—")
                    LabeledContent("SDK", value: "ThreadHive \(ThreadHive.sdkVersion)")
                }
            }
            .navigationTitle("ThreadHive Demo")
            .sheet(isPresented: $showChat, onDismiss: { ThreadHive.unreadCount { unread = $0 } }) {
                if let chat = ThreadHiveChatView(onClose: { showChat = false }) {
                    chat
                } else {
                    Text("Call ThreadHive.configure(...) first.").padding()
                }
            }
            .onAppear { ThreadHive.unreadCount { unread = $0 } }
        }
        .navigationViewStyle(.stack)
    }
}
