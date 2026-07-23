# Watch mutation durability audit — 2026-07-15

Status: code-level findings closed on 2026-07-16. Paired-device and
distribution-signed evidence remains an external release gate; this document is
not that evidence.

Baseline: `main` at `110220b540e894dda9cedd0d11fcccf64243d921`.

## Resolution — 2026-07-16

The defects below describe the historical baseline named above. The replacement
now implements the recommended architecture rather than extending the old
UserDefaults replay cache:

- `LorvexWatchCommandJournal` atomically persists a stable install UUID,
  monotonic sequence, exact mutation, retry state, and terminal rejection before
  any optimistic UI update or transfer. It never capacity- or time-evicts an
  unacknowledged command and fails closed on corrupt state.
- `LorvexWatchCommand` and `LorvexWatchCommandAck` are strict, versioned,
  exact-key JSON envelopes. Canonical IDs/dates/timestamps and a checksum over
  every command field bind an ACK to one physical workspace, installation,
  sequence, command ID, and payload.
- Reachable delivery uses request/reply; background delivery uses
  `transferUserInfo`. Inactive sessions call neither API. Transport completion
  only advances retry timing; only a validated application ACK removes a
  pending command. Rejected commands remain visible until dismissal.
- `WatchCommandLedger` stores an indefinite per-install/per-workspace sequence
  high-water and terminal receipts in `local_watch_command_streams` and
  `local_watch_command_receipts`. Core preflights before minting an HLC, and an
  applied receipt commits in the same `BEGIN IMMEDIATE` transaction as the
  domain mutation. Gaps retry, exact replays return the same outcome, and
  sequence/ID/checksum collisions fail closed.
- The phone publishes a bounded Watch-only replica through replaceable
  application context. It validates and preserves mutation-capable identities
  and semantic date/status fields, measures the complete binary-plist context
  against the transfer ceiling, and binds the replica to the same Core instance
  that produced it. The Watch atomically stores the complete workspace-fenced
  envelope in `watch_replica_v1.json`.
- Old `WatchMutationReplay`, `WatchMutationApplyCoordinator`, MobileStore
  readiness/gate wrappers, and their tests were deleted. The new local command
  tables are absent from the explicit sync, export, and import contracts; only
  the resulting task/habit/focus mutations enter the ordinary sync pipeline.

Host coverage pins restart replay, concurrent duplicate application, gap and
collision handling, deterministic rejection, corrupt receipts/journals,
workspace replacement, strict wire decoding, direct/background/inactive
delivery, ACK identity/order, outstanding-transfer deduplication, replica
freshness, semantic-field preservation, and the complete application-context
size budget. See the finalization worklog for the final full-gate counts.

## Executive conclusion

The current Watch path has in-process duplicate suppression, but it does not
provide crash-safe, application-acknowledged delivery. A Watch mutation can be
removed from the UI after merely entering WatchConnectivity's transport queue,
then be lost permanently after a transient phone-side failure. Conversely, a
phone crash after the domain write commits but before the separate UserDefaults
receipt is stored can apply the same stable mutation id twice.

The final architecture should use:

- a Watch-local atomic-file command outbox retained until an application ACK;
- an explicitly versioned command/ACK wire envelope with stable id and payload
  checksum;
- a phone-side SQLite receipt written atomically with the canonical domain
  mutation;
- typed `applied`, `retryable`, and terminal `rejected` outcomes; and
- transport delivery callbacks only as retry signals, never as proof of a
  Lorvex database commit.

This control plane remains device-local. The resulting task/habit/focus writes
still use the ordinary changelog and CloudKit funnels; Watch commands and
receipts must not become CloudKit entities.

## Historical confirmed defects at the audited baseline

### 1. HIGH — transport queueing is treated as application success

`Sources/LorvexWatch/LorvexWatchConnectivity.swift:67-69` calls
`transferUserInfo` and returns without a phone application result. The task and
habit actions then optimistically update the Watch surface in
`Sources/LorvexWatch/LorvexWatchStoreTaskActions.swift:154-173`. Capture clears
the draft before forwarding completes at the same file's `:107-123`, while
`Sources/LorvexWatch/LorvexWatchCaptureSection.swift:20-29` presents success
feedback.

WatchConnectivity queues background dictionaries for transport; that is not a
Lorvex commit acknowledgement. The Watch currently has no durable outbox, so
the cleared draft or removed row may have been the only durable representation
of the user's intent.

Apple reference: [WCSession](https://developer.apple.com/documentation/watchconnectivity/wcsession)
and [transferUserInfo(_:)](https://developer.apple.com/documentation/watchconnectivity/wcsession/transferuserinfo%28_%3A%29).

### 2. HIGH — background delivery has no application ACK

The phone's `didReceiveUserInfo` path invokes the apply coordinator and discards
its result in
`Sources/LorvexMobile/PhoneWatchConnectivityReceiver.swift:255-289`. The
current result model is only `.ok` or `.error(String)` in
`Sources/LorvexCore/Models/WatchMutationReplay.swift:7-16`; it cannot distinguish
retryable infrastructure failure from terminal validation rejection.

`Sources/LorvexCore/Models/WatchMutationApplyCoordinator.swift:48-66` caches
every returned result. A transient database or storage error can therefore
become the stable result for that mutation id, even though the Watch receives
no result and does not retry.

### 3. HIGH — domain commit and dedup receipt are not atomic

`WatchMutationApplyCoordinator.swift:48-66` awaits the complete business apply
before recording a receipt. The domain write commits inside
`PhoneWatchConnectivityReceiver.swift:125-219`; snapshot projection and
publication also occur before the coordinator returns. Only afterward does
`WatchMutationReplay.swift:123-160` persist the receipt in UserDefaults.

A process death after the domain commit and before the receipt write permits a
same-id replay to execute again. Capture, habit completion, and defer-count
mutations are not all naturally idempotent, so this is a real double-apply
window.

### 4. HIGH — an inactive WCSession still initiates a transfer

`LorvexWatchConnectivity.swift:63-69` routes a non-activated session to
`transferUserInfo`. Apple states that transfers may be initiated only while
`activationState == .activated`; sending while `.notActivated` or `.inactive`
is a programmer error.

The existing source assertion in
`Tests/LorvexAppleTests/WatchConnectivityForwarderTests.swift:7-18` is a false
positive: it finds an unrelated `throw WatchForwardingError.unavailable` in the
unsupported-session branch and does not prove the inactive branch refuses to
transfer.

Apple references:
[activationState](https://developer.apple.com/documentation/watchconnectivity/wcsession/activationstate)
and [WCSessionActivationState](https://developer.apple.com/documentation/watchconnectivity/wcsessionactivationstate).

### 5. MED — final background-transfer failure is unobserved

The Watch forwarder does not implement
`session(_:didFinish:error:)` for `WCSessionUserInfoTransfer`. Delivery failure,
timeout, insufficient space, or malformed transport data therefore cannot
restore the pending intent or schedule a retry.

Apple explicitly describes this callback as the place to observe successful or
failed completion and, on error, retry later:
[session(_:didFinish:error:)](https://developer.apple.com/documentation/watchconnectivity/wcsessiondelegate/session%28_%3Adidfinish%3Aerror%3A%29-8627b).

### 6. MED — the command wire has no explicit compatibility envelope

`Sources/LorvexCore/Models/LorvexWatchMutation.swift:49-104` relies on synthesized
`Codable` for the mutation enum. There is no protocol version, canonical
payload checksum, or independently decodable header. A phone that cannot decode
a newer case only logs the failure in
`PhoneWatchConnectivityReceiver.swift:61-77`; the background path cannot tell
the Watch that the command was rejected.

### 7. MED — the Watch scene lacks the WatchConnectivity background handler

`Sources/LorvexWatchApp/LorvexWatchApp.swift:45-66` declares the scene without a
`.backgroundTask(.watchConnectivity)` handler. The eventual phone-to-Watch ACK
drain must be able to run under the system's WatchConnectivity background task
rather than relying on a foreground launch.

Apple reference:
[BackgroundTask.watchConnectivity](https://developer.apple.com/documentation/swiftui/backgroundtask/watchconnectivity).

### 8. MED — phone results are inferred from shared UI error state

Several phone mutations ignore their operation-local Boolean result and later
read the mutable `MobileStore.errorMessage` in
`PhoneWatchConnectivityReceiver.swift:145-219`. That state can be changed by a
different suspended operation, so it is not a reliable basis for a command ACK.
The ACK must come from the core transaction's typed result.

### 9. LOW/MED — the 128-entry, 24-hour receipt cache is not a durability invariant

`WatchMutationReplay.swift:55-72` bounds the cache to 128 entries and one day.
A delayed or high-volume replay can fall outside that window and execute again.
The cache also has no `(id, checksum)` collision rule, so reusing an id for
different content does not fail closed.

## Recommended command state machine

The Watch should persist this envelope before attempting any transfer:

```text
protocol_version
command_id
install_sequence
created_at
typed_mutation
canonical_payload_checksum
attempt_count / next_attempt_at
```

The durable states are:

```text
pending
  -> transport_queued
  -> awaiting_application_ack
  -> applied                 (remove from outbox)
  -> retryable               (retain with backoff)
  -> terminal_rejected       (retain until user observes or dismisses)
```

Persist-before-send is mandatory. A successful transport callback changes only
the transport state; it never removes the command. The Watch drains on launch,
session activation, reachability changes, explicit retry, and the
WatchConnectivity background task. `outstandingUserInfoTransfers` prevents
blindly queueing a duplicate command after process restart.

The UI should distinguish Pending from Applied. A capture draft may disappear
from the editor once its durable outbox record exists, but a terminal rejection
must preserve enough content for recovery or copying.

## Recommended phone transaction

Move correctness below `MobileStore` into a core-level command applier:

1. Begin the same SQLite write transaction as the domain mutation.
2. Look up `(command_id, checksum)`.
3. Replay the stored applied result for the same id and checksum.
4. Reject the same id with a different checksum.
5. Otherwise execute the canonical core mutation.
6. Write the applied receipt inside the same transaction.
7. Commit, then return a typed application ACK.
8. Treat UI reload, snapshot publication, and haptics as post-commit best-effort
   effects; their failure cannot turn an applied mutation into an error ACK.

Transient infrastructure errors write no terminal receipt. Deterministic
validation or unsupported-protocol rejections may be durably replayable. The
existing actor/in-flight map can remain as a performance optimization, but the
SQLite receipt is the crash-safety authority.

Before schema freeze, prefer a generic local idempotency-receipt table with a
namespace/operation/id/checksum/result contract over extending the currently
MCP-named table as an implicit second use. This table is local control state and
must be excluded from sync/export/import.

## Error classification

Retain and retry automatically:

- session inactive/not activated or counterpart temporarily unreachable;
- delivery failure, transfer timeout, message reply failure/timeout;
- temporary database, storage, or cutover failure;
- insufficient space, with a visible blocked state.

Retain while waiting for environment repair:

- no paired device;
- companion app not installed.

Terminal rejection:

- unsupported protocol version or undecodable command;
- invalid or unsupported payload/property-list type;
- payload too large;
- same command id with a different checksum;
- deterministic domain validation failure;
- a definitively removed target for a command whose semantics cannot recreate it.

Apple's current error inventory is documented at
[WCError.Code](https://developer.apple.com/documentation/watchconnectivity/wcerror/code).

## Required host test matrix

Watch outbox tests:

- persist-before-send and restart recovery before the first transfer;
- inactive sessions never call a WCSession transfer API;
- transport completion without application ACK does not remove the command;
- transfer failure, retryable ACK, terminal ACK, duplicate ACK, and out-of-order
  ACK behavior;
- same-id checksum mismatch;
- no duplicate queue when `outstandingUserInfoTransfers` already contains the id;
- old/new protocol versions and malformed payloads yield deterministic ACKs.

Phone/core tests:

- crash after capture commit but before ACK/receipt observation, then replay;
- the same crash boundary for habit completion and defer count;
- transient first failure leaves no receipt and the next attempt succeeds;
- terminal rejection and applied success replay identically;
- concurrent same-id requests execute once;
- same id/different checksum fails closed;
- post-commit snapshot/reload failure does not change an applied ACK;
- commands from one Watch install apply in sequence order.

These tests must be pure Swift and host-runnable; static substring tests are not
evidence for transport-state correctness.

## Required paired-device release evidence

The final gate requires a paired Watch and iPhone. Exercise:

- phone unavailable, rebooted, and terminated;
- Watch app terminated after persistence and after transport queueing;
- long offline intervals and delayed ACKs;
- transfer errors and retry backoff;
- phone commit followed by fault injection before ACK delivery;
- ACK loss followed by same-id replay;
- background ACK receipt through `.backgroundTask(.watchConnectivity)`;
- inbound callback work and the durable journal drain both complete under the
  WatchConnectivity background-task handler. `hasContentPending` is not used as
  proof that an outgoing command or ACK was applied.

Record the exact signed build, devices, OS versions, command ids, and final
single-application database evidence. Simulator or source-only green tests are
not substitutes for this release evidence.
