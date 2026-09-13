using UnityEngine;
using UnityEngine.InputSystem;
using Salvo.Sim;

namespace Salvo.Runtime
{
    /// <summary>
    /// Turns whatever the player is holding — a touchscreen, a controller, a keyboard — into a
    /// <see cref="PlayerInput"/>.
    /// </summary>
    /// <remarks>
    /// This is the only place raw device state is read, and the only thing it produces is a
    /// command. It cannot move the player, because it has no reference to anything that could.
    /// That is the client side of the brief's rule that the server is authoritative: not a
    /// policy, but an absence of the wiring that would let a client do otherwise.
    ///
    /// <para>The command is built through <see cref="PlayerInput.Quantised"/>, which is not an
    /// optimisation. The client predicts using the quantised value and sends that same value, so
    /// the server replays bit-identical input. Predicting on the raw floats and sending the
    /// rounded ones would desynchronise on every tick.</para>
    /// </remarks>
    [AddComponentMenu("Salvo/Local Player Input")]
    public sealed class LocalPlayerInput : MonoBehaviour
    {
        [Header("Look sensitivity")]
        [Tooltip("Radians of yaw per unit of pointer delta.")]
        [SerializeField] private float lookSensitivity = 0.003f;
        [Tooltip("Radians of yaw per second at full stick deflection.")]
        [SerializeField] private float stickSensitivity = 3.2f;
        [SerializeField] private bool invertPitch;

        private ViewAngles _view;
        private byte _desiredSlot;

        public ViewAngles View => _view;

        public void ResetView(ViewAngles view) => _view = view;

        /// <summary>Builds this frame's command. Call once per simulation tick, not per frame:
        /// a command has to correspond to a tick or reconciliation has nothing to line up.</summary>
        public PlayerInput Build(int tick, float dt)
        {
            Vector2 move = ReadMove();
            ApplyLook(dt);
            InputButtons buttons = ReadButtons();
            return PlayerInput.Quantised(tick, move.x, move.y, _view, buttons, _desiredSlot);
        }

        private static Vector2 ReadMove()
        {
            var move = Vector2.zero;
            if (Gamepad.current != null) move = Gamepad.current.leftStick.ReadValue();

            // Keyboard is additive on top, so a desktop build works without a pad plugged in.
            Keyboard keyboard = Keyboard.current;
            if (keyboard != null)
            {
                if (keyboard.wKey.isPressed) move.y += 1f;
                if (keyboard.sKey.isPressed) move.y -= 1f;
                if (keyboard.dKey.isPressed) move.x += 1f;
                if (keyboard.aKey.isPressed) move.x -= 1f;
            }
            return Vector2.ClampMagnitude(move, 1f);
        }

        private void ApplyLook(float dt)
        {
            float yawDelta = 0f;
            float pitchDelta = 0f;

            Mouse mouse = Mouse.current;
            if (mouse != null)
            {
                Vector2 delta = mouse.delta.ReadValue();
                yawDelta += delta.x * lookSensitivity;
                pitchDelta += delta.y * lookSensitivity;
            }

            if (Gamepad.current != null)
            {
                Vector2 look = Gamepad.current.rightStick.ReadValue();
                // Squared response on the stick: fine aim near the centre, fast turns at the
                // edge. A linear stick is the single most common reason console aim feels bad.
                yawDelta += look.x * Mathf.Abs(look.x) * stickSensitivity * dt;
                pitchDelta += look.y * Mathf.Abs(look.y) * stickSensitivity * dt;
            }

            if (invertPitch) pitchDelta = -pitchDelta;
            _view = _view.RotatedBy(pitchDelta, yawDelta);
        }

        private InputButtons ReadButtons()
        {
            var buttons = InputButtons.None;
            Keyboard keyboard = Keyboard.current;
            Mouse mouse = Mouse.current;
            Gamepad pad = Gamepad.current;

            bool Down(bool a, bool b) => a || b;

            if (Down(mouse != null && mouse.leftButton.isPressed,
                     pad != null && pad.rightTrigger.isPressed)) buttons |= InputButtons.Fire;
            if (Down(mouse != null && mouse.rightButton.isPressed,
                     pad != null && pad.leftTrigger.isPressed)) buttons |= InputButtons.Aim;
            if (Down(keyboard != null && keyboard.spaceKey.isPressed,
                     pad != null && pad.buttonSouth.isPressed)) buttons |= InputButtons.Jump;
            if (Down(keyboard != null && keyboard.leftCtrlKey.isPressed,
                     pad != null && pad.buttonEast.isPressed)) buttons |= InputButtons.Crouch;
            if (Down(keyboard != null && keyboard.leftShiftKey.isPressed,
                     pad != null && pad.leftStickButton.isPressed)) buttons |= InputButtons.Walk;
            if (Down(keyboard != null && keyboard.rKey.isPressed,
                     pad != null && pad.buttonWest.isPressed)) buttons |= InputButtons.Reload;
            if (Down(keyboard != null && keyboard.eKey.isPressed,
                     pad != null && pad.buttonNorth.isPressed)) buttons |= InputButtons.Use;

            if (keyboard != null)
            {
                if (keyboard.digit1Key.isPressed) _desiredSlot = 0;
                else if (keyboard.digit2Key.isPressed) _desiredSlot = 1;
                else if (keyboard.digit3Key.isPressed) _desiredSlot = 2;
            }
            return buttons;
        }
    }
}
