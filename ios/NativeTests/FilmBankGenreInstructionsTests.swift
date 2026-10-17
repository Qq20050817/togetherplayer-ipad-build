import XCTest
@testable import TogetherPoC

final class FilmBankGenreInstructionsTests:XCTestCase {
 func testAll21IndependentGenresCoverEveryMajorFilmFamily() {
  let profiles=FilmBankGenreInstructions.playbooks
  XCTAssertEqual(profiles.count,21,"Genre-specific film prompts must not silently disappear")
  XCTAssertEqual(Set(profiles.map{$0.id}).count,profiles.count)
  for name in ["喜剧与无厘头","黑色幽默与社会讽刺","恐怖与超自然","悬疑与侦探推理",
               "心理惊悚与犯罪","爱情与浪漫","青春校园与成长","家庭亲情与温情治愈",
               "现实主义与社会剧情","动作警匪与谍战","科幻与时间循环","奇幻冒险与武侠",
               "战争历史与年代","灾难与生存","纪录片与人物传记","动画与合家欢",
               "音乐歌舞与表演","体育竞技与励志","文艺电影与超现实主义",
               "西部片与江湖武侠","职场行业与群像"] {
   XCTAssertTrue(profiles.contains{$0.title==name},"Missing specific movie type: \(name)")
  }
  for profile in profiles {
   XCTAssertTrue(profile.guidance.contains("核心叙事"),profile.title)
   XCTAssertTrue(profile.guidance.contains("题目策略"),profile.title)
   XCTAssertTrue(profile.guidance.contains("触发与禁区"),profile.title)
   XCTAssertTrue(profile.guidance.contains("片尾"),profile.title)
   XCTAssertGreaterThan(profile.guidance.count,95,profile.title)
  }
 }
 func testGuideRoutesMixedGenresWithoutChangingExistingSchema() {
  let guide=FilmBankProjectInstructions.text
  for phrase in ["主类型","副类型","21 类独立","未揭晓","filmReview","discussion",
                 "answerIndex=null","evidence","revealEvidence","triggerAtMs",
                 "不能把","片名","时机"] {
   XCTAssertTrue(guide.contains(phrase),"Missing safety/editorial rule: \(phrase)")
  }
  XCTAssertTrue(guide.contains("喜剧与无厘头"))
  XCTAssertTrue(guide.contains("爱情与浪漫"))
  XCTAssertTrue(guide.contains("纪录片与人物传记"))
  XCTAssertTrue(guide.contains("恐怖与超自然"))
  XCTAssertEqual(FilmBankGenreInstructions.exportFiles.count,21)
  XCTAssertEqual(Set(FilmBankGenreInstructions.exportFiles.map{$0.0}).count,21)
  XCTAssertTrue(FilmBankGenreInstructions.exportFiles.allSatisfy{$0.0.hasPrefix("genres/") && !$0.1.isEmpty})
 }
}
