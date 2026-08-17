#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

setup() {
  [[ "$(uname -s)" == "Darwin" ]] || skip "macOS pasteboard integration test"

  export CLEANSHOT_CLIPBOARD_PASTEBOARD_NAME="local.cleanshot-clipboard-test.$$.$BATS_TEST_NUMBER.$RANDOM"
  export HELPER="$BATS_TEST_DIRNAME/../dot_config/prb/bin/executable_cleanshot_clipboard_macos.sh"
  export IMAGE="$BATS_TEST_TMPDIR/2026-08-17_12-34-56--code--clipboard-fix.png"
  export JPEG_IMAGE="$BATS_TEST_TMPDIR/2026-08-17_12-34-57--code--clipboard-fix.jpg"

  printf '%s' 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=' |
    /usr/bin/base64 -D >"$IMAGE"
  /usr/bin/sips -s format jpeg "$IMAGE" --out "$JPEG_IMAGE" >/dev/null
}

teardown() {
  [[ -n "${CLEANSHOT_CLIPBOARD_PASTEBOARD_NAME:-}" ]] || return 0
  /usr/bin/osascript -l JavaScript - "$CLEANSHOT_CLIPBOARD_PASTEBOARD_NAME" >/dev/null <<'JXA' || true
ObjC.import("AppKit");

function run(argv) {
  $.NSPasteboard.pasteboardWithName(argv[0]).releaseGlobally;
}
JXA
}

seed_text() {
  local text="$1"

  /usr/bin/osascript -l JavaScript - "$CLEANSHOT_CLIPBOARD_PASTEBOARD_NAME" "$text" <<'JXA'
ObjC.import("AppKit");

function run(argv) {
  const pasteboard = $.NSPasteboard.pasteboardWithName(argv[0]);
  pasteboard.clearContents;
  if (!pasteboard.setStringForType(argv[1], $.NSPasteboardTypeString)) {
    throw new Error("could not seed named pasteboard");
  }
}
JXA
}

inspect_pasteboard() {
  /usr/bin/osascript -l JavaScript - "$CLEANSHOT_CLIPBOARD_PASTEBOARD_NAME" <<'JXA'
ObjC.import("AppKit");
ObjC.import("Foundation");

function run(argv) {
  const pasteboard = $.NSPasteboard.pasteboardWithName(argv[0]);
  const items = pasteboard.pasteboardItems;
  if (Number(ObjC.unwrap(items.count)) !== 1) {
    throw new Error("expected one pasteboard item");
  }

  const item = items.objectAtIndex(0);
  const fileURL = ObjC.unwrap(item.stringForType($.NSPasteboardTypeFileURL));
  const filePath = fileURL ? ObjC.unwrap($.NSURL.URLWithString(fileURL).path) : null;

  return JSON.stringify({
    types: ObjC.deepUnwrap(item.types),
    filePath,
    text: ObjC.unwrap(item.stringForType($.NSPasteboardTypeString)),
  });
}
JXA
}

@test "copies the final file URL and image representations" {
  seed_text 'clipboard before screenshot'
  token="$(bash "$HELPER" observe)"

  run bash "$HELPER" copy-if-current "$token" "$IMAGE"

  [[ "$status" -eq 0 ]]
  [[ "$output" =~ ^copied\ [0-9]+$ ]]
  metadata="$(inspect_pasteboard)"
  [[ "$(jq -r '.filePath' <<<"$metadata")" == "$IMAGE" ]]
  jq -e '
    (.types | index("public.file-url")) != null
    and (.types | index("public.png")) != null
    and (.types | index("public.tiff")) != null
  ' <<<"$metadata" >/dev/null
  copied_token="${output#copied }"
  [[ "$(bash "$HELPER" observe)" == "$copied_token" ]]
}

@test "copies JPEG data with its native pasteboard type" {
  seed_text 'clipboard before screenshot'
  token="$(bash "$HELPER" observe)"

  run bash "$HELPER" copy-if-current "$token" "$JPEG_IMAGE"

  [[ "$status" -eq 0 ]]
  [[ "$output" =~ ^copied\ [0-9]+$ ]]
  metadata="$(inspect_pasteboard)"
  [[ "$(jq -r '.filePath' <<<"$metadata")" == "$JPEG_IMAGE" ]]
  jq -e '
    (.types | index("public.file-url")) != null
    and (.types | index("public.jpeg")) != null
    and (.types | index("public.tiff")) != null
  ' <<<"$metadata" >/dev/null
}

@test "leaves newer clipboard content untouched" {
  seed_text 'clipboard before screenshot'
  token="$(bash "$HELPER" observe)"
  seed_text 'newer clipboard content'

  run bash "$HELPER" copy-if-current "$token" "$IMAGE"

  [[ "$status" -eq 0 ]]
  [[ "$output" == 'changed' ]]
  metadata="$(inspect_pasteboard)"
  [[ "$(jq -r '.text' <<<"$metadata")" == 'newer clipboard content' ]]
  jq -e '.types == ["public.utf8-plain-text"]' <<<"$metadata" >/dev/null
}
