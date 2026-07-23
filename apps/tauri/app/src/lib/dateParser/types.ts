/** Result of extracting a date from natural language text. */
export interface ParseResult {
  /** The parsed date. */
  date: Date;
  /** The task title with the date phrase removed. */
  cleanTitle: string;
  /** The exact text fragment that was matched as a date expression. */
  matchedText: string;
}
