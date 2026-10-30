extends Node
## Двойник для тестов: пересылает все события ввода в cb (до остальных обработчиков)
var cb: Callable


func _input(event: InputEvent) -> void:
	cb.call(event)
