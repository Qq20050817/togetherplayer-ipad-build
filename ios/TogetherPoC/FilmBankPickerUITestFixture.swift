#if DEBUG
import Foundation

@MainActor enum FilmBankPickerUITestFixture {
 static func install(into model:TestClient)throws {
  try LocalPickerUITestFixture.install(into:model)
  let documents=FileManager.default.urls(for:.documentDirectory,in:.userDomainMask)[0]
  let folder=documents.appendingPathComponent("JSONUITest",isDirectory:true)
  try? FileManager.default.removeItem(at:folder)
  try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
  let movie=folder.appendingPathComponent("JSON-PICKER-FILM.mp4")
  var bytes=Data(base64Encoded:"AAAAIGZ0eXBpc29tAAACAGlzb21pc28yYXZjMW1wNDEAAAAIZnJlZQAAAt9tZGF0AAACrQYF//+p3EXpvebZSLeWLNgg2SPu73gyNjQgLSBjb3JlIDE2NCByMzEwOCAzMWUxOWY5IC0gSC4yNjQvTVBFRy00IEFWQyBjb2RlYyAtIENvcHlsZWZ0IDIwMDMtMjAyMyAtIGh0dHA6Ly93d3cudmlkZW9sYW4ub3JnL3gyNjQuaHRtbCAtIG9wdGlvbnM6IGNhYmFjPTEgcmVmPTMgZGVibG9jaz0xOjA6MCBhbmFseXNlPTB4MzoweDExMyBtZT1oZXggc3VibWU9NyBwc3k9MSBwc3lfcmQ9MS4wMDowLjAwIG1peGVkX3JlZj0xIG1lX3JhbmdlPTE2IGNocm9tYV9tZT0xIHRyZWxsaXM9MSA4eDhkY3Q9MSBjcW09MCBkZWFkem9uZT0yMSwxMSBmYXN0X3Bza2lwPTEgY2hyb21hX3FwX29mZnNldD0tMiB0aHJlYWRzPTIgbG9va2FoZWFkX3RocmVhZHM9MSBzbGljZWRfdGhyZWFkcz0wIG5yPTAgZGVjaW1hdGU9MSBpbnRlcmxhY2VkPTAgYmx1cmF5X2NvbXBhdD0wIGNvbnN0cmFpbmVkX2ludHJhPTAgYmZyYW1lcz0zIGJfcHlyYW1pZD0yIGJfYWRhcHQ9MSBiX2JpYXM9MCBkaXJlY3Q9MSB3ZWlnaHRiPTEgb3Blbl9nb3A9MCB3ZWlnaHRwPTIga2V5aW50PTI1MCBrZXlpbnRfbWluPTEgc2NlbmVjdXQ9NDAgaW50cmFfcmVmcmVzaD0wIHJjX2xvb2thaGVhZD00MCByYz1jcmYgbWJ0cmVlPTEgY3JmPTIzLjAgcWNvbXA9MC42MCBxcG1pbj0wIHFwbWF4PTY5IHFwc3RlcD00IGlwX3JhdGlvPTEuNDAgYXE9MToxLjAwAIAAAAAiZYiEABX//vfJ78Cm69vetb+Tz0j4e8ZQD6wZq+vbSH/7MQAAAxVtb292AAAAbG12aGQAAAAAAAAAAAAAAAAAAAPoAAEk+AABAAABAAAAAAAAAAAAAAAAAQAAAAAAAAAAAAAAAAAAAAEAAAAAAAAAAAAAAAAAAEAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAACAAACQHRyYWsAAABcdGtoZAAAAAMAAAAAAAAAAAAAAAEAAAAAAAEk+AAAAAAAAAAAAAAAAAAAAAAAAQAAAAAAAAAAAAAAAAAAAAEAAAAAAAAAAAAAAAAAAEAAAAAAQAAAAEAAAAAAACRlZHRzAAAAHGVsc3QAAAAAAAAAAQABJPgAAAAAAAEAAAAAAbhtZGlhAAAAIG1kaGQAAAAAAAAAAAAAAAAAAEAAABLAAFXEAAAAAAAtaGRscgAAAAAAAAAAdmlkZQAAAAAAAAAAAAAAAFZpZGVvSGFuZGxlcgAAAAFjbWluZgAAABR2bWhkAAAAAQAAAAAAAAAAAAAAJGRpbmYAAAAcZHJlZgAAAAAAAAABAAAADHVybCAAAAABAAABI3N0YmwAAAC/c3RzZAAAAAAAAAABAAAAr2F2YzEAAAAAAAAAAQAAAAAAAAAAAAAAAAAAAAAAQABAAEgAAABIAAAAAAAAAAEVTGF2YzYxLjE5LjEwMSBsaWJ4MjY0AAAAAAAAAAAAAAAY//8AAAA1YXZjQwFkAAr/4QAYZ2QACqzZRCbARAAAAwEsAAADAAg8SJZYAQAGaOvjyyLA/fj4AAAAABBwYXNwAAAAAQAAAAEAAAAUYnRydAAAAAAAAABNAAAAAAAAABhzdHRzAAAAAAAAAAEAAAABABLAAAAAABxzdHNjAAAAAAAAAAEAAAABAAAAAQAAAAEAAAAUc3RzegAAAAAAAALXAAAAAQAAABRzdGNvAAAAAAAAAAEAAAAwAAAAYXVkdGEAAABZbWV0YQAAAAAAAAAhaGRscgAAAAAAAAAAbWRpcmFwcGwAAAAAAAAAAAAAAAAsaWxzdAAAACSpdG9vAAAAHGRhdGEAAAABAAAAAExhdmY2MS43LjEwMw==")!
  // Distinct source per launch; a previous run must not auto-load a bank and
  // make a failed import look successful. ISO-BMFF free box leaves AV intact.
  let marker=Data(UUID().uuidString.utf8),length=UInt32(marker.count+8)
  bytes.append(contentsOf:[UInt8(length>>24),UInt8((length>>16)&255),UInt8((length>>8)&255),UInt8(length&255)])
  bytes.append(Data("free".utf8));bytes.append(marker);try bytes.write(to:movie)
  let q=FilmBankQuestion(id:"picker-q1",triggerAtMs:20_000,revealAtMs:50_000,type:"prediction",question:"守门人藏起钥匙后，访客会向谁求证？",options:["询问当时在场的证人","寻找钥匙的购买记录"],answerIndex:0,evidence:[FilmBankEvidence(kind:"subtitle",startMs:10_000,endMs:15_000,text:"守门人否认移动钥匙")],revealEvidence:[FilmBankEvidence(kind:"subtitle",startMs:45_000,endMs:48_000,text:"访客向在场证人求证")],explanation:"后续对白验证访客选择询问证人。",confidence:0.9,qualityScore:90)
  let bank=FilmQuestionBank(schemaVersion:1,title:"JSON-PICKER-LOADED",year:nil,edition:nil,durationMs:75_000,sourceFingerprint:try FilmMaterialFingerprint.source(movie),subtitleFingerprint:nil,questions:[q])
  try JSONEncoder().encode(bank).write(to:folder.appendingPathComponent("VALID-QUESTION-BANK.json"))
  try Data("{\"schemaVersion\":1}".utf8).write(to:folder.appendingPathComponent("INVALID-QUESTION-BANK.json"))
  model.installCleanupTestSource(movie)
  model.isRoomHost=true;model.isConnected=true;model.supportsBlockingPolls=true
  model.plotIntelligence.mode = .fallback
  model.plotIntelligence.automaticAllowed=false;model.plotIntelligence.consent=false
 }
}
#endif
