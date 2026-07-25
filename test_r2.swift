import Foundation
import CryptoKit

enum AWSV4Signer {
    static func sign(
        method: String,
        endpoint: String,
        bucket: String,
        key: String,
        body: Data,
        contentType: String,
        accessKeyID: String,
        secretKey: String,
        region: String,
        service: String
    ) -> URLRequest? {
        let cleanEndpoint = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        let urlString = "\(cleanEndpoint)/\(bucket)/\(key)"
        guard let url = URL(string: urlString) else { return nil }
        
        let now = Date()
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withYear, .withMonth, .withDay, .withTime, .withTimeZone, .withColonSeparatorInTime]
        let amzDate = dateFormatter.string(from: now).replacingOccurrences(of: "-", with: "").replacingOccurrences(of: ":", with: "")
        let dateStamp = String(amzDate.prefix(8))
        
        let bodyHash = SHA256.hash(data: body).compactMap { String(format: "%02x", $0) }.joined()
        guard let host = URL(string: cleanEndpoint)?.host else { return nil }
        
        let canonicalHeaders = "content-type:\(contentType)\nhost:\(host)\nx-amz-content-sha256:\(bodyHash)\nx-amz-date:\(amzDate)\n"
        let signedHeaders = "content-type;host;x-amz-content-sha256;x-amz-date"
        
        let encodedKey = key.split(separator: "/", omittingEmptySubsequences: false)
            .map { $0.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? String($0) }
            .joined(separator: "/")
        let canonicalURI = "/\(bucket)/\(encodedKey)"
        
        let canonicalRequest = method + "\n" + canonicalURI + "\n" + "" + "\n" + canonicalHeaders + "\n" + signedHeaders + "\n" + bodyHash
        let credentialScope = "\(dateStamp)/\(region)/\(service)/aws4_request"
        let canonicalHash = SHA256.hash(data: Data(canonicalRequest.utf8)).compactMap { String(format: "%02x", $0) }.joined()
        
        let stringToSign = "AWS4-HMAC-SHA256\n" + amzDate + "\n" + credentialScope + "\n" + canonicalHash
        
        func hmac256(_ key: Data, _ data: String) -> Data {
            let symKey = SymmetricKey(data: key)
            let mac = HMAC<SHA256>.authenticationCode(for: Data(data.utf8), using: symKey)
            return Data(mac)
        }
        let signingKey = hmac256(hmac256(hmac256(hmac256(Data(("AWS4" + secretKey).utf8), dateStamp), region), service), "aws4_request")
        
        let symKey = SymmetricKey(data: signingKey)
        let signatureMac = HMAC<SHA256>.authenticationCode(for: Data(stringToSign.utf8), using: symKey)
        let signature = Data(signatureMac).compactMap { String(format: "%02x", $0) }.joined()
        
        let authHeader = "AWS4-HMAC-SHA256 Credential=\(accessKeyID)/\(credentialScope), SignedHeaders=\(signedHeaders), Signature=\(signature)"
        
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.setValue(host, forHTTPHeaderField: "Host")
        request.setValue(amzDate, forHTTPHeaderField: "x-amz-date")
        request.setValue(bodyHash, forHTTPHeaderField: "x-amz-content-sha256")
        request.setValue(authHeader, forHTTPHeaderField: "Authorization")
        return request
    }
}

let request = AWSV4Signer.sign(
    method: "PUT",
    endpoint: "https://66c40e0caaaa333ca0f4977bf32be2a7.r2.cloudflarestorage.com",
    bucket: "haispaceproject",
    key: "haispace-logs/ipad-latest.txt",
    body: "test log".data(using: .utf8)!,
    contentType: "text/plain; charset=utf-8",
    accessKeyID: "b4612a74659f3f9ce39bd5ec1ffbefbf",
    secretKey: "388aab4ee2e7cabb97c3ac0a30a34dac2f7480628ce6afbbec6e2c730ffcbc49",
    region: "auto",
    service: "s3"
)!

let sema = DispatchSemaphore(value: 0)
URLSession.shared.dataTask(with: request) { data, response, error in
    if let error = error {
        print("Error: \(error)")
    }
    if let http = response as? HTTPURLResponse {
        print("Status: \(http.statusCode)")
        if let data = data, let str = String(data: data, encoding: .utf8) {
            print("Body: \(str)")
        }
    }
    sema.signal()
}.resume()
sema.wait()
