import SwiftUI
import WebKit

struct PrometheusDashboardView: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            PrometheusWebView(url: url)
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle(LocalizedStringKey("Metrics dashboard"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(LocalizedStringKey("Close")) { dismiss() }
                    }
                }
        }
    }
}

private struct PrometheusWebView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
