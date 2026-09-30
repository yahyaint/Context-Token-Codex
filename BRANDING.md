# Context-Token Codex (CTC)

Product name: **Context-Token Codex**. Logo: a simple lowercase **ctc** wordmark in **Segoe UI Semibold**, matching the app's Windows UI typeface.

Five base colors, selected by Yahya Nabil:

| Role | Color | HEX |
|---|---|---|
| Main background | Ink Black | #0D1B2A |
| Cards and controls | Prussian Blue | #1B263B |
| Borders and tracks | Dusk Blue | #415A77 |
| Accents and focus | Dusty Denim | #778DA9 |
| Primary text | Alabaster Grey | #E0E1DD |

These colors replace the earlier charcoal/ivory/amber palette and supersede the original three-color restriction. Historical Nord inspiration remains acknowledged; the current palette is user-selected. Background transparency and antialiasing can produce blended colors. Text and controls remain opaque. Navigation uses selected fills instead of dimming usable tabs. Scrollbars, expanders and progress bars use the shared palette.

Ivory lettering sits on an ink-blue rounded square. Build/build.ps1 outlines the installed Windows font and renders the mark at 16, 24, 32, 48, 64, 128 and 256 pixels. The same icon appears in the widget, tray, taskbar, installer and shortcuts. Build/ctc-logo.png provides a large preview. The font is supplied by Windows; no font file or third-party logo is bundled. The earlier interlocking mark remains in previous release archives.

Controls use a shared centered content template and a 28-pixel minimum target height. The Limits tab embeds the context editor in the widget. Combo boxes use the same palette, including their dropdown. Compact mode reserves enough vertical space for navigation and the footer.

Existing executable names, settings paths and process coordination IDs remain stable for upgrade compatibility. The public name and shortcut labels use Context-Token Codex. Windows launchers remain unsigned.

## Display and shortcut icons

The taskbar artwork is the source for every current logo.
The widget and setup select an icon frame for the display scale. They use high-quality image scaling.
Desktop, Start Menu, and startup shortcuts use ContextWidget.exe,0.
The installer notifies Explorer when it changes a shortcut. It does not clear the global icon cache.
Tests compare the encoded image resources in both launchers with Context.ico.
Earlier logos remain only in historical release files and version backups.
