ObjC.import("CoreGraphics");

function run(argv) {
  const pid = Number(argv[0]);
  const onScreenOnly = 1;
  const windows = ObjC.deepUnwrap(ObjC.castRefToObject($.CGWindowListCopyWindowInfo(onScreenOnly, 0))) || [];
  return windows
    .filter((window) => window.kCGWindowOwnerPID === pid)
    .map((window) => {
      const bounds = window.kCGWindowBounds;
      return [window.kCGWindowNumber, window.kCGWindowLayer, bounds.X, bounds.Y, bounds.Width, bounds.Height].join(" ");
    })
    .join("\n");
}
