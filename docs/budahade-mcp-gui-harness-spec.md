# BudahADE MCP GUI Harness — Build Spec

## Meta

- **Author**: Spec Author Agent (Plan Mode)
- **Date**: 2026-04-03
- **Branch**: `mcp-gui-harness` (create from `tab-plan`)
- **Scope**: Add MCP server + GUI rendering infrastructure to budahADE
- **Builder model**: Claude Code via tmux
- **Estimated phases**: 5 (3 core + 1 integration + 1 API pivot prep)

---

## 1. Problem Statement

BudahADE's Plan Mode agent roles (Researcher, Ideator, Designer, Developer, Spec Author) currently output plain text to terminal sessions via Claude Code CLI. This limits their ability to produce rich artifacts: diagrams, comparison tables, interactive prototypes, charts, and structured handoff documents.

Claude Code CLI has no native artifact rendering. But it supports MCP (Model Context Protocol) tool calling. By building a custom MCP server that exposes rendering tools, and promoting the existing `BrowserTileView` (WKWebView) to a first-class artifact panel, Plan Mode agents gain rich output capabilities without requiring an API subscription.

The architecture is designed so that a future pivot from Claude Code CLI to direct Anthropic API calls requires changing only the transport layer. All rendering infrastructure, tool schemas, role definitions, and persistence remain identical.

---

## 2. Architecture Overview

```
┌──────────────────────────────────────────────────────────┐
│  budahADE (Swift App)                                     │
│                                                           │
│  ┌─────────────┐  ┌──────────────────┐  ┌──────────────┐ │
│  │ Plan Mode   │  │ Artifact Panel   │  │ Build Mode   │ │
│  │ Chat Tabs   │  │ (WKWebView)      │  │ Terminal     │ │
│  │ (per role)  │  │                  │  │ (Ghostty)    │ │
│  │             │  │ Renders:         │  │              │ │
│  │ Researcher  │  │ - Mermaid        │  │              │ │
│  │ Ideator     │  │ - HTML/CSS/JS    │  │              │ │
│  │ Designer    │  │ - SVG            │  │              │ │
│  │ Developer   │  │ - Charts (Vega)  │  │              │ │
│  │ Spec Author │  │ - Markdown       │  │              │ │
│  └──────┬──────┘  └────────▲─────────┘  └──────────────┘ │
│         │                  │                              │
│         │    ┌─────────────┴──────────────┐               │
│         │    │ Artifact File Watcher      │               │
│         │    │ .budahade/artifacts/        │               │
│         │    └─────────────▲──────────────┘               │
│         │                  │                              │
│  ┌──────▼──────────────────┴──────────────┐               │
│  │ MCP Server (Node.js, stdio transport)  │               │
│  │                                        │               │
│  │ Tools:                                 │               │
│  │  render_artifact    → writes file      │               │
│  │  show_comparison    → writes JSON      │               │
│  │  update_spec_section → writes spec     │               │
│  │  request_context    ← reads from app   │               │
│  │  show_prototype     → writes HTML      │               │
│  │  log_decision       → writes JSON      │               │
│  │  show_chart         → writes Vega JSON │               │
│  └──────▲─────────────────────────────────┘               │
│         │ stdio (JSON-RPC)                                │
│  ┌──────┴──────────────────────────────────┐              │
│  │ Claude Code Session (tmux)              │              │
│  │ .mcp.json connects to budahade-gui      │              │
│  └─────────────────────────────────────────┘              │
└──────────────────────────────────────────────────────────┘
```

### Communication Flow

1. User sends message in Plan Mode chat tab
2. Message is injected into Claude Code tmux session (existing flow)
3. Claude Code calls MCP tool (e.g., `render_artifact` with Mermaid content)
4. MCP server writes artifact file to `.budahade/artifacts/{id}.{ext}`
5. MCP server writes metadata to `.budahade/artifacts/manifest.json`
6. Swift app's `ArtifactWatcher` detects new file via FSEvents
7. Artifact Panel (WKWebView) renders the content
8. MCP tool returns success to Claude Code
9. Claude Code continues its response in terminal

### Key Design Decisions

- **Node.js for MCP server**: Mature MCP SDK (`@modelcontextprotocol/sdk`), well-tested stdio transport, avoids Swift bridging complexity
- **File system as IPC**: Consistent with existing patterns (SpecWatcher, BuildStatusWatcher). No sockets, no IPC frameworks.
- **WKWebView for rendering**: Already exists as `BrowserTileView.swift`. Promotes from canvas tile to first-class panel.
- **Manifest file for artifact metadata**: Single JSON file tracks all artifacts, their types, timestamps, and source roles. Avoids scanning directory.

---

## 3. Roadmap

```
Phase 1: MCP Server Foundation          [Week 1]
Phase 2: Artifact Rendering Pipeline    [Week 1-2]
Phase 3: Tool Implementation            [Week 2]
Phase 4: Plan Mode Integration          [Week 2-3]
Phase 5: API Pivot Preparation          [Week 3]
                                         
Total estimated: ~3 weeks
```

### Dependency Graph

```
Phase 1 (MCP server) ──┬──> Phase 3 (tools)
                        │
Phase 2 (rendering)  ───┤──> Phase 4 (integration)
                        │
Phase 3 + Phase 4 ──────┴──> Phase 5 (API prep)
```

Phases 1 and 2 can run in parallel. Phase 3 depends on Phase 1. Phase 4 depends on both Phase 2 and Phase 3. Phase 5 depends on Phase 4.

---

## 4. Phase 1 — MCP Server Foundation

### Goal
Standalone Node.js MCP server that Claude Code can connect to. No tools yet, just the server skeleton with health check.

### New Files

```
.budahade/mcp-server/
├── package.json
├── tsconfig.json
├── src/
│   ├── index.ts              # Server entry point, stdio transport
│   ├── tools/                # Tool definitions (empty this phase)
│   │   └── index.ts          # Tool registry
│   └── utils/
│       ├── paths.ts          # Resolve .budahade/ paths
│       └── manifest.ts       # Read/write artifact manifest
```

### Modified Files

```
.mcp.json                     # NEW - project-scoped MCP config
CLAUDE.md                     # ADD - MCP server documentation
project.yml                   # NO CHANGE (Node process is external)
```

### .mcp.json

```json
{
  "mcpServers": {
    "budahade-gui": {
      "command": "node",
      "args": [".budahade/mcp-server/dist/index.js"],
      "env": {
        "BUDAHADE_PROJECT_DIR": "${PROJECT_DIR}",
        "BUDAHADE_ARTIFACTS_DIR": ".budahade/artifacts"
      }
    }
  }
}
```

### Server Skeleton (src/index.ts)

```typescript
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";

const server = new McpServer({
  name: "budahade-gui",
  version: "0.1.0",
  capabilities: {
    tools: {}
  }
});

// Tool registrations go here (Phase 3)

const transport = new StdioServerTransport();
await server.connect(transport);
```

### Manifest Schema (.budahade/artifacts/manifest.json)

```json
{
  "artifacts": [
    {
      "id": "arch-001",
      "type": "mermaid",
      "title": "System Architecture",
      "sourceRole": "developer",
      "filePath": "arch-001.mermaid",
      "createdAt": "2026-04-03T10:30:00Z",
      "conversationId": "conv-abc123"
    }
  ]
}
```

### Verification

1. `cd .budahade/mcp-server && npm install && npm run build`
2. Start Claude Code in the project directory
3. Run `/mcp` — should show `budahade-gui: connected`
4. Ask Claude Code: "What tools are available from budahade-gui?" — should return empty list

### Risk Flags

- **Node.js version**: MCP SDK requires Node 18+. Verify with `node --version` before starting.
- **Path resolution**: `${PROJECT_DIR}` in .mcp.json may not expand correctly. If it fails, use absolute path as fallback and document in CLAUDE.md.
- **Claude Code MCP timeout**: Default is 10s. If the server takes longer to start, set `MCP_TIMEOUT=15000` in the environment.

---

## 5. Phase 2 — Artifact Rendering Pipeline

### Goal
Swift-side infrastructure to watch `.budahade/artifacts/`, detect new files, and render them in a promoted WKWebView panel.

### New Files

```
BudahADE/Artifacts/
├── ArtifactWatcher.swift         # FSEvents watcher for artifacts dir
├── ArtifactManifest.swift        # Parse/track manifest.json
├── ArtifactPanelView.swift       # SwiftUI container for artifact display
├── ArtifactType.swift            # Enum: mermaid, html, svg, chart, markdown, comparison, prototype
├── Renderers/
│   ├── MermaidRenderer.swift     # WKWebView + mermaid.js CDN
│   ├── HTMLRenderer.swift        # WKWebView for raw HTML/prototypes
│   ├── SVGRenderer.swift         # WKWebView for SVG content
│   ├── ChartRenderer.swift       # WKWebView + Vega-Lite CDN
│   ├── MarkdownRenderer.swift    # Native SwiftUI markdown (uses existing swift-markdown dep)
│   └── ComparisonRenderer.swift  # Native SwiftUI table for structured comparisons
```

### Modified Files

```
BudahADE/Workspace/WorkspaceView.swift    # Add artifact panel to layout
BudahADE/Workspace/WorkspaceState.swift   # Add artifact panel visibility state
BudahADE/Shared/Theme.swift               # Add artifact panel styling tokens
```

### ArtifactWatcher.swift

Uses FSEvents (not polling) to watch `.budahade/artifacts/` directory. When `manifest.json` changes, parses the manifest and emits new artifacts to the UI.

```swift
// Key interface
class ArtifactWatcher: ObservableObject {
    @Published var latestArtifact: Artifact?
    @Published var artifacts: [Artifact] = []
    
    func startWatching(projectPath: URL)
    func stopWatching()
}
```

**IMPORTANT**: Do NOT poll. Use `DispatchSource.makeFileSystemObjectSource` or `FileManager` FSEvents stream. This replaces the polling pattern used by GitRepository (which is flagged for replacement in plan-tab.md Phase 4.1).

### ArtifactPanelView.swift

```swift
// Key interface
struct ArtifactPanelView: View {
    @ObservedObject var watcher: ArtifactWatcher
    @State private var selectedArtifact: Artifact?
    
    // Renders as a right-side panel or bottom panel
    // depending on workspace layout state
    // Uses GlassPanel(.sidebar) from existing component library
}
```

### Renderer Pattern

Each renderer conforms to a common protocol:

```swift
protocol ArtifactRenderer {
    associatedtype Content
    func canRender(artifact: Artifact) -> Bool
    func render(artifact: Artifact) -> AnyView
}
```

WKWebView renderers share a base class that handles:
- Loading CDN scripts (mermaid.js, vega-lite)
- Dark theme injection (match budahADE's `#0c0c0e` background)
- Error handling (display error state if render fails)
- Content Security Policy (sandboxed, no external requests except CDN)

### MermaidRenderer HTML Template

```html
<!DOCTYPE html>
<html>
<head>
  <script src="https://cdn.jsdelivr.net/npm/mermaid/dist/mermaid.min.js"></script>
  <style>
    body { 
      background: #0c0c0e; 
      margin: 0; 
      display: flex; 
      justify-content: center; 
      padding: 20px;
    }
    .mermaid { 
      color: #e0e0e0; 
    }
  </style>
</head>
<body>
  <div class="mermaid">
    {{MERMAID_CONTENT}}
  </div>
  <script>
    mermaid.initialize({ 
      theme: 'dark',
      themeVariables: {
        primaryColor: '#7c6cf0',
        primaryTextColor: '#e0e0e0',
        lineColor: '#555',
        secondaryColor: '#111115',
        tertiaryColor: '#1a1a1a'
      }
    });
  </script>
</body>
</html>
```

### Workspace Layout Integration

The artifact panel appears as an optional right-side panel in both Plan and Build modes. It slides in when an artifact is produced and can be pinned open or dismissed.

```
┌──────────┬──────────────────┬─────────────────┐
│ Sidebar  │ Chat / Terminal  │ Artifact Panel  │
│ (220px)  │ (flex)           │ (360px, toggle) │
└──────────┴──────────────────┴─────────────────┘
```

Width: 360px default, resizable via drag handle.
Animation: slide-in from right, 200ms ease-out.
Toggle: keyboard shortcut `Cmd+Shift+A` and toolbar button.

### Verification

1. Manually create `.budahade/artifacts/manifest.json` with a test artifact entry
2. Manually create `.budahade/artifacts/test.mermaid` with a simple flowchart
3. Launch budahADE — artifact panel should appear and render the Mermaid diagram
4. Delete the test files — panel should update (empty state)
5. Verify dark theme matches budahADE's color scheme

### Risk Flags

- **WKWebView in SwiftUI**: Use `NSViewRepresentable` wrapper. The existing `BrowserTileView` already does this. Reuse or extend that pattern, do NOT create a new WKWebView wrapper from scratch.
- **CDN access**: Mermaid.js and Vega-Lite load from CDN. If offline, renderers should show a graceful fallback ("Diagram available — connect to internet to render"). Consider bundling mermaid.min.js locally as a future optimization.
- **Memory**: Each WKWebView renderer is a separate web process. Don't create one per artifact. Reuse a single WKWebView and reload content when the selected artifact changes.

---

## 6. Phase 3 — MCP Tool Implementation

### Goal
Implement all 7 MCP tools in the Node.js server.

### Tool Definitions

#### 3.1 render_artifact

Renders diagrams, SVGs, and formatted markdown in the GUI artifact panel.

```typescript
{
  name: "render_artifact",
  description: "Render a visual artifact in the budahADE GUI panel. Use this when you want to show the user a diagram, SVG, or formatted document.",
  inputSchema: {
    type: "object",
    properties: {
      type: {
        type: "string",
        enum: ["mermaid", "svg", "markdown", "html"],
        description: "The artifact format"
      },
      title: {
        type: "string",
        description: "Human-readable title for the artifact"
      },
      content: {
        type: "string",
        description: "The raw content (Mermaid syntax, SVG markup, markdown, or HTML)"
      }
    },
    required: ["type", "title", "content"]
  }
}
```

**Implementation**: 
1. Generate unique ID (`{role}-{timestamp}-{short-hash}`)
2. Write content to `.budahade/artifacts/{id}.{ext}`
3. Append entry to `manifest.json`
4. Return `{ success: true, artifactId: id }`

#### 3.2 show_comparison

Renders a structured comparison table for evaluating options.

```typescript
{
  name: "show_comparison",
  description: "Display a structured comparison table in the GUI. Use when evaluating multiple approaches, tools, frameworks, or options against criteria.",
  inputSchema: {
    type: "object",
    properties: {
      title: { type: "string" },
      options: {
        type: "array",
        items: {
          type: "object",
          properties: {
            name: { type: "string" },
            description: { type: "string" }
          }
        }
      },
      criteria: {
        type: "array",
        items: {
          type: "object",
          properties: {
            name: { type: "string" },
            weight: { type: "number", description: "0-1 importance weight" }
          }
        }
      },
      scores: {
        type: "array",
        description: "2D array: scores[optionIndex][criteriaIndex], each 1-5",
        items: {
          type: "array",
          items: { type: "number" }
        }
      },
      recommendation: { 
        type: "string",
        description: "The recommended option and why"
      }
    },
    required: ["title", "options", "criteria", "scores"]
  }
}
```

**Implementation**: Write JSON to `.budahade/artifacts/{id}.comparison.json`. Swift `ComparisonRenderer` parses and renders as native SwiftUI table with weighted scores, color coding, and recommendation highlight.

#### 3.3 update_spec_section

Writes content to a specific section of the active spec.

```typescript
{
  name: "update_spec_section",
  description: "Update a specific section of the project spec. Use when contributing findings, design decisions, or implementation details to the shared spec document.",
  inputSchema: {
    type: "object",
    properties: {
      section: {
        type: "string",
        description: "Section name (e.g., 'Architecture', 'API Design', 'Data Model')"
      },
      content: {
        type: "string",
        description: "Markdown content for this section"
      },
      action: {
        type: "string",
        enum: ["replace", "append"],
        description: "Replace the section entirely or append to it"
      }
    },
    required: ["section", "content"]
  }
}
```

**Implementation**: Read `.budahade/spec.md`, find section header, replace or append content, write back. Triggers existing SpecWatcher pipeline.

#### 3.4 request_context

Retrieves context from the project to inform the agent's work.

```typescript
{
  name: "request_context",
  description: "Request specific context from the project. Use when you need to see a file, recent conversation output from another role, or the current spec state.",
  inputSchema: {
    type: "object",
    properties: {
      contextType: {
        type: "string",
        enum: ["file", "spec", "role_output", "git_diff", "artifact"],
        description: "Type of context to retrieve"
      },
      path: {
        type: "string",
        description: "For 'file': relative file path. For 'role_output': role name. For 'artifact': artifact ID."
      },
      maxTokens: {
        type: "number",
        description: "Maximum approximate tokens to return (truncates if exceeded)",
        default: 4000
      }
    },
    required: ["contextType"]
  }
}
```

**Implementation**: 
- `file`: Read file from project directory, return contents (truncated to maxTokens)
- `spec`: Read `.budahade/spec.md`
- `role_output`: Read latest conversation from `.budahade/conversations/{role}/`
- `git_diff`: Run `git diff --stat` and return summary
- `artifact`: Read artifact content by ID from manifest

#### 3.5 show_prototype

Renders an interactive HTML prototype in the artifact panel.

```typescript
{
  name: "show_prototype",
  description: "Display an interactive HTML prototype in the GUI. Use for wireframes, UI concepts, or interactive demos. The prototype renders in a sandboxed WebView.",
  inputSchema: {
    type: "object",
    properties: {
      title: { type: "string" },
      html: {
        type: "string",
        description: "Complete HTML document (include inline CSS and JS)"
      },
      width: {
        type: "number",
        description: "Viewport width in pixels (default: 375 for mobile, 1024 for desktop)",
        default: 375
      },
      height: {
        type: "number",
        description: "Viewport height in pixels",
        default: 812
      }
    },
    required: ["title", "html"]
  }
}
```

**Implementation**: Write HTML to `.budahade/artifacts/{id}.html`. Swift `HTMLRenderer` loads in sandboxed WKWebView with specified viewport dimensions. Adds device frame chrome around the viewport.

#### 3.6 log_decision

Records a structured decision with rationale and alternatives.

```typescript
{
  name: "log_decision",
  description: "Record a decision with its rationale and alternatives considered. Use whenever the team makes a significant technical or design choice.",
  inputSchema: {
    type: "object",
    properties: {
      title: { type: "string" },
      decision: { type: "string", description: "What was decided" },
      rationale: { type: "string", description: "Why this was chosen" },
      alternatives: {
        type: "array",
        items: {
          type: "object",
          properties: {
            name: { type: "string" },
            reason_rejected: { type: "string" }
          }
        }
      },
      sourceRole: { type: "string" },
      tags: {
        type: "array",
        items: { type: "string" },
        description: "Categorization tags (e.g., 'architecture', 'ux', 'performance')"
      }
    },
    required: ["title", "decision", "rationale"]
  }
}
```

**Implementation**: Append to `.budahade/decisions/log.json`. Each entry gets a timestamp and auto-incrementing ID. The decision log is viewable in a dedicated panel or as a filterable list in the sidebar.

#### 3.7 show_chart

Renders data visualizations using Vega-Lite.

```typescript
{
  name: "show_chart",
  description: "Display a data chart or graph in the GUI. Use for visualizing metrics, comparisons, timelines, or any quantitative data. Uses Vega-Lite specification.",
  inputSchema: {
    type: "object",
    properties: {
      title: { type: "string" },
      spec: {
        type: "object",
        description: "A complete Vega-Lite specification object"
      }
    },
    required: ["title", "spec"]
  }
}
```

**Implementation**: Write Vega-Lite JSON to `.budahade/artifacts/{id}.vega.json`. Swift `ChartRenderer` loads in WKWebView with Vega-Lite + Vega-Embed CDN. Dark theme via Vega's `dark` config.

### Verification

For each tool:
1. Start Claude Code with MCP connected
2. Ask Claude Code to use the specific tool with test data
3. Verify file appears in `.budahade/artifacts/`
4. Verify manifest.json is updated
5. Verify Swift app detects and renders the artifact

### Risk Flags

- **Tool description quality matters**: Claude Code decides whether to use tools based on their descriptions. If descriptions are vague, Claude Code will ignore them and just print text. Be extremely specific about WHEN to use each tool.
- **JSON schema validation**: Claude Code sometimes sends malformed tool inputs. The MCP server must validate all inputs and return clear error messages, not crash.
- **File write atomicity**: Write to a temp file first, then rename. Prevents the FSEvents watcher from reading a half-written file.

---

## 7. Phase 4 — Plan Mode Integration

### Goal
Update Plan Mode role prompts to use MCP tools. Wire artifact panel into the Plan Mode workspace layout. Connect handoff mechanism to use structured artifacts.

### Modified Files

```
BudahADE/Agents/AgentPrompts.swift        # Add MCP tool usage instructions to each role
BudahADE/Plan/PlanConversationView.swift   # Add artifact panel to layout
BudahADE/Plan/PlanConversationState.swift  # Track active artifacts per conversation
BudahADE/Plan/HandoffManager.swift         # Include artifacts in handoff context
```

### Role Prompt Updates

Each role gets appended instructions for when and how to use MCP tools. These go into the existing `AgentPrompts` struct.

#### Researcher Role — Additions

```
## Output Tools

When presenting research findings:
- Use `show_comparison` to compare options you've evaluated (frameworks, approaches, tools)
- Use `render_artifact` with type "mermaid" for relationship diagrams or taxonomy trees
- Use `log_decision` when you recommend a specific direction based on your research
- Use `request_context` to read relevant project files before making recommendations
- Use `show_chart` for any quantitative data (market size, benchmark results, adoption rates)

Always use tools for structured output. Do NOT print ASCII tables or text-based diagrams.
```

#### Ideator Role — Additions

```
## Output Tools

When developing ideas:
- Use `render_artifact` with type "mermaid" for concept maps, user flows, and system diagrams
- Use `show_comparison` when presenting multiple ideas for the team to evaluate
- Use `show_prototype` for quick interactive wireframes or concept demos
- Use `log_decision` when narrowing from multiple ideas to a recommended approach
- Use `request_context` with contextType "role_output" to read the Researcher's findings before ideating

Build on previous role outputs. Don't start from scratch.
```

#### Designer Role — Additions

```
## Output Tools

When designing solutions:
- Use `show_prototype` for all UI concepts (mobile: width 375, desktop: width 1024)
- Use `render_artifact` with type "mermaid" for user flows and state diagrams
- Use `render_artifact` with type "svg" for icons, illustrations, or visual elements
- Use `show_comparison` for design option evaluation (with UX criteria)
- Use `log_decision` for design choices with visual rationale
- Use `request_context` to read the Ideator's output and existing spec

Prototypes should use inline CSS with the project's design tokens:
- Background: #0c0c0e
- Surface: #111115  
- Accent: #7c6cf0
- Text: #e0e0e0
- Font: system-ui (Geist Sans equivalent)
```

#### Developer Role — Additions

```
## Output Tools

When analyzing technical approaches:
- Use `render_artifact` with type "mermaid" for architecture diagrams, sequence diagrams, data models
- Use `show_comparison` for technical tradeoff analysis (with criteria like performance, complexity, maintainability)
- Use `show_chart` for performance projections, complexity estimates, or timeline charts
- Use `request_context` with contextType "file" to read existing code before proposing changes
- Use `request_context` with contextType "git_diff" to understand recent changes
- Use `log_decision` for all architecture decisions
- Use `update_spec_section` to add implementation details to the spec

Always read relevant existing code before proposing architecture.
```

#### Spec Author Role — Additions

```
## Output Tools

When authoring specs:
- Use `update_spec_section` to build the spec incrementally (section by section)
- Use `request_context` with contextType "role_output" to read ALL previous role outputs
- Use `request_context` with contextType "artifact" to reference diagrams and comparisons from other roles
- Use `render_artifact` with type "markdown" for the final formatted spec preview
- Use `log_decision` for any spec-level decisions (scope cuts, priority changes)

Your spec must reference artifacts from previous roles by ID. Use the format:
[See: Architecture Diagram (artifact:arch-001)]

The builder agent will use these references to access visual context.
```

### Handoff Enhancement

Currently handoff is "click → pick target" and sends a chat message. Enhance to include:

1. When handing off, collect all artifacts produced by the current role
2. Create a handoff document at `.budahade/handoffs/{from}-to-{to}-{timestamp}.json`:

```json
{
  "from": "researcher",
  "to": "ideator",
  "timestamp": "2026-04-03T10:30:00Z",
  "summary": "Auto-generated summary of conversation",
  "artifactIds": ["comp-001", "chart-001"],
  "decisionIds": [1, 2],
  "keyFindings": ["extracted from conversation"],
  "openQuestions": ["extracted from conversation"]
}
```

3. The receiving role's system prompt includes: "You are continuing from the {from} role's work. Here is their handoff document: {handoff content}. Key artifacts to review: {artifact references}."

### Verification

1. Start a Plan Mode conversation with the Researcher role
2. Ask it to research a topic — should produce artifacts using MCP tools
3. Hand off to Ideator — should receive handoff document with artifact references
4. Ideator should be able to use `request_context` to read Researcher's artifacts
5. Continue through Designer → Developer → Spec Author
6. Spec Author should produce a spec that references artifacts from all previous roles

### Risk Flags

- **Prompt length**: Adding tool usage instructions to each role increases system prompt size. Monitor total prompt tokens. If too large, move tool instructions to a separate file that roles read via `request_context`.
- **Claude Code tool selection**: Claude Code may not consistently use MCP tools even when instructed. If this happens, make the instructions more forceful: "You MUST use show_comparison for any multi-option evaluation. Do NOT print text tables."
- **Handoff document generation**: The auto-summary and key findings extraction is the hardest part. Start with a simple version (just artifact IDs and a manual summary prompt) and iterate.

---

## 8. Phase 5 — API Pivot Preparation

### Goal
Structure the codebase so that swapping from Claude Code CLI to direct Anthropic API calls is a clean, isolated change. Do NOT implement the API client yet. Just prepare the abstraction.

### New Files

```
BudahADE/Agents/
├── AgentTransport.swift          # Protocol defining the transport interface
├── CLITransport.swift            # Current implementation (tmux + Claude Code)
├── APITransport.swift            # Stub for future API implementation
```

### AgentTransport Protocol

```swift
protocol AgentTransport {
    /// Send a message to the agent and receive a streaming response
    func send(
        message: String,
        role: PlanRole,
        context: AgentContext,
        onToken: @escaping (String) -> Void,
        onToolUse: @escaping (ToolCall) -> Void,
        onComplete: @escaping (AgentResponse) -> Void
    )
    
    /// Cancel an in-progress request
    func cancel()
    
    /// Check if the transport is available
    var isAvailable: Bool { get }
}

struct AgentContext {
    let systemPrompt: String
    let conversationHistory: [Message]
    let tools: [ToolDefinition]        // MCP tools as API tool definitions
    let model: String
    let maxTokens: Int
}

struct ToolCall {
    let name: String
    let input: [String: Any]
    let id: String
}
```

### CLITransport (wraps existing tmux flow)

```swift
class CLITransport: AgentTransport {
    // Wraps the existing tmux session management
    // onToken: emits chunks from scrollback capture
    // onToolUse: detected when MCP server writes artifacts
    // This is a refactor of existing code, not new functionality
}
```

### APITransport (stub)

```swift
class APITransport: AgentTransport {
    // STUB — not implemented yet
    // When implemented:
    // - POST to /v1/messages with streaming
    // - Convert AgentContext.tools to API tool definitions
    // - Handle tool_use response blocks → same onToolUse callback
    // - Prompt caching for system prompts
    
    func send(...) {
        fatalError("API transport not yet implemented. Set transport to CLI in settings.")
    }
}
```

### Tool Definition Mapping

The MCP tools defined in Phase 3 map directly to API tool definitions:

```swift
struct ToolDefinition {
    let name: String
    let description: String
    let inputSchema: [String: Any]  // JSON Schema
    
    /// Convert from MCP tool format to API tool format
    func toAPITool() -> [String: Any] {
        return [
            "name": name,
            "description": description,
            "input_schema": inputSchema
        ]
    }
}
```

When the API transport is activated, tool calls come back as `tool_use` content blocks instead of MCP file writes. The rendering pipeline is the same — the API transport's `onToolUse` handler writes the artifact files to `.budahade/artifacts/` just like the MCP server does. The Swift rendering layer doesn't know or care which transport produced the artifact.

### Settings Integration

Add a transport selector to settings:

```swift
enum TransportType: String, Codable {
    case cli = "Claude Code CLI"
    case api = "Anthropic API (requires key)"
}
```

When `api` is selected, show API key field in settings. Store in Keychain, not in plaintext.

### Verification

1. Refactor existing Claude Code session management into `CLITransport`
2. All existing Plan Mode functionality works identically
3. `APITransport` exists as a stub — selecting it shows "not yet implemented" message
4. Tool definitions can be serialized to both MCP format and API format

### What the Full API Pivot Looks Like (future, not this spec)

When you're ready to implement `APITransport`:

1. **New dependency**: Add Swift `AnthropicSwift` SDK or use raw `URLSession` with streaming
2. **Implement `APITransport.send()`**: ~200-300 lines
   - Build messages array from conversation history
   - Add tools from `AgentContext.tools` converted via `toAPITool()`
   - Add `cache_control` to system prompt for prompt caching
   - Stream response via `AsyncBytes`
   - Parse SSE events, emit tokens via `onToken`
   - When `tool_use` block received, write artifact file, call `onToolUse`
   - When `message_stop` received, call `onComplete`
3. **Streaming chat view**: Update `PlanConversationView` to handle incremental token display (~100-150 lines)
4. **Model routing**: Map role to model in `AgentContext` (Researcher→Haiku, Ideator→Sonnet, Designer→Sonnet, Developer→Sonnet, Spec Author→Opus)
5. **Prompt caching**: Add `cache_control: { type: "ephemeral" }` to system prompt content block

Estimated effort for the full pivot: 3-5 days after this spec's infrastructure is built.

---

## 9. File Manifest (Complete)

### New Files (by phase)

| File | Phase | Purpose |
|------|-------|---------|
| `.mcp.json` | 1 | MCP server config for Claude Code |
| `.budahade/mcp-server/package.json` | 1 | Node.js project config |
| `.budahade/mcp-server/tsconfig.json` | 1 | TypeScript config |
| `.budahade/mcp-server/src/index.ts` | 1 | Server entry point |
| `.budahade/mcp-server/src/tools/index.ts` | 1, 3 | Tool registry |
| `.budahade/mcp-server/src/tools/render_artifact.ts` | 3 | Artifact rendering tool |
| `.budahade/mcp-server/src/tools/show_comparison.ts` | 3 | Comparison table tool |
| `.budahade/mcp-server/src/tools/update_spec_section.ts` | 3 | Spec editor tool |
| `.budahade/mcp-server/src/tools/request_context.ts` | 3 | Context retrieval tool |
| `.budahade/mcp-server/src/tools/show_prototype.ts` | 3 | HTML prototype tool |
| `.budahade/mcp-server/src/tools/log_decision.ts` | 3 | Decision logger tool |
| `.budahade/mcp-server/src/tools/show_chart.ts` | 3 | Chart/graph tool |
| `.budahade/mcp-server/src/utils/paths.ts` | 1 | Path resolution helpers |
| `.budahade/mcp-server/src/utils/manifest.ts` | 1 | Manifest read/write |
| `BudahADE/Artifacts/ArtifactWatcher.swift` | 2 | FSEvents watcher |
| `BudahADE/Artifacts/ArtifactManifest.swift` | 2 | Manifest parser |
| `BudahADE/Artifacts/ArtifactPanelView.swift` | 2 | Panel container |
| `BudahADE/Artifacts/ArtifactType.swift` | 2 | Type enum |
| `BudahADE/Artifacts/Renderers/MermaidRenderer.swift` | 2 | Mermaid rendering |
| `BudahADE/Artifacts/Renderers/HTMLRenderer.swift` | 2 | HTML rendering |
| `BudahADE/Artifacts/Renderers/SVGRenderer.swift` | 2 | SVG rendering |
| `BudahADE/Artifacts/Renderers/ChartRenderer.swift` | 2 | Vega-Lite rendering |
| `BudahADE/Artifacts/Renderers/MarkdownRenderer.swift` | 2 | Markdown rendering |
| `BudahADE/Artifacts/Renderers/ComparisonRenderer.swift` | 2 | Comparison table |
| `BudahADE/Agents/AgentTransport.swift` | 5 | Transport protocol |
| `BudahADE/Agents/CLITransport.swift` | 5 | CLI transport impl |
| `BudahADE/Agents/APITransport.swift` | 5 | API transport stub |

### Modified Files

| File | Phase | Change |
|------|-------|--------|
| `CLAUDE.md` | 1 | Add MCP server docs, build instructions |
| `project.yml` | 2 | Add Artifacts source group |
| `BudahADE/Workspace/WorkspaceView.swift` | 2 | Add artifact panel to layout |
| `BudahADE/Workspace/WorkspaceState.swift` | 2 | Artifact panel visibility state |
| `BudahADE/Shared/Theme.swift` | 2 | Artifact panel styling tokens |
| `BudahADE/Agents/AgentPrompts.swift` | 4 | Add MCP tool instructions per role |
| `BudahADE/Plan/PlanConversationView.swift` | 4 | Artifact panel integration |
| `BudahADE/Plan/PlanConversationState.swift` | 4 | Track artifacts per conversation |
| `BudahADE/Plan/HandoffManager.swift` | 4 | Structured handoff with artifacts |
| `.gitignore` | 1 | Add `.budahade/mcp-server/node_modules/` |

---

## 10. Testing Checkpoints

### After Phase 1
- [ ] `npm run build` succeeds in `.budahade/mcp-server/`
- [ ] Claude Code `/mcp` shows `budahade-gui: connected`
- [ ] No errors in Claude Code on startup related to MCP

### After Phase 2
- [ ] Manual test: place files in `.budahade/artifacts/` → panel renders them
- [ ] Mermaid diagram renders with dark theme
- [ ] HTML prototype renders in sandboxed WKWebView
- [ ] SVG renders correctly
- [ ] Artifact panel toggles on/off with `Cmd+Shift+A`
- [ ] Panel resizing works via drag handle
- [ ] Empty state displays when no artifacts exist
- [ ] `xcodebuild build -scheme BudahADE -quiet 2>&1 | tail -5` — no errors

### After Phase 3
- [ ] Each of the 7 tools is callable from Claude Code
- [ ] `render_artifact` writes file + updates manifest
- [ ] `show_comparison` produces valid JSON the Swift renderer parses
- [ ] `update_spec_section` modifies `.budahade/spec.md` correctly
- [ ] `request_context` returns file contents, spec, role output, git diff
- [ ] `show_prototype` writes valid HTML
- [ ] `log_decision` appends to decision log
- [ ] `show_chart` writes valid Vega-Lite JSON
- [ ] Invalid tool inputs return error messages, don't crash server

### After Phase 4
- [ ] Researcher role uses `show_comparison` and `show_chart` without explicit prompting
- [ ] Ideator role references Researcher's artifacts via `request_context`
- [ ] Handoff document is created when switching roles
- [ ] Receiving role acknowledges handoff context
- [ ] Spec Author produces spec with artifact references
- [ ] Full 5-role pipeline produces a spec with embedded artifact references

### After Phase 5
- [ ] Existing Plan Mode works identically through `CLITransport`
- [ ] `APITransport` exists and shows "not implemented" when selected
- [ ] Tool definitions serialize to both MCP and API formats
- [ ] No regressions in Build Mode

---

## 11. Builder Agent Prompt

The following prompt should be used when launching the builder agent for this spec:

```
Read the file .budahade/mcp-gui-harness-spec.md. This is the build spec.

You are implementing the BudahADE MCP GUI Harness. Follow the spec exactly.

RULES:
1. Work phase by phase, in order. Do NOT skip ahead.
2. After each phase, run the verification steps listed in the spec.
3. After creating new Swift files, run `xcodegen generate` to regenerate the project.
4. After any build, run `xcodebuild build -scheme BudahADE -quiet 2>&1 | tail -5` to confirm.
5. Use ONLY colors from Theme.swift. Use ONLY radii from Theme.Radius.
6. For the MCP server (Node.js), use TypeScript with the @modelcontextprotocol/sdk package.
7. Write to temp files first, then rename, for all artifact file writes (prevents partial reads).
8. Do NOT modify Plan Mode views in Views/Plan/ except where explicitly listed in the spec.
9. Do NOT modify Build Mode, terminal, or Ghostty integration.
10. Commit after each sub-phase with descriptive messages.

START with Phase 1. Report progress after each verification checkpoint.
```

---

## 12. Open Questions

1. **Should the MCP server auto-start when budahADE launches?** Current design requires Claude Code to connect, which starts the server via stdio. But if the user opens budahADE before Claude Code, the artifacts directory won't exist yet. Consider creating `.budahade/artifacts/` on app launch regardless.

2. **Artifact retention policy**: How long do artifacts persist? Per-session? Per-project forever? Recommend: persist until manually cleared, with a "Clear artifacts" action in the UI.

3. **Multiple artifact panels**: Should users be able to view two artifacts side-by-side? Start with single panel. Add split view later if needed.

4. **Offline CDN bundling**: Mermaid.js and Vega-Lite are loaded from CDN. Should we bundle them locally? Recommend: CDN for now, bundle as a Phase 6 optimization if offline use is important.

5. **Builder agent artifact access**: When the Spec Author produces a spec with artifact references like `(artifact:arch-001)`, should the builder agent's prompt include the actual artifact content? This would require the builder prompt to resolve artifact references and inject the content. Worth implementing in a future iteration.
