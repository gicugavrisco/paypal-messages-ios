import Foundation

enum HTTPMethod: String {
    case get = "GET"
    case post = "POST"
}

enum FetchError: Error {
    case invalidURL
}

func fetch(
    _ url: URL,
    method: HTTPMethod = .get,
    headers: HTTPHeaders? = nil,
    body: Data? = nil,
    session: URLSession = URLSession.shared,
    timeoutInterval: TimeInterval? = nil,
    fetchQueue: DispatchQueue = DispatchQueue.global(qos: .default),
    completionQueue: DispatchQueue = DispatchQueue.main,
    completion: @escaping (Data?, URLResponse?, Error?) -> Void
) {
    fetchQueue.async {
        var request = URLRequest(url: url)

        if let timeoutInterval {
            request.timeoutInterval = timeoutInterval
        }

        request.httpMethod = method.rawValue

        if let headers {
            headers.forEach { request.addValue($1, forHTTPHeaderField: $0.rawValue) }
        }

        if let body {
            request.httpBody = body
        }

        let task = session.dataTask(with: request) { data, response, error in
            guard let data, error == nil else {
                completionQueue.async { completion(nil, response, error) }
                return
            }

            completionQueue.async { completion(data, response, nil) }
        }

        task.resume()
    }
}
