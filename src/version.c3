<*
 The version this build reports, on the first line of `--help`.

 A checkout says "dev". A release build is stamped from its v* tag before it
 compiles: `packaging/stamp-version.sh` rewrites the VERSION line, and the
 release workflow runs it. The stamped file is never committed.
*>
module ktxview;

const String VERSION = "dev";
