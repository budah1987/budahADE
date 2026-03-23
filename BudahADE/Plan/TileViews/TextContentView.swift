import SwiftUI

// MARK: - Text Content View

struct TextContentView: View {
    let element: CanvasElement
    let textData: TextData
    @ObservedObject var canvas: PlanCanvasState

    @State private var isEditing = false
    @State private var editContent: String = ""

    private var isSelected: Bool { canvas.selectedId == element.id }

    var body: some View {
        VStack(spacing: 0) {
            if isEditing {
                TextField("Type text...", text: $editContent, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(textData.font)
                    .foregroundColor(textData.color)
                    .onSubmit {
                        commitEdit()
                    }
                    .onExitCommand {
                        commitEdit()
                    }
            } else {
                Text(textData.content)
                    .font(textData.font)
                    .italic(textData.isItalic)
                    .foregroundColor(textData.color)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) {
                        editContent = textData.content
                        isEditing = true
                    }
            }
        }
        .padding(8)
    }

    private func commitEdit() {
        isEditing = false
        var updated = textData
        updated.content = editContent
        canvas.updateText(element.id, data: updated)
    }
}

// MARK: - Text Style Toolbar (floats above text element)

struct TextStyleToolbar: View {
    let element: CanvasElement
    let textData: TextData
    @ObservedObject var canvas: PlanCanvasState

    var body: some View {
        HStack(spacing: 4) {
            tButton("B", isActive: textData.isBold, weight: .bold) {
                var updated = textData
                updated.isBold.toggle()
                canvas.updateText(element.id, data: updated)
            }

            tButton("I", isActive: textData.isItalic, italic: true) {
                var updated = textData
                updated.isItalic.toggle()
                canvas.updateText(element.id, data: updated)
            }

            Divider().frame(height: 14).padding(.horizontal, 2)

            Menu {
                ForEach([12, 14, 16, 20, 24, 32, 48, 64], id: \.self) { size in
                    Button("\(size)px") {
                        var updated = textData
                        updated.fontSize = CGFloat(size)
                        canvas.updateText(element.id, data: updated)
                    }
                }
            } label: {
                Text("\(Int(textData.fontSize))")
                    .font(Theme.mono(10))
                    .foregroundColor(Theme.textSecondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Theme.surface3.cornerRadius(3))
            }

            Menu {
                ForEach(TextWeight.allCases, id: \.self) { weight in
                    Button(weight.rawValue.capitalized) {
                        var updated = textData
                        updated.weight = weight
                        canvas.updateText(element.id, data: updated)
                    }
                }
            } label: {
                Text(textData.weight.rawValue.prefix(3).uppercased())
                    .font(Theme.mono(10))
                    .foregroundColor(Theme.textSecondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Theme.surface3.cornerRadius(3))
            }

            Menu {
                ForEach(TextFontFamily.allCases, id: \.self) { family in
                    Button(family.rawValue.capitalized) {
                        var updated = textData
                        updated.fontFamily = family
                        canvas.updateText(element.id, data: updated)
                    }
                }
            } label: {
                Text(textData.fontFamily.rawValue.prefix(4).uppercased())
                    .font(Theme.mono(10))
                    .foregroundColor(Theme.textSecondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Theme.surface3.cornerRadius(3))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Theme.surface2)
                .shadow(color: .black.opacity(0.3), radius: 6, y: 2)
        )
    }

    private func tButton(_ label: String, isActive: Bool, weight: Font.Weight = .regular, italic: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 11, weight: weight))
                .italic(italic)
                .foregroundColor(isActive ? Theme.textPrimary : Theme.textMuted)
                .frame(width: 22, height: 22)
                .background(
                    RoundedRectangle(cornerRadius: 3)
                        .fill(isActive ? Theme.selectedFill : Color.clear)
                )
        }
        .buttonStyle(.plain)
    }
}
