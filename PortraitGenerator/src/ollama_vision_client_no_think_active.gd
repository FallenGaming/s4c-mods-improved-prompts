extends "ollama_vision_client_no_think.gd"

const CLIENT_VERSION = "no-think-v5"

func _ready():
    ._ready()
    print("[PortraitGenerator][OutfitVision] Active client: %s" % CLIENT_VERSION)
