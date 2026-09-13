import Foundation

/// Source-style movement tuned for touch controls: forgiving acceleration, generous
/// step-up, and a slide that rewards good timing without being a mobility exploit.
public enum MovementSystem {
    public static let gravity: Float = 18.5
    public static let runSpeed: Float = 5.4
    public static let sprintSpeed: Float = 7.1
    public static let crouchSpeed: Float = 2.6
    public static let airSpeed: Float = 1.6
    public static let groundAcceleration: Float = 62
    public static let airAcceleration: Float = 24
    public static let friction: Float = 8.5
    public static let jumpVelocity: Float = 6.3
    public static let maxStepHeight: Float = 0.55
    public static let slideDuration: Float = 0.75
    public static let slideBoost: Float = 1.7
    public static let slideFriction: Float = 3.2
    public static let maxSlopeCos: Float = 0.55        // ~56° walkable
    public static let footstepInterval: Float = 2.1    // metres between steps
    public static let noiseRadiusWalk: Float = 14
    public static let noiseRadiusSprint: Float = 24

    public struct Context {
        public var world: CollisionWorld
        public var now: Float
        public var events: EventBus
        public init(world: CollisionWorld, now: Float, events: EventBus) {
            self.world = world; self.now = now; self.events = events
        }
    }

    /// Advances one player by one tick. Pure function of (state, input, world).
    public static func step(player: inout PlayerState, input: InputCommand, ctx: Context) {
        guard player.isAlive else { return }
        let dt = input.deltaTime

        // 1. View
        player.angles.yaw = input.yaw
        player.angles.pitch = input.pitch
        player.angles.clampPitch()

        // 2. Stance
        updateStance(&player, input: input, ctx: ctx, dt: dt)

        // 3. Wish direction in world space
        let move = input.moveVector
        let wishDir = (player.angles.groundForward * -move.z + player.angles.right * move.x).normalized
        let wishSpeed = targetSpeed(player: player, input: input, ctx: ctx)

        // 4. Accelerate
        if player.onGround {
            applyFriction(&player, dt: dt, sliding: player.stance == .sliding)
            accelerate(&player, wishDir: wishDir, wishSpeed: wishSpeed,
                       acceleration: player.stance == .sliding ? 8 : groundAcceleration, dt: dt)
            if input.buttons.contains(.jump) && player.stance != .crouching {
                player.velocity.y = jumpVelocity
                player.onGround = false
                player.stance = .airborne
                ctx.events.emit(.jumped(player: player.id, position: player.position))
                emitNoise(&player, radius: noiseRadiusWalk, ctx: ctx)
            }
        } else {
            accelerate(&player, wishDir: wishDir, wishSpeed: min(wishSpeed, airSpeed),
                       acceleration: airAcceleration, dt: dt)
            player.velocity.y -= gravity * dt
        }

        // 5. Move and resolve collisions
        let previousVelocityY = player.velocity.y
        let startPosition = player.position
        moveWithCollisions(&player, dt: dt, ctx: ctx)

        // 6. Ground check and landing
        let wasOnGround = player.onGround
        checkGround(&player, ctx: ctx)
        if !wasOnGround && player.onGround {
            let impact = abs(previousVelocityY)
            ctx.events.emit(.landed(player: player.id, position: player.position, hardness: impact))
            let damage = DamageModel.fallDamage(impactSpeed: impact, scale: player.perks.fallDamageScale)
            if damage > 0 {
                _ = player.applyDamage(DamageResult(health: damage, armor: 0),
                                       from: player.id, now: ctx.now)
            }
            if impact > 6 { emitNoise(&player, radius: noiseRadiusWalk, ctx: ctx) }
            if player.stance == .airborne { player.stance = input.buttons.contains(.crouch) ? .crouching : .standing }
        }

        // 7. Footsteps — distance based so speed changes feel right
        if player.onGround {
            let travelled = (player.position - startPosition).flattened.length
            player.lastFootstepDistance += travelled
            let interval = player.stance == .crouching ? footstepInterval * 1.6 : footstepInterval
            if player.lastFootstepDistance >= interval {
                player.lastFootstepDistance = 0
                let surface = ctx.world.surface(below: player.position)
                player.groundSurface = surface
                let sprinting = player.velocity.horizontalLength > runSpeed * 1.05
                let loud = sprinting && player.perks.footstepVolumeScale > 0.5
                ctx.events.emit(.footstep(player: player.id, position: player.position,
                                          surface: surface, loud: loud))
                if player.stance != .crouching {
                    emitNoise(&player, radius: sprinting ? noiseRadiusSprint : noiseRadiusWalk, ctx: ctx)
                }
            }
        }

        if !player.position.isFinite { player.position = startPosition; player.velocity = .zero }
    }

    // MARK: - Pieces

    private static func targetSpeed(player: PlayerState, input: InputCommand, ctx: Context) -> Float {
        var base: Float
        switch player.stance {
        case .crouching: base = crouchSpeed
        case .sliding: base = sprintSpeed * slideBoost
        default:
            let sprinting = input.buttons.contains(.sprint) && input.moveForward > 0.5
                && !player.isAiming && player.action != .firing
            base = sprinting ? sprintSpeed : runSpeed
        }
        return base * player.speedScale(now: ctx.now)
    }

    private static func updateStance(_ player: inout PlayerState, input: InputCommand,
                                     ctx: Context, dt: Float) {
        let wantsCrouch = input.buttons.contains(.crouch)
        let sprinting = player.velocity.horizontalLength > runSpeed * 1.1

        switch player.stance {
        case .sliding:
            player.slideTimer.tick(dt)
            if !wantsCrouch || player.slideTimer.isFinished || player.velocity.horizontalLength < crouchSpeed {
                player.stance = wantsCrouch ? .crouching : .standing
            }
        case .standing, .airborne:
            if !player.onGround {
                player.stance = .airborne
            } else if wantsCrouch {
                if sprinting {
                    player.stance = .sliding
                    player.slideTimer.start(slideDuration)
                    player.velocity = player.velocity.flattened * 1.15
                    player.velocity.y = 0
                } else {
                    player.stance = .crouching
                }
            } else {
                player.stance = .standing
            }
        case .crouching:
            if !player.onGround {
                player.stance = .airborne
            } else if !wantsCrouch && canStandUp(player, ctx: ctx) {
                player.stance = .standing
            }
        case .dead:
            break
        }
    }

    private static func canStandUp(_ player: PlayerState, ctx: Context) -> Bool {
        let box = AABB(min: player.position + Vec3(-0.42, 0.05, -0.42),
                       max: player.position + Vec3(0.42, 1.8, 0.42))
        return !ctx.world.overlaps(box: box, mask: .solid)
    }

    private static func applyFriction(_ player: inout PlayerState, dt: Float, sliding: Bool) {
        let speed = player.velocity.flattened.length
        guard speed > 0.01 else {
            player.velocity.x = 0; player.velocity.z = 0
            return
        }
        let f = sliding ? slideFriction : friction
        let drop = max(speed, 1.5) * f * dt
        let newSpeed = max(0, speed - drop)
        let scale = newSpeed / speed
        player.velocity.x *= scale
        player.velocity.z *= scale
    }

    private static func accelerate(_ player: inout PlayerState, wishDir: Vec3, wishSpeed: Float,
                                   acceleration: Float, dt: Float) {
        guard wishSpeed > 0.001, wishDir.lengthSquared > 0.001 else { return }
        let currentSpeed = player.velocity.dot(wishDir)
        let addSpeed = wishSpeed - currentSpeed
        guard addSpeed > 0 else { return }
        let accelSpeed = min(acceleration * wishSpeed * dt, addSpeed)
        player.velocity += wishDir * accelSpeed
    }

    private static func playerBox(_ player: PlayerState) -> AABB {
        let h = 1.8 * player.stance.heightScale
        return AABB(min: player.position + Vec3(-0.42, 0.02, -0.42),
                    max: player.position + Vec3(0.42, h, 0.42))
    }

    /// Slide-and-retry collision resolution with a step-up attempt, so players glide along
    /// walls and climb kerbs instead of catching on geometry.
    private static func moveWithCollisions(_ player: inout PlayerState, dt: Float, ctx: Context) {
        var remaining = player.velocity * dt
        var iterations = 0

        while remaining.lengthSquared > 1e-8 && iterations < 4 {
            iterations += 1
            let box = playerBox(player)
            let result = ctx.world.sweep(box: box, delta: remaining, mask: .solid)
            if !result.hit {
                player.position += remaining
                break
            }

            let travelled = remaining * result.fraction
            player.position += travelled
            remaining -= travelled

            // Try to step over low obstacles before sliding along them.
            if player.onGround && abs(result.normal.y) < 0.3 {
                if attemptStepUp(&player, remaining: remaining, ctx: ctx) { continue }
            }

            remaining = remaining.clipped(normal: result.normal)
            player.velocity = player.velocity.clipped(normal: result.normal)
            if result.normal.y > maxSlopeCos {
                player.onGround = true
                player.velocity.y = max(player.velocity.y, 0)
            }
        }
    }

    private static func attemptStepUp(_ player: inout PlayerState, remaining: Vec3, ctx: Context) -> Bool {
        let savedPosition = player.position
        let up = Vec3(0, maxStepHeight, 0)
        let liftedBox = playerBox(player).offset(by: up)
        if ctx.world.overlaps(box: liftedBox, mask: .solid) { return false }

        let horizontal = remaining.flattened
        guard horizontal.lengthSquared > 1e-6 else { return false }
        let stepResult = ctx.world.sweep(box: liftedBox, delta: horizontal, mask: .solid)
        guard stepResult.fraction > 0.1 else { return false }

        player.position += up + horizontal * stepResult.fraction
        // Settle back down onto the step.
        let down = ctx.world.sweep(box: playerBox(player), delta: Vec3(0, -maxStepHeight, 0), mask: .solid)
        player.position.y -= maxStepHeight * down.fraction
        if ctx.world.overlaps(box: playerBox(player), mask: .solid) {
            player.position = savedPosition
            return false
        }
        return true
    }

    private static func checkGround(_ player: inout PlayerState, ctx: Context) {
        let probe = ctx.world.sweep(box: playerBox(player), delta: Vec3(0, -0.12, 0), mask: .solid)
        if probe.hit && probe.normal.y > maxSlopeCos {
            player.onGround = true
            if player.velocity.y < 0 { player.velocity.y = 0 }
            player.position.y += -0.12 * probe.fraction
            player.groundSurface = probe.surface
        } else {
            player.onGround = false
        }
    }

    private static func emitNoise(_ player: inout PlayerState, radius: Float, ctx: Context) {
        player.lastNoiseTime = ctx.now
        player.lastNoisePosition = player.position
        _ = radius * player.perks.footstepVolumeScale   // bots read these fields directly
    }

    /// Radius within which bots and the enemy minimap can hear this player right now.
    public static func audibleRadius(of player: PlayerState) -> Float {
        let speed = player.velocity.horizontalLength
        var r: Float
        switch player.stance {
        case .crouching, .sliding: r = 5
        default: r = speed > runSpeed * 1.05 ? noiseRadiusSprint : (speed > 1 ? noiseRadiusWalk : 0)
        }
        return r * player.perks.footstepVolumeScale
    }
}
