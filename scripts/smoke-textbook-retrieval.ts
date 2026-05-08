import { buildSearchQuery } from "../src/query-builder";
import { search } from "../src/retrieval";

const checks = [
  {
    message: "Anesthesia textbook",
    expectedQuery: '"anesthesia" "textbook"',
  },
  {
    message: "Please continue to look for my anesthesia textbooks",
    expectedQuery: '"anesthesia" "textbooks"',
  },
  {
    message: "It should be with miller",
    expectedQuery: '"miller" "anesthesia"',
  },
];

for (const check of checks) {
  const query = buildSearchQuery(check.message, [
    {
      role: "user",
      content: "Anesthesia textbook",
      ts: new Date(0).toISOString(),
    },
  ]);

  if (query !== check.expectedQuery) {
    throw new Error(
      `unexpected query for ${JSON.stringify(check.message)}: ${query}`,
    );
  }

  const t0 = Date.now();
  const hits = await search(query, 5);
  const elapsed = Date.now() - t0;
  const textbookHits = hits.filter((hit) =>
    hit.file_path.includes("/Desktop/Exam_Prep/Textbooks/")
  );

  console.log(
    JSON.stringify(
      {
        message: check.message,
        query,
        elapsed,
        hit_count: hits.length,
        textbook_hit_count: textbookHits.length,
        first_textbook_hit: textbookHits[0]?.file_path,
        first_textbook_status: textbookHits[0]?.content,
      },
      null,
      2,
    ),
  );

  if (textbookHits.length === 0) {
    throw new Error(`no textbook path hits for ${query}`);
  }

  if (!textbookHits[0].content.includes("extraction_status=skipped")) {
    throw new Error(`textbook hit did not surface extraction status for ${query}`);
  }
}

console.log("PASS: textbook retrieval smoke checks returned scoped path hits");
