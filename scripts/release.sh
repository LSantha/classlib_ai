#!/bin/sh
set -eu

# Local release helper: create tag, build artifacts, and publish a GitHub Release with artifacts.
# Usage: ./scripts/release.sh [<tag>|auto] [--dry-run]
# If no tag is provided or 'auto' is given, the script will create a date-based tag of the form
#   YYYY.MM.DD.N
# where N is a sequence number starting at 1 for each date.

# Parse arguments: optional tag (or 'auto') and optional --dry-run
TAG=""
DRY_RUN=false
if [ "$#" -eq 0 ]; then
  TAG=""  # auto
elif [ "$#" -eq 1 ]; then
  if [ "$1" = "--dry-run" ]; then
    DRY_RUN=true
    TAG=""  # auto
  else
    TAG="$1"
  fi
else
  TAG="$1"
  if [ "${2-}" = "--dry-run" ]; then
    DRY_RUN=true
  fi
fi

# If tag is empty or 'auto', compute date-based tag in the form
#   classlib-YYYY.MM.DD_NN  (NN is zero-padded two-digit sequence)
if [ -z "$TAG" ] || [ "$TAG" = "auto" ]; then
  DATE_PREFIX=$(date +%Y.%m.%d)
  prefix="classlib-${DATE_PREFIX}_"
  # fetch tags from origin to ensure we consider remote tags
  git fetch --tags origin >/dev/null 2>&1 || true
  max=0
  # list matching tags (local) and compute numeric suffix max
  for t in $(git tag --list "${prefix}*"); do
    # extract numeric suffix after last underscore
    n=$(echo "$t" | awk -F'_' '{print $NF}' | sed 's/^0*//')
    [ -z "$n" ] && n=0
    case "$n" in
      ''|*[!0-9]*) ;;
      *)
        if [ "$n" -gt "$max" ] 2>/dev/null; then
          max=$n
        fi
        ;;
    esac
  done
  next=$((max + 1))
  seq=$(printf "%02d" "$next")
  TAG="${prefix}${seq}"
fi

if [ "$DRY_RUN" = true ]; then
  echo "Release helper: tag=$TAG (auto) dry_run=$DRY_RUN"
else
  echo "Release helper: tag=$TAG dry_run=$DRY_RUN"
fi

command -v gh >/dev/null 2>&1 || { echo "gh (GitHub CLI) is required. Install: https://cli.github.com/"; exit 1; }
command -v git >/dev/null 2>&1 || { echo "git required"; exit 1; }

# Detect repository from git remote (supports both SSH and HTTPS URLs)
REPO_REMOTE=""
GH_REPO_FLAG=""
for remote in origin upstream; do
  remote_url=$(git remote get-url "$remote" 2>/dev/null) || continue
  # Strip .git suffix and extract owner/repo from SSH (git@github.com:owner/repo.git) or HTTPS (https://github.com/owner/repo.git) URLs
  case "$remote_url" in
    git@github.com:*)
      repo_path=$(echo "$remote_url" | sed 's|git@github.com:||' | sed 's|\.git$||')
      ;;
    https://github.com/*)
      repo_path=$(echo "$remote_url" | sed 's|https://github.com/||' | sed 's|\.git$||')
      ;;
    http://github.com/*)
      repo_path=$(echo "$remote_url" | sed 's|http://github.com/||' | sed 's|\.git$||')
      ;;
    *) continue ;;
  esac
  # Validate format (owner/repo)
  if echo "$repo_path" | grep -qE '^[a-zA-Z0-9_-]+/[a-zA-Z0-9_.-]+$'; then
    REPO_REMOTE="$repo_path"
    GH_REPO_FLAG="-R $REPO_REMOTE"
    echo "Detected repository: $REPO_REMOTE"
    break
  fi
done

if [ -z "$REPO_REMOTE" ]; then
  echo "Warning: Could not detect repository from git remote; gh will use default or require -R flag"
fi

# ensure clean working tree
if [ -n "$(git status --porcelain)" ]; then
  echo "Working tree not clean. Commit or stash changes first.";
  git status --porcelain
  exit 1
fi

# ensure on an expected branch
BRANCH=$(git rev-parse --abbrev-ref HEAD)
echo "On branch $BRANCH"

if [ "$DRY_RUN" = true ]; then
  echo "DRY RUN: would create tag $TAG and push it"
else
  echo "Creating annotated tag $TAG"
  git tag -a "$TAG" -m "Release $TAG"
  git push origin "$TAG"
fi

# Build artifacts using the existing build script. The Ant build expects java.runtime.version contains 1.6;
# we pass -Djava.runtime.version=1.6 to avoid failing on modern JDKs.
echo "Building artifacts (Ant targets: classlib-pack, classlib-src-bz)"
if [ "$DRY_RUN" = true ]; then
  echo "DRY RUN: ./build.sh -Djava.runtime.version=1.6 classlib-pack classlib-src-bz"
else
  ./build.sh -Djava.runtime.version=1.6 classlib-pack classlib-src-bz
fi

ART_DIR="all/build"
# Only upload the actual build artifacts to GitHub Releases. FTP metadata (`ftp.properties`) is
# internal to the legacy FTP deployment and should not be attached to GH releases.
ARTS="${ART_DIR}/classlib.pack.gz ${ART_DIR}/classlib-src.jar.bz2"

# Generate MD5 checksum files for artifacts so GH releases can include integrity data.
echo "Generating MD5 checksums (if md5sum available)"
for f in ${ARTS}; do
  if [ -f "$f" ]; then
    if command -v md5sum >/dev/null 2>&1; then
      md5sum "$f" | awk '{print $1}' > "${f}.md5"
      echo " - generated ${f}.md5"
    elif command -v md5 >/dev/null 2>&1; then
      md5 -q "$f" > "${f}.md5"
      echo " - generated ${f}.md5"
    else
      echo " - warning: no md5 tool found; skipping checksum for $f" >&2
    fi
  fi
done

echo "Preparing to publish release $TAG with assets:"
for f in ${ARTS}; do
  [ -f "$f" ] && echo " - $f" || echo " - MISSING: $f"
  [ -f "${f}.md5" ] && echo " - ${f}.md5" || true
done

if [ "$DRY_RUN" = true ]; then
  echo "DRY RUN: gh release create $GH_REPO_FLAG $TAG --title $TAG --notes 'Release $TAG' ${ARTS}";
  exit 0
fi

echo "Creating GitHub release and uploading assets"
# Create release and upload artifacts (gh will fail if an asset file does not exist; we upload only existing files)
UPLOAD_ARGS=""
for f in ${ARTS}; do
  if [ -f "$f" ]; then
    UPLOAD_ARGS="$UPLOAD_ARGS $f"
  fi
  if [ -f "${f}.md5" ]; then
    UPLOAD_ARGS="$UPLOAD_ARGS ${f}.md5"
  fi
done

if [ -z "$UPLOAD_ARGS" ]; then
  echo "No artifacts found to upload; aborting release creation.";
  exit 1
fi

gh release create $GH_REPO_FLAG "$TAG" --title "$TAG" --notes "Release $TAG" $UPLOAD_ARGS

echo "Release $TAG published."
