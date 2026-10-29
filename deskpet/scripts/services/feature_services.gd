extends Node
## Optional future services register here; no model credentials ship in builds.
signal reminder_due(reminder: Dictionary)
signal dialogue_requested(message: String)
signal outfit_requested(outfit_id: String)
signal game_space_requested(space_id: String)
var providers: Dictionary = {}
func register_provider(service: String, provider: Node) -> void:
	providers[service] = provider
