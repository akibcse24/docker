# ============================================
# STAGE 1: Builder stage for compiled tools
# ============================================
FROM kalilinux/kali-rolling AS builder

# Install build dependencies for custom tools
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential git cmake clang \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# ============================================
# STAGE 2: Final systemd-enabled image
# ============================================
FROM kalilinux/kali-rolling

# --- SECURITY & ENVIRONMENT ---
ARG USERNAME=crytonix
ARG USER_PASSWORD=akib  # ⚠️ CHANGE THIS for production use
ARG SSH_PORT=2222

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    TERM=screen-256color \
    TZ=UTC \
    SHELL=/bin/zsh \
    container=docker

# Update system and install systemd
RUN apt-get update && apt-get upgrade -y \
    && apt-get install -y --no-install-recommends \
    ca-certificates gnupg lsb-release \
    systemd systemd-sysv \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Configure systemd for container environment
RUN (cd /lib/systemd/system/sysinit.target.wants/; for i in *; do [ $i = systemd-tmpfiles-setup.service ] || rm -f $i; done) && \
    rm -f /lib/systemd/system/multi-user.target.wants/* && \
    rm -f /etc/systemd/system/*.wants/* && \
    rm -f /lib/systemd/system/local-fs.target.wants/* && \
    rm -f /lib/systemd/system/sockets.target.wants/*udev* && \
    rm -f /lib/systemd/system/sockets.target.wants/*initctl* && \
    rm -f /lib/systemd/system/basic.target.wants/* && \
    rm -f /lib/systemd/system/anaconda.target.wants/* && \
    rm -f /lib/systemd/system/plymouth* && \
    rm -f /lib/systemd/system/systemd-update-utmp*

# --- MULTI-LAYER OPTIMIZED INSTALLATION ---

# Layer 1: Core system & networking
RUN apt-get update && apt-get install -y --no-install-recommends \
    openssh-server cron sudo \
    neovim tmux zsh stow unzip ca-certificates \
    curl wget git tree htop \
    net-tools iputils-ping dnsutils iproute2 \
    # Homebrew dependencies
    ca-certificates build-essential procps file \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Layer 2: Development languages (use system packages)
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential gcc g++ clang gdb cmake valgrind make \
    default-jdk-headless \
    python3-full python3-pip python3-venv python3-dev \
    ruby-full perl libwww-perl lua5.4 \
    nodejs npm golang-go rustc cargo \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Layer 3: Pentest tools - SPLIT for better error handling
# Install core tools first
RUN apt-get update && apt-get install -y --no-install-recommends \
    nmap masscan gobuster nikto wpscan whatweb amass sublist3r \
    metasploit-framework sqlmap exploitdb \
    hydra john hashcat \
    aircrack-ng tshark tcpdump bettercap wireshark \
    netcat-traditional whois \
    burpsuite commix wfuzz dirb \
    binwalk foremost radare2 ghidra \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Install volatile/missing tools and services
RUN apt-get update && apt-get install -y --no-install-recommends \
    postgresql mariadb-server apache2 nginx \
    volatility \
    && apt-get clean && rm -rf /var/lib/apt/lists/* || true

# Install global npm packages
RUN npm install -g @angular/cli create-react-app vue-cli

# --- SECURITY HARDENING ---

# Create kali group first
RUN groupadd -f kali

# Create non-root user
RUN useradd -m -s /bin/zsh -G sudo,kali,staff,dialout,plugdev ${USERNAME} \
    && echo "${USERNAME}:${USER_PASSWORD}" | chpasswd \
    && echo "${USERNAME} ALL=(ALL) ALL" >> /etc/sudoers.d/${USERNAME} \
    && chmod 0440 /etc/sudoers.d/${USERNAME}

# Configure SSH
RUN mkdir -p /var/run/sshd /etc/ssh/keys \
    && ssh-keygen -t ed25519 -f /etc/ssh/keys/ssh_host_ed25519_key -N "" \
    && ssh-keygen -t rsa -b 4096 -f /etc/ssh/keys/ssh_host_rsa_key -N "" \
    && sed -i 's|#HostKey /etc/ssh/ssh_host_|HostKey /etc/ssh/keys/ssh_host_|g' /etc/ssh/sshd_config \
    && sed -i 's|^#PermitRootLogin .*|PermitRootLogin no|' /etc/ssh/sshd_config \
    && sed -i 's|^#PasswordAuthentication .*|PasswordAuthentication yes|' /etc/ssh/sshd_config \
    && sed -i 's|^#Port 22|Port '"${SSH_PORT}"'|' /etc/ssh/sshd_config \
    && sed -i 's|^#AllowGroups.*|AllowGroups sudo ${USERNAME}|' /etc/ssh/sshd_config

# --- USER CONFIGURATION ---

USER ${USERNAME}
WORKDIR /home/${USERNAME}

# Install Starship to USER LOCAL BIN (~/.local/bin)
RUN curl -sS https://starship.rs/install.sh | sh -s -- -y --bin-dir ~/.local/bin

# Install Oh-My-Zsh and plugins
RUN sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended \
    && git clone https://github.com/zsh-users/zsh-autosuggestions ~/.oh-my-zsh/custom/plugins/zsh-autosuggestions \
    && git clone https://github.com/zsh-users/zsh-syntax-highlighting ~/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting

# Create dotfiles directories step-by-step
RUN mkdir -p ~/dotfiles/zsh \
    && mkdir -p ~/dotfiles/nvim/.config/nvim \
    && mkdir -p ~/dotfiles/tmux

# Create Starship config
RUN echo '[character]\nsuccess_symbol = "[➜](bold green)"\nerror_symbol = "[✗](bold red)"\n\n[docker_context]\nsymbol = " "' > ~/dotfiles/zsh/starship.toml

# TMUX CONFIG - Auto-start optimized
RUN echo '# TMUX AUTOSTART CONFIG\n\
set -g default-terminal "screen-256color"\n\
set -ga terminal-overrides ",xterm-256color:Tc"\n\
set -g mouse on\n\
\n\
# Easy split keys\n\
bind | split-window -h -c "#{pane_current_path}"\n\
bind - split-window -v -c "#{pane_current_path}"\n\
\n\
# Reload config (Ctrl-A + r)\n\
set -g prefix C-a\n\
unbind C-b\n\
bind r source-file ~/.tmux.conf \\\\; display "Config reloaded!"\n\
\n\
# Smart pane switching\n\
bind -n M-Left select-pane -L\n\
bind -n M-Right select-pane -R\n\
bind -n M-Up select-pane -U\n\
bind -n M-Down select-pane -D\n\
\n\
# Status bar\n\
set -g status-bg colour234\n\
set -g status-fg colour137\n\
set -g status-left "#[fg=colour233,bg=colour241,bold] #S "\n\
set -g status-right "#[fg=colour233,bg=colour241,bold] %d/%m #[fg=colour233,bg=colour245,bold] %H:%M:%S "\n\
set -g window-status-current-format "#[fg=colour233,bg=colour39,bold] #I|#W "\n\
set -g window-status-format "#[fg=colour233,bg=colour240] #I|#W "\n\
\n\
# Start at index 1\n\
set -g base-index 1\n\
set -g pane-base-index 1\n\
\n\
# Activity alerts\n\
setw -g monitor-activity on\n\
set -g visual-activity on\n\
\n\
# History limit\n\
set -g history-limit 10000\n\
' > ~/dotfiles/tmux/.tmux.conf

# ZSHRC WITH AUTO-TMUX STARTUP + HOMEBREW
RUN echo '#!/bin/zsh\n\
# --- TMUX AUTO-START ---\n\
if [[ -z "$TMUX" ]] && [[ "$TERM_PROGRAM" != "vscode" ]]; then\n\
    if tmux has-session -t main 2>/dev/null; then\n\
        echo "Attaching to existing tmux session '\''main'\''..."\n\
        exec tmux attach-session -t main\n\
    else\n\
        echo "Starting new tmux session '\''main'\''..."\n\
        exec tmux new-session -s main\n\
    fi\n\
fi\n\
\n\
# --- STANDARD ZSH CONFIG ---\n\
export PATH="/home/linuxbrew/.linuxbrew/bin:/home/linuxbrew/.linuxbrew/sbin:$HOME/.local/bin:$PATH"\n\
export EDITOR="nvim"\n\
export SSH_PORT='"${SSH_PORT}"'\n\
\n\
# Aliases\n\
alias vim="nvim"\n\
alias ll="ls -lah --color=auto"\n\
alias update="sudo apt update && sudo apt upgrade -y"\n\
alias ports="sudo ss -tuln"\n\
alias pwn="python3 -c '\''import pty; pty.spawn('/bin/bash')'\''"\n\
alias systemctl="sudo systemctl"\n\
alias service="sudo systemctl"\n\
alias tkill="tmux kill-session -t"\n\
alias tlist="tmux list-sessions"\n\
alias brew="~/.linuxbrew/bin/brew"\n\
\n\
# Starship\n\
eval "$(starship init zsh)"\n\
\n\
# Zsh plugins\n\
source ~/.oh-my-zsh/custom/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh\n\
source ~/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh\n\
\n\
# History\n\
HISTSIZE=10000\n\
SAVEHIST=10000\n\
HISTFILE=~/.zsh_history\n\
\n\
# TMUX tweaks\n\
if [[ -n "$TMUX" ]]; then\n\
    export KEYTIMEOUT=1\n\
    export NVIM_TUI_ENABLE_TRUE_COLOR=1\n\
fi\n\
' > ~/dotfiles/zsh/.zshrc

# Remove existing config files before stowing
RUN rm -f ~/.zshrc ~/.tmux.conf

# Create symlinks with stow
RUN cd ~/dotfiles && stow zsh nvim tmux

# --- INSTALL HOMEBREW (as user) ---
# Install Homebrew after all shell configs are set up
RUN /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" \
    && eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)" \
    && brew update \
    && brew install tree ripgrep fd bat exa zoxide

# --- FINAL SETUP ---

USER root

# Create persistent data directories
RUN mkdir -p /data/{tools,wordlists,reports,targets} \
    && chown -R ${USERNAME}:${USERNAME} /data

# Install Python tools with --break-system-packages (safe in Docker)
USER ${USERNAME}
RUN pip3 install --user --break-system-packages \
    pwntools requests beautifulsoup4 scapy impacket ipython

# --- SYSTEMD FINALIZATION ---
USER root

# Enable essential services
RUN systemctl enable ssh.service postgresql.service

# Set systemd target
RUN systemctl set-default multi-user.target

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD systemctl is-system-running || exit 1

# Volumes (cgroup required for systemd)
VOLUME ["/data", "/home/${USERNAME}/.msf4", "/sys/fs/cgroup"]

# Expose ports
EXPOSE ${SSH_PORT} 80 443 3000 4444 5432 8000 3306

# Enhanced welcome message with brew info
RUN echo '[ ! -f /etc/welcome-shown ] && echo "\n\
==========================================\n\
KALI SYSTEMD CONTAINER (TMUX-ENABLED) + HOMEBREW\n\
==========================================\n\
User: '"${USERNAME}"'\n\
Password: '"${USER_PASSWORD}"'\n\
SSH Port: '"${SSH_PORT}"'\n\
==========================================\n\
TMUX: Auto-starts on login!\n\
  - Prefix: Ctrl-A\n\
  - Split: | (vertical) - (horizontal)\n\
HOMEBREW: Installed!\n\
  - Usage: brew install <package>\n\
  - Examples: brew install tree ripgrep fd bat exa\n\
==========================================\n\
" && touch /etc/welcome-shown' >> /etc/zsh/zlogin

# Use systemd as init
CMD ["/sbin/init"]
