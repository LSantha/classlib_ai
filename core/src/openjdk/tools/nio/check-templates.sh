#!/bin/sh
#
# Verify that the vendored java.nio SPP templates and the SPP preprocessor
# still match the upstream OpenJDK 6 sources they were copied from.
#
# The templates cannot live in the compile path (they are full of SPP
# directives), so they were moved out of core/src/openjdk/java/java/nio into
# this tools/nio directory - which the oj-compare filesets do not scan.
# This script restores the drift detection for them.
#
# Usage: check-templates.sh <openjdk-checkout-dir>
#   <openjdk-checkout-dir> : dir holding jdk/src/share/classes and
#                            jdk/make (i.e. the value of main.openjdk.dir)
#
# Exits with a non-zero status if any file differs from upstream; prints a
# per-file status line so the report makes clear what drifted.

set -e

OJROOT="$1"
NIO_TEMPLATES="$OJROOT/jdk/src/share/classes/java/nio"
JAVA_MAKE="$OJROOT/jdk/make/java/nio"
SPP_SRC="$OJROOT/jdk/make/tools/src/build/tools/spp"

status=0

check() {
    local vendored="$1"
    local upstream="$2"
    local name="$3"
    if [ ! -f "$upstream" ]; then
        echo "  ?? $name: upstream file missing at $upstream"
        status=1
    elif cmp -s "$vendored" "$upstream"; then
        echo "  ok $name"
    else
        echo "  DRIFT $name: $vendored differs from $upstream"
        status=1
    fi
}

HERE=`dirname "$0"`

echo "java.nio SPP templates (expected: identical to upstream):"
check "$HERE/X-Buffer.java"              "$NIO_TEMPLATES/X-Buffer.java"              "X-Buffer.java"
check "$HERE/X-Buffer-bin.java"          "$NIO_TEMPLATES/X-Buffer-bin.java"          "X-Buffer-bin.java"
check "$HERE/Heap-X-Buffer.java"          "$NIO_TEMPLATES/Heap-X-Buffer.java"         "Heap-X-Buffer.java"
check "$HERE/Direct-X-Buffer.java"       "$NIO_TEMPLATES/Direct-X-Buffer.java"      "Direct-X-Buffer.java"
check "$HERE/Direct-X-Buffer-bin.java"   "$NIO_TEMPLATES/Direct-X-Buffer-bin.java"   "Direct-X-Buffer-bin.java"
check "$HERE/ByteBufferAs-X-Buffer.java" "$NIO_TEMPLATES/ByteBufferAs-X-Buffer.java" "ByteBufferAs-X-Buffer.java"
check "$HERE/genBuffer.sh"               "$JAVA_MAKE/genBuffer.sh"                  "genBuffer.sh"
check "$HERE/../spp/Spp.java"            "$SPP_SRC/Spp.java"                          "spp/Spp.java"

if [ "$status" != "0" ]; then
    echo "templates-check FAILED: vendored SPP tooling has drifted from upstream"
fi
exit "$status"