/// Whether a trigger was performed, or ignored because the controller was in a state that does not accept it.
/// Ignored triggers are logged and never queued.
public enum TriggerResult<Value: Sendable>: Sendable {
    case performed(Value)
    case ignored(currentState: SessionState)
}

extension TriggerResult: Equatable where Value: Equatable {}
