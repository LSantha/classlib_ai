# Agent Instructions for JNode Classlib

## Project Context

This repo builds the JNode **class library** (`classlib.jar`): the `java.*`/`javax.*`
runtime the JNode OS runs on. It is the library half of a two-repo split:

| Repo | Role | Rule |
|------|------|------|
| `classlib_ai` (here) | Full upstream imports (OpenJDK 6, GNU Classpath, IcedTea) compiled as-is into one monolithic `classlib.jar`, plus tiny JNode-owned additions | Upstream trees stay pristine; every intentional divergence is tagged (see Sync Philosophy) |
| `jnode_ai` (sibling OS checkout, `../jnode_ai`) | Kernel, drivers, plugins, and the **overlay trees** (`core/src/openjdk/vm`, `core/src/classpath/vm`) whose classes shadow `classlib.jar` at boot/plugin load | Houses plugin descriptors that re-export `classlib.jar` packages |

Philosophy: the classlib never forks upstream files silently. Divergence is either
mechanical (build-time annotation injection via `all/conf/openjdk-annotations.properties`)
or marked in-source so the compare reports file it correctly.

## Workspace Layout

The build expects this sibling layout under one parent dir (all local-only):

```
<parent>/classlib_ai   this repo
<parent>/jnode_ai      OS checkout (a plain clone; wired via jnode.properties)
<parent>/openjdk       upstream OpenJDK 6 sources (compare only, never built here)
<parent>/classpath     upstream GNU Classpath sources (compare only)
```

- `jnode.properties` is **gitignored, local-only**. It must set
  `main.jnode.dir=${root.dir}/../jnode_ai` (deploy target),
  `main.openjdk.dir=${root.dir}/../openjdk` and
  `main.classpath.dir=${root.dir}/../classpath` (compare targets).
- Upstream versions and provenance are recorded in
  `<parent>/openjdk/JNODE_UPSTREAM.txt` (b27 bundle, 26 Oct 2012 — exact match
  for the tree's last integration) and `<parent>/classpath/JNODE_UPSTREAM.txt`
  (0.99, Mar 2012; authoritative markers are its own `NEWS`/`configure.ac`).
  Live OpenJDK history (b00–b49) is at `github.com/openjdk/jdk6`; Classpath is
  dormant since Mar 2016 (112 post-0.99 commits: warnings + API stubs, 3 real fixes).

## Key Directories

| Path | Purpose |
|------|---------|
| `core/src/openjdk/` | Full OpenJDK 6 snapshot: `java`, `javax`, `com`, `sun`, `org`, `jaxws`, `langtools`, `svm` (11.7k files). No overlay dir exists here by design |
| `core/src/classpath/{gnu,java,javax,tools}` | GNU Classpath subset (616 files) |
| `core/src/icedtea/` | IcedTea gap-fillers (129 files) |
| `core/src/classlib/` | JNode-owned only: `org.jnode.annotation.*`, `org.jnode.java.*`, `java/lang/ProcessImpl.java` (20 files) |
| `builder/src/builder/.../taskdefs/classpath/` | Build tooling incl. `CompareTask.java` |
| `all/conf/` | `openjdk-annotations.properties`, `oj-compare-excludes.txt`, plugin lists |
| `all/build.xml`, `core/build.xml` | Master + core build files |

## Build System

- **Command**: `sh build.sh <target>` from root. **Java 1.6** required.
- **Main targets**: `classlib`, `classlib-src`, `copy`, `quick-deploy`
  (= `classlib` + `classlib-src` + `copy`), `clean`, `oj-compare`, `cp-compare`.
- **Downstream flow**: `sh build.sh quick-deploy` copies both jars to
  `../jnode_ai/all/lib/`; the sibling must have `jnode.local.classlib=true`
  in its (also gitignored) `jnode.properties`, otherwise it downloads
  classlib from the net and overwrites them.

## Upstream Sync Philosophy

Syncing is **manual, selective merge** — the compare targets are report-only
worklists, never auto-merge (`CompareTask` only writes `all/build/*-compare/`).
A past integration (`5a802ec3`, "Integrating OpenJDK 6 build 27") touched just
28 files. Workflow for any re-sync:

1. `sh build.sh oj-compare` (OpenJDK) / `cp-compare` (Classpath).
2. Work the `NEEDS_MERGE` rows; **skip green `vm-specific` rows**; treat yellow
   `openjdk-only` rows as deletion candidates, not auto-imports.
3. Keep large removals + their tracking config in reviewable commits
   (precedent: mechanism commit, then modified-files commit, then deletions commit).

Divergence tracking, in order of preference:
- `@vm-specific` javadoc tag on intentionally diverged classes (compare files
  them green; e.g. JRMP-only JMX after the CORBA removal).
- `@classpath-bugfix[-<bugzilla-id>]` for fixes also sent upstream.
- `all/conf/oj-compare-excludes.txt`: Ant path patterns (`pkg/**` for packages,
  exact paths for single classes) hiding **upstream-missing** rows of
  intentionally removed APIs. Files present in the tree are always still
  compared, so a resurrected file surfaces immediately.
- `oj-compare` covers upstream `jdk/`, `corba/` and `langtools/` repos
  (the `corba/` fileset exists precisely so deletions stay visible).
  `jaxws`/`jaxp` remain out of scope (commented out), as before.

## Downstream Integration Notes (learned removing CORBA, JEP-320 style)

- `javax.rmi.CORBA` + `PortableRemoteObject` are CORBA (delete); `javax.rmi.ssl`
  is JRMP (keep). `javax.activity` is CORBA (delete); `javax.transaction/xa`
  is JTA (keep). `java.rmi`/`sun.rmi` never depended on CORBA — the arrow
  points `CORBA → RMI`, so plain RMI survives untouched.
- JAX-WS does **not** use CORBA (only `{@link com.sun.pept...}` doc references;
  `com.sun.pept` shipped inside the corba repo).
- The only true external users were optional IIOP transports: JMX
  (`RMIConnector`/`RMIConnectorServer` → JRMP-only; `RMIIIOPServerImpl` and
  `ProxyInputStream` deleted; `com.sun.jmx.remote.protocol.iiop` provider
  classes stay — they load fine and fail only at use time), CosNaming JNDI
  provider + `corbaname`/`iiop`/`iiopname` URL contexts, `idlj`, rmic-IIOP.
- Stale references live in the **sibling**: JNode plugin descriptors
  (`core/descriptors/org.classpath.ext.*.xml`, `all/conf/*plugin-list.xml`)
  export `classlib.jar` packages — remove dead fragments/exports there
  (precedent: `org.classpath.ext.corba` fragment + 72 dangling exports).
- Boot validation: VirtualBox headless + serial agent is the validated loop
  (see sibling skills). QEMU is misleading here: KVM faults very early and
  `-vga none` under TCG stalls the shell spinning on the serial port
  (shows as `OutOfMemoryError` in `CommandShellReader`) — both environmental.

## Known Platform Limits (verified, do not re-investigate)

- **No TLS 1.2 anywhere**: runtime JSSE is OpenJDK's (`MAX = TLS10`); b49 only
  adds a `TLS12` constant (`MAX` becomes `TLS11`, default stays 1.0) — no working
  1.2 exists in the OpenJDK 6 line. LLM HTTPS endpoints (TLS ≥ 1.2 mandatory)
  are unreachable from this stack; realistic routes are a BouncyCastle `bctls`
  plugin or an off-box TLS proxy, not a JSSE backport.
- Upstream post-freeze movement (for context, not action): OpenJDK b27→b49
  ≈ 1,900 files, dominated by 2013–16 CPU security backports; one hunk applies
  to our tree (`ReflectUtil.checkPackageAccess` in `RMIConnector`'s
  `ObjectInputStreamWithLoader` — intentionally left for a security pass).

## Constraints

- Never commit unless explicitly requested. Never push force to main/master.
- Don't commit secrets or credentials. `jnode.properties` stays untracked.
- Verify by execution: `classlib` must build, `oj-compare` must stay green,
  and any runtime-affecting change needs a sibling boot (`cd-x86-lite` + shell
  responsive over serial) before calling it done.
