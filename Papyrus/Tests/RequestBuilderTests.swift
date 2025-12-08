import XCTest
@testable import Papyrus

final class RequestBuilderTests: XCTestCase {
    func testPath() throws {
        let req = RequestBuilder(baseURL: "foo/", method: "bar", path: "baz")
        XCTAssertEqual(try req.fullURL().absoluteString, "foo/baz")
    }

    func testPathNoTrailingSlash() throws {
        let req = RequestBuilder(baseURL: "foo", method: "bar", path: "/baz")
        XCTAssertEqual(try req.fullURL().absoluteString, "foo/baz")
    }

    func testPathDoubleSlash() throws {
        let req = RequestBuilder(baseURL: "foo/", method: "bar", path: "/baz")
        XCTAssertEqual(try req.fullURL().absoluteString, "foo/baz")
    }

    func testMultipart() throws {
        var req = RequestBuilder(baseURL: "foo/", method: "bar", path: "/baz")
        let encoder = MultipartEncoder(boundary: UUID().uuidString)
        req.requestBodyEncoder = encoder
        req.addField("a", value: Part(data: Data("one".utf8), fileName: "one.txt", mimeType: "text/plain"))
        req.addField("b", value: Part(data: Data("two".utf8)))
        let (body, headers) = try req.bodyAndHeaders()
        guard let body else {
            XCTFail()
            return
        }

        // 0. Assert Headers

        XCTAssertEqual(headers, [
            "Content-Type": "multipart/form-data; boundary=\(encoder.boundary)",
            "Content-Length": "266"
        ])

        // 1. Assert Body

        XCTAssertEqual(body.string, """
            --\(encoder.boundary)\r
            Content-Disposition: form-data; name="a"; filename="one.txt"\r
            Content-Type: text/plain\r
            \r
            one\r
            --\(encoder.boundary)\r
            Content-Disposition: form-data; name="b"\r
            \r
            two\r
            --\(encoder.boundary)--\r

            """
        )
    }

    func testJSON() async throws {
        var req = RequestBuilder(baseURL: "foo/", method: "bar", path: "/baz")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        req.requestBodyEncoder = encoder
        req.addField("a", value: "one")
        req.addField("b", value: "two")
        let (body, headers) = try req.bodyAndHeaders()
        guard let body else {
            XCTFail()
            return
        }

        // 0. Assert Headers

        XCTAssertEqual(headers, [
            "Content-Type": "application/json",
            "Content-Length": "32"
        ])

        // 1. Assert Body

        XCTAssertEqual(body.string, """
            {
              "a" : "one",
              "b" : "two"
            }
            """
        )
    }

    func testURLForm() async throws {
        var req = RequestBuilder(baseURL: "foo/", method: "bar", path: "/baz")
        req.requestBodyEncoder = URLEncodedFormEncoder()
        req.addField("a", value: "one")
        req.addField("b", value: "two")
        let (body, headers) = try req.bodyAndHeaders()
        guard let body else {
            XCTFail()
            return
        }

        // 0. Assert Headers

        XCTAssertEqual(headers, [
            "Content-Type": "application/x-www-form-urlencoded",
            "Content-Length": "11"
        ])

        // 1. Assert Body
        XCTAssertTrue(["a=one&b=two", "b=two&a=one"].contains(body.string))
    }

    // MARK: - Encoding Strategy Tests

    func testJSONDateEncodingStrategyISO8601() throws {
        var req = RequestBuilder(baseURL: "foo/", method: "bar", path: "/baz")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        req.requestBodyEncoder = encoder

        let date = Date(timeIntervalSince1970: 0) // 1970-01-01T00:00:00Z
        req.addField("date", value: date)

        let (body, _) = try req.bodyAndHeaders()
        guard let body else {
            XCTFail()
            return
        }

        XCTAssertEqual(body.string, """
            {"date":"1970-01-01T00:00:00Z"}
            """)
    }

    func testJSONDateEncodingStrategySecondsSince1970() throws {
        var req = RequestBuilder(baseURL: "foo/", method: "bar", path: "/baz")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        req.requestBodyEncoder = encoder

        let date = Date(timeIntervalSince1970: 1000.5)
        req.addField("date", value: date)

        let (body, _) = try req.bodyAndHeaders()
        guard let body else {
            XCTFail()
            return
        }

        XCTAssertEqual(body.string, """
            {"date":1000.5}
            """)
    }

    func testJSONDateEncodingStrategyMillisecondsSince1970() throws {
        var req = RequestBuilder(baseURL: "foo/", method: "bar", path: "/baz")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        req.requestBodyEncoder = encoder

        let date = Date(timeIntervalSince1970: 10.5)
        req.addField("date", value: date)

        let (body, _) = try req.bodyAndHeaders()
        guard let body else {
            XCTFail()
            return
        }

        // Platform differences: macOS outputs "10500", Linux Swift 5.9 outputs "10500.0"
        XCTAssertTrue(
            body.string == #"{"date":10500}"# ||
            body.string == #"{"date":10500.0}"#
        )
    }

    func testJSONDateEncodingStrategyFormatted() throws {
        var req = RequestBuilder(baseURL: "foo/", method: "bar", path: "/baz")
        let encoder = JSONEncoder()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")
        encoder.dateEncodingStrategy = .formatted(formatter)
        req.requestBodyEncoder = encoder

        let date = Date(timeIntervalSince1970: 0)
        req.addField("date", value: date)

        let (body, _) = try req.bodyAndHeaders()
        guard let body else {
            XCTFail()
            return
        }

        XCTAssertEqual(body.string, """
            {"date":"1970-01-01"}
            """)
    }

    func testJSONDataEncodingStrategyBase64() throws {
        var req = RequestBuilder(baseURL: "foo/", method: "bar", path: "/baz")
        let encoder = JSONEncoder()
        encoder.dataEncodingStrategy = .base64
        req.requestBodyEncoder = encoder

        let data = Data("hello".utf8)
        req.addField("data", value: data)

        let (body, _) = try req.bodyAndHeaders()
        guard let body else {
            XCTFail()
            return
        }

        XCTAssertEqual(body.string, """
            {"data":"aGVsbG8="}
            """)
    }

    func testJSONMultipleFieldsWithDate() throws {
        var req = RequestBuilder(baseURL: "foo/", method: "bar", path: "/baz")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        encoder.outputFormatting = .sortedKeys
        req.requestBodyEncoder = encoder

        req.addField("name", value: "test")
        req.addField("createdAt", value: Date(timeIntervalSince1970: 1000))
        req.addField("count", value: 42)

        let (body, _) = try req.bodyAndHeaders()
        guard let body else {
            XCTFail()
            return
        }

        // Platform differences: macOS outputs "1000", Linux Swift 5.9 outputs "1000.0"
        XCTAssertTrue(
            body.string == #"{"count":42,"createdAt":1000,"name":"test"}"# ||
            body.string == #"{"count":42,"createdAt":1000.0,"name":"test"}"#
        )
    }

    func testQueryDateEncodingStrategy() throws {
        var req = RequestBuilder(baseURL: "https://api.example.com/", method: "GET", path: "search")
        var queryEncoder = req.queryEncoder
        queryEncoder.dateEncodingStrategy = .secondsSince1970
        req.queryEncoder = queryEncoder

        let date = Date(timeIntervalSince1970: 1000)
        req.addQuery("since", value: date)

        let url = try req.fullURL()
        XCTAssertEqual(url.absoluteString, "https://api.example.com/search?since=1000.0")
    }

    func testJSONNonConformingFloatEncodingStrategy() throws {
        var req = RequestBuilder(baseURL: "foo/", method: "bar", path: "/baz")
        let encoder = JSONEncoder()
        encoder.nonConformingFloatEncodingStrategy = .convertToString(
            positiveInfinity: "Infinity",
            negativeInfinity: "-Infinity",
            nan: "NaN"
        )
        req.requestBodyEncoder = encoder

        req.addField("value", value: Double.nan)

        let (body, _) = try req.bodyAndHeaders()
        guard let body else {
            XCTFail()
            return
        }

        XCTAssertEqual(body.string, """
            {"value":"NaN"}
            """)
    }
}

extension Data {
    fileprivate var string: String {
        String(decoding: self, as: UTF8.self)
    }
}
