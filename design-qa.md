# Room and source cards — native UI review, 0.5.4

Reference: the user's 1280 × 960 card-layout image in this conversation, with the subsequently requested removals. This is a similar-style native implementation, not a pixel-identical web clone.

Evidence:
- iPad: `/workspace/artifacts/TogetherPlayer-0.5.4-房间界面与弹幕修复/iPad验证/房间卡片横屏.png` and `本机影片卡片竖屏.png`.
- Android: `/workspace/artifacts/TogetherPlayer-0.5.4-房间界面与弹幕修复/Android验证/android-delivery/screenshots/02-room-settings.png`.
- iPad captures: 2420 × 1668 landscape, 1668 × 2420 portrait after EXIF orientation normalization; native 2× screen density. Android: 1080 × 2400, native phone density. CSS viewport and browser console do not apply to these SwiftUI/Android apps.
- The iPad evidence is the settings-sheet presentation of RoomScreen; the reference uses the full-page entry. The sheet width and scroll position differ intentionally. Reviewed card styling and action affordances rather than claiming a matched full-page pixel comparison.

## Findings and comparison history

- Earlier Android capture had an empty icon tile in the source header (P2). Replaced its empty existing drawable with the existing visible play icon. The final Android 02-room-settings screenshot shows the white icon and the full native suite passes.
- No remaining P0/P1/P2 findings in the captured settings presentations. Primary source actions are visible, cards separate concerns, long labels remain readable, and actions have a distinct background and native touch targets.

## Required surfaces

- Typography: native system fonts, semibold button labels and bold section titles. The longer compatible-import label wraps within its button at narrower sheet widths instead of clipping. Fields, status and helper text have separate hierarchy.
- Spacing: consistent card padding, rounded corners, button targets of at least 44 pt on iPad / 48 dp on Android. The iPad local-file and compatible-copy choices adapt between horizontal and vertical layouts.
- Color: dark navy cards, blue primary actions, purple film/device icons, secondary helper text and red destructive labels follow the supplied direction.
- Assets: genuine SF Symbols on iPad and existing Android vector icons. The reference has no custom photography or illustration assets to generate.
- Copy: requested Apple test clip, friend-keeps-online local replacement, quality diagnostics and connection/test entries are removed. Authorization, file selection, compatible copy, source cleanup, local alternative link, profile and timing remain.

## Interaction checks

Native tests exercise removed-entry absence, minimum action height, file-picker return, subtitle import, fullscreen controls and settings retention. Android also exercises link-section expansion, authorization opening, missing-browser fallback and clipboard copying. iPad core tests check actual rendered pixels for final Chinese glyphs at 14/24/44 pt and 2×/3×, including mixed fonts, emoji and long text.

## Remaining test gaps

The full-page iPad tab has not been separately captured in this run. Its RoomScreen component is shared with the verified sheet. Physical-device font rendering and real network/account behavior are not established by these simulator screenshots. No new microphone recognition changes were made in this release.

final result: passed
