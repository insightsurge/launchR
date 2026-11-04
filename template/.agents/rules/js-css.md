# JavaScript and CSS

Only for packages with JavaScript or CSS in `inst/`.

- Keep it plain and readable, with no build step unless the package already has one.
- Ship every file the package needs inside it; never load from a CDN. Keep a third-party file's licence, and note
  where it came from.
- Biome formats and lints it, with the settings in `biome.json`.
- **Accessibility:** meaning never rests on colour alone, everything works from the keyboard, controls have labels,
  and motion honours `prefers-reduced-motion`.
