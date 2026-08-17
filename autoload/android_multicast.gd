extends Node

## Невелика platform boundary для Android Wi-Fi multicast filtering.
## На Windows/macOS/Linux/iOS цей autoload є повним no-op. На Android він
## бере WifiManager.MulticastLock лише поки хоча б один discovery owner
## (host або scan) реально його потребує.

const LOCK_TAG := "MultiplayerTemplateDiscovery"

var _multicast_lock
var _owners: Dictionary = {}


func is_available() -> bool:
	return OS.get_name() == "Android" and Engine.has_singleton("AndroidRuntime")


func acquire(owner: String) -> void:
	if not is_available() or _owners.has(owner):
		return

	if not _ensure_lock():
		return

	_owners[owner] = true
	if not _multicast_lock.isHeld():
		_multicast_lock.acquire()


func release(owner: String) -> void:
	if not _owners.erase(owner):
		return

	if _owners.is_empty():
		_release_lock()


func release_all() -> void:
	_owners.clear()
	_release_lock()


func _exit_tree() -> void:
	release_all()


func _ensure_lock() -> bool:
	if _multicast_lock:
		return true

	var android_runtime = Engine.get_singleton("AndroidRuntime")
	if android_runtime == null:
		return false

	var application_context = android_runtime.getApplicationContext()
	var wifi_manager = application_context.getSystemService("wifi")
	if wifi_manager == null:
		return false

	_multicast_lock = wifi_manager.createMulticastLock(LOCK_TAG)
	_multicast_lock.setReferenceCounted(false)
	return true


func _release_lock() -> void:
	if _multicast_lock and _multicast_lock.isHeld():
		_multicast_lock.release()
