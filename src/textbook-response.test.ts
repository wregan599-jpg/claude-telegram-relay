import { expect, test } from "bun:test";
import { buildSkippedTextbookResponse } from "./textbook-response";
import type { Hit } from "./retrieval";

function hit(path: string, content: string): Hit {
  return {
    chunk_id: -1,
    file_path: path,
    content,
    chunk_index: 0,
    rank_score: -1,
    display_score: 1,
    score: 1,
  };
}

test("returns deterministic response for skipped textbook path hits", () => {
  const response = buildSkippedTextbookResponse("What does Barash say?", [
    hit(
      `${process.env.HOME}/Desktop/Exam_Prep/Textbooks/Miller_Barash/Barash 9.pdf`,
      "Indexed file path match. extraction_status=skipped; chunk_count=0",
    ),
  ]);

  expect(response).toContain("I found the textbook files");
  expect(response).toContain("Barash 9.pdf");
  expect(response).toContain("cannot quote or answer");
});

test("does not intercept non-textbook retrieval", () => {
  const response = buildSkippedTextbookResponse("What did we decide?", [
    hit(
      `${process.env.HOME}/Desktop/Exam_Prep/Textbooks/Miller_Barash/Barash 9.pdf`,
      "Indexed file path match. extraction_status=skipped; chunk_count=0",
    ),
  ]);

  expect(response).toBeNull();
});

test("does not intercept extracted textbook content", () => {
  const response = buildSkippedTextbookResponse("What does Miller say?", [
    hit(
      `${process.env.HOME}/Desktop/Exam_Prep/Textbooks/Miller_Barash/Miller.pdf`,
      "Airway management chapter content",
    ),
  ]);

  expect(response).toBeNull();
});
