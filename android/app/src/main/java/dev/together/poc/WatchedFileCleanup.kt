package dev.together.poc

import android.content.ContentResolver
import android.net.Uri
import android.provider.DocumentsContract
import android.system.Os
import android.system.OsConstants
import java.io.IOException

// The tree grant is requested explicitly. No broad storage permission or path guessing.
class WatchedFileCleanup(private val resolver:ContentResolver) {
 data class Physical(val device:Long,val inode:Long,val size:Long,val modified:Long)
 data class Stamp(val documentId:String,val name:String,val size:Long,val modified:Long,val physical:Physical?)
 data class File(val uri:Uri,val stamp:Stamp,val movie:Boolean) {val name get()=stamp.name}
 data class Plan(val source:Uri,val tree:Uri,val files:List<File>)
 data class Result(val deleted:List<String>,val failed:List<String>)
 private fun documentId(uri:Uri)=runCatching{DocumentsContract.getDocumentId(uri)}.getOrNull()
 private fun physical(uri:Uri):Physical?=runCatching {
  resolver.openFileDescriptor(uri,"r")?.use {fd->
   val s=Os.fstat(fd.fileDescriptor)
   if(OsConstants.S_ISREG(s.st_mode) && s.st_ino!=0L)Physical(s.st_dev,s.st_ino,s.st_size,s.st_mtime)else null
  }
 }.getOrNull()
 private fun read(uri:Uri):Stamp {
  val projection=arrayOf(DocumentsContract.Document.COLUMN_DOCUMENT_ID,DocumentsContract.Document.COLUMN_DISPLAY_NAME,DocumentsContract.Document.COLUMN_SIZE,DocumentsContract.Document.COLUMN_LAST_MODIFIED,DocumentsContract.Document.COLUMN_MIME_TYPE)
  return resolver.query(uri,projection,null,null,null)?.use {c->
   if(!c.moveToFirst() || c.getString(4)==DocumentsContract.Document.MIME_TYPE_DIR)throw IOException("不支持删除文件夹")
   Stamp(c.getString(0),c.getString(1),if(c.isNull(2))-1 else c.getLong(2),if(c.isNull(3))0 else c.getLong(3),physical(uri))
  } ?: throw IOException("无法读取文件信息")
 }
 private fun sameSource(source:Uri,stamp:Stamp,candidate:Uri,other:Stamp):Boolean {
  if(stamp.name!=other.name)return false
  if(source.authority==candidate.authority && documentId(source)==other.documentId)return stamp.size==other.size && stamp.modified==other.modified
  return stamp.physical!=null && stamp.physical==other.physical
 }
 fun plan(source:Uri,tree:Uri,importedSubtitle:Uri?):Plan {
  if(!DocumentsContract.isTreeUri(tree) || source.scheme!="content")throw IOException("请选择系统文件夹授权")
  val original=read(source)
  val parent=DocumentsContract.getTreeDocumentId(tree)
  val children=DocumentsContract.buildChildDocumentsUriUsingTree(tree,parent)
  val candidates=mutableListOf<File>()
  var count=0
  resolver.query(children,arrayOf(DocumentsContract.Document.COLUMN_DOCUMENT_ID,DocumentsContract.Document.COLUMN_DISPLAY_NAME,DocumentsContract.Document.COLUMN_MIME_TYPE,DocumentsContract.Document.COLUMN_FLAGS),null,null,null)?.use {c->
   while(c.moveToNext()) {
    if(++count>2000)throw IOException("文件过多，请选择具体的影片文件夹")
    if(c.getString(2)==DocumentsContract.Document.MIME_TYPE_DIR)continue
    val id=c.getString(0);val name=c.getString(1)
    val explicit=importedSubtitle?.authority==tree.authority && documentId(importedSubtitle)==id
    if(name!=original.name && !CleanupNamePolicy.associatedSubtitle(name,original.name) && !explicit)continue
    val uri=DocumentsContract.buildDocumentUriUsingTree(tree,id)
    val stamp=read(uri)
    val movie=sameSource(source,original,uri,stamp)
    if(!movie && !CleanupNamePolicy.isSubtitle(name))continue
    if(!movie && !explicit && !CleanupNamePolicy.associatedSubtitle(name,original.name))continue
    if(c.getInt(3) and DocumentsContract.Document.FLAG_SUPPORTS_DELETE == 0)throw IOException("文件夹中的 $name 不支持删除，请在系统文件管理器处理")
    candidates.add(File(uri,stamp,movie))
   }
  } ?: throw IOException("无法读取所选文件夹")
  if(candidates.count{it.movie}!=1)throw IOException("这里没有当前正在观看的原始文件，请选择正确文件夹；同名文件不会被当成当前影片")
  return Plan(source,tree,candidates.sortedWith(compareByDescending<File>{it.movie}.thenBy{it.name}))
 }
 fun remove(plan:Plan,selected:List<File>):Result {
  val deleted=mutableListOf<String>();val failed=mutableListOf<String>()
  val allowed=plan.files.associateBy{it.uri}
  for(file in selected) {
   try {
    if(allowed[file.uri]!=file || file.uri.authority!=plan.tree.authority)throw IOException("文件不属于已确认清单")
    val current=read(file.uri)
    if(current!=file.stamp)throw IOException("文件已变化，未删除，请重新检查")
    if(!DocumentsContract.deleteDocument(resolver,file.uri))throw IOException("系统未允许删除")
    deleted.add(file.name)
   } catch(e:Exception){failed.add("${file.name}：${e.localizedMessage ?: "删除失败"}")}
  }
  return Result(deleted,failed)
 }
}
