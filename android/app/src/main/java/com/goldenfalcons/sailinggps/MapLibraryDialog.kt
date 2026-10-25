package com.goldenfalcons.sailinggps

import android.content.Context
import android.widget.*
import androidx.appcompat.app.AlertDialog

/** Library operations are separate from target selection and GPS recording. */
class MapLibraryDialog(private val context: Context, private val points: () -> List<Waypoint>,
    private val state: () -> MapLibrary, private val save: (List<Waypoint>, MapLibrary) -> Unit,
    private val export: (List<Waypoint>, List<MapFeature>, String) -> Unit, private val importFile: () -> Unit) {
    private fun menu(title: String, actions: List<Pair<String,()->Unit>>) { AlertDialog.Builder(context).setTitle(title).setItems(actions.map{it.first}.toTypedArray()){_,i->actions[i].second()}.setNegativeButton("閉じる",null).show() }
    private fun groups() = (listOf("メインフォルダ") + state().groups+points().map{it.group}+state().features.map{it.group}).filter{it.isNotBlank()}.distinct().sorted()
    fun show(): Unit = if(BuildConfig.DEBUG && (context as? android.app.Activity)?.intent?.getBooleanExtra("previewCircleEditor",false)==true) editFeature(points().firstOrNull()?.let{MapFeature(name=it.name,kind="circle",waypointIds=listOf(it.id))},"circle") else menu("地点・グループ・エリア",listOf(
        "KMZ / KML / JSON インポート" to importFile, "エクスポート" to { exportScope() },
        "グループ" to { groupList() }, "円エリアを作成" to { editFeature(null,"circle") },
        "囲みエリアを作成" to { editFeature(null,"area") }, "地点間の直線を作成" to { editFeature(null,"line") },
        "エリア・直線の一覧" to { featureList() }))
    private fun selected(title: String, source: List<Waypoint> = points(), done: (List<Waypoint>)->Unit) {
        val all=source;val order=mutableListOf<Int>()
        AlertDialog.Builder(context).setTitle(title + "（選択順に結ぶ）")
            .setMultiChoiceItems(all.map{"${it.name} [${it.group.ifEmpty{"メインフォルダ"}}]"}.toTypedArray(),BooleanArray(all.size)){_,i,checked->if(checked)order.add(i) else order.remove(i)}
            .setPositiveButton("選択完了"){_,_->done(order.map{all[it]})}.setNegativeButton("キャンセル",null).show()
    }
    private fun exportScope(): Unit = menu("出力する地点",listOf("全件" to { exportFormat(points()) },"グループ" to {
        val names=listOf("")+groups();menu("グループ",names.map{g->g.ifEmpty{"メインフォルダ"} to { exportFormat(points().filter{it.group==g},g) }})
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
    private fun groupList(): Unit = menu("グループ",listOf("＋ 新規グループ" to { textInput("グループ名"){g->save(points(),state().copy(groups=(state().groups+g).distinct(),groupColors=state().groupColors+ (g to WaypointFolderColors.color(g,state()))));groupList()} },"地点の所属を変更" to { selected("移動する地点"){selected->
        val ids=selected.map{it.id}.toSet();val names=listOf("")+groups();menu("移動先",names.map{g->g.ifEmpty{"メインフォルダ"} to {save(points().map{if(it.id in ids)it.copy(group=g) else it},state());groupList()}})
    } })+groups().map{g->"${if(g in state().hiddenGroups)"非表示" else "表示"} · $g (${points().count{it.group==g}})" to { groupActions(g) }})
    private fun groupActions(g: String): Unit =menu(g,listOf(
        "表示 / 非表示" to {val hidden=state().hiddenGroups.toMutableSet();if(!hidden.add(g))hidden.remove(g);save(points(),state().copy(hiddenGroups=hidden));groupList()},
        "フォルダの既定色" to { chooseFolderColor(g) },
        "名前を変更" to {textInput("グループ名",g){n->val colors=state().groupColors.toMutableMap();colors.remove(g)?.let{colors[n]=it};save(points().map{if(it.group==g)it.copy(group=n)else it},state().copy(groups=(groups().filter{it!=g}+n).distinct(),hiddenGroups=state().hiddenGroups.map{if(it==g)n else it}.toSet(),features=state().features.map{if(it.group==g)it.copy(group=n)else it},groupColors=colors));groupList()}},
        "グループを削除（地点は未分類へ）" to {AlertDialog.Builder(context).setTitle("グループを削除しますか？").setMessage("地点と図形は残して未分類に移します。").setPositiveButton("削除"){_,_->save(points().map{if(it.group==g)it.copy(group="メインフォルダ")else it},state().copy(groups=groups().filter{it!=g},hiddenGroups=state().hiddenGroups-g,features=state().features.map{if(it.group==g)it.copy(group="メインフォルダ")else it},groupColors=state().groupColors-g));groupList()}.setNegativeButton("キャンセル",null).show()}))

    private fun chooseFolderColor(group: String) {
        val palette=WaypointFolderColors.palette
        val labels=palette.map{ "${it.first}  ${it.second}" }.toTypedArray()
        AlertDialog.Builder(context).setTitle("$group の既定色").setItems(labels){_,index->
            val color=palette[index].second
            save(points(),state().copy(groupColors=state().groupColors+(group to color)))
            groupList()
        }.setNegativeButton("キャンセル",null).show()
    }
    private fun featureList(): Unit = menu("エリア・直線",state().features.map{f->"${if(f.visible)"表示" else "非表示"} · ${f.name}" to {menu(f.name,listOf(
        "編集" to {editFeature(f,f.kind)},"表示 / 非表示" to {save(points(),state().copy(features=state().features.map{if(it.id==f.id)it.copy(visible=!it.visible)else it}));featureList()},
        "削除" to {AlertDialog.Builder(context).setTitle("${f.name}を削除しますか？").setPositiveButton("削除"){_,_->save(points(),state().copy(features=state().features.filter{it.id!=f.id}));featureList()}.setNegativeButton("キャンセル",null).show()}))}})
    private fun editFeature(original: MapFeature?, kind: String) {
        val name=EditText(context).apply{hint="名前";setText(original?.name ?: if(kind=="circle")"円エリア" else if(kind=="area")"囲みエリア" else "直線")}
        val radius=EditText(context).apply{hint="半径";inputType=8194;setText((original?.radius ?: 200.0).toString())}
        val unit=Spinner(context);val units=listOf("m","km","nm");val factors=listOf(1.0,1000.0,1852.0);var radiusFactor=1.0
        unit.adapter=ArrayAdapter(context,android.R.layout.simple_spinner_dropdown_item,units)
        unit.onItemSelectedListener=object:android.widget.AdapterView.OnItemSelectedListener {
            override fun onNothingSelected(parent:android.widget.AdapterView<*>?) {}
            override fun onItemSelected(parent:android.widget.AdapterView<*>?,view:android.view.View?,position:Int,id:Long) { val meters=radius.text.toString().toDoubleOrNull()?.times(radiusFactor);radiusFactor=factors[position];if(meters!=null)radius.setText((meters/radiusFactor).toString()) }
        }
        val color=EditText(context).apply{hint="#RRGGBB";setText(original?.color ?: "#00AAFF")}
        val group=Spinner(context);val names=listOf("")+groups();group.adapter=ArrayAdapter(context,android.R.layout.simple_spinner_dropdown_item,names.map{it.ifEmpty{"メインフォルダ"}});group.setSelection(names.indexOf(original?.group ?: "").coerceAtLeast(0))
        var ids=original?.waypointIds ?: emptyList();val chosen=TextView(context)
        val folder=Spinner(context);val folders=groups();folder.adapter=ArrayAdapter(context,android.R.layout.simple_spinner_dropdown_item,folders)
        val preferred=context.getSharedPreferences("display",Context.MODE_PRIVATE).getString("mainWaypointFolder","") ?: ""
        folder.setSelection(folders.indexOf(preferred).coerceAtLeast(0))
        val preview=org.osmdroid.views.MapView(context).apply { setTileSource(org.osmdroid.tileprovider.tilesource.TileSourceFactory.MAPNIK);setMultiTouchControls(true);layoutParams=LinearLayout.LayoutParams(-1,(240*context.resources.displayMetrics.density).toInt());setOnTouchListener{v,e->v.parent?.requestDisallowInterceptTouchEvent(e.action!=android.view.MotionEvent.ACTION_UP && e.action!=android.view.MotionEvent.ACTION_CANCEL);false} }
        fun drawPreview() {
            preview.overlays.clear()
            val selectedPoints=points().filter{it.id in ids}
            val visible=selectedPoints.ifEmpty{points().filter{it.group==folders.getOrNull(folder.selectedItemPosition)}}
            val meters=((radius.text.toString().toDoubleOrNull() ?: 0.0)*radiusFactor).coerceIn(0.0,1000000.0)
            val draft=MapFeature(name="preview",kind=kind,waypointIds=ids,coordinates=if(ids.isEmpty())original?.coordinates ?: emptyList() else emptyList(),radius=meters)
            val boundary=draft.boundary(points()).map{org.osmdroid.util.GeoPoint(it.lat,it.lon)}
            if(boundary.size>=3 && kind!="line")preview.overlays.add(org.osmdroid.views.overlay.Polygon(preview).apply{setPoints(boundary);outlinePaint.color=android.graphics.Color.CYAN;fillPaint.color=0x4000AAFF;outlinePaint.strokeWidth=3f})
            else if(boundary.size>=2)preview.overlays.add(org.osmdroid.views.overlay.Polyline(preview).apply{setPoints(boundary);outlinePaint.color=android.graphics.Color.CYAN;outlinePaint.strokeWidth=3f})
            visible.forEach{w->preview.overlays.add(org.osmdroid.views.overlay.Marker(preview).apply{position=org.osmdroid.util.GeoPoint(w.lat,w.lon);title=w.name})}
            val bounds=(boundary+visible.map{org.osmdroid.util.GeoPoint(it.lat,it.lon)}).distinct()
            preview.post { if(bounds.size>1)preview.zoomToBoundingBox(org.osmdroid.util.BoundingBox.fromGeoPoints(bounds),false,28,17.0,null) else if(bounds.isNotEmpty()){preview.controller.setZoom(16.0);preview.controller.setCenter(bounds.first())};preview.invalidate() }
        }
        fun update(){chosen.text=if(ids.isEmpty())"地点未選択（編集時は元の座標を維持）" else ids.mapNotNull{id->points().firstOrNull{it.id==id}?.name}.joinToString(" → ");if(kind=="circle")points().firstOrNull{it.id==ids.firstOrNull()}?.let{name.setText(it.name)};drawPreview()};update()
        val container=LinearLayout(context).apply {
            orientation=LinearLayout.VERTICAL;setPadding(24,12,24,12)
            addView(name);if(kind=="circle"){addView(radius);addView(unit)};addView(color);addView(group);addView(TextView(context).apply{text="作成中の地図（保存前の仮表示） · © OpenStreetMap contributors"});addView(preview);addView(TextView(context).apply{text="地点のフォルダ"});addView(folder);addView(chosen)
            addView(Button(context).apply {
                text=if(kind=="circle")"中心の地点を選ぶ" else "結ぶ順に地点を選ぶ"
                setOnClickListener {
                    val visible=points().filter{it.group==folders.getOrNull(folder.selectedItemPosition)}
                    if(kind=="circle")AlertDialog.Builder(context).setTitle("中心の地点").setItems(visible.map{it.name}.toTypedArray()){_,i->ids=listOf(visible[i].id);update()}.show()
                    else { val working=ids.toMutableList();AlertDialog.Builder(context).setTitle("結ぶ順に地点を選択").setMultiChoiceItems(visible.map{it.name}.toTypedArray(),BooleanArray(visible.size){visible[it].id in ids}){_,i,checked->if(checked){if(visible[i].id !in working)working.add(visible[i].id)}else working.remove(visible[i].id)}.setPositiveButton("選択完了"){_,_->ids=working;update()}.setNegativeButton("キャンセル",null).show() }
                }
            })
        }
        folder.onItemSelectedListener=object:AdapterView.OnItemSelectedListener { override fun onNothingSelected(parent:AdapterView<*>?){};override fun onItemSelected(parent:AdapterView<*>?,view:android.view.View?,position:Int,id:Long){drawPreview()} }
        radius.addTextChangedListener(object:android.text.TextWatcher{override fun beforeTextChanged(s:CharSequence?,start:Int,count:Int,after:Int){};override fun onTextChanged(s:CharSequence?,start:Int,before:Int,count:Int){drawPreview()};override fun afterTextChanged(s:android.text.Editable?){} })
        val d=AlertDialog.Builder(context).setTitle("エリア・直線").setView(ScrollView(context).apply{addView(container)}).setPositiveButton("保存",null).setNegativeButton("キャンセル",null).create()
        d.setOnShowListener{d.getButton(-1).setOnClickListener{runCatching{
            require(kind!="circle" || (if(ids.isEmpty())original?.coordinates?.size ?: 0 else ids.size)==1){"円の中心は1地点を選んでください"}
            val f=MapFeature(id=original?.id ?: java.util.UUID.randomUUID().toString(),name=if(kind=="circle")points().firstOrNull{it.id==ids.firstOrNull()}?.name ?: name.text.toString().trim() else name.text.toString().trim(),kind=kind,waypointIds=ids,coordinates=if(ids.isEmpty())original?.coordinates ?: emptyList() else emptyList(),radius=radius.text.toString().toDouble()*radiusFactor,color=color.text.toString().uppercase(),group=names[group.selectedItemPosition],visible=original?.visible ?: true);f.validate()
            save(points(),state().copy(features=state().features.filter{it.id!=f.id}+f));d.dismiss()
        }.onFailure{Toast.makeText(context,it.message,Toast.LENGTH_LONG).show()}}};d.setOnDismissListener{preview.onPause();preview.onDetach()};d.show();preview.onResume();drawPreview()
    }
}
