// CSMC.h — minimal Apple SMC (System Management Controller) client.
//
// The SMC key protocol is undocumented but stable and widely used (iStat Menus,
// smcFanControl, Stats). No root required. This shim exposes a tiny C surface so
// Swift never has to mirror the fixed-layout SMC structs.
#ifndef CSMC_H
#define CSMC_H

#include <stdbool.h>

/// Open a connection to AppleSMC. Returns true on success. Safe to call once.
bool smc_open(void);
void smc_close(void);

/// Read a 4-character SMC key. On success fills `typeOut` (5 bytes: 4-char type
/// code + NUL) and `valueOut` (decoded numeric value) and returns true.
bool smc_read(const char *key, char *typeOut, double *valueOut);

/// Total number of SMC keys (from the "#KEY" key).
int smc_key_count(void);

/// Fetch the key name at `index` into `keyOut` (5 bytes). Returns true on success.
bool smc_key_at_index(int index, char *keyOut);

#endif /* CSMC_H */
