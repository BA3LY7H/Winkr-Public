/* dinkr_ray.h — raw World_Intersect, with no Lua stack in the way.
 *
 * dinkr_TraceLine_lua reads its arguments off the Lua stack and pushes results
 * back onto it. That is fine for a handful of traces a second from a rotation,
 * and hopeless for the live navmesh generator, which fires a few hundred
 * thousand rays per tile. This is the same call with the Lua layer removed;
 * the bridge function is now a thin wrapper around it, so there is still exactly
 * one implementation of the world-frame resolution and its safety checks.
 *
 * Coordinates are WOW space, same as every other dinkr entry point.
 */
#ifndef DINKR_RAY_H
#define DINKR_RAY_H

#ifdef __cplusplus
extern "C" {
#endif

/* Cast one ray.
 *   returns  1 -> BLOCKED, outHit3 receives the hit point
 *            0 -> CLEAR, nothing in the way
 *           -1 -> the world frame or collision context would not resolve, so
 *                 the answer is unknown. Callers must not treat this as clear:
 *                 the Lua bridge reports it as blocked-at-origin, and the mesh
 *                 generator counts it and aborts the tile if it keeps happening.
 * flags of 0 selects the default collision mask (0x120151). */
int dinkr_RayCastRaw(float sx, float sy, float sz,
                     float dx, float dy, float dz,
                     unsigned int flags, float* outHit3);

#ifdef __cplusplus
}
#endif
#endif /* DINKR_RAY_H */
