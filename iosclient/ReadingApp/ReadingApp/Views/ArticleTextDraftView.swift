//
//  ArticleTextDraftView.swift
//  ReadingApp
//
//  Created by GPT-5.1 Codex on 2026/7/9.
//

import SwiftUI

struct ArticleTextDraftView: View {
    @Environment(\.dismiss) private var dismiss
    
    let onSubmitted: (String) -> Void
    let startByCapturing: Bool
    
    @State private var draftText: String = ""
    @State private var isCameraPresented = false
    @State private var isSubmitting = false
    @State private var hasAutoOpenedCamera = false
    @State private var alertMessage: String?
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color(red: 0.97, green: 0.98, blue: 0.97)
                    .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    headerCard
                    editorSection
                    bottomActions
                }
            }
            .navigationTitle("正文草稿")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("关闭") {
                        dismiss()
                    }
                }
            }
        }
        .task {
            guard startByCapturing, !hasAutoOpenedCamera else { return }
            hasAutoOpenedCamera = true
            isCameraPresented = true
        }
        .fullScreenCover(isPresented: $isCameraPresented) {
            CameraCaptureView(
                onSubmit: { uploadItems in
                    try await TextRecognitionService.shared.recognizeArticleText(from: uploadItems)
                },
                onSuccess: { recognizedText in
                    appendRecognizedText(recognizedText)
                }
            )
        }
        .alert(alertMessage ?? "", isPresented: Binding(
            get: { alertMessage != nil },
            set: { _ in alertMessage = nil }
        )) {
            Button("确定", role: .cancel) { alertMessage = nil }
        }
    }
    
    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("拍照后先在本机识别英文，再由你校对。")
                .font(.headline)
                .foregroundColor(.primary)
            Text("你可以继续追加拍照内容，也可以直接编辑识别结果。确认无误后再提交到服务器进行拆句、翻译和音频生成。")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(Color.white)
        .cornerRadius(18)
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 12)
    }
    
    private var editorSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("可编辑英文正文")
                    .font(.headline)
                Spacer()
                Text("\(draftText.count) 字符")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            TextEditor(text: $draftText)
                .scrollContentBackground(.hidden)
                .padding(12)
                .background(Color.white)
                .cornerRadius(16)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(alignment: .topLeading) {
                    if draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("先拍照识别，或直接在这里粘贴/输入英文正文")
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 20)
                            .allowsHitTesting(false)
                    }
                }
        }
        .padding(.horizontal, 16)
    }
    
    private var bottomActions: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Button {
                    isCameraPresented = true
                } label: {
                    Label("继续拍照追加", systemImage: "camera.fill")
                        .font(.headline)
                        .foregroundColor(Color(red: 0.03, green: 0.76, blue: 0.38))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.white)
                        .cornerRadius(16)
                }
                
                Button {
                    draftText = ""
                } label: {
                    Label("清空", systemImage: "trash")
                        .font(.headline)
                        .foregroundColor(.red)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.white)
                        .cornerRadius(16)
                }
                .disabled(draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            
            Button {
                submitDraft()
            } label: {
                HStack {
                    if isSubmitting {
                        ProgressView()
                            .tint(.white)
                    }
                    Text(isSubmitting ? "正在提交..." : "确认并提交")
                        .font(.headline)
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Color(red: 0.03, green: 0.76, blue: 0.38))
                .cornerRadius(18)
            }
            .disabled(isSubmitting || draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .opacity(isSubmitting || draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.6 : 1)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 18)
    }
    
    private func appendRecognizedText(_ text: String) {
        let cleanText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanText.isEmpty else { return }
        
        if draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            draftText = cleanText
        } else {
            draftText += "\n\n" + cleanText
        }
    }
    
    private func submitDraft() {
        let finalText = draftText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !finalText.isEmpty else {
            alertMessage = "请先准备要提交的英文正文"
            return
        }
        
        isSubmitting = true
        Task {
            defer { isSubmitting = false }
            do {
                let response = try await ArticleAPI.shared.processArticleText(finalText)
                guard let id = response.id, !id.isEmpty else {
                    alertMessage = "服务器未返回文章 ID"
                    return
                }
                onSubmitted(id)
                dismiss()
            } catch {
                alertMessage = error.localizedDescription
            }
        }
    }
}

#Preview {
    ArticleTextDraftView(onSubmitted: { _ in }, startByCapturing: false)
}
