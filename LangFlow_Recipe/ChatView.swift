import SwiftUI

struct ChatView: View {
    @State private var question = ""
    @State private var answer = ""
    @State private var isStreaming = false

    private let client = LangflowClient(
        baseURL: URL(string: "")!,
        flowID: "",
        apiKey: ""
    )
    private let sessionID = "ios-demo-session"

    var body: some View {
        VStack(spacing: 12) {
            TextEditor(text: $question)
                .frame(height: 120)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(.secondary))
            HStack {
                Button("Ask (non-stream)") { Task { await ask() } }
                Button("Ask (stream)") { Task { await askStream() } }
            }
            .buttonStyle(.borderedProminent)

            ScrollView {
                Text(answer)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 8)
            }
        }
        .padding()
    }

    private func ask() async {
        isStreaming = false; answer = ""
        do { answer = try await client.ask(question: question, sessionID: sessionID) }
        catch { answer = "Error: \(error.localizedDescription)" }
    }

    private func askStream() async {
        isStreaming = true; answer = ""
        do {
            for try await token in client.stream(question: question, sessionID: sessionID) {
                answer += token
            }
            isStreaming = false
        } catch {
            answer = "Error: \(error.localizedDescription)"
            isStreaming = false
        }
    }
}
