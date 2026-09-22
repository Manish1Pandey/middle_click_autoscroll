/// Non-web implementation: there is no browser to guard against, and desktop
/// embedders report leaving the window with pointer-remove events, so this is
/// a no-op that returns no handle.
Object? installBrowserGuard({
  required bool preventDefaults,
  required void Function() onPointerLeftView,
}) => null;

/// Non-web implementation: nothing to remove.
void uninstallBrowserGuard(Object? handle) {}
