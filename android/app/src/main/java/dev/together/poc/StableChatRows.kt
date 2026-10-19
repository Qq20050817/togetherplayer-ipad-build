package dev.together.poc

/** Reuse unchanged UI rows and evict entries outside the visible history window. */
class StableChatRows<K,S,V> {
 private data class Entry<S,V>(val signature:S,val value:V)
 private var rows=HashMap<K,Entry<S,V>>()
 fun <T> reconcile(items:List<T>,key:(T)->K,signature:(T)->S,create:(T)->V):List<V> {
  val next=HashMap<K,Entry<S,V>>(items.size)
  val result=items.map {item->
   val id=key(item);val stamp=signature(item)
   val row=rows[id]?.takeIf {it.signature==stamp} ?: Entry(stamp,create(item))
   next[id]=row;row.value
  }
  rows=next
  return result
 }
 fun clear(){rows.clear()}
 internal val size get()=rows.size
}
