/* SPDX-License-Identifier: GPL-2.0-only */
#ifndef IRIS2_LIFECYCLE_STATE_H
#define IRIS2_LIFECYCLE_STATE_H
/* All accesses must be serialized by the owner (spinlock in the driver). */
enum iris2_phase { IRIS2_DEAD, IRIS2_IDLE, IRIS2_ACTIVE, IRIS2_QUIESCING };
struct iris2_life_state {
	enum iris2_phase phase;
	unsigned int users;
	unsigned int epoch;
};
static inline int iris2_state_bind(struct iris2_life_state *state)
{
	if (state->phase != IRIS2_DEAD || state->users)
		return 0;
	if (!++state->epoch)
		++state->epoch;
	state->phase = IRIS2_IDLE;
	return 1;
}
static inline int iris2_state_get(struct iris2_life_state *state,
		unsigned int epoch)
{
	if (state->phase != IRIS2_ACTIVE || (epoch && epoch != state->epoch))
		return 0;
	state->users++;
	return 1;
}
static inline int iris2_state_put(struct iris2_life_state *state)
{
	if (!state->users)
		return 0;
	state->users--;
	return 1;
}
static inline void iris2_state_stop(struct iris2_life_state *state)
{
	if (state->phase != IRIS2_DEAD)
		state->phase = IRIS2_QUIESCING;
}
static inline int iris2_state_idle(struct iris2_life_state *state)
{
	if (state->phase == IRIS2_DEAD || state->users)
		return 0;
	state->phase = IRIS2_IDLE;
	return 1;
}
static inline int iris2_state_activate(struct iris2_life_state *state)
{
	if (state->phase != IRIS2_IDLE && state->phase != IRIS2_ACTIVE)
		return 0;
	state->phase = IRIS2_ACTIVE;
	return 1;
}
static inline int iris2_state_unbind(struct iris2_life_state *state)
{
	if (state->users)
		return 0;
	state->phase = IRIS2_DEAD;
	return 1;
}
#endif
