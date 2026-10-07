import SwiftUI
import UniformTypeIdentifiers

// Small subtitle files are copied into the sandbox. Unlike a SwiftUI importer,
// this delegates selection directly even when another app owns the file's UTI.
struct SubtitleDocumentPicker: UIViewControllerRepresentable {
 let onPick:(URL)->Void
 let onCancel:()->Void
 func makeCoordinator()->Coordinator {Coordinator(onPick:onPick,onCancel:onCancel)}
 func makeUIViewController(context:Context)->UIDocumentPickerViewController {
  let picker=UIDocumentPickerViewController(forOpeningContentTypes:[.data,.plainText],asCopy:true)
  picker.allowsMultipleSelection=false;picker.shouldShowFileExtensions=true
  picker.delegate=context.coordinator
  let documents=FileManager.default.urls(for:.documentDirectory,in:.userDomainMask).first
  #if DEBUG
  if ProcessInfo.processInfo.environment["TOGETHER_SUBTITLE_SELECTION_TEST"]=="1" {
   picker.directoryURL=documents?.appendingPathComponent("SubtitleUITest",isDirectory:true)
  } else {picker.directoryURL=documents}
  #else
  picker.directoryURL=documents
  #endif
  picker.view.accessibilityIdentifier="subtitle-document-picker"
  return picker
 }
 func updateUIViewController(_ picker:UIDocumentPickerViewController,context:Context) {}
 final class Coordinator:NSObject,UIDocumentPickerDelegate {
  let onPick:(URL)->Void
  let onCancel:()->Void
  private var completed=false
  init(onPick:@escaping(URL)->Void,onCancel:@escaping()->Void) {self.onPick=onPick;self.onCancel=onCancel}
  func documentPicker(_ controller:UIDocumentPickerViewController,didPickDocumentsAt urls:[URL]) {
   guard !completed else {return};completed=true
   if let url=urls.first {onPick(url)} else {onCancel()}
  }
  func documentPickerWasCancelled(_ controller:UIDocumentPickerViewController) {
   guard !completed else {return};completed=true;onCancel()
  }
 }
}
