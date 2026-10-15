import XCTest
@testable import TogetherPoC

@MainActor final class WholeFilmModelRouterTests:XCTestCase {
 private let unsupported=NSError(domain:"FoundationModels",code:1,userInfo:[NSLocalizedDescriptionKey:"An unsupported language or locale was used"])
 func testChatGPTOnlyNeverInvokesAvailableLocalModelForAnyStage() async throws {
  let router=WholeFilmModelRouter();var local=0;var cloud=0
  router.localAvailable={true};router.cloudAllowed={true}
  router.localInference={_,_ in local+=1;throw self.unsupported}
  router.cloudInference={_,_ in cloud+=1;return "cloud-result"}
  for instruction in [WholeFilmPlan.sectionInstructions,WholeFilmPlan.mapInstructions,WholeFilmPlan.questionInstructions,WholeFilmPlan.auditInstructions] {
   let result=try await router.respond(mode:.chatgpt,instructions:instruction,input:"fixture")
   XCTAssertEqual(result,"cloud-result")
  }
  XCTAssertEqual(local,0);XCTAssertEqual(cloud,4)
 }
 func testChatGPTOnlyWithoutCloudConsentDoesNotUseLocalFallback() async {
  let router=WholeFilmModelRouter();var calls=0
  router.localAvailable={true};router.cloudAllowed={false}
  router.localInference={_,_ in calls+=1;return "local"};router.cloudInference={_,_ in calls+=1;return "cloud"}
  XCTAssertFalse(router.available(mode:.chatgpt))
  do {_ = try await router.respond(mode:.chatgpt,instructions:"",input:"");XCTFail("Missing consent must block")}
  catch {XCTAssertTrue(error.localizedDescription.contains("ChatGPT"))}
  XCTAssertEqual(calls,0)
 }
 func testSmartLanguageFailureUsesPermittedCloudOnceAndRemembersFailure() async throws {
  let router=WholeFilmModelRouter();var local=0;var cloud=0
  router.localAvailable={true};router.cloudAllowed={true}
  router.localInference={_,_ in local+=1;throw self.unsupported}
  router.cloudInference={_,_ in cloud+=1;return "cloud"}
  _=try await router.respond(mode:.smart,instructions:"section",input:"")
  _=try await router.respond(mode:.smart,instructions:"next section",input:"")
  XCTAssertEqual(local,1);XCTAssertEqual(cloud,2);XCTAssertFalse(router.canUseLocal)
 }
 func testLanguageErrorDoesNotCreateCloudConsentOrRequest() async {
  let router=WholeFilmModelRouter();var cloud=0
  router.localAvailable={true};router.cloudAllowed={false}
  router.localInference={_,_ in throw self.unsupported};router.cloudInference={_,_ in cloud+=1;return "unexpected"}
  do {_=try await router.respond(mode:.smart,instructions:"",input:"");XCTFail("Must report unsupported locale")}
  catch {XCTAssertTrue(error.localizedDescription.contains("不支持当前语言"));XCTAssertFalse(error.localizedDescription.contains("An unsupported"))}
  XCTAssertEqual(cloud,0)
 }
 func testLocalOnlyDoesNotSendMovieToCloudAfterLanguageError() async {
  let router=WholeFilmModelRouter();var cloud=0
  router.localAvailable={true};router.cloudAllowed={true}
  router.localInference={_,_ in throw self.unsupported};router.cloudInference={_,_ in cloud+=1;return "unexpected"}
  do {_=try await router.respond(mode:.local,instructions:"",input:"");XCTFail("Local only must stop")}
  catch {XCTAssertTrue(error.localizedDescription.contains("苹果本地 AI"))}
  XCTAssertEqual(cloud,0)
 }
 func testCancellationAndOtherLocalFailuresAreNotAutomaticallyRetried() async {
  for error in [CancellationError() as Error,NSError(domain:"fixture",code:2) as Error] {
   let router=WholeFilmModelRouter();var cloud=0
   router.localAvailable={true};router.cloudAllowed={true};router.localInference={_,_ in throw error}
   router.cloudInference={_,_ in cloud+=1;return "unexpected"}
   do {_=try await router.respond(mode:.smart,instructions:"",input:"");XCTFail("Expected failure")}
   catch {}
   XCTAssertEqual(cloud,0)
  }
 }
}
