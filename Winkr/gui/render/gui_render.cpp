/*
 * gui_render.cpp — DINKR GUI panel rendering
 *
 * All render functions take WowSession* — render state lives in the session.
 */

#include "gui_render.h"
#include "gui_external.h"
#include "gui_ipc_host.h"
#include "imgui.h"

#include "ipc_protocol.h"
#include "dump_protocol.h"
#include "om_types.h"
#include "rva_defs.h"
#include "wow_guid_format.h"

#include <cmath>
#include <cstdio>
#include <cstring>
#include <cctype>
#include <cstdlib>
#include <cstdarg>
#include <algorithm>
#include <vector>

#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

/* ======================================================================
 * Constants
 * ====================================================================== */

enum ObjectFilter {
    FILTER_ALL = 0,
    FILTER_UNITS,
    FILTER_PLAYERS,
    FILTER_GAMEOBJECTS,
    FILTER_ITEMS,
    FILTER_OTHER,
    FILTER_COUNT
};

/* Resolve selected GUID to current ipc index; returns -1 if not found */
static int ResolveSelectedIndex(const DinkrIPC* ipc, const WowSession* s)
{
    if (!ipc || !s) return -1;
    if (s->selectedGuidLo == 0 && s->selectedGuidHi == 0) return -1;
    uint32_t count = (uint32_t)InterlockedOr((volatile LONG*)&ipc->om_object_count, 0);
    if (count > MAX_OM_OBJECTS) count = MAX_OM_OBJECTS;
    for (uint32_t i = 0; i < count; i++) {
        if (ipc->objects[i].guid_lo == s->selectedGuidLo &&
            ipc->objects[i].guid_hi == s->selectedGuidHi)
            return (int)i;
    }
    return -1;  /* object left the OM */
}

/* ======================================================================
 * Helpers
 * ====================================================================== */

static const char* DllStatusText(uint32_t status)
{
    switch (status) {
    case DLL_STATUS_IDLE:        return "Idle";
    case DLL_STATUS_ATTACHED:    return "Attached";
    case DLL_STATUS_MOD_LOADING: return "Loading Mods";
    case DLL_STATUS_READY:       return "Ready";
    case DLL_STATUS_ERROR:       return "Error";
    case DLL_STATUS_DETACHED:    return "Detached";
    default:                     return "Unknown";
    }
}

static ImVec4 CgTypeColor(uint8_t type)
{
    switch (type) {
    case CGTYPE_PLAYER:
    case CGTYPE_ACTIVE_PLAYER:
        return ImVec4(0.40f, 0.70f, 1.00f, 1.00f);  /* light blue   */
    case CGTYPE_UNIT:
        return ImVec4(1.00f, 0.50f, 0.50f, 1.00f);  /* salmon       */
    case CGTYPE_GAMEOBJECT:
        return ImVec4(0.50f, 1.00f, 0.50f, 1.00f);  /* light green  */
    case CGTYPE_ITEM:
    case CGTYPE_CONTAINER:
    case CGTYPE_AZERITE_ITEM:
    case CGTYPE_AZERITE_EMPOWERED:
        return ImVec4(1.00f, 1.00f, 0.40f, 1.00f);  /* yellow       */
    default:
        return ImVec4(0.70f, 0.70f, 0.70f, 1.00f);  /* gray         */
    }
}

/* ======================================================================
 * Copyable-value helpers  (right-click to copy, tooltip hint)
 * ====================================================================== */

static void CopyableValue(const char* label, const char* value,
                          ImVec4 labelCol = ImVec4(0.50f,0.50f,0.60f,1.0f),
                          ImVec4 valueCol = ImVec4(0.90f,0.90f,0.95f,1.0f))
{
    ImGui::TextColored(labelCol, "%s", label);
    ImGui::SameLine(0, 0);
    ImGui::TextColored(valueCol, "%s", value);
    if (ImGui::IsItemHovered()) {
        ImGui::SetTooltip("Right-click to copy");
        if (ImGui::IsMouseReleased(ImGuiMouseButton_Right))
            ImGui::SetClipboardText(value);
    }
}

static float ComputeDistance(const OmCacheEntry* a, const OmCacheEntry* b)
{
    float dx = a->pos_x - b->pos_x;
    float dy = a->pos_y - b->pos_y;
    float dz = a->pos_z - b->pos_z;
    return sqrtf(dx * dx + dy * dy + dz * dz);
}

static const OmCacheEntry* FindActivePlayer(DinkrIPC* ipc)
{
    if (!ipc) return nullptr;
    uint32_t count = (uint32_t)InterlockedOr((volatile LONG*)&ipc->om_object_count, 0);
    if (count > MAX_OM_OBJECTS) count = MAX_OM_OBJECTS;
    for (uint32_t i = 0; i < count; i++) {
        if (ipc->objects[i].guid_lo == ipc->active_player_guid_lo &&
            ipc->objects[i].guid_hi == ipc->active_player_guid_hi &&
            ipc->active_player_guid_lo != 0)
            return &ipc->objects[i];
    }
    return nullptr;
}

static bool PassesFilter(const OmCacheEntry* obj, int currentFilter)
{
    switch (currentFilter) {
    case FILTER_UNITS:
        return obj->type == CGTYPE_UNIT;
    case FILTER_PLAYERS:
        return obj->type == CGTYPE_PLAYER || obj->type == CGTYPE_ACTIVE_PLAYER;
    case FILTER_GAMEOBJECTS:
        return obj->type == CGTYPE_GAMEOBJECT;
    case FILTER_ITEMS:
        return obj->type == CGTYPE_ITEM || obj->type == CGTYPE_CONTAINER ||
               obj->type == CGTYPE_AZERITE_ITEM || obj->type == CGTYPE_AZERITE_EMPOWERED;
    case FILTER_OTHER:
        return obj->type != CGTYPE_UNIT && obj->type != CGTYPE_PLAYER &&
               obj->type != CGTYPE_ACTIVE_PLAYER && obj->type != CGTYPE_GAMEOBJECT &&
               obj->type != CGTYPE_ITEM && obj->type != CGTYPE_CONTAINER &&
               obj->type != CGTYPE_AZERITE_ITEM && obj->type != CGTYPE_AZERITE_EMPOWERED;
    default: /* FILTER_ALL */
        return true;
    }
}

/* Case-insensitive substring search */
static bool ContainsCI(const char* haystack, const char* needle)
{
    if (!needle[0]) return true;
    for (const char* h = haystack; *h; h++) {
        const char* hi = h;
        const char* ni = needle;
        while (*hi && *ni && (tolower((unsigned char)*hi) == tolower((unsigned char)*ni))) {
            hi++;
            ni++;
        }
        if (!*ni) return true;
    }
    return false;
}

static bool PassesSearch(const OmCacheEntry* obj, const char* search)
{
    if (!search[0]) return true;
    char guidBuf[80];
    if (obj->guid_str[0]) {
        strncpy(guidBuf, obj->guid_str, sizeof(guidBuf) - 1);
        guidBuf[sizeof(guidBuf) - 1] = '\0';
    } else if (obj->guid_lo || obj->guid_hi) {
        int w = WowGuid_Format(obj->guid_hi, obj->guid_lo, guidBuf, sizeof(guidBuf));
        if (w <= 0 || w >= (int)sizeof(guidBuf)) {
            snprintf(guidBuf, sizeof(guidBuf), "0x%016llX-%016llX",
                     (unsigned long long)obj->guid_hi, (unsigned long long)obj->guid_lo);
        }
    } else {
        guidBuf[0] = '\0';
    }
    if (ContainsCI(guidBuf, search)) return true;
    return false;
}

/* ======================================================================
 * Dump thread — runs Ext_DumpProcess on background thread
 * ====================================================================== */

#include "process/gui_dump.h"

struct DumpThreadParam { WowSession* session; };

static DWORD WINAPI DumpThreadProc(LPVOID param)
{
    auto* p = (DumpThreadParam*)param;
    WowSession* s = p->session;
    free(p);

    bool ok = Ext_DumpProcess(s);
    s->dumpResult   = ok ? 0 : 1;
    s->dumpDoneTick = GetTickCount();
    InterlockedExchange(&s->dumping, 0);
    return 0;
}

/* ======================================================================
 * Panel: Status Bar
 * ====================================================================== */

static void RenderStatusBar(WowSession* s, DinkrIPC* ipc, bool connected)
{
    float barH = ImGui::GetFrameHeight() + ImGui::GetStyle().WindowPadding.y * 2;
    ImGui::BeginChild("##StatusBar", ImVec2(0, barH), true,
                      ImGuiWindowFlags_NoScrollbar | ImGuiWindowFlags_NoScrollWithMouse);

    if (!ipc) {
        ImGui::AlignTextToFramePadding();
        ImGui::TextDisabled("Initializing...");
        ImGui::EndChild();
        return;
    }

    /* Inject button — disabled while dumping or dump ever ran */
    {
        bool isDumpActive = InterlockedOr(&s->dumping, 0) != 0 || InterlockedOr(&s->dumpActive, 0) != 0;
        bool disableInject = !connected || s->injecting || isDumpActive || s->isClassic;  /* Classic = dump-only */
        if (disableInject) ImGui::BeginDisabled();
        if (ImGui::Button(s->injecting ? "Injecting..." : "Inject", ImVec2(80, 0))) {
            if (connected && !s->injecting) {
                char exePath[MAX_PATH] = {};
                GetModuleFileNameA(NULL, exePath, MAX_PATH);
                char* lastSlash = strrchr(exePath, '\\');
                if (lastSlash) {
                    *(lastSlash + 1) = '\0';
                    strncat(exePath, "dinkr.dll", MAX_PATH - strlen(exePath) - 1);
                    if (Ext_InjectDLL(s, exePath)) {
                        InterlockedExchange(&s->dllInjected, 1);
                        IpcHost_LogSession(s, "[gui]", "DLL injected \xe2\x80\x94 waiting 3s for decrypt + patch...");
                        s->injecting = true;
                        s->injectStartTick = GetTickCount();
                        s->injectPatched = false;
                    } else {
                        IpcHost_LogSession(s, "[gui]", "DLL injection FAILED");
                    }
                }
            }
        }
        if (disableInject) ImGui::EndDisabled();
    }

    /* Non-blocking injection wait: re-patch after 3 seconds */
    if (s->injecting && !s->injectPatched) {
        DWORD elapsed = GetTickCount() - s->injectStartTick;
        if (elapsed >= 3000) {
            IpcHost_LogSession(s, "[gui]", "re-applying patches as safety net...");
            Ext_ReapplyPatches(s);
            IpcHost_LogSession(s, "[gui]", "injection + patch sequence complete");
            s->injectPatched = true;
            s->injecting = false;
        }
    }

    /* Dump button — Start/Stop toggle */
    ImGui::SameLine();
    ImGui::AlignTextToFramePadding();
    ImGui::TextDisabled("  |  ");
    ImGui::SameLine();
    {
        bool isDumping  = InterlockedOr(&s->dumping, 0) != 0;
        bool isScanning = InterlockedOr(&s->dumpScanning, 0) != 0;
        bool isInjected = InterlockedOr(&s->dllInjected, 0) != 0;
        bool canDump    = connected && s->baseAddr != 0 && !s->injecting && !isInjected;

        /* Result flash (3s after completion) */
        bool showResult = false;
        int result = 0;
        if (!isDumping && s->dumpDoneTick != 0) {
            DWORD elapsed = GetTickCount() - s->dumpDoneTick;
            if (elapsed < 3000) {
                showResult = true;
                result = s->dumpResult;
            } else {
                s->dumpDoneTick = 0;
            }
        }

        /* Button label and color */
        const char* label;
        bool pushedColor = false;

        if (isScanning) {
            /* Show module count while scanning */
            static char scanLabel[48];
            LONG modCount = 0;
            if (s->pDumpIpc) {
                DinkrDumpIPC* dipc = (DinkrDumpIPC*)s->pDumpIpc;
                modCount = InterlockedOr(&dipc->modules_found, 0);
            }
            snprintf(scanLabel, sizeof(scanLabel), "Stop (%ld)", modCount);
            label = scanLabel;
            ImGui::PushStyleColor(ImGuiCol_Text, ImVec4(1.0f, 0.85f, 0.3f, 1.0f));
            pushedColor = true;
        } else if (isDumping) {
            label = "Dumping...";
        } else if (showResult && result == 0) {
            label = "Dumped!";
            ImGui::PushStyleColor(ImGuiCol_Text, ImVec4(0.3f, 1.0f, 0.3f, 1.0f));
            pushedColor = true;
        } else if (showResult && result != 0) {
            label = "Failed!";
            ImGui::PushStyleColor(ImGuiCol_Text, ImVec4(1.0f, 0.3f, 0.3f, 1.0f));
            pushedColor = true;
        } else {
            label = "Dump";
        }

        if (isScanning) {
            /* Stop button — always enabled while scanning */
            if (ImGui::Button(label, ImVec2(90, 0))) {
                Ext_RequestDumpStop(s);
            }
        } else {
            /* Start button */
            bool disable = !canDump || isDumping;
            if (disable) ImGui::BeginDisabled();
            if (ImGui::Button(label, ImVec2(90, 0))) {
                InterlockedExchange(&s->dumping, 1);
                auto* param = (DumpThreadParam*)malloc(sizeof(DumpThreadParam));
                param->session = s;
                s->hDumpThread = CreateThread(NULL, 0, DumpThreadProc, param, 0, NULL);
                IpcHost_LogSession(s, "[gui]", "starting binary dump...");
            }
            if (disable) ImGui::EndDisabled();
        }
        if (pushedColor) ImGui::PopStyleColor();
    }

    ImGui::SameLine();
    ImGui::AlignTextToFramePadding();
    ImGui::TextDisabled("  |  ");
    ImGui::SameLine();

    /* Connection status */
    ImGui::AlignTextToFramePadding();
    if (connected) {
        /* Detect client type for display */
        const char* clientTag = "Retail";
        {
            char pn[MAX_PATH] = {};
            DWORD ns = MAX_PATH;
            if (QueryFullProcessImageNameA(s->hProcess, 0, pn, &ns)) {
                char* sl = strrchr(pn, '\\');
                const char* en = sl ? (sl + 1) : pn;
                if (_stricmp(en, "WowClassic.exe") == 0 ||
                    _stricmp(en, "WowClassicB.exe") == 0 ||
                    _stricmp(en, "WowClassicT.exe") == 0)
                    clientTag = "Classic";
            }
        }
        ImGui::TextColored(ImVec4(0.3f, 1.0f, 0.3f, 1.0f), "Connected (Build %u, %s)",
                           ipc->build_number, clientTag);
    } else {
        ImGui::TextColored(ImVec4(1.0f, 1.0f, 0.4f, 1.0f), "Not Connected");
    }

    ImGui::SameLine();
    ImGui::AlignTextToFramePadding();
    ImGui::TextDisabled("  |  ");
    ImGui::SameLine();

    /* DLL status */
    ImGui::AlignTextToFramePadding();
    const char* statusTxt = DllStatusText(ipc->dll_status);
    ImVec4 statusCol = (ipc->dll_status == DLL_STATUS_READY)
        ? ImVec4(0.3f, 1.0f, 0.3f, 1.0f)
        : (ipc->dll_status == DLL_STATUS_ERROR)
            ? ImVec4(1.0f, 0.3f, 0.3f, 1.0f)
            : ImVec4(0.8f, 0.8f, 0.8f, 1.0f);
    ImGui::TextColored(statusCol, "DLL: %s", statusTxt);

    ImGui::SameLine();
    ImGui::AlignTextToFramePadding();
    ImGui::TextDisabled("  |  ");
    ImGui::SameLine();

    /* Mods */
    ImGui::AlignTextToFramePadding();
    ImGui::Text("Mods: %u loaded", ipc->mod_count);

    ImGui::SameLine();
    ImGui::AlignTextToFramePadding();
    ImGui::TextDisabled("  |  ");
    ImGui::SameLine();

    /* Objects */
    ImGui::AlignTextToFramePadding();
    ImGui::Text("Objects: %u", ipc->om_object_count);

    /* Last error, if any */
    if (ipc->last_error[0]) {
        ImGui::SameLine();
        ImGui::AlignTextToFramePadding();
        ImGui::TextDisabled("  |  ");
        ImGui::SameLine();
        ImGui::AlignTextToFramePadding();
        ImGui::TextColored(ImVec4(1.0f, 0.3f, 0.3f, 1.0f), "%s", ipc->last_error);
    }

    ImGui::EndChild();
}

/* (Control panel removed — inject button moved to status bar) */

/* ======================================================================
 * Panel: Object Manager
 * ====================================================================== */

static void RenderObjectManager(WowSession* s, DinkrIPC* ipc, bool /*connected*/, float height)
{
    ImGui::BeginChild("##ObjectManager", ImVec2(0, height), true);

    if (!ipc) {
        ImGui::TextDisabled("No IPC");
        ImGui::EndChild();
        return;
    }

    /* Title */
    ImGui::TextColored(ImVec4(0.000f, 0.471f, 0.831f, 1.00f), "Object Manager");
    ImGui::SameLine(ImGui::GetWindowWidth() - 300);
    /* OM health indicator. "Alert only" hides the raw tick and only surfaces a
     * red warning if the enumerator stops advancing (>1.5s = frozen/out-of-world). */
    {
        static bool s_alertOnly = true;   /* default: "OM live" + freeze-alert only, not the raw tick */
        static uint32_t s_lastTick = 0;
        static double s_lastChange = 0.0;
        uint32_t tick = ipc->om_update_tick;
        double now = ImGui::GetTime();
        if (tick != s_lastTick) { s_lastTick = tick; s_lastChange = now; }
        bool frozen = (now - s_lastChange) > 1.5;

        if (frozen) {
            ImGui::TextColored(ImVec4(0.95f, 0.29f, 0.24f, 1.0f), "OM FROZEN (%u)", tick);
        } else if (!s_alertOnly) {
            ImGui::Text("OM Tick: %u", tick);
        } else {
            ImGui::TextColored(ImVec4(0.30f, 0.80f, 0.40f, 1.0f), "OM live");
        }
        /* A visible bordered toggle button rather than a tiny dark checkbox. */
        ImGui::SameLine(0, 10);
        ImGui::PushStyleColor(ImGuiCol_Button, s_alertOnly
                              ? ImVec4(0.16f, 0.34f, 0.22f, 1.0f) : ImVec4(0.20f, 0.23f, 0.28f, 1.0f));
        ImGui::PushStyleColor(ImGuiCol_ButtonHovered, ImVec4(0.28f, 0.40f, 0.52f, 1.0f));
        ImGui::PushStyleColor(ImGuiCol_Border, ImVec4(0.40f, 0.55f, 0.75f, 0.9f));
        ImGui::PushStyleVar(ImGuiStyleVar_FrameBorderSize, 1.0f);
        if (ImGui::SmallButton(s_alertOnly ? "alerts: on" : "alerts: off"))
            s_alertOnly = !s_alertOnly;
        ImGui::PopStyleVar();
        ImGui::PopStyleColor(3);
        if (ImGui::IsItemHovered())
            ImGui::SetTooltip("Toggle: hide the OM tick and only warn if the enumerator freezes");
    }

    /* Filter buttons with counts */
    {
        static const char* labels[] = { "All", "Units", "Players", "GameObjects", "Items", "Other" };

        uint32_t totalCount = (uint32_t)InterlockedOr(
            (volatile LONG*)&ipc->om_object_count, 0);
        if (totalCount > MAX_OM_OBJECTS) totalCount = MAX_OM_OBJECTS;
        int filterCounts[FILTER_COUNT] = {};
        for (uint32_t i = 0; i < totalCount; i++) {
            const OmCacheEntry* o = &ipc->objects[i];
            if (o->guid_lo == 0 && o->guid_hi == 0) continue;
            filterCounts[FILTER_ALL]++;
            if (o->type == CGTYPE_UNIT)
                filterCounts[FILTER_UNITS]++;
            else if (o->type == CGTYPE_PLAYER || o->type == CGTYPE_ACTIVE_PLAYER)
                filterCounts[FILTER_PLAYERS]++;
            else if (o->type == CGTYPE_GAMEOBJECT)
                filterCounts[FILTER_GAMEOBJECTS]++;
            else if (o->type == CGTYPE_ITEM || o->type == CGTYPE_CONTAINER ||
                     o->type == CGTYPE_AZERITE_ITEM || o->type == CGTYPE_AZERITE_EMPOWERED)
                filterCounts[FILTER_ITEMS]++;
            else
                filterCounts[FILTER_OTHER]++;
        }

        for (int f = 0; f < FILTER_COUNT; f++) {
            if (f > 0) ImGui::SameLine();
            bool selected = (s->currentFilter == f);
            if (selected)
                ImGui::PushStyleColor(ImGuiCol_Button,
                    ImGui::GetStyleColorVec4(ImGuiCol_ButtonActive));
            char btnLabel[40];
            snprintf(btnLabel, sizeof(btnLabel), "%s (%d)", labels[f], filterCounts[f]);
            if (ImGui::Button(btnLabel, ImVec2(0, 0)))
                s->currentFilter = f;
            if (selected)
                ImGui::PopStyleColor();
        }
    }

    ImGui::SameLine(0, 20);
    ImGui::SetNextItemWidth(200);
    /* Make it read as an interactive field: brighter bg + visible border. */
    ImGui::PushStyleColor(ImGuiCol_FrameBg,        ImVec4(0.16f, 0.19f, 0.24f, 1.0f));
    ImGui::PushStyleColor(ImGuiCol_FrameBgHovered, ImVec4(0.20f, 0.24f, 0.30f, 1.0f));
    ImGui::PushStyleColor(ImGuiCol_Border,         ImVec4(0.34f, 0.50f, 0.72f, 0.90f));
    ImGui::PushStyleColor(ImGuiCol_TextDisabled,   ImVec4(0.62f, 0.68f, 0.78f, 1.0f)); /* brighter hint */
    ImGui::PushStyleVar(ImGuiStyleVar_FrameBorderSize, 1.0f);
    ImGui::InputTextWithHint("##Search", "Filter by GUID...", s->searchText,
                             sizeof(s->searchText));
    ImGui::PopStyleVar();
    ImGui::PopStyleColor(4);

    ImGui::Separator();

    const OmCacheEntry* activePlayer = FindActivePlayer(ipc);

    const ImGuiTableFlags tableFlags =
        ImGuiTableFlags_Borders | ImGuiTableFlags_RowBg |
        ImGuiTableFlags_ScrollY | ImGuiTableFlags_Resizable |
        ImGuiTableFlags_SizingFixedFit | ImGuiTableFlags_Sortable;

    float tableHeight = ImGui::GetContentRegionAvail().y;

    if (ImGui::BeginTable("##ObjTable", 6, tableFlags, ImVec2(0, tableHeight))) {
        ImGui::TableSetupScrollFreeze(0, 1);
        ImGui::TableSetupColumn("#",        ImGuiTableColumnFlags_WidthFixed | ImGuiTableColumnFlags_DefaultSort, 50.0f);
        ImGui::TableSetupColumn("Type",     ImGuiTableColumnFlags_WidthFixed, 110.0f);
        ImGui::TableSetupColumn("Position", ImGuiTableColumnFlags_WidthFixed, 200.0f);
        ImGui::TableSetupColumn("Facing",   ImGuiTableColumnFlags_WidthFixed, 80.0f);
        ImGui::TableSetupColumn("Dist",     ImGuiTableColumnFlags_WidthFixed, 60.0f);
        ImGui::TableSetupColumn("GUID",     ImGuiTableColumnFlags_WidthFixed, 170.0f);
        ImGui::TableHeadersRow();

        uint32_t count = (uint32_t)InterlockedOr(
            (volatile LONG*)&ipc->om_object_count, 0);
        if (count > MAX_OM_OBJECTS) count = MAX_OM_OBJECTS;

        static std::vector<int> visible;
        visible.clear();
        visible.reserve(count);
        for (uint32_t i = 0; i < count; i++) {
            const OmCacheEntry* obj = &ipc->objects[i];
            if (obj->guid_lo == 0 && obj->guid_hi == 0) continue;
            if (!PassesFilter(obj, s->currentFilter)) continue;
            if (!PassesSearch(obj, s->searchText)) continue;
            visible.push_back((int)i);
        }

        ImGuiTableSortSpecs* sortSpecs = ImGui::TableGetSortSpecs();
        if (sortSpecs && sortSpecs->SpecsDirty && sortSpecs->SpecsCount > 0) {
            s->sortColumn    = sortSpecs->Specs[0].ColumnIndex;
            s->sortDirection = sortSpecs->Specs[0].SortDirection;
            sortSpecs->SpecsDirty = false;
        }

        {
            const int col = s->sortColumn;
            const bool asc = (s->sortDirection == ImGuiSortDirection_Ascending);

            std::sort(visible.begin(), visible.end(),
                [&](int ai, int bi) -> bool {
                    const OmCacheEntry* a = &ipc->objects[ai];
                    const OmCacheEntry* b = &ipc->objects[bi];
                    int cmp = 0;
                    switch (col) {
                    case 0: cmp = ai - bi; break;
                    case 1: cmp = strcmp(CGTypeName(a->type), CGTypeName(b->type)); break;
                    case 2:
                        if (a->pos_x != b->pos_x)      cmp = (a->pos_x < b->pos_x) ? -1 : 1;
                        else if (a->pos_y != b->pos_y)  cmp = (a->pos_y < b->pos_y) ? -1 : 1;
                        else if (a->pos_z != b->pos_z)  cmp = (a->pos_z < b->pos_z) ? -1 : 1;
                        break;
                    case 3:
                        if (a->facing < b->facing) cmp = -1;
                        else if (a->facing > b->facing) cmp = 1;
                        break;
                    case 4: {
                        float da = activePlayer ? ComputeDistance(a, activePlayer) : 0.0f;
                        float db = activePlayer ? ComputeDistance(b, activePlayer) : 0.0f;
                        if (da < db) cmp = -1; else if (da > db) cmp = 1;
                        break;
                    }
                    case 5:
                        if (a->guid_hi != b->guid_hi)
                            cmp = (a->guid_hi < b->guid_hi) ? -1 : 1;
                        else if (a->guid_lo != b->guid_lo)
                            cmp = (a->guid_lo < b->guid_lo) ? -1 : 1;
                        break;
                    }
                    return asc ? (cmp < 0) : (cmp > 0);
                });
        }

        int visibleIdx = 0;
        for (int idx : visible) {
            const OmCacheEntry* obj = &ipc->objects[idx];
            visibleIdx++;
            ImGui::PushID(idx);

            ImGui::TableNextRow();
            bool isSelected = (obj->guid_lo == s->selectedGuidLo &&
                               obj->guid_hi == s->selectedGuidHi &&
                               s->selectedGuidLo != 0);

            ImGui::TableSetColumnIndex(0);
            if (ImGui::Selectable("##sel",
                    isSelected,
                    ImGuiSelectableFlags_SpanAllColumns | ImGuiSelectableFlags_AllowOverlap,
                    ImVec2(0, 0))) {
                if (isSelected) {
                    s->selectedGuidLo = 0;
                    s->selectedGuidHi = 0;
                } else {
                    s->selectedGuidLo = obj->guid_lo;
                    s->selectedGuidHi = obj->guid_hi;
                }
            }
            ImGui::SameLine();
            ImGui::Text("%d", visibleIdx);

            ImGui::TableSetColumnIndex(1);
            ImGui::TextColored(CgTypeColor(obj->type), "%s", CGTypeName(obj->type));

            ImGui::TableSetColumnIndex(2);
            ImGui::Text("%.2f, %.2f, %.2f", obj->pos_x, obj->pos_y, obj->pos_z);
            if (ImGui::IsItemHovered()) {
                ImGui::SetTooltip("Right-click to copy XYZ");
                if (ImGui::IsMouseReleased(ImGuiMouseButton_Right)) {
                    char posCopy[80];
                    snprintf(posCopy, sizeof(posCopy), "%.4f, %.4f, %.4f", obj->pos_x, obj->pos_y, obj->pos_z);
                    ImGui::SetClipboardText(posCopy);
                }
            }

            ImGui::TableSetColumnIndex(3);
            {
                float deg = obj->facing * (180.0f / (float)M_PI);
                if (deg < 0.0f) deg += 360.0f;
                bool valid = std::isfinite(deg) && deg >= 0.0f && deg <= 360.0f;
                if (valid)
                    ImGui::Text("%.1f\xc2\xb0", deg);
                else
                    ImGui::TextDisabled("NIL");
            }

            ImGui::TableSetColumnIndex(4);
            if (activePlayer && obj != activePlayer) {
                float dist = ComputeDistance(obj, activePlayer);
                ImGui::Text("%.1f", dist);
            } else if (obj == activePlayer) {
                ImGui::TextDisabled("--");
            } else {
                ImGui::TextDisabled("?");
            }

            ImGui::TableSetColumnIndex(5);
            {
                char shortGuid[40];
                WowGuid_ShortForm(obj->guid_hi, obj->guid_lo, shortGuid, sizeof(shortGuid));
                ImGui::TextDisabled("%s", shortGuid);
                if (ImGui::IsItemHovered()) {
                    ImGui::SetTooltip("Right-click to copy full GUID");
                    if (ImGui::IsMouseReleased(ImGuiMouseButton_Right))
                        ImGui::SetClipboardText(obj->guid_str);
                }
            }

            ImGui::PopID();
        }

        ImGui::EndTable();
    }

    ImGui::EndChild();
}

/* ======================================================================
 * Panel: Object Detail (selected object — full width)
 * ====================================================================== */

static void RenderObjectDetail(WowSession* s, DinkrIPC* ipc, float height)
{
    ImGui::BeginChild("##ObjDetail", ImVec2(0, height), true);

    int selIdx = ResolveSelectedIndex(ipc, s);
    bool objectGone = false;

    if (selIdx >= 0) {
        s->lastSelected = ipc->objects[selIdx];
        s->hasSnapshot  = true;
    } else if (s->hasSnapshot) {
        objectGone = true;
    } else {
        ImGui::TextDisabled("Object not found in OM");
        ImGui::EndChild();
        return;
    }

    const OmCacheEntry* obj = &s->lastSelected;

    /* Header: type + GUID */
    char headerGuid[80];
    if (obj->guid_str[0]) {
        strncpy(headerGuid, obj->guid_str, sizeof(headerGuid) - 1);
        headerGuid[sizeof(headerGuid) - 1] = '\0';
    } else if (obj->guid_lo || obj->guid_hi) {
        int w = WowGuid_Format(obj->guid_hi, obj->guid_lo, headerGuid, sizeof(headerGuid));
        if (w <= 0 || w >= (int)sizeof(headerGuid)) {
            snprintf(headerGuid, sizeof(headerGuid), "0x%016llX-%016llX",
                     (unsigned long long)obj->guid_hi, (unsigned long long)obj->guid_lo);
        }
    } else {
        strncpy(headerGuid, "(unknown)", sizeof(headerGuid) - 1);
        headerGuid[sizeof(headerGuid) - 1] = '\0';
    }

    ImGui::TextColored(CgTypeColor(obj->type), "[%s]", CGTypeName(obj->type));
    ImGui::SameLine();
    ImGui::TextColored(ImVec4(0.000f, 0.471f, 0.831f, 1.00f), "  %s", headerGuid);
    if (objectGone) {
        ImGui::SameLine();
        ImGui::TextColored(ImVec4(1.0f, 0.4f, 0.4f, 1.0f), "  (Gone)");
    }
    ImGui::SameLine(ImGui::GetWindowWidth() - 60);
    if (ImGui::SmallButton("X##close")) {
        s->selectedGuidLo = 0;
        s->selectedGuidHi = 0;
        s->hasSnapshot = false;
        ImGui::EndChild();
        return;
    }

    ImGui::Separator();

    if (ImGui::BeginTabBar("##detailTabs")) {
        /* === INFO TAB === */
        if (ImGui::BeginTabItem("Info")) {
            ImVec4 labelCol(0.50f, 0.50f, 0.60f, 1.0f);
            ImVec4 valCol(0.90f, 0.90f, 0.95f, 1.0f);
            ImVec4 accentCol(0.40f, 0.80f, 1.00f, 1.0f);
            ImVec4 sectionCol(1.0f, 0.85f, 0.30f, 1.0f);

            /* ---- Identity ---- */
            ImGui::TextColored(sectionCol, "Identity");
            CopyableValue("GUID:  ", headerGuid, labelCol, accentCol);
            { char ab[32]; snprintf(ab, sizeof(ab), "0x%016llX", (unsigned long long)obj->cgobj);
              CopyableValue("Address:  ", ab, labelCol, valCol); }
            { char tb[64]; snprintf(tb, sizeof(tb), "%u (%s)", obj->type, CGTypeName(obj->type));
              ImGui::TextColored(labelCol, "CG Type:  ");
              ImGui::SameLine(0, 0);
              ImGui::TextColored(CgTypeColor(obj->type), "%s", tb); }
            if (obj->npc_id > 0) {
                char nb[16]; snprintf(nb, sizeof(nb), "%u", obj->npc_id);
                CopyableValue("NPC ID:  ", nb, labelCol, valCol);
            }

            /* ---- Spatial ---- */
            ImGui::Spacing(); ImGui::TextColored(sectionCol, "Spatial");
            { char pb[80]; snprintf(pb, sizeof(pb), "%.4f, %.4f, %.4f",
                                    obj->pos_x, obj->pos_y, obj->pos_z);
              CopyableValue("Position:  ", pb, labelCol, valCol); }
            { float deg = obj->facing * (180.0f / (float)M_PI);
              if (deg < 0.0f) deg += 360.0f;
              char fb[48]; snprintf(fb, sizeof(fb), "%.4f rad (%.1f\xc2\xb0)",
                                    obj->facing, deg);
              CopyableValue("Facing:  ", fb, labelCol, valCol); }
            if (obj->height > 0.01f) {
                char hb[32]; snprintf(hb, sizeof(hb), "%.4f", obj->height);
                CopyableValue("Height:  ", hb, labelCol, valCol);
            }
            if (IsUnitType(obj->type)) {
                char cb[64]; snprintf(cb, sizeof(cb), "%.2f  |  Bounding: %.2f",
                                      obj->combat_reach, obj->bounding_radius);
                CopyableValue("Combat Reach:  ", cb, labelCol, valCol);
            }

            /* ---- Flags (unit only) ---- */
            if (IsUnitType(obj->type) &&
                (obj->unit_flags || obj->unit_flags2 ||
                 obj->dynamic_flags || obj->movement_flags)) {
                ImGui::Spacing(); ImGui::TextColored(sectionCol, "Flags");
                if (obj->unit_flags) {
                    char fb[16]; snprintf(fb, sizeof(fb), "0x%08X", obj->unit_flags);
                    CopyableValue("Unit Flags:  ", fb, labelCol, valCol);
                }
                if (obj->unit_flags2) {
                    char fb[16]; snprintf(fb, sizeof(fb), "0x%08X", obj->unit_flags2);
                    CopyableValue("Flags2:  ", fb, labelCol, valCol);
                }
                if (obj->dynamic_flags) {
                    char fb[32]; snprintf(fb, sizeof(fb), "0x%02X%s",
                                          obj->dynamic_flags,
                                          (obj->dynamic_flags & 0x04) ? "  [Lootable]" : "");
                    CopyableValue("DynFlags:  ", fb, labelCol, valCol);
                }
                if (obj->movement_flags) {
                    char fb[16]; snprintf(fb, sizeof(fb), "0x%08X", obj->movement_flags);
                    CopyableValue("MoveFlags:  ", fb, labelCol, valCol);
                }
            }

            /* ---- Relationships ---- */
            if ((obj->summoned_by_lo || obj->summoned_by_hi) ||
                (obj->created_by_lo  || obj->created_by_hi)) {
                ImGui::Spacing(); ImGui::TextColored(sectionCol, "Relationships");
                if (obj->summoned_by_lo || obj->summoned_by_hi) {
                    char sb[80]; WowGuid_Format(obj->summoned_by_hi, obj->summoned_by_lo, sb, sizeof(sb));
                    CopyableValue("Summoned By:  ", sb, labelCol, valCol);
                }
                if (obj->created_by_lo || obj->created_by_hi) {
                    char cb[80]; WowGuid_Format(obj->created_by_hi, obj->created_by_lo, cb, sizeof(cb));
                    CopyableValue("Created By:  ", cb, labelCol, valCol);
                }
            }

            /* ---- AreaTrigger ---- */
            if (obj->type == CGTYPE_AREA_TRIGGER) {
                ImGui::Spacing(); ImGui::TextColored(sectionCol, "AreaTrigger");
                { char sb[16]; snprintf(sb, sizeof(sb), "%u", obj->at_spell_id);
                  CopyableValue("Spell ID:  ", sb, labelCol, accentCol); }
                if (obj->at_duration_ms == 0)
                    CopyableValue("Duration:  ", "Permanent", labelCol, valCol);
                else {
                    char db[32]; snprintf(db, sizeof(db), "%.1fs", obj->at_duration_ms / 1000.0);
                    CopyableValue("Duration:  ", db, labelCol, valCol);
                }
                { char cb[16]; snprintf(cb, sizeof(cb), "%u", obj->at_create_props_id);
                  CopyableValue("Create Props:  ", cb, labelCol, valCol); }
                { char cfb[16]; snprintf(cfb, sizeof(cfb), "0x%08X", obj->at_client_flags);
                  CopyableValue("Client Flags:  ", cfb, labelCol, valCol); }
                const char* shapeName = "Unknown";
                switch (obj->at_shape_type) {
                    case 0: shapeName = "Sphere";   break;
                    case 1: shapeName = "Box";      break;
                    case 4: shapeName = "Circle";   break;
                    case 7: shapeName = "Cylinder"; break;
                    default: break;
                }
                if (obj->at_shape_type != 0 && obj->at_shape_type != 1 &&
                    obj->at_shape_type != 4 && obj->at_shape_type != 7) {
                    char shb[32]; snprintf(shb, sizeof(shb), "Unknown(%u)", (unsigned)obj->at_shape_type);
                    CopyableValue("Shape:  ", shb, labelCol, valCol);
                } else {
                    CopyableValue("Shape:  ", shapeName, labelCol, valCol);
                }
                { char rb[16]; snprintf(rb, sizeof(rb), "%.2f", obj->at_radius);
                  CopyableValue("Radius:  ", rb, labelCol, valCol); }
                if (obj->at_caster_lo || obj->at_caster_hi) {
                    char casterBuf[80];
                    int w = WowGuid_Format(obj->at_caster_hi, obj->at_caster_lo, casterBuf, sizeof(casterBuf));
                    if (w <= 0 || w >= (int)sizeof(casterBuf)) {
                        snprintf(casterBuf, sizeof(casterBuf), "0x%016llX-%016llX",
                                 (unsigned long long)obj->at_caster_hi, (unsigned long long)obj->at_caster_lo);
                    }
                    CopyableValue("Caster:  ", casterBuf, labelCol, valCol);
                }
            }

            ImGui::EndTabItem();
        }

        ImGui::EndTabBar();
    }

    ImGui::EndChild();
}

/* ======================================================================
 * Panel: Console / Log
 * ====================================================================== */

/* Determine log line color from prefix tag.
 * Timestamps are prepended: "[HH:MM:SS.mmm] [tag] msg"
 * so we skip past the timestamp to find the tag. */
static const char* SkipTimestamp(const char* line, int len)
{
    /* Expect "[HH:MM:SS.mmm] " = 16 chars */
    if (len > 16 && line[0] == '[' && line[13] == ']' && line[14] == ' ')
        return line + 15;
    return line;
}

static ImVec4 LogLineColor(const char* line, int len)
{
    const char* tag = SkipTimestamp(line, len);
    int tagLen = len - (int)(tag - line);
    if (tagLen <= 0 || tag < line || tag > line + len)
        return ImVec4(0.80f, 0.80f, 0.80f, 1.00f);

    /* DLL vs GUI source distinction */
    if (tagLen >= 5  && strncmp(tag, "[dll]",      5) == 0)
        return ImVec4(0.40f, 0.60f, 1.00f, 1.00f);  /* blue   */
    if (tagLen >= 5  && strncmp(tag, "[gui]",      5) == 0)
        return ImVec4(0.85f, 0.85f, 0.85f, 1.00f);  /* white  */

    /* Semantic tags (from DLL messages after [dll] prefix) */
    if (tagLen >= 7  && strncmp(tag, "[error]",    7) == 0)
        return ImVec4(1.00f, 0.30f, 0.30f, 1.00f);  /* red    */
    if (tagLen >= 6  && strncmp(tag, "[init]",     6) == 0)
        return ImVec4(0.60f, 0.60f, 0.60f, 1.00f);  /* gray   */
    if (tagLen >= 10 && strncmp(tag, "[security]", 10) == 0)
        return ImVec4(1.00f, 1.00f, 0.40f, 1.00f);  /* yellow */
    if (tagLen >= 6  && strncmp(tag, "[mods]",     6) == 0)
        return ImVec4(0.40f, 1.00f, 1.00f, 1.00f);  /* cyan   */
    if (tagLen >= 8  && strncmp(tag, "[reload]",   8) == 0)
        return ImVec4(0.40f, 1.00f, 0.40f, 1.00f);  /* green  */
    return ImVec4(0.80f, 0.80f, 0.80f, 1.00f);      /* default */
}

static void RenderConsole(WowSession* s, DinkrIPC* ipc, bool connected, ImVec2 size)
{
    ImGui::BeginChild("##Console", size, true);

    if (!ipc) {
        ImGui::TextDisabled("No IPC");
        ImGui::EndChild();
        return;
    }

    /* Header row: title + buttons */
    ImGui::TextColored(ImVec4(0.000f, 0.471f, 0.831f, 1.00f), "Console");
    ImGui::SameLine(ImGui::GetWindowWidth() - 270);
    if (ImGui::SmallButton("Clear")) {
        /* Zero the log buffer; safe for demo data, acceptable race for live IPC */
        memset(ipc->log_buffer, 0, DINKR_LOG_SIZE);
        InterlockedExchange(&ipc->log_write_pos, 0);
    }
    ImGui::SameLine();
    if (ImGui::SmallButton("Copy All")) {
        LONG pos = InterlockedOr(&ipc->log_write_pos, 0);
        if (pos < 0) pos = 0;
        if (pos > DINKR_LOG_SIZE) pos = DINKR_LOG_SIZE;
        if (pos > 0) {
            /* Build a null-terminated copy for the clipboard */
            char* tmp = (char*)malloc(pos + 1);
            if (tmp) {
                memcpy(tmp, ipc->log_buffer, pos);
                tmp[pos] = '\0';
                ImGui::SetClipboardText(tmp);
                free(tmp);
            }
        }
    }
    ImGui::SameLine();
    ImGui::Checkbox("Auto-scroll", &s->consoleAutoScroll);
    if (ImGui::IsItemHovered())
        ImGui::SetTooltip("Automatically scroll to newest log entries");
    ImGui::Separator();

    /* Scrollable log content */
    ImGui::BeginChild("##LogScroll", ImVec2(0, 0), false);

    if (!connected && InterlockedOr(&ipc->log_write_pos, 0) == 0) {
        ImGui::TextDisabled("Console will appear when DLL is connected");
    } else {
        /* Parse and display log buffer line-by-line — snapshot write pos */
        LONG writePos = InterlockedOr(&ipc->log_write_pos, 0);
        if (writePos < 0) writePos = 0;
        if (writePos > DINKR_LOG_SIZE) writePos = DINKR_LOG_SIZE;

        const char* buf = ipc->log_buffer;
        const char* lineStart = buf;

        for (LONG idx = 0; idx <= writePos; idx++) {
            bool isEnd = (idx == writePos);
            bool isNewline = (!isEnd && buf[idx] == '\n');

            if (isEnd || isNewline) {
                int lineLen = (int)(buf + idx - lineStart);
                if (lineLen > 0) {
                    ImVec4 col = LogLineColor(lineStart, lineLen);
                    ImGui::TextColored(col, "%.*s", lineLen, lineStart);
                }
                lineStart = buf + idx + 1;
            }
        }

        /* Auto-scroll */
        if (s->consoleAutoScroll && ImGui::GetScrollY() >= ImGui::GetScrollMaxY() - 10.0f)
            ImGui::SetScrollHereY(1.0f);
    }

    ImGui::EndChild(); /* LogScroll */
    ImGui::EndChild(); /* Console   */
}

/* ======================================================================
 * Panel: Thread Panel
 * ====================================================================== */

static void RenderThreadPanel(WowSession* s, ImVec2 size)
{
    ImGui::BeginChild("##Threads", size, true);

    ImGui::TextColored(ImVec4(0.000f, 0.471f, 0.831f, 1.00f), "Suspended Threads");
    ImGui::Separator();

    DWORD tids[128];
    int count = Ext_GetSuspendedThreads(s, tids, 128);

    if (count == 0) {
        ImGui::TextDisabled("No suspended threads");
    } else {
        ImGui::BeginChild("##ThreadScroll", ImVec2(0, 0), false);

        if (ImGui::BeginTable("##ThreadTable", 2,
            ImGuiTableFlags_Borders | ImGuiTableFlags_RowBg | ImGuiTableFlags_ScrollY)) {
            ImGui::TableSetupScrollFreeze(0, 1);
            ImGui::TableSetupColumn("#", ImGuiTableColumnFlags_WidthFixed, 30.0f);
            ImGui::TableSetupColumn("Thread ID", ImGuiTableColumnFlags_WidthStretch);
            ImGui::TableHeadersRow();

            for (int i = 0; i < count; i++) {
                ImGui::TableNextRow();
                ImGui::TableSetColumnIndex(0);
                ImGui::Text("%d", i + 1);
                ImGui::TableSetColumnIndex(1);
                ImGui::Text("%lu", (unsigned long)tids[i]);
            }

            ImGui::EndTable();
        }

        ImGui::EndChild(); /* ThreadScroll */
    }

    ImGui::EndChild(); /* Threads */
}

/* ======================================================================
 * Public API
 * ====================================================================== */

void InitRenderState()
{
    /* Nothing to initialize — IPC is managed by gui_ipc_host */
}

void RenderUI(WowSession* s)
{
    if (!s) return;
    DinkrIPC* ipc = s->pIpc;
    bool connected = (ipc != nullptr && Ext_IsSessionAttached(s));

    ImGuiIO& io = ImGui::GetIO();

    /* ---- Status Bar (includes Inject button) ---- */
    RenderStatusBar(s, ipc, connected);

    /* ---- Layout: Object Manager + splitter + Console ---- */
    float availH = ImGui::GetContentRegionAvail().y;

    if (s->consoleHeight < 60.0f) s->consoleHeight = 60.0f;
    if (s->consoleHeight > availH - 100.0f) s->consoleHeight = availH - 100.0f;

    float splitterH = 6.0f;
    float bottomMargin = 14.0f;

    bool hasSelection = (s->selectedGuidLo != 0 || s->selectedGuidHi != 0);
    float detailHeight = hasSelection ? s->detailHeight : 0.0f;
    float detailSplitterH = hasSelection ? 6.0f : 0.0f;
    float omHeight = availH - s->consoleHeight - splitterH - bottomMargin - detailHeight - detailSplitterH;

    RenderObjectManager(s, ipc, connected, omHeight);

    if (hasSelection) {
        ImGui::InvisibleButton("##DetailSplitter", ImVec2(-1, detailSplitterH));
        if (ImGui::IsItemActive())
            s->detailHeight -= io.MouseDelta.y;
        if (s->detailHeight < 120.0f) s->detailHeight = 120.0f;
        if (s->detailHeight > availH - 200.0f) s->detailHeight = availH - 200.0f;
        if (ImGui::IsItemHovered() || ImGui::IsItemActive())
            ImGui::SetMouseCursor(ImGuiMouseCursor_ResizeNS);
    }

    if (hasSelection && ipc)
        RenderObjectDetail(s, ipc, detailHeight);

    ImGui::InvisibleButton("##Splitter", ImVec2(-1, splitterH));
    if (ImGui::IsItemActive())
        s->consoleHeight -= io.MouseDelta.y;
    if (ImGui::IsItemHovered() || ImGui::IsItemActive())
        ImGui::SetMouseCursor(ImGuiMouseCursor_ResizeNS);

    {
        float bottomW = ImGui::GetContentRegionAvail().x;
        float spacing = ImGui::GetStyle().ItemSpacing.x;
        float consoleW = bottomW * 0.70f - spacing * 0.5f;
        float threadW  = bottomW - consoleW - spacing;

        RenderConsole(s, ipc, connected, ImVec2(consoleW, s->consoleHeight));
        ImGui::SameLine(0, spacing);
        RenderThreadPanel(s, ImVec2(threadW, s->consoleHeight));
    }
}

void CleanupRenderState()
{
    /* Nothing to free */
}
