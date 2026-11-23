//
//  lpm_unlock.h
//  Bypass Low Power Mode 60Hz ProMotion cap via DarkSword remote-call.
//  Target: iPhone16,2 / iOS 18.3 (22D63) first; extend offsets per build.
//

#ifndef lpm_unlock_h
#define lpm_unlock_h

#import <stdbool.h>

// Apply unlock. max_hz: 120 preferred; 80 as fallback some panels accept under LPM.
// Returns true if at least one strategy reported success (not proof of panel Hz).
bool lpm_unlock_apply(int max_hz);

// Best-effort restore stock LPM refresh policy (does not toggle LPM itself).
bool lpm_unlock_restore(void);

#endif
