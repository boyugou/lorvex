import Dispatch

/// A task executor that runs its jobs on one serial GCD queue, outside Swift's
/// cooperative thread pool.
///
/// A test that pauses synchronous code (a projector callback, a write barrier)
/// blocks the thread running it until the test body releases it, and the body
/// needs a cooperative-pool thread to get there. The pool has one thread per
/// core, three on a hosted runner, and does not add one when a thread blocks,
/// so a few such pauses at once can leave the body none and stop the whole
/// run. A task started with
/// `Task(executorPreference: SerialQueueTaskExecutor())` runs its nonisolated
/// code, and the code of default actors it calls, here instead: a pause then
/// blocks this queue's thread, and GCD adds threads for blocked ones. Code
/// isolated to the main actor, or to an actor with its own executor, still
/// runs there.
///
/// One instance is one thread. The child tasks of such a task (`async let`, a
/// task group) inherit the preference and share that thread, so a pause must
/// not wait for one of them; and two tasks that must run at the same moment,
/// such as two parties to a rendezvous, each need an instance of their own.
final class SerialQueueTaskExecutor: TaskExecutor {
  private let queue = DispatchQueue(label: "lorvex.tests.serial-task-executor")

  func enqueue(_ job: consuming ExecutorJob) {
    let job = UnownedJob(job)
    let executor = asUnownedTaskExecutor()
    queue.async { job.runSynchronously(on: executor) }
  }
}
