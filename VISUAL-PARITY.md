# Visual parity work

User wants native CTC to match PowerShell 6.8.9 one to one.

- [x] Reuse preserved main, parked, settings, and tool-call WPF layouts.
- [x] Match compact/expanded sizes, header, logo, footer, quota bars, and corner behavior.
- [x] Match context summary, active cards, token grids and expandable details.
- [x] Match limits fields, presets, saved values, fixed Save and Back controls.
- [x] Match queue and app settings views.
- [x] Compare actual captures and geometry with isolated legacy fixtures.
- [ ] Install and open the tested release. Keep earlier versions.

C#/.NET10/WPF remains the runtime. Do not edit legacy source. Use STE.
Do not restart Codex or change real context settings for tests.

Checks: 75 core, 33 actual WPF, and 7 preserved-layout checks.
