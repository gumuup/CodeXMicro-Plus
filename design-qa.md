# Design QA — CodeXMicro++ visual changes

## Evidence

- Source visual truth: `/Users/gumu/Downloads/dock/codex.jpg`
- Implementation screenshot: `/Users/gumu/CodeXmicro/DesignQA/codex-mark-implementation.png`
- Focused comparison: `/Users/gumu/CodeXmicro/DesignQA/codex-mark-comparison.png`
- Capture: 876 × 876 px (438 × 438 pt at 2× scale)
- State: light appearance, normal/resting state, bottom-right “Open Codex” key

## Full-view comparison

- The panel frame, grid, key sizing, glow, and surrounding controls remain unchanged.
- The replacement graphic stays centered inside the existing bottom-right key and does not clip or overlap the key boundary.

## Focused comparison

- The implementation uses the supplied purple-blue flower asset rather than an approximation.
- The white `>_` glyph, gradients, blur, and highlight details are preserved from the source.
- The source JPG's edge-connected white canvas was removed; the bundled PNG has a transparent background while preserving the white glyph.
- The asset is scaled proportionally with no visible distortion.

## Fidelity surfaces

- Typography: not applicable beyond the rasterized source glyph; preserved exactly.
- Spacing and alignment: centered and optically balanced within the key.
- Color and effects: inherited directly from the supplied source image.
- Image quality: transparent 821 × 828 PNG, rendered with aspect-fit scaling.
- Copy: unchanged.

## Comparison history

1. Initial implementation used system symbols and visibly differed in stroke weight and rounding.
2. Replaced the approximation with the supplied source asset.
3. Direct JPG use introduced a white square; converted it with edge-connected background removal to preserve the internal white glyph.
4. Final comparison found no actionable P0, P1, or P2 visual defects.

## Findings

- P0: none.
- P1: none.
- P2: none.
- P3: none.

## Hidden-label eye state

- Source reference: `/var/folders/js/2mcqx4m54274cgngs0b4rc2r0000gn/T/codex-clipboard-61727c45-b8f8-41ed-bd6e-06b9af196b55.png`
- Implementation screenshot: `/Users/gumu/CodeXmicro/DesignQA/eye-hidden-slash.png`
- Side-by-side comparison: `/Users/gumu/CodeXmicro/DesignQA/eye-hidden-comparison.png`
- State: light appearance, key labels hidden, transient “已隐藏按键标注” feedback visible.
- Interaction verification: the button changes from `eye.fill` / “隐藏按键标注” to `eye.slash.fill` / “显示按键标注” after a real click.
- Visual verification: the slash is legible at the existing 18 pt icon size, remains centered inside the black circular sensor, and does not disturb the surrounding layout.
- Findings: no actionable P0, P1, or P2 defects.

## Smaller bottom-right Codex mark

- Source reference: `/var/folders/js/2mcqx4m54274cgngs0b4rc2r0000gn/T/codex-clipboard-a4496027-ce9c-41d2-8850-45ebe038314f.png`
- Implementation screenshot: `/Users/gumu/CodeXmicro/DesignQA/codex-mark-smaller.png`
- Side-by-side comparison: `/Users/gumu/CodeXmicro/DesignQA/codex-mark-smaller-comparison.png`
- State: light appearance, normal panel state, transient task feedback visible.
- The mark scale changed from `0.74` to `0.63`, reducing its visible size by about 15%.
- The button frame, hit target, purple glow, source artwork, aspect ratio, and center alignment remain unchanged.
- The resulting inset is visibly larger on every side, with no clipping or distortion.
- Findings: no actionable P0, P1, or P2 defects.

## FAST enabled yellow glow

- Source reference: `/var/folders/js/2mcqx4m54274cgngs0b4rc2r0000gn/T/codex-clipboard-454f5f69-f400-42c5-8290-08d471d9289e.png`
- Implementation screenshot: `/Users/gumu/CodeXmicro/DesignQA/fast-yellow-glow.png`
- Side-by-side comparison: `/Users/gumu/CodeXmicro/DesignQA/fast-yellow-glow-comparison.png`
- State: light appearance, FAST mode enabled.
- The yellow light originates beneath the lightning glyph and remains contained within the FAST key.
- The glow does not reduce the black glyph contrast, obscure the FAST label, or affect neighboring keys.
- FAST state changes only after a successful automation command and is preserved across app relaunches.
- The accessibility label switches between “启用 Fast 模式” and “关闭 Fast 模式” with the state.
- Findings: no actionable P0, P1, or P2 defects.

## Codex toolbox popover

- Source visual truth: `/var/folders/js/2mcqx4m54274cgngs0b4rc2r0000gn/T/codex-clipboard-96c501f5-4306-4e82-a61b-055f93508cb1.png`
- Implementation screenshot: `/var/folders/js/2mcqx4m54274cgngs0b4rc2r0000gn/T/com.openai.sky.CUAService/Codex Micro Screenshot 2026-07-17 at 3.03.54 AM.jpeg`
- Full-view comparison: `/tmp/codex-toolbox-comparison.png`
- Viewport: 640 × 520 pt toolbox popover beside the 438 × 438 pt floating keyboard.
- State: light appearance, toolbox open, All category selected.
- Interaction verification: opened the toolbox from the new button immediately left of Settings; selected the Git category and observed the catalog narrow from 52 to 7 actions; searched for `PR` and observed the result narrow to Create PR and Review PR.

### Full-view comparison

- The implementation preserves the source hierarchy of title, search, keycap catalog, and compact icon-led actions.
- The implementation intentionally uses four wider columns rather than the source's six square columns so Chinese titles and the action type remain legible at native macOS popover size.
- The new toolbox trigger is visibly located immediately left of the gear button and does not disturb the existing 4 × 4 keyboard grid.

### Focused comparison

- A separate crop was not required because the combined 920 px-high comparison keeps the header, search field, categories, keycaps, short codes, and legend readable in one view.
- SF Symbols are used consistently for UI icons; no placeholder art, emoji, or handcrafted SVG replacements were introduced.

### Fidelity surfaces

- Typography: native system text keeps the existing app's rounded, compact macOS hierarchy; labels remain legible without wrapping in the tested state.
- Spacing and layout: 18 pt outer padding, 10 pt grid gaps, 92 pt key cards, and the persistent scroll indicator produce a balanced, scannable grid with no clipping.
- Colors and tokens: semantic foregrounds and materials adapt to macOS appearance; blue, purple, and orange consistently distinguish shortcuts, destinations, and workflows.
- Image quality and assets: all UI glyphs are native SF Symbols and remain sharp at Retina scale.
- Copy: 52 actions use Chinese titles plus familiar official keycap abbreviations such as FAST, APPR, REJ, FORK, DIFF, TERM, BRCH, PR, OAI, TIME, MIND+, and YEET.

### Comparison history

1. The source reference established the searchable keycap-grid pattern and common Codex action vocabulary.
2. The first rendered implementation fit the full action catalog, but retained wider cards as an intentional readability improvement rather than forcing the source's six-column density.
3. Runtime inspection confirmed the button placement, 52-action catalog, Git category filter, and PR search state with no actionable P0, P1, or P2 visual issues.

### Findings

- P0: none.
- P1: none.
- P2: none.
- P3: the translucent floating-panel capture can show minor screenshot compositing softness; the live controls remain sharp and accessible.

## Final result

passed
