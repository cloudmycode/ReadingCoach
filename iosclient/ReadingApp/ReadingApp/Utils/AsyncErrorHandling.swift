import Foundation

func isCancellationError(_ error: Error) -> Bool {
    if error is CancellationError {
        return true
    }
    if let urlError = error as? URLError, urlError.code == .cancelled {
        return true
    }
    let nsError = error as NSError
    return nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled
}
