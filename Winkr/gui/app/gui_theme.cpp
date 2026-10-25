/* gui_theme.cpp — Windows 11 inspired dark theme for ImGui */

#include "gui_theme.h"
#include "imgui.h"

/* ======================================================================
 * ImGui style — Windows 11 inspired dark theme
 * ====================================================================== */

void SetupImGuiStyle()
{
    ImGui::StyleColorsDark();
    ImGuiStyle& s = ImGui::GetStyle();

    /* Rounding — W11 uses generous radii */
    s.WindowRounding    = 0.0f;
    s.ChildRounding     = 6.0f;
    s.FrameRounding     = 6.0f;
    s.GrabRounding      = 6.0f;
    s.TabRounding       = 6.0f;
    s.PopupRounding     = 8.0f;
    s.ScrollbarRounding = 6.0f;

    /* Spacing — more breathing room */
    s.WindowPadding    = ImVec2(12, 12);
    s.FramePadding     = ImVec2(8, 5);
    s.ItemSpacing      = ImVec2(8, 6);
    s.ItemInnerSpacing = ImVec2(6, 4);
    s.ScrollbarSize    = 10.0f;
    s.GrabMinSize      = 8.0f;
    s.WindowBorderSize = 0.0f;
    s.ChildBorderSize  = 1.0f;
    s.FrameBorderSize  = 0.0f;
    s.TabBorderSize    = 0.0f;
    s.IndentSpacing    = 20.0f;

    s.AntiAliasedLines = true;
    s.AntiAliasedFill  = true;

    /* W11-inspired dark palette with blue accent (#0078D4) */
    ImVec4* c = s.Colors;

    /* Base surfaces — layered elevation for depth */
    c[ImGuiCol_WindowBg]             = ImVec4(0.078f, 0.078f, 0.090f, 1.00f);
    c[ImGuiCol_ChildBg]              = ImVec4(0.110f, 0.110f, 0.135f, 1.00f);
    c[ImGuiCol_PopupBg]              = ImVec4(0.098f, 0.098f, 0.118f, 0.96f);

    /* Text */
    c[ImGuiCol_Text]                 = ImVec4(0.922f, 0.922f, 0.941f, 1.00f);
    c[ImGuiCol_TextDisabled]         = ImVec4(0.500f, 0.500f, 0.540f, 1.00f);

    /* Borders — visible panel edges */
    c[ImGuiCol_Border]               = ImVec4(0.220f, 0.220f, 0.280f, 0.60f);
    c[ImGuiCol_BorderShadow]         = ImVec4(0.000f, 0.000f, 0.000f, 0.00f);

    /* Frame backgrounds */
    c[ImGuiCol_FrameBg]              = ImVec4(0.118f, 0.118f, 0.141f, 1.00f);
    c[ImGuiCol_FrameBgHovered]       = ImVec4(0.157f, 0.157f, 0.188f, 1.00f);
    c[ImGuiCol_FrameBgActive]        = ImVec4(0.196f, 0.196f, 0.235f, 1.00f);

    /* Title bar */
    c[ImGuiCol_TitleBg]              = ImVec4(0.067f, 0.067f, 0.082f, 1.00f);
    c[ImGuiCol_TitleBgActive]        = ImVec4(0.082f, 0.082f, 0.106f, 1.00f);
    c[ImGuiCol_TitleBgCollapsed]     = ImVec4(0.051f, 0.051f, 0.067f, 0.50f);

    /* Menu bar */
    c[ImGuiCol_MenuBarBg]            = ImVec4(0.090f, 0.090f, 0.110f, 1.00f);

    /* Scrollbar — thin, subtle */
    c[ImGuiCol_ScrollbarBg]          = ImVec4(0.059f, 0.059f, 0.075f, 0.40f);
    c[ImGuiCol_ScrollbarGrab]        = ImVec4(0.235f, 0.235f, 0.275f, 0.80f);
    c[ImGuiCol_ScrollbarGrabHovered] = ImVec4(0.314f, 0.314f, 0.361f, 0.90f);
    c[ImGuiCol_ScrollbarGrabActive]  = ImVec4(0.392f, 0.392f, 0.447f, 1.00f);

    /* Accent-colored interactive elements */
    c[ImGuiCol_CheckMark]            = ImVec4(0.000f, 0.471f, 0.831f, 1.00f);
    c[ImGuiCol_SliderGrab]           = ImVec4(0.000f, 0.412f, 0.729f, 1.00f);
    c[ImGuiCol_SliderGrabActive]     = ImVec4(0.000f, 0.529f, 0.933f, 1.00f);

    /* Buttons — flat, accent on hover/active */
    c[ImGuiCol_Button]               = ImVec4(0.137f, 0.137f, 0.169f, 1.00f);
    c[ImGuiCol_ButtonHovered]        = ImVec4(0.000f, 0.412f, 0.729f, 0.80f);
    c[ImGuiCol_ButtonActive]         = ImVec4(0.000f, 0.529f, 0.933f, 1.00f);

    /* Headers (table headers, collapsing headers, menu items) */
    c[ImGuiCol_Header]               = ImVec4(0.137f, 0.137f, 0.169f, 1.00f);
    c[ImGuiCol_HeaderHovered]        = ImVec4(0.000f, 0.412f, 0.729f, 0.50f);
    c[ImGuiCol_HeaderActive]         = ImVec4(0.000f, 0.471f, 0.831f, 0.70f);

    /* Separators — W11 hairline dividers */
    c[ImGuiCol_Separator]            = ImVec4(0.200f, 0.200f, 0.235f, 0.30f);
    c[ImGuiCol_SeparatorHovered]     = ImVec4(0.000f, 0.412f, 0.729f, 0.60f);
    c[ImGuiCol_SeparatorActive]      = ImVec4(0.000f, 0.529f, 0.933f, 0.80f);

    /* Resize grip */
    c[ImGuiCol_ResizeGrip]           = ImVec4(0.000f, 0.412f, 0.729f, 0.20f);
    c[ImGuiCol_ResizeGripHovered]    = ImVec4(0.000f, 0.412f, 0.729f, 0.50f);
    c[ImGuiCol_ResizeGripActive]     = ImVec4(0.000f, 0.529f, 0.933f, 0.80f);

    /* Tabs */
    c[ImGuiCol_Tab]                  = ImVec4(0.110f, 0.110f, 0.137f, 1.00f);
    c[ImGuiCol_TabHovered]           = ImVec4(0.000f, 0.412f, 0.729f, 0.60f);

    /* Table */
    c[ImGuiCol_TableHeaderBg]        = ImVec4(0.110f, 0.110f, 0.137f, 1.00f);
    c[ImGuiCol_TableBorderStrong]    = ImVec4(0.180f, 0.180f, 0.220f, 0.60f);
    c[ImGuiCol_TableBorderLight]     = ImVec4(0.145f, 0.145f, 0.180f, 0.40f);
    c[ImGuiCol_TableRowBg]           = ImVec4(0.000f, 0.000f, 0.000f, 0.00f);
    c[ImGuiCol_TableRowBgAlt]        = ImVec4(1.000f, 1.000f, 1.000f, 0.05f);

    /* Selection / Drag-drop */
    c[ImGuiCol_TextSelectedBg]       = ImVec4(0.000f, 0.412f, 0.729f, 0.30f);
    c[ImGuiCol_DragDropTarget]       = ImVec4(0.000f, 0.529f, 0.933f, 0.90f);

    /* Nav */
    c[ImGuiCol_NavHighlight]         = ImVec4(0.000f, 0.471f, 0.831f, 0.80f);
    c[ImGuiCol_NavWindowingHighlight]= ImVec4(1.000f, 1.000f, 1.000f, 0.70f);
    c[ImGuiCol_NavWindowingDimBg]    = ImVec4(0.200f, 0.200f, 0.200f, 0.20f);

    /* Modal dim */
    c[ImGuiCol_ModalWindowDimBg]     = ImVec4(0.000f, 0.000f, 0.000f, 0.50f);
}
