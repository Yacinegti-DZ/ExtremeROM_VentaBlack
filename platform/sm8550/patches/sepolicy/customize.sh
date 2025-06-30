SKIPUNZIP=1

# [
APPLY_PATCH()
{
    local PATCH
    local OUT

    cd "$WORK_DIR/system_ext/etc/selinux"
    PATCH="$SRC_DIR/platform/sm8550/patches/sepolicy/$1"
    OUT="$(patch -p1 -s -t -N --dry-run < "$PATCH")" \
        || echo "$OUT" | grep -q "Skipping patch" || false
    patch -p1 -s -t -N --no-backup-if-mismatch < "$PATCH" &> /dev/null || true
    cd - &> /dev/null
}
# ]

APPLY_PATCH "patch/0001-Patch-sepolicy.patch"