import AVKit
import SwiftUI

struct QABodyView: View {
    let blocks: [QABodyBlock]
    let segmentSubject: CommentSubjectDTO?
    let onNavigate: (QANavigationIntent) -> Void
    @Environment(\.nativeContentPresentation) private var presentation
    @ScaledMetric(relativeTo: .body) private var bodyPointSize: CGFloat = 17
    @ScaledMetric(relativeTo: .callout) private var calloutPointSize: CGFloat = 16

    init(
        blocks: [QABodyBlock],
        segmentSubject: CommentSubjectDTO? = nil,
        onNavigate: @escaping (QANavigationIntent) -> Void
    ) {
        self.blocks = blocks
        self.segmentSubject = segmentSubject
        self.onNavigate = onNavigate
    }

    private var galleryImages: [QAImageDTO] {
        blocks.compactMap { block in
            guard case let .image(image) = block else { return nil }
            return image
        }
    }

    private var galleryURLs: [URL] { galleryImages.map(\.url) }

    var body: some View {
        // Keep the complete document in one selection hierarchy. A LazyVStack
        // recycles off-screen Text views, which truncates Select All/copy for
        // long answers after scrolling.
        VStack(alignment: .leading, spacing: presentation.blockSpacing()) {
            ForEach(blocks) { block in
                blockView(block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
        .environment(\.openURL, OpenURLAction { url in
            guard let destination = QABodyLinkResolver.resolve(url) else { return .discarded }
            onNavigate(.link(destination))
            return .handled
        })
    }

    @ViewBuilder
    private func blockView(_ block: QABodyBlock) -> some View {
        switch block {
        case let .paragraph(_, runs):
            QARichText(runs: runs, pointSize: bodyPointSize * presentation.fontScale)
                .font(bodyFont)
                .lineSpacing(bodyLineSpacing)
                .tint(.accentColor)
                .textSelection(.enabled)
        case let .heading(_, level, runs):
            QARichText(runs: runs, pointSize: headingPointSize(level))
                .font(headingFont(level))
                .fontWeight(.bold)
                .textSelection(.enabled)
                .padding(.top, level <= 2 ? 8 : 2)
        case let .quote(_, runs):
            HStack(alignment: .top, spacing: 12) {
                Capsule().fill(.secondary.opacity(0.38)).frame(width: 3)
                QARichText(runs: runs, pointSize: bodyPointSize * presentation.fontScale)
                    .font(bodyFont)
                    .foregroundStyle(.secondary)
                    .lineSpacing(bodyLineSpacing)
                    .tint(.accentColor)
                    .textSelection(.enabled)
            }
        case let .list(_, kind, items):
            VStack(alignment: .leading, spacing: 9) {
                ForEach(listRows(kind: kind, items: items)) { row in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(row.marker)
                            .fontWeight(.semibold)
                            .foregroundStyle(.secondary)
                            .frame(minWidth: 18, alignment: .trailing)
                        QARichText(runs: row.runs, pointSize: bodyPointSize * presentation.fontScale)
                            .font(bodyFont)
                            .lineSpacing(bodyLineSpacing)
                            .tint(.accentColor)
                            .textSelection(.enabled)
                    }
                    .padding(.leading, CGFloat(row.depth) * 20)
                }
            }
        case let .code(_, language, text):
            ScrollView(.horizontal, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 7) {
                    if let language, !language.isEmpty {
                        Text(language.uppercased())
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                    }
                    Text(text)
                        .font(.system(size: calloutPointSize * presentation.fontScale, design: .monospaced))
                        .textSelection(.enabled)
                }
                .padding(14)
            }
            .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
        case let .formula(_, latex):
            QAKaTeXFormulaView(
                latex: latex,
                pointSize: bodyPointSize * presentation.fontScale
            )
        case let .image(image):
            Button {
                let index = galleryImages.firstIndex { $0.id == image.id } ?? 0
                onNavigate(.images(urls: galleryURLs, initialIndex: index))
            } label: {
                VStack(spacing: 7) {
                    QABodyRemoteImage(image: image)
                    if let caption = image.caption ?? image.altText, !caption.isEmpty {
                        Text(caption).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(image.altText ?? image.caption ?? "查看图片")
        case let .segment(_, segmentID, runs):
            if let segmentSubject,
               let subject = segmentCommentSubject(segmentSubject, segmentID: segmentID) {
                HStack(alignment: .bottom, spacing: 7) {
                    QARichText(runs: runs, pointSize: bodyPointSize * presentation.fontScale)
                        .font(bodyFont)
                        .lineSpacing(bodyLineSpacing)
                        .tint(.accentColor)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                        .textSelection(.enabled)
                    Button {
                        onNavigate(.segmentComments(CommentThreadRouteDTO(subject: subject)))
                    } label: {
                        Image(systemName: "text.bubble")
                            .font(.caption)
                            .foregroundStyle(.tint)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("查看本段评论")
                }
            } else {
                HStack(alignment: .bottom, spacing: 7) {
                    QARichText(runs: runs, pointSize: bodyPointSize * presentation.fontScale)
                        .font(bodyFont)
                        .lineSpacing(bodyLineSpacing)
                        .tint(.accentColor)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                        .textSelection(.enabled)
                }
            }
        case let .video(_, video):
            if video.playbackURL != nil {
                QANativeVideoPlayer(video: video)
            } else {
                QAVideoAttachmentView(video: video) {
                    onNavigate(.video(videoRoute(video)))
                }
            }
        case .divider:
            Divider()
        }
    }

    private var bodyFont: Font {
        .system(size: bodyPointSize * presentation.fontScale)
    }

    private func headingPointSize(_ level: Int) -> CGFloat {
        let scale = presentation.fontScale
        switch level {
        case 1: return 22 * scale
        case 2: return 20 * scale
        case 3: return 17 * scale
        default: return bodyPointSize * scale
        }
    }

    private var bodyLineSpacing: CGFloat {
        presentation.extraLineSpacing(for: bodyPointSize * presentation.fontScale)
    }

    private func headingFont(_ level: Int) -> Font {
        let scale = presentation.fontScale
        switch level {
        case 1: return .system(size: 22 * scale, weight: .bold)
        case 2: return .system(size: 20 * scale, weight: .bold)
        case 3: return .system(size: 17 * scale, weight: .semibold)
        default: return .system(size: bodyPointSize * scale, weight: .semibold)
        }
    }

    private func listRows(kind: QAListKind, items: [QAListItem]) -> [QAListDisplayRow] {
        flattenList(QAListGroup(kind: kind, items: items), depth: 0)
    }

    private func flattenList(_ group: QAListGroup, depth: Int) -> [QAListDisplayRow] {
        group.items.enumerated().flatMap { index, item in
            let number = item.ordinal ?? group.startIndex + index
            let marker = group.kind == .ordered ? "\(number)." : "•"
            let row = QAListDisplayRow(
                id: item.id,
                marker: marker,
                depth: depth,
                runs: item.runs
            )
            return [row] + item.nestedLists.flatMap {
                flattenList($0, depth: depth + 1)
            }
        }
    }

    private func segmentCommentSubject(
        _ subject: CommentSubjectDTO,
        segmentID: String
    ) -> CommentSubjectDTO? {
        switch subject {
        case let .answer(id): return .segment(contentID: String(id), contentTypeRaw: "answer", segmentID: segmentID)
        case let .article(id): return .segment(contentID: String(id), contentTypeRaw: "article", segmentID: segmentID)
        case let .question(id): return .segment(contentID: String(id), contentTypeRaw: "question", segmentID: segmentID)
        case let .pin(id): return .segment(contentID: String(id), contentTypeRaw: "pin", segmentID: segmentID)
        case .segment: return nil
        }
    }

    private func videoRoute(_ video: QAAttachmentVideoDTO) -> NativeVideoRouteDTO {
        let contentID: Int64
        let contentType: NativeVideoContentType
        switch segmentSubject {
        case let .answer(id):
            contentID = id
            contentType = .answer
        case let .article(id):
            contentID = id
            contentType = .article
        case let .question(id):
            contentID = id
            contentType = .question
        case let .pin(id):
            contentID = id
            contentType = .zvideo
        case .segment, .none:
            contentID = video.videoID
            contentType = .zvideo
        }
        return NativeVideoRouteDTO(
            contentID: contentID,
            videoID: video.videoID,
            contentType: contentType,
            thumbnailURL: video.thumbnailURL,
            playbackURL: video.playbackURL,
            webURL: video.destinationURL
        )
    }
}

private struct QARichText: View {
    let runs: [QAInlineRun]
    let pointSize: CGFloat

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.displayScale) private var displayScale
    @State private var renderedImages: [UUID: UIImage] = [:]
    @State private var failedRunIDs: Set<UUID> = []

    private var requestsByID: [UUID: QAKaTeXRenderRequest] {
        runs.reduce(into: [:]) { requests, run in
            guard let formula = run.formula else { return }
            requests[run.id] = QAKaTeXRenderRequest(
                latex: formula.latex,
                pointSize: min(
                    max(pointSize, QAKaTeXRenderPolicy.minimumPointSize),
                    QAKaTeXRenderPolicy.maximumPointSize
                ),
                color: colorScheme == .dark ? .darkForeground : .lightForeground,
                scale: min(
                    max(displayScale, QAKaTeXRenderPolicy.minimumScale),
                    QAKaTeXRenderPolicy.maximumScale
                ),
                isDarkMode: colorScheme == .dark,
                displayMode: run.formula?.isDisplay ?? true
            )
        }
    }

    private var requestKey: String {
        requestsByID.values.map(\.cacheKey).sorted().joined(separator: "|")
    }

    var body: some View {
        content
            .task(id: requestKey) {
                for run in runs where run.formula != nil {
                    guard let request = requestsByID[run.id] else { continue }
                    guard renderedImages[run.id] == nil, !failedRunIDs.contains(run.id) else { continue }
                    do {
                        renderedImages[run.id] = try await QAKaTeXRenderService.shared.render(request)
                    } catch is CancellationError {
                        return
                    } catch {
                        failedRunIDs.insert(run.id)
                    }
                }
            }
    }

    private var content: Text {
        runs.reduce(Text("")) { accumulated, run in
            accumulated + text(for: run)
        }
    }

    private func text(for run: QAInlineRun) -> Text {
        guard let formula = run.formula else {
            return Text(QARichTextFormatter.attributed([run]))
        }
        guard let image = renderedImages[run.id] else {
            return Text(QARichTextFormatter.attributed([run]))
        }

        let centeringOffset = max(0, image.size.height - pointSize * 0.72) / 2
        return Text(Image(uiImage: image))
            .baselineOffset(-centeringOffset)
    }
}

private struct QAListDisplayRow: Identifiable {
    let id: UUID
    let marker: String
    let depth: Int
    let runs: [QAInlineRun]
}

private struct QABodyRemoteImage: View {
    let image: QAImageDTO

    var body: some View {
        Group {
            if let dimensions = image.dimensions {
                content
                    .aspectRatio(CGFloat(dimensions.aspectRatio), contentMode: .fit)
            } else {
                content
                    .frame(minHeight: 120)
            }
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var content: some View {
        if NativeRemoteMediaPolicy.isAnimatedImage(image.url) {
            NativeAnimatedRemoteImage(url: image.url)
        } else {
            AsyncImage(url: image.url) { phase in
                switch phase {
                case let .success(value):
                    value.resizable().scaledToFit()
                case .failure:
                    VStack(spacing: 8) {
                        Image(systemName: "photo.badge.exclamationmark")
                        Text("图片加载失败").font(.caption)
                    }
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .empty:
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                @unknown default:
                    EmptyView()
                }
            }
        }
    }
}

enum QARichTextFormatter {
    static func attributed(_ runs: [QAInlineRun]) -> AttributedString {
        runs.reduce(into: AttributedString()) { value, run in
            var part = AttributedString(run.text)
            var presentation: InlinePresentationIntent = []
            if run.style.contains(.strong) { presentation.insert(.stronglyEmphasized) }
            if run.style.contains(.emphasis) { presentation.insert(.emphasized) }
            if !presentation.isEmpty { part.inlinePresentationIntent = presentation }
            if run.style.contains(.strikethrough) { part.strikethroughStyle = .single }
            if run.style.contains(.code) {
                part.font = .body.monospaced()
                part.backgroundColor = Color(uiColor: .secondarySystemBackground)
            }
            if let link = run.link {
                part.link = QABodyLinkResolver.url(link)
                part.foregroundColor = .accentColor
                part.underlineStyle = .single
            }
            value.append(part)
        }
    }
}

private struct QANativeVideoPlayer: View {
    let video: QAAttachmentVideoDTO
    @State private var player: AVPlayer?

    var body: some View {
        ZStack {
            Color.black
            if let player {
                VideoPlayer(player: player)
            } else if let thumbnailURL = video.thumbnailURL {
                AsyncImage(url: thumbnailURL) { image in
                    image.resizable().scaledToFit()
                } placeholder: {
                    ProgressView().tint(.white)
                }
            } else {
                ProgressView().tint(.white)
            }
        }
        .aspectRatio(16 / 9, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .onAppear {
            guard player == nil, let playbackURL = video.playbackURL else { return }
            player = AVPlayer(url: playbackURL)
        }
        .onDisappear { player?.pause() }
        .accessibilityLabel("视频播放器")
    }
}

private struct QAVideoAttachmentView: View {
    let video: QAAttachmentVideoDTO
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                AsyncImage(url: video.thumbnailURL) { phase in
                    switch phase {
                    case let .success(image): image.resizable().scaledToFill()
                    case .failure:
                        Color(uiColor: .secondarySystemBackground)
                            .overlay(Image(systemName: "video.slash").foregroundStyle(.secondary))
                    case .empty:
                        Color(uiColor: .secondarySystemBackground)
                            .overlay(ProgressView())
                    @unknown default:
                        Color(uiColor: .secondarySystemBackground)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.white, .black.opacity(0.34))
                    .shadow(radius: 8)
                VStack {
                    Spacer()
                    HStack {
                        Label("视频", systemImage: "play.rectangle.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white)
                        Spacer()
                    }
                    .padding(10)
                    .background(.black.opacity(0.38))
                }
            }
            .aspectRatio(16 / 9, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("播放视频")
    }
}

struct NativeVideoPlayerScreen: View {
    let route: NativeVideoRouteDTO
    let repository: NativeVideoRepository
    let openExternal: (URL) -> Void

    @State private var player: AVPlayer?
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 18) {
            ZStack {
                Color.black
                if let player {
                    VideoPlayer(player: player)
                } else if let thumbnailURL = route.thumbnailURL {
                    AsyncImage(url: thumbnailURL) { phase in
                        switch phase {
                        case let .success(image):
                            image.resizable().scaledToFit()
                        case .failure:
                            Color.black
                        case .empty:
                            ProgressView().tint(.white)
                        @unknown default:
                            Color.black
                        }
                    }
                }
                if isLoading {
                    ProgressView("正在载入视频")
                        .tint(.white)
                        .foregroundStyle(.white)
                }
            }
            .aspectRatio(16 / 9, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 14))

            if let errorMessage {
                VStack(spacing: 12) {
                    Image(systemName: "video.slash")
                        .font(.title2)
                    Text("视频加载失败")
                        .font(.headline)
                    Text(errorMessage)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button("重试") {
                        Task { await load() }
                    }
                    .buttonStyle(.borderedProminent)
                    if let webURL = route.webURL {
                        Button("在浏览器中打开") { openExternal(webURL) }
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .navigationTitle(route.title)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: route) { await load() }
        .onDisappear { player?.pause() }
    }

    @MainActor
    private func load() async {
        player?.pause()
        player = nil
        errorMessage = nil
        isLoading = true
        do {
            let playbackURL = try await repository.resolvePlaybackURL(for: route)
            guard !Task.isCancelled else { return }
            let player = AVPlayer(url: playbackURL)
            self.player = player
            isLoading = false
            player.play()
        } catch {
            guard !error.isNativeRequestCancellation else { return }
            isLoading = false
            errorMessage = error.localizedDescription
        }
    }
}

enum QABodyLinkResolver {
    static func url(_ destination: QALinkDestination) -> URL? {
        switch destination {
        case let .answer(id): return URL(string: "zhihu://answers/\(id)")
        case let .article(id): return URL(string: "zhihu://articles/\(id)")
        case let .question(id): return URL(string: "zhihu://questions/\(id)")
        case let .pin(id): return URL(string: "zhihu://pin/\(id)")
        case let .person(token): return URL(string: "zhihu://people/\(token)")
        case let .external(url): return url
        }
    }

    static func resolve(_ url: URL) -> QALinkDestination? {
        if let destination = NativeContentDestinationResolver.resolve(url.absoluteString) {
            switch destination {
            case let .article(id, kind):
                return kind == .answer ? .answer(id) : .article(id)
            case let .question(id):
                return .question(id)
            case let .person(_, token, _):
                return .person(urlToken: token)
            case let .pin(id):
                return .pin(id)
            case .special, .column:
                return .external(url)
            case .search:
                break
            case let .external(externalURL):
                return .external(externalURL)
            }
        }
        guard url.scheme?.lowercased() == "https", url.user == nil, url.password == nil else { return nil }
        return .external(url)
    }
}
