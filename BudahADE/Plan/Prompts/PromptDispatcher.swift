import SwiftUI

/// Chooses the right card for the current queue shape and draws it inside
/// a single `@Namespace`. The same question text, accent line, and dismiss
/// button use `matchedGeometryEffect` so a confirm → stepper transition feels
/// like one object morphing rather than two sheets swapping.
///
/// Rules:
/// - `queue.count >= 2` → StepperCard flattening each prompt to one step.
/// - single prompt of kind `.questionSeries` → StepperCard over the sub-questions.
/// - single `.confirm` / `.choice` / `.question` → its dedicated card.
struct PromptDispatcher: View {
    let queue: [AgentSession.QueuedPrompt]
    let onAnswerPrompt: (AgentSession.QueuedPrompt, String) -> Void
    let onAnswerAll: ([String]) -> Void
    let onApproveAndBuild: () -> Void
    let onDismiss: () -> Void

    @Namespace private var morph

    var body: some View {
        Group {
            if queue.count >= 2 {
                StepperCard(
                    steps: queue.map { stepFromPrompt($0) },
                    namespace: morph,
                    onComplete: { answers in
                        onAnswerAll(answers)
                    },
                    onDismiss: onDismiss
                )
            } else if let first = queue.first {
                singleCard(for: first)
            }
        }
        .animation(.spring(response: 0.5, dampingFraction: 0.85), value: queue.count)
        .animation(.spring(response: 0.5, dampingFraction: 0.85), value: queue.first?.id)
        .transition(.asymmetric(
            insertion: .move(edge: .bottom).combined(with: .opacity),
            removal: .move(edge: .bottom).combined(with: .opacity)
        ))
    }

    @ViewBuilder
    private func singleCard(for prompt: AgentSession.QueuedPrompt) -> some View {
        switch prompt.kind {
        case .confirm:
            ConfirmCard(
                prompt: prompt,
                namespace: morph,
                onAnswer: { answer in onAnswerPrompt(prompt, answer) },
                onDismiss: onDismiss
            )
        case .choice(let options, let recommendedIndex, let isSpecReady):
            ChoiceCard(
                prompt: prompt,
                options: options,
                recommendedIndex: recommendedIndex,
                showApproveAndBuild: isSpecReady,
                namespace: morph,
                onSelect: { option in
                    let label = "\(option.id + 1). \(option.text)"
                    onAnswerPrompt(prompt, label)
                },
                onCustomResponse: { text in
                    onAnswerPrompt(prompt, text)
                },
                onApproveAndBuild: onApproveAndBuild,
                onDismiss: onDismiss
            )
        case .question(let suggestions):
            QuestionCard(
                prompt: prompt,
                suggestions: suggestions,
                namespace: morph,
                onSubmit: { answer in onAnswerPrompt(prompt, answer) },
                onDismiss: onDismiss
            )
        case .questionSeries(let subs):
            StepperCard(
                steps: subs.map { sub in
                    StepperStep(
                        id: sub.id,
                        question: sub.question,
                        context: sub.context,
                        suggestions: sub.suggestions,
                        sourcePrompt: prompt
                    )
                },
                namespace: morph,
                onComplete: { answers in
                    let response = answers.count == 1
                        ? answers[0]
                        : answers.enumerated().map { i, a in "\(i + 1). \(a)" }.joined(separator: "\n")
                    onAnswerPrompt(prompt, response)
                },
                onDismiss: onDismiss
            )
        }
    }

    private func stepFromPrompt(_ prompt: AgentSession.QueuedPrompt) -> StepperStep {
        // Each queue item becomes one stepper step. For series prompts, we flatten
        // to the first sub-question text as the step title. (Full series stacking
        // is handled as a single-prompt case, not when mixed with other prompts.)
        let suggestions: [String]
        switch prompt.kind {
        case .confirm:
            suggestions = ["Yes", "No"]
        case .choice(let options, _, _):
            suggestions = options.map { $0.text }
        case .question(let s):
            suggestions = s
        case .questionSeries(let subs):
            suggestions = subs.first?.suggestions ?? []
        }
        return StepperStep(
            id: prompt.id,
            question: prompt.question,
            context: prompt.context,
            suggestions: suggestions,
            sourcePrompt: prompt
        )
    }
}
