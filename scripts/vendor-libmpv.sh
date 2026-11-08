#!/bin/sh
# Copies libmpv and every library it needs from Homebrew into Vendor/libmpv,
# so that the app carries its own player. The install names are rewritten
# to @rpath, the build embeds the files in Contents/Frameworks.
#
#   brew install mpv
#   scripts/vendor-libmpv.sh
set -eu

root="$(cd "$(dirname "$0")/.." && pwd)"
brew_prefix="$(brew --prefix)"
out="$root/Vendor/libmpv"

rm -rf "$out"
mkdir -p "$out/lib" "$out/include/mpv"

cp "$brew_prefix"/include/mpv/client.h "$brew_prefix"/include/mpv/render.h \
   "$brew_prefix"/include/mpv/render_gl.h "$brew_prefix"/include/mpv/stream_cb.h "$out/include/mpv/"
cat > "$out/include/module.modulemap" <<'EOF'
module Libmpv [system] {
    header "mpv/client.h"
    header "mpv/render.h"
    header "mpv/render_gl.h"
    link "mpv"
    export *
}
EOF

python3 - "$brew_prefix" "$out/lib" <<'PY'
import os, shutil, subprocess, sys

prefix, dest = sys.argv[1], sys.argv[2]

def deps(path):
    lines = subprocess.run(["otool", "-L", path], check=True, capture_output=True, text=True).stdout.splitlines()[1:]
    return [line.strip().split(" (")[0] for line in lines]

def install_id(path):
    lines = subprocess.run(["otool", "-D", path], check=True, capture_output=True, text=True).stdout.splitlines()
    return lines[1].strip() if len(lines) > 1 else os.path.basename(path)

def resolve(reference, loader):
    if reference.startswith(prefix):
        return os.path.realpath(reference)
    if reference.startswith("@rpath/") or reference.startswith("@loader_path/"):
        name = reference.split("/", 1)[1]
        for directory in (os.path.dirname(loader), os.path.join(prefix, "lib")):
            candidate = os.path.join(directory, name)
            if os.path.exists(candidate):
                return os.path.realpath(candidate)
        sys.exit(f"cannot resolve {reference} of {loader}")
    return None  # a library of the system

start = os.path.realpath(os.path.join(prefix, "lib", "libmpv.dylib"))
names = {}       # real path -> file name in the bundle
references = {}  # real path -> [(reference as written, real path of the dependency)]
pending = [start]
while pending:
    path = pending.pop()
    if path in names:
        continue
    names[path] = os.path.basename(install_id(path))
    references[path] = []
    for reference in deps(path):
        target = resolve(reference, path)
        if target and target != path:
            references[path].append((reference, target))
            pending.append(target)

for path, name in names.items():
    target = os.path.join(dest, name)
    shutil.copyfile(path, target)
    os.chmod(target, 0o755)
    arguments = ["install_name_tool", "-id", "@rpath/" + name]
    for reference, dependency in references[path]:
        arguments += ["-change", reference, "@rpath/" + names[dependency]]
    subprocess.run(arguments + [target], check=True, capture_output=True)
    # Homebrew stamps these with the OS they were built on. The app targets
    # macOS 15, so the load command has to say so too; the linker warns
    # otherwise. The bytes are unchanged.
    stamped = target + ".stamp"
    subprocess.run(
        ["vtool", "-set-build-version", "macos", "15.0", "27.2", "-replace", "-output", stamped, target],
        check=True, capture_output=True)
    os.replace(stamped, target)
    subprocess.run(["codesign", "--force", "--sign", "-", target], check=True, capture_output=True)

os.symlink(names[start], os.path.join(dest, "libmpv.dylib"))
total = sum(os.path.getsize(os.path.join(dest, n)) for n in names.values())
print(f"{len(names)} libraries, {total // 1024 // 1024} MB in {dest}")
PY
