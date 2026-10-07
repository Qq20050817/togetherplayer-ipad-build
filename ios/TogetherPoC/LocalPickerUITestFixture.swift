#if DEBUG
import Foundation

// Only used by the simulator UI test, never included in Release.
@MainActor enum LocalPickerUITestFixture {
 static func installQualitySelection(into model: TestClient) throws {
  try install(into:model)
  let reference=BaiduMediaReference.create(fingerprint:String(repeating:"a",count:32),size:2000)!
  let timeline:[String:Any]=["state":"paused","position":0,"updatedAt":0,"playbackRate":1]
  model.receive(["type":"STATE","room":["roomId":"picker-ui-room","hostId":"fixture-host","title":"LOCAL-PICKER-TEST.mkv","mediaUrl":reference.value,"duration":1000,"version":2,"executeAt":0,"state":"paused","position":0,"updatedAt":0,"playbackRate":1,"before":timeline]],t4:0)
 }
 static func installRoomMediaValidation(into model: TestClient) throws {
  let timeline:[String:Any]=["state":"paused","position":0,"updatedAt":0,"playbackRate":1]
  let room:[String:Any]=["roomId":"media-ui-test","hostId":"media-ui-host","mediaUrl":"https://example.org/movie.mp4","version":1,"executeAt":0,"state":"paused","position":0,"updatedAt":0,"playbackRate":1,"before":timeline]
  model.receive(["type":"WELCOME","room":room],t4:0)
  model.mediaURL="invalid-file-link"
 }
 static func install(into model: TestClient) throws {
  let documents=FileManager.default.urls(for:.documentDirectory,in:.userDomainMask)[0]
  try FileManager.default.createDirectory(at:documents,withIntermediateDirectories:true)
  let url=documents.appendingPathComponent("LOCAL-PICKER-TEST.MP4")
  try Data(base64Encoded:"AAAAIGZ0eXBpc29tAAACAGlzb21pc28yYXZjMW1wNDEAAAMVbW9vdgAAAGxtdmhkAAAAAAAAAAAAAAAAAAAD6AAAA+gAAQAAAQAAAAAAAAAAAAAAAAEAAAAAAAAAAAAAAAAAAAABAAAAAAAAAAAAAAAAAABAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAgAAAkB0cmFrAAAAXHRraGQAAAADAAAAAAAAAAAAAAABAAAAAAAAA+gAAAAAAAAAAAAAAAAAAAAAAAEAAAAAAAAAAAAAAAAAAAABAAAAAAAAAAAAAAAAAABAAAAAACAAAAAgAAAAAAAkZWR0cwAAABxlbHN0AAAAAAAAAAEAAAPoAAAAAAABAAAAAAG4bWRpYQAAACBtZGhkAAAAAAAAAAAAAAAAAABAAAAAQABVxAAAAAAALWhkbHIAAAAAAAAAAHZpZGUAAAAAAAAAAAAAAABWaWRlb0hhbmRsZXIAAAABY21pbmYAAAAUdm1oZAAAAAEAAAAAAAAAAAAAACRkaW5mAAAAHGRyZWYAAAAAAAAAAQAAAAx1cmwgAAAAAQAAASNzdGJsAAAAv3N0c2QAAAAAAAAAAQAAAK9hdmMxAAAAAAAAAAEAAAAAAAAAAAAAAAAAAAAAACAAIABIAAAASAAAAAAAAAABFUxhdmM2MS4xOS4xMDEgbGlieDI2NAAAAAAAAAAAAAAAGP//AAAANWF2Y0MBZAAK/+EAGGdkAAqs2UlsBEAAAAMAQAAAAwCDxIllgAEABmjr48siwP34+AAAAAAQcGFzcAAAAAEAAAABAAAAFGJ0cnQAAAAAAAAWUAAAAAAAAAAYc3R0cwAAAAAAAAABAAAAAQAAQAAAAAAcc3RzYwAAAAAAAAABAAAAAQAAAAEAAAABAAAAFHN0c3oAAAAAAAACygAAAAEAAAAUc3RjbwAAAAAAAAABAAADRQAAAGF1ZHRhAAAAWW1ldGEAAAAAAAAAIWhkbHIAAAAAAAAAAG1kaXJhcHBsAAAAAAAAAAAAAAAALGlsc3QAAAAkqXRvbwAAABxkYXRhAAAAAQAAAABMYXZmNjEuNy4xMDMAAAAIZnJlZQAAAtJtZGF0AAACrQYF//+p3EXpvebZSLeWLNgg2SPu73gyNjQgLSBjb3JlIDE2NCByMzEwOCAzMWUxOWY5IC0gSC4yNjQvTVBFRy00IEFWQyBjb2RlYyAtIENvcHlsZWZ0IDIwMDMtMjAyMyAtIGh0dHA6Ly93d3cudmlkZW9sYW4ub3JnL3gyNjQuaHRtbCAtIG9wdGlvbnM6IGNhYmFjPTEgcmVmPTMgZGVibG9jaz0xOjA6MCBhbmFseXNlPTB4MzoweDExMyBtZT1oZXggc3VibWU9NyBwc3k9MSBwc3lfcmQ9MS4wMDowLjAwIG1peGVkX3JlZj0xIG1lX3JhbmdlPTE2IGNocm9tYV9tZT0xIHRyZWxsaXM9MSA4eDhkY3Q9MSBjcW09MCBkZWFkem9uZT0yMSwxMSBmYXN0X3Bza2lwPTEgY2hyb21hX3FwX29mZnNldD0tMiB0aHJlYWRzPTEgbG9va2FoZWFkX3RocmVhZHM9MSBzbGljZWRfdGhyZWFkcz0wIG5yPTAgZGVjaW1hdGU9MSBpbnRlcmxhY2VkPTAgYmx1cmF5X2NvbXBhdD0wIGNvbnN0cmFpbmVkX2ludHJhPTAgYmZyYW1lcz0zIGJfcHlyYW1pZD0yIGJfYWRhcHQ9MSBiX2JpYXM9MCBkaXJlY3Q9MSB3ZWlnaHRiPTEgb3Blbl9nb3A9MCB3ZWlnaHRwPTIga2V5aW50PTI1MCBrZXlpbnRfbWluPTEgc2NlbmVjdXQ9NDAgaW50cmFfcmVmcmVzaD0wIHJjX2xvb2thaGVhZD00MCByYz1jcmYgbWJ0cmVlPTEgY3JmPTIzLjAgcWNvbXA9MC42MCBxcG1pbj0wIHFwbWF4PTY5IHFwc3RlcD00IGlwX3JhdGlvPTEuNDAgYXE9MToxLjAwAIAAAAAVZYiEABX//vfJ78Cm69vetb9gAQD5")!.write(to:url)
  let timeline:[String:Any]=["state":"paused","position":0,"updatedAt":0,"playbackRate":1]
  model.receive(["type":"WELCOME","room":["roomId":"picker-ui-room","hostId":"fixture-host","mediaUrl":"https://example.invalid/fixture.mp4","version":1,"executeAt":0,"state":"paused","position":0,"updatedAt":0,"playbackRate":1,"before":timeline]],t4:0)
 }
}
#endif
