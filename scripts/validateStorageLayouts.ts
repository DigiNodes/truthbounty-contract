/**
 * Legacy storage-layout validation entry point (V2-SC-040 compatibility shim).
 *
 * The original implementation compared hardcoded slot *counts* that were never
 * derived from the compiler, so it validated nothing. Since V2-SC-121 the
 * canonical check is the reviewed storage-layout manifest:
 *
 *   npm run test:layouts   (scripts/generateStorageLayouts.ts --check)
 *
 * This shim delegates to that check so existing callers
 * (test/ReleaseReadiness.test.ts) exercise the real freeze.
 */

export async function validateStorageLayouts(): Promise<void> {
  // Lazy import keeps the solc compile out of unrelated tooling import paths.
  const cli = await import("./generateStorageLayouts");
  const ok = cli.checkStorageLayouts();
  if (!ok) {
    throw new Error("Storage layout validation failed (see storage-layouts check output).");
  }
}

if (require.main === module) {
  validateStorageLayouts()
    .then(() => process.exit(0))
    .catch((error) => {
      console.error(error);
      process.exit(1);
    });
}
