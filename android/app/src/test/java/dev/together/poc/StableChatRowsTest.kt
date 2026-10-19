package dev.together.poc
import org.junit.Assert.*
import org.junit.Test

class StableChatRowsTest {
 data class Row(val id:Long,val text:String,val width:Int=300)
 @Test fun newMessageBuildsOneRowAndKeepsExistingRows() {
  val cache=StableChatRows<Long,Row,Any>();var creates=0
  fun render(rows:List<Row>)=cache.reconcile(rows,{it.id},{it}){creates++;Any()}
  val first=(1L..100L).map{Row(it,"message $it")};val before=render(first)
  val after=render(first.drop(1)+Row(101,"new"))
  assertEquals(101,creates);assertEquals(100,cache.size)
  for(i in 0 until 99)assertSame(before[i+1],after[i])
  repeat(100){assertEquals(after,render(first.drop(1)+Row(101,"new")))}
  assertEquals(101,creates)
 }
 @Test fun changedTextOrLayoutRebuildsOnlyAffectedRow() {
  val cache=StableChatRows<Long,Row,Any>();var creates=0
  fun render(rows:List<Row>)=cache.reconcile(rows,{it.id},{it}){creates++;Any()}
  val before=render(listOf(Row(1,"one"),Row(2,"two")))
  val after=render(listOf(Row(1,"one",500),Row(2,"two")))
  assertNotSame(before[0],after[0]);assertSame(before[1],after[1]);assertEquals(3,creates)
  val edited=render(listOf(Row(1,"edited",500),Row(2,"two")))
  assertNotSame(after[0],edited[0]);assertSame(after[1],edited[1])
 }
 @Test fun reorderingReusesRowsAndEmptyHistoryReleasesEverything() {
  val cache=StableChatRows<Long,Row,Any>()
  fun render(rows:List<Row>)=cache.reconcile(rows,{it.id},{it}){Any()}
  val first=render(listOf(Row(1,"one"),Row(2,"two")))
  val reordered=render(listOf(Row(2,"two"),Row(1,"one")))
  assertSame(first[1],reordered[0]);assertSame(first[0],reordered[1])
  render(emptyList());assertEquals(0,cache.size)
  assertNotSame(first[0],render(listOf(Row(1,"one")))[0])
 }
}
