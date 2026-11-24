#!/bin/sh
# Generate the concrete java.nio buffer classes from the OpenJDK templates.
#
# Usage: gen-buffers.sh <spp-classes-dir> <templates-dir> <output-dir> [java-cmd]
#   <spp-classes-dir> : dir containing the compiled build.tools.spp.Spp
#   <templates-dir>   : dir with X-Buffer.java, Heap-X-Buffer.java,
#                       Direct-X-Buffer.java, ByteBufferAs-X-Buffer.java,
#                       X-Buffer-bin.java, Direct-X-Buffer-bin.java, genBuffer.sh
#   <output-dir>      : dir to write ByteBuffer.java, CharBuffer.java, ... into
#   <java-cmd>        : JVM used to run Spp; defaults to "java" from PATH.
#                       The build passes ${java.home}/bin/java so SPP runs on
#                       the same JVM the classlib is built with.
#
# Generates the full OpenJDK 6 buffer set (71 files):
#   - 7  abstract base buffers        (ByteBuffer, CharBuffer, ...)   [X-Buffer]
#   - 7  heap buffers                 (HeapByteBuffer, ...)           [Heap-X-Buffer]
#   - 7  read-only heap buffers       (HeapByteBufferR, ...)          [Heap-X-Buffer RW=R]
#   - 26 direct buffers               (DirectByteBuffer, DirectCharBufferU/S, ...)
#                                                                      [Direct-X-Buffer]
#   - 24 view buffers                 (ByteBufferAsCharBufferB/L, ...)
#                                                                      [ByteBufferAs-X-Buffer]
# This replaces the GNU Classpath java.nio buffer classes wholesale; the
# JNode-specific native methods (Bits.copy*, MappedByteBuffer.isLoaded0/load0/
# force0) are provided by the Native* classes in the sibling jnode_ai tree.
set -e

SPP_CLASSES="$1"
TEMPLATES="$2"
OUT="$3"

# Start from a clean output dir so stale files from a previous (e.g. heap-only)
# run cannot leak into the build.
rm -rf "$OUT"
mkdir -p "$OUT"

# SPP must be a single executable for genBuffer.sh (it does an unquoted
# $SPP <in >out, so spaces would word-split). Wrap it. The JVM used for
# SPP is passed by the build (${java.home}/bin/java) so it is always the
# same one that compiles the classlib.
JAVA_CMD="${4:-java}"
SPP_WRAPPER="$OUT/.spp.sh"
cat > "$SPP_WRAPPER" <<EOF
#!/bin/sh
exec "$JAVA_CMD" -cp "$SPP_CLASSES" build.tools.spp.Spp "\$@"
EOF
chmod +x "$SPP_WRAPPER"

export SPP="$SPP_WRAPPER" NAWK=awk SED=sed SH=sh

# 1. Abstract base buffers. BIN=1 (binary-data access methods from
#    X-Buffer-bin.java) applies only to ByteBuffer; the other types get
#    X-Buffer.java alone, matching the upstream Makefile rules.
for spec in "byte:ByteBuffer" "char:CharBuffer" "short:ShortBuffer" \
            "int:IntBuffer" "long:LongBuffer" "float:FloatBuffer" "double:DoubleBuffer"; do
  type=${spec%%:*}
  name=${spec##*:}
  if [ "$type" = "byte" ]; then
    TYPE=$type BIN=1 SRC="$TEMPLATES/X-Buffer.java" DST="$OUT/$name.java" \
      sh "$TEMPLATES/genBuffer.sh"
  else
    TYPE=$type SRC="$TEMPLATES/X-Buffer.java" DST="$OUT/$name.java" \
      sh "$TEMPLATES/genBuffer.sh"
  fi
done

# 2. Heap buffers (concrete backing-array buffers).
for spec in "byte:HeapByteBuffer" "char:HeapCharBuffer" "short:HeapShortBuffer" \
            "int:HeapIntBuffer" "long:HeapLongBuffer" "float:HeapFloatBuffer" "double:HeapDoubleBuffer"; do
  type=${spec%%:*}
  name=${spec##*:}
  TYPE=$type SRC="$TEMPLATES/Heap-X-Buffer.java" DST="$OUT/$name.java" \
    sh "$TEMPLATES/genBuffer.sh"
done

# 3. Read-only heap variants (HeapByteBufferR, HeapCharBufferR, ...).
for spec in "byte:HeapByteBufferR" "char:HeapCharBufferR" "short:HeapShortBufferR" \
            "int:HeapIntBufferR" "long:HeapLongBufferR" "float:HeapFloatBufferR" "double:HeapDoubleBufferR"; do
  type=${spec%%:*}
  name=${spec##*:}
  TYPE=$type RW=R SRC="$TEMPLATES/Heap-X-Buffer.java" DST="$OUT/$name.java" \
    sh "$TEMPLATES/genBuffer.sh"
done

# 4. Direct buffers. DirectByteBuffer itself (BIN=1) + read-only; then the
#    unswapped (U) and swapped (S) views of each type, writable + read-only.
#    Direct-X-Buffer uses sun.misc.Unsafe (allocateMemory/copyMemory/
#    freeMemory), which NativeUnsafe now backs.
TYPE=byte BIN=1 SRC="$TEMPLATES/Direct-X-Buffer.java" DST="$OUT/DirectByteBuffer.java" \
  sh "$TEMPLATES/genBuffer.sh"
TYPE=byte BIN=1 RW=R SRC="$TEMPLATES/Direct-X-Buffer.java" DST="$OUT/DirectByteBufferR.java" \
  sh "$TEMPLATES/genBuffer.sh"
for bo in U S; do
  for spec in "char:DirectCharBuffer" "short:DirectShortBuffer" \
              "int:DirectIntBuffer" "long:DirectLongBuffer" \
              "float:DirectFloatBuffer" "double:DirectDoubleBuffer"; do
    type=${spec%%:*}
    name=${spec##*:}
    TYPE=$type BO=$bo SRC="$TEMPLATES/Direct-X-Buffer.java" DST="$OUT/${name}${bo}.java" \
      sh "$TEMPLATES/genBuffer.sh"
    TYPE=$type BO=$bo RW=R SRC="$TEMPLATES/Direct-X-Buffer.java" DST="$OUT/${name}R${bo}.java" \
      sh "$TEMPLATES/genBuffer.sh"
  done
done

# 5. View buffers (ByteBufferAsCharBufferB/L, etc.): big- and little-endian
#    views of a ByteBuffer, writable + read-only, for each type.
for bo in B L; do
  for spec in "char:ByteBufferAsCharBuffer" "short:ByteBufferAsShortBuffer" \
              "int:ByteBufferAsIntBuffer" "long:ByteBufferAsLongBuffer" \
              "float:ByteBufferAsFloatBuffer" "double:ByteBufferAsDoubleBuffer"; do
    type=${spec%%:*}
    name=${spec##*:}
    TYPE=$type BO=$bo SRC="$TEMPLATES/ByteBufferAs-X-Buffer.java" DST="$OUT/${name}${bo}.java" \
      sh "$TEMPLATES/genBuffer.sh"
    TYPE=$type BO=$bo RW=R SRC="$TEMPLATES/ByteBufferAs-X-Buffer.java" DST="$OUT/${name}R${bo}.java" \
      sh "$TEMPLATES/genBuffer.sh"
  done
done

rm -f "$SPP_WRAPPER"

echo "generated $(ls "$OUT"/*.java | wc -l) buffer source files in $OUT"