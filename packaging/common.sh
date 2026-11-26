# Sourced by the package-*.sh scripts. Run from the repository root, after
# `c3c build ktxview`.

set -euo pipefail

# The version from a v* tag, or a dev stamp for a hand-run build.
ktxview_version() {
	local ref="${GITHUB_REF_NAME:-$(git describe --tags --exact-match 2>/dev/null || true)}"
	case "$ref" in
		v*) echo "${ref#v}" ;;
		*)  echo "0.0.0-dev+$(git rev-parse --short HEAD)" ;;
	esac
}

# Copy the licences into <dir>: ktxview's and the compiled-in font's. Nothing
# else is read at run time, so a bundle needs no assets folder. The optional
# second argument is a suffix for the file names, such as .txt on Windows.
stage_licenses() {
	cp LICENSE "$1/LICENSE${2:-}"
	cp assets/DejaVuSans-LICENSE "$1/DejaVuSans-LICENSE${2:-}"
}
