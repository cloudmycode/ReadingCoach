//
//  CameraCaptureView.swift
//  ReadingApp
//
//  Created by GPT-5.1 Codex on 2025/11/27.
//
//  单张拍照组件：拍摄 → 框选文字区域裁剪 → 云端识别后返回文字编辑页。

import SwiftUI
import AVFoundation
import UIKit
import PhotosUI
import Combine

// MARK: - Constants

private enum Constants {
    static let jpegCompressionQuality: CGFloat = 0.75
    /// 上传识别前的最长边像素上限。文档 OCR 用 ~1600px 已足够清晰，
    /// 过高分辨率会显著拖慢云端识别甚至超时。
    static let maxUploadDimension: CGFloat = 1600
    static let buttonSize: CGFloat = 60
    static let captureButtonSize: CGFloat = 80
    static let captureButtonInnerSize: CGFloat = 64
    static let cornerHandleSize: CGFloat = 22
    /// 归一化裁剪框最小边长（相对图片宽/高）
    static let minCropSize: CGFloat = 0.08
    static let bottomButtonHeight: CGFloat = 100
}

// MARK: - Camera Capture View

struct CameraCaptureView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: CameraViewModel
    
    let onSubmit: (PhotoUploadItem) async throws -> String
    let onSuccess: (String) -> Void
    
    init(
        onSubmit: @escaping (PhotoUploadItem) async throws -> String,
        onSuccess: @escaping (String) -> Void
    ) {
        self.onSubmit = onSubmit
        self.onSuccess = onSuccess
        _viewModel = StateObject(wrappedValue: CameraViewModel(onSubmit: onSubmit))
    }
    
    var body: some View {
        ZStack {
            cameraPreview
            overlays
        }
        .background(Color.black.ignoresSafeArea())
        .onAppear {
            viewModel.activateCamera()
        }
        .onDisappear {
            viewModel.stopCamera()
        }
        .fullScreenCover(isPresented: $viewModel.isShowingPreview) {
            PhotoPreviewView(
                photo: $viewModel.photo,
                isProcessing: viewModel.isProcessing,
                onRetake: viewModel.retakePhoto,
                onRotate: viewModel.rotatePhoto,
                onCrop: viewModel.cropPhoto,
                onRestoreOriginal: viewModel.restoreOriginal,
                onSubmit: handleProcess
            )
        }
        .sheet(isPresented: $viewModel.isShowingPhotoPicker) {
            PhotoPickerView { image in
                viewModel.handleSelectedPhoto(image)
            }
        }
        .alert(viewModel.alertMessage ?? "", isPresented: Binding(
            get: { viewModel.alertMessage != nil },
            set: { _ in viewModel.alertMessage = nil }
        )) {
            Button("确定", role: .cancel) {
                viewModel.alertMessage = nil
            }
        } message: {
            if let message = viewModel.alertMessage {
                Text(message)
            }
        }
    }
    
    private var cameraPreview: some View {
        Group {
            if viewModel.hasCameraPermission && viewModel.isSessionConfigured {
                CameraPreviewHolder(session: viewModel.cameraService.session)
                    .ignoresSafeArea()
            } else {
                Color.black
                    .overlay(permissionOverlay)
                    .ignoresSafeArea()
            }
        }
    }
    
    private var permissionOverlay: some View {
        VStack(spacing: 16) {
            Image(systemName: "camera.fill")
                .font(.system(size: 48))
                .foregroundColor(.white.opacity(0.8))
            Text(viewModel.permissionMessage)
                .font(.headline)
                .foregroundColor(.white)
            if !viewModel.hasCameraPermission {
                Button("前往设置") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 10)
                .background(Color.white.opacity(0.2))
                .cornerRadius(20)
            }
        }
        .padding()
    }
    
    private var overlays: some View {
        VStack {
            topToolbar
            Spacer()
            bottomControls
        }
        .padding()
    }
    
    private var topToolbar: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
                    .background(Color.black.opacity(0.4))
                    .clipShape(Circle())
            }
            Spacer()
        }
    }
    
    private var bottomControls: some View {
        HStack {
            Button {
                viewModel.showPhotoPicker()
            } label: {
                Image(systemName: "photo.on.rectangle")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundColor(.white)
                    .frame(width: Constants.buttonSize, height: Constants.buttonSize)
                    .background(Color.white.opacity(0.15))
                    .clipShape(Circle())
            }
            
            Spacer()
            
            captureButton
                .disabled(!viewModel.canCapturePhoto)
                .opacity(viewModel.canCapturePhoto ? 1 : 0.5)
            
            Spacer()
            
            Button {
                viewModel.switchCamera()
            } label: {
                Image(systemName: "arrow.triangle.2.circlepath.camera")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundColor(.white)
                    .frame(width: Constants.buttonSize, height: Constants.buttonSize)
                    .background(Color.white.opacity(0.15))
                    .clipShape(Circle())
            }
            .disabled(!viewModel.canSwitchCamera)
            .opacity(viewModel.canSwitchCamera ? 1 : 0.4)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
    }
    
    private func handleProcess() {
        Task {
            guard !viewModel.isProcessing else { return }
            if let recognizedText = await viewModel.submitPhoto() {
                onSuccess(recognizedText)
                dismiss()
            }
        }
    }
    
    // MARK: - Helper Views
    
    private var captureButton: some View {
        Button {
            viewModel.takePhoto()
        } label: {
            ZStack {
                Circle()
                    .strokeBorder(Color.white, lineWidth: 5)
                    .frame(width: Constants.captureButtonSize, height: Constants.captureButtonSize)
                Circle()
                    .fill(Color.white)
                    .frame(width: Constants.captureButtonInnerSize, height: Constants.captureButtonInnerSize)
            }
        }
    }
}

// MARK: - Camera preview holder

private struct CameraPreviewHolder: UIViewRepresentable {
    let session: AVCaptureSession
    
    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.videoPreviewLayer.session = session
        view.videoPreviewLayer.videoGravity = .resizeAspectFill
        return view
    }
    
    func updateUIView(_ uiView: PreviewView, context: Context) {
        uiView.videoPreviewLayer.session = session
    }
}

private final class PreviewView: UIView {
    override class var layerClass: AnyClass {
        AVCaptureVideoPreviewLayer.self
    }
    
    var videoPreviewLayer: AVCaptureVideoPreviewLayer {
        layer as! AVCaptureVideoPreviewLayer
    }
}

// MARK: - ViewModel

@MainActor
final class CameraViewModel: NSObject, ObservableObject {
    @Published var photo: CapturedPhoto?
    @Published var isProcessing: Bool = false
    @Published var alertMessage: String?
    @Published var isShowingPreview: Bool = false
    @Published var hasCameraPermission: Bool = true
    @Published var permissionMessage: String = "正在请求相机权限..."
    @Published var isSessionConfigured: Bool = false
    @Published var isShowingPhotoPicker: Bool = false
    
    let cameraService = CameraService()
    private var currentPosition: AVCaptureDevice.Position = .back
    private let onSubmit: (PhotoUploadItem) async throws -> String
    
    init(onSubmit: @escaping (PhotoUploadItem) async throws -> String) {
        self.onSubmit = onSubmit
    }
    
    var canCapturePhoto: Bool {
        hasCameraPermission && isSessionConfigured && !isProcessing
    }
    
    var canSwitchCamera: Bool {
        hasCameraPermission && isSessionConfigured
    }
    
    func activateCamera() {
        Task {
            let granted = await requestCameraPermissionIfNeeded()
            hasCameraPermission = granted
            if granted {
                permissionMessage = "加载相机..."
                await configureSession(position: currentPosition)
            } else {
                permissionMessage = "需要相机权限，请到设置中开启"
            }
        }
    }
    
    func stopCamera() {
        cameraService.stopSession()
    }
    
    func takePhoto() {
        guard canCapturePhoto else {
            alertMessage = "相机不可用"
            return
        }
        cameraService.capturePhoto(delegate: self)
    }
    
    func switchCamera() {
        guard canSwitchCamera else { return }
        let targetPosition: AVCaptureDevice.Position = currentPosition == .back ? .front : .back
        let previousPosition = currentPosition
        currentPosition = targetPosition
        Task {
            await configureSession(position: targetPosition, fallback: previousPosition)
        }
    }
    
    func retakePhoto() {
        photo = nil
        isShowingPreview = false
    }

    /// 按像素矩形裁剪当前预览图（原点在左上角）。始终基于当前显示图裁剪。
    func cropPhoto(_ cropRect: CGRect) {
        guard let cgImage = photo?.image.cgImage else { return }
        let imageBounds = CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height)
        let pixelRect = cropRect.integral.intersection(imageBounds)
        guard pixelRect.width > 0,
              pixelRect.height > 0,
              let croppedImage = cgImage.cropping(to: pixelRect) else { return }
        photo?.image = UIImage(cgImage: croppedImage, scale: 1, orientation: .up)
    }

    /// 恢复拍照原图，供重新框选裁剪。
    func restoreOriginal() {
        guard let original = photo?.originalImage else { return }
        photo?.image = original
    }

    /// 逆时针旋转 90°。框选阶段同步旋转原图；已裁剪后只转当前图。
    func rotatePhoto(updatingOriginal: Bool = true) {
        guard let current = photo,
              let rotatedImage = current.image.rotatedLeft() else { return }
        let newOriginal: UIImage
        if updatingOriginal {
            newOriginal = current.originalImage.rotatedLeft() ?? rotatedImage
        } else {
            newOriginal = current.originalImage
        }
        photo = CapturedPhoto(image: rotatedImage, originalImage: newOriginal)
    }
    
    func showPhotoPicker() {
        isShowingPhotoPicker = true
    }
    
    func handleSelectedPhoto(_ image: UIImage) {
        guard let normalizedImage = image.normalizedForEditing else {
            alertMessage = "图片格式不支持"
            return
        }
        photo = CapturedPhoto(image: normalizedImage)
        isShowingPreview = true
    }
    
    func submitPhoto() async -> String? {
        guard let photo else {
            alertMessage = "请先拍照"
            return nil
        }

        guard let data = photo.currentJpegData else {
            alertMessage = "图片编码失败，请重新拍照"
            return nil
        }

        isProcessing = true
        defer { isProcessing = false }
        let uploadItem = PhotoUploadItem(
            data: data,
            fileName: "photo.jpg",
            mimeType: "image/jpeg"
        )

        do {
            let recognizedText = try await onSubmit(uploadItem)
            guard !recognizedText.isEmpty else {
                alertMessage = "处理失败，请稍后重试"
                return nil
            }
            self.photo = nil
            return recognizedText
        } catch {
            alertMessage = error.localizedDescription
            return nil
        }
    }
    
    private func requestCameraPermissionIfNeeded() async -> Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .authorized:
            return true
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .video) { granted in
                    continuation.resume(returning: granted)
                }
            }
        default:
            return false
        }
    }
    
    private func configureSession(position: AVCaptureDevice.Position, fallback: AVCaptureDevice.Position? = nil) async {
        do {
            try await cameraService.configureSession(position: position)
            isSessionConfigured = true
            permissionMessage = "相机已准备"
        } catch {
            alertMessage = "相机初始化失败：\(error.localizedDescription)"
            isSessionConfigured = false
            if let fallback = fallback {
                currentPosition = fallback
            }
        }
    }
}

// MARK: - Photo model

struct CapturedPhoto {
    /// 当前用于预览/上传的图（可能已被裁剪）
    var image: UIImage
    /// 拍照/选图时的原图，用于「重新裁剪」
    let originalImage: UIImage

    init(image: UIImage) {
        self.image = image
        self.originalImage = image
    }

    init(image: UIImage, originalImage: UIImage) {
        self.image = image
        self.originalImage = originalImage
    }
    
    var currentJpegData: Data? {
        // 上传前降采样，避免超大分辨率照片拖慢云端 OCR / 触发超时。
        image
            .downscaled(maxDimension: Constants.maxUploadDimension)
            .jpegData(compressionQuality: Constants.jpegCompressionQuality)
    }
}

// MARK: - Camera service

final class CameraService {
    let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "words.camera.session")
    private let photoOutput = AVCapturePhotoOutput()
    private var currentInput: AVCaptureDeviceInput?
    private var currentDevice: AVCaptureDevice?
    
    func configureSession(position: AVCaptureDevice.Position) async throws {
        try await withCheckedThrowingContinuation { continuation in
            sessionQueue.async {
                do {
                    try self.setupSession(position: position)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    func stopSession() {
        sessionQueue.async {
            if self.session.isRunning {
                self.session.stopRunning()
            }
        }
    }
    
    func capturePhoto(delegate: AVCapturePhotoCaptureDelegate) {
        sessionQueue.async {
            // 使用高质量设置
            let settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])
            
            // 配置闪光灯
            if self.photoOutput.supportedFlashModes.contains(.auto) {
                settings.flashMode = .auto
            }
            
            if #available(iOS 16.0, *) {
                // maxPhotoDimensions 已在 setupSession 中设置
            } else if self.photoOutput.isHighResolutionCaptureEnabled {
                settings.isHighResolutionPhotoEnabled = true
            }
            
            // 在sessionQueue中调用capturePhoto
            self.photoOutput.capturePhoto(with: settings, delegate: delegate)
        }
    }
    
    private func setupSession(position: AVCaptureDevice.Position) throws {
        session.beginConfiguration()
        session.sessionPreset = .photo
        
        if let currentInput = currentInput {
            session.removeInput(currentInput)
            self.currentInput = nil
        }
        
        guard let device = preferredCaptureDevice(for: position) else {
            session.commitConfiguration()
            throw NSError(domain: "CameraService", code: -1, userInfo: [NSLocalizedDescriptionKey: "无法找到摄像头"])
        }
        
        // 配置自动对焦和曝光，确保照片清晰
        try device.lockForConfiguration()
        
        // 配置对焦模式：优先使用连续自动对焦
        if device.isFocusModeSupported(.continuousAutoFocus) {
            device.focusMode = .continuousAutoFocus
            // 设置对焦点为画面中心
            if device.isFocusPointOfInterestSupported {
                device.focusPointOfInterest = CGPoint(x: 0.5, y: 0.5)
            }
        } else if device.isFocusModeSupported(.autoFocus) {
            device.focusMode = .autoFocus
        }
        
        // 配置曝光模式
        if device.isExposureModeSupported(.continuousAutoExposure) {
            device.exposureMode = .continuousAutoExposure
            // 设置曝光点为画面中心
            if device.isExposurePointOfInterestSupported {
                device.exposurePointOfInterest = CGPoint(x: 0.5, y: 0.5)
            }
        } else if device.isExposureModeSupported(.autoExpose) {
            device.exposureMode = .autoExpose
        }
        
        // 配置白平衡
        if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
            device.whiteBalanceMode = .continuousAutoWhiteBalance
        }
        
        // 启用平滑自动对焦（如果支持）
        if device.isSmoothAutoFocusSupported {
            device.isSmoothAutoFocusEnabled = true
        }
        
        device.unlockForConfiguration()
        
        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else {
            session.commitConfiguration()
            throw NSError(domain: "CameraService", code: -2, userInfo: [NSLocalizedDescriptionKey: "无法添加摄像头输入"])
        }
        session.addInput(input)
        currentInput = input
        currentDevice = device

        // 配置微距：让多摄虚拟设备在近距离自动切换到超广角镜头
        configureMacroIfAvailable(for: device)

        if session.outputs.isEmpty {
            guard session.canAddOutput(photoOutput) else {
                session.commitConfiguration()
                throw NSError(domain: "CameraService", code: -3, userInfo: [NSLocalizedDescriptionKey: "无法添加相机输出"])
            }
            session.addOutput(photoOutput)
            // 使用新的API设置最大照片尺寸（iOS 16.0+）
            if #available(iOS 16.0, *) {
                // 从设备的活动格式中获取支持的最大尺寸
                // 注意：必须在添加output到session之后才能获取支持的尺寸
                let activeFormat = device.activeFormat
                // 获取该格式支持的所有最大照片尺寸
                let supportedDimensions = activeFormat.supportedMaxPhotoDimensions
                if !supportedDimensions.isEmpty {
                    // 选择面积最大的尺寸（宽度 * 高度）
                    let maxDimensions = supportedDimensions.max { dim1, dim2 in
                        let area1 = Int64(dim1.width) * Int64(dim1.height)
                        let area2 = Int64(dim2.width) * Int64(dim2.height)
                        return area1 < area2
                    }
                    if let maxDimensions = maxDimensions {
                        photoOutput.maxPhotoDimensions = maxDimensions
                    }
                }
                // 如果没有找到支持的尺寸，不设置maxPhotoDimensions，让系统使用默认值
            } else {
                // iOS 16.0以下使用旧API
                photoOutput.isHighResolutionCaptureEnabled = true
            }
        }
        
        session.commitConfiguration()
        
        if !session.isRunning {
            session.startRunning()
        }
    }

    /// 选择拍摄设备。后置优先使用支持微距的多摄虚拟设备（三摄 / 双广角），
    /// 系统会在近距离自动切换到超广角镜头实现微距对焦；无多摄时回退到普通广角。
    private func preferredCaptureDevice(for position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        if position == .back {
            let preferredTypes: [AVCaptureDevice.DeviceType] = [
                .builtInTripleCamera,
                .builtInDualWideCamera,
                .builtInWideAngleCamera
            ]
            for type in preferredTypes {
                if let device = AVCaptureDevice.default(type, for: .video, position: .back) {
                    return device
                }
            }
            return nil
        }
        return AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position)
    }

    /// 为多摄虚拟设备开启自动微距，并将初始视野设置为标准广角。
    ///
    /// 多摄虚拟设备（如 `.builtInDualWideCamera` / `.builtInTripleCamera`）默认
    /// `videoZoomFactor = 1.0` 对应超广角镜头。开启自动切换后，当镜头贴近书本、
    /// 超出主广角最小对焦距离时，系统会自动切到超广角镜头对焦，即“微距”效果。
    private func configureMacroIfAvailable(for device: AVCaptureDevice) {
        guard device.isVirtualDevice else { return }
        do {
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }

            if #available(iOS 16.0, *) {
                // 不限制切换条件，允许系统按对焦距离自由切换镜头（含微距）
                device.setPrimaryConstituentDeviceSwitchingBehavior(
                    .auto,
                    restrictedSwitchingBehaviorConditions: []
                )
            }

            // 将初始变焦调到主广角视野，避免默认使用超广角的过宽画面
            if let firstSwitchOver = device.virtualDeviceSwitchOverVideoZoomFactors.first {
                let target = CGFloat(truncating: firstSwitchOver)
                let clamped = min(
                    max(target, device.minAvailableVideoZoomFactor),
                    device.maxAvailableVideoZoomFactor
                )
                device.videoZoomFactor = clamped
            }
        } catch {
            // 微距配置失败时忽略，继续使用默认相机配置
        }
    }
}

// MARK: - Preview View（拍完后先框选文字区域，裁剪后再识别）

private struct PhotoPreviewView: View {
    @Binding var photo: CapturedPhoto?
    let isProcessing: Bool
    let onRetake: () -> Void
    let onRotate: (_ updatingOriginal: Bool) -> Void
    let onCrop: (CGRect) -> Void
    let onRestoreOriginal: () -> Void
    let onSubmit: () -> Void

    /// 归一化裁剪框（相对图片显示区域，0~1）
    @State private var normalizedCropRect = CGRect(x: 0.08, y: 0.12, width: 0.84, height: 0.76)
    /// 已完成裁剪：隐藏选区框，留在本页完整展示裁剪结果并等待识别
    @State private var hasAppliedCrop = false
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                GeometryReader { geometry in
                    if let photo {
                        let imageSize = pixelSize(of: photo.image)
                        let availableSize = CGSize(
                            width: geometry.size.width,
                            height: max(1, geometry.size.height - Constants.bottomButtonHeight)
                        )
                        // 始终 aspectFit：完整显示选区内容，避免 aspectFill 裁掉末行文字
                        let displaySize = aspectFit(imageSize, inside: availableSize)
                        let center = CGPoint(
                            x: geometry.size.width / 2,
                            y: availableSize.height / 2
                        )

                        ZStack {
                            Image(uiImage: photo.image)
                                .resizable()
                                .interpolation(.high)
                                .frame(width: displaySize.width, height: displaySize.height)
                                // 用像素尺寸作 id，裁剪后强制刷新，避免仍显示旧原图帧
                                .id("\(Int(imageSize.width))x\(Int(imageSize.height))-\(hasAppliedCrop)")

                            if !hasAppliedCrop {
                                CropOverlay(
                                    normalizedRect: $normalizedCropRect,
                                    viewSize: displaySize
                                )
                                .frame(width: displaySize.width, height: displaySize.height)
                            }
                        }
                        .frame(width: displaySize.width, height: displaySize.height)
                        .position(center)
                    } else {
                        Text("暂无图片")
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }

                VStack(spacing: 0) {
                    Text(hasAppliedCrop ? "已裁剪，可识别或重新裁剪" : "拖动边角框选文字区域")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color.black.opacity(0.55))
                        .clipShape(Capsule())
                        .padding(.top, 16)

                    Spacer()

                    if photo != nil {
                        previewActions
                            .padding(.horizontal, 16)
                            .padding(.vertical, 20)
                            .background(
                                LinearGradient(
                                    gradient: Gradient(colors: [Color.black.opacity(0.7), Color.black.opacity(0.9)]),
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                    }
                }

                if isProcessing {
                    Color.black.opacity(0.5).ignoresSafeArea()
                    ProgressView("正在识别文字...")
                        .tint(.white)
                        .foregroundColor(.white)
                        .padding(20)
                        .background(Color.black.opacity(0.75))
                        .cornerRadius(12)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private var previewActions: some View {
        HStack(spacing: 16) {
            Button {
                onRetake()
            } label: {
                actionLabel("重拍", systemImage: "camera.fill", color: .white)
            }
            .disabled(isProcessing)

            if hasAppliedCrop {
                Button {
                    beginRecrop()
                } label: {
                    actionLabel("重新裁剪", systemImage: "crop", color: .white)
                }
                .disabled(isProcessing)

                Button {
                    onRotate(false)
                } label: {
                    actionLabel("旋转", systemImage: "rotate.left", color: .white)
                }
                .disabled(isProcessing)

                Button {
                    onSubmit()
                } label: {
                    actionLabel("识别文字", systemImage: "text.viewfinder", color: .green)
                }
                .disabled(isProcessing)
            } else {
                Button {
                    // 框选阶段同步转原图；旋转后重置选框，避免与新方向错位
                    onRotate(true)
                    normalizedCropRect = CGRect(x: 0.08, y: 0.12, width: 0.84, height: 0.76)
                } label: {
                    actionLabel("旋转", systemImage: "rotate.left", color: .white)
                }
                .disabled(isProcessing)

                Button {
                    applyCropAndStay()
                } label: {
                    actionLabel("完成裁剪", systemImage: "crop", color: .green)
                }
                .disabled(isProcessing)
            }
        }
    }

    private func actionLabel(_ title: String, systemImage: String, color: Color) -> some View {
        VStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: 22))
            Text(title)
                .font(.system(size: 12))
        }
        .foregroundColor(color)
        .frame(maxWidth: .infinity)
    }

    /// 只裁剪并留在本页：完整展示裁剪结果（不拉伸、不裁边），等待识别。
    private func applyCropAndStay() {
        guard let image = photo?.image else { return }
        let size = pixelSize(of: image)
        onCrop(CGRect(
            x: normalizedCropRect.minX * size.width,
            y: normalizedCropRect.minY * size.height,
            width: normalizedCropRect.width * size.width,
            height: normalizedCropRect.height * size.height
        ))
        hasAppliedCrop = true
        normalizedCropRect = CGRect(x: 0.05, y: 0.05, width: 0.9, height: 0.9)
    }

    /// 恢复原图并重新进入框选。
    private func beginRecrop() {
        onRestoreOriginal()
        hasAppliedCrop = false
        normalizedCropRect = CGRect(x: 0.08, y: 0.12, width: 0.84, height: 0.76)
    }

    private func pixelSize(of image: UIImage) -> CGSize {
        guard let cgImage = image.cgImage else { return image.size }
        return CGSize(width: cgImage.width, height: cgImage.height)
    }

    private func aspectFit(_ source: CGSize, inside bounds: CGSize) -> CGSize {
        guard source.width > 0, source.height > 0 else { return bounds }
        let scale = min(bounds.width / source.width, bounds.height / source.height)
        return CGSize(width: source.width * scale, height: source.height * scale)
    }
}

// MARK: - Crop Overlay

private struct CropOverlay: View {
    @Binding var normalizedRect: CGRect
    let viewSize: CGSize

    @State private var dragStartRect: CGRect = .zero
    @State private var isDragging = false
    @State private var dragType: DragType = .none

    enum DragType {
        case none
        case move
        case resizeTopLeft
        case resizeTopRight
        case resizeBottomLeft
        case resizeBottomRight
    }

    private let cornerHandleSize = Constants.cornerHandleSize

    private var cropFrame: CGRect {
        CGRect(
            x: normalizedRect.origin.x * viewSize.width,
            y: normalizedRect.origin.y * viewSize.height,
            width: normalizedRect.width * viewSize.width,
            height: normalizedRect.height * viewSize.height
        )
    }

    private var topLeft: CGPoint { CGPoint(x: cropFrame.minX, y: cropFrame.minY) }
    private var topRight: CGPoint { CGPoint(x: cropFrame.maxX, y: cropFrame.minY) }
    private var bottomLeft: CGPoint { CGPoint(x: cropFrame.minX, y: cropFrame.maxY) }
    private var bottomRight: CGPoint { CGPoint(x: cropFrame.maxX, y: cropFrame.maxY) }

    var body: some View {
        ZStack {
            // 半透明遮罩，中间镂空选区
            Color.black.opacity(0.55)
                .overlay(
                    Rectangle()
                        .frame(width: cropFrame.width, height: cropFrame.height)
                        .position(x: cropFrame.midX, y: cropFrame.midY)
                        .blendMode(.destinationOut)
                )
                .compositingGroup()

            Rectangle()
                .stroke(Color.white, lineWidth: 2)
                .frame(width: cropFrame.width, height: cropFrame.height)
                .position(x: cropFrame.midX, y: cropFrame.midY)

            CornerHandle(position: topLeft)
            CornerHandle(position: topRight)
            CornerHandle(position: bottomLeft)
            CornerHandle(position: bottomRight)
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if !isDragging {
                        isDragging = true
                        dragStartRect = normalizedRect
                        dragType = detectDragType(at: value.startLocation)
                    }

                    let deltaX = value.translation.width / max(viewSize.width, 1)
                    let deltaY = value.translation.height / max(viewSize.height, 1)

                    switch dragType {
                    case .move:
                        let newX = max(0, min(1 - dragStartRect.width, dragStartRect.origin.x + deltaX))
                        let newY = max(0, min(1 - dragStartRect.height, dragStartRect.origin.y + deltaY))
                        normalizedRect = CGRect(
                            x: newX,
                            y: newY,
                            width: dragStartRect.width,
                            height: dragStartRect.height
                        )
                    case .resizeTopLeft:
                        normalizedRect = resizeFromTopLeft(startRect: dragStartRect, deltaX: deltaX, deltaY: deltaY)
                    case .resizeTopRight:
                        normalizedRect = resizeFromTopRight(startRect: dragStartRect, deltaX: deltaX, deltaY: deltaY)
                    case .resizeBottomLeft:
                        normalizedRect = resizeFromBottomLeft(startRect: dragStartRect, deltaX: deltaX, deltaY: deltaY)
                    case .resizeBottomRight:
                        normalizedRect = resizeFromBottomRight(startRect: dragStartRect, deltaX: deltaX, deltaY: deltaY)
                    case .none:
                        break
                    }
                }
                .onEnded { _ in
                    isDragging = false
                    dragType = .none
                }
        )
    }

    private func detectDragType(at location: CGPoint) -> DragType {
        // 触控区域略大于视觉手柄，便于手指操作
        let handleRadius: CGFloat = max(cornerHandleSize, 36) / 2

        if distance(location, topLeft) < handleRadius { return .resizeTopLeft }
        if distance(location, topRight) < handleRadius { return .resizeTopRight }
        if distance(location, bottomLeft) < handleRadius { return .resizeBottomLeft }
        if distance(location, bottomRight) < handleRadius { return .resizeBottomRight }
        if cropFrame.contains(location) { return .move }
        return .none
    }

    private func distance(_ p1: CGPoint, _ p2: CGPoint) -> CGFloat {
        hypot(p1.x - p2.x, p1.y - p2.y)
    }

    private func resizeFromTopLeft(startRect: CGRect, deltaX: CGFloat, deltaY: CGFloat) -> CGRect {
        let newX = max(0, min(startRect.maxX - Constants.minCropSize, startRect.origin.x + deltaX))
        let newY = max(0, min(startRect.maxY - Constants.minCropSize, startRect.origin.y + deltaY))
        return CGRect(
            x: newX,
            y: newY,
            width: startRect.maxX - newX,
            height: startRect.maxY - newY
        )
    }

    private func resizeFromTopRight(startRect: CGRect, deltaX: CGFloat, deltaY: CGFloat) -> CGRect {
        let newY = max(0, min(startRect.maxY - Constants.minCropSize, startRect.origin.y + deltaY))
        let newWidth = max(Constants.minCropSize, min(startRect.width + deltaX, 1 - startRect.origin.x))
        return CGRect(
            x: startRect.origin.x,
            y: newY,
            width: newWidth,
            height: startRect.maxY - newY
        )
    }

    private func resizeFromBottomLeft(startRect: CGRect, deltaX: CGFloat, deltaY: CGFloat) -> CGRect {
        let newX = max(0, min(startRect.maxX - Constants.minCropSize, startRect.origin.x + deltaX))
        let newHeight = max(Constants.minCropSize, min(startRect.height + deltaY, 1 - startRect.origin.y))
        return CGRect(
            x: newX,
            y: startRect.origin.y,
            width: startRect.maxX - newX,
            height: newHeight
        )
    }

    private func resizeFromBottomRight(startRect: CGRect, deltaX: CGFloat, deltaY: CGFloat) -> CGRect {
        let newWidth = max(Constants.minCropSize, min(startRect.width + deltaX, 1 - startRect.origin.x))
        let newHeight = max(Constants.minCropSize, min(startRect.height + deltaY, 1 - startRect.origin.y))
        return CGRect(
            x: startRect.origin.x,
            y: startRect.origin.y,
            width: newWidth,
            height: newHeight
        )
    }
}

private struct CornerHandle: View {
    let position: CGPoint

    var body: some View {
        Circle()
            .fill(Color.white)
            .frame(width: Constants.cornerHandleSize, height: Constants.cornerHandleSize)
            .overlay(
                Circle()
                    .stroke(Color.blue, lineWidth: 1.5)
            )
            .position(position)
    }
}

// MARK: - AVCapturePhotoCaptureDelegate

extension CameraViewModel: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error = error {
            alertMessage = "拍照失败：\(error.localizedDescription)"
            return
        }
        
        guard let data = photo.fileDataRepresentation() else {
            alertMessage = "无法读取照片数据"
            return
        }
        
        guard let image = UIImage(data: data)?.normalizedForEditing else {
            alertMessage = "图片格式不支持"
            return
        }
        
        self.photo = CapturedPhoto(image: image)
        isShowingPreview = true
    }
}

// MARK: - Photo Picker View

struct PhotoPickerView: UIViewControllerRepresentable {
    let onSelection: (UIImage) -> Void
    
    func makeUIViewController(context: Context) -> PHPickerViewController {
        var configuration = PHPickerConfiguration()
        configuration.filter = .images
        configuration.selectionLimit = 1
        configuration.preferredAssetRepresentationMode = .current
        
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(onSelection: onSelection)
    }
    
    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let onSelection: (UIImage) -> Void
        
        init(onSelection: @escaping (UIImage) -> Void) {
            self.onSelection = onSelection
        }
        
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            
            guard let provider = results.first?.itemProvider,
                  provider.canLoadObject(ofClass: UIImage.self) else { return }

            provider.loadObject(ofClass: UIImage.self) { [onSelection] object, _ in
                guard let image = object as? UIImage else { return }
                DispatchQueue.main.async {
                    onSelection(image)
                }
            }
        }
    }
}
