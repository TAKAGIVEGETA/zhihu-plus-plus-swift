import ImageIO
import Photos
import SwiftUI
import UIKit

struct NativeMediaGallery: View {
    let urls: [URL]
    let initialIndex: Int
    let accessibilityPrefix: String

    @Environment(\.dismiss) private var dismiss
    @Environment(\.nativeHapticFeedback) private var hapticFeedback
    @State private var selectedIndex: Int
    @StateObject private var imageStore = NativeMediaImageStore()
    @State private var zoomedIndices: Set<Int> = []
    @State private var dismissOffset: CGFloat = 0
    @State private var shareItems: NativeMediaActivityItems?
    @State private var message: NativeMediaMessage?
    @State private var isSaving = false
    @State private var isInputReady = false

    init(urls: [URL], initialIndex: Int, accessibilityPrefix: String = "media_gallery") {
        self.urls = urls
        self.initialIndex = min(max(0, initialIndex), max(0, urls.count - 1))
        self.accessibilityPrefix = accessibilityPrefix
        _selectedIndex = State(initialValue: min(max(0, initialIndex), max(0, urls.count - 1)))
    }

    var body: some View {
        ZStack {
            Color.black
                .opacity(backgroundOpacity())
                .ignoresSafeArea()

            pager
                .ignoresSafeArea()

            if urls.count > 1 {
                VStack {
                    Spacer()
                    Text("\(selectedIndex + 1) / \(urls.count)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.white)
                        .fixedSize(horizontal: true, vertical: false)
                        .frame(minWidth: 54)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 7)
                        .modifier(NativeMediaIndicatorSurface())
                        .padding(.bottom, 18)
                }
                .allowsHitTesting(false)
            }
        }
        .clipped()
        .background(Color.black.ignoresSafeArea())
        .overlay(alignment: .top) { topControls }
        .allowsHitTesting(isInputReady)
        .preferredColorScheme(.dark)
        .sheet(item: $shareItems) { items in
            NativeMediaActivityView(activityItems: items.values)
        }
        .alert(item: $message) { message in
            Alert(
                title: Text("操作结果"),
                message: Text(message.text),
                dismissButton: .default(Text("知道了"))
            )
        }
        .onChange(of: selectedIndex) { _ in
            hapticFeedback(.selection)
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                isInputReady = true
            }
        }
        .accessibilityIdentifier(accessibilityPrefix)
    }

    @ViewBuilder
    private var pager: some View {
        if urls.count == 1, let url = urls.first {
            page(url: url, index: 0)
        } else {
            TabView(selection: $selectedIndex) {
                ForEach(urls.indices, id: \.self) { index in
                    page(url: urls[index], index: index)
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
        }
    }

    private func page(url: URL, index: Int) -> some View {
        NativeZoomableRemoteImage(
            url: url,
            image: imageStore.image(for: url),
            didFail: imageStore.didFail(url),
            isCurrentPage: index == selectedIndex,
            isInputReady: isInputReady,
            onZoomChanged: { isZoomed in
                if isZoomed {
                    zoomedIndices.insert(index)
                } else {
                    zoomedIndices.remove(index)
                }
            },
            onDismissProgress: { offset in
                dismissOffset = offset
            },
            onSingleTap: {
                dismiss()
            },
            onInteractiveDismiss: {
                NativeMediaGalleryFeedback(action: hapticFeedback)
                    .verticalDismissDidCommit(true)
                dismiss()
            },
            onRetry: {
                Task { await imageStore.load(url) }
            }
        )
        .task(id: url) {
            await imageStore.load(url)
        }
    }

    @ViewBuilder
    private var topControls: some View {
        if #available(iOS 26, *) {
            GlassEffectContainer(spacing: 10) {
                controls
            }
        } else {
            controls
        }
    }

    private var controls: some View {
        HStack(spacing: 10) {
            NativeMediaControlButton(
                systemImage: "xmark",
                accessibilityLabel: "关闭图片",
                action: dismiss.callAsFunction
            )
            .accessibilityIdentifier("\(accessibilityPrefix)_close")

            Spacer()

            Menu {
                if let currentImage {
                    Button {
                        shareItems = NativeMediaActivityItems(values: [currentImage])
                    } label: {
                        Label("分享图片文件", systemImage: "square.and.arrow.up")
                    }
                }

                if #available(iOS 16, *), let currentURL {
                    ShareLink(item: currentURL) {
                        Label("分享图片链接", systemImage: "link")
                    }
                }

                Button(action: copyCurrentImage) {
                    Label("复制图片", systemImage: "doc.on.doc")
                }

                Button(action: saveCurrentImage) {
                    Label(isSaving ? "正在保存" : "保存到照片", systemImage: "square.and.arrow.down")
                }
                .disabled(currentImage == nil || isSaving)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
                    .modifier(NativeMediaControlSurface())
            }
            .foregroundStyle(.white)
            .accessibilityLabel("图片操作")
            .accessibilityIdentifier("\(accessibilityPrefix)_actions")
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
    }

    private var currentURL: URL? {
        urls.indices.contains(selectedIndex) ? urls[selectedIndex] : nil
    }

    private var currentImage: UIImage? {
        currentURL.flatMap { imageStore.image(for: $0) }
    }

    private var isCurrentImageZoomed: Bool { zoomedIndices.contains(selectedIndex) }

    private func backgroundOpacity() -> Double {
        let fadeDistance: CGFloat = 300
        return 1 - min(abs(dismissOffset) / fadeDistance, 1) * 0.55
    }

    private func copyCurrentImage() {
        if let currentImage {
            UIPasteboard.general.image = currentImage
            message = NativeMediaMessage(text: "已复制图片")
        } else if let currentURL {
            UIPasteboard.general.url = currentURL
            message = NativeMediaMessage(text: "图片尚未加载完成，已复制图片链接")
        } else {
            message = NativeMediaMessage(text: "当前图片不可用")
        }
    }

    private func saveCurrentImage() {
        guard let currentImage, !isSaving else { return }
        isSaving = true
        Task {
            defer { isSaving = false }
            do {
                try await NativePhotoLibrary.save(currentImage)
                message = NativeMediaMessage(text: "已保存到照片")
            } catch {
                message = NativeMediaMessage(text: "无法保存图片，请检查照片权限后重试")
            }
        }
    }
}

private struct NativeMediaControlButton: View {
    let systemImage: String
    let accessibilityLabel: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .semibold))
                .frame(width: 44, height: 44)
                .contentShape(Circle())
                .modifier(NativeMediaControlSurface())
        }
        .foregroundStyle(.white)
        .accessibilityLabel(accessibilityLabel)
    }
}

private struct NativeMediaControlSurface: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content.glassEffect(.regular.interactive(), in: .circle)
        } else {
            content.background(.ultraThinMaterial, in: Circle())
        }
    }
}

private struct NativeMediaIndicatorSurface: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content.glassEffect(.regular, in: .capsule)
        } else {
            content.background(.ultraThinMaterial, in: Capsule())
        }
    }
}

private struct NativeZoomableRemoteImage: UIViewControllerRepresentable {
    let url: URL
    let image: UIImage?
    let didFail: Bool
    let isCurrentPage: Bool
    let isInputReady: Bool
    let onZoomChanged: (Bool) -> Void
    let onDismissProgress: (CGFloat) -> Void
    let onSingleTap: () -> Void
    let onInteractiveDismiss: () -> Void
    let onRetry: () -> Void

    func makeUIViewController(context: Context) -> NativeZoomImageController {
        NativeZoomImageController()
    }

    func updateUIViewController(_ controller: NativeZoomImageController, context: Context) {
        controller.isCurrentPage = isCurrentPage
        controller.updateInputState(isReadyForInput: isInputReady)
        controller.updateContent(image: image, didFail: didFail)
        controller.updateCallbacks(
            onZoomChanged: onZoomChanged,
            onDismissProgress: onDismissProgress,
            onSingleTap: onSingleTap,
            onInteractiveDismiss: onInteractiveDismiss,
            onRetry: onRetry
        )
    }

    static func dismantleUIViewController(
        _ controller: NativeZoomImageController,
        coordinator: ()
    ) {
        controller.prepareForRemoval()
    }
}

private enum NativeMediaZoomPolicy {
    static let minimumScale: CGFloat = 1
    static let maximumScale: CGFloat = 4
    static let doubleTapScale: CGFloat = 2
    private static let minimumZoomDelta: CGFloat = 0.01

    static func clampedScale(_ scale: CGFloat) -> CGFloat {
        min(max(scale, minimumScale), maximumScale)
    }

    static func normalizedScale(_ scale: CGFloat) -> CGFloat {
        let clamped = clampedScale(scale)
        return clamped <= minimumScale + minimumZoomDelta ? minimumScale : clamped
    }

    static func isZoomed(_ scale: CGFloat) -> Bool {
        normalizedScale(scale) > minimumScale
    }

    static func doubleTapTarget(currentScale: CGFloat) -> CGFloat {
        isZoomed(currentScale) ? minimumScale : doubleTapScale
    }
}

private enum NativeMediaDismissAxis {
    case vertical
}

@MainActor
private final class NativeZoomImageController: UIViewController,
    UIScrollViewDelegate,
    UIGestureRecognizerDelegate {
    private let scrollView = UIScrollView()
    private let zoomContentView = UIView()
    private let imageView = UIImageView()
    private let activityIndicator = UIActivityIndicatorView(style: .large)
    private let retryButton = UIButton(type: .system)
    private lazy var dismissPanGestureRecognizer = UIPanGestureRecognizer(
        target: self,
        action: #selector(handleDismissPan(_:))
    )

    private var image: UIImage?
    private var didFail = false
    private var lastReportedZoomed = false
    private var activeDismissAxis: NativeMediaDismissAxis?
    private var isCompletingDismissGesture = false
    private var isReadyForInput = false

    var isCurrentPage = true
    var onZoomChanged: ((Bool) -> Void)?
    var onDismissProgress: ((CGFloat) -> Void)?
    var onSingleTap: (() -> Void)?
    var onInteractiveDismiss: (() -> Void)?
    var onRetry: (() -> Void)?

    override func loadView() {
        let rootView = UIView()
        rootView.backgroundColor = .black
        view = rootView

        // The explicit full-screen constraints below own this view's frame.
        // Leaving the default autoresizing translation enabled can fight those
        // constraints during modal presentation and produce a zero-sized,
        // completely black preview surface.
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.backgroundColor = .black
        scrollView.delegate = self
        scrollView.minimumZoomScale = NativeMediaZoomPolicy.minimumScale
        scrollView.maximumZoomScale = NativeMediaZoomPolicy.maximumScale
        scrollView.bounces = true
        scrollView.bouncesZoom = true
        scrollView.alwaysBounceHorizontal = false
        scrollView.alwaysBounceVertical = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.decelerationRate = .fast
        scrollView.delaysContentTouches = false
        // At rest the parent TabView owns horizontal paging. The scroll view's
        // pan recognizer is enabled only while the image is actually zoomed.
        scrollView.panGestureRecognizer.isEnabled = false
        scrollView.pinchGestureRecognizer?.delaysTouchesBegan = false
        scrollView.pinchGestureRecognizer?.delaysTouchesEnded = false
        scrollView.isAccessibilityElement = true
        scrollView.accessibilityLabel = "全屏图片"
        scrollView.accessibilityTraits = [.image]
        view.addSubview(scrollView)

        zoomContentView.backgroundColor = .black
        zoomContentView.clipsToBounds = true
        scrollView.addSubview(zoomContentView)

        imageView.contentMode = .scaleAspectFit
        imageView.clipsToBounds = true
        imageView.backgroundColor = .clear
        zoomContentView.addSubview(imageView)

        let doubleTapRecognizer = UITapGestureRecognizer(
            target: self,
            action: #selector(handleDoubleTap(_:))
        )
        doubleTapRecognizer.numberOfTapsRequired = 2
        doubleTapRecognizer.cancelsTouchesInView = false
        let singleTapRecognizer = UITapGestureRecognizer(
            target: self,
            action: #selector(handleSingleTap(_:))
        )
        singleTapRecognizer.numberOfTapsRequired = 1
        singleTapRecognizer.cancelsTouchesInView = false
        singleTapRecognizer.require(toFail: doubleTapRecognizer)
        view.addGestureRecognizer(doubleTapRecognizer)
        view.addGestureRecognizer(singleTapRecognizer)

        dismissPanGestureRecognizer.maximumNumberOfTouches = 1
        dismissPanGestureRecognizer.cancelsTouchesInView = false
        dismissPanGestureRecognizer.delegate = self
        view.addGestureRecognizer(dismissPanGestureRecognizer)

        activityIndicator.color = .white
        activityIndicator.hidesWhenStopped = true
        activityIndicator.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(activityIndicator)

        var retryConfiguration = UIButton.Configuration.gray()
        retryConfiguration.title = "图片加载失败，点按重试"
        retryConfiguration.image = UIImage(systemName: "arrow.clockwise")
        retryConfiguration.imagePadding = 8
        retryButton.configuration = retryConfiguration
        retryButton.tintColor = .white
        retryButton.translatesAutoresizingMaskIntoConstraints = false
        retryButton.addTarget(self, action: #selector(retry), for: .touchUpInside)
        view.addSubview(retryButton)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            activityIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            retryButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            retryButton.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            retryButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
        ])

        updateContentVisibility()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        isReadyForInput = false
        imageView.stopAnimating()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let viewportSize = scrollView.bounds.size
        if viewportSize != .zero,
           viewportSize != zoomContentView.bounds.size,
           NativeMediaZoomPolicy.isZoomed(scrollView.zoomScale) {
            resetZoom(animated: false)
        }
        if viewportSize != .zero,
           NativeMediaZoomPolicy.isZoomed(scrollView.zoomScale) == false {
            zoomContentView.bounds = CGRect(origin: .zero, size: viewportSize)
            zoomContentView.center = CGPoint(
                x: scrollView.bounds.midX,
                y: scrollView.bounds.midY
            )
            scrollView.contentSize = viewportSize
        }
        imageView.frame = zoomContentView.bounds
        centerZoomedContent()
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        zoomContentView
    }

    func scrollViewWillBeginZooming(_ scrollView: UIScrollView, with view: UIView?) {
        scrollView.panGestureRecognizer.isEnabled = true
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        updateZoomState()
    }

    func scrollViewDidEndZooming(
        _ scrollView: UIScrollView,
        with view: UIView?,
        atScale scale: CGFloat
    ) {
        let normalizedScale = NativeMediaZoomPolicy.normalizedScale(scale)
        if normalizedScale != scale {
            scrollView.setZoomScale(normalizedScale, animated: false)
        }
        updateZoomState()
        if NativeMediaZoomPolicy.isZoomed(normalizedScale) == false {
            DispatchQueue.main.async { [weak self] in
                guard let self,
                      NativeMediaZoomPolicy.isZoomed(self.scrollView.zoomScale) == false
                else { return }
                self.scrollView.panGestureRecognizer.isEnabled = false
            }
        }
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer === dismissPanGestureRecognizer,
              isCurrentPage,
              isReadyForInput,
              isCompletingDismissGesture == false,
              NativeMediaZoomPolicy.isZoomed(scrollView.zoomScale) == false,
              NativeMediaDismissalPolicy.isVerticalVelocity(
                  dismissPanGestureRecognizer.velocity(in: view)
              )
        else { return false }
        activeDismissAxis = .vertical
        return true
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        guard gestureRecognizer === dismissPanGestureRecognizer,
              let otherPan = otherGestureRecognizer as? UIPanGestureRecognizer,
              otherPan !== scrollView.panGestureRecognizer,
              let ancestorView = otherPan.view
        else { return false }
        return view.isDescendant(of: ancestorView)
    }

    func updateContent(image: UIImage?, didFail: Bool) {
        let imageChanged = self.image !== image
        self.image = image
        self.didFail = didFail

        if imageChanged {
            NativeAnimatedImageInstaller.apply(
                image,
                to: imageView,
                startsWhenPossible: viewIfLoaded?.window != nil
            )
            if image != nil {
                resetZoom(animated: false)
            }
        }
        updateContentVisibility()
    }

    func updateCallbacks(
        onZoomChanged: @escaping (Bool) -> Void,
        onDismissProgress: @escaping (CGFloat) -> Void,
        onSingleTap: @escaping () -> Void,
        onInteractiveDismiss: @escaping () -> Void,
        onRetry: @escaping () -> Void
    ) {
        self.onZoomChanged = onZoomChanged
        self.onDismissProgress = onDismissProgress
        self.onSingleTap = onSingleTap
        self.onInteractiveDismiss = onInteractiveDismiss
        self.onRetry = onRetry
    }

    func updateInputState(isReadyForInput: Bool) {
        self.isReadyForInput = isReadyForInput
        if isReadyForInput {
            startAnimatedImageIfNeeded()
        }
    }

    func prepareForRemoval() {
        imageView.stopAnimating()
        onZoomChanged = nil
        onDismissProgress = nil
        onSingleTap = nil
        onInteractiveDismiss = nil
        onRetry = nil
    }

    private func updateContentVisibility() {
        let showsRetry = image == nil && didFail
        let showsActivity = image == nil && didFail == false
        retryButton.isHidden = showsRetry == false
        if showsActivity {
            activityIndicator.startAnimating()
        } else {
            activityIndicator.stopAnimating()
        }
    }

    private func startAnimatedImageIfNeeded() {
        NativeAnimatedImageInstaller.startIfNeeded(on: imageView)
    }

    @objc private func handleSingleTap(_ recognizer: UITapGestureRecognizer) {
        guard recognizer.state == .ended,
              isReadyForInput,
              isCompletingDismissGesture == false
        else { return }
        onSingleTap?()
    }

    @objc private func handleDoubleTap(_ recognizer: UITapGestureRecognizer) {
        guard recognizer.state == .ended,
              isReadyForInput
        else { return }
        let targetScale = NativeMediaZoomPolicy.doubleTapTarget(
            currentScale: scrollView.zoomScale
        )
        if targetScale == NativeMediaZoomPolicy.minimumScale {
            scrollView.setZoomScale(targetScale, animated: true)
        } else {
            scrollView.panGestureRecognizer.isEnabled = true
            let location = recognizer.location(in: zoomContentView)
            zoom(
                to: targetScale,
                centeredAt: zoomContentView.bounds.contains(location)
                    ? location
                    : zoomContentView.center
            )
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            self?.updateZoomState()
        }
    }

    @objc private func retry() {
        onRetry?()
    }

    @objc private func handleDismissPan(_ recognizer: UIPanGestureRecognizer) {
        guard activeDismissAxis != nil else { return }
        let translation = recognizer.translation(in: view)
        switch recognizer.state {
        case .changed:
            scrollView.transform = CGAffineTransform(
                translationX: 0,
                y: translation.y
            )
            onDismissProgress?(translation.y)
        case .ended:
            if NativeMediaDismissalPolicy.shouldDismiss(
                translation: translation,
                velocity: recognizer.velocity(in: view),
                viewportHeight: view.bounds.height
            ) {
                isCompletingDismissGesture = true
                onInteractiveDismiss?()
            } else {
                restoreAfterCancelledDismissal()
            }
            activeDismissAxis = nil
        case .cancelled, .failed:
            restoreAfterCancelledDismissal()
            activeDismissAxis = nil
        default:
            break
        }
    }

    private func restoreAfterCancelledDismissal() {
        isCompletingDismissGesture = true
        if UIAccessibility.isReduceMotionEnabled {
            scrollView.transform = .identity
            onDismissProgress?(0)
            isCompletingDismissGesture = false
            return
        }
        UIView.animate(
            withDuration: 0.28,
            delay: 0,
            usingSpringWithDamping: 0.84,
            initialSpringVelocity: 0,
            options: [.beginFromCurrentState, .allowUserInteraction],
            animations: { [weak self] in
                self?.scrollView.transform = .identity
            }
        ) { [weak self] _ in
            self?.onDismissProgress?(0)
            self?.isCompletingDismissGesture = false
        }
    }

    private func zoom(to scale: CGFloat, centeredAt location: CGPoint) {
        let targetScale = NativeMediaZoomPolicy.clampedScale(scale)
        let viewportSize = scrollView.bounds.size
        guard viewportSize.width > 0, viewportSize.height > 0 else {
            scrollView.setZoomScale(targetScale, animated: true)
            return
        }
        let zoomSize = CGSize(
            width: viewportSize.width / targetScale,
            height: viewportSize.height / targetScale
        )
        scrollView.zoom(
            to: CGRect(
                x: location.x - zoomSize.width / 2,
                y: location.y - zoomSize.height / 2,
                width: zoomSize.width,
                height: zoomSize.height
            ),
            animated: true
        )
    }

    private func updateZoomState() {
        let isZoomed = NativeMediaZoomPolicy.isZoomed(scrollView.zoomScale)
        if isZoomed != lastReportedZoomed {
            lastReportedZoomed = isZoomed
            onZoomChanged?(isZoomed)
        }
        centerZoomedContent()
    }

    private func resetZoom(animated: Bool) {
        scrollView.setZoomScale(NativeMediaZoomPolicy.minimumScale, animated: animated)
        scrollView.panGestureRecognizer.isEnabled = false
        scrollView.transform = .identity
        centerZoomedContent()
        updateZoomState()
    }

    private func centerZoomedContent() {
        let contentSize = scrollView.contentSize
        zoomContentView.center = CGPoint(
            x: max(contentSize.width, scrollView.bounds.width) / 2,
            y: max(contentSize.height, scrollView.bounds.height) / 2
        )
    }
}

enum NativeRemoteMediaPolicy {
    static func isAnimatedImage(_ url: URL) -> Bool {
        ["gif", "webp", "apng"].contains(url.pathExtension.lowercased())
    }
}

struct NativeAnimatedRemoteImage: View {
    let url: URL
    let contentMode: ContentMode

    @StateObject private var loader = NativeAnimatedImageLoader()

    init(url: URL, contentMode: ContentMode = .fit) {
        self.url = url
        self.contentMode = contentMode
    }

    var body: some View {
        Group {
            if let image = loader.image {
                NativeAnimatedUIImageView(image: image, contentMode: contentMode)
                    .aspectRatio(
                        image.size.height > 0 ? image.size.width / image.size.height : 1,
                        contentMode: contentMode
                    )
            } else if loader.didFail {
                ZStack {
                    Color.secondary.opacity(0.12)
                    Image(systemName: "photo.badge.exclamationmark")
                        .foregroundStyle(.secondary)
                }
            } else {
                ZStack {
                    Color.secondary.opacity(0.08)
                    ProgressView()
                }
            }
        }
        .task(id: url) { await loader.load(url) }
        .accessibilityLabel("动图")
    }
}

enum NativeMediaImageRequestFactory {
    static func make(for url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue(
            ZhihuAPIClient.defaultUserAgent,
            forHTTPHeaderField: "User-Agent"
        )
        return request
    }
}

@MainActor
enum NativeAnimatedImageInstaller {
    static func apply(
        _ image: UIImage?,
        to imageView: UIImageView,
        startsWhenPossible: Bool
    ) {
        imageView.stopAnimating()

        guard let image else {
            imageView.animationImages = nil
            imageView.animationDuration = 0
            imageView.image = nil
            return
        }

        let frames = image.images ?? []
        if frames.count > 1 {
            imageView.animationImages = frames
            imageView.animationDuration = image.duration
            imageView.image = frames.first ?? image
            if startsWhenPossible {
                imageView.startAnimating()
            }
        } else {
            imageView.animationImages = nil
            imageView.animationDuration = 0
            imageView.image = image
        }
    }

    static func startIfNeeded(on imageView: UIImageView) {
        guard (imageView.animationImages?.count ?? 1) > 1,
              imageView.isAnimating == false
        else { return }
        imageView.startAnimating()
    }
}

private struct NativeAnimatedUIImageView: UIViewRepresentable {
    let image: UIImage
    let contentMode: ContentMode

    func makeUIView(context: Context) -> UIImageView {
        let view = UIImageView()
        view.clipsToBounds = true
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ uiView: UIImageView, context: Context) {
        uiView.contentMode = contentMode == .fill ? .scaleAspectFill : .scaleAspectFit
        let frames = image.images ?? []
        let currentFrame = frames.count > 1
            ? uiView.animationImages?.first
            : uiView.image
        let newFrame = frames.first ?? image
        guard currentFrame !== newFrame else { return }
        NativeAnimatedImageInstaller.apply(image, to: uiView, startsWhenPossible: true)
    }

    static func dismantleUIView(_ uiView: UIImageView, coordinator: ()) {
        NativeAnimatedImageInstaller.apply(nil, to: uiView, startsWhenPossible: false)
    }
}

@MainActor
private final class NativeAnimatedImageLoader: ObservableObject {
    @Published private(set) var image: UIImage?
    @Published private(set) var didFail = false
    private var loadedURL: URL?

    func load(_ url: URL) async {
        guard loadedURL != url || image == nil else { return }
        loadedURL = url
        image = nil
        didFail = false
        do {
            let (data, response) = try await URLSession.shared.data(
                for: NativeMediaImageRequestFactory.make(for: url)
            )
            try Task.checkCancellation()
            guard let response = response as? HTTPURLResponse,
                  (200..<300).contains(response.statusCode),
                  data.count <= 40 * 1_024 * 1_024,
                  let decoded = NativeAnimatedImageDecoder.decode(data)
            else { throw URLError(.cannotDecodeContentData) }
            guard loadedURL == url else { return }
            image = decoded
        } catch is CancellationError {
        } catch {
            guard loadedURL == url else { return }
            didFail = true
        }
    }
}

enum NativeAnimatedImageDecoder {
    private static let maximumFrameCount = 60
    private static let maximumTotalPixels = 24_000_000
    private static let maximumPixelSize = 1_600

    static func decode(_ data: Data) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let frameCount = CGImageSourceGetCount(source)
        guard frameCount > 1 else { return UIImage(data: data) }

        let stride = max(1, Int(ceil(Double(frameCount) / Double(maximumFrameCount))))
        let decodedFrameCount = Int(ceil(Double(frameCount) / Double(stride)))
        let memoryBoundPixelSize = Int(
            sqrt(Double(maximumTotalPixels) / Double(max(decodedFrameCount, 1)))
        )
        let thumbnailPixelSize = min(maximumPixelSize, max(memoryBoundPixelSize, 320))
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: thumbnailPixelSize,
            kCGImageSourceShouldCacheImmediately: true,
        ] as CFDictionary
        var frames: [UIImage] = []
        frames.reserveCapacity(min(frameCount, maximumFrameCount))
        var duration = 0.0

        for index in 0 ..< frameCount {
            guard index % stride == 0,
                  let cgImage = CGImageSourceCreateThumbnailAtIndex(source, index, options)
            else { continue }
            duration += frameDuration(source: source, index: index)
            frames.append(UIImage(cgImage: cgImage))
        }

        guard !frames.isEmpty else { return nil }
        return UIImage.animatedImage(with: frames, duration: max(duration, 0.1))
    }

    private static func frameDuration(source: CGImageSource, index: Int) -> TimeInterval {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil)
            as? [CFString: Any]
        else { return 0.1 }
        return frameDuration(properties: properties)
    }

    static func frameDuration(properties: [CFString: Any]) -> TimeInterval {
        if let gif = properties[kCGImagePropertyGIFDictionary] as? [CFString: Any] {
            return normalizedDelay(
                unclamped: gif[kCGImagePropertyGIFUnclampedDelayTime],
                clamped: gif[kCGImagePropertyGIFDelayTime]
            )
        }
        if let webp = properties[kCGImagePropertyWebPDictionary] as? [CFString: Any] {
            return normalizedDelay(
                unclamped: webp[kCGImagePropertyWebPUnclampedDelayTime],
                clamped: webp[kCGImagePropertyWebPDelayTime]
            )
        }
        if let apng = properties[kCGImagePropertyPNGDictionary] as? [CFString: Any] {
            return normalizedDelay(
                unclamped: apng[kCGImagePropertyAPNGUnclampedDelayTime],
                clamped: apng[kCGImagePropertyAPNGDelayTime]
            )
        }
        return 0.1
    }

    private static func normalizedDelay(unclamped: Any?, clamped: Any?) -> TimeInterval {
        let unclamped = (unclamped as? NSNumber)?.doubleValue
        let clamped = (clamped as? NSNumber)?.doubleValue
        let value = unclamped ?? clamped ?? 0.1
        return value < 0.02 ? 0.1 : value
    }
}

@MainActor
struct NativeMediaGalleryFeedback {
    let action: NativeHapticFeedbackAction

    func pageDidCommit(from previousIndex: Int, to selectedIndex: Int) {
        guard previousIndex != selectedIndex else { return }
        action(.selection)
    }

    func verticalDismissDidCommit(_ committed: Bool) {
        guard committed else { return }
        action(.dismiss)
    }
}

struct NativeMediaDismissalPolicy {
    static func isVertical(_ translation: CGSize) -> Bool {
        abs(translation.height) > abs(translation.width) * 1.15
    }

    static func isVerticalVelocity(_ velocity: CGPoint) -> Bool {
        abs(velocity.y) > abs(velocity.x) * 1.15
    }

    static func shouldDismiss(
        translation: CGSize,
        predictedEndTranslation: CGSize,
        viewportHeight: CGFloat
    ) -> Bool {
        guard isVertical(translation) else { return false }
        let threshold = max(viewportHeight * 0.16, 72)
        return abs(translation.height) >= threshold ||
            abs(predictedEndTranslation.height) >= threshold * 1.35
    }

    static func shouldDismiss(
        translation: CGPoint,
        velocity: CGPoint,
        viewportHeight: CGFloat
    ) -> Bool {
        let threshold = max(viewportHeight * 0.16, 72)
        return abs(translation.y) >= threshold ||
            (abs(translation.y) >= 60 && abs(velocity.y) >= 1_000)
    }
}

struct NativeMediaPagingPolicy {
    static func targetIndex(
        currentIndex: Int,
        pageCount: Int,
        translationWidth: CGFloat,
        predictedEndTranslationWidth: CGFloat,
        pageWidth: CGFloat
    ) -> Int {
        guard pageCount > 0, pageWidth > 0, pageCount > currentIndex, currentIndex >= 0 else {
            return currentIndex
        }
        let threshold = pageWidth * 0.18
        if (translationWidth <= -threshold || predictedEndTranslationWidth <= -threshold * 1.35),
           currentIndex < pageCount - 1 {
            return currentIndex + 1
        }
        if (translationWidth >= threshold || predictedEndTranslationWidth >= threshold * 1.35),
           currentIndex > 0 {
            return currentIndex - 1
        }
        return currentIndex
    }
}

@MainActor
private final class NativeMediaImageStore: ObservableObject {
    private struct LoadOperation {
        let id = UUID()
        let task: Task<Data, Error>
    }

    @Published private var images: [URL: UIImage] = [:]
    @Published private var failedURLs: Set<URL> = []
    private var operations: [URL: LoadOperation] = [:]

    func image(for url: URL) -> UIImage? { images[url] }
    func didFail(_ url: URL) -> Bool { failedURLs.contains(url) }

    func load(_ url: URL) async {
        guard images[url] == nil else { return }
        let operation: LoadOperation
        if let existing = operations[url] {
            operation = existing
        } else {
            failedURLs.remove(url)
            operation = LoadOperation(task: Task {
                let (data, response) = try await URLSession.shared.data(
                    for: NativeMediaImageRequestFactory.make(for: url)
                )
                guard let response = response as? HTTPURLResponse,
                      (200..<300).contains(response.statusCode)
                else { throw URLError(.badServerResponse) }
                return data
            })
            operations[url] = operation
        }
        do {
            let data = try await operation.task.value
            // The decoder inspects frame count itself, so animated media works
            // even when Zhihu serves it from an extensionless or renamed URL.
            guard let image = NativeAnimatedImageDecoder.decode(data) else {
                throw URLError(.cannotDecodeContentData)
            }
            images[url] = image
            failedURLs.remove(url)
        } catch is CancellationError {
            // A second visible page may still await the shared operation.
        } catch {
            failedURLs.insert(url)
        }
        if operations[url]?.id == operation.id { operations.removeValue(forKey: url) }
    }
}

private enum NativePhotoLibrary {
    static func save(_ image: UIImage) async throws {
        let status = await authorizationStatus()
        guard status == .authorized || status == .limited else {
            throw NativePhotoLibraryError.permissionDenied
        }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            } completionHandler: { succeeded, error in
                if let error { continuation.resume(throwing: error) }
                else if succeeded { continuation.resume() }
                else { continuation.resume(throwing: NativePhotoLibraryError.saveFailed) }
            }
        }
    }

    private static func authorizationStatus() async -> PHAuthorizationStatus {
        let current = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        guard current == .notDetermined else { return current }
        return await withCheckedContinuation { continuation in
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
                continuation.resume(returning: status)
            }
        }
    }
}

private enum NativePhotoLibraryError: Error {
    case permissionDenied
    case saveFailed
}

private struct NativeMediaActivityItems: Identifiable {
    let id = UUID()
    let values: [Any]
}

private struct NativeMediaActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

private struct NativeMediaMessage: Identifiable {
    let id = UUID()
    let text: String
}
