import XCTest
@testable import NautaConnectCore

final class DirectPortalTransportTests: XCTestCase {
    func testSerializesDoubleSlashLoginPostRequest() {
        let url = URL(string: "https://secure.etecsa.net:8443//LoginServlet")!
        let body = Data("username=user%40nauta.com.cu".utf8)
        let data = HTTPWireCodec.serializeRequest(
            method: "POST",
            url: url,
            headers: [
                ("Host", "secure.etecsa.net:8443"),
                ("Content-Type", "application/x-www-form-urlencoded"),
            ],
            body: body
        )
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(text.hasPrefix("POST //LoginServlet HTTP/1.1\r\n"))
        XCTAssertTrue(text.contains("Content-Length: \(body.count)\r\n"))
        XCTAssertTrue(text.hasSuffix("\r\n\r\nusername=user%40nauta.com.cu"))
    }

    func testParsesContentLengthResponseAndCookies() throws {
        let raw = Data(
            (
                "HTTP/1.1 200 OK\r\n" +
                "Set-Cookie: JSESSIONID=ABC123; Path=/; Secure; HttpOnly\r\n" +
                "Content-Length: 5\r\n" +
                "\r\n" +
                "helloEXTRA"
            ).utf8
        )
        let response = try XCTUnwrap(HTTPWireCodec.parseResponse(from: raw))
        XCTAssertEqual(response.statusCode, 200)
        XCTAssertEqual(String(decoding: response.body, as: UTF8.self), "hello")
        XCTAssertEqual(
            HTTPWireCodec.parseCookies(from: response.headerValues("Set-Cookie")),
            ["JSESSIONID": "ABC123"]
        )
    }

    func testDecodesChunkedResponse() throws {
        let raw = Data(
            (
                "HTTP/1.1 200 OK\r\n" +
                "Transfer-Encoding: chunked\r\n" +
                "\r\n" +
                "5\r\nhello\r\n" +
                "6\r\n world\r\n" +
                "0\r\n\r\n"
            ).utf8
        )
        let response = try XCTUnwrap(HTTPWireCodec.parseResponse(from: raw))
        XCTAssertEqual(String(decoding: response.body, as: UTF8.self), "hello world")
    }

    func testDetectsIncompleteChunkedResponse() {
        let partial = Data(
            (
                "HTTP/1.1 200 OK\r\n" +
                "Transfer-Encoding: chunked\r\n" +
                "\r\n" +
                "5\r\nhello\r\n"
            ).utf8
        )
        let split = HTTPWireCodec.splitHeaderAndBody(in: partial)!
        let header = HTTPWireCodec.parseHeaderBlock(split.headerData)!
        XCTAssertFalse(
            HTTPWireCodec.isResponseComplete(
                buffer: partial,
                bodyStart: split.bodyStart,
                headers: header.headers
            )
        )
    }
}
