import Foundation

// Only successful terminal Responses events advance this check. Compiling,
// sign-in alone, a token in Keychain or a mocked test never enables production.
struct PlotAuthAcceptance:Codable,Equatable {
 private(set) var run=""
 private(set) var calls=0
 private(set) var ready=false
 mutating func success(run current:String) {
  guard !current.isEmpty else {return}
  if run==current {calls+=1}
  else if calls>=2 {ready=true}
  else {run=current;calls=1}
 }
}
