#!/data/data/com.termux/files/usr/bin/bash

# Instala dependências
echo "Instalando dependências..."
pkg install git rsync tar gpg rclone cron -y

# Move para o diretório home
cd ~

# Clona o repositório (se ainda não foi clonado)
if [ ! -d "teracount" ]; then
    git clone https://github.com/gerfunesbr/teracount.git
fi

# Copia e dá permissão ao script teracount.sh
cp teracount/teracount.sh .
chmod +x teracount.sh

# Configura rclone (se necessário)
if ! rclone listremotes | grep -q "gdrive:"; then
    echo "Configure o rclone para acessar o Google Drive."
    rclone config
fi

echo "Instalação concluída! Execute './teracount.sh' para usar."
