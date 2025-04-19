#!/data/data/com.termux/files/usr/bin/bash

# Configurações
BACKUP_DIR="/sdcard/Termux"
BACKUP_FILE="termux-backup-$(date +%Y%m%d_%H%M%S).tar.gz"
INCREMENTAL_DIR="$BACKUP_DIR/backup_incremental"
RESTORE_FILE="$BACKUP_DIR/termux-backup-latest.tar.gz"
RCLONE_REMOTE="gdrive:termux-backup"
USER_FILE="$HOME/.teracount_user"
TERMUX_HOME="/data/data/com.termux/files"
EXCLUDE_FILE="$BACKUP_DIR/.backup_exclude"
PKG_LIST="$BACKUP_DIR/pkg_list.txt"

# Cria arquivo de exclusão
cat << EOF > "$EXCLUDE_FILE"
.cache
.termux
.teracount_user
*/tmp/*
*/var/cache/*
*/ubuntu-fs/*
*.img
*.qcow2
*.jpg
*.png
*.jpeg
*.mp4
*.mkv
*.avi
*.mp3
*.wav
*.ogg
*/storage/shared/*
*/var/log/*
*.log
*.csv
*.history
*/.git/*
EOF

# Função para criar/verificar usuário e senha
setup_account() {
    if [ ! -f "$USER_FILE" ]; then
        echo "Configurando nova conta Teracount..."
        read -p "Digite o nome de usuário: " username
        read -sp "Digite a senha: " password
        echo
        echo "$username:$(echo -n $password | sha256sum | awk '{print $1}')" > "$USER_FILE"
        echo "Conta criada com sucesso!"
    fi
}

# Função de login
login() {
    echo "=== Login Teracount ==="
    read -p "Usuário: " input_user
    read -sp "Senha: " input_pass
    echo
    stored_user=$(cat "$USER_FILE" | cut -d':' -f1)
    stored_pass=$(cat "$USER_FILE" | cut -d':' -f2)
    input_pass_hash=$(echo -n "$input_pass" | sha256sum | awk '{print $1}')
    
    if [ "$input_user" = "$stored_user" ] && [ "$input_pass_hash" = "$stored_pass" ]; then
        echo "Login bem-sucedido!"
        GPG_PASSPHRASE="$input_pass" # Armazena a senha para GPG
        return 0
    else
        echo "Usuário ou senha incorretos!"
        exit 1
    fi
}

# Função para criar lista de pacotes
create_pkg_list() {
    echo "Gerando lista de pacotes instalados..."
    dpkg -l > "$PKG_LIST"
    if [ $? -eq 0 ]; then
        echo "Lista de pacotes salva em: $PKG_LIST"
    else
        echo "Erro ao gerar lista de pacotes!"
    fi
}

# Função para criar backup incremental
create_backup() {
    echo "Criando backup incremental..."
    mkdir -p "$INCREMENTAL_DIR"
    # Copia apenas arquivos alterados
    rsync -a --exclude-from="$EXCLUDE_FILE" "$TERMUX_HOME/" "$INCREMENTAL_DIR/"
    # Gera lista de pacotes
    create_pkg_list
    # Compacta e criptografa
    tar -zcf - -C "$INCREMENTAL_DIR" . | gpg -c --batch --yes --passphrase "$GPG_PASSPHRASE" > "$BACKUP_DIR/$BACKUP_FILE.gpg"
    if [ $? -eq 0 ]; then
        echo "Backup criado: $BACKUP_DIR/$BACKUP_FILE.gpg"
        ln -sf "$BACKUP_DIR/$BACKUP_FILE.gpg" "$BACKUP_DIR/termux-backup-latest.tar.gz.gpg"
        sync_to_cloud
    else
        echo "Erro ao criar backup!"
        exit 1
    fi
}

# Função para sincronizar com o Google Drive
sync_to_cloud() {
    echo "Sincronizando com o Google Drive..."
    rclone copy "$BACKUP_DIR/$BACKUP_FILE.gpg" "$RCLONE_REMOTE" -P
    rclone copy "$PKG_LIST" "$RCLONE_REMOTE" -P
    if [ $? -eq 0 ]; then
        echo "Sincronização concluída!"
        rclone delete "$RCLONE_REMOTE" --min-age 3d
    else
        echo "Erro ao sincronizar!"
        exit 1
    fi
}

# Função para restaurar backup
restore_backup() {
    echo "Restaurando backup do Google Drive..."
    rclone copy "$RCLONE_REMOTE/termux-backup-latest.tar.gz.gpg" "$BACKUP_DIR" -P
    rclone copy "$RCLONE_REMOTE/pkg_list.txt" "$BACKUP_DIR" -P
    if [ -f "$BACKUP_DIR/termux-backup-latest.tar.gz.gpg" ]; then
        gpg -d --batch --yes --passphrase "$GPG_PASSPHRASE" "$BACKUP_DIR/termux-backup-latest.tar.gz.gpg" > "$RESTORE_FILE"
        mkdir -p "$INCREMENTAL_DIR"
        tar -zxf "$RESTORE_FILE" -C "$INCREMENTAL_DIR" --recursive-unlink --preserve-permissions
        rsync -a "$INCREMENTAL_DIR/" "$TERMUX_HOME/"
        if [ $? -eq 0 ]; then
            echo "Restauração concluída! Reinicie o Termux."
            echo "Lista de pacotes disponível em: $PKG_LIST"
            rm -f "$RESTORE_FILE" "$BACKUP_DIR/termux-backup-latest.tar.gz.gpg"
        else
            echo "Erro ao restaurar!"
            exit 1
        fi
    else
        echo "Arquivo de backup não encontrado!"
        exit 1
    fi
}

# Função para configurar backup automático
setup_auto_backup() {
    echo "Configurando backup automático..."
    crontab -l > mycron 2>/dev/null
    echo "0 * * * * /data/data/com.termux/files/usr/bin/bash $HOME/teracount.sh --auto-backup" >> mycron
    crontab mycron
    rm mycron
    echo "Backup automático configurado para rodar a cada hora."
}

# Menu principal
main_menu() {
    echo "=== Teracount ==="
    echo "1. Fazer backup"
    echo "2. Restaurar backup"
    echo "3. Configurar backup automático"
    echo "4. Sair"
    read -p "Escolha uma opção: " option
    case $option in
        1) create_backup ;;
        2) restore_backup ;;
        3) setup_auto_backup ;;
        4) exit 0 ;;
        *) echo "Opção inválida!" ;;
    esac
}

# Verifica se é um backup automático
if [ "$1" = "--auto-backup" ]; then
    # Para backup automático, requer senha armazenada ou outra lógica
    echo "Backup automático não suporta senha dinâmica. Configure uma senha fixa ou execute manualmente."
    exit 1
fi

# Fluxo principal
setup_account
login
main_menu
