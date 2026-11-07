# ~/.config/zsh/conf.d/30-bindings.zsh

bindkey -v                
export KEYTIMEOUT=2       

# Fix Vi insert mode backspace behavior
bindkey -M viins '^?' backward-delete-char
bindkey -M viins '^h' backward-delete-char
bindkey -M viins '^w' backward-kill-word
bindkey -M viins '^u' backward-kill-line
bindkey -M viins '^a' beginning-of-line     
bindkey -M viins '^e' end-of-line

# Home/End: the Caps layer's ; and ', and ⌘←/→ (keyd). Both cursor-key modes.
# Shift+Home/End (⌘⇧←/→) move the same way: the shell line has no selection,
# and unbound, the sequence drops viins into vicmd and runs as commands.
for m in viins vicmd; do
  bindkey -M $m '^[[H' beginning-of-line '^[OH' beginning-of-line '^[[1;2H' beginning-of-line
  bindkey -M $m '^[[F' end-of-line '^[OF' end-of-line '^[[1;2F' end-of-line
  # Ctrl+←/→ (⌥←/→); with Shift, the same move.
  bindkey -M $m '^[[1;5D' backward-word '^[[1;6D' backward-word
  bindkey -M $m '^[[1;5C' forward-word '^[[1;6C' forward-word
done

# History substring search keys
if [[ -n ${terminfo[kcuu1]} && -n ${terminfo[kcud1]} ]]; then
  bindkey -M viins "${terminfo[kcuu1]}" history-substring-search-up
  bindkey -M viins "${terminfo[kcud1]}" history-substring-search-down
else
  bindkey -M viins '^[[A' history-substring-search-up
  bindkey -M viins '^[[B' history-substring-search-down
fi
bindkey -M vicmd 'k' history-substring-search-up
bindkey -M vicmd 'j' history-substring-search-down

# Edit the current line in $EDITOR
autoload -Uz edit-command-line
zle -N edit-command-line
bindkey -M vicmd 'v' edit-command-line

# Cursor shape management
case $TERM in
  xterm*|tmux*|screen*) CURSOR_SHAPES_SUPPORTED=1 ;;
  *) CURSOR_SHAPES_SUPPORTED=0 ;;
esac

if (( CURSOR_SHAPES_SUPPORTED )); then
  autoload -Uz add-zle-hook-widget
  
  function _cursor_keymap_select {
    case $KEYMAP in
      vicmd)      print -n '\e[2 q' ;; # block
      viins|main) print -n '\e[6 q' ;; # beam
    esac
  }
  
  function _cursor_line_init { 
    print -n '\e[6 q' 
  }
  
  add-zle-hook-widget keymap-select _cursor_keymap_select
  add-zle-hook-widget line-init     _cursor_line_init
  print -n '\e[6 q'
fi
