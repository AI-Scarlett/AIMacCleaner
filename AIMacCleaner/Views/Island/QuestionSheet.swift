import SwiftUI

struct QuestionSheetView: View {
    @EnvironmentObject var localizer: Localizer
    let question: PendingQuestion
    let session: SessionState
    let onAnswer: (String) -> Void

    @State private var selectedOptions: Set<String> = []
    @State private var textAnswer: String = ""
    @FocusState private var isTextAnswerFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            compactHeader

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    Text(question.question)
                        .font(.system(size: 11))
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if !question.questions.isEmpty {
                        ForEach(question.questions, id: \.question) { item in
                            QuestionItemView(
                                item: item,
                                selectedOptions: $selectedOptions,
                                multiSelect: item.multiSelect
                            )
                        }
                    } else if !question.options.isEmpty {
                        optionList
                    }

                    if !question.attachments.isEmpty {
                        ApprovalAttachmentStrip(attachments: question.attachments)
                    }

                    customReplySection
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .onAppear {
                if question.isTextReply {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        isTextAnswerFocused = true
                    }
                }
            }

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

    private var compactHeader: some View {
        HStack(spacing: 8) {
            Image(systemName: "questionmark.bubble.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.purple)
                .frame(width: 24, height: 24)
                .background(.purple.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 1) {
                Text(question.header ?? localizer.agentCenterQuestion)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(question.isTextReply ? localizer.agentCustomReply : localizer.agentCenterQuestion)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
    }

    private var optionList: some View {
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

    private var customReplySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(localizer.agentCustomReply)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)

            TextEditor(text: $textAnswer)
                .font(.system(size: 12))
                .scrollContentBackground(.hidden)
                .focused($isTextAnswerFocused)
                .frame(minHeight: 58)
                .padding(6)
                .background(.primary.opacity(0.04))
                .cornerRadius(8)
                .overlay(alignment: .topLeading) {
                    if textAnswer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(localizer.agentCustomReplyPlaceholder)
                            .font(.system(size: 12))
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 14)
                            .allowsHitTesting(false)
                    }
                }

            Button {
                onAnswer(textAnswer.trimmingCharacters(in: .whitespacesAndNewlines))
            } label: {
                Text(localizer.agentSendReply)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(textAnswer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.secondary : Color.purple)
                    .cornerRadius(8)
            }
            .buttonStyle(.plain)
            .disabled(textAnswer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.top, 6)
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
