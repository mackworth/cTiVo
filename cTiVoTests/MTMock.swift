//
//  MTMock.swift
//  cTiVoTests
//
//  Created by Steve Schmadeke on 8/9/22.
//  Copyright © 2022 cTiVo. All rights reserved.
//

import Foundation
import XCTest

enum MTMockError: Error {
    case message(String)
}

class MTMockURLProtocol: URLProtocol {
    static var responses = [URL?: (data: Data, response: URLResponse, error: Error?)]()
    static var counts = [URL?: Int]()
    static func reset() {
        responses = [URL?: (data: Data, response: URLResponse, error: Error?)]()
        counts = [URL?: Int]()
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else {
            XCTFail("missing request URL")
            client?.urlProtocol(self, didFailWithError: MTMockError.message("missing request URL"))
            return
        }
        MTMockURLProtocol.counts[url] = (MTMockURLProtocol.counts[url] ?? 0) + 1
        guard let value = MTMockURLProtocol.responses[url] else {
            XCTFail("no configured mock")
            client?.urlProtocol(self, didFailWithError: MTMockError.message("no configured mock"))
            return
        }
        let (data, response, error) = value
        if let error = error {
            client?.urlProtocol(self, didFailWithError: error)
            return
        }
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() { }
}

func createMockSession() -> URLSession {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [MTMockURLProtocol.self]
    return URLSession(configuration: config)
}

func setMockResponse(for url: String, data: String, statusCode: Int, message: String? = nil) -> URL? {
    guard let encodedURL = url.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
        XCTFail("bad mock encoded URL");
        return nil
    }
    guard let key = URL(string: encodedURL) else {
        XCTFail("bad mock URL");
        return nil
    }
    guard let data = data.data(using: .utf8) else {
        XCTFail("bad mock data")
        return key
    }
    guard let response = HTTPURLResponse(
            url: key,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil) else {
        XCTFail("bad mock response")
        return key
    }
    let error: Error?
    if let message = message {
        error = MTMockError.message(message)
    } else {
        error = nil
    }
    MTMockURLProtocol.responses[key] = (data: data, response: response, error: error)
    return key
}
