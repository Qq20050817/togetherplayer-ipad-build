import Foundation
import Network

// Serves only an immutable public reference playlist on device loopback.
// Video/audio requests go directly to Apple's CDN, never through this listener.
@MainActor final class AtmosReferenceServer {
 private var listener: NWListener?
 private var readyURL: URL?
 private var waiting: [CheckedContinuation<URL,Error>]=[]
 private let manifest: Data
 init() {manifest=Data(Self.referenceManifest.utf8)}
 private static let referenceManifest="""
#EXTM3U
#EXT-X-VERSION:6
#EXT-X-INDEPENDENT-SEGMENTS
#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="ec3-48-768",NAME="English",LANGUAGE="en-US",AUTOSELECT=YES,DEFAULT=YES,CHANNELS="16/JOC",URI="https://devstreaming-cdn.apple.com/videos/streaming/examples/adv_dv_atmos/Job932393e2-1e4f-4fdb-ab59-0d201f752656-107660254-Transcode_audio_full_en_atmos_0_1-en_audio/prog_index.m3u8"
#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="ec3-48-768",NAME="English (DVS)",LANGUAGE="en-US",AUTOSELECT=YES,DEFAULT=NO,CHANNELS="16/JOC",CHARACTERISTICS="public.accessibility.describes-video",URI="https://devstreaming-cdn.apple.com/videos/streaming/examples/adv_dv_atmos/Jobca103e1c-625a-4cbc-ad9f-ffd8c6b760de-107673271-Transcode_dvs_full_en_atmos_0_1-en_audio/prog_index.m3u8"
#EXT-X-MEDIA:TYPE=SUBTITLES,GROUP-ID="subtitles",NAME="English (Forced)",LANGUAGE="en-US",AUTOSELECT=YES,FORCED=YES,DEFAULT=NO,URI="https://devstreaming-cdn.apple.com/videos/streaming/examples/adv_dv_atmos/Jobe9ecaff1-8802-4a35-a411-5d83d0d368e0-107675778-Convertforced_subtitles_vttv2_en_any-en/prog_index.m3u8"
#EXT-X-MEDIA:TYPE=SUBTITLES,GROUP-ID="subtitles",NAME="Italiano (SDH)",LANGUAGE="it",AUTOSELECT=YES,FORCED=NO,DEFAULT=NO,CHARACTERISTICS="public.accessibility.transcribes-spoken-dialog,public.accessibility.describes-music-and-sound",URI="https://devstreaming-cdn.apple.com/videos/streaming/examples/adv_dv_atmos/Jobe9ecaff1-8802-4a35-a411-5d83d0d368e0-107675778-Convertsdh_vttv2_it_any-it/prog_index.m3u8"
#EXT-X-MEDIA:TYPE=SUBTITLES,GROUP-ID="subtitles",NAME="中文（繁體） (SDH)",LANGUAGE="cmn-Hant",AUTOSELECT=YES,FORCED=NO,DEFAULT=NO,CHARACTERISTICS="public.accessibility.transcribes-spoken-dialog,public.accessibility.describes-music-and-sound",URI="https://devstreaming-cdn.apple.com/videos/streaming/examples/adv_dv_atmos/Jobe9ecaff1-8802-4a35-a411-5d83d0d368e0-107675778-Convertsdh_vttv2_cmn-Hant_any-cmn-Hant/prog_index.m3u8"
#EXT-X-MEDIA:TYPE=SUBTITLES,GROUP-ID="subtitles",NAME="中文（简体） (SDH)",LANGUAGE="cmn-Hans",AUTOSELECT=YES,FORCED=NO,DEFAULT=NO,CHARACTERISTICS="public.accessibility.transcribes-spoken-dialog,public.accessibility.describes-music-and-sound",URI="https://devstreaming-cdn.apple.com/videos/streaming/examples/adv_dv_atmos/Jobe9ecaff1-8802-4a35-a411-5d83d0d368e0-107675778-Convertsdh_vttv2_cmn-Hans_any-cmn-Hans/prog_index.m3u8"
#EXT-X-MEDIA:TYPE=SUBTITLES,GROUP-ID="subtitles",NAME="English (SDH)",LANGUAGE="en-US",AUTOSELECT=YES,FORCED=NO,DEFAULT=NO,CHARACTERISTICS="public.accessibility.transcribes-spoken-dialog,public.accessibility.describes-music-and-sound",URI="https://devstreaming-cdn.apple.com/videos/streaming/examples/adv_dv_atmos/Job7fd5dc08-5172-4910-b0e3-195f63fe6ef5-107660331-Convertsdh_vttv2_en_any-en/prog_index.m3u8"
#EXT-X-MEDIA:TYPE=SUBTITLES,GROUP-ID="subtitles",NAME="Italiano",LANGUAGE="it",AUTOSELECT=YES,FORCED=NO,DEFAULT=NO,URI="https://devstreaming-cdn.apple.com/videos/streaming/examples/adv_dv_atmos/Jobe9ecaff1-8802-4a35-a411-5d83d0d368e0-107675778-Convertsubtitles_vttv2_it_any-it/prog_index.m3u8"
#EXT-X-MEDIA:TYPE=SUBTITLES,GROUP-ID="subtitles",NAME="Français (France)",LANGUAGE="fr-FR",AUTOSELECT=YES,FORCED=NO,DEFAULT=NO,URI="https://devstreaming-cdn.apple.com/videos/streaming/examples/adv_dv_atmos/Jobe9ecaff1-8802-4a35-a411-5d83d0d368e0-107675778-Convertsubtitles_vttv2_fr-FR_any-fr-FR/prog_index.m3u8"
#EXT-X-MEDIA:TYPE=SUBTITLES,GROUP-ID="subtitles",NAME="Français (Canada)",LANGUAGE="fr-CA",AUTOSELECT=YES,FORCED=NO,DEFAULT=NO,URI="https://devstreaming-cdn.apple.com/videos/streaming/examples/adv_dv_atmos/Jobe9ecaff1-8802-4a35-a411-5d83d0d368e0-107675778-Convertsubtitles_vttv2_fr-CA_any-fr-CA/prog_index.m3u8"
#EXT-X-MEDIA:TYPE=SUBTITLES,GROUP-ID="subtitles",NAME="Español (España)",LANGUAGE="es-ES",AUTOSELECT=YES,FORCED=NO,DEFAULT=NO,URI="https://devstreaming-cdn.apple.com/videos/streaming/examples/adv_dv_atmos/Jobe9ecaff1-8802-4a35-a411-5d83d0d368e0-107675778-Convertsubtitles_vttv2_es-ES_any-es-ES/prog_index.m3u8"
#EXT-X-MEDIA:TYPE=SUBTITLES,GROUP-ID="subtitles",NAME="Español (Latinoamérica)",LANGUAGE="es-419",AUTOSELECT=YES,FORCED=NO,DEFAULT=NO,URI="https://devstreaming-cdn.apple.com/videos/streaming/examples/adv_dv_atmos/Jobe9ecaff1-8802-4a35-a411-5d83d0d368e0-107675778-Convertsubtitles_vttv2_es-419_any-es-419/prog_index.m3u8"
#EXT-X-MEDIA:TYPE=SUBTITLES,GROUP-ID="subtitles",NAME="中文（繁體）",LANGUAGE="cmn-Hant",AUTOSELECT=YES,FORCED=NO,DEFAULT=NO,URI="https://devstreaming-cdn.apple.com/videos/streaming/examples/adv_dv_atmos/Jobe9ecaff1-8802-4a35-a411-5d83d0d368e0-107675778-Convertsubtitles_vttv2_cmn-Hant_any-cmn-Hant/prog_index.m3u8"
#EXT-X-MEDIA:TYPE=SUBTITLES,GROUP-ID="subtitles",NAME="中文（简体）",LANGUAGE="cmn-Hans",AUTOSELECT=YES,FORCED=NO,DEFAULT=NO,URI="https://devstreaming-cdn.apple.com/videos/streaming/examples/adv_dv_atmos/Jobe9ecaff1-8802-4a35-a411-5d83d0d368e0-107675778-Convertsubtitles_vttv2_cmn-Hans_any-cmn-Hans/prog_index.m3u8"
#EXT-X-MEDIA:TYPE=SUBTITLES,GROUP-ID="subtitles",NAME="English",LANGUAGE="en-US",AUTOSELECT=YES,FORCED=NO,DEFAULT=YES,URI="https://devstreaming-cdn.apple.com/videos/streaming/examples/adv_dv_atmos/Job932393e2-1e4f-4fdb-ab59-0d201f752656-107660254-Convertsubtitles_vttv2_en_any-en/prog_index.m3u8"
#EXT-X-MEDIA:TYPE=CLOSED-CAPTIONS,GROUP-ID="cc",LANGUAGE="en",NAME="English",DEFAULT=YES,AUTOSELECT=YES,INSTREAM-ID="CC1"
#EXT-X-I-FRAME-STREAM-INF:AVERAGE-BANDWIDTH=763081,BANDWIDTH=1382836,VIDEO-RANGE=SDR,CODECS="avc1.64001f",RESOLUTION=864x486,URI="https://devstreaming-cdn.apple.com/videos/streaming/examples/adv_dv_atmos/Job932393e2-1e4f-4fdb-ab59-0d201f752656-107660254_Merged_Main_TrickPlay_HLS230_tier14/iframe_index.m3u8"
#EXT-X-STREAM-INF:AVERAGE-BANDWIDTH=10803450,BANDWIDTH=18352480,VIDEO-RANGE=SDR,CODECS="avc1.640028,ec-3",RESOLUTION=1920x1080,FRAME-RATE=23.976,CLOSED-CAPTIONS="cc",AUDIO="ec3-48-768",SUBTITLES="subtitles"
https://devstreaming-cdn.apple.com/videos/streaming/examples/adv_dv_atmos/Job2dae5735-d6ca-48ca-91be-0ec0bead535c-107702578-hls_bundle_hls290/prog_index.m3u8
#EXT-X-I-FRAME-STREAM-INF:AVERAGE-BANDWIDTH=2692031,BANDWIDTH=3733163,VIDEO-RANGE=SDR,CODECS="avc1.640028",RESOLUTION=1920x1080,URI="https://devstreaming-cdn.apple.com/videos/streaming/examples/adv_dv_atmos/Job932393e2-1e4f-4fdb-ab59-0d201f752656-107660254_Merged_Main_TrickPlay_HLS265_tier16/iframe_index.m3u8"
#EXT-X-STREAM-INF:AVERAGE-BANDWIDTH=4569760,BANDWIDTH=6301022,VIDEO-RANGE=SDR,CODECS="avc1.640028,ec-3",RESOLUTION=1920x1080,FRAME-RATE=23.976,CLOSED-CAPTIONS="cc",AUDIO="ec3-48-768",SUBTITLES="subtitles"
https://devstreaming-cdn.apple.com/videos/streaming/examples/adv_dv_atmos/Job2dae5735-d6ca-48ca-91be-0ec0bead535c-107702578-hls_bundle_hls265/prog_index.m3u8
#EXT-X-STREAM-INF:AVERAGE-BANDWIDTH=4647460,BANDWIDTH=6766146,VIDEO-RANGE=SDR,CODECS="avc1.64001f,ec-3",RESOLUTION=1280x720,FRAME-RATE=23.976,CLOSED-CAPTIONS="cc",AUDIO="ec3-48-768",SUBTITLES="subtitles"
https://devstreaming-cdn.apple.com/videos/streaming/examples/adv_dv_atmos/Job2dae5735-d6ca-48ca-91be-0ec0bead535c-107702578-hls_bundle_hls260/prog_index.m3u8
#EXT-X-I-FRAME-STREAM-INF:AVERAGE-BANDWIDTH=1449091,BANDWIDTH=2548095,VIDEO-RANGE=SDR,CODECS="avc1.64001f",RESOLUTION=1280x720,URI="https://devstreaming-cdn.apple.com/videos/streaming/examples/adv_dv_atmos/Job932393e2-1e4f-4fdb-ab59-0d201f752656-107660254_Merged_Main_TrickPlay_HLS250_tier15/iframe_index.m3u8"
#EXT-X-STREAM-INF:AVERAGE-BANDWIDTH=3561760,BANDWIDTH=4909286,VIDEO-RANGE=SDR,CODECS="avc1.64001f,ec-3",RESOLUTION=1280x720,FRAME-RATE=23.976,CLOSED-CAPTIONS="cc",AUDIO="ec3-48-768",SUBTITLES="subtitles"
https://devstreaming-cdn.apple.com/videos/streaming/examples/adv_dv_atmos/Job2dae5735-d6ca-48ca-91be-0ec0bead535c-107702578-hls_bundle_hls250/prog_index.m3u8
#EXT-X-I-FRAME-STREAM-INF:AVERAGE-BANDWIDTH=177512,BANDWIDTH=296000,VIDEO-RANGE=SDR,CODECS="mjpg",RESOLUTION=400x226,URI="https://devstreaming-cdn.apple.com/videos/streaming/examples/adv_dv_atmos/Job8208634a-0add-4223-9782-600c14a70339-139240443_Merged_Main_motionJpegTrickPlay_VT_HLS211_tier1/iframe_index.m3u8"
#EXT-X-I-FRAME-STREAM-INF:AVERAGE-BANDWIDTH=487047,BANDWIDTH=734517,VIDEO-RANGE=SDR,CODECS="avc1.64001f",RESOLUTION=672x378,URI="https://devstreaming-cdn.apple.com/videos/streaming/examples/adv_dv_atmos/Job932393e2-1e4f-4fdb-ab59-0d201f752656-107660254_Merged_Main_TrickPlay_HLS210_tier13/iframe_index.m3u8"
#EXT-X-STREAM-INF:AVERAGE-BANDWIDTH=2892539,BANDWIDTH=4501986,VIDEO-RANGE=SDR,CODECS="hvc1.2.20000000.L123.B0,ec-3",RESOLUTION=1280x720,FRAME-RATE=23.976,CLOSED-CAPTIONS="cc",AUDIO="ec3-48-768",SUBTITLES="subtitles"
https://devstreaming-cdn.apple.com/videos/streaming/examples/adv_dv_atmos/Job2dae5735-d6ca-48ca-91be-0ec0bead535c-107702578-hls_bundle_hevchls550/prog_index.m3u8
#EXT-X-I-FRAME-STREAM-INF:AVERAGE-BANDWIDTH=692477,BANDWIDTH=1441450,VIDEO-RANGE=SDR,CODECS="hvc1.2.20000000.L123.B0",RESOLUTION=1024x576,URI="https://devstreaming-cdn.apple.com/videos/streaming/examples/adv_dv_atmos/Job932393e2-1e4f-4fdb-ab59-0d201f752656-107660254_Merged_Main_sdrHevc_TrickPlay_HEVCHLS540_tier17/iframe_index.m3u8"
#EXT-X-STREAM-INF:AVERAGE-BANDWIDTH=21623585,BANDWIDTH=38288489,VIDEO-RANGE=SDR,CODECS="hvc1.2.20000000.H150.B0,ec-3",RESOLUTION=3840x2160,FRAME-RATE=23.976,CLOSED-CAPTIONS="cc",AUDIO="ec3-48-768",SUBTITLES="subtitles"
https://devstreaming-cdn.apple.com/videos/streaming/examples/adv_dv_atmos/Job2dae5735-d6ca-48ca-91be-0ec0bead535c-107702578-hls_bundle_hevchls598/prog_index.m3u8
#EXT-X-I-FRAME-STREAM-INF:AVERAGE-BANDWIDTH=2015997,BANDWIDTH=4399276,VIDEO-RANGE=SDR,CODECS="hvc1.2.20000000.L123.B0",RESOLUTION=1920x1080,URI="https://devstreaming-cdn.apple.com/videos/streaming/examples/adv_dv_atmos/Job932393e2-1e4f-4fdb-ab59-0d201f752656-107660254_Merged_Main_sdrHevc_TrickPlay_HEVCHLS585_tier19/iframe_index.m3u8"
#EXT-X-STREAM-INF:AVERAGE-BANDWIDTH=13061199,BANDWIDTH=26931098,VIDEO-RANGE=SDR,CODECS="hvc1.2.20000000.H150.B0,ec-3",RESOLUTION=3840x2160,FRAME-RATE=23.976,CLOSED-CAPTIONS="cc",AUDIO="ec3-48-768",SUBTITLES="subtitles"
https://devstreaming-cdn.apple.com/videos/streaming/examples/adv_dv_atmos/Job2dae5735-d6ca-48ca-91be-0ec0bead535c-107702578-hls_bundle_hevchls597/prog_index.m3u8
#EXT-X-STREAM-INF:AVERAGE-BANDWIDTH=12822217,BANDWIDTH=21622014,VIDEO-RANGE=SDR,CODECS="hvc1.2.20000000.H150.B0,ec-3",RESOLUTION=2560x1440,FRAME-RATE=23.976,CLOSED-CAPTIONS="cc",AUDIO="ec3-48-768",SUBTITLES="subtitles"
https://devstreaming-cdn.apple.com/videos/streaming/examples/adv_dv_atmos/Job2dae5735-d6ca-48ca-91be-0ec0bead535c-107702578-hls_bundle_hevchls591/prog_index.m3u8
#EXT-X-STREAM-INF:AVERAGE-BANDWIDTH=7766758,BANDWIDTH=12993630,VIDEO-RANGE=SDR,CODECS="hvc1.2.20000000.L123.B0,ec-3",RESOLUTION=1920x1080,FRAME-RATE=23.976,CLOSED-CAPTIONS="cc",AUDIO="ec3-48-768",SUBTITLES="subtitles"
https://devstreaming-cdn.apple.com/videos/streaming/examples/adv_dv_atmos/Job2dae5735-d6ca-48ca-91be-0ec0bead535c-107702578-hls_bundle_hevchls585/prog_index.m3u8
#EXT-X-STREAM-INF:AVERAGE-BANDWIDTH=3488792,BANDWIDTH=5422896,VIDEO-RANGE=SDR,CODECS="hvc1.2.20000000.L123.B0,ec-3",RESOLUTION=1920x1080,FRAME-RATE=23.976,CLOSED-CAPTIONS="cc",AUDIO="ec3-48-768",SUBTITLES="subtitles"
https://devstreaming-cdn.apple.com/videos/streaming/examples/adv_dv_atmos/Job2dae5735-d6ca-48ca-91be-0ec0bead535c-107702578-hls_bundle_hevchls565/prog_index.m3u8
#EXT-X-I-FRAME-STREAM-INF:AVERAGE-BANDWIDTH=1013960,BANDWIDTH=2274555,VIDEO-RANGE=SDR,CODECS="hvc1.2.20000000.L123.B0",RESOLUTION=1280x720,URI="https://devstreaming-cdn.apple.com/videos/streaming/examples/adv_dv_atmos/Job932393e2-1e4f-4fdb-ab59-0d201f752656-107660254_Merged_Main_sdrHevc_TrickPlay_HEVCHLS560_tier18/iframe_index.m3u8"
#EXT-X-STREAM-INF:AVERAGE-BANDWIDTH=3516666,BANDWIDTH=5824986,VIDEO-RANGE=SDR,CODECS="hvc1.2.20000000.L123.B0,ec-3",RESOLUTION=1280x720,FRAME-RATE=23.976,CLOSED-CAPTIONS="cc",AUDIO="ec3-48-768",SUBTITLES="subtitles"
https://devstreaming-cdn.apple.com/videos/streaming/examples/adv_dv_atmos/Job2dae5735-d6ca-48ca-91be-0ec0bead535c-107702578-hls_bundle_hevchls560/prog_index.m3u8
#EXT-X-I-FRAME-STREAM-INF:AVERAGE-BANDWIDTH=542003,BANDWIDTH=1090318,VIDEO-RANGE=SDR,CODECS="hvc1.2.20000000.L123.B0",RESOLUTION=864x486,URI="https://devstreaming-cdn.apple.com/videos/streaming/examples/adv_dv_atmos/Job932393e2-1e4f-4fdb-ab59-0d201f752656-107660254_Merged_Main_sdrHevc_TrickPlay_HEVCHLS530_tier16/iframe_index.m3u8"
#EXT-X-I-FRAME-STREAM-INF:AVERAGE-BANDWIDTH=604530,BANDWIDTH=1455657,VIDEO-RANGE=PQ,CODECS="dvh1.05.01",RESOLUTION=1024x576,URI="https://devstreaming-cdn.apple.com/videos/streaming/examples/adv_dv_atmos/Job932393e2-1e4f-4fdb-ab59-0d201f752656-107660254_Merged_MainHdrHlsDolbyVision_TrickPlay_HDRHLS740_tier17/iframe_index.m3u8"
#EXT-X-STREAM-INF:AVERAGE-BANDWIDTH=25097073,BANDWIDTH=37409767,VIDEO-RANGE=PQ,CODECS="dvh1.05.06,ec-3",RESOLUTION=3840x2160,FRAME-RATE=23.976,CLOSED-CAPTIONS="cc",AUDIO="ec3-48-768",SUBTITLES="subtitles"
https://devstreaming-cdn.apple.com/videos/streaming/examples/adv_dv_atmos/Job2dae5735-d6ca-48ca-91be-0ec0bead535c-107702578-hls_bundle_hdrhls798_dolbyvision/prog_index.m3u8
#EXT-X-I-FRAME-STREAM-INF:AVERAGE-BANDWIDTH=1680398,BANDWIDTH=3433652,VIDEO-RANGE=PQ,CODECS="dvh1.05.01",RESOLUTION=1920x1080,URI="https://devstreaming-cdn.apple.com/videos/streaming/examples/adv_dv_atmos/Job932393e2-1e4f-4fdb-ab59-0d201f752656-107660254_Merged_MainHdrHlsDolbyVision_TrickPlay_HDRHLS785_tier19/iframe_index.m3u8"
#EXT-X-STREAM-INF:AVERAGE-BANDWIDTH=16657358,BANDWIDTH=33623778,VIDEO-RANGE=PQ,CODECS="dvh1.05.06,ec-3",RESOLUTION=3840x2160,FRAME-RATE=23.976,CLOSED-CAPTIONS="cc",AUDIO="ec3-48-768",SUBTITLES="subtitles"
https://devstreaming-cdn.apple.com/videos/streaming/examples/adv_dv_atmos/Job2dae5735-d6ca-48ca-91be-0ec0bead535c-107702578-hls_bundle_hdrhls797_dolbyvision/prog_index.m3u8
#EXT-X-STREAM-INF:AVERAGE-BANDWIDTH=15695540,BANDWIDTH=27872950,VIDEO-RANGE=PQ,CODECS="dvh1.05.05,ec-3",RESOLUTION=2560x1440,FRAME-RATE=23.976,CLOSED-CAPTIONS="cc",AUDIO="ec3-48-768",SUBTITLES="subtitles"
https://devstreaming-cdn.apple.com/videos/streaming/examples/adv_dv_atmos/Job2dae5735-d6ca-48ca-91be-0ec0bead535c-107702578-hls_bundle_hdrhls791_dolbyvision/prog_index.m3u8
#EXT-X-STREAM-INF:AVERAGE-BANDWIDTH=9395322,BANDWIDTH=17259229,VIDEO-RANGE=PQ,CODECS="dvh1.05.03,ec-3",RESOLUTION=1920x1080,FRAME-RATE=23.976,CLOSED-CAPTIONS="cc",AUDIO="ec3-48-768",SUBTITLES="subtitles"
https://devstreaming-cdn.apple.com/videos/streaming/examples/adv_dv_atmos/Job2dae5735-d6ca-48ca-91be-0ec0bead535c-107702578-hls_bundle_hdrhls785_dolbyvision/prog_index.m3u8
#EXT-X-STREAM-INF:AVERAGE-BANDWIDTH=4091669,BANDWIDTH=6597524,VIDEO-RANGE=PQ,CODECS="dvh1.05.03,ec-3",RESOLUTION=1920x1080,FRAME-RATE=23.976,CLOSED-CAPTIONS="cc",AUDIO="ec3-48-768",SUBTITLES="subtitles"
https://devstreaming-cdn.apple.com/videos/streaming/examples/adv_dv_atmos/Job2dae5735-d6ca-48ca-91be-0ec0bead535c-107702578-hls_bundle_hdrhls765_dolbyvision/prog_index.m3u8
#EXT-X-I-FRAME-STREAM-INF:AVERAGE-BANDWIDTH=860516,BANDWIDTH=2007303,VIDEO-RANGE=PQ,CODECS="dvh1.05.01",RESOLUTION=1280x720,URI="https://devstreaming-cdn.apple.com/videos/streaming/examples/adv_dv_atmos/Job932393e2-1e4f-4fdb-ab59-0d201f752656-107660254_Merged_MainHdrHlsDolbyVision_TrickPlay_HDRHLS760_tier18/iframe_index.m3u8"
#EXT-X-STREAM-INF:AVERAGE-BANDWIDTH=4067185,BANDWIDTH=6160435,VIDEO-RANGE=PQ,CODECS="dvh1.05.01,ec-3",RESOLUTION=1280x720,FRAME-RATE=23.976,CLOSED-CAPTIONS="cc",AUDIO="ec3-48-768",SUBTITLES="subtitles"
https://devstreaming-cdn.apple.com/videos/streaming/examples/adv_dv_atmos/Job2dae5735-d6ca-48ca-91be-0ec0bead535c-107702578-hls_bundle_hdrhls760_dolbyvision/prog_index.m3u8
#EXT-X-STREAM-INF:AVERAGE-BANDWIDTH=3323532,BANDWIDTH=5186851,VIDEO-RANGE=PQ,CODECS="dvh1.05.01,ec-3",RESOLUTION=1280x720,FRAME-RATE=23.976,CLOSED-CAPTIONS="cc",AUDIO="ec3-48-768",SUBTITLES="subtitles"
https://devstreaming-cdn.apple.com/videos/streaming/examples/adv_dv_atmos/Job2dae5735-d6ca-48ca-91be-0ec0bead535c-107702578-hls_bundle_hdrhls750_dolbyvision/prog_index.m3u8
#EXT-X-I-FRAME-STREAM-INF:AVERAGE-BANDWIDTH=474498,BANDWIDTH=1094317,VIDEO-RANGE=PQ,CODECS="dvh1.05.01",RESOLUTION=864x486,URI="https://devstreaming-cdn.apple.com/videos/streaming/examples/adv_dv_atmos/Job932393e2-1e4f-4fdb-ab59-0d201f752656-107660254_Merged_MainHdrHlsDolbyVision_TrickPlay_HDRHLS730_tier16/iframe_index.m3u8"
#EXT-X-I-FRAME-STREAM-INF:AVERAGE-BANDWIDTH=715557,BANDWIDTH=1355514,VIDEO-RANGE=PQ,CODECS="hvc1.2.20000000.L123.B0",RESOLUTION=1024x576,URI="https://devstreaming-cdn.apple.com/videos/streaming/examples/adv_dv_atmos/Job8208634a-0add-4223-9782-600c14a70339-139240443-UpgradeToHDR10Plus_hdr10PlusMetadata_HDR10_tiers_trickPlay_HDRHLS740_HDR10Plus/iframe_index.m3u8"
#EXT-X-STREAM-INF:AVERAGE-BANDWIDTH=24757420,BANDWIDTH=40068766,VIDEO-RANGE=PQ,CODECS="hvc1.2.20000000.H150.B0,ec-3",RESOLUTION=3840x2160,FRAME-RATE=23.976,CLOSED-CAPTIONS="cc",AUDIO="ec3-48-768",SUBTITLES="subtitles"
https://devstreaming-cdn.apple.com/videos/streaming/examples/adv_dv_atmos/Job8208634a-0add-4223-9782-600c14a70339-139240443-hls_bundle_hdrhls798_hdr10plus/prog_index.m3u8
#EXT-X-I-FRAME-STREAM-INF:AVERAGE-BANDWIDTH=2188373,BANDWIDTH=4442603,VIDEO-RANGE=PQ,CODECS="hvc1.2.20000000.L123.B0",RESOLUTION=1920x1080,URI="https://devstreaming-cdn.apple.com/videos/streaming/examples/adv_dv_atmos/Job8208634a-0add-4223-9782-600c14a70339-139240443-UpgradeToHDR10Plus_hdr10PlusMetadata_HDR10_tiers_trickPlay_HDRHLS785_HDR10Plus/iframe_index.m3u8"
#EXT-X-STREAM-INF:AVERAGE-BANDWIDTH=15879341,BANDWIDTH=30434627,VIDEO-RANGE=PQ,CODECS="hvc1.2.20000000.H150.B0,ec-3",RESOLUTION=3840x2160,FRAME-RATE=23.976,CLOSED-CAPTIONS="cc",AUDIO="ec3-48-768",SUBTITLES="subtitles"
https://devstreaming-cdn.apple.com/videos/streaming/examples/adv_dv_atmos/Job8208634a-0add-4223-9782-600c14a70339-139240443-hls_bundle_hdrhls797_hdr10plus/prog_index.m3u8
#EXT-X-STREAM-INF:AVERAGE-BANDWIDTH=15331423,BANDWIDTH=26794663,VIDEO-RANGE=PQ,CODECS="hvc1.2.20000000.H150.B0,ec-3",RESOLUTION=2560x1440,FRAME-RATE=23.976,CLOSED-CAPTIONS="cc",AUDIO="ec3-48-768",SUBTITLES="subtitles"
https://devstreaming-cdn.apple.com/videos/streaming/examples/adv_dv_atmos/Job8208634a-0add-4223-9782-600c14a70339-139240443-hls_bundle_hdrhls791_hdr10plus/prog_index.m3u8
#EXT-X-STREAM-INF:AVERAGE-BANDWIDTH=9392465,BANDWIDTH=16580085,VIDEO-RANGE=PQ,CODECS="hvc1.2.20000000.L123.B0,ec-3",RESOLUTION=1920x1080,FRAME-RATE=23.976,CLOSED-CAPTIONS="cc",AUDIO="ec3-48-768",SUBTITLES="subtitles"
https://devstreaming-cdn.apple.com/videos/streaming/examples/adv_dv_atmos/Job8208634a-0add-4223-9782-600c14a70339-139240443-hls_bundle_hdrhls785_hdr10plus/prog_index.m3u8
#EXT-X-STREAM-INF:AVERAGE-BANDWIDTH=4005346,BANDWIDTH=6262643,VIDEO-RANGE=PQ,CODECS="hvc1.2.20000000.L123.B0,ec-3",RESOLUTION=1920x1080,FRAME-RATE=23.976,CLOSED-CAPTIONS="cc",AUDIO="ec3-48-768",SUBTITLES="subtitles"
https://devstreaming-cdn.apple.com/videos/streaming/examples/adv_dv_atmos/Job8208634a-0add-4223-9782-600c14a70339-139240443-hls_bundle_hdrhls765_hdr10plus/prog_index.m3u8
#EXT-X-I-FRAME-STREAM-INF:AVERAGE-BANDWIDTH=1084852,BANDWIDTH=2421227,VIDEO-RANGE=PQ,CODECS="hvc1.2.20000000.L123.B0",RESOLUTION=1280x720,URI="https://devstreaming-cdn.apple.com/videos/streaming/examples/adv_dv_atmos/Job8208634a-0add-4223-9782-600c14a70339-139240443-UpgradeToHDR10Plus_hdr10PlusMetadata_HDR10_tiers_trickPlay_HDRHLS760_HDR10Plus/iframe_index.m3u8"
#EXT-X-STREAM-INF:AVERAGE-BANDWIDTH=3990516,BANDWIDTH=6154594,VIDEO-RANGE=PQ,CODECS="hvc1.2.20000000.L123.B0,ec-3",RESOLUTION=1280x720,FRAME-RATE=23.976,CLOSED-CAPTIONS="cc",AUDIO="ec3-48-768",SUBTITLES="subtitles"
https://devstreaming-cdn.apple.com/videos/streaming/examples/adv_dv_atmos/Job8208634a-0add-4223-9782-600c14a70339-139240443-hls_bundle_hdrhls760_hdr10plus/prog_index.m3u8
#EXT-X-STREAM-INF:AVERAGE-BANDWIDTH=3277330,BANDWIDTH=5186572,VIDEO-RANGE=PQ,CODECS="hvc1.2.20000000.L123.B0,ec-3",RESOLUTION=1280x720,FRAME-RATE=23.976,CLOSED-CAPTIONS="cc",AUDIO="ec3-48-768",SUBTITLES="subtitles"
https://devstreaming-cdn.apple.com/videos/streaming/examples/adv_dv_atmos/Job8208634a-0add-4223-9782-600c14a70339-139240443-hls_bundle_hdrhls750_hdr10plus/prog_index.m3u8
#EXT-X-I-FRAME-STREAM-INF:AVERAGE-BANDWIDTH=550015,BANDWIDTH=1065785,VIDEO-RANGE=PQ,CODECS="hvc1.2.20000000.L123.B0",RESOLUTION=864x486,URI="https://devstreaming-cdn.apple.com/videos/streaming/examples/adv_dv_atmos/Job8208634a-0add-4223-9782-600c14a70339-139240443-UpgradeToHDR10Plus_hdr10PlusMetadata_HDR10_tiers_trickPlay_HDRHLS730_HDR10Plus/iframe_index.m3u8"
"""
 func prepareURL() async throws -> URL {
  if let readyURL=readyURL {return readyURL}
  return try await withCheckedThrowingContinuation {continuation in
   waiting.append(continuation)
   guard listener == nil else {return}
   do {
    let parameters=NWParameters.tcp
    parameters.requiredLocalEndpoint = .hostPort(host:.ipv4(IPv4Address("127.0.0.1")!),port:.any)
    let server=try NWListener(using:parameters)
    listener=server
    server.newConnectionHandler={ [weak self] connection in
     Task { @MainActor in
      guard let self=self else {connection.cancel();return}
      connection.start(queue:.main);self.readRequest(connection,buffer:Data())
     }
    }
    server.stateUpdateHandler={ [weak self] state in
     Task { @MainActor in
      guard let self=self else {return}
      switch state {
      case .ready:
       guard let port=server.port,let url=URL(string:"http://127.0.0.1:\(port.rawValue)/atmos-reference.m3u8") else {self.finish(.failure(NSError(domain:"AtmosReference",code:1)));return}
       self.readyURL=url;self.finish(.success(url))
      case .failed(let error):self.readyURL=nil;self.listener=nil;self.finish(.failure(error));server.cancel()
      case .cancelled:if self.listener === server {self.readyURL=nil;self.listener=nil};self.finish(.failure(NSError(domain:"AtmosReference",code:2)))
      default:break
      }
     }
    }
    server.start(queue:.main)
   } catch {listener=nil;finish(.failure(error))}
  }
 }
 private func finish(_ result: Result<URL,Error>) {
  let pending=waiting;waiting.removeAll()
  for continuation in pending {continuation.resume(with:result)}
 }
 private func readRequest(_ connection: NWConnection,buffer: Data) {
  connection.receive(minimumIncompleteLength:1,maximumLength:4096) { [weak self] chunk,_,complete,error in
   Task { @MainActor in
    guard let self=self,error == nil else {connection.cancel();return}
    var request=buffer;if let chunk=chunk {request.append(chunk)}
    guard request.count<=8192 else {connection.cancel();return}
    guard let text=String(data:request,encoding:.utf8),text.contains("\r\n\r\n") else {
     if complete {connection.cancel()} else {self.readRequest(connection,buffer:request)}
     return
    }
    let parts=text.components(separatedBy:"\r\n")[0].split(separator:" ")
    guard parts.count>=2,["GET","HEAD"].contains(String(parts[0])),parts[1]=="/atmos-reference.m3u8" else {connection.cancel();return}
    var response=Data("HTTP/1.1 200 OK\r\nContent-Type: application/vnd.apple.mpegurl\r\nContent-Length: \(self.manifest.count)\r\nCache-Control: no-cache\r\nConnection: close\r\n\r\n".utf8)
    if parts[0]=="GET" {response.append(self.manifest)}
    connection.send(content:response,completion:.contentProcessed {_ in connection.cancel()})
   }
  }
 }
}
