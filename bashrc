PS1='[\W]\$ '
for f in ~/.secrets/*.env; do
    [ -f "$f" ] && source "$f"
done
[ -f ~/dataops-plugin.env ] && source ~/dataops-plugin.env
az devops configure --defaults organization=https://mcgsead.visualstudio.com/ 2>/dev/null
alias claude='claude --plugin-dir ~/.config/dotfiles/dataops-plugin'
