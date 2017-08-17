//
//  BadCookieWritingMiddleware.swift
//  Kitura
//
//  Created by Carl Brown on 5/1/17.
//
//

import Foundation
import Dispatch
import LoggerAPI
import Kitura
import HTTP

class BadCookieWritingMiddleware {
    
    var UUIDString:String?
    let cookieName:String
    let urlForUUIDFetch: URL
    
    private class HTTPResponseWriterAddingCookie : HTTPResponseWriter {
        
        let oldResponseWriter: HTTPResponseWriter
        let cookieValue: String
        
        init(oldResponseWriter: HTTPResponseWriter, cookieValue: String) {
            self.oldResponseWriter = oldResponseWriter
            self.cookieValue = cookieValue
        }
        
        func writeHeader(status: HTTPResponseStatus, headers: HTTPHeaders, completion: @escaping (Result) -> Void) {
            var newHeaders = headers
            
            newHeaders.append(["Set-Cookie": self.cookieValue])
            
            oldResponseWriter.writeHeader(status: status, headers: newHeaders)

        }
        
        func writeTrailer(_ trailers: HTTPHeaders, completion: @escaping (Result) -> Void) {
            oldResponseWriter.writeTrailer(trailers, completion: completion)
        }

        func writeBody(_ data: UnsafeHTTPResponseBody, completion: @escaping (Result) -> Void) {
            oldResponseWriter.writeBody(data, completion: completion)
        }

        func done(completion: @escaping (Result) -> Void) {
            return oldResponseWriter.done(completion: completion)
        }

        func done() { return oldResponseWriter.done() }
        func abort()  { return oldResponseWriter.abort() }

    }
    
    init(cookieName: String, urlForUUIDFetch: URL) {
        self.cookieName = cookieName
        self.urlForUUIDFetch = urlForUUIDFetch
    }
    
    func preProcess (_ req: HTTPRequest, _ context: RequestContext, _ completionHandler: @escaping (_ req: HTTPRequest, _ context: RequestContext) -> ()) -> HTTPPreProcessingStatus {
        //Go grab a UUID from the web - not because we need to, but because we want to test Async().
        //FIXME: Get this to not fail when offline
        
        let session = URLSession(configuration: URLSessionConfiguration.default)
        let dataTask = session.dataTask(with: urlForUUIDFetch) { (responseBody, rawResponse, error) in
            guard let body = responseBody, let uuidString = String(data: body, encoding: .utf8) else {
                Log.error("failed to retrive UUID")
                completionHandler(req, context)
                return
            }
            let urlResponse = rawResponse as? HTTPURLResponse
            guard let response = urlResponse else {
                Log.error("failed to get status code")
                completionHandler(req, context)
                return
            }
            if response.statusCode != 200 {
                Log.error("Status code was not OK")
                completionHandler(req, context)
                return
            }
            let index = uuidString.index(uuidString.startIndex, offsetBy: 36
            )
            completionHandler(req, context.adding(dict: ["X-OurUUID": String(uuidString[..<index])]))
        }
        dataTask.resume()
        return .willCallCompletionBlock
    }
    
    func postProcess (_ req: HTTPRequest, _ context: RequestContext, _ res: HTTPResponseWriter) -> HTTPPostProcessingStatus {
        
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US")
        dateFormatter.timeZone = TimeZone(identifier: "GMT")!
        dateFormatter.dateFormat = "E, dd MMM yyyy HH:mm:ss z"
        let cookieDate = Date(timeIntervalSinceNow: 3600)
        
        if let uuidString = context["X-OurUUID"] {
            
            let cookieString = "\(self.cookieName)=\(uuidString); path=/; domain=localhost; expires=\(dateFormatter.string(from: cookieDate));"
            
            return HTTPPostProcessingStatus.replace(res: HTTPResponseWriterAddingCookie(oldResponseWriter: res, cookieValue: cookieString))
        }
        
        Log.verbose("Can't get X-OurUUID from context")
        return HTTPPostProcessingStatus.notApplicable
    }
    
}
