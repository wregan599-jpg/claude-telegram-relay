import type { Hit } from "./retrieval";

const TEXTBOOK_REQUEST =
  /\b(barash|miller|textbooks?|anesthesia\s+textbooks?|anesthesia\s+book)\b/i;

function isSkippedTextbookPath(hit: Hit): boolean {
  return (
    hit.file_path.includes("/Desktop/Exam_Prep/Textbooks/") &&
    hit.content.includes("extraction_status=skipped") &&
    hit.content.includes("chunk_count=0")
  );
}

function displayPath(path: string): string {
  return path.replace(`${process.env.HOME}/`, "");
}

export function buildSkippedTextbookResponse(
  message: string,
  hits: Hit[],
): string | null {
  if (!TEXTBOOK_REQUEST.test(message)) return null;

  const skippedHits = hits.filter(isSkippedTextbookPath).slice(0, 3);
  if (skippedHits.length === 0) return null;

  const files = skippedHits
    .map((hit) => `- ${displayPath(hit.file_path)}`)
    .join("\n");

  return [
    "I found the textbook files in your index, but they were indexed only as file paths, not extracted into searchable text yet.",
    "",
    files,
    "",
    "So I can confirm the files exist, but I cannot quote or answer from Barash/Miller content until we fix PDF extraction for those files.",
  ].join("\n");
}
