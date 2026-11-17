import Combine
@testable import T3IsleCore

@MainActor
func until<Object: ObservableObject>(_ object: Object, _ condition: () -> Bool) async
where Object.ObjectWillChangePublisher == ObservableObjectPublisher {
    let (changes, continuation) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
    let observer = object.objectWillChange.sink { continuation.yield() }
    defer { observer.cancel() }
    var iterator = changes.makeAsyncIterator()
    while !condition() {
        await iterator.next()
    }
}

extension ReplaySource {
    func progress() -> AsyncStream<ReplayProgress> {
        let (stream, continuation) = AsyncStream<ReplayProgress>.makeStream()
        onProgress { continuation.yield($0) }
        return stream
    }
}
