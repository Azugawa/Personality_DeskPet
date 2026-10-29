extends SceneTree
## Reminder scheduler tests: add, fire, catch-up, snooze, cancel, validation.

const ReminderScript := preload("res://scripts/services/reminder_service.gd")

var _root_dir := ""


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	_root_dir = OS.get_environment("TEMP").path_join("deskpet_reminders_%d" % Time.get_ticks_usec())
	await _test_add_fire_snooze_dismiss()
	await _test_catch_up_and_expiry()
	await _test_validation()
	JsonStore.remove_tree(_root_dir)
	print("PASS: reminders add/fire/catch-up/snooze/validation")
	quit()


func _new_service(file_name: String, clock: AssistantClock, grace_hours := 24) -> Node:
	var service = ReminderScript.new()
	root.add_child(service)
	service.setup(_root_dir.path_join(file_name), clock, grace_hours, 7, 200, 200)
	service.set_process(false)
	return service


func _free_service(service: Node) -> void:
	service.queue_free()
	await process_frame


func _test_add_fire_snooze_dismiss() -> void:
	var clock := AssistantClock.new()
	clock.set_fixed_now(1793311200)
	var service := _new_service("basic.json", clock)
	var added: Dictionary = service.add_after("喝水", 300)
	assert(bool(added.get("ok", false)))
	var id := str((added.get("reminder", {}) as Dictionary).get("id", ""))
	assert(service.pending_count() == 1)
	assert(service.list_pending().size() == 1)
	clock.advance_for_test(301)
	service.tick()
	assert(service.pending_count() == 0)
	var queued: Array = service.take_pending()
	assert(queued.size() == 1)
	assert(str(queued[0].get("text", "")) == "喝水")
	assert(str(service.find_reminder(id).get("status", "")) == "fired")
	await _free_service(service)
	# Not presented yet: a restart must queue it again.
	var second := _new_service("basic.json", clock)
	var again: Array = second.take_pending()
	assert(again.size() == 1)
	second.mark_presented(id)
	await _free_service(second)
	var third := _new_service("basic.json", clock)
	assert(third.take_pending().is_empty())
	# Snooze the fired reminder, then reach it again.
	assert(third.snooze(id, 60))
	clock.advance_for_test(61)
	third.tick()
	assert(third.take_pending().size() == 1)
	third.dismiss(id)
	assert(str(third.find_reminder(id).get("status", "")) == "dismissed")
	assert(third.pending_count() == 0)
	# Cancel a pending reminder.
	var extra: Dictionary = third.add_after("交作业", 600)
	assert(str(third.find_reminder(str(extra.reminder.id)).get("status", "")) == "pending")
	assert(third.cancel(str(extra.reminder.id)))
	assert(third.pending_count() == 0)
	await _free_service(third)


func _test_catch_up_and_expiry() -> void:
	var clock := AssistantClock.new()
	clock.set_fixed_now(1793311200)
	var service := _new_service("catchup.json", clock)
	var parsed := clock.parse_local("2026-10-30 08:00")
	assert(not parsed.is_empty())
	assert(bool(service.add_at_string("早会", "2026-10-30 08:00").get("ok", false)))
	clock.advance_for_test(11 * 3600)
	var catchup := _new_service("catchup.json", clock)
	var queued: Array = catchup.take_pending()
	assert(queued.size() == 1)
	assert(bool(queued[0].get("overdue", false)))
	await _free_service(catchup)
	# Three days late: expired instead of queued.
	clock.advance_for_test(3 * 24 * 3600)
	var expired := _new_service("catchup.json", clock)
	assert(expired.take_pending().is_empty())
	assert(str(expired.find_reminder(str(queued[0].get("id", ""))).get("status", "")) == "expired")
	await _free_service(service)
	await _free_service(expired)


func _test_validation() -> void:
	var clock := AssistantClock.new()
	clock.set_fixed_now(1793311200)
	var service := _new_service("validation.json", clock)
	assert(not bool(service.add_after("", 10).get("ok", true)))
	assert(not bool(service.add_after("   ", 10).get("ok", true)))
	assert(not bool(service.add_after("过去", -100).get("ok", true)))
	assert(not bool(service.add_at_string("坏时间", "2026-02-31 08:00").get("ok", true)))
	var long_text := "字".repeat(201)
	assert(not bool(service.add_after(long_text, 10).get("ok", true)))
	assert(bool(service.add_after("正常", 10).get("ok", false)))
	await _free_service(service)
