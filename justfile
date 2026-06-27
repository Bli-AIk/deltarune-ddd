default: run

# Run this mod through Kristal in a detached terminal.
run:
    @.helix/run-kristal-terminal.sh

# Same as run, but keep the terminal open after Love exits.
hold:
    @.helix/run-kristal-terminal.sh --hold

alias l := run
alias L := hold
