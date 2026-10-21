import Foundation

@main struct P2PMuseHandoffRegression {
 static func hint(_ action:P2PPlaybackAction = .play) -> P2PControlHint {
  P2PControlHint(roomID:"room",senderUserID:"host",roomVersion:7,
                 sequence:1,action:action,positionMs:20_000,issuedAtMs:100_000)
 }
 static func main() {
  var handoff=P2PMuseHandoff()
  handoff.begin(hint(),timelineOffset:0,now:100)
  precondition(handoff.shouldDeferMuse(now:1_400,roomID:"room",roomVersion:7,
    targetState:"paused",targetPositionMs:20_000,blockingPoll:false,authoritativePause:false))
  precondition(handoff.shouldDeferMuse(now:1_500,roomID:"room",roomVersion:8,
    targetState:"paused",targetPositionMs:20_000,blockingPoll:false,authoritativePause:false))
  precondition(!handoff.shouldDeferMuse(now:1_600,roomID:"room",roomVersion:8,
    targetState:"playing",targetPositionMs:20_100,blockingPoll:false,authoritativePause:false))
  precondition(!handoff.shouldDeferMuse(now:1_700,roomID:"room",roomVersion:8,
    targetState:"playing",targetPositionMs:20_200,blockingPoll:false,authoritativePause:false))
  handoff.begin(hint(.pause),timelineOffset:0,now:1_800)
  precondition(handoff.shouldDeferMuse(now:2_000,roomID:"room",roomVersion:7,
    targetState:"playing",targetPositionMs:nil,blockingPoll:false,authoritativePause:false))
  precondition(!handoff.shouldDeferMuse(now:2_100,roomID:"room",roomVersion:8,
    targetState:"paused",targetPositionMs:20_000,blockingPoll:false,authoritativePause:false))
  handoff.begin(hint(.seek),timelineOffset:500,now:2_200)
  precondition(handoff.shouldDeferMuse(now:2_500,roomID:"room",roomVersion:8,
    targetState:"playing",targetPositionMs:50_000,blockingPoll:false,authoritativePause:false))
  precondition(!handoff.shouldDeferMuse(now:2_600,roomID:"room",roomVersion:8,
    targetState:"playing",targetPositionMs:20_550,blockingPoll:false,authoritativePause:false))
  handoff.begin(hint(),timelineOffset:0,now:3_000)
  precondition(!handoff.shouldDeferMuse(now:6_500,roomID:"room",roomVersion:7,
    targetState:"paused",targetPositionMs:nil,blockingPoll:false,authoritativePause:false))
  handoff.begin(hint(),timelineOffset:0,now:7_000)
  precondition(!handoff.shouldDeferMuse(now:7_100,roomID:"room",roomVersion:7,
    targetState:"paused",targetPositionMs:nil,blockingPoll:true,authoritativePause:false))
  handoff.begin(hint(),timelineOffset:0,now:8_000)
  precondition(!handoff.shouldDeferMuse(now:8_100,roomID:"room",roomVersion:7,
    targetState:"paused",targetPositionMs:nil,blockingPoll:false,authoritativePause:true))
  handoff.begin(hint(),timelineOffset:0,now:9_000)
  precondition(!handoff.shouldDeferMuse(now:9_100,roomID:"newroom",roomVersion:7,
    targetState:"paused",targetPositionMs:nil,blockingPoll:false,authoritativePause:false))
  handoff.begin(hint(),timelineOffset:0,now:10_000)
  precondition(!handoff.shouldDeferMuse(now:10_100,roomID:"room",roomVersion:9,
    targetState:"paused",targetPositionMs:nil,blockingPoll:false,authoritativePause:false))
  print("P2P → Muse bounded handoff regression passed")
 }
}
