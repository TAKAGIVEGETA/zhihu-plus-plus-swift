import Foundation
import XCTest
@testable import iosApp

final class FeedInfrastructureTests: XCTestCase {
    override func tearDown() {
        FeedURLProtocol.setHandler(nil)
        super.tearDown()
    }

    func testHotProjectionOmitsAuthorAndThumbnailAndCreatesAnswerRoute() throws {
        let page = try FeedResponseMapper.page(from: FeedFixtures.hotPage, policy: .hot)
        let item = try XCTUnwrap(page.items.first)

        XCTAssertEqual(item.id, FeedItemID(kind: .answer, contentID: "42"))
        XCTAssertEqual(item.title, "问题标题")
        XCTAssertEqual(item.summary, "回答摘要")
        XCTAssertNil(item.author)
        XCTAssertNil(item.thumbnailURL)
        XCTAssertEqual(
            item.route,
            .answer(answerID: 42, questionID: 7, questionTitle: "问题标题")
        )
        XCTAssertEqual(page.nextURL, URL(string: "https://www.zhihu.com/api/v3/hot?page=2"))
        XCTAssertFalse(page.isEnd)
    }

    func testSearchProjectionKeepsTypedArticlePresentation() throws {
        let page = try FeedResponseMapper.page(from: FeedFixtures.searchPage, policy: .search)
        let item = try XCTUnwrap(page.items.first)

        XCTAssertEqual(item.kind, .article)
        XCTAssertEqual(item.title, "原生搜索文章")
        XCTAssertEqual(item.author?.displayName, "作者")
        XCTAssertEqual(item.thumbnailURL, URL(string: "https://pic.zhimg.com/article.jpg"))
        XCTAssertEqual(item.route, .article(articleID: 81, title: "原生搜索文章"))
    }

    func testAnswerProjectionPreservesThumbnailDimensionsForTallLayout() throws {
        let data = Data(
            #"""
            {
              "data": [{
                "target": {
                  "id": "2065638900522079962",
                  "type": "answer",
                  "excerpt": "回答摘要",
                  "thumbnail": "https://picx.zhimg.com/answer_qhd.jpg",
                  "thumbnail_info": {
                    "thumbnails": [{
                      "url": "https://picx.zhimg.com/answer_720w.jpg",
                      "width": 1280,
                      "height": 6076
                    }]
                  },
                  "question": {
                    "id": "2065059989778076694",
                    "title": "问题标题"
                  }
                }
              }],
              "paging": {"is_end": true, "next": null}
            }
            """#.utf8
        )

        let item = try XCTUnwrap(
            FeedResponseMapper.page(from: data, policy: .search).items.first
        )

        XCTAssertEqual(item.thumbnailURL, URL(string: "https://picx.zhimg.com/answer_qhd.jpg"))
        XCTAssertEqual(item.thumbnailPixelWidth, 1280)
        XCTAssertEqual(item.thumbnailPixelHeight, 6076)
        XCTAssertEqual(
            FeedThumbnailPresentationPolicy.placement(
                pixelWidth: item.thumbnailPixelWidth,
                pixelHeight: item.thumbnailPixelHeight
            ),
            .wideInline
        )
        XCTAssertEqual(
            FeedThumbnailPresentationPolicy.placement(
                pixelWidth: item.thumbnailPixelWidth,
                pixelHeight: item.thumbnailPixelHeight
            ).cropAnchor,
            .top
        )
    }

    func testThumbnailPresentationKeepsNormalPortraitAndUnknownSizesTrailing() {
        XCTAssertEqual(
            FeedThumbnailPresentationPolicy.placement(pixelWidth: 900, pixelHeight: 1_600),
            .trailing
        )
        XCTAssertEqual(
            FeedThumbnailPresentationPolicy.placement(
                pixelWidth: 900,
                pixelHeight: 1_600
            ).cropAnchor,
            .center
        )
        XCTAssertEqual(
            FeedThumbnailPresentationPolicy.placement(pixelWidth: 1_600, pixelHeight: 900),
            .trailing
        )
        XCTAssertEqual(
            FeedThumbnailPresentationPolicy.placement(pixelWidth: nil, pixelHeight: nil),
            .trailing
        )
        XCTAssertEqual(
            FeedThumbnailPresentationPolicy.placement(pixelWidth: 1_000, pixelHeight: 2_500),
            .wideInline
        )
    }

    func testFeedMetadataOmitsContentTypeAndCompactsCounts() {
        XCTAssertEqual(
            FeedItemMetadataFormatter.displayText(
                kind: .answer,
                details: "回答 · 23000 赞同 · 1528 评论 · 某人回答了问题"
            ),
            "2.3 万赞同 · 1,528 评论"
        )
        XCTAssertEqual(
            FeedItemMetadataFormatter.displayText(
                kind: .pin,
                details: "想法 · 285 赞 · 18 评论"
            ),
            "285 赞 · 18 评论"
        )
    }

    func testFeedMetadataUsesTypeSpecificMetricsAndIgnoresSourceLabels() {
        XCTAssertEqual(
            FeedItemMetadataFormatter.displayText(
                kind: .question,
                details: "问题 · 100000000 关注 · 12345 回答 · 推荐关注"
            ),
            "1 亿关注 · 1.2 万回答"
        )
        XCTAssertEqual(
            FeedItemMetadataFormatter.displayText(
                kind: .article,
                details: "文章 · 编辑推荐"
            ),
            ""
        )
    }

    func testAnswerProjectionUsesQuestionAuthorWithoutFallingBackToAnswerAuthor() throws {
        let data = Data(
            #"{"data":[{"target":{"id":42,"type":"answer","excerpt":"回答","question":{"id":7,"title":"问题","author":{"id":"asker-id","url_token":"asker","name":"提问者","avatar_url":"https://pic.zhimg.com/asker.jpg"}},"author":{"id":"answerer-id","url_token":"answerer","name":"回答者"}}}],"paging":{"is_end":true,"next":null}}"#.utf8
        )

        let item = try XCTUnwrap(
            FeedResponseMapper.page(from: data, policy: .search).items.first
        )

        XCTAssertEqual(item.author?.memberID, "answerer-id")
        XCTAssertEqual(item.questionAuthor?.memberID, "asker-id")
        XCTAssertEqual(item.questionAuthor?.displayName, "提问者")
    }

    func testAnswerWithoutQuestionAuthorDoesNotUseAnswerAuthorForBlocking() throws {
        let data = Data(
            #"{"data":[{"target":{"id":42,"type":"answer","excerpt":"回答","question":{"id":7,"title":"问题"},"author":{"id":"answerer-id","url_token":"answerer","name":"回答者"}}}],"paging":{"is_end":true,"next":null}}"#.utf8
        )

        let item = try XCTUnwrap(
            FeedResponseMapper.page(from: data, policy: .search).items.first
        )

        XCTAssertEqual(item.author?.memberID, "answerer-id")
        XCTAssertNil(item.questionAuthor)
    }

    func testQuestionProjectionUsesItsOwnAuthorAsQuestionAuthor() throws {
        let data = Data(
            #"{"data":[{"target":{"id":7,"type":"question","title":"问题","author":{"id":"asker-id","url_token":"asker","name":"提问者"}}}],"paging":{"is_end":true,"next":null}}"#.utf8
        )

        let item = try XCTUnwrap(
            FeedResponseMapper.page(from: data, policy: .hot).items.first
        )

        XCTAssertNil(item.author)
        XCTAssertEqual(item.questionAuthor?.memberID, "asker-id")
    }

    func testQuestionAuthorVisibilityKeepsUnknownAuthorsAndFiltersExactMemberID() {
        let blockedAuthor = FeedAuthorDTO(
            memberID: "blocked",
            urlToken: "blocked-token",
            displayName: "已屏蔽提问者",
            avatarURL: nil,
            headline: ""
        )
        let visibleAuthor = FeedAuthorDTO(
            memberID: "visible",
            urlToken: "visible-token",
            displayName: "其他提问者",
            avatarURL: nil,
            headline: ""
        )
        let blocked = feedQuestion(id: 1, questionAuthor: blockedAuthor)
        let visible = feedQuestion(id: 2, questionAuthor: visibleAuthor)
        let unknown = feedQuestion(id: 3, questionAuthor: nil)

        XCTAssertEqual(
            FeedQuestionAuthorVisibilityPolicy.visibleItems(
                from: [blocked, visible, unknown],
                blockedMemberIDs: ["blocked"]
            ).map(\.id.contentID),
            ["2", "3"]
        )
    }

    func testVideoProjectionUsesEmbeddedHighestBitratePlaybackURL() throws {
        let page = try FeedResponseMapper.page(from: FeedFixtures.videoPage, policy: .search)
        let item = try XCTUnwrap(page.items.first)
        guard case let .video(route) = item.route else {
            return XCTFail("Expected native video route")
        }

        XCTAssertEqual(route.contentID, 90)
        XCTAssertEqual(route.videoID, 901)
        XCTAssertEqual(route.contentType, .zvideo)
        XCTAssertEqual(route.thumbnailURL, URL(string: "https://pic.zhimg.com/video.jpg"))
        XCTAssertEqual(route.playbackURL, URL(string: "https://video.vzuu.com/hd.mp4"))
        XCTAssertEqual(route.webURL, URL(string: "https://www.zhihu.com/zvideo/90"))
    }

    func testPinProjectionUsesTypedTextAndBoundedSemanticMedia() throws {
        let page = try FeedResponseMapper.page(from: FeedFixtures.pinPage, policy: .search)
        let item = try XCTUnwrap(page.items.first)

        XCTAssertEqual(item.kind, .pin)
        XCTAssertEqual(item.title, "List<Integer> 后面的标题")
        XCTAssertEqual(item.summary, "正文 List<Integer> 后面的内容")
        XCTAssertEqual(item.media.count, 4)
        XCTAssertEqual(item.media.first?.kind, .animatedImage)
        XCTAssertEqual(item.media.first?.sourceURL, URL(string: "https://pic.zhimg.com/animated.gif"))
        XCTAssertEqual(item.media.first?.previewURL, URL(string: "https://pic.zhimg.com/animated-preview.jpg"))
        XCTAssertEqual(item.media.first?.pixelWidth, 1200)
        XCTAssertEqual(item.media.first?.pixelHeight, 800)
        XCTAssertEqual(FeedMediaPreviewPolicy.visibleMedia(from: item.media).count, 3)
        XCTAssertEqual(item.route, .pin(pinID: 574))
    }

    func testPinProjectionFallsBackToLegacyExcerptWhenTypedTextIsUnavailable() throws {
        let page = try FeedResponseMapper.page(from: FeedFixtures.legacyPinPage, policy: .search)
        let item = try XCTUnwrap(page.items.first)

        XCTAssertEqual(item.title, "兼容摘要")
        XCTAssertNil(item.summary)
        XCTAssertTrue(item.media.isEmpty)
    }

    func testPinProjectionPromotesUntitledChineseBodyAndBoundsTallImageMetadata() throws {
        let page = try FeedResponseMapper.page(from: FeedFixtures.untitledTallPinPage, policy: .search)
        let item = try XCTUnwrap(page.items.first)

        XCTAssertEqual(item.title, "新举措。效果如何，拭目以待吧。")
        XCTAssertNil(item.summary)
        XCTAssertEqual(item.media.count, 1)
        XCTAssertEqual(item.media.first?.pixelWidth, 1_279)
        XCTAssertEqual(item.media.first?.pixelHeight, 2_781)
        XCTAssertEqual(
            item.media.first?.sourceURL,
            URL(string: "https://pic4.zhimg.com/100/tall_720w.jpg")
        )
    }

    func testSearchProjectionSkipsNonContentSearchCards() throws {
        let page = try FeedResponseMapper.page(
            from: FeedFixtures.searchPageWithStructuredDescription,
            policy: .search
        )

        XCTAssertEqual(page.items.count, 1)
        XCTAssertEqual(page.items.first?.route, .article(articleID: 81, title: "原生搜索文章"))
    }

    func testNonSearchCommercialCardsAreSkippedInsteadOfBecomingNoOpRows() throws {
        let page = try FeedResponseMapper.page(from: FeedFixtures.nonContentSearchPage, policy: .search)
        XCTAssertTrue(page.items.isEmpty)
    }

    func testUntrustedPagingURLRejectsWholePageBeforeItCanReceiveCredentials() throws {
        XCTAssertThrowsError(try FeedResponseMapper.page(from: FeedFixtures.untrustedPagingPage, policy: .hot)) {
            XCTAssertEqual($0 as? ZhihuAPIError, .malformedPayload)
        }
    }

    func testSuggestionsPreserveOrderAndAreCappedAtFifteen() throws {
        let suggestions = try FeedResponseMapper.suggestions(from: FeedFixtures.suggestions)
        XCTAssertEqual(suggestions.count, 15)
        XCTAssertEqual(suggestions.first?.query, "热搜 1")
        XCTAssertEqual(suggestions.last?.query, "热搜 15")
    }

    func testAPIClientAppliesAccountHeadersAndMergesResponseCookie() async throws {
        let recorder = FeedRequestRecorder()
        FeedURLProtocol.setHandler { request in
            recorder.record(request)
            return (200, Data("{}".utf8), ["Set-Cookie": "captcha_session=updated; Path=/; Secure"])
        }
        let account = FeedAccountStore(
            json: #"{"cookies":{"d_c0":"device-cookie","z_c0":"login-cookie","_xsrf":"token"},"userAgent":"feed-agent"}"#
        )
        let client = ZhihuAPIClient(accountStore: account, session: makeFeedSession())

        _ = try await client.data(for: URL(string: "https://www.zhihu.com/api/v4/search/hot_search")!)
        let request = try XCTUnwrap(recorder.request)
        XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent"), "feed-agent")
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-xsrftoken"), "token")
        XCTAssertTrue(request.value(forHTTPHeaderField: "Cookie")?.contains("z_c0=login-cookie") == true)
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-zse-93"), ZhihuRequestSignature.zse93)
        XCTAssertTrue(request.value(forHTTPHeaderField: "x-zse-96")?.hasPrefix("2.0_") == true)
        XCTAssertTrue(try XCTUnwrap(account.load()).contains(#""captcha_session":"updated""#))
    }

    func testAccountRequiredRejectsSessionWithoutLoginCookieBeforeNetworkRequest() async throws {
        let recorder = FeedRequestRecorder()
        FeedURLProtocol.setHandler { request in
            recorder.record(request)
            return (200, Data("{}".utf8), [:])
        }
        let account = FeedAccountStore(
            json: #"{"cookies":{"d_c0":"device-cookie"},"userAgent":"feed-agent"}"#
        )
        let client = ZhihuAPIClient(accountStore: account, session: makeFeedSession())

        do {
            _ = try await client.data(
                for: URL(string: "https://www.zhihu.com/api/v4/me")!,
                authentication: .accountRequired
            )
            XCTFail("Expected the incomplete account session to require login")
        } catch {
            XCTAssertEqual(error as? ZhihuAPIError, .authenticationRequired)
        }
        XCTAssertNil(recorder.request)
    }

    func testBlankResponseLoginCookieDoesNotEraseVerifiedSession() throws {
        let blankLoginCookie = try XCTUnwrap(
            HTTPCookie(properties: [
                .name: "z_c0",
                .value: "",
                .domain: ".zhihu.com",
                .path: "/",
            ])
        )
        let source = #"{"login":true,"cookies":{"d_c0":"device-cookie","z_c0":"login-cookie"},"future":7}"#

        let merged = try XCTUnwrap(
            ZhihuAccountSessionCodec.merging(cookies: [blankLoginCookie], into: source)
        )
        let credentials = try XCTUnwrap(ZhihuAccountSessionCodec.credentials(from: merged))

        XCTAssertEqual(credentials.cookies["z_c0"], "login-cookie")
        XCTAssertEqual(credentials.cookies["d_c0"], "device-cookie")
        XCTAssertTrue(merged.contains(#""future":7"#))
    }

    func testAPIClientKeepsLoginCookieWhenSuccessfulResponseAttemptsToClearIt() async throws {
        FeedURLProtocol.setHandler { _ in
            (
                200,
                Data("{}".utf8),
                ["Set-Cookie": "z_c0=; Max-Age=0; Path=/; Secure"]
            )
        }
        let account = FeedAccountStore(
            json: #"{"login":true,"cookies":{"d_c0":"device-cookie","z_c0":"login-cookie"},"userAgent":"feed-agent"}"#
        )
        let client = ZhihuAPIClient(accountStore: account, session: makeFeedSession())

        _ = try await client.data(
            for: URL(string: "https://www.zhihu.com/api/v4/me")!,
            authentication: .accountRequired
        )
        let credentials = try XCTUnwrap(
            ZhihuAccountSessionCodec.credentials(from: account.load())
        )

        XCTAssertEqual(credentials.cookies["z_c0"], "login-cookie")
        XCTAssertEqual(credentials.cookies["d_c0"], "device-cookie")
    }

    func testHomeRecommendationUsesAuthenticatedWebContract() async throws {
        let recorder = FeedRequestRecorder()
        FeedURLProtocol.setHandler { request in
            recorder.record(request)
            return (200, FeedFixtures.emptyPage, [:])
        }
        let client = ZhihuAPIClient(
            accountStore: FeedAccountStore(
                json: #"{"cookies":{"d_c0":"device-cookie","z_c0":"login-cookie","_xsrf":"token"},"userAgent":"feed-agent"}"#
            ),
            session: makeFeedSession()
        )
        let repository = URLSessionHomeFeedRepository(client: client)

        _ = try await repository.fetchPage(source: .web, after: nil)

        let request = try XCTUnwrap(recorder.request)
        let url = try XCTUnwrap(request.url)
        let items = try XCTUnwrap(
            URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
        )
        XCTAssertEqual(url.host, "www.zhihu.com")
        XCTAssertEqual(url.path, "/api/v3/feed/topstory/recommend")
        XCTAssertEqual(items.first(where: { $0.name == "desktop" })?.value, "true")
        XCTAssertEqual(items.first(where: { $0.name == "limit" })?.value, "10")
        XCTAssertEqual(items.first(where: { $0.name == "offset" })?.value, "0")
        XCTAssertEqual(
            items.first(where: { $0.name == "include" })?.value,
            "data[*].content,excerpt,headline,target.author.badge_v2,target.question.author"
        )
        XCTAssertTrue(request.value(forHTTPHeaderField: "Cookie")?.contains("z_c0=login-cookie") == true)
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-xsrftoken"), "token")
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-zse-93"), ZhihuRequestSignature.zse93)
        XCTAssertTrue(request.value(forHTTPHeaderField: "x-zse-96")?.hasPrefix("2.0_") == true)
    }

    func testHomeRecommendationRequiresCompleteAccountBeforeNetworkRequest() async {
        let recorder = FeedRequestRecorder()
        FeedURLProtocol.setHandler { request in
            recorder.record(request)
            return (200, FeedFixtures.emptyPage, [:])
        }
        let client = ZhihuAPIClient(
            accountStore: FeedAccountStore(
                json: #"{"cookies":{"d_c0":"device-cookie"},"userAgent":"feed-agent"}"#
            ),
            session: makeFeedSession()
        )
        let repository = URLSessionHomeFeedRepository(client: client)

        do {
            _ = try await repository.fetchPage(source: .web, after: nil)
            XCTFail("Expected home recommendation to require a complete account")
        } catch {
            XCTAssertEqual(error as? ZhihuAPIError, .authenticationRequired)
        }
        XCTAssertNil(recorder.request)
    }

    func testHomeAppRecommendationAllowsGuestContract() async throws {
        let recorder = FeedRequestRecorder()
        FeedURLProtocol.setHandler { request in
            recorder.record(request)
            return (200, FeedFixtures.emptyPage, [:])
        }
        let client = ZhihuAPIClient(
            accountStore: FeedAccountStore(json: nil),
            session: makeFeedSession()
        )
        let repository = URLSessionHomeFeedRepository(client: client)

        _ = try await repository.fetchPage(source: .app, after: nil)

        let request = try XCTUnwrap(recorder.request)
        let url = try XCTUnwrap(request.url)
        let items = try XCTUnwrap(
            URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
        )
        XCTAssertEqual(url.host, "api.zhihu.com")
        XCTAssertEqual(url.path, "/topstory/recommend")
        XCTAssertEqual(items.first(where: { $0.name == "limit" })?.value, "10")
        XCTAssertNil(request.value(forHTTPHeaderField: "Cookie"))
    }

    func testHotListUsesGuestCompatibleMobileContract() async throws {
        let recorder = FeedRequestRecorder()
        FeedURLProtocol.setHandler { request in
            recorder.record(request)
            return (200, FeedFixtures.mobileHotPage, [:])
        }
        let repository = URLSessionHotFeedRepository(
            accountStore: FeedAccountStore(json: nil),
            session: makeFeedSession()
        )

        let page = try await repository.fetchPage(after: nil)

        let request = try XCTUnwrap(recorder.request)
        let url = try XCTUnwrap(request.url)
        let items = try XCTUnwrap(
            URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
        )
        XCTAssertEqual(url.host, "api.zhihu.com")
        XCTAssertEqual(url.path, "/topstory/hot-list")
        XCTAssertEqual(items.first(where: { $0.name == "limit" })?.value, "50")
        XCTAssertNil(request.value(forHTTPHeaderField: "Cookie"))
        XCTAssertEqual(page.items.count, 1)
        XCTAssertEqual(
            page.items.first?.route,
            .question(questionID: 7, title: "游客热榜问题")
        )
    }

    func testAccountSessionCodecPreservesQuotedDeviceCookieRepresentation() throws {
        let account = [
            "cookies": [
                "d_c0": #""quoted-device-cookie""#,
                "z_c0": "login-cookie",
            ],
            "userAgent": "feed-agent",
        ] as [String: Any]
        let data = try JSONSerialization.data(withJSONObject: account, options: [.sortedKeys])
        let credentials = try XCTUnwrap(
            ZhihuAccountSessionCodec.credentials(from: String(decoding: data, as: UTF8.self))
        )
        let deviceCookie = try XCTUnwrap(credentials.cookies["d_c0"])

        XCTAssertEqual(Set(credentials.cookies.keys), ["d_c0", "z_c0"])
        XCTAssertTrue(deviceCookie.hasPrefix("\""))
        XCTAssertTrue(deviceCookie.hasSuffix("\""))
        XCTAssertEqual(deviceCookie.count, 22)
    }

    private func feedQuestion(
        id: Int64,
        questionAuthor: FeedAuthorDTO?
    ) -> FeedItemDTO {
        FeedItemDTO(
            id: FeedItemID(kind: .question, contentID: String(id)),
            kind: .question,
            title: "问题 \(id)",
            summary: nil,
            details: "问题",
            sourceLabel: nil,
            author: questionAuthor,
            questionAuthor: questionAuthor,
            thumbnailURL: nil,
            route: .question(questionID: id, title: "问题 \(id)")
        )
    }

    func testSearchRepositoryBuildsExistingFilterAndMemberRestrictionContract() async throws {
        let recorder = FeedRequestRecorder()
        FeedURLProtocol.setHandler { request in
            recorder.record(request)
            return (200, FeedFixtures.emptyPage, [:])
        }
        let repository = URLSessionSearchRepository(
            accountStore: FeedAccountStore(
                json: #"{"cookies":{"d_c0":"device-cookie","z_c0":"login-cookie"},"userAgent":"feed-agent"}"#
            ),
            session: makeFeedSession()
        )
        let criteria = SearchCriteria(
            query: "知乎 搜索/排序",
            restrictedMemberHashID: "member hash/id",
            sort: .latest,
            contentType: .answer,
            timeRange: .week
        )

        _ = try await repository.fetchPage(criteria: criteria, after: nil)
        let url = try XCTUnwrap(recorder.request?.url?.absoluteString)
        XCTAssertTrue(url.contains("q=%E7%9F%A5%E4%B9%8E+%E6%90%9C%E7%B4%A2%2F%E6%8E%92%E5%BA%8F"))
        XCTAssertTrue(url.contains("restricted_scene=member"))
        XCTAssertTrue(url.contains("restricted_field=member_hash_id"))
        XCTAssertTrue(url.contains("restricted_value=member+hash%2Fid"))
        XCTAssertTrue(url.contains("sort=created_time"))
        XCTAssertTrue(url.contains("vertical=answer"))
        XCTAssertTrue(url.contains("time_interval=a_week"))
        XCTAssertTrue(url.contains("include="))
        let request = try XCTUnwrap(recorder.request)
        XCTAssertTrue(request.value(forHTTPHeaderField: "Cookie")?.contains("z_c0=login-cookie") == true)
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-zse-93"), ZhihuRequestSignature.zse93)
        XCTAssertTrue(request.value(forHTTPHeaderField: "x-zse-96")?.hasPrefix("2.0_") == true)
    }

    func testSearchSuggestionsUseAuthenticatedSignature() async throws {
        let recorder = FeedRequestRecorder()
        FeedURLProtocol.setHandler { request in
            recorder.record(request)
            return (200, FeedFixtures.suggestions, [:])
        }
        let repository = URLSessionSearchRepository(
            accountStore: FeedAccountStore(
                json: #"{"cookies":{"d_c0":"device-cookie","z_c0":"login-cookie"},"userAgent":"feed-agent"}"#
            ),
            session: makeFeedSession()
        )

        let suggestions = try await repository.fetchSuggestions()

        XCTAssertEqual(suggestions.count, 15)
        let request = try XCTUnwrap(recorder.request)
        XCTAssertEqual(request.url?.path, "/api/v4/search/hot_search")
        XCTAssertTrue(request.value(forHTTPHeaderField: "Cookie")?.contains("z_c0=login-cookie") == true)
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-zse-93"), ZhihuRequestSignature.zse93)
        XCTAssertTrue(request.value(forHTTPHeaderField: "x-zse-96")?.hasPrefix("2.0_") == true)
    }

    func testSearchRepositoryRejectsMissingAccountBeforeNetworkRequest() async {
        let recorder = FeedRequestRecorder()
        FeedURLProtocol.setHandler { request in
            recorder.record(request)
            return (200, FeedFixtures.emptyPage, [:])
        }
        let repository = URLSessionSearchRepository(
            accountStore: FeedAccountStore(json: nil),
            session: makeFeedSession()
        )

        do {
            _ = try await repository.fetchSuggestions()
            XCTFail("Expected search suggestion authentication failure")
        } catch {
            XCTAssertEqual(error as? ZhihuAPIError, .authenticationRequired)
        }
        do {
            _ = try await repository.fetchPage(
                criteria: SearchCriteria(
                    query: "Swift",
                    restrictedMemberHashID: nil,
                    sort: .relevance,
                    contentType: .all,
                    timeRange: .all
                ),
                after: nil
            )
            XCTFail("Expected search result authentication failure")
        } catch {
            XCTAssertEqual(error as? ZhihuAPIError, .authenticationRequired)
        }

        XCTAssertNil(recorder.request)
    }

    func testAPIRequestPolicyUsesKnownHostAndPathPairs() throws {
        XCTAssertTrue(
            ZhihuAPIURLPolicy.allowsAPIRequest(
                try XCTUnwrap(URL(string: "https://www.zhihu.com/api/v4/search/hot_search"))
            )
        )
        XCTAssertTrue(
            ZhihuAPIURLPolicy.allowsAPIRequest(
                try XCTUnwrap(URL(string: "https://www.zhihu.com/api/v3/feed/topstory/recommend"))
            )
        )
        XCTAssertTrue(
            ZhihuAPIURLPolicy.allowsAPIRequest(
                try XCTUnwrap(URL(string: "https://api.zhihu.com/notifications/v3/message/v3"))
            )
        )
        XCTAssertTrue(
            ZhihuAPIURLPolicy.allowsAPIRequest(
                try XCTUnwrap(URL(string: "https://api.zhihu.com/search_v3?offset=20"))
            )
        )
        XCTAssertTrue(
            ZhihuAPIURLPolicy.allowsAPIRequest(
                try XCTUnwrap(URL(string: "https://news-at.zhihu.com/api/4/stories/latest"))
            )
        )
        XCTAssertFalse(
            ZhihuAPIURLPolicy.allowsAPIRequest(
                try XCTUnwrap(URL(string: "https://www.zhihu.com/question/7"))
            )
        )
        XCTAssertFalse(
            ZhihuAPIURLPolicy.allowsAPIRequest(
                try XCTUnwrap(URL(string: "https://unknown.zhihu.com/api/v4/steal"))
            )
        )
        XCTAssertFalse(
            ZhihuAPIURLPolicy.allowsAPIRequest(
                try XCTUnwrap(URL(string: "https://api.zhihu.com/search_v4?offset=20"))
            )
        )
        XCTAssertFalse(
            ZhihuAPIURLPolicy.allows(
                try XCTUnwrap(URL(string: "https://user:password@www.zhihu.com/api/v4/me"))
            )
        )
    }

    func testAccountSessionCookieMergePreservesUnknownFieldsAndRejectsForeignDomains() throws {
        let trusted = try XCTUnwrap(
            HTTPCookie(properties: [
                .name: "captcha_session",
                .value: "updated",
                .domain: ".zhihu.com",
                .path: "/",
            ])
        )
        let foreign = try XCTUnwrap(
            HTTPCookie(properties: [
                .name: "foreign",
                .value: "ignored",
                .domain: ".example.com",
                .path: "/",
            ])
        )
        let source = #"{"cookies":{"z_c0":"token"},"userAgent":"agent","future":{"value":1}}"#

        let merged = try XCTUnwrap(
            ZhihuAccountSessionCodec.merging(cookies: [trusted, foreign], into: source)
        )
        let root = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(merged.utf8)) as? [String: Any]
        )
        let cookies = try XCTUnwrap(root["cookies"] as? [String: String])
        XCTAssertEqual(cookies["z_c0"], "token")
        XCTAssertEqual(cookies["captcha_session"], "updated")
        XCTAssertNil(cookies["foreign"])
        XCTAssertNotNil(root["future"])
    }
}

private enum FeedFixtures {
    static let hotPage = Data(
        #"{"data":[{"type":"hot_list_feed","detail_text":"热度 100 万","target":{"id":42,"type":"answer","url":"https://api.zhihu.com/answers/42","excerpt":"回答摘要","voteup_count":475,"comment_count":138,"thumbnail":"https://pic.zhimg.com/answer.jpg","question":{"id":7,"type":"question","title":"问题标题"},"author":{"id":"member","url_token":"author","name":"作者","headline":"简介","avatar_url":"https://pic.zhimg.com/avatar.jpg"}}}],"paging":{"is_end":false,"next":"http://www.zhihu.com/api/v3/hot?page=2"}}"#.utf8
    )

    static let mobileHotPage = Data(
        #"{"data":[{"type":"hot_list_feed","detail_text":"622 万热度","target":{"id":7,"type":"question","title":"游客热榜问题","excerpt":"问题摘要","answer_count":254,"follower_count":951,"comment_count":0,"author":{"id":"0","url_token":"","name":"用户"}}}],"paging":{"is_end":true,"next":""}}"#.utf8
    )

    static let searchPage = Data(
        #"{"data":[{"type":"search_result","id":"result-1","object":{"id":"81","type":"article","title":"原生搜索文章","excerpt":"文章摘要","voteup_count":12,"comment_count":3,"thumbnail_info":{"thumbnails":[{"url":"https://pic.zhimg.com/article.jpg"}]},"author":{"id":"member","url_token":"author","name":"作者","headline":"简介","avatar_url":"https://pic.zhimg.com/avatar.jpg"}}}],"paging":{"is_end":true,"next":null}}"#.utf8
    )

    static let videoPage = Data(
        #"{"data":[{"target":{"id":"90","type":"video","title":"原生视频","excerpt":"视频摘要","vote_count":12,"comment_count":3,"thumbnail_extra_info":{"video_id":"901","url":"https://pic.zhimg.com/video.jpg","playlist":{"ld":{"url":"https://video.vzuu.com/ld.mp4","bitrate":100},"sd":{"url":"https://video.vzuu.com/sd.mp4","bitrate":200},"hd":{"url":"https://video.vzuu.com/hd.mp4","bitrate":300}}}}}],"paging":{"is_end":true,"next":null}}"#.utf8
    )

    static let pinPage = Data(
        #"{"data":[{"target":{"id":574,"type":"pin","excerpt_title":"旧摘要","like_count":8,"comment_count":3,"author":{"id":"member","url_token":"author","name":"作者","headline":"","avatar_url":"https://pic.zhimg.com/avatar.jpg"},"content":[{"type":"image","url":"https://pic.zhimg.com/animated.gif","thumbnail":"https://pic.zhimg.com/animated-preview.jpg","width":1200,"height":800,"is_gif":true,"original_url":"https://pic.zhimg.com/original.gif"},{"type":"text","title":"List<Integer> 后面的标题","content":"<p>正文 List&lt;Integer&gt; 后面的内容</p>"},{"type":"image","url":"https://pic.zhimg.com/2.jpg","width":640,"height":480,"is_gif":false},{"type":"image","url":"https://pic.zhimg.com/3.jpg","width":640,"height":480,"is_gif":false},{"type":"image","url":"https://pic.zhimg.com/4.jpg","width":640,"height":480,"is_gif":false}]} }],"paging":{"is_end":true,"next":null}}"#.utf8
    )

    static let legacyPinPage = Data(
        #"{"data":[{"target":{"id":575,"type":"pin","excerpt_title":"<p>兼容摘要</p>","content":{"unexpected":"legacy-shape"}}}],"paging":{"is_end":true,"next":null}}"#.utf8
    )

    static let untitledTallPinPage = Data(
        #"{"data":[{"target":{"id":"2065396329153663168","type":"pin","like_count":15,"comment_count":8,"author":{"id":"member","url_token":"author","name":"作者","headline":""},"content":[{"title":"","content":"<p>新举措。效果如何，拭目以待吧。</p>","type":"text"},{"url":"https://pic4.zhimg.com/100/tall_720w.jpg","original_url":"https://pica.zhimg.com/tall.jpg","thumbnail":"","width":1279,"height":2781,"type":"image","is_gif":false}]}}],"paging":{"is_end":true,"next":null}}"#.utf8
    )

    static let searchPageWithStructuredDescription = Data(
        #"{"data":[{"type":"hot_timing","object":{"type":"hot_timing","title":"热点聚合","description":{"type":"question","object":{"id":"9","type":"question","title":"聚合问题"}}}},{"type":"knowledge_ad","object":{"header":{"card_title":"电子书"},"body":{"title":"商品卡片"},"footer":""}},{"type":"relevant_query","object":null},{"type":"search_result","id":"result-1","object":{"id":"81","type":"article","title":"原生搜索文章","excerpt":"文章摘要","voteup_count":12,"comment_count":3,"thumbnail_info":{"thumbnails":[{"url":"https://pic.zhimg.com/article.jpg"}]},"author":{"id":"member","url_token":"author","name":"作者","headline":"简介","avatar_url":"https://pic.zhimg.com/avatar.jpg"}}}],"paging":{"is_end":true,"next":null}}"#.utf8
    )

    static let nonContentSearchPage = Data(
        #"{"data":[{"type":"knowledge_ad","object":{"id":"1","type":"paid_column","title":"广告"}}],"paging":{"is_end":true,"next":null}}"#.utf8
    )

    static let untrustedPagingPage = Data(
        #"{"data":[],"paging":{"is_end":false,"next":"https://attacker.example/steal"}}"#.utf8
    )

    static let emptyPage = Data(#"{"data":[],"paging":{"is_end":true,"next":null}}"#.utf8)

    static let suggestions: Data = {
        let rows = (1...18).map { #"{"query":"热搜 \#($0)","hot_show":"\#($0) 万"}"# }.joined(separator: ",")
        return Data(#"{"hot_search_queries":[\#(rows)]}"#.utf8)
    }()
}

private func makeFeedSession() -> URLSession {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [FeedURLProtocol.self]
    return URLSession(configuration: configuration)
}

private final class FeedURLProtocol: URLProtocol {
    typealias Handler = @Sendable (URLRequest) throws -> (Int, Data, [String: String])

    private static let lock = NSLock()
    private static var storedHandler: Handler?

    static func setHandler(_ handler: Handler?) {
        lock.lock()
        storedHandler = handler
        lock.unlock()
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.lock()
        let handler = Self.storedHandler
        Self.lock.unlock()
        guard let handler else {
            client?.urlProtocol(self, didFailWithError: ZhihuAPIError.invalidResponse)
            return
        }
        do {
            let (status, data, headers) = try handler(request)
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: status,
                httpVersion: "HTTP/1.1",
                headerFields: headers
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private final class FeedRequestRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storedRequest: URLRequest?

    var request: URLRequest? {
        lock.lock()
        defer { lock.unlock() }
        return storedRequest
    }

    func record(_ request: URLRequest) {
        let captured = URLRequestBodyCapture.capture(request)
        lock.lock()
        storedRequest = captured
        lock.unlock()
    }
}

enum URLRequestBodyCapture {
    static func capture(_ request: URLRequest) -> URLRequest {
        guard request.httpBody == nil, let stream = request.httpBodyStream else { return request }
        stream.open()
        defer { stream.close() }

        var body = Data()
        var buffer = [UInt8](repeating: 0, count: 4_096)
        while true {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count > 0 {
                body.append(contentsOf: buffer.prefix(count))
            } else if count == 0 {
                var captured = request
                captured.httpBodyStream = nil
                captured.httpBody = body
                return captured
            } else {
                return request
            }
        }
    }
}

private final class FeedAccountStore: AccountJSONStore, @unchecked Sendable {
    private let lock = NSLock()
    private var json: String?

    init(json: String?) { self.json = json }

    func load() throws -> String? {
        lock.lock()
        defer { lock.unlock() }
        return json
    }

    func save(_ accountJSON: String) throws {
        lock.lock()
        json = accountJSON
        lock.unlock()
    }

    func clear() throws {
        lock.lock()
        json = nil
        lock.unlock()
    }

    func update(_ transform: (String?) throws -> String?) throws {
        lock.lock()
        defer { lock.unlock() }
        json = try transform(json)
    }
}
