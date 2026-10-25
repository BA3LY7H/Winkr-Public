/*
 * gui_render.h — DINKR GUI render interface (per-session)
 */

#pragma once

struct WowSession;

void InitRenderState();
void RenderUI(WowSession* s);
void CleanupRenderState();
