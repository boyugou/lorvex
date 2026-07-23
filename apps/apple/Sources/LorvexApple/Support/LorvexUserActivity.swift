import Foundation
import LorvexCore

// Re-export the shared catalog from LorvexCore so callers in LorvexApple need
// only import LorvexCore (which they already do) — no source-breaking change.
//
// All builder and parser functions are defined in LorvexCore/Models/:
//   makeOpenTaskActivity, makeOpenDestinationActivity, makeOpenListActivity,
//   parseOpenTaskActivity, parseOpenDestinationActivity, parseOpenListActivity.
