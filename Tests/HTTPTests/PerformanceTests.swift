//
//  ServerTests.swift
//  Edge
//
//  Created by Tyler Fleming Cloutier on 10/30/16.
//
//

import Foundation
import XCTest
import PromiseKit
@testable import HTTP

func generateRandomBytes(_ num: Int) -> Data? {
    var data = Data(count: num)
    let result = data.withUnsafeMutableBytes {
        SecRandomCopyBytes(kSecRandomDefault, data.count, $0)
    }
    if result == errSecSuccess {
        return data
    } else {
        print("Problem generating random bytes")
        return nil
    }
}
let dataSize = 10_000_000
var bullshit: UInt16 = 0
let modnum: UInt16 = 1
let oneMBData = generateRandomBytes(dataSize)!
let rootUrl = "http://localhost:"
let session = URLSession(configuration: URLSessionConfiguration.background(withIdentifier: "background"))

class PerformanceTests: XCTestCase {

    struct TestError: Error {

    }

    private func postData(path: String) -> Promise<()> {

        let urlString = rootUrl + path
        let url = URL(string: urlString)!
        var req = URLRequest(url: url)

        req.httpMethod = "POST"
        req.httpBody = oneMBData

        return Promise { resolve, reject in
            session.dataTask(with: req) { (data, urlResp, err) in
                if let err = err {
                    reject(err)
                }
                resolve(())
            }.resume()
        }
    }

    private func getData(path: String) -> Promise<Data> {

        let urlString = rootUrl + path
        let url = URL(string: urlString)!
        var req = URLRequest(url: url)

        req.httpMethod = "GET"

        return Promise { resolve, reject in
            session.dataTask(with: req) { (data, urlResp, err) in
                if let err = err {
                    XCTFail("Error on response: \(err)")
                    reject(err)
                }
                guard let data = data else {
                    XCTFail("No data returned")
                    reject(TestError())
                    return
                }
                resolve(data)
            }.resume()
        }
    }

    private func emptyGet(path: String) -> Promise<()> {

        let foo = rootUrl + String(3000 + (bullshit % modnum))
        let urlString = foo + path
        print(urlString)
        let url = URL(string: urlString)!
        var req = URLRequest(url: url)

        req.httpMethod = "GET"

        return Promise { resolve, reject in
            print("ABOUT TO SEND")
            NSURLConnection.sendAsynchronousRequest(req, queue: OperationQueue.main) {(response, data, err) in
                if let err = err {
                    XCTFail("Error on response: \(err)")
                    reject(err)
                }
                resolve(())
            }
        }

    }

    func testPerformanceReceivingData() {
        self.measureMetrics(XCTestCase.defaultPerformanceMetrics, automaticallyStartMeasuring: false) {
            let app = Router()

            app.post("/post") { request -> Response in
                let count = request.body.count
                XCTAssertEqual(count, dataSize)
                return Response()
            }

            let server = HTTP.Server(delegate: app, reusePort: true)
            server.listen(host: "0.0.0.0", port: 3000)

            let expectSuccess = expectation(description: "Request was not successful.")

            self.startMeasuring()

            postData(path: "/post").then {
                expectSuccess.fulfill()
            }.catch { error in
                XCTFail(error.localizedDescription)
            }

            waitForExpectations(timeout: 5) { error in
                self.stopMeasuring()
                server.stop()
            }
        }
    }

    func testPerformanceSendingData() {
        self.measureMetrics(XCTestCase.defaultPerformanceMetrics, automaticallyStartMeasuring: false) {
            let app = Router()

            app.get("/get") { request -> Response in
                return Response(body: oneMBData)
            }

            let server = HTTP.Server(delegate: app, reusePort: true)
            server.listen(host: "0.0.0.0", port: 3000)

            let expectSuccess = expectation(description: "Request was not successful.")

            self.startMeasuring()

            getData(path: "/get").then { data in
                expectSuccess.fulfill()
                XCTAssertEqual(dataSize, data.count)
            }.catch { error in
                XCTFail(error.localizedDescription)
            }

            waitForExpectations(timeout: 5) { error in
                self.stopMeasuring()
                server.stop()
            }
        }
    }

    func testPerformanceConcurrentRequests() {
        self.measureMetrics(XCTestCase.defaultPerformanceMetrics, automaticallyStartMeasuring: false) {
            let app = Router()

            app.get("/get") { request -> Response in
                return Response()
            }

            print(bullshit)
            let server = HTTP.Server(delegate: app, reusePort: false)
            server.listen(host: "0.0.0.0", port: 3000 + (bullshit % modnum))


            self.startMeasuring()

            for _ in 0..<150 {
                let expectSuccess = self.expectation(description: "Request was not successful.")
                    self.emptyGet(path: "/get").then {
                        print("HAP")
                        expectSuccess.fulfill()
                    }.catch { error in
                        XCTFail(error.localizedDescription)
                    }
            }

            waitForExpectations(timeout: 5) { error in
                bullshit += 1
                server.stop()
                self.stopMeasuring()

            }

        }
    }

}

extension PerformanceTests {
    static var allTests = [
        ("testPerformanceSendingData", testPerformanceSendingData),
    ]
}

