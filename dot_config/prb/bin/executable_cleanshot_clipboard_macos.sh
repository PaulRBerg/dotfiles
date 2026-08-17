#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat >&2 <<'EOF'
Usage:
  cleanshot_clipboard_macos.sh observe
  cleanshot_clipboard_macos.sh copy-if-current <token> <image-path>
EOF
  exit 2
}

case "${1:-}" in
observe)
  (($# == 1)) || usage
  ;;
copy-if-current)
  (($# == 3)) || usage
  [[ "$2" =~ ^[0-9]+$ ]] || usage
  [[ -f "$3" ]] || {
    printf 'screenshot not found: %s\n' "$3" >&2
    exit 1
  }
  case "${3##*.}" in
  jpg | png) ;;
  *)
    printf 'unsupported screenshot extension: %s\n' "$3" >&2
    exit 1
    ;;
  esac
  ;;
*) usage ;;
esac

exec /usr/bin/osascript -l JavaScript - "$1" "${CLEANSHOT_CLIPBOARD_PASTEBOARD_NAME:-}" "${@:2}" <<'JXA'
ObjC.import("AppKit");
ObjC.import("Foundation");

function changeCount(pasteboard) {
  return Number(ObjC.unwrap(pasteboard.changeCount));
}

function openPasteboard(name) {
  if (name.length > 0) {
    return $.NSPasteboard.pasteboardWithName(name);
  }
  return $.NSPasteboard.generalPasteboard;
}

function run(argv) {
  const command = argv[0];
  const pasteboard = openPasteboard(argv[1]);

  if (command === "observe") {
    return String(changeCount(pasteboard));
  }

  const expectedChangeCount = Number(argv[2]);
  const imagePath = argv[3];

  if (changeCount(pasteboard) !== expectedChangeCount) {
    return "changed";
  }

  const imageURL = $.NSURL.fileURLWithPath(imagePath);
  const imageData = $.NSData.dataWithContentsOfURL(imageURL);
  const image = $.NSImage.alloc.initWithContentsOfURL(imageURL);

  if (imageData.js === undefined || image.js === undefined) {
    throw new Error(`could not read screenshot: ${imagePath}`);
  }

  const extension = ObjC.unwrap(imageURL.pathExtension).toLowerCase();
  const imageType = extension === "png" ? $.NSPasteboardTypePNG : $("public.jpeg");
  const item = $.NSPasteboardItem.alloc.init;

  if (!item.setStringForType(imageURL.absoluteString, $.NSPasteboardTypeFileURL)) {
    throw new Error("could not add screenshot file URL to pasteboard item");
  }
  if (!item.setDataForType(imageData, imageType)) {
    throw new Error("could not add screenshot data to pasteboard item");
  }

  const tiffData = image.TIFFRepresentation;
  if (tiffData.js !== undefined && !item.setDataForType(tiffData, $.NSPasteboardTypeTIFF)) {
    throw new Error("could not add TIFF data to pasteboard item");
  }

  if (changeCount(pasteboard) !== expectedChangeCount) {
    return "changed";
  }

  const ownedChangeCount = Number(ObjC.unwrap(pasteboard.clearContents));
  if (!pasteboard.writeObjects($.NSArray.arrayWithObject(item))) {
    throw new Error("could not write screenshot to pasteboard");
  }

  return `copied ${ownedChangeCount}`;
}
JXA
