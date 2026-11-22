class_name CombatStatusRow
extends Control
## Phase 4 (T4.3 - T4.4): Team Combat Status Row beside the active character.
## Uses StatusIcon items, wraps at 6+ icons, and smoothly reflows positions over 0.15s.

signal status_clicked(payload: Dictionary)

const ICON_SZ: float = 30.0
const ICON_GAP: float = 8.0
const WRAP_COLS: int = 5

var _icons: Dictionary = {}   # status_name -> StatusIcon


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	custom_minimum_size = Vector2(200, 72)


func sync_statuses(statuses: Array, owner_elem: String = "Physical") -> void:
	var seen: Dictionary = {}
	for i in range(statuses.size()):
		var st = statuses[i]
		var sname := String(st.name)
		var key := "%s#%d" % [sname, i]
		seen[key] = true
		var sdef: CardDataSystem.StatusData = CardDataSystem.get_status_def(sname)
		var kind := "buff"
		if st.shield > 0 or (sdef != null and sdef.shield > 0):
			kind = "shield"
		elif sname == "Frozen" or sname == "Petrified" or sname == "Stunned":
			kind = "debuff"
		elif sname == "Dice Carryover":
			kind = "special"
		var cnt: int = st.shield if st.shield > 0 else maxi(0, st.usages)
		if cnt <= 0 and st.duration >= 0:
			cnt = st.duration
		var payload := {
			"kind": kind,
			"name": sname,
			"elem": owner_elem,
			"count": cnt,
			"status": st,
		}
		var target_pos := Vector2(
			float(i % WRAP_COLS) * (ICON_SZ + ICON_GAP),
			float(i / WRAP_COLS) * (ICON_SZ + ICON_GAP)
		)
		if _icons.has(key):
			var icon: StatusIcon = _icons[key]
			if is_instance_valid(icon):
				icon.set_count(cnt, true)
				_tween_to(icon, target_pos)
		else:
			var icon := StatusIcon.new()
			icon.size = Vector2(ICON_SZ, ICON_SZ)
			icon.position = target_pos
			icon.setup(payload)
			icon.clicked.connect(func(p: Dictionary) -> void: status_clicked.emit(p))
			add_child(icon)
			icon.pulse()
			_icons[key] = icon

	# Remove disappeared icons cleanly with reflow
	for existing_key in _icons.keys():
		if not seen.has(existing_key):
			var old_icon: StatusIcon = _icons[existing_key]
			_icons.erase(existing_key)
			if is_instance_valid(old_icon):
				old_icon.remove_animated()


func _tween_to(icon: Control, target: Vector2) -> void:
	if icon.position.is_equal_approx(target):
		return
	if is_inside_tree():
		var tw := create_tween()
		tw.tween_property(icon, "position", target, 0.15).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	else:
		icon.position = target


func get_icon_nodes() -> Array:
	var out: Array = []
	for v in _icons.values():
		if is_instance_valid(v):
			out.append(v)
	return out

