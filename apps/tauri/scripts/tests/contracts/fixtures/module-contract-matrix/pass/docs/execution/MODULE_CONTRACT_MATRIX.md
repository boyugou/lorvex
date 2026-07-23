| module id | settings toggle | sidebar guard | render branch | fallback behavior |
|---|---|---|---|---|
| `today` | x | x | x | x |
| `upcoming` | x | x | x | x |
| `all_tasks` | x | x | x | x |
| `someday` | x | x | x | x |
| `calendar` | x | x | x | x |
| `eisenhower` | x | x | x | x |
| `daily_review` | x | x | x | x |
| `memory` | x | x | x | x |
| `review` | x | x | x | x |
| `changelog` | x | x | x | x |
| `focus` | x | x | x | x |

npm run verify:module-contract-matrix
npm run verify:ui-wiring
cd app && npx tsc --noEmit
