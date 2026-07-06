//
//  CameraCaptureView.swift
//  ReadingApp
//
//  Created by GPT-5.1 Codex on 2025/11/27.
//
//  通用拍照组件，支持拍照、选择照片、预览、裁剪、旋转等功能
//  使用方式：
//  CameraCaptureView(
//      onSubmit: { uploadItems in
//          // 处理图片上传，返回结果标识符
//          let response = try await YourAPI.analyzeImages(uploadItems)
//          return response.resultId
//      },
//      onSuccess: { resultId in
//          // 处理成功后的逻辑
//          print("处理成功，结果ID: \(resultId)")
//      }
//  )

import SwiftUI
import AVFoundation
import UIKit
import PhotosUI
import Combine

// MARK: - Constants

private enum Constants {
    static let jpegCompressionQuality: CGFloat = 0.9
    static let buttonSize: CGFloat = 60
    static let captureButtonSize: CGFloat = 80
    static let captureButtonInnerSize: CGFloat = 64
    static let thumbnailSize: CGFloat = 90
    static let cornerHandleSize: CGFloat = 20
    static let minCropSize: CGFloat = 0.05
    static let bottomButtonHeight: CGFloat = 100
}

// MARK: - Camera Capture View

struct CameraCaptureView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: CameraViewModel
    
    /// 提交图片的回调函数
    /// - Parameter uploadItems: 要上传的图片数据
    /// - Returns: 成功时返回结果标识符（如文章ID），失败时返回 nil
    let onSubmit: ([PhotoUploadItem]) async throws -> String?
    
    /// 提交成功后的回调
    /// - Parameter resultId: 提交成功后返回的标识符
    let onSuccess: (String) -> Void
    
    /// 初始化通用拍照组件
    /// - Parameters:
    ///   - onSubmit: 提交图片的处理函数，接收图片数据并返回结果标识符
    ///   - onSuccess: 提交成功后的回调，接收结果标识符
    init(
        onSubmit: @escaping ([PhotoUploadItem]) async throws -> String?,
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
            
            if viewModel.isProcessing {
                Color.black.opacity(0.45)
                    .ignoresSafeArea()
                ProgressView("正在处理图片...")
                    .padding(20)
                    .background(Color.black.opacity(0.7))
                    .cornerRadius(12)
                    .foregroundColor(.white)
            }
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
                photos: $viewModel.photos,
                currentIndex: $viewModel.previewIndex,
                onContinueCapture: {
                    viewModel.isShowingPreview = false
                },
                onDelete: { index in
                    viewModel.deletePhoto(at: index)
                },
                onRetake: { index in
                    viewModel.retakePhoto(at: index)
                },
                onRotate: { index in
                    viewModel.rotatePhoto(at: index)
                },
                onCrop: { index, cropRect in
                    viewModel.cropPhoto(at: index, cropRect: cropRect)
                },
                onRestore: { index in
                    viewModel.restorePhoto(at: index)
                },
                onSubmit: {
                    handleProcess()
                }
            )
        }
        .sheet(isPresented: $viewModel.isShowingPhotoPicker) {
            PhotoPickerView { images in
                viewModel.handleSelectedPhotos(images)
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
            cameraControlsOverlay
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
    
    private var cameraControlsOverlay: some View {
        HStack {
            Spacer()
            if viewModel.photoCount > 0 {
                VStack(alignment: .trailing, spacing: 16) {
                    Button {
                        viewModel.showPreview()
                    } label: {
                        ZStack(alignment: .topTrailing) {
                            if let image = viewModel.lastPhotoImage {
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 90, height: 90)
                                    .clipped()
                                    .cornerRadius(12)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(Color.cyan, lineWidth: 2)
                                    )
                            } else {
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.white.opacity(0.2))
                                    .frame(width: 90, height: 90)
                                    .overlay(
                                        Image(systemName: "photo")
                                            .foregroundColor(.white)
                                    )
                            }
                            
                            Text("\(viewModel.photoCount)")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                                .padding(6)
                                .background(Color.red)
                                .clipShape(Circle())
                                .offset(x: 6, y: -6)
                        }
                    }
                    
                    Button {
                        handleProcess()
                    } label: {
                        Text("处理图片")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.white)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 10)
                            .background(Color.cyan)
                            .cornerRadius(20)
                    }
                    .disabled(viewModel.isProcessing)
                    .opacity(viewModel.isProcessing ? 0.6 : 1)
                }
                .transition(.opacity)
            }
        }
    }
    
    private var bottomControls: some View {
        HStack {
            // 相册按钮 - 左边
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
            
            // 拍照按钮 - 中间
            captureButton
                .disabled(!viewModel.canCapturePhoto)
                .opacity(viewModel.canCapturePhoto ? 1 : 0.5)
            
            Spacer()
            
            // 旋转镜头按钮 - 右边
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
            if let resultId = await viewModel.submitPhotos() {
                onSuccess(resultId)
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
    @Published var photos: [CapturedPhoto] = []
    @Published var isProcessing: Bool = false
    @Published var alertMessage: String?
    @Published var isShowingPreview: Bool = false
    @Published var previewIndex: Int = 0
    @Published var hasCameraPermission: Bool = true
    @Published var permissionMessage: String = "正在请求相机权限..."
    @Published var isSessionConfigured: Bool = false
    @Published var isShowingPhotoPicker: Bool = false
    
    let cameraService = CameraService()
    private var currentPosition: AVCaptureDevice.Position = .back
    private var retakeIndex: Int? = nil  // 标记需要重拍的照片索引
    
    /// 提交图片的处理函数
    private let onSubmit: ([PhotoUploadItem]) async throws -> String?
    
    init(onSubmit: @escaping ([PhotoUploadItem]) async throws -> String?) {
        self.onSubmit = onSubmit
    }
    
    var photoCount: Int {
        photos.count
    }
    
    var lastPhotoImage: UIImage? {
        photos.last?.image
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
    
    func showPreview() {
        previewIndex = 0
        isShowingPreview = true
    }
    
    func deletePhoto(at index: Int) {
        guard photos.indices.contains(index) else { return }
        photos.remove(at: index)
        if previewIndex >= photos.count {
            previewIndex = max(photos.count - 1, 0)
        }
        if photos.isEmpty {
            isShowingPreview = false
        }
    }
    
    func retakePhoto(at index: Int) {
        guard photos.indices.contains(index) else { return }
        // 标记需要重拍的照片索引，关闭预览，让用户拍照
        retakeIndex = index
        isShowingPreview = false
    }
    
    func rotatePhoto(at index: Int) {
        guard photos.indices.contains(index) else { return }
        photos[index].rotationAngle = (photos[index].rotationAngle + 90).truncatingRemainder(dividingBy: 360)
        // 更新图片和 JPEG 数据
        if let rotatedImage = photos[index].image.rotated(by: photos[index].rotationAngle) {
            photos[index].image = rotatedImage
            photos[index].rotationAngle = 0  // 重置角度，因为图片已经旋转
            if let newJpegData = rotatedImage.jpegData(compressionQuality: 0.9) {
                photos[index].jpegData = newJpegData
            }
        }
    }
    
    func restorePhoto(at index: Int) {
        guard photos.indices.contains(index) else { return }
        let originalImg = photos[index].originalImage
        photos[index].image = originalImg
        photos[index].rotationAngle = 0
        updateJpegData(for: index, image: originalImg)
    }
    
    func cropPhoto(at index: Int, cropRect: CGRect) {
        guard photos.indices.contains(index) else { return }
        let photo = photos[index]
        // 使用原始图片进行裁剪
        let originalImg = photo.originalImage
        
        guard let cgImage = originalImg.cgImage else { return }
        let cgImageWidth = CGFloat(cgImage.width)
        let cgImageHeight = CGFloat(cgImage.height)
        
        // cropRect 已经是相对于CGImage实际尺寸的坐标（已经经过比例计算）
        // 确保裁剪区域在图片范围内，并转换为整数像素
        let clampedRect = CGRect(
            x: floor(max(0, min(cropRect.origin.x, cgImageWidth - 1))),
            y: floor(max(0, min(cropRect.origin.y, cgImageHeight - 1))),
            width: ceil(max(1, min(cropRect.width, cgImageWidth - max(0, cropRect.origin.x)))),
            height: ceil(max(1, min(cropRect.height, cgImageHeight - max(0, cropRect.origin.y))))
        )
        
        // 使用CGImage进行裁剪，坐标系是左上角为原点
        // CGImage的坐标需要是整数，并且需要考虑scale
        let scale = originalImg.scale
        let cgCropRect = CGRect(
            x: floor(clampedRect.origin.x * scale),
            y: floor(clampedRect.origin.y * scale),
            width: ceil(clampedRect.width * scale),
            height: ceil(clampedRect.height * scale)
        )
        
        // 确保裁剪区域不超出CGImage边界
        let finalCgCropRect = CGRect(
            x: max(0, min(cgCropRect.origin.x, CGFloat(cgImage.width) - 1)),
            y: max(0, min(cgCropRect.origin.y, CGFloat(cgImage.height) - 1)),
            width: max(1, min(cgCropRect.width, CGFloat(cgImage.width) - max(0, cgCropRect.origin.x))),
            height: max(1, min(cgCropRect.height, CGFloat(cgImage.height) - max(0, cgCropRect.origin.y)))
        )
        
        guard let croppedCGImage = cgImage.cropping(to: finalCgCropRect) else {
            return
        }
        
        // 创建裁剪后的UIImage，保持原始orientation，不旋转
        let croppedUIImage = UIImage(cgImage: croppedCGImage, scale: originalImg.scale, orientation: originalImg.imageOrientation)
        
        photos[index].image = croppedUIImage
        photos[index].rotationAngle = 0
        updateJpegData(for: index, image: croppedUIImage)
    }
    
    func showPhotoPicker() {
        isShowingPhotoPicker = true
    }
    
    func handleSelectedPhotos(_ images: [UIImage]) {
        for image in images {
            guard let jpegData = image.jpegData(compressionQuality: Constants.jpegCompressionQuality) else {
                continue
            }
            photos.append(CapturedPhoto(image: image, jpegData: jpegData, timestamp: Date()))
        }
    }
    
    private func updateJpegData(for index: Int, image: UIImage) {
        if let newJpegData = image.jpegData(compressionQuality: Constants.jpegCompressionQuality) {
            photos[index].jpegData = newJpegData
        }
    }
    
    func submitPhotos() async -> String? {
        guard !photos.isEmpty else {
            alertMessage = "请先拍照"
            return nil
        }
        
        isProcessing = true
        let orderedPhotos = photos.sorted { $0.timestamp < $1.timestamp }
        let uploadItems = orderedPhotos.enumerated().map { index, photo in
            PhotoUploadItem(
                data: photo.currentJpegData,  // 使用编辑后的图片数据
                fileName: "photo_\(index + 1).jpg",
                mimeType: "image/jpeg"
            )
        }
        
        do {
            let resultId = try await onSubmit(uploadItems)
            isProcessing = false
            guard let resultId = resultId, !resultId.isEmpty else {
                alertMessage = "处理失败，请稍后重试"
                return nil
            }
            photos.removeAll()
            return resultId
        } catch {
            isProcessing = false
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

struct CapturedPhoto: Identifiable, Equatable {
    let id = UUID()
    var image: UIImage
    var jpegData: Data
    let timestamp: Date
    var rotationAngle: CGFloat = 0  // 旋转角度（度）
    let originalImage: UIImage  // 保存原始图片，用于重新裁剪
    
    init(image: UIImage, jpegData: Data, timestamp: Date) {
        self.image = image
        self.jpegData = jpegData
        self.timestamp = timestamp
        self.originalImage = image  // 保存原始图片
    }
    
    // 获取当前显示的图片（考虑旋转）
    var displayImage: UIImage {
        if rotationAngle == 0 {
            return image
        }
        return image.rotated(by: rotationAngle) ?? image
    }
    
    // 检查图片是否被裁剪过
    var isCropped: Bool {
        // 比较当前图片和原始图片的尺寸
        let currentSize = image.size
        let originalSize = originalImage.size
        // 如果尺寸不同，说明被裁剪过
        return abs(currentSize.width - originalSize.width) > 0.1 || 
               abs(currentSize.height - originalSize.height) > 0.1
    }
    
    var currentJpegData: Data {
        displayImage.jpegData(compressionQuality: Constants.jpegCompressionQuality) ?? jpegData
    }
    
    static func == (lhs: CapturedPhoto, rhs: CapturedPhoto) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - UIImage Extension for Rotation

extension UIImage {
    func rotated(by degrees: CGFloat) -> UIImage? {
        let radians = degrees * .pi / 180
        let rotatedSize = CGRect(origin: .zero, size: size)
            .applying(CGAffineTransform(rotationAngle: radians))
            .integral.size
        
        UIGraphicsBeginImageContextWithOptions(rotatedSize, false, scale)
        defer { UIGraphicsEndImageContext() }
        
        guard let context = UIGraphicsGetCurrentContext() else { return nil }
        
        context.translateBy(x: rotatedSize.width / 2, y: rotatedSize.height / 2)
        context.rotate(by: radians)
        draw(in: CGRect(origin: CGPoint(x: -size.width / 2, y: -size.height / 2), size: size))
        
        return UIGraphicsGetImageFromCurrentImageContext()
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
        
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position) else {
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
}

// MARK: - Preview View

private struct PhotoPreviewView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var photos: [CapturedPhoto]
    @Binding var currentIndex: Int
    let onContinueCapture: () -> Void
    let onDelete: (Int) -> Void
    let onRetake: (Int) -> Void
    let onRotate: (Int) -> Void
    let onCrop: (Int, CGRect) -> Void
    let onRestore: (Int) -> Void
    let onSubmit: () -> Void
    
    @State private var isShowingCropView = false
    @State private var internalIndex: Int = 0
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                if photos.isEmpty {
                    Text("暂无图片")
                        .foregroundColor(.white)
                } else {
                    TabView(selection: $internalIndex) {
                        ForEach(Array(photos.indices), id: \.self) { index in
                            let photo = photos[index]
                            GeometryReader { geometry in
                                VStack(spacing: 0) {
                                    Spacer()
                                    
                                    // 图片预览区域 - 使用scaledToFit与CropImageView保持一致
                                    Image(uiImage: photo.displayImage)
                                        .resizable()
                                        .scaledToFit()
                                        .tag(index)
                                        .padding(.horizontal, 16)
                                    
                                    // 删除和还原按钮 - 在图片下方，水平居中
                                    HStack(spacing: 20) {
                                        // 还原按钮（仅在图片被裁剪时显示）
                                        if photo.isCropped {
                                            Button {
                                                onRestore(index)
                                            } label: {
                                                Image(systemName: "arrow.counterclockwise")
                                                    .font(.system(size: 18, weight: .medium))
                                                    .foregroundColor(.white)
                                                    .frame(width: 44, height: 44)
                                                    .background(Color.blue.opacity(0.8))
                                                    .clipShape(Circle())
                                            }
                                        }
                                        
                                        // 删除按钮
                                        Button {
                                            onDelete(index)
                                        } label: {
                                            Image(systemName: "trash")
                                                .font(.system(size: 18, weight: .medium))
                                                .foregroundColor(.white)
                                                .frame(width: 44, height: 44)
                                                .background(Color.red.opacity(0.8))
                                                .clipShape(Circle())
                                        }
                                    }
                                    .padding(.top, 16)
                                    
                                    Spacer()
                                }
                                .frame(width: geometry.size.width, height: geometry.size.height)
                            }
                        }
                    }
                    .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
                    .onChange(of: internalIndex) { oldValue, newValue in
                        // 当用户滑动时，同步更新外部索引
                        if newValue != currentIndex {
                            currentIndex = newValue
                        }
                    }
                    .onChange(of: currentIndex) { oldValue, newValue in
                        // 当外部索引变化时，同步更新内部索引
                        if newValue != internalIndex && newValue >= 0 && newValue < photos.count {
                            internalIndex = newValue
                        }
                    }
                    .onAppear {
                        // 初始化内部索引
                        internalIndex = currentIndex
                    }
                }
                
                VStack {
                    // 顶部工具栏
                    HStack {
                        // 左上角：继续拍照按钮
                        Button {
                            onContinueCapture()
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "camera.fill")
                                    .font(.system(size: 14, weight: .medium))
                                Text("继续拍")
                                    .font(.system(size: 15, weight: .medium))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Color.green.opacity(0.8))
                            .cornerRadius(20)
                            .overlay(
                                RoundedRectangle(cornerRadius: 20)
                                    .stroke(Color.green, lineWidth: 1.5)
                            )
                        }
                        
                        Spacer()
                        
                        // 右上角：页码显示
                        if !photos.isEmpty {
                            Text("\(internalIndex + 1) / \(photos.count)")
                                .foregroundColor(.white)
                                .font(.system(size: 16, weight: .medium))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.black.opacity(0.4))
                                .cornerRadius(12)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 20)
                    
                    Spacer()
                    
                    // 底部工具条
                    if !photos.isEmpty {
                        HStack(spacing: 20) {
                            // 重拍这张
                            Button {
                                onRetake(internalIndex)
                            } label: {
                                VStack(spacing: 6) {
                                    Image(systemName: "camera.fill")
                                        .font(.system(size: 22))
                                    Text("重拍这张")
                                        .font(.system(size: 12))
                                }
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                            }
                            
                            // 旋转照片
                            Button {
                                onRotate(internalIndex)
                            } label: {
                                VStack(spacing: 6) {
                                    Image(systemName: "rotate.left")
                                        .font(.system(size: 22))
                                    Text("左转")
                                        .font(.system(size: 12))
                                }
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                            }
                            
                            // 裁剪
                            Button {
                                isShowingCropView = true
                            } label: {
                                VStack(spacing: 6) {
                                    Image(systemName: "crop")
                                        .font(.system(size: 22))
                                    Text("裁剪")
                                        .font(.system(size: 12))
                                }
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                            }
                            
                            // 提交按钮
                            Button {
                                onSubmit()
                            } label: {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 32))
                                    .foregroundColor(.green)
                                    .frame(maxWidth: .infinity)
                            }
                        }
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
            }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $isShowingCropView) {
                if photos.indices.contains(internalIndex) {
                    // 显示当前图片（displayImage），但裁剪时使用原始图片
                    CropImageView(
                        displayImage: photos[internalIndex].displayImage,
                        originalImage: photos[internalIndex].originalImage,
                        onCrop: { cropRect in
                            onCrop(internalIndex, cropRect)
                            isShowingCropView = false
                        },
                        onCancel: {
                            isShowingCropView = false
                        }
                    )
                }
            }
        }
    }
}

// MARK: - Crop Image View

private struct CropImageView: View {
    let displayImage: UIImage  // 用于显示的图片（与PhotoPreviewView一致）
    let originalImage: UIImage  // 原始图片，用于裁剪计算
    let onCrop: (CGRect) -> Void
    let onCancel: () -> Void
    
    @State private var normalizedCropRect = CGRect(x: 0.1, y: 0.1, width: 0.8, height: 0.8)
    @State private var viewSize: CGSize = .zero
    
    // 获取显示图片的CGImage尺寸（用于计算显示比例）
    private var displayCgImageSize: CGSize {
        guard let cgImage = displayImage.cgImage else {
            return displayImage.size
        }
        return CGSize(width: cgImage.width, height: cgImage.height)
    }
    
    // 获取原始图片CGImage的实际尺寸（不受orientation影响），用于裁剪计算
    private var originalCgImageSize: CGSize {
        guard let cgImage = originalImage.cgImage else {
            return originalImage.size
        }
        return CGSize(width: cgImage.width, height: cgImage.height)
    }
    
    private let bottomButtonHeight = Constants.bottomButtonHeight
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                
                GeometryReader { geometry in
                    let totalSize = geometry.size
                    let imageAreaHeight = totalSize.height - bottomButtonHeight
                    let imageArea = CGSize(width: totalSize.width, height: imageAreaHeight)
                    
                    VStack(spacing: 0) {
                        // 图片显示区域（让出底部按钮位置）
                        ZStack {
                            // 图片使用scaledToFit与PhotoPreviewView保持一致
                            Image(uiImage: displayImage)
                                .resizable()
                                .scaledToFit()
                                .frame(width: imageArea.width, height: imageArea.height)
                                .clipped()
                            
                            // 裁剪框覆盖层
                            // 使用originalImage的尺寸，确保与裁剪计算一致
                            CropOverlay(
                                normalizedRect: $normalizedCropRect,
                                imageSize: originalCgImageSize,
                                viewSize: imageArea
                            )
                        }
                        .frame(height: imageArea.height)
                        .onAppear {
                            viewSize = totalSize
                        }
                        .onChange(of: totalSize) { _, newSize in
                            viewSize = newSize
                        }
                        
                        // 底部按钮区域
                        Spacer()
                            .frame(height: bottomButtonHeight)
                    }
                }
                
                VStack {
                    Spacer()
                    
                    HStack(spacing: 20) {
                        Button("取消") {
                            onCancel()
                        }
                        .foregroundColor(.white)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.gray.opacity(0.6))
                        .cornerRadius(12)
                        
                        Button("完成") {
                            let finalCropRect = calculateCropRect(
                                normalizedRect: normalizedCropRect,
                                viewSize: viewSize,
                                displayCgSize: displayCgImageSize,
                                originalCgSize: originalCgImageSize
                            )
                            onCrop(finalCropRect)
                        }
                        .foregroundColor(.white)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.green)
                        .cornerRadius(12)
                    }
                    .padding()
                    .frame(height: bottomButtonHeight)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("裁剪图片")
                        .foregroundColor(.white)
                }
            }
        }
    }
    
    // MARK: - Crop Calculation
    
    private func calculateCropRect(
        normalizedRect: CGRect,
        viewSize: CGSize,
        displayCgSize: CGSize,
        originalCgSize: CGSize
    ) -> CGRect {
        let imageAreaHeight = viewSize.height - bottomButtonHeight
        let imageArea = CGSize(width: viewSize.width, height: imageAreaHeight)
        
        let displayWidth = displayCgSize.width
        let displayHeight = displayCgSize.height
        let originalWidth = originalCgSize.width
        let originalHeight = originalCgSize.height
        
        let isRotated90 = abs(displayWidth - originalHeight) < 0.1 && abs(displayHeight - originalWidth) < 0.1
        let displayAspect = displayWidth / displayHeight
        let viewAspect = imageArea.width / imageArea.height
        
        let (imageDisplaySize, imageDisplayOffset) = calculateImageDisplaySize(
            imageArea: imageArea,
            displayAspect: displayAspect,
            viewAspect: viewAspect
        )
        
        let cropInView = CGRect(
            x: normalizedRect.origin.x * imageArea.width,
            y: normalizedRect.origin.y * imageArea.height,
            width: normalizedRect.width * imageArea.width,
            height: normalizedRect.height * imageArea.height
        )
        
        let cropInDisplayImage = CGRect(
            x: cropInView.origin.x - imageDisplayOffset.x,
            y: cropInView.origin.y - imageDisplayOffset.y,
            width: cropInView.width,
            height: cropInView.height
        )
        
        let clampedCrop = clampRect(cropInDisplayImage, to: imageDisplaySize)
        let cropRatioInDisplay = CGRect(
            x: clampedCrop.origin.x / imageDisplaySize.width,
            y: clampedCrop.origin.y / imageDisplaySize.height,
            width: clampedCrop.width / imageDisplaySize.width,
            height: clampedCrop.height / imageDisplaySize.height
        )
        
        let cropRatioInOriginal = isRotated90
            ? transformCropRatioForRotation(cropRatioInDisplay)
            : cropRatioInDisplay
        
        let actualCropRect = CGRect(
            x: cropRatioInOriginal.origin.x * originalWidth,
            y: cropRatioInOriginal.origin.y * originalHeight,
            width: cropRatioInOriginal.width * originalWidth,
            height: cropRatioInOriginal.height * originalHeight
        )
        
        return clampRect(actualCropRect, to: originalCgSize, useIntegers: true)
    }
    
    private func calculateImageDisplaySize(
        imageArea: CGSize,
        displayAspect: CGFloat,
        viewAspect: CGFloat
    ) -> (size: CGSize, offset: CGPoint) {
        if displayAspect > viewAspect {
            let size = CGSize(width: imageArea.width, height: imageArea.width / displayAspect)
            let offset = CGPoint(x: 0, y: (imageArea.height - size.height) / 2)
            return (size, offset)
        } else {
            let size = CGSize(width: imageArea.height * displayAspect, height: imageArea.height)
            let offset = CGPoint(x: (imageArea.width - size.width) / 2, y: 0)
            return (size, offset)
        }
    }
    
    private func transformCropRatioForRotation(_ ratio: CGRect) -> CGRect {
        CGRect(
            x: 1.0 - (ratio.origin.y + ratio.height),
            y: ratio.origin.x,
            width: ratio.height,
            height: ratio.width
        )
    }
    
    private func clampRect(_ rect: CGRect, to bounds: CGSize, useIntegers: Bool = false) -> CGRect {
        let x = max(0, min(rect.origin.x, bounds.width - 1))
        let y = max(0, min(rect.origin.y, bounds.height - 1))
        let width = max(1, min(rect.width, bounds.width - max(0, rect.origin.x)))
        let height = max(1, min(rect.height, bounds.height - max(0, rect.origin.y)))
        
        if useIntegers {
            return CGRect(
                x: floor(x),
                y: floor(y),
                width: ceil(width),
                height: ceil(height)
            )
        }
        return CGRect(x: x, y: y, width: width, height: height)
    }
}

// MARK: - Crop Overlay

private struct CropOverlay: View {
    @Binding var normalizedRect: CGRect
    let imageSize: CGSize  // CGImage的实际尺寸
    let viewSize: CGSize   // 图片显示区域的尺寸（已减去底部按钮高度）
    
    @State private var dragStart: CGPoint = .zero
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
    
    // 计算裁剪框在视图中的实际位置和大小
    // 由于图片使用scaledToFill，裁剪框直接基于视图尺寸
    private var cropFrame: CGRect {
        return CGRect(
            x: normalizedRect.origin.x * viewSize.width,
            y: normalizedRect.origin.y * viewSize.height,
            width: normalizedRect.width * viewSize.width,
            height: normalizedRect.height * viewSize.height
        )
    }
    
    // 获取四个角落的位置
    private var topLeft: CGPoint {
        CGPoint(x: cropFrame.minX, y: cropFrame.minY)
    }
    
    private var topRight: CGPoint {
        CGPoint(x: cropFrame.maxX, y: cropFrame.minY)
    }
    
    private var bottomLeft: CGPoint {
        CGPoint(x: cropFrame.minX, y: cropFrame.maxY)
    }
    
    private var bottomRight: CGPoint {
        CGPoint(x: cropFrame.maxX, y: cropFrame.maxY)
    }
    
    // 检测点击位置是否在某个角落附近
    private func detectDragType(at location: CGPoint) -> DragType {
        let handleRadius: CGFloat = cornerHandleSize / 2
        
        if distance(location, topLeft) < handleRadius {
            return .resizeTopLeft
        } else if distance(location, topRight) < handleRadius {
            return .resizeTopRight
        } else if distance(location, bottomLeft) < handleRadius {
            return .resizeBottomLeft
        } else if distance(location, bottomRight) < handleRadius {
            return .resizeBottomRight
        } else if cropFrame.contains(location) {
            return .move
        }
        return .none
    }
    
    private func distance(_ p1: CGPoint, _ p2: CGPoint) -> CGFloat {
        sqrt(pow(p1.x - p2.x, 2) + pow(p1.y - p2.y, 2))
    }
    
    private func resizeFromTopLeft(startRect: CGRect, deltaX: CGFloat, deltaY: CGFloat) -> CGRect {
        let newX = max(0, min(startRect.maxX - Constants.minCropSize, startRect.origin.x + deltaX))
        let newY = max(0, min(startRect.maxY - Constants.minCropSize, startRect.origin.y + deltaY))
        let newWidth = startRect.maxX - newX
        let newHeight = startRect.maxY - newY
        return CGRect(
            x: newX,
            y: newY,
            width: max(Constants.minCropSize, min(newWidth, 1 - newX)),
            height: max(Constants.minCropSize, min(newHeight, 1 - newY))
        )
    }
    
    private func resizeFromTopRight(startRect: CGRect, deltaX: CGFloat, deltaY: CGFloat) -> CGRect {
        let newY = max(0, min(startRect.maxY - Constants.minCropSize, startRect.origin.y + deltaY))
        let newWidth = max(Constants.minCropSize, min(startRect.width + deltaX, 1 - startRect.origin.x))
        let newHeight = startRect.maxY - newY
        return CGRect(
            x: startRect.origin.x,
            y: newY,
            width: newWidth,
            height: max(Constants.minCropSize, min(newHeight, 1 - newY))
        )
    }
    
    private func resizeFromBottomLeft(startRect: CGRect, deltaX: CGFloat, deltaY: CGFloat) -> CGRect {
        let newX = max(0, min(startRect.maxX - Constants.minCropSize, startRect.origin.x + deltaX))
        let newWidth = startRect.maxX - newX
        let newHeight = max(Constants.minCropSize, min(startRect.height + deltaY, 1 - startRect.origin.y))
        return CGRect(
            x: newX,
            y: startRect.origin.y,
            width: max(Constants.minCropSize, min(newWidth, 1 - newX)),
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
    
    var body: some View {
        ZStack {
            // 半透明遮罩（裁剪区域外）
            Color.black.opacity(0.6)
                .mask(
                    Rectangle()
                        .fill(Color.white)
                        .blendMode(.destinationOut)
                        .frame(width: cropFrame.width, height: cropFrame.height)
                        .position(x: cropFrame.midX, y: cropFrame.midY)
                )
            
            // 裁剪框边框
            Rectangle()
                .stroke(Color.white, lineWidth: 2)
                .frame(width: cropFrame.width, height: cropFrame.height)
                .position(x: cropFrame.midX, y: cropFrame.midY)
            
            // 四个角落的控制点
            CornerHandle(position: topLeft)
            CornerHandle(position: topRight)
            CornerHandle(position: bottomLeft)
            CornerHandle(position: bottomRight)
        }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if !isDragging {
                        isDragging = true
                        dragStart = value.startLocation
                        dragStartRect = normalizedRect
                        dragType = detectDragType(at: value.startLocation)
                    }
                    
                    // 计算移动距离（归一化，相对于视图尺寸）
                    let deltaX = value.translation.width / viewSize.width
                    let deltaY = value.translation.height / viewSize.height
                    
                    switch dragType {
                    case .move:
                        // 移动整个裁剪框
                        let newX = max(0, min(1 - dragStartRect.width, dragStartRect.origin.x + deltaX))
                        let newY = max(0, min(1 - dragStartRect.height, dragStartRect.origin.y + deltaY))
                        normalizedRect.origin.x = newX
                        normalizedRect.origin.y = newY
                        normalizedRect.size = dragStartRect.size
                        
                    case .resizeTopLeft:
                        normalizedRect = resizeFromTopLeft(
                            startRect: dragStartRect,
                            deltaX: deltaX,
                            deltaY: deltaY
                        )
                    case .resizeTopRight:
                        normalizedRect = resizeFromTopRight(
                            startRect: dragStartRect,
                            deltaX: deltaX,
                            deltaY: deltaY
                        )
                    case .resizeBottomLeft:
                        normalizedRect = resizeFromBottomLeft(
                            startRect: dragStartRect,
                            deltaX: deltaX,
                            deltaY: deltaY
                        )
                    case .resizeBottomRight:
                        normalizedRect = resizeFromBottomRight(
                            startRect: dragStartRect,
                            deltaX: deltaX,
                            deltaY: deltaY
                        )
                        
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
}

// MARK: - Corner Handle

private struct CornerHandle: View {
    let position: CGPoint
    
    var body: some View {
        Circle()
            .fill(Color.white)
            .frame(width: 20, height: 20)
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
        
        guard let image = UIImage(data: data),
              let jpegData = image.jpegData(compressionQuality: Constants.jpegCompressionQuality) else {
            alertMessage = "图片格式不支持"
            return
        }
        
        let captured = CapturedPhoto(image: image, jpegData: jpegData, timestamp: Date())
        
        // 如果标记了重拍索引，替换对应照片；否则追加新照片
        if let retakeIdx = retakeIndex, photos.indices.contains(retakeIdx) {
            photos[retakeIdx] = captured
            retakeIndex = nil
            // 重拍后自动打开预览
            previewIndex = retakeIdx
            isShowingPreview = true
        } else {
            photos.append(captured)
        }
    }
}

// MARK: - Photo Picker View

struct PhotoPickerView: UIViewControllerRepresentable {
    let onSelection: ([UIImage]) -> Void
    
    func makeUIViewController(context: Context) -> PHPickerViewController {
        var configuration = PHPickerConfiguration()
        configuration.filter = .images
        configuration.selectionLimit = 0 // 0 表示无限制
        configuration.preferredAssetRepresentationMode = .current
        
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {
        // 不需要更新
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(onSelection: onSelection)
    }
    
    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let onSelection: ([UIImage]) -> Void
        
        init(onSelection: @escaping ([UIImage]) -> Void) {
            self.onSelection = onSelection
        }
        
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            
            guard !results.isEmpty else {
                return
            }
            
            let group = DispatchGroup()
            var images: [UIImage] = []
            
            for result in results {
                group.enter()
                if result.itemProvider.canLoadObject(ofClass: UIImage.self) {
                    result.itemProvider.loadObject(ofClass: UIImage.self) { object, _ in
                        defer { group.leave() }
                        if let image = object as? UIImage {
                            images.append(image)
                        }
                    }
                } else {
                    group.leave()
                }
            }
            
            group.notify(queue: .main) {
                if !images.isEmpty {
                    self.onSelection(images)
                }
            }
        }
    }
}


