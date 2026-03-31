import Foundation

// MARK: - Dev Server Config

struct DevServerConfig: Equatable {
    let command: String
    let portInjection: PortInjection

    /// Build the full shell command with port injected.
    func shellCommand(port: Int) -> String {
        switch portInjection {
        case .envVar(let name):
            return "\(name)=\(port) \(command)"
        case .flag(let flag):
            return "\(command) \(flag) \(port)"
        case .argument:
            return "\(command) \(port)"
        case .stdout:
            return command  // Port is detected from stdout, not injected
        }
    }
}

enum PortInjection: Equatable {
    case envVar(String)   // PORT=3001 npm run dev
    case flag(String)     // npx vite --port 3001
    case argument         // python manage.py runserver 3001
    case stdout           // cargo run — parse port from output
}

// MARK: - Dev Server Detector

/// Pure function: scans a worktree for known project types and returns a dev server config.
enum DevServerDetector {
    static func detect(in worktreePath: String) -> DevServerConfig? {
        let fm = FileManager.default

        // Vite (check before generic npm — vite has its own port flag)
        if fileExists("vite.config.ts", in: worktreePath, fm: fm)
            || fileExists("vite.config.js", in: worktreePath, fm: fm)
            || fileExists("vite.config.mts", in: worktreePath, fm: fm) {
            return DevServerConfig(command: "npx vite", portInjection: .flag("--port"))
        }

        // Next.js
        if fileExists("next.config.js", in: worktreePath, fm: fm)
            || fileExists("next.config.ts", in: worktreePath, fm: fm)
            || fileExists("next.config.mjs", in: worktreePath, fm: fm) {
            return DevServerConfig(command: "npx next dev", portInjection: .flag("--port"))
        }

        // Generic Node.js with "dev" script
        if let packageJson = readJSON("package.json", in: worktreePath, fm: fm),
           let scripts = packageJson["scripts"] as? [String: Any],
           scripts["dev"] != nil {
            return DevServerConfig(command: "npm run dev", portInjection: .envVar("PORT"))
        }

        // Django
        if fileExists("manage.py", in: worktreePath, fm: fm) {
            return DevServerConfig(command: "python manage.py runserver", portInjection: .argument)
        }

        // Go with net/http
        if let goMod = readString("go.mod", in: worktreePath, fm: fm),
           goMod.contains("net/http") || goMod.contains("gin-gonic") || goMod.contains("gorilla") {
            return DevServerConfig(command: "go run .", portInjection: .stdout)
        }

        // Rust with actix/axum/rocket
        if let cargoToml = readString("Cargo.toml", in: worktreePath, fm: fm),
           cargoToml.contains("actix") || cargoToml.contains("axum") || cargoToml.contains("rocket") {
            return DevServerConfig(command: "cargo run", portInjection: .stdout)
        }

        return nil
    }

    // MARK: - Helpers

    private static func fileExists(_ name: String, in dir: String, fm: FileManager) -> Bool {
        fm.fileExists(atPath: (dir as NSString).appendingPathComponent(name))
    }

    private static func readJSON(_ name: String, in dir: String, fm: FileManager) -> [String: Any]? {
        let path = (dir as NSString).appendingPathComponent(name)
        guard let data = fm.contents(atPath: path),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return json
    }

    private static func readString(_ name: String, in dir: String, fm: FileManager) -> String? {
        let path = (dir as NSString).appendingPathComponent(name)
        guard let data = fm.contents(atPath: path) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
