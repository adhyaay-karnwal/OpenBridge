import SwiftUI

struct MessageErrorView: View {
    let error: Error
    var onRetry: (() -> Void)?

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 32))

            VStack(spacing: 4) {
                Text("The local agent hit an error.")
                    .font(.body)

                Text(error.localizedDescription)
                    .font(.body)
                    .opacity(0.75)
            }
            .multilineTextAlignment(.center)

            HStack(spacing: 12) {
                Button(action: {
                    onRetry?()
                }) {
                    Text("Try again")
                        .padding(.horizontal, 8)
                        .font(.body.weight(.medium))
                }
                .buttonStyle(.bordered)

                Button(action: {
                    reportIssue()
                }) {
                    Text("Report issue")
                        .padding(.horizontal, 8)
                        .font(.body.weight(.medium))
                }
                .buttonStyle(.pillOutlined)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func reportIssue() {
        let email = "support@cue.surf"
        let subject = "Issue Report"
        let body = """
        Error Details:
        \(error.localizedDescription)

        ---
        Please describe what you were doing when this error occurred:


        """

        guard
            let encodedSubject = subject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
            let encodedBody = body.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
            let url = URL(string: "mailto:\(email)?subject=\(encodedSubject)&body=\(encodedBody)")
        else {
            return
        }

        NSWorkspace.shared.open(url)
    }
}

#Preview {
    MessageErrorView(
        error: NSError(
            domain: "test", code: 0, userInfo: [NSLocalizedDescriptionKey: "Test error message"]
        ),
        onRetry: { print("Retry tapped") }
    )
    .frame(width: 400, height: 300)
}
