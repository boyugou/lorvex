package com.lorvex.planner

import android.content.ContentResolver
import android.content.ContentUris
import android.database.Cursor
import android.provider.CalendarContract
import org.json.JSONArray
import org.json.JSONObject
import java.util.*

/**
 * Reads calendar events from the Android CalendarContract content provider.
 *
 * Called from Rust via JNI. The [readEvents] method returns a JSON string (array)
 * representing calendar events within the next [daysAhead] days.
 *
 * Prerequisites:
 * - `READ_CALENDAR` permission must be granted at runtime before calling.
 * - The host Activity's ContentResolver is passed in the constructor.
 *
 * The returned JSON schema matches what the Rust side deserializes as
 * `RawAndroidEvent`:
 * ```json
 * [
 *   {
 *     "id": "12345",
 *     "title": "Meeting",
 *     "description": "Weekly sync",
 *     "dtstart": 1711900800000,
 *     "dtend": 1711904400000,
 *     "all_day": false,
 *     "location": "Room 42",
 *     "calendar_name": "Work"
 *   }
 * ]
 * ```
 */
class CalendarReader(private val contentResolver: ContentResolver) {

    companion object {
        private val EVENT_PROJECTION = arrayOf(
            CalendarContract.Instances.EVENT_ID,           // 0
            CalendarContract.Instances.TITLE,              // 1
            CalendarContract.Instances.DESCRIPTION,        // 2
            CalendarContract.Instances.BEGIN,              // 3 (instance start millis)
            CalendarContract.Instances.END,                // 4 (instance end millis)
            CalendarContract.Instances.ALL_DAY,            // 5
            CalendarContract.Instances.EVENT_LOCATION,     // 6
            CalendarContract.Instances.CALENDAR_DISPLAY_NAME, // 7
        )

        private const val COL_EVENT_ID = 0
        private const val COL_TITLE = 1
        private const val COL_DESCRIPTION = 2
        private const val COL_BEGIN = 3
        private const val COL_END = 4
        private const val COL_ALL_DAY = 5
        private const val COL_LOCATION = 6
        private const val COL_CALENDAR_NAME = 7
    }

    /**
     * Query CalendarContract.Instances for events from the start of today
     * through [daysAhead] days into the future.
     *
     * Uses the Instances table (not Events) so that recurring event occurrences
     * are correctly expanded into individual instances.
     *
     * @param daysAhead Number of days into the future to scan (default 90).
     * @return JSON string (a JSONArray of event objects), or `null` if
     *         READ_CALENDAR permission is denied/revoked.
     */
    fun readEvents(daysAhead: Int = 90): String? {
        val events = JSONArray()
        // Start from the beginning of today (midnight local time) so that
        // events earlier today are included, not just events after "now".
        val calendar = Calendar.getInstance().apply {
            set(Calendar.HOUR_OF_DAY, 0)
            set(Calendar.MINUTE, 0)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
        }
        val startOfToday = calendar.timeInMillis
        val end = startOfToday + daysAhead.toLong() * 24L * 60L * 60L * 1000L

        // Use Instances URI to get expanded recurring events.
        val builder = CalendarContract.Instances.CONTENT_URI.buildUpon()
        ContentUris.appendId(builder, startOfToday)
        ContentUris.appendId(builder, end)

        val cursor: Cursor? = try {
            contentResolver.query(
                builder.build(),
                EVENT_PROJECTION,
                null,   // selection: all events in the time range
                null,   // selectionArgs
                "${CalendarContract.Instances.BEGIN} ASC" // sort by start time
            )
        } catch (e: SecurityException) {
            // READ_CALENDAR permission not granted or was revoked at runtime.
            // Return null (not "[]") so the Rust side can distinguish
            // "permission denied" from "zero events" and skip stale pruning.
            return null
        }

        cursor?.use {
            while (it.moveToNext()) {
                val event = JSONObject().apply {
                    // Use EVENT_ID for deduplication. For recurring instances, combine
                    // EVENT_ID with the instance BEGIN millis to produce a unique key.
                    val eventId = it.getLong(COL_EVENT_ID)
                    val beginMs = it.getLong(COL_BEGIN)
                    put("id", "${eventId}_$beginMs")
                    put("title", it.getString(COL_TITLE) ?: "")
                    put("description", it.getString(COL_DESCRIPTION) ?: "")
                    put("dtstart", beginMs)
                    put("dtend", it.getLong(COL_END))
                    put("all_day", it.getInt(COL_ALL_DAY) == 1)
                    put("location", it.getString(COL_LOCATION) ?: "")
                    put("calendar_name", it.getString(COL_CALENDAR_NAME) ?: "")
                }
                events.put(event)
            }
        }

        return events.toString()
    }
}
