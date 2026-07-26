//
//  CameraCaptureView.swift
//  ReadingApp
//
//  Created by GPT-5.1 Codex on 2025/11/27.
//
//  单张拍照组件：拍摄 → 四角框选透视矫正 → 云端识别后返回文字编辑页。

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

    /// 按归一化四边形透视矫正当前预览图（角点顺序：左上→右上→右下→左下）。
    /// - Returns: 是否矫正成功。
    @discardableResult
    func cropPhoto(_ quad: NormalizedQuadCorners) -> Bool {
        guard let image = photo?.image, let cgImage = image.cgImage else { return false }
        let width = CGFloat(cgImage.width)
        let height = CGFloat(cgImage.height)
        let topLeft = CGPoint(x: quad.topLeft.x * width, y: quad.topLeft.y * height)
        let topRight = CGPoint(x: quad.topRight.x * width, y: quad.topRight.y * height)
        let bottomRight = CGPoint(x: quad.bottomRight.x * width, y: quad.bottomRight.y * height)
        let bottomLeft = CGPoint(x: quad.bottomLeft.x * width, y: quad.bottomLeft.y * height)

        guard let corrected = image.perspectiveCorrected(
            topLeft: topLeft,
            topRight: topRight,
            bottomRight: bottomRight,
            bottomLeft: bottomLeft
        ) else {
            alertMessage = "四角选区无效，请调整为不交叉的凸四边形后重试"
            return false
        }
        photo?.image = corrected
        return true
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

// MARK: - 归一化四角（UIKit，原点左上，0~1）

struct NormalizedQuadCorners: Equatable {
    var topLeft: CGPoint
    var topRight: CGPoint
    var bottomRight: CGPoint
    var bottomLeft: CGPoint

    static let `default` = NormalizedQuadCorners(
        topLeft: CGPoint(x: 0.08, y: 0.12),
        topRight: CGPoint(x: 0.92, y: 0.12),
        bottomRight: CGPoint(x: 0.92, y: 0.88),
        bottomLeft: CGPoint(x: 0.08, y: 0.88)
    )

    mutating func clampToUnitSquare() {
        topLeft = Self.clamp(topLeft)
        topRight = Self.clamp(topRight)
        bottomRight = Self.clamp(bottomRight)
        bottomLeft = Self.clamp(bottomLeft)
    }

    private static func clamp(_ p: CGPoint) -> CGPoint {
        CGPoint(x: min(max(p.x, 0), 1), y: min(max(p.y, 0), 1))
    }
}

// MARK: - Preview View（拍完后先框选文字区域，透视矫正后再识别）

private struct PhotoPreviewView: View {
    @Binding var photo: CapturedPhoto?
    let isProcessing: Bool
    let onRetake: () -> Void
    let onRotate: (_ updatingOriginal: Bool) -> Void
    let onCrop: (NormalizedQuadCorners) -> Bool
    let onRestoreOriginal: () -> Void
    let onSubmit: () -> Void

    /// 归一化四角选区（相对图片显示区域）
    @State private var quadCorners = NormalizedQuadCorners.default
    /// 已完成裁剪：隐藏选区框，留在本页完整展示矫正结果并等待识别
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
                                QuadCropOverlay(
                                    corners: $quadCorners,
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
                    Text(hasAppliedCrop ? "已矫正，可识别或重新框选" : "拖动四角框选文字（可拉成梯形）")
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
                    // 框选阶段同步转原图；旋转后重置四角，避免与新方向错位
                    onRotate(true)
                    quadCorners = .default
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

    /// 透视矫正并留在本页：完整展示结果，等待识别。
    private func applyCropAndStay() {
        guard onCrop(quadCorners) else { return }
        hasAppliedCrop = true
        quadCorners = .default
    }

    /// 恢复原图并重新进入框选。
    private func beginRecrop() {
        onRestoreOriginal()
        hasAppliedCrop = false
        quadCorners = .default
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

// MARK: - Quad Crop Overlay（四角独立拖动）

private struct QuadCropOverlay: View {
    @Binding var corners: NormalizedQuadCorners
    let viewSize: CGSize

    @State private var dragStartCorners = NormalizedQuadCorners.default
    @State private var isDragging = false
    @State private var dragType: DragType = .none

    enum DragType {
        case none
        case move
        case topLeft
        case topRight
        case bottomRight
        case bottomLeft
    }

    private let cornerHandleSize = Constants.cornerHandleSize

    private var tl: CGPoint { point(corners.topLeft) }
    private var tr: CGPoint { point(corners.topRight) }
    private var br: CGPoint { point(corners.bottomRight) }
    private var bl: CGPoint { point(corners.bottomLeft) }

    var body: some View {
        ZStack {
            // 半透明遮罩，中间镂空四边形
            Path { path in
                path.addRect(CGRect(origin: .zero, size: viewSize))
                path.move(to: tl)
                path.addLine(to: tr)
                path.addLine(to: br)
                path.addLine(to: bl)
                path.closeSubpath()
            }
            .fill(Color.black.opacity(0.55), style: FillStyle(eoFill: true))

            Path { path in
                path.move(to: tl)
                path.addLine(to: tr)
                path.addLine(to: br)
                path.addLine(to: bl)
                path.closeSubpath()
            }
            .stroke(Color.white, lineWidth: 2)

            CornerHandle(position: tl)
            CornerHandle(position: tr)
            CornerHandle(position: br)
            CornerHandle(position: bl)
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if !isDragging {
                        isDragging = true
                        dragStartCorners = corners
                        dragType = detectDragType(at: value.startLocation)
                    }

                    let deltaX = value.translation.width / max(viewSize.width, 1)
                    let deltaY = value.translation.height / max(viewSize.height, 1)

                    switch dragType {
                    case .topLeft:
                        corners.topLeft = clamped(
                            CGPoint(
                                x: dragStartCorners.topLeft.x + deltaX,
                                y: dragStartCorners.topLeft.y + deltaY
                            )
                        )
                    case .topRight:
                        corners.topRight = clamped(
                            CGPoint(
                                x: dragStartCorners.topRight.x + deltaX,
                                y: dragStartCorners.topRight.y + deltaY
                            )
                        )
                    case .bottomRight:
                        corners.bottomRight = clamped(
                            CGPoint(
                                x: dragStartCorners.bottomRight.x + deltaX,
                                y: dragStartCorners.bottomRight.y + deltaY
                            )
                        )
                    case .bottomLeft:
                        corners.bottomLeft = clamped(
                            CGPoint(
                                x: dragStartCorners.bottomLeft.x + deltaX,
                                y: dragStartCorners.bottomLeft.y + deltaY
                            )
                        )
                    case .move:
                        corners = movedQuad(from: dragStartCorners, deltaX: deltaX, deltaY: deltaY)
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

    private func point(_ normalized: CGPoint) -> CGPoint {
        CGPoint(x: normalized.x * viewSize.width, y: normalized.y * viewSize.height)
    }

    private func clamped(_ p: CGPoint) -> CGPoint {
        CGPoint(x: min(max(p.x, 0), 1), y: min(max(p.y, 0), 1))
    }

    private func detectDragType(at location: CGPoint) -> DragType {
        let handleRadius: CGFloat = max(cornerHandleSize, 40) / 2
        if distance(location, tl) < handleRadius { return .topLeft }
        if distance(location, tr) < handleRadius { return .topRight }
        if distance(location, br) < handleRadius { return .bottomRight }
        if distance(location, bl) < handleRadius { return .bottomLeft }
        if pointInQuad(location, tl: tl, tr: tr, br: br, bl: bl) { return .move }
        return .none
    }

    private func distance(_ p1: CGPoint, _ p2: CGPoint) -> CGFloat {
        hypot(p1.x - p2.x, p1.y - p2.y)
    }

    /// 平移整个四边形，并保证四角仍在 [0,1] 内。
    private func movedQuad(from start: NormalizedQuadCorners, deltaX: CGFloat, deltaY: CGFloat) -> NormalizedQuadCorners {
        let points = [start.topLeft, start.topRight, start.bottomRight, start.bottomLeft]
        let minX = points.map(\.x).min() ?? 0
        let maxX = points.map(\.x).max() ?? 1
        let minY = points.map(\.y).min() ?? 0
        let maxY = points.map(\.y).max() ?? 1
        let clampedDX = min(max(deltaX, -minX), 1 - maxX)
        let clampedDY = min(max(deltaY, -minY), 1 - maxY)
        return NormalizedQuadCorners(
            topLeft: CGPoint(x: start.topLeft.x + clampedDX, y: start.topLeft.y + clampedDY),
            topRight: CGPoint(x: start.topRight.x + clampedDX, y: start.topRight.y + clampedDY),
            bottomRight: CGPoint(x: start.bottomRight.x + clampedDX, y: start.bottomRight.y + clampedDY),
            bottomLeft: CGPoint(x: start.bottomLeft.x + clampedDX, y: start.bottomLeft.y + clampedDY)
        )
    }

    private func pointInQuad(_ p: CGPoint, tl: CGPoint, tr: CGPoint, br: CGPoint, bl: CGPoint) -> Bool {
        // 拆成两个三角形判断
        return pointInTriangle(p, a: tl, b: tr, c: br) || pointInTriangle(p, a: tl, b: br, c: bl)
    }

    private func pointInTriangle(_ p: CGPoint, a: CGPoint, b: CGPoint, c: CGPoint) -> Bool {
        let d1 = sign(p, a, b)
        let d2 = sign(p, b, c)
        let d3 = sign(p, c, a)
        let hasNeg = (d1 < 0) || (d2 < 0) || (d3 < 0)
        let hasPos = (d1 > 0) || (d2 > 0) || (d3 > 0)
        return !(hasNeg && hasPos)
    }

    private func sign(_ p1: CGPoint, _ p2: CGPoint, _ p3: CGPoint) -> CGFloat {
        (p1.x - p3.x) * (p2.y - p3.y) - (p2.x - p3.x) * (p1.y - p3.y)
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
