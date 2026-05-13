import { createHash, randomUUID } from "crypto";
import { chmod, mkdir, open, rename, stat, unlink } from "fs/promises";
import { homedir } from "os";
import { dirname, join } from "path";

export const DEFAULT_SHORTCUT_NAME = "ClaudeDraft";

export interface ICloudDriveDraftInput {
  recipient: string;
  recipientLabel: string;
  body: string;
}

export interface ICloudDriveDraftResult {
  ok: boolean;
  path?: string;
  shortcutUrl?: string;
  bodySha256?: string;
  error?: string;
}

export function defaultICloudDriveDraftDir(): string {
  return process.env.RELAY_ICLOUD_DRAFT_DIR
    ?? join(
      homedir(),
      "Library",
      "Mobile Documents",
      "iCloud~is~workflow~my~workflows",
      "Documents",
      "claude-relay-drafts",
    );
}

export function shortcutRunUrl(
  shortcutName = process.env.RELAY_IMESSAGE_SHORTCUT_NAME ?? DEFAULT_SHORTCUT_NAME,
): string {
  return `shortcuts://run-shortcut?name=${encodeURIComponent(shortcutName)}`;
}

export async function writeICloudDriveDraft(
  input: ICloudDriveDraftInput,
  options: { dir?: string; now?: Date; shortcutName?: string } = {},
): Promise<ICloudDriveDraftResult> {
  const dir = options.dir ?? defaultICloudDriveDraftDir();
  const cloudDocsRoot = dirname(dir);

  try {
    const rootStats = await stat(cloudDocsRoot);
    if (!rootStats.isDirectory()) {
      return { ok: false, error: `icloud_drive_root_not_directory:${cloudDocsRoot}` };
    }
  } catch {
    return { ok: false, error: `icloud_drive_root_missing:${cloudDocsRoot}` };
  }

  const bodySha256 = createHash("sha256").update(input.body, "utf8").digest("hex");
  const payload = {
    recipient: input.recipient,
    recipient_label: input.recipientLabel,
    body: input.body,
    ts: (options.now ?? new Date()).toISOString(),
    body_sha256: bodySha256,
  };

  const target = join(dir, "latest.json");
  const tmp = join(dir, `.tmp-${process.pid}-${Date.now()}-${randomUUID()}.json`);

  let handle: Awaited<ReturnType<typeof open>> | null = null;
  try {
    await mkdir(dir, { recursive: true, mode: 0o700 });
    handle = await open(tmp, "wx", 0o600);
    await handle.writeFile(JSON.stringify(payload, null, 2) + "\n", "utf8");
    await handle.sync();
    await handle.close();
    handle = null;
    await chmod(tmp, 0o600);
    await rename(tmp, target);
  } catch (err) {
    if (handle) {
      try {
        await handle.close();
      } catch {
        // Ignore cleanup failure.
      }
    }
    try {
      await unlink(tmp);
    } catch {
      // Ignore cleanup failure.
    }
    return {
      ok: false,
      error: err instanceof Error ? err.message : String(err),
    };
  }

  return {
    ok: true,
    path: target,
    shortcutUrl: shortcutRunUrl(options.shortcutName),
    bodySha256,
  };
}
