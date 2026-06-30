extends Node

# The PortraitGenerator modules are created before the character panel exists.
# Retry the vision UI attachment after startup and whenever the panel is recreated.

var _retry_timer = null

func update():
    _retry_attach()

func _ready():
    _retry_timer = Timer.new()
    _retry_timer.set_wait_time(1.0)
    _retry_timer.set_one_shot(false)
    _retry_timer.connect("timeout", self, "_retry_attach")
    add_child(_retry_timer)
    _retry_timer.start()
    call_deferred("_retry_attach")

func _retry_attach():
    var vision_ui = modding_core.modules.PortraitGenerator_vision_ui
    if vision_ui == null:
        return
    vision_ui.update()
