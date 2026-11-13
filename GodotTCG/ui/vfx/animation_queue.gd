class_name AnimationQueue
extends Node
## Phase 1 (T1.2 - T1.3): FIFO async presentation queue with parallel event groups,
## speed multipliers (1x / 1.5x / 2x / instant), skip fast-forward, busy locking,
## and post-drain resync() safety.

signal busy_changed(busy: bool)
signal resync_requested()
signal event_started(ev: GameEvent)

var _q: Array = []
var _handlers: Dictionary = {}
var _running: bool = false
var _skip_requested: bool = false
var speed: float = 1.0  # 1.0, 1.5, 2.0, or 0.0 (instant)


func is_busy() -> bool:
	return _running


func register_handler(ev_type: int, handler: Callable) -> void:
	_handlers[ev_type] = handler


func clear_handlers() -> void:
	_handlers.clear()


func set_speed(new_speed: float) -> void:
	speed = maxf(0.0, new_speed)


func scaled(duration_sec: float) -> float:
	if _skip_requested or speed <= 0.0:
		return 0.0
	return duration_sec / maxf(0.25, speed)


func skip_all() -> void:
	if not _running and _q.is_empty():
		return
	_skip_requested = true
	_q.clear()
	_running = false
	resync_requested.emit()
	busy_changed.emit(false)


func clear_queue() -> void:
	_q.clear()
	_skip_requested = false
	if _running:
		_running = false
		busy_changed.emit(false)


func push(ev: GameEvent) -> void:
	if ev == null:
		return
	_q.append(ev)
	if not _running:
		_run()


func push_many(events: Array) -> void:
	var added: bool = false
	for ev in events:
		if ev is GameEvent:
			_q.append(ev)
			added = true
	if added and not _running:
		_run()


func wait_sec(duration_sec: float) -> void:
	var d: float = scaled(duration_sec)
	if d <= 0.001 or not is_inside_tree():
		return
	var tree := get_tree()
	if tree == null:
		return
	await tree.create_timer(d).timeout


func _run() -> void:
	if _running:
		return
	_running = true
	_skip_requested = false
	busy_changed.emit(true)

	while not _q.is_empty() and not _skip_requested:
		var ev: GameEvent = _q.pop_front()
		if ev == null:
			continue
		event_started.emit(ev)
		if ev.type == GameEvent.Type.PARALLEL_GROUP:
			await _run_parallel(ev.group_events)
		elif _handlers.has(ev.type):
			var fn: Callable = _handlers[ev.type]
			if fn.is_valid():
				await fn.call(ev)

	_running = false
	_skip_requested = false
	resync_requested.emit()
	busy_changed.emit(false)


func _run_parallel(group: Array) -> void:
	if group.is_empty():
		return
	var tracker := {"remaining": 0}
	for sub in group:
		if not (sub is GameEvent):
			continue
		if _handlers.has(sub.type):
			var fn: Callable = _handlers[sub.type]
			if fn.is_valid():
				tracker["remaining"] = int(tracker["remaining"]) + 1
				_invoke_parallel_child(fn, sub, tracker)
	while int(tracker["remaining"]) > 0 and not _skip_requested and is_inside_tree():
		await get_tree().process_frame


func _invoke_parallel_child(fn: Callable, sub: GameEvent, tracker: Dictionary) -> void:
	await fn.call(sub)
	tracker["remaining"] = maxi(0, int(tracker["remaining"]) - 1)

