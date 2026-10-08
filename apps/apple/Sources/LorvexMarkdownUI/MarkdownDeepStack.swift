import Foundation

/// Runs markdown work on a thread whose stack holds the deepest nesting a note
/// can have.
///
/// swift-markdown's parser and the walks over its tree recurse once per level of
/// nesting, and a note can nest one level per character: a run of `>` is a block
/// quote inside a block quote inside a block quote, and `_a _a _a … a_ a_ a_`
/// is emphasis inside emphasis. A note may hold 50,000 characters, so a note
/// written by an assistant (or pasted in) can ask for tens of thousands of
/// levels, which overflows the 8 MB main-thread stack on macOS, the 1 MB one on
/// iOS, and the 512 KB stack of a worker thread alike. The crash happens as soon
/// as the task's detail opens, and again every time it does.
///
/// ``run(_:)`` gives the work a 256 MB stack instead. The stack is reserved
/// address space: only the pages the recursion actually reaches are ever
/// committed, so an ordinary note costs the same memory as before. The thread
/// hop costs about 25 microseconds.
enum MarkdownDeepStack {
    /// The stack size of the thread the work runs on, in bytes. It holds the
    /// deepest note the length limit allows (50,000 levels) with room to spare:
    /// a level uses between 1 and 2 KB of stack in a debug build.
    static let stackBytes = 256 * 1024 * 1024

    /// Runs `work` on a thread with ``stackBytes`` of stack and returns its
    /// result. The calling thread waits for it. When the system cannot create
    /// such a thread, `work` runs on the calling thread instead.
    static func run<Value: Sendable>(_ work: @escaping @Sendable () -> Value) -> Value {
        let outcome = Outcome<Value>()
        guard runOnLargeStack({ outcome.value = work() }), let value = outcome.value else {
            return work()
        }
        return value
    }

    /// Runs `body` to completion on a new thread with ``stackBytes`` of stack,
    /// joining it before returning. Returns false, without running `body`, when
    /// the thread cannot be configured or created.
    private static func runOnLargeStack(_ body: @escaping @Sendable () -> Void) -> Bool {
        var attributes = pthread_attr_t()
        guard pthread_attr_init(&attributes) == 0 else { return false }
        defer { pthread_attr_destroy(&attributes) }
        guard pthread_attr_setstacksize(&attributes, stackBytes) == 0 else { return false }

        let job = Unmanaged.passRetained(Job(body))
        var thread: pthread_t?
        let status = pthread_create(&thread, &attributes, { context in
            Unmanaged<Job>.fromOpaque(context).takeRetainedValue().body()
            return nil
        }, job.toOpaque())
        guard status == 0, let thread else {
            job.release()
            return false
        }
        pthread_join(thread, nil)
        return true
    }

    /// The closure a new thread runs, handed across the C thread entry point.
    private final class Job: Sendable {
        let body: @Sendable () -> Void

        init(_ body: @escaping @Sendable () -> Void) {
            self.body = body
        }
    }

    /// The slot the thread writes its result to. Joining the thread orders that
    /// write before the read in ``run(_:)``.
    private final class Outcome<Value: Sendable>: @unchecked Sendable {
        var value: Value?
    }
}
