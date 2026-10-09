#!/bin/bash
# List every shared library an ELF in a built system/ asks for (DT_NEEDED) that exists
# in none of the library directories of its own bitness.
#
#   tools/missing-libs.sh out/target/product/ASUS_P00I/system
#
# Run it after adding blobs to proprietary-files.txt: a vendor library whose own
# dependency was not extracted fails only at load time, often silently and far from
# the cause. This is how the first boot to reach system_server was explained in one go:
# qseecomd links libdrmfs, libdrmfs links libdiag, and libdiag was not in the list.
#
# What it cannot see: libraries loaded with dlopen(). For a daemon, read its strings
# for ".so" names too (qseecomd dlopen()s librpmb, libssd, libGPreqcancel, libqisl...).
S=${1:?usage: $0 <path to out/target/product/<device>/system>}
cd "$S" || exit 1
find . -type f \( -path './bin/*' -o -path './vendor/bin/*' -o -path './lib*' -o -path './vendor/lib*' -o -path './xbin/*' \) 2>/dev/null |
while read -r f; do
    case $(head -c 5 "$f" | od -An -tx1 | tr -d ' \n') in
        7f454c4601) dirs="lib vendor/lib lib/hw vendor/lib/hw" ;;
        7f454c4602) dirs="lib64 vendor/lib64 lib64/hw vendor/lib64/hw" ;;
        *) continue ;;
    esac
    for n in $(readelf -d "$f" 2>/dev/null | sed -n 's/.*Shared library: \[\(.*\)\]/\1/p'); do
        found=
        for d in $dirs; do [ -e "$d/$n" ] && { found=1; break; }; done
        [ -z "$found" ] && echo "$n <- ${f#./}"
    done
done | sort
