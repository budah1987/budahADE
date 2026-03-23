import Foundation

enum MermaidRenderer {
    static func htmlPage(diagramCode: String, theme: MermaidTheme = .dark) -> String {
        """
        <!DOCTYPE html>
        <html>
        <head>
            <style>
                body {
                    background: \(theme.backgroundColor);
                    display: flex;
                    justify-content: center;
                    align-items: center;
                    min-height: 100vh;
                    margin: 0;
                    padding: 16px;
                }
            </style>
        </head>
        <body>
            <pre class="mermaid">
            \(diagramCode)
            </pre>
            <script src="mermaid.min.js"></script>
            <script>
                mermaid.initialize({
                    startOnLoad: true,
                    theme: '\(theme.mermaidTheme)',
                    themeVariables: { fontSize: '14px' }
                });
            </script>
        </body>
        </html>
        """
    }

    enum MermaidTheme {
        case dark, light

        var backgroundColor: String {
            switch self {
            case .dark: return "#141416"
            case .light: return "#ffffff"
            }
        }

        var mermaidTheme: String {
            switch self {
            case .dark: return "dark"
            case .light: return "default"
            }
        }
    }
}
