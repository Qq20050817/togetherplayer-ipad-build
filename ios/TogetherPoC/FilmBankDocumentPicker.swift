import SwiftUI
import UniformTypeIdentifiers

struct SelectedFilmBankDocument {
 let name:String
 let data:Data
}

enum FilmBankDocumentReader {
 static func read(_ url:URL)throws->Data {
  try Task.checkCancellation()
  guard url.isFileURL else{throw FilmBankValidation.detail("请选择下载到“文件”App的 JSON 题库。")}
  let scoped=url.startAccessingSecurityScopedResource()
  defer{if scoped {url.stopAccessingSecurityScopedResource()}}
  let coordinator=NSFileCoordinator(filePresenter:nil)
  var coordinationError:NSError?,result:Result<Data,Error>?
  coordinator.coordinate(readingItemAt:url,options:.withoutChanges,error:&coordinationError) {accessible in
   result=Result {
    try Task.checkCancellation()
    guard (try accessible.resourceValues(forKeys:[.isDirectoryKey])).isDirectory != true else{throw FilmBankValidation.detail("请选择 JSON 文件，不能选择文件夹。")}
    let handle=try FileHandle(forReadingFrom:accessible);defer{try? handle.close()}
    let data=try handle.read(upToCount:FilmBankCodec.maxBytes+1) ?? Data()
    guard !data.isEmpty,data.count<=FilmBankCodec.maxBytes else{throw FilmBankValidation.invalidFormat}
    return data
   }
  }
  if let coordinationError {throw coordinationError}
  guard let result else{throw FilmBankValidation.detail("文件提供程序没有返回题库内容，请确认已下载后重试。")}
  return try result.get()
 }
}

// Do not rely solely on a provider's JSON UTI. ChatGPT downloads may be
// registered as generic data/text. The strict schema still validates bytes.
@MainActor struct FilmBankDocumentPicker:UIViewControllerRepresentable {
 static let contentTypes:[UTType]=[.json,.data,.plainText]
 let onPick:(SelectedFilmBankDocument)->Void
 let onCancel:()->Void
 let onFailure:(String)->Void
 var onReading:(String)->Void={_ in}
 func makeCoordinator()->Coordinator {Coordinator(onPick:onPick,onCancel:onCancel,onFailure:onFailure,onReading:onReading)}
 func makeUIViewController(context:Context)->UIDocumentPickerViewController {
  let controller=UIDocumentPickerViewController(forOpeningContentTypes:Self.contentTypes,asCopy:true)
  controller.delegate=context.coordinator;controller.allowsMultipleSelection=false;controller.shouldShowFileExtensions=true
  let documents=FileManager.default.urls(for:.documentDirectory,in:.userDomainMask).first
  #if DEBUG
  controller.directoryURL=ProcessInfo.processInfo.environment["TOGETHER_BANK_PICKER_TEST"]=="1" ? documents?.appendingPathComponent("JSONUITest",isDirectory:true) : documents
  #else
  controller.directoryURL=documents
  #endif
  controller.view.accessibilityIdentifier="film-bank-document-picker"
  return controller
 }
 func updateUIViewController(_ controller:UIDocumentPickerViewController,context:Context) {}
 @MainActor final class Coordinator:NSObject,UIDocumentPickerDelegate {
  private let onPick:(SelectedFilmBankDocument)->Void,onCancel:()->Void,onFailure:(String)->Void,onReading:(String)->Void
  private var selected=false,finished=false
  private var reader:Task<Data,Error>?
  init(onPick:@escaping(SelectedFilmBankDocument)->Void,onCancel:@escaping()->Void,onFailure:@escaping(String)->Void,onReading:@escaping(String)->Void) {
   self.onPick=onPick;self.onCancel=onCancel;self.onFailure=onFailure;self.onReading=onReading
  }
  func documentPicker(_ controller:UIDocumentPickerViewController,didPickDocumentsAt urls:[URL]) {
   guard !selected,!finished else{return}
   guard let url=urls.first else{documentPickerWasCancelled(controller);return}
   selected=true;onReading(url.lastPathComponent)
   // Acquire the provider grant while its selection callback is active. Read
   // the bounded JSON before handing data back or dismissing our host cover.
   let access=url.startAccessingSecurityScopedResource()
   let job=Task.detached(priority:.userInitiated){try FilmBankDocumentReader.read(url)}
   reader=job
   Task {[self] in
    let result=await job.result
    if access {url.stopAccessingSecurityScopedResource()}
    reader=nil
    guard !finished else{return};finished=true
    switch result {
    case .success(let bytes):onPick(SelectedFilmBankDocument(name:url.lastPathComponent,data:bytes))
    case .failure(let error):onFailure("题库读取失败："+error.localizedDescription)
    }
   }
  }
  func documentPickerWasCancelled(_ controller:UIDocumentPickerViewController) {
   guard !finished else{return};finished=true;reader?.cancel();onCancel()
  }
 }
}
