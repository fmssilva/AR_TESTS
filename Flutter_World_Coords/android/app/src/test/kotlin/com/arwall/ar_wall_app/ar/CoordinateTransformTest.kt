package com.arwall.ar_wall_app.ar

import org.junit.Assert.assertEquals
import org.junit.Test
import kotlin.math.abs
import kotlin.math.sqrt

/**
 * Pure-Kotlin (no ARCore / Android) unit tests for the blueprint-to-world coordinate math.
 *
 * Mirrors the logic in WorldCoordinateManager / ARModels:
 *   correctionPose = driftedPose × blueprintPose^-1
 *   childWorldPos  = correctionPose × childLocalBlueprint
 *
 * ARCore AugmentedImage local frame (verified from visual inspection):
 *   image_X  = world right
 *   image_Y  = outward from wall (toward camera)
 *   image_Z  = downward
 *
 * Our blueprint frame:
 *   blueprint_X = right      → image_X  ✓
 *   blueprint_Y = up         → -image_Z ✓  (up = -down)
 *   blueprint_Z = outward    → image_Y  ✓
 *
 * blueprintPose.rotation = Rx(+90°) = quaternion (0.7071, 0, 0, 0.7071)
 * blueprintPose.translation = anchor blueprint position = (0.505, 0.505, 0.0)
 */
class CoordinateTransformTest {

    // ─── Minimal Pose math (mirrors ARCore semantics) ────────────────────────

    data class Pose(val tx: Float, val ty: Float, val tz: Float,
                    val qx: Float, val qy: Float, val qz: Float, val qw: Float)

    /** Apply pose to point: p_out = R × p_in + t */
    private fun transformPoint(pose: Pose, px: Float, py: Float, pz: Float): FloatArray {
        val (tx, ty, tz, qx, qy, qz, qw) = pose
        // Rodrigues: v' = v + 2qw(q × v) + 2(q × (q × v))
        val twx = 2f * (qy * pz - qz * py)
        val twy = 2f * (qz * px - qx * pz)
        val twz = 2f * (qx * py - qy * px)
        val rx = px + qw * twx + qy * twz - qz * twy
        val ry = py + qw * twy + qz * twx - qx * twz
        val rz = pz + qw * twz + qx * twy - qy * twx
        return floatArrayOf(rx + tx, ry + ty, rz + tz)
    }

    /** Compose: (A × B)(p) = A(B(p)) */
    private fun compose(a: Pose, b: Pose): Pose {
        // Combined rotation (Hamilton product a × b)
        val rqx = a.qw*b.qx + a.qx*b.qw + a.qy*b.qz - a.qz*b.qy
        val rqy = a.qw*b.qy - a.qx*b.qz + a.qy*b.qw + a.qz*b.qx
        val rqz = a.qw*b.qz + a.qx*b.qy - a.qy*b.qx + a.qz*b.qw
        val rqw = a.qw*b.qw - a.qx*b.qx - a.qy*b.qy - a.qz*b.qz
        // Combined translation: a applied to b's translation
        val t = transformPoint(a, b.tx, b.ty, b.tz)
        return Pose(t[0], t[1], t[2], rqx, rqy, rqz, rqw)
    }

    /** Inverse: (R, t)^-1 = (R^-1, -R^-1 × t). For unit quaternion R^-1 = conjugate. */
    private fun inverse(p: Pose): Pose {
        val iqx = -p.qx; val iqy = -p.qy; val iqz = -p.qz; val iqw = p.qw  // conjugate
        val twx = 2f * (iqy * (-p.tz) - iqz * (-p.ty))
        val twy = 2f * (iqz * (-p.tx) - iqx * (-p.tz))
        val twz = 2f * (iqx * (-p.ty) - iqy * (-p.tx))
        val nx = -p.tx + iqw * twx + iqy * twz - iqz * twy
        val ny = -p.ty + iqw * twy + iqz * twx - iqx * twz
        val nz = -p.tz + iqw * twz + iqx * twy - iqy * twx
        return Pose(nx, ny, nz, iqx, iqy, iqz, iqw)
    }

    // ─── Constants ───────────────────────────────────────────────────────────

    private val SQ2_2 = (sqrt(2.0) / 2.0).toFloat()   // sin/cos(45°) ≈ 0.70711

    /**
     * blueprintPose: Rx(+90°) rotation + translation = anchor blueprint coords.
     * Rx(+90°) quaternion [x,y,z,w] = (sin45°, 0, 0, cos45°)
     */
    private fun quatMul(a: FloatArray, b: FloatArray): FloatArray {
        val ax = a[0]; val ay = a[1]; val az = a[2]; val aw = a[3]
        val bx = b[0]; val by = b[1]; val bz = b[2]; val bw = b[3]
        return floatArrayOf(
            aw*bx + ax*bw + ay*bz - az*by,
            aw*by - ax*bz + ay*bw + az*bx,
            aw*bz + ax*by - ay*bx + az*bw,
            aw*bw - ax*bx - ay*by - az*bz
        )
    }

    private fun makeBlueprintPose(
        anchorBpX: Float,
        anchorBpY: Float,
        anchorBpZ: Float,
        yawDegrees: Float = 0f
    ): Pose {
        val halfYaw = Math.toRadians((yawDegrees / 2.0).toDouble())
        val yawQuat = floatArrayOf(0f, kotlin.math.sin(halfYaw).toFloat(), 0f, kotlin.math.cos(halfYaw).toFloat())
        val rx90Quat = floatArrayOf(SQ2_2, 0f, 0f, SQ2_2)
        val combined = quatMul(yawQuat, rx90Quat)
        return Pose(anchorBpX, anchorBpY, anchorBpZ, combined[0], combined[1], combined[2], combined[3])
    }

    /**
     * driftedPose for a painting on a vertical wall in front of the camera.
     * In ARCore world: image_X=(1,0,0), image_Y=(0,0,1), image_Z=(0,-1,0)
     * Rotation = Rx(+90°) (same quaternion as Rx+90° since the wall is flat-on to world XY).
     */
    private fun makeVerticalWallDriftedPose(cx: Float, cy: Float, cz: Float) =
        Pose(cx, cy, cz, SQ2_2, 0f, 0f, SQ2_2)

    // ─── Tests ───────────────────────────────────────────────────────────────

    @Test
    fun blCornerEqualsCorrection_translation() {
        // BL blueprint = (0,0,0). Its world pos = correctionPose.translation.
        val anchorCenter = Triple(1.5f, 1.2f, -2.0f)
        val drifted  = makeVerticalWallDriftedPose(anchorCenter.first, anchorCenter.second, anchorCenter.third)
        val blueprint = makeBlueprintPose(0.505f, 0.505f, 0f)
        val correction = compose(drifted, inverse(blueprint))

        val bl = transformPoint(correction, 0f, 0f, 0f)

        // BL should be 0.505m left and 0.505m below the anchor center, at same Z.
        assertClose(anchorCenter.first  - 0.505f, bl[0], 0.01f, "BL.x")
        assertClose(anchorCenter.second - 0.505f, bl[1], 0.01f, "BL.y")
        assertClose(anchorCenter.third,            bl[2], 0.01f, "BL.z")
    }

    @Test
    fun tlCornerIs1mAboveBl() {
        val drifted   = makeVerticalWallDriftedPose(1.0f, 1.5f, -1.8f)
        val blueprint  = makeBlueprintPose(0.505f, 0.505f, 0f)
        val correction = compose(drifted, inverse(blueprint))

        val bl = transformPoint(correction, 0f, 0f, 0f)
        val tl = transformPoint(correction, 0f, 1.01f, 0f)

        // TL = BL + (0, +1.01, 0) in world space
        assertClose(bl[0],         tl[0], 0.01f, "TL.x == BL.x")
        assertClose(bl[1] + 1.01f, tl[1], 0.01f, "TL.y == BL.y + 1.01")
        assertClose(bl[2],         tl[2], 0.01f, "TL.z == BL.z")
    }

    @Test
    fun brCornerIs1mRightOfBl() {
        val drifted   = makeVerticalWallDriftedPose(1.0f, 1.5f, -1.8f)
        val blueprint  = makeBlueprintPose(0.505f, 0.505f, 0f)
        val correction = compose(drifted, inverse(blueprint))

        val bl = transformPoint(correction, 0f, 0f, 0f)
        val br = transformPoint(correction, 1.01f, 0f, 0f)

        assertClose(bl[0] + 1.01f, br[0], 0.01f, "BR.x == BL.x + 1.01")
        assertClose(bl[1],         br[1], 0.01f, "BR.y == BL.y")
        assertClose(bl[2],         br[2], 0.01f, "BR.z == BL.z")
    }

    @Test
    fun trCornerIs1mRightAndAboveBl() {
        val drifted   = makeVerticalWallDriftedPose(1.0f, 1.5f, -1.8f)
        val blueprint  = makeBlueprintPose(0.505f, 0.505f, 0f)
        val correction = compose(drifted, inverse(blueprint))

        val bl = transformPoint(correction, 0f, 0f, 0f)
        val tr = transformPoint(correction, 1.01f, 1.01f, 0f)

        assertClose(bl[0] + 1.01f, tr[0], 0.01f, "TR.x == BL.x + 1.01")
        assertClose(bl[1] + 1.01f, tr[1], 0.01f, "TR.y == BL.y + 1.01")
        assertClose(bl[2],         tr[2], 0.01f, "TR.z == BL.z")
    }

    @Test
    fun blueprintXAxisMapsToWorldRight() {
        val drifted   = makeVerticalWallDriftedPose(1.0f, 1.5f, -1.8f)
        val blueprint  = makeBlueprintPose(0.505f, 0.505f, 0f)
        val correction = compose(drifted, inverse(blueprint))

        val o = transformPoint(correction, 0f, 0f, 0f)
        val x = transformPoint(correction, 1f, 0f, 0f)

        assertClose(1f,  x[0]-o[0], 0.01f, "+X delta_x ≈ 1")
        assertClose(0f,  x[1]-o[1], 0.01f, "+X delta_y ≈ 0")
        assertClose(0f,  x[2]-o[2], 0.01f, "+X delta_z ≈ 0")
    }

    @Test
    fun blueprintYAxisMapsToWorldUp() {
        val drifted   = makeVerticalWallDriftedPose(1.0f, 1.5f, -1.8f)
        val blueprint  = makeBlueprintPose(0.505f, 0.505f, 0f)
        val correction = compose(drifted, inverse(blueprint))

        val o = transformPoint(correction, 0f, 0f, 0f)
        val y = transformPoint(correction, 0f, 1f, 0f)

        assertClose(0f,  y[0]-o[0], 0.01f, "+Y delta_x ≈ 0")
        assertClose(1f,  y[1]-o[1], 0.01f, "+Y delta_y ≈ 1  ← UP")
        assertClose(0f,  y[2]-o[2], 0.01f, "+Y delta_z ≈ 0")
    }

    @Test
    fun blueprintZAxisMapsTowardCamera() {
        val drifted   = makeVerticalWallDriftedPose(1.0f, 1.5f, -1.8f)
        val blueprint  = makeBlueprintPose(0.505f, 0.505f, 0f)
        val correction = compose(drifted, inverse(blueprint))

        val o = transformPoint(correction, 0f, 0f, 0f)
        val z = transformPoint(correction, 0f, 0f, 1f)

        // blueprint_Z = outward from wall = toward camera = +world_Z direction
        assertClose(0f,  z[0]-o[0], 0.01f, "+Z delta_x ≈ 0")
        assertClose(0f,  z[1]-o[1], 0.01f, "+Z delta_y ≈ 0")
        assertClose(1f,  z[2]-o[2], 0.01f, "+Z delta_z ≈ 1  ← toward camera")
    }

    @Test
    fun anchorCenterMapsToItsDetectedWorldPosition() {
        // correctionPose × anchorBlueprintCenter should equal driftedPose.translation
        val cx = 0.023f; val cy = 0.139f; val cz = -1.590f  // from real log
        val drifted   = makeVerticalWallDriftedPose(cx, cy, cz)
        val blueprint  = makeBlueprintPose(0.505f, 0.505f, 0f)
        val correction = compose(drifted, inverse(blueprint))

        val anchorWorld = transformPoint(correction, 0.505f, 0.505f, 0f)

        assertClose(cx, anchorWorld[0], 0.01f, "anchor_world.x")
        assertClose(cy, anchorWorld[1], 0.01f, "anchor_world.y")
        assertClose(cz, anchorWorld[2], 0.01f, "anchor_world.z")
    }

    @Test
    fun oldIdentityRotationProducesWrongResults() {
        // Verify the OLD (broken) blueprint pose gives WRONG POI placement.
        val drifted = makeVerticalWallDriftedPose(1.0f, 1.5f, -1.8f)
        // Old code: Pose.makeTranslation = identity rotation [0,0,0,1]
        val wrongBlueprint = Pose(0.505f, 0.505f, 0f, 0f, 0f, 0f, 1f)
        val wrongCorrection = compose(drifted, inverse(wrongBlueprint))

        val bl = transformPoint(wrongCorrection, 0f, 0f, 0f)
        val tl = transformPoint(wrongCorrection, 0f, 1.01f, 0f)

        // With wrong rotation, TL is NOT above BL (Y delta should be ~0, Z delta ~1.01)
        val dy = abs(tl[1] - bl[1])
        val dz = abs(tl[2] - bl[2])
        assert(dy < 0.01f) { "OLD math: TL.y - BL.y should be ~0, got $dy (Y is not up)" }
        assert(dz > 0.5f)  { "OLD math: TL.z - BL.z should be ~1.01, got $dz (Z instead of Y)" }
    }

    @Test
    fun ninetyDegreeYawMapsBlueprintNegativeZWallIntoWorldPositiveX() {
        val drifted = makeVerticalWallDriftedPose(1.0f, 1.5f, -1.8f)
        val blueprint = makeBlueprintPose(1.0f, 1.505f, -0.505f, 90f)
        val correction = compose(drifted, inverse(blueprint))

        val bl = transformPoint(correction, 1.0f, 1.0f, 0.0f)
        val br = transformPoint(correction, 1.0f, 1.0f, -1.01f)
        val tl = transformPoint(correction, 1.0f, 2.01f, 0.0f)

        assertClose(bl[0] + 1.01f, br[0], 0.03f, "BR.x == BL.x + 1.01 for front-facing corrected wall")
        assertClose(bl[1], br[1], 0.03f, "BR.y == BL.y for 90 deg wall")
        assertClose(bl[2], br[2], 0.03f, "BR.z == BL.z for front-facing corrected wall")

        assertClose(bl[0], tl[0], 0.03f, "TL.x == BL.x for vertical edge")
        assertClose(bl[1] + 1.01f, tl[1], 0.03f, "TL.y == BL.y + 1.01")
        assertClose(bl[2], tl[2], 0.03f, "TL.z == BL.z for vertical edge")
    }

    // ─── Helpers ─────────────────────────────────────────────────────────────

    private fun assertClose(expected: Float, actual: Float, delta: Float, msg: String) {
        assertEquals("$msg: expected $expected, got $actual", expected, actual, delta)
    }
}
