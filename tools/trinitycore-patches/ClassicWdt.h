/*
 * Classic Era WDT lookup.
 *
 * Retail's Map.db2 carries a WdtFileDataID column and both extractors read a
 * map's WDT straight from it. Classic Era 1.15.9's Map.db2 (LAYOUT B47C6F05)
 * has no such column, so that path yields 0 for every map and ReadMapDBC's
 * erase_if then throws the entire map list away.
 *
 * The client itself finds these files by path, and the Classic Era root still
 * ships filename hashes -- verified by opening World\Maps\Azeroth\Azeroth.wdt
 * by name against the live storage. So we reconstruct the canonical path from
 * Map.db2's Directory column, open by name, and read the FileDataId back off
 * the handle. Everything downstream is unchanged: the WDT's MAID chunk carries
 * per-ADT FileDataIds exactly as on retail (131072 bytes = 64x64x2 ids), so
 * ADT loading still goes through ids and never touches a name again.
 */

#ifndef TRINITYCORE_CLASSIC_WDT_H
#define TRINITYCORE_CLASSIC_WDT_H

#include "CascHandles.h"
#include <CascLib.h>
#include <memory>
#include <string>

// Returns 0 when the map has no WDT of its own, which is normal -- Map.db2
// lists phasing//cosmetic child maps that ship no terrain. Callers already
// drop maps with a zero id.
inline int32 ResolveWdtFileDataId(CASC::Storage const* storage, std::string const& directory)
{
    if (directory.empty())
        return 0;

    std::string path = "World\\Maps\\" + directory + "\\" + directory + ".wdt";
    std::unique_ptr<CASC::File> wdt(storage->OpenFile(path.c_str(), CASC_LOCALE_NONE, false));
    if (!wdt)
        return 0;

    uint32 id = wdt->GetId();
    if (id == CASC_INVALID_ID)
        return 0;

    return int32(id);
}

#endif // TRINITYCORE_CLASSIC_WDT_H
