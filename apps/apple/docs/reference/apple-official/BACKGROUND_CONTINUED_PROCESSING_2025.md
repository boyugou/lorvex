# Continuous Background Processing, 2025

Primary sources:

- [Performing long-running tasks on iOS and iPadOS](https://developer.apple.com/documentation/backgroundtasks/performing-long-running-tasks-on-ios-and-ipados)
- [BGContinuedProcessingTask](https://developer.apple.com/documentation/backgroundtasks/bgcontinuedprocessingtask)
- [Background Tasks updates](https://developer.apple.com/documentation/updates/backgroundtasks)

Last verified: 2026-07-10

## Apple Contract

`BGContinuedProcessingTask` is an iOS/iPadOS 26 task that begins while the app
is in the foreground in direct response to a person's action, then may continue
when the app moves to the background. The system displays progress, lets the
person cancel, and can terminate the task under resource pressure. The app must
report progress and handle expiration/cancellation.

It is different from a scheduled refresh, processing task, or silent push. It
cannot be used to turn an unsolicited CloudKit notification into unrestricted
background execution.

## Lorvex Mapping

Potential uses are large user-started export/import work, a lengthy local data
repair, or an explicitly started on-device model operation. Each must already
be resumable or transactional because the system can still terminate it.

This API does not solve the current silent-push deadline finding: Lorvex's
CloudKit remote-notification path is system-initiated, not a foreground action,
and still needs to finish or durably hand off work within the background-push
budget.

Adopt only behind OS-26 availability with the existing path as fallback. No
schema change is necessary for ordinary use; if a workflow needs resumption,
prefer the existing durable job/checkpoint concepts over an OS-specific opaque
state blob.
