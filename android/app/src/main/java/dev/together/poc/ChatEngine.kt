package dev.together.poc
import org.json.JSONObject
data class ChatMessage(val id: Long,val userId: String,val name: String,val text: String,val clientId: String,val timestamp: Double=0.0) {companion object {fun parse(o: JSONObject)=ChatMessage(o.getLong("id"),o.getString("userId"),o.getString("name"),o.getString("text"),o.getString("clientMessageId"),o.optDouble("timestamp",0.0))}}
class ChatEngine {
 private var room="";val messages=ArrayList<ChatMessage>();var visible=true;var unread=0;private set;var typingName="";private set;private var until=0.0
 fun reset(id: String){if(room!=id){room=id;messages.clear();unread=0;typingName=""}}
 fun accept(m: ChatMessage,mine: Boolean): Boolean {if(messages.any {it.id==m.id})return false;messages.add(m);messages.sortBy {it.id};while(messages.size>500)messages.removeAt(0);if(!visible && !mine)unread++;return true}
 fun read(){unread=0};fun typing(name: String,now: Double){typingName=name;until=now+3000};fun tick(now: Double){if(now>until)typingName=""}
}
