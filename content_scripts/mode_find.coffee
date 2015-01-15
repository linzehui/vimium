# NOTE(smblott).  Ultimately, all of the FindMode-related code should be moved to this file.

# When we use find mode, the selection/focus can end up in a focusable/editable element.  In this situation,
# special considerations apply.  We implement three special cases:
#   1. Prevent keyboard events from dropping us unintentionally into insert mode.
#   2. Prevent all printable keypress events on the active element from propagating beyond normal mode.  See
#   #1415.
#   3. If the very-next keystroke is Escape, then drop immediately into insert mode.
#
class PostFindMode extends UIMode
  constructor: (findModeAnchorNode) ->
    # Locate the element we need to protect and focus it, if necessary.  Usually, we can just rely on insert
    # mode to have picked it up (when it received the focus).
    element = InsertMode.permanentInstance.insertModeLock
    unless element?
      # For contentEditable elements, chrome does not leave them focused, so insert mode does not pick them
      # up. We start at findModeAnchorNode and walk up the DOM, stopping at the last node encountered which is
      # contentEditable.
      element = findModeAnchorNode
      element = element.parentElement while element?.parentElement?.isContentEditable
      return unless element?.isContentEditable
      # The element might be disabled (and therefore unable to receive focus), we use the approximate
      # heuristic of checking that element is an ancestor of the active element.
      return unless document.activeElement and DomUtils.isDOMDescendant document.activeElement, element
      element.focus()

    super
      name: "post-find"
      badge: "N" # Pretend to be normal mode (because we don't want the insert-mode badge).
      exitOnBlur: element
      exitOnClick: true
      keydown: (event) -> InsertMode.suppressEvent event # Truthy.
      keypress: (event) -> InsertMode.suppressEvent event # Truthy.
      keyup: (event) =>
        @alwaysContinueBubbling =>
          if document.getSelection().type != "Range"
            # If the selection is no longer a range, then the user is interacting with the element, so get out
            # of the way and stop suppressing insert mode.  See discussion of Option 5c from #1415.
            @exit()
          else
            InsertMode.suppressEvent event

    # If the very-next keydown is Esc, drop immediately into insert mode.
    self = @
    @push
      _name: "mode-#{@id}/handle-escape"
      keydown: (event) ->
        if document.activeElement == element and KeyboardUtils.isEscape event
          DomUtils.suppressKeyupAfterEscape handlerStack
          self.exit()
          false # Suppress event.
        else
          @remove()
          true # Continue bubbling.

    # Prevent printable keyboard events from propagating to to the page; see #1415.
    do =>
      handler = (event) =>
        if event.srcElement == element and KeyboardUtils.isPrintable event
          @suppressEvent
        else
          @continueBubbling

      # Note. We use unshift here, instead of push.  We see events *after* normal mode, so we only see
      # unmapped keys.
      @unshift
        _name: "mode-#{@id}/suppressPrintableEvents"
        keydown: handler
        keypress: handler
        keyup: handler

# NOTE.  There's a problem with this approach when a find/search lands in a contentEditable element.  Chrome
# generates a focus event triggering insert mode (good), then immediately generates a "blur" event, disabling
# insert mode again.  Nevertheless, unmapped keys *do* result in the element being focused again.
# So, asking insert mode whether it's active is giving us the wrong answer.

root = exports ? window
root.PostFindMode = PostFindMode
