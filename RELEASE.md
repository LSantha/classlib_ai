Release guide — GitHub Releases for classlib_ai
===============================================

This document is a practical, self-contained guide for creating releases for `classlib_ai` using the repository's GitHub-based release workflow. It explains how to perform a release locally and via CI, what artifacts are produced, and how integrity information is published.

Scope
-----
- The GitHub release flow builds the same artifacts the existing Ant build produces and publishes them as GitHub Release assets.
- The legacy FTP upload (Ant `upload`/`deploy`) remains available for now; FTP metadata (`ftp.properties`) is intentionally not attached to GitHub Releases. This keeps the two publishing channels separate while we migrate.

Tag format used by the release script
------------------------------------
- The release script auto-generates tags using the format:
  classlib-YYYY.MM.DD_NN
  - example: `classlib-2026.04.11_01`
  - NN is a zero-padded two-digit sequence starting at 01 for each date.
- You can also pass an explicit tag to the script if you prefer a custom tag.

Prerequisites
-------------
- Git and the GitHub CLI (`gh`) installed and authenticated (run `gh auth status`).
- A clean working tree (no uncommitted changes) — the script enforces this.
- If you run CI releases, the workflow uses `${{ secrets.GITHUB_TOKEN }}` so no extra secrets are needed for publishing GitHub Releases. (FTP uploads require separate secrets and are not enabled by default.)

Local release (recommended workflow)
-----------------------------------
1. Make sure your working tree is clean and you are on the branch you want to release (e.g. `master`).
2. Run a dry-run to preview actions (no tag created, no build, no upload):

```bash
./scripts/release.sh --dry-run
```

3. If the dry-run looks good, create a real release (auto-generated tag):

```bash
./scripts/release.sh
```

Or provide an explicit tag:

```bash
./scripts/release.sh classlib-2026.04.11_01
```

What the script does
- Computes a tag (auto or uses the given tag).
- Creates an annotated tag and pushes it to `origin` (unless `--dry-run`).
- Builds artifacts via the project's Ant build (`./build.sh` with -Djava.runtime.version=1.6 to satisfy the legacy check).
- Generates per-artifact MD5 checksum files (e.g. `classlib.pack.gz.md5`) and uploads both artifacts and checksum files to the GitHub Release.

CI-based release
-----------------
- The repository includes a GitHub Actions workflow that runs on tag push. It builds the artifacts and publishes a GitHub Release with the artifacts and their `.md5` checksum files.
- The workflow is triggered on tags matching `classlib-*`.

Artifacts and integrity data
----------------------------
- Artifacts produced by the build:
  - `all/build/classlib.pack.gz`
  - `all/build/classlib-src.jar.bz2`
- The release process also produces companion checksum files uploaded to the GH Release:
  - `all/build/classlib.pack.gz.md5` (contains the hex MD5 digest)
  - `all/build/classlib-src.jar.bz2.md5`
- FTP metadata (`ftp.properties`) is produced by the Ant `upload` target and remains part of the FTP workflow only; it is not attached to GitHub Releases.

Dry-run details and network behavior
------------------------------------
- `--dry-run` prints the computed tag and the commands the script would run but does not create or push the tag, does not run the full build, and does not create the GH Release.
- When computing an auto tag the script performs `git fetch --tags origin` to inspect remote tags and choose the next sequence number — so dry-run may perform a network fetch when using auto mode. If you need a fully offline preview, call the script with an explicit tag.

Security and notes
------------------
- The script and CI use MD5 for parity with the existing FTP-based flow. MD5 is suitable for simple integrity checks but is not collision-resistant; consider SHA-256 if you want stronger guarantees (this requires updating jnode consumers).
- FTP credentials (if you enable FTP upload) must be stored in environment or GitHub Secrets — do not commit them into the repository.

Troubleshooting
---------------
- "Working tree not clean" — commit or stash changes before running the script.
- Tag push fails because tag already exists remotely — this can happen if someone else pushed a tag concurrently. Re-run the script (it will compute the next sequence) or provide an explicit tag.
- CI didn't run for my tag — ensure your tag matches `classlib-*` or update the workflow triggers if you prefer a different pattern.

Extending or changing the workflow
---------------------------------
- To add changelog generation, signature files, or alternative checksum algorithms (SHA-256), update `scripts/release.sh` and the workflow accordingly.
- To re-enable FTP uploads from the GH workflow (not recommended by default), add a step that creates a `jnode.properties` file from repository secrets and runs the Ant `deploy` target. Be cautious: the Ant upload deletes old directories on the remote FTP server and needs correct credentials.

Questions / next steps
---------------------
  - add an optional `--ftp` flag to the release script to run the Ant `deploy` target (opt-in),
  - switch to SHA-256 checksums for the GH Release assets,
  - or add a retry-on-push loop to handle tag collisions automatically.
