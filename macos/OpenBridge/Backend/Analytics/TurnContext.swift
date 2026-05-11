import Foundation

struct TraceContextCarrier: Sendable {
    let traceparent: String
    let tracestate: String?

    init(traceparent: String, tracestate: String?) {
        self.traceparent = traceparent
        self.tracestate = tracestate?.isEmpty == true ? nil : tracestate
    }
}
