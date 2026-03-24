import Foundation

/// Reads terminal text content from a Ghostty surface using the C API.
enum ScrollbackCapture {
    /// Read all visible + scrollback text from a Ghostty surface.
    static func readAll(from surface: ghostty_surface_t) -> String? {
        var selection = ghostty_selection_s()
        selection.rectangle = false

        var topLeft = ghostty_point_s()
        topLeft.tag = GHOSTTY_POINT_SCREEN
        topLeft.coord = GHOSTTY_POINT_COORD_TOP_LEFT
        topLeft.x = 0
        topLeft.y = 0
        selection.top_left = topLeft

        var bottomRight = ghostty_point_s()
        bottomRight.tag = GHOSTTY_POINT_ACTIVE
        bottomRight.coord = GHOSTTY_POINT_COORD_BOTTOM_RIGHT
        bottomRight.x = 0
        bottomRight.y = 0
        selection.bottom_right = bottomRight

        var textInfo = ghostty_text_s()
        guard ghostty_surface_read_text(surface, selection, &textInfo) else {
            return nil
        }
        defer {
            var mutableInfo = textInfo
            ghostty_surface_free_text(surface, &mutableInfo)
        }

        guard let ptr = textInfo.text, textInfo.text_len > 0 else { return nil }
        return String(cString: ptr)
    }
}
