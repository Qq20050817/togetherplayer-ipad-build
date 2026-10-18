import Foundation

@main enum P2PFastPathStandalone {
 static func main() {
  var gate = P2PFastPathGate()
  let command = P2PControlHint(roomID:"demo1234",senderUserID:"host",roomVersion:2,sequence:1,
                               action:.pause,positionMs:250,issuedAtMs:100_000)
  gate.attach(roomID:"demo1234",hostUserID:"host",localUserID:"guest",serverVersion:2)
  precondition(gate.admit(command,nowMs:100_100) == .noVerifiedPeer)
  gate.verifyPeer(fromAuthoritativeRoster:true)
  gate.setChannelAlive(true)
  precondition(gate.admit(command,nowMs:100_100) == .accepted)
  precondition(gate.admit(command,nowMs:100_100) == .staleSequence)
  gate.serverState(version:3)
  let stale = P2PControlHint(roomID:"demo1234",senderUserID:"host",roomVersion:2,sequence:2,
                             action:.pause,positionMs:250,issuedAtMs:100_000)
  precondition(gate.admit(stale,nowMs:100_100) == .staleVersion)
  gate.reset()
  precondition(gate.admit(stale,nowMs:100_100) == .noVerifiedPeer)
  print("P2PFastPathGate standalone checks passed")
 }
}
