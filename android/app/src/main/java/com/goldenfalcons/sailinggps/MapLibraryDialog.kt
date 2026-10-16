package com.goldenfalcons.sailinggps

import android.content.Context
import android.widget.*
import androidx.appcompat.app.AlertDialog

/** Library operations are separate from target selection and GPS recording. */
class MapLibraryDialog(private val context: Context, private val points: () -> List<Waypoint>,
    private val state: () -> MapLibrary, private val save: (List<Waypoint>, MapLibrary) -> Unit,
    private val export: (List<Waypoint>, List<MapFeature>, String) -> Unit, private val importFile: () -> Unit) {
    private fun menu(title: String, actions: List<Pair<String,()->Unit>>) { AlertDialog.Builder(context).setTitle(title).setItems(actions.map{it.first}.toTypedArray()){_,i->actions[i].second()}.setNegativeButton("閉じる",null).show() }
    private fun groups() = (state().groups+points().map{it.group}+state().features.map{it.group}).filter{it.isNotBlank()}.distinct().sorted()
    fun show(): Unit = menu("地点・グループ・エリア",listOf(
        "KMZ / KML / JSON インポート" to importFile, "エクスポート" to { exportScope() },
        "グループ" to { groupList() }, "円エリアを作成" to { editFeature(null,"circle") },
        "囲みエリアを作成" to { editFeature(null,"area") }, "地点間の直線を作成" to { editFeature(null,"line") },
        "エリア・直線の一覧" to { featureList() }))
    private fun selected(title: String, done: (List<Waypoint>)->Unit) {
        val all=points();val order=mutableListOf<Int>()
        AlertDialog.Builder(context).setTitle(title + "（選択順に結ぶ）")
            .setMultiChoiceItems(all.map{"${it.name} [${it.group.ifEmpty{"未分類"}}]"}.toTypedArray(),BooleanArray(all.size)){_,i,checked->if(checked)order.add(i) else order.remove(i)}
            .setPositiveButton("選択完了"){_,_->done(order.map{all[it]})}.setNegativeButton("キャンセル",null).show()
    }
    private fun exportScope(): Unit = menu("出力する地点",listOf("全件" to { exportFormat(points()) },"グループ" to {
        val names=listOf("")+groups();menu("グループ",names.map{g->g.ifEmpty{"未分類"} to { exportFormat(points().filter{it.group==g},g) }})
    },"地点を選択" to { selected("出力する地点を選択"){ exportFormat(it) } }))
    private fun exportFormat(selected: List<Waypoint>, group: String?=null) {
        val ids=selected.map{it.id}.toSet()
        val features=state().features.filter{f-> if(group!=null) f.group==group else if(selected.size==points().size)true else f.waypointIds.isNotEmpty() && ids.containsAll(f.waypointIds) }
        // Include every referenced vertex so group exports remain independently editable.
        val needed=features.flatMap{it.waypointIds}.toSet();val included=(selected+points().filter{it.id in needed}).distinctBy{it.id}
        menu("ファイル形式",listOf("KMZ（地点・エリア・線）" to { export(included,features,"kmz") },"KML（地点・エリア・線）" to { export(included,features,"kml") },"JSON（地点のみ）" to { export(selected,emptyList(),"json") }))
    }
    private fun textInput(title: String, initial: String="", done:(String)->Unit) {
        val input=EditText(context).apply{setText(initial);setSingleLine(true)}
        val d=AlertDialog.Builder(context).setTitle(title).setView(input).setPositiveButton("保存",null).setNegativeButton("キャンセル",null).create()
        d.setOnShowListener { d.getButton(-1).setOnClickListener { val name=input.text.toString().trim();if(name.isBlank())input.error="入力してください" else {done(name);d.dismiss()} } };d.show()
    }
    private fun groupList(): Unit = menu("グループ",listOf("＋ 新規グループ" to { textInput("グループ名"){g->save(points(),state().copy(groups=(state().groups+g).distinct()));groupList()} },"地点の所属を変更" to { selected("移動する地点"){selected->
        val ids=selected.map{it.id}.toSet();val names=listOf("")+groups();menu("移動先",names.map{g->g.ifEmpty{"未分類"} to {save(points().map{if(it.id in ids)it.copy(group=g) else it},state());groupList()}})
    } })+groups().map{g->"${if(g in state().hiddenGroups)"非表示" else "表示"} · $g (${points().count{it.group==g}})" to { groupActions(g) }})
    private fun groupActions(g: String): Unit =menu(g,listOf(
        "表示 / 非表示" to {val hidden=state().hiddenGroups.toMutableSet();if(!hidden.add(g))hidden.remove(g);save(points(),state().copy(hiddenGroups=hidden));groupList()},
        "名前を変更" to {textInput("グループ名",g){n->save(points().map{if(it.group==g)it.copy(group=n)else it},state().copy(groups=(groups().filter{it!=g}+n).distinct(),hiddenGroups=state().hiddenGroups.map{if(it==g)n else it}.toSet(),features=state().features.map{if(it.group==g)it.copy(group=n)else it}));groupList()}},
        "グループを削除（地点は未分類へ）" to {AlertDialog.Builder(context).setTitle("グループを削除しますか？").setMessage("地点と図形は残して未分類に移します。").setPositiveButton("削除"){_,_->save(points().map{if(it.group==g)it.copy(group="")else it},state().copy(groups=groups().filter{it!=g},hiddenGroups=state().hiddenGroups-g,features=state().features.map{if(it.group==g)it.copy(group="")else it}));groupList()}.setNegativeButton("キャンセル",null).show()}))
    private fun featureList(): Unit = menu("エリア・直線",state().features.map{f->"${if(f.visible)"表示" else "非表示"} · ${f.name}" to {menu(f.name,listOf(
        "編集" to {editFeature(f,f.kind)},"表示 / 非表示" to {save(points(),state().copy(features=state().features.map{if(it.id==f.id)it.copy(visible=!it.visible)else it}));featureList()},
        "削除" to {AlertDialog.Builder(context).setTitle("${f.name}を削除しますか？").setPositiveButton("削除"){_,_->save(points(),state().copy(features=state().features.filter{it.id!=f.id}));featureList()}.setNegativeButton("キャンセル",null).show()}))}})
    private fun editFeature(original: MapFeature?, kind: String) {
        val name=EditText(context).apply{hint="名前";setText(original?.name ?: if(kind=="circle")"円エリア" else if(kind=="area")"囲みエリア" else "直線")}
        val radius=EditText(context).apply{hint="半径（m）";inputType=8194;setText((original?.radius ?: 200.0).toString())}
        val color=EditText(context).apply{hint="#RRGGBB";setText(original?.color ?: "#00AAFF")}
        val group=Spinner(context);val names=listOf("")+groups();group.adapter=ArrayAdapter(context,android.R.layout.simple_spinner_dropdown_item,names.map{it.ifEmpty{"未分類"}});group.setSelection(names.indexOf(original?.group ?: "").coerceAtLeast(0))
        var ids=original?.waypointIds ?: emptyList();val chosen=TextView(context)
        fun update(){chosen.text=if(ids.isEmpty())"地点未選択（編集時は元の座標を維持）" else ids.mapNotNull{id->points().firstOrNull{it.id==id}?.name}.joinToString(" → ")};update()
        val container=LinearLayout(context).apply {
            orientation=LinearLayout.VERTICAL;setPadding(24,12,24,12)
            addView(name);if(kind=="circle")addView(radius);addView(color);addView(group);addView(chosen)
            addView(Button(context).apply {
                text=if(kind=="circle")"中心の地点を選ぶ" else "結ぶ順に地点を選ぶ"
                setOnClickListener { selected("地点選択") { items -> ids=items.map{w->w.id};update() } }
            })
        }
        val d=AlertDialog.Builder(context).setTitle("エリア・直線").setView(ScrollView(context).apply{addView(container)}).setPositiveButton("保存",null).setNegativeButton("キャンセル",null).create()
        d.setOnShowListener{d.getButton(-1).setOnClickListener{runCatching{
            require(kind!="circle" || (if(ids.isEmpty())original?.coordinates?.size ?: 0 else ids.size)==1){"円の中心は1地点を選んでください"}
            val f=MapFeature(id=original?.id ?: java.util.UUID.randomUUID().toString(),name=name.text.toString().trim(),kind=kind,waypointIds=ids,coordinates=if(ids.isEmpty())original?.coordinates ?: emptyList() else emptyList(),radius=radius.text.toString().toDouble(),color=color.text.toString().uppercase(),group=names[group.selectedItemPosition],visible=original?.visible ?: true);f.validate()
            save(points(),state().copy(features=state().features.filter{it.id!=f.id}+f));d.dismiss()
        }.onFailure{Toast.makeText(context,it.message,Toast.LENGTH_LONG).show()}}};d.show()
    }
}
