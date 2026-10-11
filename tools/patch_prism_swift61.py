#!/usr/bin/env python3
"""Split a seed expression that exceeds Swift 6.1's type-checker budget.

Only applied to the pinned dependency after package resolution. Media selection titles also retain source metadata; codec routing is unchanged.
"""
import pathlib
import subprocess
import sys

PIN = '36c841bc4c8e91fb83532860d2f2f04957d8c0e5'
root = pathlib.Path(sys.argv[1])
actual = subprocess.check_output(['git', '-C', str(root), 'rev-parse', 'HEAD'], text=True).strip()
if actual != PIN:
    raise SystemExit('PrismCore pin mismatch; refusing an unreviewed patch')
file = root / 'Sources/PrismCore/Fuzz/FuzzCorpus.swift'
before = '''        let rbsp: [UInt8] = [0x80, UInt8(structureOfPictures.count)] + structureOfPictures
            + [0xFF, 0x05, UInt8(extendedType.count)] + extendedType
            + [0x05, UInt8(banner.count)] + banner
            + [0x04, UInt8(caption.count)] + caption
            + [0x04, UInt8(hdr10PlusT35Payload.count)] + hdr10PlusT35Payload
            + [0x80]'''
after = '''        // Swift 6.1 times out inferring the chained array additions in the seed.
        var rbsp: [UInt8] = [0x80, UInt8(structureOfPictures.count)]
        rbsp.append(contentsOf: structureOfPictures)
        rbsp.append(contentsOf: [0xFF, 0x05, UInt8(extendedType.count)])
        rbsp.append(contentsOf: extendedType)
        rbsp.append(contentsOf: [0x05, UInt8(banner.count)])
        rbsp.append(contentsOf: banner)
        rbsp.append(contentsOf: [0x04, UInt8(caption.count)])
        rbsp.append(contentsOf: caption)
        rbsp.append(contentsOf: [0x04, UInt8(hdr10PlusT35Payload.count)])
        rbsp.append(contentsOf: hdr10PlusT35Payload)
        rbsp.append(0x80)'''
source = file.read_text()
if source.count(before) != 1:
    raise SystemExit('Expected seed expression missing; refusing an ambiguous patch')
file.chmod(file.stat().st_mode | 0o200)
file.write_text(source.replace(before, after))
print('Applied equivalent array-construction patch to pinned PrismCore FuzzCorpus.swift')

# Keep source codec/layout in each rendition NAME, including bridged audio.
file = root / 'Sources/PrismCore/Remux/AudioRenditionWriter.swift'
source = file.read_text()
start = source.index('    private var baseRenditionName: String {')
end = source.index('    /// The RFC 6381', start)
source = source[:start] + r'''    private var baseRenditionName: String {
        let languageName = track.language.flatMap { Locale.current.localizedString(forLanguageCode: $0) }
        let title = track.title.flatMap { $0.isEmpty ? nil : $0 } ?? languageName ?? "音轨"
        let baseCodec = track.codecName.uppercased()
        let profile = track.profileName.flatMap { $0.isEmpty ? nil : $0 }
        let codec = profile.map { $0.uppercased().contains(baseCodec) ? $0 : "\(baseCodec) (\($0))" } ?? baseCodec
        let layout = track.channelLayoutDescription.flatMap { $0.isEmpty ? nil : $0 } ?? "\(track.channelCount)声道"
        let delivery: String
        switch route.mode {
        case .streamCopy: delivery = ""
        case .bridge, .boost: delivery = " → " + AudioBridge.defaultTargetCodecName.uppercased()
        }
        return "\(title) [\(codec) · \(layout) · 源音轨 \(ordinal + 1)]\(delivery)"
    }

''' + source[end:]
file.chmod(file.stat().st_mode | 0o200)
file.write_text(source)
# The upstream subtitle title filter drops CHS/CHT and region labels.
file = root / 'Sources/PrismCore/Subtitles/SubtitleRenditionSet.swift'
source = file.read_text()
before = r'case (let name?, let t?) where describes: return "\(name) (\(t))"'
after = r'case (let name?, let t?) where !t.isEmpty: return "\(name) (\(t))"'
if source.count(before) != 1:
    raise SystemExit('Expected subtitle title expression missing')
file.chmod(file.stat().st_mode | 0o200)
file.write_text(source.replace(before, after).replace('        let describes = title.map { t in kindWords.contains { t.lowercased().contains($0) } } ?? false', '').replace('        let kindWords = ["sdh", "cc", "hearing", "forced", "signs", "songs", "commentary"]', ''))
print('Preserved codec/layout and original subtitle titles in HLS selection names')
