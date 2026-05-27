import SwiftUI

struct QuestionSheetView: View {
    @EnvironmentObject var localizer: Localizer
    let question: PendingQuestion
    let session: SessionState
    let onAnswer: (String) -> Void

    @State private var selectedOptions: Set<String> = []
    @State private var textAnswer: String = ""

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                Image(systemName: "questionmark.bubble.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(.purple)

                if let header = question.header {
                    Text(header)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                }

                Text(question.question)
                    .font(.system(size: 12))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                if !question.questions.isEmpty {
                    ForEach(question.questions, id: \.question) { item in
                        QuestionItemView(
                            item: item,
                            selectedOptions: $selectedOptions,
                            multiSelect: item.multiSelect
                        )
                    }
                } else if !question.options.isEmpty {
                    VStack(spacing: 4) {
                        ForEach(Array(question.options.enumerated()), id: \.offset) { idx, option in
                            Button(action: {
                                if question.multiSelect {
                                    if selectedOptions.contains(option) {
                                        selectedOptions.remove(option)
                                    } else {
                                        selectedOptions.insert(option)
                                    }
                                } else {
                                    onAnswer(option)
                                }
                            }) {
                                HStack {
                                    if question.multiSelect {
                                        Image(systemName: selectedOptions.contains(option) ? "checkmark.square.fill" : "square")
                                            .font(.system(size: 12))
                                            .foregroundStyle(selectedOptions.contains(option) ? .blue : .secondary)
                                    } else {
                                        Circle()
                                            .stroke(.secondary, lineWidth: 1)
                                            .frame(width: 12, height: 12)
                                    }
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(option)
                                            .font(.system(size: 12))
                                            .foregroundStyle(.primary)
                                        if idx < question.descriptions.count {
                                            Text(question.descriptions[idx])
                                                .font(.system(size: 10))
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    Spacer()
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(.primary.opacity(0.04))
                                .cornerRadius(8)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            if question.multiSelect {
                Divider()

                HStack(spacing: 8) {
                    Button(action: {
                        onAnswer("cancel")
                    }) {
                        Text(localizer.agentCancel)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(.secondary.opacity(0.1))
                            .cornerRadius(8)
                    }
                    .buttonStyle(.plain)

                    Button(action: {
                        let answer = selectedOptions.sorted().joined(separator: ", ")
                        onAnswer(answer.isEmpty ? "skip" : answer)
                    }) {
                        Text(localizer.agentSubmit)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(selectedOptions.isEmpty ? Color.secondary : Color.blue)
                            .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                    .disabled(selectedOptions.isEmpty)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
        }
    }
}

struct QuestionItemView: View {
    let item: QuestionItem
    @Binding var selectedOptions: Set<String>
    let multiSelect: Bool

    @State private var localSelection: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let header = item.header {
                Text(header)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
            }

            Text(item.question)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.primary)

            ForEach(item.options, id: \.label) { opt in
                Button(action: {
                    if item.multiSelect {
                        if localSelection.contains(opt.label) {
                            localSelection.remove(opt.label)
                        } else {
                            localSelection.insert(opt.label)
                        }
                    } else {
                        localSelection = [opt.label]
                    }
                    selectedOptions = localSelection
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: localSelection.contains(opt.label)
                            ? (item.multiSelect ? "checkmark.square.fill" : "record.circle.fill")
                            : (item.multiSelect ? "square" : "circle"))
                            .font(.system(size: 11))
                            .foregroundStyle(localSelection.contains(opt.label) ? .blue : .secondary)

                        VStack(alignment: .leading, spacing: 1) {
                            Text(opt.label)
                                .font(.system(size: 11))
                                .foregroundStyle(.primary)
                            if let desc = opt.description {
                                Text(desc)
                                    .font(.system(size: 9))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.vertical, 3)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(8)
        .background(.primary.opacity(0.03))
        .cornerRadius(8)
    }
}
