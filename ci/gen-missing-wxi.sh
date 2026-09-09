#!/bin/bash
# msitools' prebuilt .wxi groups drift from what Fedora ships; regenerate the
# missing, stale and duplicate ones with wixl-heat, keeping their <?require?> edges.
set -euo pipefail

S=/usr/x86_64-w64-mingw32/sys-root/mingw
W=$(rpm -ql msitools | grep -m1 'spice-gtk3.wxi' | xargs dirname)

roots=(spice-gtk3 gstreamer1-plugins-base gstreamer1-plugins-good
       gstreamer1-plugins-bad-free adwaita-icon-theme libxml2)

sources_of() { grep -ho 'Source="$(var.SourceDir)[^"]*"' "$W/$1.wxi" 2>/dev/null |
               sed 's|Source="$(var.SourceDir)||; s|"$||'; }
requires_of() { grep -ho '<?require [^?]*?>' "$W/$1.wxi" 2>/dev/null |
                sed 's/<?require //; s/?>//; s/\.wxi//' | tr -d ' '; }

# rpm prints "no package provides X" on stdout and exits 1, so gate on its exit
# status; reading the output would carry that sentence on as a package name.
resolve_pkg() { local out
                out=$(rpm -q --whatprovides --queryformat '%{NAME}\n' "$1" 2>/dev/null) || return 1
                echo "$out" | head -1; }

# Fedora's renames and soname bumps leave the .wxi name behind (libsoup ->
# libsoup3, SDL2 -> sdl2-compat). Prefer a successor that is already installed:
# something in the runtime closure pulled it in, so it holds the DLL the other
# groups actually link against -- installing the old name would ship a dead one.
provider_for() {
    local n=$1 pkg
    resolve_pkg "mingw64-$n" && return 0
    pkg=$(rpm -qa --queryformat '%{NAME}\n' "mingw64-$n[0-9]*" |
          grep -Ev -- '-(devel|static|tools)$' | sort | head -1) || true
    [ -n "$pkg" ] && { echo "$pkg"; return 0; }
    dnf install -y "mingw64-$n" >/dev/null 2>&1 || return 1
    resolve_pkg "mingw64-$n"
}

owner_pkg() {                       # ask rpm about a file the wxi lists that exists
    local n=$1 f out
    while read -r f; do
        [ -e "$S$f" ] || continue
        out=$(rpm -qf --queryformat '%{NAME}\n' "$S$f" 2>/dev/null) || continue
        echo "$out" | head -1; return 0
    done < <(sources_of "$n")
    provider_for "$n"               # nothing it lists survives; go by name
}

is_stale() { local f; while read -r f; do [ -e "$S$f" ] || return 0
             done < <(sources_of "$1"); return 1; }

# msitools' groups carry runtime files only; wixl-heat over a whole RPM would add
# headers and static libs to the installer. Their per-package .ignore sidecars are
# not in the package, so approximate them.
runtime_only() {
    grep -Ev '/include/|\.a$|\.la$|/lib/pkgconfig/|/bin/[^/]*-config$|/share/(man|doc|gtk-doc|info|aclocal|gir-1\.0|vala)/'
}

regen() {
    local n=$1 pkg=$2; shift 2
    local reqargs=() r
    for r in "$@"; do reqargs+=(--require "$r"); done
    local files
    # grep exits 1 on no match, which under pipefail would kill the script here
    # before the guard below can say which package was empty.
    files=$(rpm -ql "$pkg" | grep "^$S/" | runtime_only |
            while read -r f; do [ -f "$f" ] && echo "$f"; done) || true
    # An empty group installs nothing and fails at runtime, not at build time.
    [ -n "$files" ] || { echo "!! $pkg contributes no runtime files to $n.wxi" >&2; exit 1; }
    # -i emits an <Include> root; wixl rejects a bare <Wix> when included.
    echo "$files" |
        wixl-heat -i --var var.SourceDir -p "$S/" --directory-ref INSTALLDIR \
                  --win64 --component-group "CG.$n" "${reqargs[@]}" > "$W/$n.wxi"
}

ensure() {                          # generate-if-missing / resync-if-stale
    local n=$1 pkg
    if [ ! -e "$W/$n.wxi" ]; then
        pkg=$(provider_for "$n") ||
            { echo "!! nothing provides mingw64-$n for missing $n.wxi" >&2; exit 1; }
        regen "$n" "$pkg"; echo "generated $n.wxi from $pkg"
    elif is_stale "$n"; then
        pkg=$(owner_pkg "$n") ||
            { echo "!! nothing provides mingw64-$n to resync $n.wxi" >&2; exit 1; }
        mapfile -t reqs < <(requires_of "$n")
        regen "$n" "$pkg" "${reqs[@]}"
        echo "resynced  $n.wxi from $pkg"
    fi
}

declare -A inclosure
walk() {                            # <?require?> closure from a seed
    local queue=("$@") n dep
    while [ ${#queue[@]} -gt 0 ]; do
        n="${queue[0]}"; queue=("${queue[@]:1}")
        [ -n "${inclosure[$n]:-}" ] && continue
        ensure "$n"; inclosure[$n]=1
        while read -r dep; do [ -n "$dep" ] && queue+=("$dep"); done < <(requires_of "$n")
    done
}

walk "${roots[@]}"

# A .wxi listing another package's files duplicates them once both groups are
# referenced, and libmsi rejects the duplicate insert -- resync it from its owner.
pkg_of_name() { resolve_pkg "mingw64-$1" || true; }

files=(); for n in "${!inclosure[@]}"; do files+=("$W/$n.wxi"); done
mapfile -t dups < <(grep -h 'Source="$(var.SourceDir)' "${files[@]}" |
                    sed 's|.*Source="$(var.SourceDir)||; s|".*||' | sort | uniq -d)
declare -A resync
for p in "${dups[@]}"; do
    owner=$(rpm -qf --queryformat '%{NAME}\n' "$S$p" 2>/dev/null | head -1) || continue
    for n in "${!inclosure[@]}"; do
        grep -q "SourceDir)$p\"" "$W/$n.wxi" || continue
        own=$(pkg_of_name "$n")
        [ -n "$own" ] && [ "$own" != "$owner" ] && resync[$n]=$own
    done
done
for n in "${!resync[@]}"; do
    mapfile -t reqs < <(requires_of "$n")
    regen "$n" "${resync[$n]}" "${reqs[@]}"
    echo "deduped   $n.wxi from ${resync[$n]} (was carrying other packages' files)"
done

# Alias ComponentGroupRefs nothing defines (renamed packages: SDL2 -> sdl2-compat)
# into a file that is actually <?require?>d, since wixl only pulls in what is.
norm() { echo "$1" | tr 'A-Z' 'a-z' | tr -cd 'a-z0-9'; }

add_alias() {                       # $1 = provider wxi, $2 = alias group name
    python3 - "$W/$1.wxi" "$2" "$1" <<'PY'
import io, sys
path, alias, provider = sys.argv[1], sys.argv[2], sys.argv[3]
s = io.open(path, encoding='utf8').read()
frag = ('  <Fragment>\n'
        '    <ComponentGroup Id="CG.%s">\n'
        '      <ComponentGroupRef Id="CG.%s"/>\n'
        '    </ComponentGroup>\n'
        '  </Fragment>\n</Include>' % (alias, provider))
assert s.count('</Include>') == 1, path
io.open(path, 'w', encoding='utf8').write(s.replace('</Include>', frag))
PY
}

while :; do
    files=(); for n in "${!inclosure[@]}"; do files+=("$W/$n.wxi"); done
    defined=$(grep -ho '<ComponentGroup Id="CG\.[^"]*"' "${files[@]}" |
              sed 's/.*Id="CG\.//; s/"//' | sort -u)
    referenced=$(grep -ho 'ComponentGroupRef Id="CG\.[^"]*"' "${files[@]}" |
                 sed 's/.*Id="CG\.//; s/"//' | sort -u)
    missing=$(comm -13 <(echo "$defined") <(echo "$referenced"))
    [ -z "$missing" ] && break
    progress=0
    for m in $missing; do
        for n in "${!inclosure[@]}"; do
            grep -q "ComponentGroupRef Id=\"CG\.$m\"" "$W/$n.wxi" || continue
            for r in $(requires_of "$n"); do
                [ -n "${inclosure[$r]:-}" ] || continue
                case "$(norm "$r")" in "$(norm "$m")"*) ;; *)
                    case "$(norm "$m")" in "$(norm "$r")"*) ;; *) continue ;; esac ;;
                esac
                add_alias "$r" "$m"
                echo "aliased   CG.$m -> CG.$r (in $r.wxi, for $n.wxi)"
                progress=1; break 2
            done
        done
    done
    [ "$progress" = 1 ] || { echo "!! cannot resolve: $(echo $missing)" >&2; exit 1; }
done

echo "--- wxi closure clean (${#inclosure[@]} groups) ---"
