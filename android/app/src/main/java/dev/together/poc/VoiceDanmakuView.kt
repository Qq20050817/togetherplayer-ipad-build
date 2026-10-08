package dev.together.poc
import android.content.Context
import android.view.MotionEvent
import android.view.View
import android.widget.*
import android.text.Editable
import android.text.TextWatcher

class VoiceDanmakuView(context:Context,private val voice:VoiceDanmakuController,private val connected:()->Boolean):LinearLayout(context) {
 private val status=TextView(context)
 private val start=Button(context).apply {text="启用语音弹幕";contentDescription=text;setOnClickListener {if(connected())voice.enable()}}
 private val hold=Button(context).apply {text="按住说话";contentDescription=text}
 private val close=Button(context).apply {text="关闭语音";setOnClickListener {voice.disable()}}
 private val settings=Button(context).apply {text="语音设置";setOnClickListener {showSettings()}}
 private val result=EditText(context).apply {hint="识别结果，可修改";contentDescription="语音识别结果";maxLines=4}
 private val review=LinearLayout(context)
 private val level=ProgressBar(context,null,android.R.attr.progressBarStyleHorizontal).apply {max=1000;contentDescription="麦克风输入电平"}
 private val confirm=Button(context).apply {text="确认发送";contentDescription=text;setOnClickListener {voice.preview=result.text.toString();voice.confirm()}}
 private var downY=0f
 private var held=false
 private var updating=false
 init {
  orientation=VERTICAL
  val row=LinearLayout(context);listOf(start,hold,close,settings).forEach {row.addView(it,LayoutParams(0,LayoutParams.WRAP_CONTENT,1f))};addView(row)
  status.setTextColor(0xffa2b9c8.toInt());status.textSize=12f;addView(status);addView(level)
  review.addView(result,LayoutParams(0,LayoutParams.WRAP_CONTENT,1f));review.addView(confirm);review.addView(Button(context).apply {text="取消";setOnClickListener {voice.cancel()}});addView(review)
  result.addTextChangedListener(object:TextWatcher {override fun beforeTextChanged(s:CharSequence?,start:Int,count:Int,after:Int){};override fun onTextChanged(s:CharSequence?,start:Int,before:Int,count:Int){if(!updating && voice.state==VoiceDanmakuController.State.REVIEW)voice.preview=s.toString()};override fun afterTextChanged(s:Editable?) {}})
  hold.setOnTouchListener {_,event->when(event.actionMasked){MotionEvent.ACTION_DOWN->{if(connected() && voice.state==VoiceDanmakuController.State.READY){downY=event.rawY;held=true;voice.begin();parent?.requestDisallowInterceptTouchEvent(true)};true};MotionEvent.ACTION_UP->{if(held){voice.release(event.rawY-downY < -60*resources.displayMetrics.density);held=false;parent?.requestDisallowInterceptTouchEvent(false)};true};MotionEvent.ACTION_CANCEL->{if(held){voice.release(true);held=false};true};else->true}}
  hold.setOnClickListener {if(voice.state==VoiceDanmakuController.State.RECORDING)voice.release()else if(connected())voice.begin()}
  render()
 }
 fun render(){
  val s=voice.state;status.text=voice.status
  start.visibility=if(s==VoiceDanmakuController.State.DISABLED || s==VoiceDanmakuController.State.PREPARING)VISIBLE else GONE
  start.isEnabled=connected() && s==VoiceDanmakuController.State.DISABLED
  val enabled=s!=VoiceDanmakuController.State.DISABLED && s!=VoiceDanmakuController.State.PREPARING
  hold.visibility=if(enabled)VISIBLE else GONE;close.visibility=hold.visibility;settings.visibility=hold.visibility
  hold.isEnabled=s==VoiceDanmakuController.State.RECORDING || (connected() && s==VoiceDanmakuController.State.READY)
  hold.text=if(s==VoiceDanmakuController.State.RECORDING)"松开预览"else"按住说话";settings.isEnabled=s==VoiceDanmakuController.State.READY
  review.visibility=if(s==VoiceDanmakuController.State.REVIEW)VISIBLE else GONE;confirm.isEnabled=connected()
  if(s==VoiceDanmakuController.State.REVIEW && result.text.toString()!=voice.preview){updating=true;result.setText(voice.preview);updating=false}
  level.visibility=if(s==VoiceDanmakuController.State.RECORDING)VISIBLE else GONE;level.progress=(voice.level*1000).toInt()
 }
 private fun showSettings(){
  val body=LinearLayout(context).apply {orientation=VERTICAL;setPadding(24,8,24,8)}
  val value=TextView(context);body.addView(value)
  val slider=SeekBar(context).apply {max=99;progress=((voice.threshold-0.001)*1000).toInt().coerceIn(0,99)};body.addView(slider)
  fun show(){value.text="收音阈值：%.3f".format(voice.threshold)};show()
  slider.setOnSeekBarChangeListener(object:SeekBar.OnSeekBarChangeListener {override fun onProgressChanged(s:SeekBar?,p:Int,user:Boolean){if(user){voice.threshold=(p+1)/1000.0;show()}};override fun onStartTrackingTouch(s:SeekBar?){};override fun onStopTrackingTouch(s:SeekBar?) {}})
  body.addView(TextView(context).apply {text="阈值过高会漏掉轻声，外放对白突然变响仍可能混入。推荐耳机；请核对后确认发送。"})
  val time=Spinner(context).apply {adapter=ArrayAdapter(context,android.R.layout.simple_spinner_dropdown_item,listOf("30 秒","60 秒","120 秒"));setSelection(listOf(30,60,120).indexOf(voice.maxSeconds).coerceAtLeast(0));onItemSelectedListener=object:AdapterView.OnItemSelectedListener{override fun onItemSelected(p:AdapterView<*>?,v:View?,position:Int,id:Long){voice.maxSeconds=listOf(30,60,120)[position]};override fun onNothingSelected(p:AdapterView<*>?) {}}};body.addView(time)
  val length=Spinner(context).apply {adapter=ArrayAdapter(context,android.R.layout.simple_spinner_dropdown_item,listOf("最多 120 字","最多 300 字","最多 500 字"));setSelection(listOf(120,300,500).indexOf(voice.maxCharacters).coerceAtLeast(0));onItemSelectedListener=object:AdapterView.OnItemSelectedListener{override fun onItemSelected(p:AdapterView<*>?,v:View?,position:Int,id:Long){voice.maxCharacters=listOf(120,300,500)[position]};override fun onNothingSelected(p:AdapterView<*>?) {}}};body.addView(length)
  android.app.AlertDialog.Builder(context).setTitle("语音弹幕设置").setView(body).setPositiveButton("完成",null).show()
 }
}
