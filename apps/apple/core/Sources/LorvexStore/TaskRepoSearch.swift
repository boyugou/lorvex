import Foundation
import GRDB
import LorvexDomain

extension TaskRepo {
  /// Search-task read paths: FTS5 (`unicode61` BM25), trigram-FTS5 (CJK),
  /// and LIKE fallback, with automatic strategy selection.
  public enum Search {

    /// Result of a search query: matched rows and total matching count.
    public struct Result: Sendable, Equatable {
      public let rows: [TaskRow]
      public let totalMatching: Int64

      public init(rows: [TaskRow], totalMatching: Int64) {
        self.rows = rows
        self.totalMatching = totalMatching
      }
    }

    /// Cap on the inner LIKE-fallback count scan. The scan stops after at most
    /// `likeFallbackCountCap + 1` matching rows: an exact count (`<= cap`) is
    /// returned verbatim, while a saturated scan reports `cap + 1` as a
    /// "more may exist" sentinel so downstream pagination keeps `truncated`
    /// true and `nextOffset` non-nil past the cap instead of a slow full-table
    /// COUNT(*).
    static let likeFallbackCountCap: Int64 = 10_000

    /// FTS5 result ordering: status bucket → bm25 relevance → canonical stable
    /// sort. The tiebreaker is the canonical `priority_effective ASC, due_date
    /// ASC NULLS LAST, id ASC` (all stable columns), NOT `updated_at` — the HLC
    /// rewrites `updated_at` on conflict resolution, so using it as a pagination
    /// tiebreaker can skip or duplicate rows across page boundaries after a
    /// sync. Shared by the counted production path and the test-only
    /// `searchTasks` so the bm25 weights and ordering cannot drift apart. The
    /// trigram path applies the same canonical tiebreaker after its relevance
    /// score.
    static let ftsOrderByClause =
      "ORDER BY CASE WHEN t.status IN (\(StatusName.actionableStatusSqlList)) THEN 0 "
      + "WHEN t.status = '\(StatusName.someday)' THEN 1 ELSE 2 END, "
      + "bm25(tasks_fts, 10.0, 1.0, 0.5, 3.0), \(TaskRepo.taskOrderByQualified("t"))"

    // -------------------------------------------------------------------
    // Dispatcher
    // -------------------------------------------------------------------

    /// Full-text search with automatic LIKE fallback.
    ///
    /// - CJK queries of 3+ chars go through `tasks_fts_trigram`; shorter CJK
    ///   queries (and any trigram schema-missing error) fall to LIKE.
    /// - Pure emoji/punctuation queries (zero alphanumerics) go straight to
    ///   LIKE.
    /// - Latin-script queries go through `tasks_fts` (BM25). On zero FTS hits
    ///   with a short trailing token, retry that token via LIKE. FTS
    ///   schema-missing errors fall to LIKE.
    /// - Empty/whitespace queries return an empty result.
    public static func searchTasksWithFallback(
      _ db: Database, predicate pred: SearchPredicate, page: Pagination
    ) throws -> Result {
      if pred.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        return Result(rows: [], totalMatching: 0)
      }

      if Fts.containsCjk(pred.query) {
        if pred.query.count >= 3 {
          do {
            return try searchTasksTrigramCounted(
              db, rawQuery: pred.query, pred: pred, page: page)
          } catch {
            if !isFtsSchemaMissing(error) { throw error }
            return try searchTasksLike(db, rawQuery: pred.query, pred: pred, page: page)
          }
        }
        return try searchTasksLike(db, rawQuery: pred.query, pred: pred, page: page)
      }

      if Fts.shouldUseLikeFallback(pred.query) {
        return try searchTasksLike(db, rawQuery: pred.query, pred: pred, page: page)
      }

      let sanitized = Fts.sanitizeFtsQuery(pred.query)
      if !sanitized.isEmpty {
        do {
          let result = try searchTasksFtsCounted(
            db, sanitized: sanitized, pred: pred, page: page)
          if result.totalMatching == 0 {
            if let tok = Fts.shortTrailingTokenForLikeRetry(pred.query) {
              return try searchTasksLike(db, rawQuery: tok, pred: pred, page: page)
            }
          }
          return result
        } catch {
          if !isFtsSchemaMissing(error) { throw error }
        }
      }

      return try searchTasksLike(db, rawQuery: pred.query, pred: pred, page: page)
    }

    /// FTS-only search returning rows in rank order. The bare entrypoint
    /// exists for FTS-only behaviour tests; production goes through
    /// ``searchTasksWithFallback(_:predicate:page:)``. Returns `[]` when the
    /// sanitized query is empty.
    static func searchTasks(
      _ db: Database, predicate pred: SearchPredicate, page: Pagination
    ) throws -> [TaskRow] {
      let sanitized = Fts.sanitizeFtsQuery(pred.query)
      if sanitized.isEmpty { return [] }

      var args: [any DatabaseValueConvertible] = [sanitized]
      let scaffold = buildFtsFilterScaffolding(pred: pred, args: &args)

      let limitIdx = args.count + 1
      let offsetIdx = args.count + 2
      args.append(Int64(page.limit))
      args.append(Int64(page.offset))

      let sql = """
        SELECT \(TaskRepo.taskColumnsQualified("t")) FROM tasks t \
        JOIN tasks_fts ON t.rowid = tasks_fts.rowid \
        \(scaffold.tagJoin) \
        WHERE tasks_fts MATCH ?1\(scaffold.whereExtra) \
        \(Self.ftsOrderByClause) \
        LIMIT ?\(limitIdx) OFFSET ?\(offsetIdx)
        """
      let rows = try Row.fetchAll(db, sql: sql, arguments: StatementArguments(args))
      return try rows.map(TaskRepo.rowToTaskRow)
    }

    // -------------------------------------------------------------------
    // FTS5 (unicode61) path
    // -------------------------------------------------------------------

    static func searchTasksFtsCounted(
      _ db: Database, sanitized: String, pred: SearchPredicate, page: Pagination
    ) throws -> Result {
      var args: [any DatabaseValueConvertible] = [sanitized]
      let scaffold = buildFtsFilterScaffolding(pred: pred, args: &args)

      let countSql = """
        SELECT COUNT(*) FROM tasks t \
        JOIN tasks_fts ON t.rowid = tasks_fts.rowid \
        \(scaffold.tagJoin) \
        WHERE tasks_fts MATCH ?1\(scaffold.whereExtra)
        """
      let totalMatching =
        try Int64.fetchOne(db, sql: countSql, arguments: StatementArguments(args)) ?? 0

      let limitIdx = args.count + 1
      let offsetIdx = args.count + 2
      args.append(Int64(page.limit))
      args.append(Int64(page.offset))

      let sql = """
        SELECT \(TaskRepo.taskColumnsQualified("t")) FROM tasks t \
        JOIN tasks_fts ON t.rowid = tasks_fts.rowid \
        \(scaffold.tagJoin) \
        WHERE tasks_fts MATCH ?1\(scaffold.whereExtra) \
        \(Self.ftsOrderByClause) \
        LIMIT ?\(limitIdx) OFFSET ?\(offsetIdx)
        """
      let rows = try Row.fetchAll(db, sql: sql, arguments: StatementArguments(args))
      return Result(rows: try rows.map(TaskRepo.rowToTaskRow), totalMatching: totalMatching)
    }

    // -------------------------------------------------------------------
    // Trigram (CJK) path
    // -------------------------------------------------------------------

    static func searchTasksTrigramCounted(
      _ db: Database, rawQuery: String, pred: SearchPredicate, page: Pagination
    ) throws -> Result {
      let capped = Fts.capFtsQueryLength(rawQuery)
      // FTS5 phrase-quote the query so user punctuation/whitespace can't be
      // parsed as FTS operators; inner double quotes are doubled.
      let ftsQuery = "\"\(capped.replacingOccurrences(of: "\"", with: "\"\""))\""
      let tagLike = Parsing.escapeLike(capped)

      var conditions = [
        "t.archived_at IS NULL",
        "(t.rowid IN (SELECT rowid FROM tasks_fts_trigram WHERE tasks_fts_trigram MATCH ?1) "
          + "OR EXISTS (SELECT 1 FROM task_tags tt2 JOIN tags tg ON tg.id = tt2.tag_id "
          + "WHERE tt2.task_id = t.id AND tg.display_name LIKE '%' || ?2 || '%' ESCAPE '\\'))",
      ]
      var args: [any DatabaseValueConvertible] = [ftsQuery, tagLike]

      applyStatusFilter(pred, &conditions, &args)
      applyListFilter(pred, &conditions, &args)
      applyTagFilterExists(pred, &conditions, &args)

      let whereClause = conditions.joined(separator: " AND ")

      let countSql = "SELECT COUNT(*) FROM tasks t WHERE \(whereClause)"
      let totalMatching =
        try Int64.fetchOne(db, sql: countSql, arguments: StatementArguments(args)) ?? 0

      let limitIdx = args.count + 1
      let offsetIdx = args.count + 2
      args.append(Int64(page.limit))
      args.append(Int64(page.offset))

      let sql = """
        SELECT \(TaskRepo.taskColumnsQualified("t")), ( \
            (CASE WHEN LOWER(t.title) LIKE LOWER(?2) ESCAPE '\\' THEN 100 ELSE 0 END) \
            + (CASE WHEN LOWER(t.title) LIKE LOWER('%' || ?2 || '%') ESCAPE '\\' THEN 50 ELSE 0 END) \
            + (CASE WHEN LOWER(t.body) LIKE LOWER('%' || ?2 || '%') ESCAPE '\\' THEN 10 ELSE 0 END) \
            + (CASE WHEN LOWER(t.ai_notes) LIKE LOWER('%' || ?2 || '%') ESCAPE '\\' THEN 5 ELSE 0 END) \
        ) AS match_score \
        FROM tasks t \
        WHERE \(whereClause) \
        ORDER BY match_score DESC, \(TaskRepo.taskOrderByQualified("t")) \
        LIMIT ?\(limitIdx) OFFSET ?\(offsetIdx)
        """
      let rows = try Row.fetchAll(db, sql: sql, arguments: StatementArguments(args))
      return Result(rows: try rows.map(TaskRepo.rowToTaskRow), totalMatching: totalMatching)
    }

    // -------------------------------------------------------------------
    // LIKE fallback path
    // -------------------------------------------------------------------

    static func searchTasksLike(
      _ db: Database, rawQuery: String, pred: SearchPredicate, page: Pagination,
      countCap: Int64 = likeFallbackCountCap
    ) throws -> Result {
      let capped = Fts.capFtsQueryLength(rawQuery)
      let escaped = Parsing.escapeLike(capped)

      var conditions = [
        "t.archived_at IS NULL",
        "(t.title LIKE '%' || ?2 || '%' ESCAPE '\\' "
          + "OR t.body LIKE '%' || ?2 || '%' ESCAPE '\\' "
          + "OR t.ai_notes LIKE '%' || ?2 || '%' ESCAPE '\\' "
          + "OR EXISTS (SELECT 1 FROM task_tags tt2 JOIN tags tg ON tg.id = tt2.tag_id "
          + "WHERE tt2.task_id = t.id AND tg.display_name LIKE '%' || ?2 || '%' ESCAPE '\\'))",
      ]
      var args: [any DatabaseValueConvertible] = [escaped, escaped]

      applyStatusFilter(pred, &conditions, &args)
      applyListFilter(pred, &conditions, &args)
      applyTagFilterExists(pred, &conditions, &args)

      let whereClause = conditions.joined(separator: " AND ")

      // Scan one past the cap: a returned count of `countCap + 1` marks the
      // total as saturated ("more than countCap"), which pagination reads as
      // "more may exist" rather than nulling nextOffset at the cap boundary.
      let countSql =
        "SELECT COUNT(*) FROM (SELECT 1 FROM tasks t WHERE \(whereClause) "
        + "LIMIT \(countCap + 1))"
      let totalMatching =
        try Int64.fetchOne(db, sql: countSql, arguments: StatementArguments(args)) ?? 0

      let limitIdx = args.count + 1
      let offsetIdx = args.count + 2
      args.append(Int64(page.limit))
      args.append(Int64(page.offset))

      let sql = """
        SELECT \(TaskRepo.taskColumnsQualified("t")), ( \
            (CASE WHEN LOWER(t.title) LIKE LOWER(?1) ESCAPE '\\' THEN 100 ELSE 0 END) \
            + (CASE WHEN LOWER(t.title) LIKE LOWER('%' || ?2 || '%') ESCAPE '\\' THEN 50 ELSE 0 END) \
            + (CASE WHEN LOWER(t.body) LIKE LOWER('%' || ?2 || '%') ESCAPE '\\' THEN 10 ELSE 0 END) \
            + (CASE WHEN LOWER(t.ai_notes) LIKE LOWER('%' || ?2 || '%') ESCAPE '\\' THEN 5 ELSE 0 END) \
        ) AS match_score \
        FROM tasks t \
        WHERE \(whereClause) \
        ORDER BY match_score DESC, \(TaskRepo.taskOrderByQualified("t")) \
        LIMIT ?\(limitIdx) OFFSET ?\(offsetIdx)
        """
      let rows = try Row.fetchAll(db, sql: sql, arguments: StatementArguments(args))
      return Result(rows: try rows.map(TaskRepo.rowToTaskRow), totalMatching: totalMatching)
    }

    // -------------------------------------------------------------------
    // Filter scaffolding
    // -------------------------------------------------------------------

    /// `(tagJoin, whereExtra)` for the FTS-counted / FTS-only paths. The
    /// caller seeds `args` with the FTS query as `?1` first. The FTS path
    /// uses a JOIN form for the tag filter (it feeds the FROM clause), while
    /// the trigram/LIKE paths use the EXISTS form.
    static func buildFtsFilterScaffolding(
      pred: SearchPredicate, args: inout [any DatabaseValueConvertible]
    ) -> (tagJoin: String, whereExtra: String) {
      var conditions = ["t.archived_at IS NULL"]

      applyStatusFilter(pred, &conditions, &args)
      applyListFilter(pred, &conditions, &args)

      var tagJoin = ""
      if let tags = pred.tagFilter, !tags.isEmpty {
        let ph = Sql.sqlInPlaceholders(tags.count, args.count)
        conditions.append("tt.tag_id IN (\(ph))")
        for tag in tags { args.append(tag) }
        tagJoin = "JOIN task_tags tt ON t.id = tt.task_id"
      }

      let whereExtra = conditions.isEmpty ? "" : " AND \(conditions.joined(separator: " AND "))"
      return (tagJoin, whereExtra)
    }

    static func applyStatusFilter(
      _ pred: SearchPredicate, _ conditions: inout [String],
      _ args: inout [any DatabaseValueConvertible]
    ) {
      if let statuses = pred.statusFilter, !statuses.isEmpty {
        let ph = Sql.sqlInPlaceholders(statuses.count, args.count)
        conditions.append("t.status IN (\(ph))")
        for s in statuses { args.append(s) }
      }
    }

    static func applyListFilter(
      _ pred: SearchPredicate, _ conditions: inout [String],
      _ args: inout [any DatabaseValueConvertible]
    ) {
      if let lists = pred.listFilter, !lists.isEmpty {
        let ph = Sql.sqlInPlaceholders(lists.count, args.count)
        conditions.append("t.list_id IN (\(ph))")
        for l in lists { args.append(l) }
      }
    }

    static func applyTagFilterExists(
      _ pred: SearchPredicate, _ conditions: inout [String],
      _ args: inout [any DatabaseValueConvertible]
    ) {
      if let tags = pred.tagFilter, !tags.isEmpty {
        let ph = Sql.sqlInPlaceholders(tags.count, args.count)
        conditions.append(
          "EXISTS (SELECT 1 FROM task_tags tt3 WHERE tt3.task_id = t.id AND tt3.tag_id IN (\(ph)))")
        for tag in tags { args.append(tag) }
      }
    }

    // -------------------------------------------------------------------
    // FTS schema-missing classifier
    // -------------------------------------------------------------------

    /// True when the error indicates FTS5 is unavailable or a `tasks_fts*`
    /// shadow table was never created (fresh install, corrupted schema) —
    /// the only cases where search silently degrades to the LIKE fallback.
    /// Every other error must propagate.
    ///
    /// SQLite surfaces both "no such table" and "no such module" as the
    /// generic `SQLITE_ERROR` primary code; the message substring is the
    /// only discriminator SQLite provides.
    static func isFtsSchemaMissing(_ error: Error) -> Bool {
      guard let dbError = error as? DatabaseError else { return false }
      guard dbError.resultCode.primaryResultCode == .SQLITE_ERROR else { return false }
      guard let msg = dbError.message else { return false }
      let lower = msg.lowercased()
      return lower.contains("no such table") || lower.contains("no such module")
    }
  }
}
