extends Node2D

const ANIMATIONS: Array[StringName] = [&"idle", &"move", &"attack", &"death"]
var animation_index := 0

@onready var sprites: Array[AnimatedSprite2D] = [$Bear, $SmallBoar, $HornedBlob]


func _ready() -> void:
    _play_current()


func _unhandled_input(event: InputEvent) -> void:
    if event.is_action_pressed("ui_accept"):
        _next_animation()


func _on_cycle_timer_timeout() -> void:
    _next_animation()


func _next_animation() -> void:
    animation_index = (animation_index + 1) % ANIMATIONS.size()
    _play_current()


func _play_current() -> void:
    var animation_name := ANIMATIONS[animation_index]
    for sprite in sprites:
        sprite.play(animation_name)
    $AnimationName.text = "Animation: " + String(animation_name).to_upper() + "  |  SPACE to switch"
