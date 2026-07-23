extends RefCounted
class_name SimulationClock
## Pause-safe deterministic clock advanced only by authoritative simulation delta.

const USEC_PER_SECOND: float = 1_000_000.0

var elapsed_usec: int = 0
var _fractional_usec: float = 0.0


func reset() -> void:
	elapsed_usec = 0
	_fractional_usec = 0.0


func advance(delta: float) -> int:
	if delta <= 0.0:
		return elapsed_usec
	var pending_usec := _fractional_usec + delta * USEC_PER_SECOND
	var whole_usec := floori(pending_usec)
	elapsed_usec += whole_usec
	_fractional_usec = pending_usec - float(whole_usec)
	return elapsed_usec
