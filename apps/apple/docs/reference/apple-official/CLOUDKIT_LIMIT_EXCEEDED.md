# CKError.Code.limitExceeded

Source: [CKError limitExceeded](https://developer.apple.com/documentation/cloudkit/ckerror/code/limitexceeded)

Last verified: 2026-07-10

## Apple Contract

Apple documents general limits of 400 records/shares per operation and 2 MB per
request excluding assets, while reserving the right to change server limits. On
`limitExceeded`, split the operation and retry the smaller requests.

## Lorvex Mapping

- The coordinator caps a push chunk at 400 records.
- It also uses a conservative 768-KiB estimated byte budget.
- The pusher recursively halves a request on `limitExceeded`.
- A single unsplittable record becomes a per-record failure instead of blocking
  unrelated records.

## Audit Conclusion

This path matches Apple's guidance. Keep the recursive server-error fallback
even if the proactive estimate becomes more accurate; Apple's limits are not a
fixed client-side constant.
