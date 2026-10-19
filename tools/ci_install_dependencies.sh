# Sourced by .github/workflows/build.yml from the directory holding the
# castle-build-ci clone: runs its install_dependencies until wget is there
# (on Windows it installs wget through Chocolatey, whose feed sometimes
# answers 503 / 504 while the script still exits 0), and if three tries
# give no wget, puts a curl-based stand-in on the PATH (this step's and,
# through GITHUB_PATH, the next steps'). setup_castle_engine only calls
# "wget --progress=... URL --output-document FILE".

ci_install_dependencies() {
  local attempt shim
  for attempt in 1 2 3; do
    if castle-build-ci/install_dependencies && command -v wget > /dev/null; then
      return 0
    fi
    echo "install_dependencies left no wget (attempt $attempt)"
    if [ "$attempt" != 3 ]; then sleep 30; fi
  done
  shim="${RUNNER_TEMP:-/tmp}/wget-shim"
  mkdir -p "$shim"
  cat > "$shim/wget" << 'EOF'
#!/bin/bash
# wget stand-in (curl): a URL and --output-document / -O FILE.
out=""
url=""
while [ $# -gt 0 ]; do
  case "$1" in
    --output-document|-O) out="$2"; shift 2 ;;
    --output-document=*) out="${1#*=}"; shift ;;
    -*) shift ;;
    *) url="$1"; shift ;;
  esac
done
exec curl -fL --retry 5 --retry-delay 5 -o "${out:-$(basename "$url")}" "$url"
EOF
  chmod +x "$shim/wget"
  export PATH="$shim:$PATH"
  if [ -n "${GITHUB_PATH:-}" ]; then echo "$shim" >> "$GITHUB_PATH"; fi
  echo "Using a curl-based wget from $shim"
}

ci_install_dependencies
