class_name TCGBattleLogPanel
extends Control
## Stage 5: Reusable Battle Log Panel Component
## Direct port of PythonTCG/ui/match.py `_draw_battle_log`.
## Renders recent log lines from TCGGameState.log with color coding for reactions,
## damage, healing, skills, and round transitions.

var log_entries: Array[String] = []


func _init() -> void:
	custom_minimum_size = Vector2(160, 148)
	size = Vector2(160, 148)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func setup(p_logs: Array[String]) -> void:
	log_entries = p_logs.duplicate()
	queue_redraw()


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	TCGTheme.draw_rounded_box(
		self,
		r,
		Color(0.05, 0.09, 0.14, 0.84),
		TCGTheme.GOLD_D,
		10,
		1
	)
	TCGTheme.draw_text_pos(self, "BATTLE LOG", Vector2(10, 6), 10, TCGTheme.GOLD, true, true)
	draw_line(Vector2(8, 22), Vector2(r.size.x - 8, 22), TCGTheme.GOLD_D, 1.0)

	var max_lines: int = 6
	var start_idx: int = maxi(0, log_entries.size() - max_lines)
	var y: float = 26.0
	for i in range(start_idx, log_entries.size()):
		var entry: String = log_entries[i]
		var col := TCGTheme.TEXT
		if entry.begins_with("==="):
			col = TCGTheme.GOLD_L
		elif entry.contains(" triggers "):
			col = Color8(255, 196, 118)
		elif entry.contains(" takes "):
			col = TCGTheme.RED
		elif entry.contains(" heals "):
			col = TCGTheme.GREEN
		elif entry.contains(" uses "):
			col = TCGTheme.TEAL

		var short_txt := entry
		if short_txt.length() > 26:
			short_txt = short_txt.substr(0, 25) + "…"
		TCGTheme.draw_text_pos(self, short_txt, Vector2(8, y), 10, col, false, true)
		y += 19.0

