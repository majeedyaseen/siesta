//
//  ResourceRequestsSpec.swift
//  Siesta
//
//  Created by Paul on 2015/7/5.
//  Copyright © 2015 Bust Out Solutions. All rights reserved.
//

import Siesta
import Quick
import Nimble
import Nocilla

class ResourceRequestsSpec: ResourceSpecBase
    {
    override func resourceSpec(service: () -> Service, _ resource: () -> Resource)
        {
        it("starts in a blank state")
            {
            expect(resource().latestData).to(beNil())
            expect(resource().latestError).to(beNil())
            
            expect(resource().loading).to(beFalse())
            expect(resource().requests).to(beIdentialObjects([]))
            }
        
        describe("request()")
            {
            it("fetches the resource")
                {
                stubReqest(resource, "GET").andReturn(200)
                awaitNewData(resource().request(RequestMethod.GET))
                }
            
            it("handles various HTTP methods")
                {
                stubReqest(resource, "PATCH").andReturn(200)
                awaitNewData(resource().request(RequestMethod.PATCH))
                }
            
            it("does not update the resource state")
                {
                stubReqest(resource, "GET").andReturn(200)
                awaitNewData(resource().request(RequestMethod.GET))
                expect(resource().latestData).to(beNil())
                expect(resource().latestError).to(beNil())
                }
            
            it("can be cancelled")
                {
                let reqStub = stubReqest(resource, "GET").andReturn(200).delay()
                let req = resource().request(RequestMethod.GET)
                req.cancel()
                reqStub.go()
                awaitFailure(req, alreadyCompleted: true)
                }
            
            // TODO: How to reproduce these conditions in tests?
            pending("server response has no effect if it arrives but cancel() already called") { }
            pending("cancel() has no effect after request completed") { }
            
            it("tracks concurrent requests")
                {
                func stubDelayedAndLoad(ident: String) -> (LSStubResponseDSL, Request)
                    {
                    let reqStub = stubReqest(resource, "GET")
                        .withHeader("Request-ident", ident)
                        .andReturn(200)
                        .delay()
                    let req = resource().request(RequestMethod.GET)
                        { $0.setValue(ident, forHTTPHeaderField: "Request-ident") }
                    return (reqStub, req)
                    }
                
                let (reqStub0, req0) = stubDelayedAndLoad("zero"),
                    (reqStub1, req1) = stubDelayedAndLoad("one")
                
                expect(resource().loading).to(beTrue())
                expect(resource().requests).to(beIdentialObjects([req0, req1]))
                
                reqStub0.go()
                awaitNewData(req0)
                expect(resource().loading).to(beTrue())
                expect(resource().requests).to(beIdentialObjects([req1]))
                
                reqStub1.go()
                awaitNewData(req1)
                expect(resource().loading).to(beFalse())
                expect(resource().requests).to(beIdentialObjects([]))
                }
            
            context("POST/PUT/PATCH body")
                {
                it("handles raw data")
                    {
                    let bytes: [UInt8] = [0x00, 0xFF, 0x17, 0xCA]
                    let nsdata = NSData(bytes: bytes, length: bytes.count)
                    
                    stubReqest(resource, "POST")
                        .withHeader("Content-Type", "application/monkey")
                        .withBody(nsdata)
                        .andReturn(200)

                    awaitNewData(resource().request(.POST, data: nsdata, contentType: "application/monkey"))
                    }
                
                it("handles string data")
                    {
                    stubReqest(resource, "POST")
                        .withHeader("Content-Type", "text/plain; charset=utf-8")
                        .withBody("Très bien!")
                        .andReturn(200)

                    awaitNewData(resource().request(.POST, text: "Très bien!"))
                    }
                
                it("handles string encoding errors")
                    {
                    awaitFailure(
                        resource().request(.POST, text: "Hélas!", encoding: NSASCIIStringEncoding),
                        alreadyCompleted: true)
                    }
                
                it("handles JSON data")
                    {
                    stubReqest(resource, "PUT")
                        .withHeader("Content-Type", "application/json")
                        .withBody("{\"question\":[[2,\"be\"],[\"not\",2,\"be\"]]}")
                        .andReturn(200)

                    awaitNewData(resource().request(.PUT, json: ["question": [[2, "be"], ["not", 2, "be"]]]))
                    }
                
                it("handles JSON encoding errors")
                    {
                    awaitFailure(
                        resource().request(.POST, json: ["question": [2, UIView()]]),
                        alreadyCompleted: true)
                    }

                it("handles url-encoded param data")
                    {
                    stubReqest(resource, "PATCH")
                        .withHeader("Content-Type", "application/x-www-form-urlencoded")
                        .withBody("brown=cow&foo=bar&how=now")
                        .andReturn(200)

                    awaitNewData(resource().request(.PATCH, urlEncoded: ["foo": "bar", "how": "now", "brown": "cow"]))
                    }

                it("escapes url-encoded param data")
                    {
                    stubReqest(resource, "PATCH")
                        .withHeader("Content-Type", "application/x-www-form-urlencoded")
                        .withBody("%E2%84%A5%3D%26=%E2%84%8C%E2%84%91%3D%26&f%E2%80%A2%E2%80%A2=b%20r")
                        .andReturn(200)

                    awaitNewData(resource().request(.PATCH, urlEncoded: ["f••": "b r", "℥=&": "ℌℑ=&"]))
                    }
                }
            }

        describe("load()")
            {
            it("marks that the resource is loading")
                {
                expect(resource().loading).to(beFalse())
                
                stubReqest(resource, "GET").andReturn(200)
                let req = resource().load()
                expect(resource().loading).to(beTrue())
                
                awaitNewData(req)
                expect(resource().loading).to(beFalse())
                }
            
            it("stores the response data")
                {
                stubReqest(resource, "GET").andReturn(200)
                    .withBody("eep eep")
                awaitNewData(resource().load())
                
                expect(resource().latestData).notTo(beNil())
                expect(dataAsString(resource().latestData?.content)).to(equal("eep eep"))
                }
            
            it("stores the content type")
                {
                stubReqest(resource, "GET").andReturn(200)
                    .withHeader("cOnTeNt-TyPe", "text/monkey")
                awaitNewData(resource().load())
                
                expect(resource().latestData?.contentType).to(equal("text/monkey"))
                }
            
            it("extracts the charset if present")
                {
                stubReqest(resource, "GET").andReturn(200)
                    .withHeader("Content-type", "text/monkey; charset=utf-8")
                awaitNewData(resource().load())
                
                expect(resource().latestData?.charset).to(equal("utf-8"))
                }
            
            it("includes the charset in the content type")
                {
                stubReqest(resource, "GET").andReturn(200)
                    .withHeader("Content-type", "text/monkey; charset=utf-8")
                awaitNewData(resource().load())
                
                expect(resource().latestData?.contentType).to(equal("text/monkey; charset=utf-8"))
                }
            
            it("parses the charset")
                {
                let monkeyType = "text/monkey; body=fuzzy; charset=euc-jp; arms=long"
                stubReqest(resource, "GET").andReturn(200)
                    .withHeader("Content-type", monkeyType)
                awaitNewData(resource().load())
                
                expect(resource().latestData?.contentType).to(equal(monkeyType))
                expect(resource().latestData?.charset).to(equal("euc-jp"))
                }
            
            it("defaults content type to raw binary")
                {
                stubReqest(resource, "GET").andReturn(200)
                awaitNewData(resource().load())
                
                // Although Apple's NSURLResponse.contentType defaults to text/plain,
                // the correct default content type for HTTP is application/octet-stream.
                // http://www.w3.org/Protocols/rfc2616/rfc2616-sec7.html#sec7.2.1
                
                expect(resource().latestData?.contentType).to(equal("application/octet-stream"))
                }
                
            it("stores headers")
                {
                stubReqest(resource, "GET").andReturn(200)
                    .withHeader("Personal-Disposition", "Quirky")
                awaitNewData(resource().load())
                
                expect(resource().latestData?.header("Personal-Disposition")).to(equal("Quirky"))
                expect(resource().latestData?.header("pErsonal-dIsposition")).to(equal("Quirky"))
                expect(resource().latestData?.header("pErsonaldIsposition")).to(beNil())
                }
            
            it("handles missing etag")
                {
                stubReqest(resource, "GET").andReturn(200)
                awaitNewData(resource().load())
                
                expect(resource().latestData?.etag).to(beNil())
                }
            
            func sendAndWaitForSuccessfulRequest()
                {
                stubReqest(resource, "GET")
                    .andReturn(200)
                    .withHeader("eTaG", "123 456 xyz")
                    .withHeader("Content-Type", "applicaiton/zoogle+plotz")
                    .withBody("zoogleplotz")
                awaitNewData(resource().load())
                LSNocilla.sharedInstance().clearStubs()
                }
            
            func expectDataToBeUnchanged()
                {
                expect(dataAsString(resource().latestData?.content)).to(equal("zoogleplotz"))
                expect(resource().latestData?.contentType).to(equal("applicaiton/zoogle+plotz"))
                expect(resource().latestData?.etag).to(equal("123 456 xyz"))
                }
            
            context("receiving an etag")
                {
                beforeEach(sendAndWaitForSuccessfulRequest)
                
                it("stores the etag")
                    {
                    expect(resource().latestData?.etag).to(equal("123 456 xyz"))
                    }
                
                it("sends the etag with subsequent requests")
                    {
                    stubReqest(resource, "GET")
                        .withHeader("If-None-Match", "123 456 xyz")
                        .andReturn(304)
                    awaitNotModified(resource().load())
                    }
                
                it("handles subsequent 200 by replacing data")
                    {
                    stubReqest(resource, "GET")
                        .andReturn(200)
                        .withHeader("eTaG", "ABC DEF 789")
                        .withHeader("Content-Type", "applicaiton/ploogle+zotz")
                        .withBody("plooglezotz")
                    awaitNewData(resource().load())
                        
                    expect(dataAsString(resource().latestData?.content)).to(equal("plooglezotz"))
                    expect(resource().latestData?.contentType).to(equal("applicaiton/ploogle+zotz"))
                    expect(resource().latestData?.etag).to(equal("ABC DEF 789"))
                    }
                
                it("handles subsequent 304 by keeping existing data")
                    {
                    stubReqest(resource, "GET").andReturn(304)
                    awaitNotModified(resource().load())
                    
                    expectDataToBeUnchanged()
                    expect(resource().latestError).to(beNil())
                    }
                }
            
            it("handles request errors")
                {
                let sampleError = NSError(domain: "TestDomain", code: 12345, userInfo: nil)
                stubReqest(resource, "GET").andFailWithError(sampleError)
                awaitFailure(resource().load())
                
                expect(resource().latestData).to(beNil())
                expect(resource().latestError).notTo(beNil())
                expect(resource().latestError?.nsError).to(equal(sampleError))
                }
            
            // Testing all these HTTP codes individually because Apple likes
            // to treat specific ones as special cases.
            
            for statusCode in Array(400...410) + (500...505)
                {
                it("treats HTTP \(statusCode) as an error")
                    {
                    stubReqest(resource, "GET").andReturn(statusCode)
                    awaitFailure(resource().load())
                    
                    expect(resource().latestData).to(beNil())
                    expect(resource().latestError).notTo(beNil())
                    expect(resource().latestError?.httpStatusCode).to(equal(statusCode))
                    }
                }
            
            it("preserves last valid data after error")
                {
                sendAndWaitForSuccessfulRequest()

                stubReqest(resource, "GET").andReturn(500)
                awaitFailure(resource().load())
                
                expectDataToBeUnchanged()
                }

            it("leaves everything unchanged after a cancelled request")
                {
                sendAndWaitForSuccessfulRequest()
                
                let reqStub = stubReqest(resource, "GET").andReturn(200).delay()
                let req = resource().load()
                req.cancel()
                reqStub.go()
                awaitFailure(req, alreadyCompleted: true)

                expectDataToBeUnchanged()
                expect(resource().latestError).to(beNil())
                }
            
            // TODO: test no internet connnection if possible
            
            it("generates error messages from NSError message")
                {
                let sampleError = NSError(
                    domain: "TestDomain", code: 12345,
                    userInfo: [NSLocalizedDescriptionKey: "KABOOM"])
                stubReqest(resource, "GET").andFailWithError(sampleError)
                awaitFailure(resource().load())
                
                expect(resource().latestError?.userMessage).to(equal("KABOOM"))
                }
            
            it("generates error messages from HTTP status codes")
                {
                stubReqest(resource, "GET").andReturn(404)
                awaitFailure(resource().load())
                
                expect(resource().latestError?.userMessage).to(equal("Not found"))
                }
            
            // TODO: test custom error message extraction
            
            // TODO: how should it handle redirects?
            }
        
        describe("loadIfNeeded()")
            {
            func expectToLoad(@autoclosure req: () -> Request?)
                {
                LSNocilla.sharedInstance().clearStubs()
                stubReqest(resource, "GET").andReturn(200) // Stub first...
                let reqMaterialized = req()                // ...then allow loading
                expect(reqMaterialized).notTo(beNil())
                expect(resource().loading).to(beTrue())
                awaitNewData(resource().load())
                }
            
            func expectNotToLoad(req: Request?)
                {
                expect(req).to(beNil())
                expect(resource().loading).to(beFalse())
                }
            
            it("loads a resource never before loaded")
                {
                expectToLoad(resource().loadIfNeeded())
                }
            
            context("with data present")
                {
                beforeEach
                    {
                    setResourceTime(1000)
                    expectToLoad(resource().load())
                    }
                
                it("does not load again soon")
                    {
                    setResourceTime(1010)
                    expectNotToLoad(resource().loadIfNeeded())
                    }
                
                it("loads again later")
                    {
                    setResourceTime(2000)
                    expectToLoad(resource().loadIfNeeded())
                    }
                
                it("respects custom expiration time")
                    {
                    service().configure("**") { $0.config.expirationTime = 1 }
                    expect(resource().config.expirationTime).to(equal(1))
                    setResourceTime(1002)
                    expectToLoad(resource().loadIfNeeded())
                    }
                }
            
            context("with an error present")
                {
                beforeEach
                    {
                    setResourceTime(1000)
                    stubReqest(resource, "GET").andReturn(404)
                    awaitFailure(resource().load())
                    }
                
                it("does not retry soon")
                    {
                    setResourceTime(1001)
                    expectNotToLoad(resource().loadIfNeeded())
                    }
                
                it("retries later")
                    {
                    setResourceTime(2000)
                    expectToLoad(resource().loadIfNeeded())
                    }
                
                it("respects custom retry time")
                    {
                    service().configure("**") { $0.config.retryTime = 1 }
                    setResourceTime(1002)
                    expectToLoad(resource().loadIfNeeded())
                    }
                }
            }

        describe("localEntityOverride()")
            {
            let arbitraryContentType = "content-can-be/anything"
            let arbitraryContent = specVar { NSCalendar(calendarIdentifier: NSCalendarIdentifierEthiopicAmeteMihret) as! AnyObject }
            let localData = specVar { Entity(content: arbitraryContent(), contentType: arbitraryContentType) }
            
            it("updates the data")
                {
                resource().localEntityOverride(localData())
                expect(resource().latestData?.content).to(beIdenticalTo(arbitraryContent()))
                expect(resource().latestData?.contentType).to(equal(arbitraryContentType))
                }

            it("clears the latest error")
                {
                stubReqest(resource, "GET").andReturn(500)
                awaitFailure(resource().load())
                expect(resource().latestError).notTo(beNil())

                resource().localEntityOverride(localData())
                expect(resource().latestData).notTo(beNil())
                expect(resource().latestError).to(beNil())
                }

            it("does not touch the transformer pipeline")
                {
                let rawData = "a string".dataUsingEncoding(NSASCIIStringEncoding)
                resource().localEntityOverride(Entity(content: rawData!, contentType: "text/plain"))
                expect(resource().latestData?.content as? NSData).to(beIdenticalTo(rawData))
                }
            }
        
        describe("wipe()")
            {
            it("clears latestData")
                {
                stubReqest(resource, "GET")
                awaitNewData(resource().load())
                expect(resource().latestData).notTo(beNil())
                
                resource().wipe()
                
                expect(resource().latestData).to(beNil())
                }
            
            it("clears latestError")
                {
                stubReqest(resource, "GET").andReturn(500)
                awaitFailure(resource().load())
                expect(resource().latestError).notTo(beNil())
                
                resource().wipe()
                
                expect(resource().latestError).to(beNil())
                }
            
            it("cancels all requests in progress and prevents them from updating resource state")
                {
                let reqStubs =
                    [
                    stubReqest(resource, "GET").andReturn(200).delay(),
                    stubReqest(resource, "PUT").andReturn(200).delay(),
                    stubReqest(resource, "POST").andReturn(500).delay()
                    ]
                let reqs =
                    [
                    resource().load(),
                    resource().request(RequestMethod.PUT),
                    resource().request(RequestMethod.POST)
                    ]

                expect(resource().loading).to(beTrue())
                
                resource().wipe()
                
                for reqStub in reqStubs
                    { reqStub.go() }
                for req in reqs
                    { awaitFailure(req, alreadyCompleted: true) }
                
                expect(resource().loading).to(beFalse())
                expect(resource().latestData).to(beNil())
                expect(resource().latestError).to(beNil())
                }
            }
        }
    }


// MARK: - Helpers

private func dataAsString(data: AnyObject?) -> String?
    {
    guard let nsdata = data as? NSData else
        { return nil }
    
    return NSString(data: nsdata, encoding: NSUTF8StringEncoding) as? String
    }
