import CoreGraphics
import ImageIO
import UIKit
import XCTest
@testable import iosApp

final class NativeMediaGalleryTests: XCTestCase {
    func testAnimatedImagePolicyRecognizesSupportedFormats() {
        XCTAssertTrue(NativeRemoteMediaPolicy.isAnimatedImage(
            URL(string: "https://pic.zhimg.com/demo.gif?source=answer")!
        ))
        XCTAssertTrue(NativeRemoteMediaPolicy.isAnimatedImage(
            URL(string: "https://pic.zhimg.com/demo.webp")!
        ))
        XCTAssertTrue(NativeRemoteMediaPolicy.isAnimatedImage(
            URL(string: "https://pic.zhimg.com/demo.apng")!
        ))
        XCTAssertFalse(NativeRemoteMediaPolicy.isAnimatedImage(
            URL(string: "https://pic.zhimg.com/demo.jpg")!
        ))
    }

    func testGalleryDestinationPreservesAllMediaAndSelectedIdentity() throws {
        let media = [
            CommentMediaDTO(kind: .image, url: URL(string: "https://pic.zhimg.com/one.jpg")!),
            CommentMediaDTO(kind: .image, url: URL(string: "https://pic.zhimg.com/two.jpg")!),
            CommentMediaDTO(kind: .sticker, url: URL(string: "https://pic.zhimg.com/three.png")!),
        ]

        let destination = try XCTUnwrap(
            CommentMediaGalleryDestination(media: media, selectedID: media[1].id)
        )

        XCTAssertEqual(destination.urls, media.map(\.url))
        XCTAssertEqual(destination.initialIndex, 1)
    }

    func testVerticalDismissalAcceptsUpAndDownAtOneScalePolicyBoundary() {
        XCTAssertFalse(NativeMediaDismissalPolicy.isVertical(CGSize(width: 120, height: 30)))
        XCTAssertTrue(
            NativeMediaDismissalPolicy.shouldDismiss(
                translation: CGSize(width: 4, height: -150),
                predictedEndTranslation: CGSize(width: 6, height: -190),
                viewportHeight: 800
            )
        )
        XCTAssertTrue(
            NativeMediaDismissalPolicy.shouldDismiss(
                translation: CGSize(width: 4, height: 50),
                predictedEndTranslation: CGSize(width: 6, height: 230),
                viewportHeight: 800
            )
        )
        XCTAssertFalse(
            NativeMediaDismissalPolicy.shouldDismiss(
                translation: CGSize(width: 4, height: 30),
                predictedEndTranslation: CGSize(width: 6, height: 50),
                viewportHeight: 800
            )
        )
    }

    func testVerticalDismissalUsesPanVelocityDirectionAndCommitPolicy() {
        XCTAssertTrue(NativeMediaDismissalPolicy.isVerticalVelocity(
            CGPoint(x: 20, y: 300)
        ))
        XCTAssertFalse(NativeMediaDismissalPolicy.isVerticalVelocity(
            CGPoint(x: 300, y: 20)
        ))
        XCTAssertTrue(NativeMediaDismissalPolicy.shouldDismiss(
            translation: CGPoint(x: 4, y: -60),
            velocity: CGPoint(x: 0, y: -1_200),
            viewportHeight: 800
        ))
        XCTAssertFalse(NativeMediaDismissalPolicy.shouldDismiss(
            translation: CGPoint(x: 4, y: -50),
            velocity: CGPoint(x: 0, y: -900),
            viewportHeight: 800
        ))
    }

    @MainActor
    func testAnimatedImageDecoderPreservesGIFFramesAndDuration() throws {
        let data = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(
            data,
            "com.compuserve.gif" as CFString,
            2,
            nil
        ))
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = try XCTUnwrap(CGContext(
            data: nil,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        let frame = try XCTUnwrap(context.makeImage())
        let properties = [
            kCGImagePropertyGIFDictionary: [
                kCGImagePropertyGIFDelayTime: 0.08
            ]
        ] as CFDictionary

        CGImageDestinationAddImage(destination, frame, properties)
        CGImageDestinationAddImage(destination, frame, properties)
        XCTAssertTrue(CGImageDestinationFinalize(destination))

        let image = try XCTUnwrap(NativeAnimatedImageDecoder.decode(data as Data))
        XCTAssertEqual(image.images?.count, 2)
        XCTAssertEqual(image.duration, 0.16, accuracy: 0.001)

        let imageView = UIImageView()
        NativeAnimatedImageInstaller.apply(
            image,
            to: imageView,
            startsWhenPossible: false
        )
        XCTAssertEqual(imageView.animationImages?.count, 2)
        XCTAssertEqual(imageView.animationDuration, 0.16, accuracy: 0.001)
        XCTAssertEqual(imageView.image, image.images?.first)
    }

    func testAnimatedImageDecoderReadsWebPAndAPNGFrameDurations() {
        let webpProperties: [CFString: Any] = [
            kCGImagePropertyWebPDictionary: [
                kCGImagePropertyWebPUnclampedDelayTime: 0.12
            ]
        ]
        let apngProperties: [CFString: Any] = [
            kCGImagePropertyPNGDictionary: [
                kCGImagePropertyAPNGDelayTime: 0.07
            ]
        ]

        XCTAssertEqual(
            NativeAnimatedImageDecoder.frameDuration(properties: webpProperties),
            0.12,
            accuracy: 0.001
        )
        XCTAssertEqual(
            NativeAnimatedImageDecoder.frameDuration(properties: apngProperties),
            0.07,
            accuracy: 0.001
        )
    }

    func testImageRequestsUseZhihuBrowserUserAgent() throws {
        let url = try XCTUnwrap(URL(string: "https://pic.zhimg.com/demo.gif"))
        let request = NativeMediaImageRequestFactory.make(for: url)

        XCTAssertEqual(
            request.value(forHTTPHeaderField: "User-Agent"),
            ZhihuAPIClient.defaultUserAgent
        )
    }

    func testPagingUsesViewportWidthAndStopsAtBothBoundaries() {
        XCTAssertEqual(
            NativeMediaPagingPolicy.targetIndex(
                currentIndex: 1,
                pageCount: 3,
                translationWidth: -90,
                predictedEndTranslationWidth: -120,
                pageWidth: 400
            ),
            2
        )
        XCTAssertEqual(
            NativeMediaPagingPolicy.targetIndex(
                currentIndex: 0,
                pageCount: 3,
                translationWidth: 120,
                predictedEndTranslationWidth: 180,
                pageWidth: 400
            ),
            0
        )
        XCTAssertEqual(
            NativeMediaPagingPolicy.targetIndex(
                currentIndex: 2,
                pageCount: 3,
                translationWidth: -120,
                predictedEndTranslationWidth: -180,
                pageWidth: 400
            ),
            2
        )
        XCTAssertEqual(
            NativeMediaPagingPolicy.targetIndex(
                currentIndex: 1,
                pageCount: 3,
                translationWidth: 30,
                predictedEndTranslationWidth: 40,
                pageWidth: 400
            ),
            1
        )
    }

    @MainActor
    func testGalleryFeedbackOnlyEmitsForChangedPageAndCommittedVerticalDismiss() {
        var events: [NativeHapticFeedbackEvent] = []
        let action = NativeHapticFeedbackAction(configuration: .init()) { event, _ in
            events.append(event)
        }
        let feedback = NativeMediaGalleryFeedback(action: action)

        feedback.pageDidCommit(from: 1, to: 1)
        feedback.verticalDismissDidCommit(false)
        feedback.pageDidCommit(from: 1, to: 2)
        feedback.verticalDismissDidCommit(true)

        XCTAssertEqual(events, [.selection, .dismiss])
    }
}
