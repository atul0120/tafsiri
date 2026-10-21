import SwiftUI

extension Color {
    static let tafsiriGreen = Color(red: 0.055, green: 0.42, blue: 0.36)
    static let tafsiriSun = Color(red: 0.85, green: 0.54, blue: 0.12)
}

struct ContentView: View {
    @StateObject private var engine = ListenEngine()
    @State private var showSettings = false
    @State private var typing = false
    @State private var typedReply = ""
    @AppStorage(Prefs.Key.speakAloud) private var speakAloud = true

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                StatusStrip(engine: engine)

                if let latest = engine.lines.first {
                    LatestCard(line: latest) { engine.replay(latest) }
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                } else {
                    EmptyState(engine: engine)
                }

                List {
                    ForEach(engine.lines.dropFirst()) { line in
                        HistoryRow(line: line)
                            .contentShape(Rectangle())
                            .onTapGesture { engine.replay(line) }
                    }
                }
                .listStyle(.plain)

                BottomBar(engine: engine, speakAloud: $speakAloud) { typing = true }
            }
            .navigationTitle("Tafsiri Live")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { engine.clear() } label: { Image(systemName: "trash") }
                        .accessibilityLabel("Clear conversation")
                        .disabled(engine.lines.isEmpty)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: { Image(systemName: "gearshape") }
                        .accessibilityLabel("Settings")
                }
            }
            .sheet(isPresented: $showSettings) { SettingsView(engine: engine) }
            .alert("Reply in Kiswahili", isPresented: $typing) {
                TextField("Type in English", text: $typedReply)
                Button("Translate & speak") { engine.reply(typed: typedReply); typedReply = "" }
                Button("Cancel", role: .cancel) { typedReply = "" }
            } message: {
                Text("Tafsiri translates it and speaks it in Kiswahili on the phone's speaker.")
            }
            .task { if engine.modelState == .notLoaded { await engine.loadModel() } }
        }
        .tint(.tafsiriGreen)
    }
}

struct StatusStrip: View {
    @ObservedObject var engine: ListenEngine
    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(engine.statusColor)
                .frame(width: 10, height: 10)
            Text(engine.isTranslating ? "Translating…" :
                    (engine.hearingSpeech ? (engine.replyArmed ? "Hearing your reply…" : "Hearing speech…") : engine.status))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Spacer(minLength: 0)
            if case .loading = engine.modelState { ProgressView().controlSize(.small) }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(.secondarySystemBackground))
    }
}

extension ListenEngine {
    var statusColor: Color {
        if replyArmed { return .tafsiriSun }
        if hearingSpeech { return .tafsiriSun }
        return isListening ? .green : .secondary
    }
}

struct LatestCard: View {
    let line: Line
    let replay: () -> Void

    var body: some View {
        let isReply = line.kind == .reply
        let big = isReply ? (line.swahili ?? "") : line.english
        let small: String? = isReply ? line.english : line.swahili
        VStack(alignment: .leading, spacing: 10) {
            Text(isReply ? "YOU SAID, IN KISWAHILI" : "THEY SAID, IN ENGLISH")
                .font(.caption.weight(.bold)).tracking(1.2)
                .foregroundStyle(.white.opacity(0.8))
            Text(big)
                .font(.system(.title, design: .rounded).weight(.semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
            if let small, !small.isEmpty {
                Text(small).font(.callout).foregroundStyle(.white.opacity(0.85))
            }
            HStack {
                Text(line.time, style: .time).font(.caption).foregroundStyle(.white.opacity(0.75))
                Spacer()
                Button(action: replay) {
                    Label(isReply ? "Sema tena" : "Hear again", systemImage: "speaker.wave.2.fill")
                }
                .font(.caption.weight(.semibold))
                .buttonStyle(.bordered).tint(.white)
            }
        }
        .padding(18)
        .background(isReply ? Color.tafsiriSun : Color.tafsiriGreen,
                    in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

struct HistoryRow: View {
    let line: Line
    var body: some View {
        let isReply = line.kind == .reply
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: isReply ? "arrowshape.turn.up.left.fill" : "ear")
                .foregroundStyle(isReply ? Color.tafsiriSun : Color.tafsiriGreen)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 3) {
                Text(isReply ? (line.swahili ?? "") : line.english).font(.body)
                if let sub = (isReply ? Optional(line.english) : line.swahili), !sub.isEmpty {
                    Text(sub).font(.footnote).foregroundStyle(.secondary)
                }
                Text(line.time, style: .time).font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }
}

struct EmptyState: View {
    @ObservedObject var engine: ListenEngine
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "ear.and.waveform")
                .font(.system(size: 48))
                .foregroundStyle(Color.tafsiriGreen)
            Text(engine.isListening ? "Listening for Kiswahili" : "Hands-free Kiswahili ↔ English")
                .font(.title3.weight(.semibold))
            Text(engine.isListening
                 ? "When someone speaks Kiswahili, the English appears here. Tap Reply and speak English to answer them in Kiswahili."
                 : "Tap Start once. Tafsiri keeps listening, even in your pocket, and translates whenever it hears Kiswahili.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if case .failed = engine.modelState {
                Button("Try downloading again") { Task { await engine.loadModel() } }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity)
    }
}

struct BottomBar: View {
    @ObservedObject var engine: ListenEngine
    @Binding var speakAloud: Bool
    let typeReply: () -> Void

    var body: some View {
        let loud = CGFloat(max(0, min(1, (engine.level + 60) / 45)))
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Button { Task { await engine.armReply() } } label: {
                    Label(engine.replyArmed ? "Speak English now…" : "Reply in Kiswahili",
                          systemImage: engine.replyArmed ? "waveform" : "arrowshape.turn.up.left.fill")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .tint(engine.replyArmed ? .red : .tafsiriSun)

                Button(action: typeReply) {
                    Image(systemName: "keyboard").frame(width: 44, height: 44)
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Type a reply")
            }

            HStack(spacing: 14) {
                Button { speakAloud.toggle() } label: {
                    Image(systemName: speakAloud ? "speaker.wave.2.fill" : "speaker.slash.fill")
                        .font(.title2)
                        .frame(width: 48, height: 48)
                }
                .accessibilityLabel(speakAloud ? "Reading English aloud on" : "Reading English aloud off")

                Button { engine.toggle() } label: {
                    ZStack {
                        Capsule()
                            .stroke(Color.tafsiriSun.opacity(engine.isListening ? 0.7 : 0), lineWidth: 3)
                            .scaleEffect(x: 1 + loud * 0.08, y: 1 + loud * 0.3)
                            .animation(.easeOut(duration: 0.12), value: loud)
                        Capsule().fill(engine.isListening ? Color.red : Color.tafsiriGreen)
                        Label(engine.isListening ? "Stop" : "Start", systemImage: engine.isListening ? "stop.fill" : "ear")
                            .font(.headline)
                            .foregroundStyle(.white)
                    }
                    .frame(height: 56)
                }
                .disabled(engine.modelState == .loading)

                Color.clear.frame(width: 48, height: 48)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.bar)
    }
}

#Preview { ContentView() }
