package dev.together.poc
import android.content.Context
import android.app.AlertDialog
import android.widget.*
import org.json.JSONArray
import org.json.JSONObject

class WatchMemory(private val context:Context,private val onlineEnabled:Boolean=true) {
 private val prefs=context.getSharedPreferences("watch-memory-v1",Context.MODE_PRIVATE)
 var catalog:List<MemoryFilm>;private set
 var catalogStatus="内置片单可离线推荐";private set
 @Volatile private var refreshing=false
 private var lastSignature=""
 private var lastRefresh=0L
 var records:List<MemoryRecord> = emptyList();private set
 private var dismissed=emptySet<String>()
 var storageError="";private set
 init {
  catalog=try {val a=JSONArray(context.assets.open("film-catalog.json").bufferedReader().use{it.readText()});(0 until a.length()).map{val o=a.getJSONObject(it);MemoryFilm(o.getString("id"),o.getString("title"),o.getInt("year"),strings(o.getJSONArray("aliases")),strings(o.getJSONArray("tags")),o.getString("synopsis"))}}catch(e:Exception){emptyList()}
  try {val cached=JSONArray(prefs.getString("catalog","[]")!!);catalog=catalog+(0 until cached.length()).map{decodeFilm(cached.getJSONObject(it))}.filter{f->catalog.none{it.id==f.id}}}catch(e:Exception){}
  try {
   val o=JSONObject(prefs.getString("archive","{\"records\":[],\"dismissed\":[]}")!!)
   records=(0 until o.getJSONArray("records").length()).map{val r=o.getJSONArray("records").getJSONObject(it);MemoryRecord(r.getString("id"),r.getString("title"),r.getLong("completedAt"),if(r.isNull("rating"))null else r.getInt("rating"),strings(r.getJSONArray("tags")),r.optString("note"))}
   dismissed=strings(o.getJSONArray("dismissed")).toSet()
  }catch(e:Exception){storageError="观影档案读取失败，原始数据已保留。"}
 }
 private fun decodeFilm(o:JSONObject)=MemoryFilm(o.getString("id"),o.getString("title"),o.getInt("year"),strings(o.getJSONArray("aliases")),strings(o.getJSONArray("tags")),o.getString("synopsis"),o.optString("sourceURL").takeIf{it.isNotBlank()})
 fun refreshCatalog(force:Boolean=false,done:()->Unit={}) {
  if(!onlineEnabled || refreshing || records.isEmpty())return
  val genres=mapOf("喜剧" to "4404","悬疑" to "4416","爱情" to "4412","科幻" to "4413","动画" to "4402","现实题材" to "4406","家庭" to "4410")
  val weights=mutableMapOf<String,Double>()
  records.forEach{r->r.tags.forEach{weights[it]=(weights[it]?:0.0)+(r.rating?.let{(it-3).toDouble()}?:0.25)}}
  val chosen=weights.filter{it.key in genres && it.value>0}.entries.sortedByDescending{it.value}.take(2).mapNotNull{genres[it.key]}
  val targets=chosen.ifEmpty{listOf("4404","4416")};val signature=targets.sorted().joinToString(",")
  if(!force && signature==lastSignature && System.currentTimeMillis()-lastRefresh<86_400_000)return
  lastSignature=signature;lastRefresh=System.currentTimeMillis();refreshing=true;catalogStatus="正在按观影偏好更新在线片单…"
  val existing=catalog.toList()
  Thread {
   val found=mutableListOf<MemoryFilm>()
   for(genre in targets) {
    try {
     val connection=java.net.URL("https://itunes.apple.com/hk/rss/topmovies/limit=50/genre="+genre+"/json").openConnection() as java.net.HttpURLConnection
     connection.connectTimeout=15000;connection.readTimeout=15000
     val root=try{JSONObject(connection.inputStream.bufferedReader().use{it.readText()})}finally{connection.disconnect()}
     val entries=root.getJSONObject("feed").getJSONArray("entry")
     for(i in 0 until entries.length()) {
      val e=entries.getJSONObject(i);val id=e.getJSONObject("id");val name=e.optJSONObject("im:name")?.optString("label").orEmpty()
      val year=e.optJSONObject("im:releaseDate")?.optString("label")?.take(4)?.toIntOrNull()?:0
      val synopsis=e.optJSONObject("summary")?.optString("label").orEmpty();val source=id.optString("label")
      val url=java.net.URI(source)
      if(name.isBlank() || year<1900 || synopsis.isBlank() || url.scheme!="https" || url.host!="itunes.apple.com")continue
      if(FilmTaste.match(name+" "+year,existing)!=null)continue
      found.add(MemoryFilm("apple:"+id.getJSONObject("attributes").getString("im:id"),name,year,emptyList(),genres.filterValues{it==genre}.keys.toList(),synopsis.take(220),source))
     }
    }catch(e:Exception){}
   }
   android.os.Handler(android.os.Looper.getMainLooper()).post {
    refreshing=false
    if(found.isEmpty()){catalogStatus="在线片单暂不可用，继续使用已保存片单";done();return@post}
    val merged=catalog.associateBy{it.id}.toMutableMap()
    found.forEach{f->val old=merged[f.id];merged[f.id]=if(old==null)f else f.copy(tags=(f.tags+old.tags).distinct().sorted())}
    catalog=merged.values.toList()
    val cached=JSONArray();catalog.filter{it.sourceURL!=null}.takeLast(400).forEach{f->cached.put(JSONObject().put("id",f.id).put("title",f.title).put("year",f.year).put("aliases",JSONArray(f.aliases)).put("tags",JSONArray(f.tags)).put("synopsis",f.synopsis).put("sourceURL",f.sourceURL))}
    prefs.edit().putString("catalog",cached.toString()).apply();lastSignature=signature;lastRefresh=System.currentTimeMillis()
    catalogStatus="在线片单已更新 · 共 "+catalog.size+" 部；离线沿用缓存";done()
   }
  }.apply{isDaemon=true;name="film-catalog-refresh"}.start()
 }
 private fun strings(a:JSONArray)=(0 until a.length()).map{a.getString(it)}
 private fun save() {
  if(storageError.isNotEmpty())return
  val a=JSONArray();records.forEach{a.put(JSONObject().put("id",it.id).put("title",it.title).put("completedAt",it.completedAt).put("rating",it.rating?:JSONObject.NULL).put("tags",JSONArray(it.tags)).put("note",it.note))}
  if(!prefs.edit().putString("archive",JSONObject().put("records",a).put("dismissed",JSONArray(dismissed.toList())).toString()).commit())storageError="观影档案保存失败，请检查设备空间。"
 }
 fun record(title:String) {
  val cleaned=FilmTaste.clean(title)
  if(storageError.isNotEmpty() || cleaned.isEmpty() || cleaned.lowercase() in listOf("一起看电影","本地影片","电影","movie","bunny"))return
  val f=FilmTaste.match(title,catalog);val id=f?.id?:"title:"+FilmTaste.key(cleaned)
  if(records.any{it.id==id})return
  records=listOf(MemoryRecord(id,f?.title?:cleaned,System.currentTimeMillis(),tags=f?.tags?:emptyList()))+records;save();refreshCatalog()
 }
 fun feedback(id:String,rating:Int?,tags:List<String>,note:String){records=records.map{if(it.id==id)it.copy(rating=rating,tags=tags,note=note.take(500))else it};save();refreshCatalog()}
 fun forget(id:String){records=records.filter{it.id!=id};save()}
 fun show(title:String) {
  val body=LinearLayout(context).apply{orientation=LinearLayout.VERTICAL;setPadding(24,12,24,24)}
  fun text(s:String,size:Float=14f){body.addView(TextView(context).apply{text=s;textSize=size;setPadding(0,12,0,8)})}
  fun button(s:String,action:()->Unit){body.addView(Button(context).apply{text=s;setOnClickListener{action()}})}
  val scroll=ScrollView(context).apply{addView(body)}
  val dialog=AlertDialog.Builder(context).setTitle("观影档案与推荐").setView(scroll).setPositiveButton("完成",null).create()
  fun refresh(){dialog.dismiss();show(title)}
  text("看完自动保存。删除片源仍保留；更新 App 会保留。档案属于这台设备，卸载或清除 App 数据会移除。",12f)
  if(storageError.isNotEmpty())text(storageError)
  button("标记当前影片已看"){record(title);refresh()}
  val input=EditText(context).apply{hint="补记以前看过的电影（可带年份）"};body.addView(input)
  button("补记已看"){record(input.text.toString());refresh()}
  text("为你推荐",20f)
  text(catalogStatus,12f)
  button("更新在线片单"){refreshCatalog(true){if(dialog.isShowing)refresh()}}
  if(records.isEmpty())text("看完或补记一部电影后开始推荐，评分能帮助区分喜欢和不喜欢。")
  FilmTaste.suggestions(records,catalog,dismissed).forEach{s->
   text(s.film.title+" · "+s.film.year,18f)
   text(s.film.tags.joinToString(" · "),12f)
   s.film.sourceURL?.let{source->button("影片资料来自 Apple"){try{context.startActivity(android.content.Intent(android.content.Intent.ACTION_VIEW,android.net.Uri.parse(source)))}catch(e:Exception){}}}
   text("讲什么\n"+s.film.synopsis+"\n\n为什么推荐\n"+s.reason+"\n\n与你的喜好关联\n"+s.connection)
   button("这部已看过"){record(s.film.title);refresh()}
   button("暂不推荐"){dismissed=dismissed+s.film.id;save();refresh()}
  }
  button("恢复暂不推荐的影片"){dismissed=emptySet();save();refresh()}
  text("从内置与 Apple 在线片单中挑选。4 至 5 分增加关联推荐，1 至 2 分减少关联推荐。",12f)
  text("我的观影档案 · "+records.size+" 部",20f)
  records.forEach{r->button(r.title+" · "+(r.rating?.let{it.toString()+"/5"}?:"尚未评分")){edit(r){refresh()}}}
  dialog.show()
  refreshCatalog{if(dialog.isShowing)refresh()}
 }
 private fun edit(r:MemoryRecord,updated:()->Unit) {
  val body=LinearLayout(context).apply{orientation=LinearLayout.VERTICAL;setPadding(24,12,24,12)}
  val rating=Spinner(context).apply{adapter=ArrayAdapter(context,android.R.layout.simple_spinner_dropdown_item,listOf("暂不评分","1 不喜欢","2 不太喜欢","3 一般","4 喜欢","5 很喜欢"));setSelection(r.rating?:0)};body.addView(rating)
  val note=EditText(context).apply{hint="喜欢或不喜欢的具体原因（备忘）";setText(r.note)};body.addView(note)
  body.addView(TextView(context).apply{text="选择这部影片实际具有的特点，推荐结合评分学习这些标签。文字原因作为备忘保存。"})
  val selected=r.tags.toMutableSet()
  FilmTaste.tags.forEach{t->body.addView(CheckBox(context).apply{text=t;isChecked=t in selected;setOnCheckedChangeListener{_,checked->if(checked)selected.add(t)else selected.remove(t)}})}
  AlertDialog.Builder(context).setTitle(r.title).setView(ScrollView(context).apply{addView(body)}).setPositiveButton("保存"){_,_->feedback(r.id, rating.selectedItemPosition.takeIf{it>0},FilmTaste.tags.filter{it in selected},note.text.toString());updated()}.setNegativeButton("取消",null).setNeutralButton("删除记忆"){_,_->
   AlertDialog.Builder(context).setTitle("仅删除观影记忆，片源不受影响").setPositiveButton("删除"){_,_->forget(r.id);updated()}.setNegativeButton("取消",null).show()
  }.show()
 }
}
